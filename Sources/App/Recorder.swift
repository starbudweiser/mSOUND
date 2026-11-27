import AVFoundation
import AppKit
import MSoundEngine
import MSoundShared

/// Enregistrement du micro dans un WAV Float32 (un seul à la fois, dans toute l'appli), avec niveaux pour les vumètres.
@MainActor final class Recorder: ObservableObject {
    static let shared = Recorder()

    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var levels: [Float] = [-120]        // dBFS par canal, avec retombée
    @Published private(set) var peakHold: [Float] = [-120]
    @Published var error: String?

    private let engine = AVAudioEngine()
    private var sink: Sink?
    private var url: URL?
    private var onFinished: ((URL) -> Void)?
    private var starting = false { didSet { if starting { startingSince = Date() } } }
    private var startingSince = Date.distantPast
    private var configObserver: NSObjectProtocol?

    /// Données partagées avec le fil audio.
    private final class Sink: @unchecked Sendable {
        var file: AVAudioFile?
        var frames: Int64 = 0
        var lastUI = Date.distantPast
        var acc: [Float] = []
    }

    static var folder: URL {
        get {
            if let p = UserDefaults.standard.string(forKey: "recordFolder") { return URL(fileURLWithPath: p, isDirectory: true) }
            return FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0].appendingPathComponent("mSOUND", isDirectory: true)
        }
        set { UserDefaults.standard.set(newValue.path, forKey: "recordFolder") }
    }

    func toggle(onFinished: @escaping (URL) -> Void) {
        if isRecording { stop(save: true) } else { start(onFinished: onFinished) }
    }

    func start(onFinished: @escaping (URL) -> Void) {
        // Un démarrage resté en attente (autorisation jamais répondue…) ne doit pas bloquer le bouton pour toujours.
        if starting, Date().timeIntervalSince(startingSince) > 8 { starting = false }
        guard !isRecording, !starting else { return }
        starting = true; error = nil
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: begin(onFinished)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                DispatchQueue.main.async { if ok { self.begin(onFinished) } else { self.fail(Loc.t("recDenied")) } }
            }
        default: fail(Loc.t("recDenied"))
        }
    }

    private func fail(_ m: String) { starting = false; error = m }

    private func begin(_ onFinished: @escaping (URL) -> Void) {
        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        guard fmt.channelCount > 0, fmt.sampleRate > 0 else { fail(Loc.t("recNoInput")); return }
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            let stamp = DateFormatter(); stamp.dateFormat = "yyyy-MM-dd HH-mm-ss"
            let u = Self.folder.appendingPathComponent("\(Loc.t("recName")) \(stamp.string(from: Date())).wav")
            let sink = Sink()
            sink.file = try AVAudioFile(forWriting: u, settings: fmt.settings, commonFormat: fmt.commonFormat, interleaved: fmt.isInterleaved)
            let rate = fmt.sampleRate, channels = Int(fmt.channelCount)
            input.installTap(onBus: 0, bufferSize: 4096, format: fmt) { [weak self] buf, _ in
                try? sink.file?.write(from: buf)
                sink.frames += Int64(buf.frameLength)
                guard let ch = buf.floatChannelData else { return }
                var lv: [Float] = []
                for c in 0..<min(channels, 2) { lv.append(Level.peakDB(ch[c], count: Int(buf.frameLength))) }
                if sink.acc.count != lv.count { sink.acc = lv } else { for i in lv.indices { sink.acc[i] = max(sink.acc[i], lv[i]) } }
                let now = Date(), dt = now.timeIntervalSince(sink.lastUI)
                guard dt > 0.04 else { return }
                sink.lastUI = now
                let merged = sink.acc
                sink.acc = []
                let frames = sink.frames
                DispatchQueue.main.async { self?.update(levels: merged, dt: dt, elapsed: Double(frames) / rate) }
            }
            engine.prepare()
            try engine.start()
            self.sink = sink; url = u; self.onFinished = onFinished
            // Changement de périphérique d'entrée (casque branché, etc.) : l'enregistrement s'arrête en gardant ce qui existe.
            configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.interrupted() }
            }
            // Garde-fou : si aucune donnée n'arrive du micro, on abandonne au lieu de rester bloqué sur 00:00.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self, weak sink] in
                guard let self, self.isRecording, let sink, self.sink === sink, sink.frames == 0 else { return }
                self.stop(save: false); self.error = Loc.t("recNoSignal")
            }
            levels = [Float](repeating: -120, count: min(channels, 2)); peakHold = levels
            elapsed = 0; isRecording = true; starting = false
        } catch {
            input.removeTap(onBus: 0)
            fail(error.localizedDescription)
        }
    }

    private func update(levels new: [Float], dt: Double, elapsed t: Double) {
        guard isRecording else { return }
        levels = zip(levels, new).map { Level.ballistic(previous: $0, new: $1, dt: dt) }
        peakHold = zip(peakHold, new).map { max($1, $0 - 8 * Float(dt)) }
        elapsed = t
    }

    private func interrupted() {
        guard isRecording else { return }
        let had = (sink?.frames ?? 0) > 0
        stop(save: had)
        if !had { error = Loc.t("recNoSignal") }
    }

    /// Arrête l'enregistrement : `save` = vrai garde le fichier et le transmet ; faux l'efface.
    func stop(save: Bool) {
        guard isRecording else { return }
        if let o = configObserver { NotificationCenter.default.removeObserver(o); configObserver = nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let frames = sink?.frames ?? 0
        sink?.file = nil                                   // referme et finalise le WAV
        isRecording = false; starting = false
        let u = url, cb = onFinished
        sink = nil; url = nil; onFinished = nil
        guard let u else { return }
        if save, frames > 0 { cb?(u) } else { try? FileManager.default.removeItem(at: u) }
    }
}
