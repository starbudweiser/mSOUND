import Foundation
import AVFoundation

/// Pyramide de crêtes (min/max) d'un fichier : zoom fluide et ouverture instantanée, même sur plusieurs heures.
public final class PeakData: @unchecked Sendable {
    public static let baseBlock = 64
    public let url: URL
    public let channels: Int
    public let sampleRate: Double
    public let frames: Int64
    /// levels[niveau][canal] = [min, max, min, max, …] ; un bloc du niveau n couvre baseBlock << n trames.
    private var levels: [[[Float]]] = []
    private let lock = NSLock()
    public private(set) var ready = false

    public init(url: URL) throws {
        self.url = url
        let f = try AVAudioFile(forReading: url)
        channels = Int(f.processingFormat.channelCount)
        sampleRate = f.processingFormat.sampleRate
        frames = f.length
    }

    /// Calcule les crêtes (à appeler hors du thread principal). `progress` : 0…1.
    public func build(progress: ((Double) -> Void)? = nil) throws {
        let f = try AVAudioFile(forReading: url)
        let B = Self.baseBlock
        let chunk = AVAudioFrameCount(B * 1024)
        guard let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: chunk) else { return }
        var l0 = [[Float]](repeating: [], count: channels)
        for c in 0..<channels { l0[c].reserveCapacity(Int(frames) / B * 2 + 4) }
        var done: Int64 = 0
        while done < frames {
            try f.read(into: buf, frameCount: chunk)
            let n = Int(buf.frameLength)
            if n == 0 { break }
            guard let data = buf.floatChannelData else { break }
            for c in 0..<channels {
                let p = data[c]
                var i = 0
                while i < n {
                    let e = min(n, i + B)
                    var mn = p[i], mx = p[i]
                    var k = i + 1
                    while k < e { let v = p[k]; if v < mn { mn = v } else if v > mx { mx = v }; k += 1 }
                    l0[c].append(mn); l0[c].append(mx)
                    i = e
                }
            }
            done += Int64(n)
            progress?(Double(done) / Double(max(frames, 1)))
        }
        var all = [l0]
        while (all.last![0].count / 2) > 2 {
            let prev = all.last!
            var next = [[Float]](repeating: [], count: channels)
            for c in 0..<channels {
                let p = prev[c]; let nb = p.count / 2
                next[c].reserveCapacity((nb / 2 + 1) * 2)
                var i = 0
                while i < nb {
                    var mn = p[2 * i], mx = p[2 * i + 1]
                    if i + 1 < nb { mn = min(mn, p[2 * i + 2]); mx = max(mx, p[2 * i + 3]) }
                    next[c].append(mn); next[c].append(mx); i += 2
                }
            }
            all.append(next)
        }
        lock.lock(); levels = all; ready = true; lock.unlock()
    }

    /// Min/max du canal `c` sur les trames [a, b) du fichier.
    public func minMax(channel c: Int, from a: Int64, to b: Int64) -> (Float, Float) {
        lock.lock(); defer { lock.unlock() }
        guard ready, c < channels, b > a else { return (0, 0) }
        let span = Double(b - a)
        var lvl = 0
        while lvl + 1 < levels.count && Double(Self.baseBlock << (lvl + 1)) <= span { lvl += 1 }
        let bs = Int64(Self.baseBlock << lvl)
        let arr = levels[lvl][min(c, channels - 1)]
        let nb = arr.count / 2
        let i0 = max(0, Int(a / bs)), i1 = min(nb - 1, Int((b - 1) / bs))
        if i1 < i0 { return (0, 0) }
        var mn = Float.greatestFiniteMagnitude, mx = -Float.greatestFiniteMagnitude
        for i in i0...i1 { mn = min(mn, arr[2 * i]); mx = max(mx, arr[2 * i + 1]) }
        return (mn, mx)
    }

    /// Plages silencieuses (début, fin en trames) : crête sous `thresholdDB` pendant au moins `minSeconds`.
    public func silences(thresholdDB: Float = -50, minSeconds: Double = 0.5) -> [(Int64, Int64)] {
        lock.lock(); defer { lock.unlock() }
        guard ready, let l0 = levels.first else { return [] }
        let thr = powf(10, thresholdDB / 20)
        let B = Int64(Self.baseBlock)
        let nb = l0[0].count / 2
        var out: [(Int64, Int64)] = []
        var runStart: Int? = nil
        func close(_ end: Int) {
            if let s = runStart, Double(Int64(end - s) * B) / sampleRate >= minSeconds { out.append((Int64(s) * B, Int64(end) * B)) }
            runStart = nil
        }
        for i in 0..<nb {
            var peak: Float = 0
            for c in 0..<channels { peak = max(peak, abs(l0[c][2 * i]), abs(l0[c][2 * i + 1])) }
            if peak < thr { if runStart == nil { runStart = i } } else { close(i) }
        }
        close(nb)
        return out
    }
}
