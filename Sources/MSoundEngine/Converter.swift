import Foundation
import AudioToolbox
import CLame

/// Conversion et découpe de fichiers audio (ExtAudioFile + LAME pour le MP3).
public struct Converter {
    public init() {}

    public struct SourceInfo: Sendable {
        public let sampleRate: Double
        public let channels: UInt32
        public let bitDepth: UInt32
        public let frames: Int64
        public var duration: Double { sampleRate > 0 ? Double(frames) / sampleRate : 0 }
    }

    public static func info(of url: URL) throws -> SourceInfo {
        var f: ExtAudioFileRef?
        guard ExtAudioFileOpenURL(url as CFURL, &f) == noErr, let file = f else {
            throw ConvertError.unreadable(url.lastPathComponent)
        }
        defer { ExtAudioFileDispose(file) }
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileDataFormat, &size, &asbd)
        var frames: Int64 = 0
        size = UInt32(MemoryLayout<Int64>.size)
        ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileLengthFrames, &size, &frames)
        let bits = asbd.mBitsPerChannel > 0 ? asbd.mBitsPerChannel : 16
        return SourceInfo(sampleRate: asbd.mSampleRate, channels: asbd.mChannelsPerFrame, bitDepth: bits, frames: frames)
    }

    /// Convertit `source` vers `format`. Retourne l'URL du fichier créé (jamais d'écrasement).
    @discardableResult
    public func convert(_ source: URL, to format: AudioFormat, options: ConvertOptions = ConvertOptions(),
                        progress: ((Double) -> Void)? = nil) throws -> URL {
        let info = try Converter.info(of: source)
        if source.pathExtension.lowercased() == format.fileExtension,
           format != .alac, format != .m4a, options.range == nil, options.sampleRate == nil {
            throw ConvertError.sameFormat
        }
        var start: Int64 = 0, length = info.frames
        if let r = options.range {
            start = Int64(max(0, r.lowerBound) * info.sampleRate)
            let end = min(info.frames, Int64(r.upperBound * info.sampleRate))
            length = max(0, end - start)
        }
        let dir = options.outputDirectory ?? source.deletingLastPathComponent()
        return try export([Clip(source: source, start: start, length: length)], to: format, options: options,
                          baseName: source.deletingPathExtension().lastPathComponent, directory: dir, progress: progress)
    }

    /// Exporte une suite de segments (montage) dans un seul fichier. Les fréquences peuvent différer d'un segment à l'autre.
    @discardableResult
    public func export(_ clips: [Clip], to format: AudioFormat, options: ConvertOptions = ConvertOptions(),
                       baseName: String, directory dir: URL, progress: ((Double) -> Void)? = nil) throws -> URL {
        guard let first = clips.first else { throw ConvertError.unreadable(baseName) }
        var infos: [URL: SourceInfo] = [:]
        for c in clips where infos[c.source] == nil { infos[c.source] = try Converter.info(of: c.source) }
        let fi = infos[first.source]!
        let channels = format == .mp3 ? min(max(fi.channels, 1), 2) : max(fi.channels, 1)
        var outRate = options.sampleRate ?? fi.sampleRate
        if format == .mp3 { outRate = Converter.mp3Rate(outRate) }
        let bits: UInt32 = fi.bitDepth >= 24 ? 24 : 16
        let reader = ClipReader(clips: clips, infos: infos, outRate: outRate, channels: channels)
        let total = reader.totalOutFrames

        let ext = format.fileExtension
        let temp = dir.appendingPathComponent(".\(baseName).\(UUID().uuidString.prefix(8)).partial.\(ext)")
        var final = temp
        try? FileManager.default.removeItem(at: temp)
        do {
            if format == .mp3 {
                try encodeMP3(reader: reader, to: temp, rate: outRate, channels: channels, frames: total,
                              kbps: options.bitrateKbps, token: options.cancelToken, progress: progress)
            } else {
                try encodeNative(reader: reader, to: temp, format: format, rate: outRate, channels: channels, bits: bits,
                                 frames: total, kbps: options.bitrateKbps, token: options.cancelToken, progress: progress)
            }
            // Déplacement sans écrasement ; en cas de course entre deux tâches, on cherche le nom libre suivant.
            var placed = false
            for _ in 0..<100 {
                final = Converter.uniqueURL(dir: dir, base: baseName, ext: ext)
                do { try FileManager.default.moveItem(at: temp, to: final); placed = true; break }
                catch CocoaError.fileWriteFileExists { continue }
                catch let e as NSError where e.code == NSFileWriteFileExistsError { continue }
            }
            if !placed { throw ConvertError.encoderFailed("nom de fichier indisponible") }
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
        return final
    }

    // MARK: - Encodeurs

    private func encodeNative(reader: ClipReader, to url: URL, format: AudioFormat, rate: Double, channels: UInt32, bits: UInt32,
                              frames: Int64, kbps: Int, token: CancelToken?, progress: ((Double) -> Void)?) throws {
        var out = Converter.outputASBD(format, rate: rate, channels: channels, bits: bits)
        var dstRef: ExtAudioFileRef?
        try check(ExtAudioFileCreateWithURL(url as CFURL, Converter.fileType(format), &out, nil,
                                            AudioFileFlags.eraseFile.rawValue, &dstRef), "création du fichier")
        guard let dst = dstRef else { throw ConvertError.encoderFailed("création") }
        defer { ExtAudioFileDispose(dst) }
        var client = reader.clientFormat
        try check(ExtAudioFileSetProperty(dst, kExtAudioFileProperty_ClientDataFormat,
                                          UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &client), "format client (sortie)")

        if format == .m4a {
            var conv: AudioConverterRef?
            var size = UInt32(MemoryLayout<AudioConverterRef?>.size)
            if ExtAudioFileGetProperty(dst, kExtAudioFileProperty_AudioConverter, &size, &conv) == noErr, let c = conv {
                var br = UInt32(min(kbps * 1000, 160_000 * Int(channels)))
                AudioConverterSetProperty(c, kAudioConverterEncodeBitRate, UInt32(MemoryLayout<UInt32>.size), &br)
                var cfg: CFArray? = nil
                ExtAudioFileSetProperty(dst, kExtAudioFileProperty_ConverterConfig, UInt32(MemoryLayout<CFArray?>.size), &cfg)
            }
        }

        let chunk: UInt32 = 16384
        let bytes = Int(chunk) * Int(channels) * 4
        let raw = UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: 16)
        defer { raw.deallocate() }
        var done: Int64 = 0
        while true {
            if Task.isCancelled || token?.isCancelled == true { throw ConvertError.cancelled }
            let n = try reader.read(into: raw, maxFrames: chunk)
            if n == 0 { break }
            var abl = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: channels, mDataByteSize: n * channels * 4, mData: raw))
            try check(ExtAudioFileWrite(dst, n, &abl), "écriture")
            done += Int64(n)
            progress?(Double(done) / Double(max(frames, 1)))
        }
    }

    private func encodeMP3(reader: ClipReader, to url: URL, rate: Double, channels: UInt32, frames: Int64, kbps: Int,
                           token: CancelToken?, progress: ((Double) -> Void)?) throws {
        guard let g = lame_init() else { throw ConvertError.encoderFailed("LAME") }
        defer { lame_close(g) }
        lame_set_in_samplerate(g, Int32(rate))
        lame_set_out_samplerate(g, Int32(rate))
        lame_set_num_channels(g, Int32(channels))
        lame_set_mode(g, channels == 1 ? MONO : JOINT_STEREO)
        lame_set_brate(g, Int32(kbps))
        lame_set_VBR(g, vbr_off)
        lame_set_quality(g, 2)
        guard lame_init_params(g) >= 0 else { throw ConvertError.encoderFailed("paramètres LAME") }

        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let fh = try? FileHandle(forWritingTo: url) else { throw ConvertError.encoderFailed("écriture") }
        defer { try? fh.close() }

        let chunk: UInt32 = 16384
        let bytes = Int(chunk) * Int(channels) * 4
        let raw = UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: 16)
        defer { raw.deallocate() }
        let mp3Size = Int(Double(chunk) * 1.25) + 7200
        let mp3 = UnsafeMutablePointer<UInt8>.allocate(capacity: mp3Size)
        defer { mp3.deallocate() }

        var done: Int64 = 0
        while true {
            if Task.isCancelled || token?.isCancelled == true { throw ConvertError.cancelled }
            let n = try reader.read(into: raw, maxFrames: chunk)
            if n == 0 { break }
            let p = raw.assumingMemoryBound(to: Float.self)
            let w: Int32
            if channels == 1 {
                w = lame_encode_buffer_ieee_float(g, p, nil, Int32(n), mp3, Int32(mp3Size))
            } else {
                w = lame_encode_buffer_interleaved_ieee_float(g, UnsafeMutablePointer(mutating: p), Int32(n), mp3, Int32(mp3Size))
            }
            if w < 0 { throw ConvertError.encoderFailed("LAME \(w)") }
            if w > 0 { fh.write(Data(bytes: mp3, count: Int(w))) }
            done += Int64(n)
            progress?(Double(done) / Double(max(frames, 1)))
        }
        let tail = lame_encode_flush(g, mp3, Int32(mp3Size))
        if tail > 0 { fh.write(Data(bytes: mp3, count: Int(tail))) }
    }

    // MARK: - Utilitaires

    static func fileType(_ f: AudioFormat) -> AudioFileTypeID {
        switch f {
        case .wav: return kAudioFileWAVEType
        case .aiff: return kAudioFileAIFFType
        case .flac: return kAudioFileFLACType
        case .m4a, .alac: return kAudioFileM4AType
        case .mp3: return kAudioFileMP3Type
        }
    }

    static func outputASBD(_ f: AudioFormat, rate: Double, channels: UInt32, bits: UInt32) -> AudioStreamBasicDescription {
        var a = AudioStreamBasicDescription()
        a.mSampleRate = rate
        a.mChannelsPerFrame = channels
        switch f {
        case .wav, .aiff:
            a.mFormatID = kAudioFormatLinearPCM
            a.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
                | (f == .aiff ? kAudioFormatFlagIsBigEndian : 0)
            a.mBitsPerChannel = bits
            a.mBytesPerFrame = channels * bits / 8
            a.mBytesPerPacket = a.mBytesPerFrame
            a.mFramesPerPacket = 1
        case .m4a:
            a.mFormatID = kAudioFormatMPEG4AAC
        case .alac:
            a.mFormatID = kAudioFormatAppleLossless
            a.mFormatFlags = bits >= 24 ? 3 : 1
        case .flac:
            a.mFormatID = kAudioFormatFLAC
            a.mFormatFlags = bits >= 24 ? 3 : 1
        case .mp3:
            a.mFormatID = kAudioFormatMPEGLayer3
        }
        return a
    }

    static func mp3Rate(_ r: Double) -> Double {
        let allowed: [Double] = [48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000]
        return allowed.first(where: { $0 <= r }) ?? 8000
    }

    static func uniqueURL(dir: URL, base: String, ext: String) -> URL {
        var url = dir.appendingPathComponent("\(base).\(ext)")
        var i = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(base) \(i).\(ext)")
            i += 1
        }
        return url
    }

    private func check(_ status: OSStatus, _ what: String) throws {
        if status != noErr { throw ConvertError.encoderFailed("\(what) (\(status))") }
    }
}

/// Lecture continue d'une suite de segments, convertis en Float32 entrelacé à la fréquence de sortie.
final class ClipReader {
    let clips: [Clip]
    let infos: [URL: Converter.SourceInfo]
    let outRate: Double
    let channels: UInt32
    private var idx = 0
    private var cur: ExtAudioFileRef?
    private var remaining: Int64 = 0

    init(clips: [Clip], infos: [URL: Converter.SourceInfo], outRate: Double, channels: UInt32) {
        self.clips = clips; self.infos = infos; self.outRate = outRate; self.channels = channels
    }
    deinit { close() }

    var clientFormat: AudioStreamBasicDescription {
        AudioStreamBasicDescription(
            mSampleRate: outRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4 * channels, mFramesPerPacket: 1, mBytesPerFrame: 4 * channels,
            mChannelsPerFrame: channels, mBitsPerChannel: 32, mReserved: 0)
    }

    private func outFrames(_ c: Clip) -> Int64 {
        Int64((Double(c.length) * outRate / max(infos[c.source]?.sampleRate ?? outRate, 1)).rounded())
    }
    var totalOutFrames: Int64 { clips.reduce(0) { $0 + outFrames($1) } }

    private func close() { if let c = cur { ExtAudioFileDispose(c); cur = nil } }

    private func open(_ i: Int) throws {
        close()
        let c = clips[i]
        var f: ExtAudioFileRef?
        guard ExtAudioFileOpenURL(c.source as CFURL, &f) == noErr, let file = f else {
            throw ConvertError.unreadable(c.source.lastPathComponent)
        }
        var client = clientFormat
        guard ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat,
                                      UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &client) == noErr else {
            ExtAudioFileDispose(file); throw ConvertError.encoderFailed("format client")
        }
        if c.start > 0 { ExtAudioFileSeek(file, c.start) }
        cur = file
        remaining = outFrames(c)
    }

    /// Lit jusqu'à `maxFrames` trames ; retourne 0 à la fin.
    func read(into raw: UnsafeMutableRawPointer, maxFrames: UInt32) throws -> UInt32 {
        while idx < clips.count {
            if cur == nil { try open(idx) }
            if remaining <= 0 { close(); idx += 1; continue }
            var n = UInt32(min(Int64(maxFrames), remaining))
            var abl = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: channels, mDataByteSize: n * channels * 4, mData: raw))
            guard ExtAudioFileRead(cur!, &n, &abl) == noErr else { throw ConvertError.encoderFailed("lecture") }
            if n == 0 { remaining = 0; continue }
            remaining -= Int64(n)
            return n
        }
        return 0
    }
}
