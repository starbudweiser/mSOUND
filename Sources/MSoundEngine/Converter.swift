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
        var f: ExtAudioFileRef?
        guard ExtAudioFileOpenURL(source as CFURL, &f) == noErr, let src = f else {
            throw ConvertError.unreadable(source.lastPathComponent)
        }
        defer { ExtAudioFileDispose(src) }

        let info = try Converter.info(of: source)
        if source.pathExtension.lowercased() == format.fileExtension,
           format != .alac, format != .m4a, options.range == nil, options.sampleRate == nil {
            throw ConvertError.sameFormat
        }

        let channels = format == .mp3 ? min(max(info.channels, 1), 2) : max(info.channels, 1)
        var outRate = options.sampleRate ?? info.sampleRate
        if format == .mp3 { outRate = Converter.mp3Rate(outRate) }
        let bits: UInt32 = info.bitDepth >= 24 ? 24 : 16

        var client = AudioStreamBasicDescription(
            mSampleRate: outRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4 * channels, mFramesPerPacket: 1, mBytesPerFrame: 4 * channels,
            mChannelsPerFrame: channels, mBitsPerChannel: 32, mReserved: 0)
        try check(ExtAudioFileSetProperty(src, kExtAudioFileProperty_ClientDataFormat,
                                          UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &client), "format client")

        // Plage à lire
        var startSec = 0.0
        var framesToRead = Int64(Double(info.frames) * outRate / max(info.sampleRate, 1))
        if let r = options.range {
            startSec = max(0, r.lowerBound)
            let end = min(info.duration, r.upperBound)
            framesToRead = Int64(max(0, end - startSec) * outRate)
            try check(ExtAudioFileSeek(src, Int64(startSec * info.sampleRate)), "positionnement")
        }

        let dir = options.outputDirectory ?? source.deletingLastPathComponent()
        let base = source.deletingPathExtension().lastPathComponent
        let temp = dir.appendingPathComponent(".\(base).\(UUID().uuidString.prefix(8)).partial.\(format.fileExtension)")
        var final = temp
        try? FileManager.default.removeItem(at: temp)

        do {
            if format == .mp3 {
                try encodeMP3(src: src, to: temp, rate: outRate, channels: channels, frames: framesToRead,
                              kbps: options.bitrateKbps, progress: progress)
            } else {
                try encodeNative(src: src, to: temp, format: format, rate: outRate, channels: channels, bits: bits,
                                 client: &client, frames: framesToRead, kbps: options.bitrateKbps, progress: progress)
            }
            // Déplacement sans écrasement ; en cas de course entre deux tâches, on cherche le nom libre suivant.
            var placed = false
            for _ in 0..<100 {
                final = Converter.uniqueURL(dir: dir, base: base, ext: format.fileExtension)
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

    private func encodeNative(src: ExtAudioFileRef, to url: URL, format: AudioFormat, rate: Double, channels: UInt32, bits: UInt32,
                              client: inout AudioStreamBasicDescription, frames: Int64, kbps: Int,
                              progress: ((Double) -> Void)?) throws {
        var out = Converter.outputASBD(format, rate: rate, channels: channels, bits: bits)
        var dstRef: ExtAudioFileRef?
        try check(ExtAudioFileCreateWithURL(url as CFURL, Converter.fileType(format), &out, nil,
                                            AudioFileFlags.eraseFile.rawValue, &dstRef), "création du fichier")
        guard let dst = dstRef else { throw ConvertError.encoderFailed("création") }
        defer { ExtAudioFileDispose(dst) }
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
        while done < frames {
            if Task.isCancelled { throw ConvertError.cancelled }
            var n = UInt32(min(Int64(chunk), frames - done))
            var abl = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: channels, mDataByteSize: UInt32(bytes), mData: raw))
            try check(ExtAudioFileRead(src, &n, &abl), "lecture")
            if n == 0 { break }
            abl.mBuffers.mDataByteSize = n * channels * 4
            try check(ExtAudioFileWrite(dst, n, &abl), "écriture")
            done += Int64(n)
            progress?(Double(done) / Double(max(frames, 1)))
        }
    }

    private func encodeMP3(src: ExtAudioFileRef, to url: URL, rate: Double, channels: UInt32, frames: Int64, kbps: Int,
                           progress: ((Double) -> Void)?) throws {
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
        while done < frames {
            if Task.isCancelled { throw ConvertError.cancelled }
            var n = UInt32(min(Int64(chunk), frames - done))
            var abl = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: channels, mDataByteSize: UInt32(bytes), mData: raw))
            try check(ExtAudioFileRead(src, &n, &abl), "lecture")
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
