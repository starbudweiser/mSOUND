import Foundation
import AudioToolbox

// MARK: - La carte : peu de filtres, bien réglés

public enum Strength: String, CaseIterable, Sendable { case light, medium, strong }
public enum EQPreset: String, CaseIterable, Sendable { case voice, warm, bright }
public enum CompPreset: String, CaseIterable, Sendable { case soft, studio, radio }

public enum FilterStep: Sendable, Equatable {
    case clean(highpassHz: Double)        // coupe-bas + ronflement secteur détecté
    case denoise(Strength)                // débruiteur spectral
    case eq(EQPreset)                     // égalisation de voix
    case compress(CompPreset)             // compresseur, niveau perçu conservé
    case loudness(Double)                 // sonie cible (LUFS) + limiteur à −1 dB

    /// Nombre de lectures du fichier (sert à la jauge de progression).
    var passes: Int {
        switch self {
        case .clean: return 2
        case .denoise: return 3
        case .eq: return 1
        case .compress: return 3
        case .loudness: return 2
        }
    }
}

/// Préconfigurations prêtes à l'emploi : chaînes de filtres réglées pour un type de source.
public enum Recipe: String, CaseIterable, Sendable {
    case voicePro        // voix propre, studio ou bureau calme → podcast, vidéo
    case noisyInterview  // interview, terrain, pièce qui résonne
    case warmNarration   // voix off, narration, livre audio
    case instrument      // instrument, échantillon, boucle

    public var steps: [FilterStep] {
        switch self {
        case .voicePro: return [.clean(highpassHz: 80), .denoise(.light), .eq(.voice), .compress(.studio), .loudness(-16)]
        case .noisyInterview: return [.clean(highpassHz: 90), .denoise(.strong), .eq(.voice), .compress(.radio), .loudness(-16)]
        case .warmNarration: return [.clean(highpassHz: 70), .denoise(.light), .eq(.warm), .compress(.soft), .loudness(-18)]
        case .instrument: return [.clean(highpassHz: 30), .denoise(.light), .compress(.soft), .loudness(-14)]
        }
    }
}

public enum FilterError: Error { case silent }

// MARK: - Rendu

public enum Filters {
    public static var cacheDir: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("mSOUND/Render", isDirectory: true)
    }

    /// Supprime les rendus de plus de 3 jours.
    public static func cleanCache() {
        let fm = FileManager.default
        guard let list = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for u in list {
            let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantFuture
            if Date().timeIntervalSince(d) > 3 * 86400 { try? fm.removeItem(at: u) }
        }
    }

    /// Applique la chaîne aux segments ; écrit un WAV Float32 de même durée dans le cache. Les originaux ne sont jamais modifiés.
    public static func apply(_ steps: [FilterStep], to clips: [Clip], token: CancelToken? = nil,
                             progress: ((Double) -> Void)? = nil) throws -> (url: URL, frames: Int64) {
        let job = try Job(clips: clips, token: token, progress: progress, total: steps.reduce(0) { $0 + $1.passes })
        for s in steps { try job.run(s) }
        guard let out = job.lastTemp else { throw FilterError.silent }
        return (out, job.frames)
    }

    /// Sonie intégrée (LUFS) d'un fichier ou d'un montage.
    public static func loudness(of clips: [Clip]) throws -> Double {
        let job = try Job(clips: clips, token: nil, progress: nil, total: 1)
        let m = LoudnessMeter(rate: job.rate, channels: job.channels)
        try job.pass([], write: nil) { m.add($0) }
        return m.integrated
    }

    // MARK: Travail interne

    final class Job {
        let rate: Double, channels: Int
        let frames: Int64
        let token: CancelToken?
        private var current: [Clip]
        private var infos: [URL: Converter.SourceInfo] = [:]
        private(set) var lastTemp: URL?
        private let progress: ((Double) -> Void)?
        private let total: Double
        private var doneUnits = 0.0

        init(clips: [Clip], token: CancelToken?, progress: ((Double) -> Void)?, total: Int) throws {
            guard let first = clips.first else { throw ConvertError.unreadable("") }
            let i0 = try Converter.info(of: first.source)
            rate = i0.sampleRate; channels = Int(i0.channels)
            current = clips; self.token = token; self.progress = progress; self.total = Double(max(total, 1))
            for c in clips where infos[c.source] == nil { infos[c.source] = try Converter.info(of: c.source) }
            frames = ClipReader(clips: clips, infos: infos, outRate: rate, channels: UInt32(channels)).totalOutFrames
        }

        private func newTemp() throws -> URL {
            try FileManager.default.createDirectory(at: Filters.cacheDir, withIntermediateDirectories: true)
            return Filters.cacheDir.appendingPathComponent("\(UUID().uuidString).wav")
        }

        /// Une lecture complète de `current` à travers `stages`. `write` : fichier de sortie ; `observe` : voit la sortie.
        @discardableResult
        func pass(_ stages: [Stage], write: URL?, observe: (([Float]) -> Void)? = nil) throws -> Void {
            let reader = ClipReader(clips: current, infos: infos, outRate: rate, channels: UInt32(channels))
            let writer = try write.map { try FloatWriter(url: $0, rate: rate, channels: channels) }
            let latency = stages.reduce(0) { $0 + $1.latency }
            var toDrop = latency, remaining = frames
            let chunk: UInt32 = 32768
            let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(chunk) * channels * 4, alignment: 16)
            defer { raw.deallocate() }

            func emit(_ out: [Float]) throws {
                var a = out
                var n = a.count / channels
                if toDrop > 0 { let d = min(toDrop, n); a.removeFirst(d * channels); toDrop -= d; n -= d }
                if Int64(n) > remaining { a.removeLast((n - Int(remaining)) * channels); n = Int(remaining) }
                guard n > 0 else { return }
                observe?(a); try writer?.write(a); remaining -= Int64(n)
            }
            var read: Int64 = 0
            while true {
                if Task.isCancelled || token?.isCancelled == true { throw ConvertError.cancelled }
                let n = try reader.read(into: raw, maxFrames: chunk)
                if n == 0 { break }
                var x = Array(UnsafeBufferPointer(start: raw.assumingMemoryBound(to: Float.self), count: Int(n) * channels))
                for s in stages { x = s.process(x) }
                try emit(x)
                read += Int64(n)
                progress?((doneUnits + Double(read) / Double(max(frames, 1))) / total)
            }
            if latency > 0 {
                var x = [Float](repeating: 0, count: latency * channels)
                for s in stages { x = s.process(x) }
                try emit(x)
            }
            writer?.close()
            doneUnits += 1
            progress?(doneUnits / total)
        }

        private func skip(_ units: Int) { doneUnits += Double(units); progress?(doneUnits / total) }

        /// Remplace l'entrée courante par le fichier écrit (et supprime le rendu intermédiaire précédent).
        private func adopt(_ url: URL) throws {
            if let old = lastTemp { try? FileManager.default.removeItem(at: old) }
            lastTemp = url
            infos[url] = try Converter.info(of: url)
            current = [Clip(source: url, start: 0, length: frames)]
        }

        private func render(_ stages: [Stage], observe: (([Float]) -> Void)? = nil) throws {
            let out = try newTemp()
            do { try pass(stages, write: out, observe: observe) } catch { try? FileManager.default.removeItem(at: out); throw error }
            try adopt(out)
        }

        private func measure() throws -> Double {
            let m = LoudnessMeter(rate: rate, channels: channels)
            try pass([], write: nil) { m.add($0) }
            return m.integrated
        }

        func run(_ step: FilterStep) throws {
            switch step {
            case .clean(let hp):
                let h = HumDetector(rate: rate)
                try pass([], write: nil) { h.add($0, channels: self.channels) }
                var sections = [BiquadCoef.highpass(hp, q: 0.7071, rate: rate), BiquadCoef.highpass(hp, q: 0.7071, rate: rate)]
                if let f = h.detected {
                    for k in 1...4 where f * Double(k) < rate / 2 - 500 { sections.append(.notch(f * Double(k), q: 35, rate: rate)) }
                }
                try render([BiquadChain(sections, channels: channels)])

            case .denoise(let st):
                let prof = SpectralDenoiser.Profiler(channels: channels)
                try pass([], write: nil) { prof.add($0) }
                prof.startPhase2()
                try pass([], write: nil) { prof.add($0) }
                guard let profile = prof.profile else { skip(1); return }
                let (alpha, floorDB): (Float, Float) = { switch st { case .light: return (1.2, -9); case .medium: return (1.8, -15); case .strong: return (2.5, -22) } }()
                try render([SpectralDenoiser(channels: channels, profile: profile, alpha: alpha, floorDB: floorDB)])

            case .eq(let p):
                var s: [BiquadCoef]
                switch p {
                case .voice:
                    s = [.highpass(70, q: 0.7071, rate: rate), .peaking(250, gainDB: -2.5, q: 1.0, rate: rate),
                         .peaking(3200, gainDB: 2.5, q: 0.9, rate: rate), .highShelf(10000, gainDB: 2.0, q: 0.7, rate: rate)]
                case .warm:
                    s = [.lowShelf(160, gainDB: 2.5, q: 0.7, rate: rate), .peaking(3000, gainDB: -1.5, q: 0.8, rate: rate),
                         .highShelf(9000, gainDB: -1.5, q: 0.7, rate: rate)]
                case .bright:
                    s = [.peaking(300, gainDB: -1.0, q: 1.0, rate: rate), .peaking(4000, gainDB: 1.5, q: 0.9, rate: rate),
                         .highShelf(6500, gainDB: 3.0, q: 0.7, rate: rate)]
                }
                try render([BiquadChain(s, channels: channels), Limiter(rate: rate, channels: channels)])

            case .compress(let p):
                let before = try measure()
                guard before.isFinite else { skip(2); return }
                let (ratio, knee, att, rel, off): (Double, Double, Double, Double, Double) = {
                    switch p {
                    case .soft: return (2, 8, 30, 250, 3)
                    case .studio: return (3, 6, 15, 160, 0)
                    case .radio: return (5, 4, 8, 100, -3)
                    }
                }()
                let st = CompressorSettings(thresholdDB: min(-6, max(-60, before + off)), ratio: ratio, kneeDB: knee, attackMs: att, releaseMs: rel)
                let after = LoudnessMeter(rate: rate, channels: channels)
                try render([Compressor(rate: rate, channels: channels, settings: st)]) { after.add($0) }
                let delta = max(-12, min(12, before - after.integrated))
                try render([GainStage(db: delta.isFinite ? delta : 0), Limiter(rate: rate, channels: channels)])

            case .loudness(let target):
                let l = try measure()
                guard l.isFinite else { skip(1); return }
                try render([GainStage(db: target - l), Limiter(rate: rate, channels: channels)])
            }
        }
    }
}

// MARK: - Écriture WAV Float32

final class FloatWriter {
    private var file: ExtAudioFileRef?
    private let channels: Int

    init(url: URL, rate: Double, channels: Int) throws {
        self.channels = channels
        var asbd = AudioStreamBasicDescription(mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: UInt32(4 * channels), mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(4 * channels), mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32, mReserved: 0)
        guard ExtAudioFileCreateWithURL(url as CFURL, kAudioFileWAVEType, &asbd, nil, AudioFileFlags.eraseFile.rawValue, &file) == noErr,
              file != nil else { throw ConvertError.encoderFailed("création du rendu") }
        var client = asbd
        ExtAudioFileSetProperty(file!, kExtAudioFileProperty_ClientDataFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &client)
    }

    func write(_ x: [Float]) throws {
        guard let f = file, !x.isEmpty else { return }
        var copy = x
        let frames = UInt32(x.count / channels)
        let st: OSStatus = copy.withUnsafeMutableBytes { p in
            var abl = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: UInt32(channels), mDataByteSize: UInt32(p.count), mData: p.baseAddress))
            return ExtAudioFileWrite(f, frames, &abl)
        }
        if st != noErr { throw ConvertError.encoderFailed("écriture du rendu (\(st))") }
    }

    func close() { if let f = file { ExtAudioFileDispose(f); file = nil } }
    deinit { close() }
}
