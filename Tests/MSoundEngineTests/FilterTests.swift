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

    func testConformMonoToStereoAndRate() throws {
        // mono 48 kHz, 2 s, sinus 440 Hz à 0,3
        let url = dir.appendingPathComponent("mono48.wav")
        let w = try FloatWriter(url: url, rate: 48000, channels: 1)
        try w.write((0..<96000).map { Float(0.3 * sin(2 * .pi * 440 * Double($0) / 48000)) }); w.close()
        let r = try Filters.conform(url, rate: 44100, channels: 2)
        XCTAssertNotEqual(r.url, url)
        XCTAssertEqual(Double(r.frames), 88200, accuracy: 64)
        let x = try readAll(r.url)
        XCTAssertEqual(toneDB(x, f: 440, from: 0.2, to: 1.8), 20 * log10(0.3), accuracy: 1.0)
        // déjà conforme : même fichier
        let same = try Filters.conform(r.url, rate: 44100, channels: 2)
        XCTAssertEqual(same.url, r.url)
    }

    func testTintSurvivesSplitAndInsert() {
        let a = URL(fileURLWithPath: "/a.wav"), b = URL(fileURLWithPath: "/b.wav")
        let m = EditModel(source: a, frames: 1000, sampleRate: 44100)
        var c = Clip(source: b, start: 0, length: 200); c.tint = 2
        m.insert([c], at: 500)
        m.delete(100..<150)
        XCTAssertEqual(m.clips.map { $0.tint }, [0, 0, 2, 0])
        XCTAssertEqual(m.totalFrames, 1150)
        m.addMarker(at: 600, name: "x")
        XCTAssertEqual(m.clips(in: 400..<720).map { $0.tint }, [0, 2, 0])
    }

    func testRenderClipsToOtherFormat() throws {
        let url = dir.appendingPathComponent("mono48b.wav")
        let w = try FloatWriter(url: url, rate: 48000, channels: 1)
        try w.write((0..<96000).map { Float(0.3 * sin(2 * .pi * 440 * Double($0) / 48000)) }); w.close()
        var c = Clip(source: url, start: 24000, length: 48000)     // 1 s au milieu
        c.g0 = 0.5; c.g1 = 0.5                                       // −6 dB
        let r = try Filters.render([c], rate: 44100, channels: 2)
        XCTAssertEqual(Double(r.frames), 44100, accuracy: 64)
        let x = try readAll(r.url)
        XCTAssertEqual(toneDB(x, f: 440, from: 0.1, to: 0.9), 20 * log10(0.15), accuracy: 1.0)
    }

    func testGainNudgesCoalesceIntoOneUndo() {
        let a = URL(fileURLWithPath: "/a.wav")
        let m = EditModel(source: a, frames: 1000, sampleRate: 44100)
        let f = powf(10, 1.0 / 20)
        for _ in 0..<5 { m.applyGain(0..<1000, factor: f, coalesce: true) }
        XCTAssertEqual(m.clips[0].g0, powf(f, 5), accuracy: 1e-4)
        m.undo()
        XCTAssertEqual(m.clips[0].g0, 1, accuracy: 1e-6)
        XCTAssertFalse(m.canUndo)
        // une autre édition entre deux retouches : pas de fusion
        m.applyGain(0..<1000, factor: f, coalesce: true)
        m.addMarker(at: 10, name: "x")
        m.applyGain(0..<1000, factor: f, coalesce: true)
        m.undo(); m.undo()
        XCTAssertEqual(m.clips[0].g0, f, accuracy: 1e-4)
    }

    func testMeterPeakAndBallistics() {
        let x: [Float] = [0, 0.5, -0.25, 0.1]
        XCTAssertEqual(x.withUnsafeBufferPointer { Level.peakDB($0.baseAddress!, count: 4) }, -6.02, accuracy: 0.05)
        XCTAssertEqual([Float](repeating: 0, count: 8).withUnsafeBufferPointer { Level.peakDB($0.baseAddress!, count: 8) }, -120)
        XCTAssertEqual(Level.ballistic(previous: -30, new: -10, dt: 0.05), -10)            // montée immédiate
        XCTAssertEqual(Level.ballistic(previous: -10, new: -60, dt: 0.5), -22, accuracy: 0.01)   // retombée 24 dB/s
        XCTAssertEqual(Level.ballistic(previous: -10, new: -12, dt: 1), -12)                // ne tombe pas sous la mesure
    }
}
