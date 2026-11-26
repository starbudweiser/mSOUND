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

    private struct Item { var file: AVAudioFile; var start: Int64; var count: Int64; var fx: (g0: Float, g1: Float, len: Int64, off: Int64)? }
    private var queue: [Item] = []
    private var outstanding = 0

    /// Joue [from, until) de la ligne de temps. Les segments sans effet sont lus directement depuis le fichier ;
    /// ceux qui ont un gain ou un fondu sont traités par blocs, alimentés au fil de la lecture.
    func play(clips: [Clip], from: Int64, until: Int64?) throws {
        stop()
        gen += 1
        let g = gen
        if !engine.isRunning { try engine.start() }
        let limit = until ?? clips.reduce(0) { $0 + $1.length }
        var pos: Int64 = 0
        queue = []; outstanding = 0
        for c in clips {
            let end = pos + c.length
            let lo = max(pos, from), hi = min(end, limit)
            if hi > lo {
                let off = lo - pos
                queue.append(Item(file: try file(c.source), start: c.start + off, count: hi - lo,
                                  fx: c.hasFX ? (c.g0, c.g1, c.length, off) : nil))
            }
            pos = end
        }
        guard !queue.isEmpty else { onFinished?(); return }
        base = from
        feed(g)
        node.play()
    }

    private func feed(_ g: Int) {
        guard g == gen else { return }
        while outstanding < 6, !queue.isEmpty {
            outstanding += 1
            let done: AVAudioNodeCompletionHandler = { [weak self] in
                DispatchQueue.main.async {
                    guard let self, self.gen == g else { return }
                    self.outstanding -= 1
                    if self.queue.isEmpty && self.outstanding == 0 { self.onFinished?() } else { self.feed(g) }
                }
            }
            var it = queue[0]
            if let fx = it.fx {
                let n = min(it.count, 65536)
                it.file.framePosition = it.start
                if let buf = AVAudioPCMBuffer(pcmFormat: it.file.processingFormat, frameCapacity: AVAudioFrameCount(n)),
                   (try? it.file.read(into: buf, frameCount: AVAudioFrameCount(n))) != nil, buf.frameLength > 0,
                   let ch = buf.floatChannelData {
                    let frames = Int(buf.frameLength), chans = Int(buf.format.channelCount)
                    for c in 0..<chans {   // données non entrelacées : une rampe par canal
                        Effects.apply(ch[c], frames: frames, channels: 1, pos: fx.off, length: fx.len, g0: fx.g0, g1: fx.g1)
                    }
                    node.scheduleBuffer(buf, at: nil, options: [], completionCallbackType: .dataPlayedBack) { _ in done() }
                    it.start += Int64(frames); it.count -= Int64(frames)
                    it.fx?.off += Int64(frames)
                } else { it.count = 0; outstanding -= 1 }
            } else {
                node.scheduleSegment(it.file, startingFrame: it.start, frameCount: AVAudioFrameCount(it.count), at: nil,
                                     completionCallbackType: .dataPlayedBack) { _ in done() }
                it.count = 0
            }
            if it.count <= 0 { queue.removeFirst() } else { queue[0] = it }
        }
        if queue.isEmpty && outstanding == 0 { onFinished?() }
    }

    func stop() {
        gen += 1; queue = []; outstanding = 0
        node.stop()
    }

    /// Position courante sur la ligne de temps.
    var position: Int64? {
        guard node.isPlaying, let t = node.lastRenderTime, let p = node.playerTime(forNodeTime: t) else { return nil }
        return base + p.sampleTime
    }
}
