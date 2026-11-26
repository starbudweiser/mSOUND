import XCTest
import AudioToolbox
@testable import MSoundEngine

final class ConverterTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("msound-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    /// WAV 24 bits stéréo, sinus 440 Hz, `seconds` secondes, via le moteur lui-même (CAF/WAV natif).
    func makeWAV(seconds: Double = 2, rate: Double = 44100, bits: UInt32 = 16) throws -> URL {
        let url = dir.appendingPathComponent("tone.wav")
        var asbd = Converter.outputASBD(.wav, rate: rate, channels: 2, bits: bits)
        var f: ExtAudioFileRef?
        XCTAssertEqual(ExtAudioFileCreateWithURL(url as CFURL, kAudioFileWAVEType, &asbd, nil, AudioFileFlags.eraseFile.rawValue, &f), noErr)
        var client = AudioStreamBasicDescription(mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 8, mFramesPerPacket: 1,
            mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        ExtAudioFileSetProperty(f!, kExtAudioFileProperty_ClientDataFormat, UInt32(MemoryLayout.size(ofValue: client)), &client)
        let n = Int(seconds * rate)
        var data = [Float](repeating: 0, count: n * 2)
        for i in 0..<n { let v = Float(sin(2 * .pi * 440 * Double(i) / rate)) * 0.5; data[2*i] = v; data[2*i+1] = v }
        data.withUnsafeMutableBytes { p in
            var abl = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(p.count), mData: p.baseAddress))
            XCTAssertEqual(ExtAudioFileWrite(f!, UInt32(n), &abl), noErr)
        }
        ExtAudioFileDispose(f!)
        return url
    }

    func testAllFormatsFromWAV() throws {
        let wav = try makeWAV()
        for fmt in AudioFormat.allCases where fmt != .wav {
            let out = try Converter().convert(wav, to: fmt)
            XCTAssertEqual(out.pathExtension, fmt.fileExtension, "\(fmt)")
            let info = try Converter.info(of: out)
            XCTAssertEqual(info.duration, 2.0, accuracy: 0.15, "durée \(fmt)")
            XCTAssertEqual(info.channels, 2, "canaux \(fmt)")
            XCTAssertGreaterThan(try FileManager.default.attributesOfItem(atPath: out.path)[.size] as! Int, 1000, "\(fmt)")
        }
    }

    func testLosslessKeepsSampleRate() throws {
        let wav = try makeWAV(rate: 48000, bits: 24)
        for fmt in [AudioFormat.flac, .alac, .aiff] {
            let out = try Converter().convert(wav, to: fmt)
            XCTAssertEqual(try Converter.info(of: out).sampleRate, 48000, "\(fmt)")
        }
    }

    func testRangeExport() throws {
        let wav = try makeWAV(seconds: 4)
        var o = ConvertOptions(); o.range = 1.0...2.5
        let out = try Converter().convert(wav, to: .flac, options: o)
        XCTAssertEqual(try Converter.info(of: out).duration, 1.5, accuracy: 0.05)
    }

    func testNeverOverwrites() throws {
        let wav = try makeWAV()
        let a = try Converter().convert(wav, to: .flac)
        let b = try Converter().convert(wav, to: .flac)
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
    }

    func testSameFormatRefused() throws {
        let wav = try makeWAV()
        XCTAssertThrowsError(try Converter().convert(wav, to: .wav)) { XCTAssertEqual($0 as? ConvertError, .sameFormat) }
    }

    func testUnreadableFile() {
        let bad = dir.appendingPathComponent("nope.wav")
        try? Data("pas de l'audio".utf8).write(to: bad)
        XCTAssertThrowsError(try Converter().convert(bad, to: .mp3))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("nope.mp3").path))
    }

    func testBatch() async throws {
        let wav = try makeWAV()
        let jobs = (0..<3).map { _ in BatchJob(source: wav) }
        let box = Box()
        await BatchQueue(maxConcurrent: 2).run(jobs, to: .m4a) { ev in
            if case .finished = ev { box.inc() }
        }
        XCTAssertEqual(box.n, 3)
    }
}

final class Box: @unchecked Sendable {
    private let l = NSLock(); private(set) var n = 0
    func inc() { l.lock(); n += 1; l.unlock() }
}
