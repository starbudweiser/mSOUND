import XCTest
@testable import MSoundEngine

final class FilterTests: XCTestCase {
    var dir: URL!
    let rate = 44100.0

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("msound-ftests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    // MARK: Aides

    struct RNG { var s: UInt64 = 12345
        mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double((s >> 33) & 0xFFFFFF) / Double(0xFFFFFF) } }
    func gauss(_ r: inout RNG) -> Double { sqrt(-2 * log(max(r.next(), 1e-9))) * cos(2 * .pi * r.next()) }

    /// Stéréo identique sur les deux canaux ; `gen(i)` rend l'échantillon i.
    func make(seconds: Double, _ gen: (Int) -> Double) throws -> URL {
        let n = Int(seconds * rate)
        var x = [Float](repeating: 0, count: n * 2)
        for i in 0..<n { let v = Float(gen(i)); x[2 * i] = v; x[2 * i + 1] = v }
        let url = dir.appendingPathComponent("\(UUID().uuidString).wav")
        let w = try FloatWriter(url: url, rate: rate, channels: 2)
        try w.write(x); w.close()
        return url
    }
    func clips(_ u: URL) throws -> [Clip] { [Clip(source: u, start: 0, length: try Converter.info(of: u).frames)] }
    func readAll(_ u: URL) throws -> [Float] {
        let c = try clips(u)
        let r = ClipReader(clips: c, infos: [u: try Converter.info(of: u)], outRate: rate, channels: 2)
        var out: [Float] = []
        let raw = UnsafeMutableRawPointer.allocate(byteCount: 8192 * 8, alignment: 16); defer { raw.deallocate() }
        while true {
            let n = try r.read(into: raw, maxFrames: 8192); if n == 0 { break }
            out += Array(UnsafeBufferPointer(start: raw.assumingMemoryBound(to: Float.self), count: Int(n) * 2))
        }
        return out
    }
    func rmsDB(_ x: [Float], from: Double, to: Double) -> Double {
        let a = Int(from * rate) * 2, b = min(Int(to * rate) * 2, x.count)
        var s = 0.0; for i in stride(from: a, to: b, by: 2) { s += Double(x[i] * x[i]) }
        return 10 * log10(max(s / Double((b - a) / 2), 1e-20))
    }
    /// Amplitude (dB) de la composante à `f` Hz entre from et to (canal gauche).
    func toneDB(_ x: [Float], f: Double, from: Double, to: Double) -> Double {
        let a = Int(from * rate), b = min(Int(to * rate), x.count / 2)
        var re = 0.0, im = 0.0
        for i in a..<b { let v = Double(x[2 * i]); let w = 2 * Double.pi * f * Double(i) / rate; re += v * cos(w); im += v * sin(w) }
        let amp = 2 * sqrt(re * re + im * im) / Double(b - a)
        return 20 * log10(max(amp, 1e-12))
    }

    // MARK: Mesures

    func testLoudnessMeterReferenceTone() throws {
        let u = try make(seconds: 6) { 0.1 * sin(2 * .pi * 1000 * Double($0) / self.rate) }   // −20 dBFS crête, stéréo
        let l = try Filters.loudness(of: try clips(u))
        XCTAssertEqual(l, -20.0, accuracy: 0.3)
    }

    func testLoudnessTargetIsReached() throws {
        let u = try make(seconds: 8) { 0.05 * sin(2 * .pi * 440 * Double($0) / self.rate) }
        let (out, n) = try Filters.apply([.loudness(-16)], to: try clips(u))
        XCTAssertEqual(n, try Converter.info(of: u).frames)
        XCTAssertEqual(try Filters.loudness(of: try clips(out)), -16.0, accuracy: 0.4)
    }

    func testLimiterNeverExceedsCeiling() throws {
        var r = RNG()
        let u = try make(seconds: 8) { i in (i % 20000 == 0 ? 0.9 : 0.02 * self.gauss(&r)) }   // impulsions + bruit faible
        let (out, _) = try Filters.apply([.loudness(-8)], to: try clips(u))
        let x = try readAll(out)
        XCTAssertLessThanOrEqual(Double(x.map { abs($0) }.max() ?? 0), 0.8913 + 0.003)
    }

    func testDenoiseReducesNoiseKeepsTone() throws {
        var r = RNG()
        let u = try make(seconds: 8) { i in
            let t = Double(i) / self.rate
            let noise = 0.01 * self.gauss(&r)                                  // ≈ −40 dBFS
            let tone = (t >= 3 && t < 5) ? 0.3 * sin(2 * .pi * 440 * t) : 0
            return noise + tone
        }
        let (out, n) = try Filters.apply([.denoise(.medium)], to: try clips(u))
        XCTAssertEqual(n, try Converter.info(of: u).frames)
        let x = try readAll(out), x0 = try readAll(u)
        let before = rmsDB(x0, from: 5.5, to: 7.5), after = rmsDB(x, from: 5.5, to: 7.5)
        XCTAssertLessThan(after, before - 10, "bruit seul : \(before) → \(after) dB")
        let t0 = toneDB(x0, f: 440, from: 3.2, to: 4.8), t1 = toneDB(x, f: 440, from: 3.2, to: 4.8)
        XCTAssertEqual(t1, t0, accuracy: 1.0, "le signal utile est conservé")
    }

    func testCleanRemovesHumKeepsVoiceBand() throws {
        let u = try make(seconds: 6) { i in
            let t = Double(i) / self.rate
            return 0.1 * sin(2 * .pi * 50 * t) + 0.05 * sin(2 * .pi * 100 * t) + 0.3 * sin(2 * .pi * 1000 * t)
        }
        let (out, _) = try Filters.apply([.clean(highpassHz: 80)], to: try clips(u))
        let x = try readAll(out), x0 = try readAll(u)
        XCTAssertLessThan(toneDB(x, f: 50, from: 2, to: 6), toneDB(x0, f: 50, from: 2, to: 6) - 30)
        XCTAssertLessThan(toneDB(x, f: 100, from: 2, to: 6), toneDB(x0, f: 100, from: 2, to: 6) - 20)
        XCTAssertEqual(toneDB(x, f: 1000, from: 2, to: 6), toneDB(x0, f: 1000, from: 2, to: 6), accuracy: 0.3)
    }

    func testHumDetection() throws {
        var r = RNG()
        let hum = try make(seconds: 5) { i in 0.05 * sin(2 * .pi * 60 * Double(i) / self.rate) + 0.01 * self.gauss(&r) }
        let d = HumDetector(rate: rate)
        d.add(try readAll(hum), channels: 2)
        XCTAssertEqual(d.detected, 60)
        let clean = try make(seconds: 5) { _ in 0.02 * self.gauss(&r) }
        let d2 = HumDetector(rate: rate)
        d2.add(try readAll(clean), channels: 2)
        XCTAssertNil(d2.detected)
    }

    func testCompressorReducesDynamicsKeepsLoudness() throws {
        // 1 s à −12 dB, 1 s à −24 dB, en alternance
        let u = try make(seconds: 8) { i in
            let t = Double(i) / self.rate
            return (Int(t) % 2 == 0 ? 0.25 : 0.0631) * sin(2 * .pi * 300 * t)
        }
        let before = try Filters.loudness(of: try clips(u))
        let (out, _) = try Filters.apply([.compress(.radio)], to: try clips(u))
        let x = try readAll(out), x0 = try readAll(u)
        let d0 = rmsDB(x0, from: 4.2, to: 5) - rmsDB(x0, from: 5.2, to: 6)
        let d1 = rmsDB(x, from: 4.2, to: 5) - rmsDB(x, from: 5.2, to: 6)
        XCTAssertLessThan(d1, d0 - 2.5, "écart de niveaux \(d0) → \(d1) dB")
        XCTAssertEqual(try Filters.loudness(of: try clips(out)), before, accuracy: 1.2)
    }

    func testEQVoiceBoostsPresenceCutsMud() throws {
        let u = try make(seconds: 4) { i in
            let t = Double(i) / self.rate
            return 0.1 * sin(2 * .pi * 250 * t) + 0.1 * sin(2 * .pi * 3200 * t) + 0.1 * sin(2 * .pi * 1000 * t)
        }
        let (out, _) = try Filters.apply([.eq(.voice)], to: try clips(u))
        let x = try readAll(out), x0 = try readAll(u)
        XCTAssertLessThan(toneDB(x, f: 250, from: 1, to: 3) - toneDB(x0, f: 250, from: 1, to: 3), -1.8)
        XCTAssertGreaterThan(toneDB(x, f: 3200, from: 1, to: 3) - toneDB(x0, f: 3200, from: 1, to: 3), 1.8)
        XCTAssertEqual(toneDB(x, f: 1000, from: 1, to: 3), toneDB(x0, f: 1000, from: 1, to: 3), accuracy: 0.7)
    }

    func testRecipeKeepsLengthAndHitsTarget() throws {
        var r = RNG()
        let u = try make(seconds: 10) { i in
            let t = Double(i) / self.rate
            let voice = (t > 2 && t < 8) ? 0.15 * sin(2 * .pi * 220 * t) * (0.6 + 0.4 * sin(2 * .pi * 3 * t)) : 0
            return voice + 0.006 * self.gauss(&r) + 0.01 * sin(2 * .pi * 50 * t)
        }
        let (out, n) = try Filters.apply(Recipe.voicePro.steps, to: try clips(u))
        XCTAssertEqual(n, try Converter.info(of: u).frames)
        let l = try Filters.loudness(of: try clips(out))
        XCTAssertEqual(l, -16, accuracy: 1.5)
        let x = try readAll(out)
        XCTAssertLessThanOrEqual(Double(x.map { abs($0) }.max() ?? 0), 0.8913 + 0.01)
    }

    func testReplaceKeepsDuration() {
        let a = URL(fileURLWithPath: "/a.wav"), b = URL(fileURLWithPath: "/b.wav")
        let m = EditModel(source: a, frames: 1000, sampleRate: 44100)
        m.replace(200..<500, with: [Clip(source: b, start: 0, length: 300)])
        XCTAssertEqual(m.totalFrames, 1000)
        XCTAssertEqual(m.clips.map { $0.source }, [a, b, a])
        XCTAssertEqual(m.clips.map { $0.length }, [200, 300, 500])
        m.undo()
        XCTAssertEqual(m.clips.count, 1)
    }
}
