import Foundation
import Accelerate

// MARK: - Étage de traitement en flux

/// Un étage traite des trames entrelacées Float32. Il rend toujours autant de trames qu'il en reçoit, avec un retard fixe `latency`.
protocol Stage: AnyObject {
    var latency: Int { get }
    func process(_ x: [Float]) -> [Float]
}

// MARK: - Biquads (cookbook RBJ), états en Double

struct BiquadCoef {
    var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    init(b0: Double, b1: Double, b2: Double, a0: Double, a1: Double, a2: Double) {
        self.b0 = b0 / a0; self.b1 = b1 / a0; self.b2 = b2 / a0; self.a1 = a1 / a0; self.a2 = a2 / a0
    }
    static func highpass(_ f: Double, q: Double, rate: Double) -> BiquadCoef {
        let w = 2 * Double.pi * f / rate, c = cos(w), al = sin(w) / (2 * q)
        return BiquadCoef(b0: (1 + c) / 2, b1: -(1 + c), b2: (1 + c) / 2, a0: 1 + al, a1: -2 * c, a2: 1 - al)
    }
    static func notch(_ f: Double, q: Double, rate: Double) -> BiquadCoef {
        let w = 2 * Double.pi * f / rate, c = cos(w), al = sin(w) / (2 * q)
        return BiquadCoef(b0: 1, b1: -2 * c, b2: 1, a0: 1 + al, a1: -2 * c, a2: 1 - al)
    }
    static func peaking(_ f: Double, gainDB: Double, q: Double, rate: Double) -> BiquadCoef {
        let a = pow(10, gainDB / 40), w = 2 * Double.pi * f / rate, c = cos(w), al = sin(w) / (2 * q)
        return BiquadCoef(b0: 1 + al * a, b1: -2 * c, b2: 1 - al * a, a0: 1 + al / a, a1: -2 * c, a2: 1 - al / a)
    }
    static func lowShelf(_ f: Double, gainDB: Double, q: Double, rate: Double) -> BiquadCoef {
        let a = pow(10, gainDB / 40), w = 2 * Double.pi * f / rate, c = cos(w), al = sin(w) / (2 * q), s = 2 * sqrt(a) * al
        return BiquadCoef(b0: a * ((a + 1) - (a - 1) * c + s), b1: 2 * a * ((a - 1) - (a + 1) * c), b2: a * ((a + 1) - (a - 1) * c - s),
                          a0: (a + 1) + (a - 1) * c + s, a1: -2 * ((a - 1) + (a + 1) * c), a2: (a + 1) + (a - 1) * c - s)
    }
    static func highShelf(_ f: Double, gainDB: Double, q: Double, rate: Double) -> BiquadCoef {
        let a = pow(10, gainDB / 40), w = 2 * Double.pi * f / rate, c = cos(w), al = sin(w) / (2 * q), s = 2 * sqrt(a) * al
        return BiquadCoef(b0: a * ((a + 1) + (a - 1) * c + s), b1: -2 * a * ((a - 1) + (a + 1) * c), b2: a * ((a + 1) + (a - 1) * c - s),
                          a0: (a + 1) - (a - 1) * c + s, a1: 2 * ((a - 1) - (a + 1) * c), a2: (a + 1) - (a - 1) * c - s)
    }
}

/// Cascade de biquads, une copie d'états par canal.
final class BiquadChain: Stage {
    let sections: [BiquadCoef]
    let channels: Int
    private var z: [Double]            // [canal][section][2]
    var latency: Int { 0 }

    init(_ sections: [BiquadCoef], channels: Int) {
        self.sections = sections; self.channels = channels
        z = [Double](repeating: 0, count: channels * sections.count * 2)
    }

    func process(_ x: [Float]) -> [Float] {
        var y = x
        let frames = x.count / channels, ns = sections.count
        y.withUnsafeMutableBufferPointer { buf in
            for c in 0..<channels {
                for s in 0..<ns {
                    let k = sections[s], zi = (c * ns + s) * 2
                    var z1 = z[zi], z2 = z[zi + 1]
                    var i = c
                    for _ in 0..<frames {
                        let v = Double(buf[i])
                        let out = k.b0 * v + z1
                        z1 = k.b1 * v - k.a1 * out + z2
                        z2 = k.b2 * v - k.a2 * out
                        buf[i] = Float(out)
                        i += channels
                    }
                    z[zi] = z1; z[zi + 1] = z2
                }
            }
        }
        return y
    }
}

/// Gain fixe en dB.
final class GainStage: Stage {
    let g: Float
    var latency: Int { 0 }
    init(db: Double) { g = Float(pow(10, db / 20)) }
    func process(_ x: [Float]) -> [Float] { var y = [Float](repeating: 0, count: x.count); vDSP.multiply(g, x, result: &y); return y }
}

// MARK: - Sonie (ITU-R BS.1770-4, pondération K, double porte)

final class LoudnessMeter {
    private let channels: Int
    private var kfilters: [BiquadChain]
    private let hop: Int
    private var hopSum = 0.0, hopCount = 0
    private var hops: [Double] = []
    private var blocks: [Double] = []     // énergie moyenne de chaque bloc de 400 ms (pas de 100 ms)

    init(rate: Double, channels: Int) {
        self.channels = channels
        hop = max(1, Int((rate * 0.1).rounded()))
        let shelf = BiquadCoef.highShelf(1681.974450955533, gainDB: 3.999843853973347, q: 0.7071752369554196, rate: rate)
        let hp = BiquadCoef.highpass(38.13547087602444, q: 0.5003270373238773, rate: rate)
        kfilters = [BiquadChain([shelf, hp], channels: channels)]
    }

    func add(_ x: [Float]) {
        let w = kfilters[0].process(x)
        let frames = w.count / channels
        for f in 0..<frames {
            var s = 0.0
            for c in 0..<channels { let v = Double(w[f * channels + c]); s += v * v }
            hopSum += s; hopCount += 1
            if hopCount == hop {
                hops.append(hopSum / Double(hop)); hopSum = 0; hopCount = 0
                if hops.count >= 4 { let c = hops.count; blocks.append((hops[c - 4] + hops[c - 3] + hops[c - 2] + hops[c - 1]) / 4) }
            }
        }
    }

    /// Sonie intégrée en LUFS ; −∞ s'il n'y a rien d'audible. Un fichier mono est compté comme un double mono (lu sur deux enceintes).
    var integrated: Double {
        let k = channels == 1 ? 2.0 : 1.0
        func lufs(_ e: Double) -> Double { -0.691 + 10 * log10(max(e * k, 1e-20)) }
        let a = blocks.filter { lufs($0) > -70 }
        guard !a.isEmpty else { return -.infinity }
        let rel = lufs(a.reduce(0, +) / Double(a.count)) - 10
        let b = a.filter { lufs($0) > rel }
        guard !b.isEmpty else { return -.infinity }
        return lufs(b.reduce(0, +) / Double(b.count))
    }
}

// MARK: - Limiteur à anticipation (plafond d'échantillon)

final class Limiter: Stage {
    private let channels: Int, n: Int
    private let ceiling: Float
    private let relCoef: Float
    private var delay: [Float]            // n−1 trames de retard
    private var dpos = 0
    private var dqIdx: [Int], dqVal: [Float]
    private var dqHead = 0, dqCount = 0
    private var mRing: [Float], mSum: Double, mPos = 0
    private var j = 0
    private var relState: Float = 1
    var latency: Int { n - 1 }

    init(rate: Double, channels: Int, ceilingDB: Double = -1.0, lookaheadMs: Double = 2.0, releaseMs: Double = 100) {
        self.channels = channels
        n = max(8, Int(rate * lookaheadMs / 1000))
        ceiling = Float(pow(10, ceilingDB / 20))
        relCoef = Float(exp(-1.0 / (rate * releaseMs / 1000)))
        delay = [Float](repeating: 0, count: (n - 1) * channels)
        dqIdx = [Int](repeating: 0, count: n + 1); dqVal = [Float](repeating: 1, count: n + 1)
        mRing = [Float](repeating: 1, count: n); mSum = Double(n)
    }

    func process(_ x: [Float]) -> [Float] {
        let frames = x.count / channels
        var out = [Float](repeating: 0, count: x.count)
        let cap = n + 1
        for f in 0..<frames {
            var pk: Float = 0
            for c in 0..<channels { pk = max(pk, abs(x[f * channels + c])) }
            let need: Float = pk > ceiling ? ceiling / pk : 1
            // minimum glissant sur n trames (file monotone)
            while dqCount > 0 {
                let last = (dqHead + dqCount - 1) % cap
                if dqVal[last] >= need { dqCount -= 1 } else { break }
            }
            let tail = (dqHead + dqCount) % cap
            dqIdx[tail] = j; dqVal[tail] = need; dqCount += 1
            while dqCount > 0 && dqIdx[dqHead] <= j - n { dqHead = (dqHead + 1) % cap; dqCount -= 1 }
            let m = dqVal[dqHead]
            // moyenne glissante sur n minima
            mSum += Double(m) - Double(mRing[mPos]); mRing[mPos] = m; mPos = (mPos + 1) % n
            let avg = Float(mSum / Double(n))
            relState = avg < relState ? avg : relState + (avg - relState) * (1 - relCoef)
            let g = min(relState, avg)
            // trame retardée de n−1
            for c in 0..<channels {
                let di = dpos * channels + c
                let d = n > 1 ? delay[di] : x[f * channels + c]
                if n > 1 { delay[di] = x[f * channels + c] }
                out[f * channels + c] = d * g
            }
            dpos = (dpos + 1) % max(n - 1, 1)
            j += 1
        }
        return out
    }
}

// MARK: - Compresseur (détection de crête liée, genou doux, lissage en dB)

struct CompressorSettings {
    var thresholdDB: Double, ratio: Double, kneeDB: Double, attackMs: Double, releaseMs: Double
}

final class Compressor: Stage {
    private let channels: Int
    private let s: CompressorSettings
    private let att: Double, rel: Double
    private var g = 0.0                    // réduction lissée (dB, ≤ 0)
    var latency: Int { 0 }

    init(rate: Double, channels: Int, settings: CompressorSettings) {
        self.channels = channels; s = settings
        att = exp(-1.0 / (rate * settings.attackMs / 1000)); rel = exp(-1.0 / (rate * settings.releaseMs / 1000))
    }

    func process(_ x: [Float]) -> [Float] {
        var y = x
        let frames = x.count / channels
        let t = s.thresholdDB, k = s.kneeDB, r = s.ratio
        for f in 0..<frames {
            var pk: Float = 0
            for c in 0..<channels { pk = max(pk, abs(x[f * channels + c])) }
            let l = 20 * log10(Double(max(pk, 1e-6)))
            let over = l - t
            var target = 0.0
            if 2 * over < -k { target = 0 }
            else if 2 * abs(over) <= k { target = (1 / r - 1) * pow(over + k / 2, 2) / (2 * k) }
            else { target = (1 / r - 1) * over }
            g = target < g ? att * g + (1 - att) * target : rel * g + (1 - rel) * target
            let lin = Float(pow(10, g / 20))
            for c in 0..<channels { y[f * channels + c] *= lin }
        }
        return y
    }
}

// MARK: - Débruiteur spectral (soustraction pondérée, lissage temps et fréquence)

final class SpectralDenoiser: Stage {
    static let n = 2048, hop = 512
    private let channels: Int
    private let profile: [[Float]]         // module du bruit par canal et par bin (n/2+1)
    private let alpha: Float, gmin: Float
    private var chans: [Chan]
    private var queue: [[Float]]           // sorties en attente, par canal
    var latency: Int { Self.n }

    private final class Chan {
        var fifo = [Float](repeating: 0, count: SpectralDenoiser.n)
        var pushed = 0
        var acc = [Float](repeating: 0, count: SpectralDenoiser.n)
        var gPrev: [Float]
        let re = UnsafeMutablePointer<Float>.allocate(capacity: SpectralDenoiser.n)
        let im = UnsafeMutablePointer<Float>.allocate(capacity: SpectralDenoiser.n)
        init() { gPrev = [Float](repeating: 1, count: SpectralDenoiser.n / 2 + 1) }
        deinit { re.deallocate(); im.deallocate() }
    }
    private static let window: [Float] = (0..<n).map { 0.5 - 0.5 * Float(cos(2 * Double.pi * Double($0) / Double(n))) }
    private static let setup = vDSP_create_fftsetup(vDSP_Length(log2(Double(n))), FFTRadix(kFFTRadix2))!

    init(channels: Int, profile: [[Float]], alpha: Float, floorDB: Float) {
        self.channels = channels; self.profile = profile; self.alpha = alpha
        gmin = powf(10, floorDB / 20)
        chans = (0..<channels).map { _ in Chan() }
        queue = [[Float]](repeating: [Float](repeating: 0, count: Self.hop), count: channels)   // retard de calage (voir latency)
        for (i, c) in chans.enumerated() { push(zeros: Self.n - Self.hop, into: c, ch: i, emit: false) }
    }

    private func push(zeros: Int, into c: Chan, ch: Int, emit: Bool) {
        for _ in 0..<zeros { feed(0, c, ch) }
    }

    /// Ajoute un échantillon ; à chaque pas de `hop` après le premier remplissage, calcule une trame et empile `hop` sorties.
    private func feed(_ v: Float, _ c: Chan, _ ch: Int) {
        let n = Self.n, hop = Self.hop
        c.fifo[c.pushed % n] = v
        c.pushed += 1
        guard c.pushed >= n, (c.pushed - n) % hop == 0 else { return }
        // trame : les n derniers échantillons dans l'ordre
        let start = c.pushed % n
        for i in 0..<n { c.re[i] = c.fifo[(start + i) % n] * Self.window[i]; c.im[i] = 0 }
        var split = DSPSplitComplex(realp: c.re, imagp: c.im)
        let l2 = vDSP_Length(log2(Double(n)))
        vDSP_fft_zip(Self.setup, &split, 1, l2, FFTDirection(kFFTDirection_Forward))
        let half = n / 2
        var gains = [Float](repeating: 1, count: half + 1)
        let noise = profile[ch]
        for k in 0...half {
            let mag = sqrtf(c.re[k] * c.re[k] + c.im[k] * c.im[k]) + 1e-12
            gains[k] = max(gmin, 1 - alpha * noise[k] / mag)
        }
        var sm = gains
        for k in 1..<half { sm[k] = 0.25 * gains[k - 1] + 0.5 * gains[k] + 0.25 * gains[k + 1] }
        for k in 0...half {
            // ouverture immédiate (préserve les attaques), fermeture lissée (évite le bruit « musical »)
            let gp = c.gPrev[k]
            let g = sm[k] > gp ? sm[k] : 0.7 * gp + 0.3 * sm[k]
            c.gPrev[k] = g
            c.re[k] *= g; c.im[k] *= g
            if k > 0 && k < half { c.re[n - k] *= g; c.im[n - k] *= g }
        }
        vDSP_fft_zip(Self.setup, &split, 1, l2, FFTDirection(kFFTDirection_Inverse))
        let scale = 1 / (Float(n) * 1.5)           // FFT inverse non normalisée ; somme des fenêtres² = 1,5 pour un recouvrement de 75 %
        for i in 0..<n { c.acc[i] += c.re[i] * Self.window[i] * scale }
        queue[ch].append(contentsOf: c.acc[0..<hop])
        c.acc.removeSubrange(0..<hop); c.acc.append(contentsOf: [Float](repeating: 0, count: hop))
    }

    func process(_ x: [Float]) -> [Float] {
        let frames = x.count / channels
        for f in 0..<frames { for ch in 0..<channels { feed(x[f * channels + ch], chans[ch], ch) } }
        var out = [Float](repeating: 0, count: x.count)
        for ch in 0..<channels {
            for f in 0..<frames { out[f * channels + ch] = queue[ch][f] }
            queue[ch].removeFirst(frames)
        }
        return out
    }

    /// Profil de bruit : module moyen des trames les plus calmes (12 % les plus faibles).
    final class Profiler {
        let channels: Int
        private var bufs: [[Float]]
        private var energies: [Double] = []
        private var threshold = 0.0
        private(set) var sums: [[Float]]
        private(set) var count = 0
        private var frameIndex = 0
        var phase = 0                       // 0 = énergies, 1 = modules
        init(channels: Int) {
            self.channels = channels
            bufs = [[Float]](repeating: [], count: channels)
            sums = [[Float]](repeating: [Float](repeating: 0, count: SpectralDenoiser.n / 2 + 1), count: channels)
        }
        func startPhase2() {
            let ok = energies.filter { $0 > 1e-10 }.sorted()
            threshold = ok.isEmpty ? -1 : ok[max(0, min(ok.count - 1, Int(Double(ok.count) * 0.12)))]
            bufs = [[Float]](repeating: [], count: channels); frameIndex = 0; phase = 1
        }
        func add(_ x: [Float]) {
            let n = SpectralDenoiser.n, hop = SpectralDenoiser.hop
            let frames = x.count / channels
            for ch in 0..<channels { for f in 0..<frames { bufs[ch].append(x[f * channels + ch]) } }
            while bufs[0].count >= n {
                if phase == 0 {
                    var e = 0.0
                    for ch in 0..<channels { var s: Float = 0; vDSP_svesq(bufs[ch], 1, &s, vDSP_Length(n)); e += Double(s) / Double(n) }
                    energies.append(e / Double(channels))
                } else {
                    let e = energies[min(frameIndex, energies.count - 1)]
                    if e > 1e-10 && e <= threshold { accumulate() }
                    frameIndex += 1
                }
                for ch in 0..<channels { bufs[ch].removeFirst(hop) }
            }
        }
        private func accumulate() {
            let n = SpectralDenoiser.n, half = n / 2
            for ch in 0..<channels {
                let re = UnsafeMutablePointer<Float>.allocate(capacity: n), im = UnsafeMutablePointer<Float>.allocate(capacity: n)
                defer { re.deallocate(); im.deallocate() }
                for i in 0..<n { re[i] = bufs[ch][i] * SpectralDenoiser.window[i]; im[i] = 0 }
                var split = DSPSplitComplex(realp: re, imagp: im)
                vDSP_fft_zip(SpectralDenoiser.setup, &split, 1, vDSP_Length(log2(Double(n))), FFTDirection(kFFTDirection_Forward))
                for k in 0...half { sums[ch][k] += sqrtf(re[k] * re[k] + im[k] * im[k]) }
            }
            count += 1
        }
        /// Profil moyen lissé sur 5 bins ; nil si aucune trame exploitable.
        var profile: [[Float]]? {
            guard count > 0 else { return nil }
            return sums.map { s in
                let m = s.map { $0 / Float(count) }
                return (0..<m.count).map { k in
                    var a: Float = 0, c: Float = 0
                    for d in -2...2 where k + d >= 0 && k + d < m.count { a += m[k + d]; c += 1 }
                    return a / c
                }
            }
        }
    }
}

// MARK: - Détection du ronflement secteur (50 / 60 Hz)

final class HumDetector {
    private let rate: Double
    private let freqs: [Double] = [50, 60, 44, 47, 53, 56, 64, 67]
    private var acc = [Double](repeating: 0, count: 8)
    private var blocks = 0
    private var re = [Double](repeating: 0, count: 8), im = [Double](repeating: 0, count: 8)
    private var rot: [(Double, Double)]
    private var cur = [(Double, Double)](repeating: (1, 0), count: 8)
    private var n = 0
    private let blockLen: Int

    init(rate: Double) {
        self.rate = rate; blockLen = Int(rate)
        rot = freqs.map { (cos(2 * Double.pi * $0 / rate), -sin(2 * Double.pi * $0 / rate)) }
    }

    func add(_ x: [Float], channels: Int) {
        let frames = x.count / channels
        for f in 0..<frames {
            var v = 0.0
            for c in 0..<channels { v += Double(x[f * channels + c]) }
            v /= Double(channels)
            for i in 0..<8 {
                re[i] += v * cur[i].0; im[i] += v * cur[i].1
                let (cr, ci) = cur[i], (rr, ri) = rot[i]
                cur[i] = (cr * rr - ci * ri, cr * ri + ci * rr)
            }
            n += 1
            if n == blockLen {
                for i in 0..<8 { acc[i] += (re[i] * re[i] + im[i] * im[i]) / Double(n * n) }
                blocks += 1; n = 0
                re = [Double](repeating: 0, count: 8); im = re; cur = [(Double, Double)](repeating: (1, 0), count: 8)
            }
        }
    }

    /// 50 ou 60 si une raie de ronflement dépasse nettement le fond voisin (≥ 9 dB), sinon nil.
    var detected: Double? {
        guard blocks > 0 else { return nil }
        let p = acc.map { $0 / Double(blocks) }
        let r50 = p[0] / max((p[2] + p[3] + p[4] + p[5]) / 4, 1e-20)
        let r60 = p[1] / max((p[4] + p[5] + p[6] + p[7]) / 4, 1e-20)
        let best = max(r50, r60)
        guard best > 8, p[0] + p[1] > 1e-10 else { return nil }
        return r50 >= r60 ? 50 : 60
    }
}
