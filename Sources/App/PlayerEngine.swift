import AVFoundation
import MSoundEngine

/// Lecture d'un montage (suite de segments) en continu depuis les fichiers, sans les charger en mémoire.
final class PlayerEngine {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var files: [URL: AVAudioFile] = [:]
    private var base: Int64 = 0
    private var gen = 0
    let format: AVAudioFormat
    var onFinished: (() -> Void)?

    init(format: AVAudioFormat) {
        self.format = format
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    private func file(_ u: URL) throws -> AVAudioFile {
        if let f = files[u] { return f }
        let f = try AVAudioFile(forReading: u); files[u] = f; return f
    }

    var isPlaying: Bool { node.isPlaying }
    var volume: Float { get { engine.mainMixerNode.outputVolume } set { engine.mainMixerNode.outputVolume = newValue } }

    /// Joue [from, until) de la ligne de temps.
    func play(clips: [Clip], from: Int64, until: Int64?) throws {
        stop()
        gen += 1
        let g = gen
        if !engine.isRunning { try engine.start() }
        let limit = until ?? clips.reduce(0) { $0 + $1.length }
        var pos: Int64 = 0
        var pieces: [(AVAudioFile, Int64, Int64)] = []
        for c in clips {
            let end = pos + c.length
            let lo = max(pos, from), hi = min(end, limit)
            if hi > lo { pieces.append((try file(c.source), c.start + (lo - pos), hi - lo)) }
            pos = end
        }
        guard !pieces.isEmpty else { onFinished?(); return }
        base = from
        for (i, p) in pieces.enumerated() {
            if i == pieces.count - 1 {
                node.scheduleSegment(p.0, startingFrame: p.1, frameCount: AVAudioFrameCount(p.2), at: nil,
                                     completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    DispatchQueue.main.async { if let self, self.gen == g { self.onFinished?() } }
                }
            } else {
                node.scheduleSegment(p.0, startingFrame: p.1, frameCount: AVAudioFrameCount(p.2), at: nil, completionHandler: nil)
            }
        }
        node.play()
    }

    func stop() {
        gen += 1
        node.stop()
    }

    /// Position courante sur la ligne de temps.
    var position: Int64? {
        guard node.isPlaying, let t = node.lastRenderTime, let p = node.playerTime(forNodeTime: t) else { return nil }
        return base + p.sampleTime
    }
}
