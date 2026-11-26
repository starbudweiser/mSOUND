import Foundation
import AppKit
import AVFoundation
import Combine
import MSoundEngine
import MSoundShared

/// État de lecture, séparé du document pour que seul l'affichage du temps se rafraîchisse à 30 Hz.
@MainActor final class Transport: ObservableObject {
    @Published var playhead: Int64 = 0
    @Published var isPlaying = false
}

@MainActor final class ZoomState: ObservableObject { @Published var level: Double = 0 }

@MainActor
final class EditorDocument: ObservableObject {
    let url: URL
    let info: Converter.SourceInfo
    let model: EditModel
    let transport = Transport()
    let redraw = PassthroughSubject<Void, Never>()
    private(set) var player: PlayerEngine?
    private var peaks: [URL: PeakData] = [:]

    @Published var selection: Range<Int64>?
    @Published var revision = 0              // change à chaque modification du montage
    @Published var peaksProgress: Double = 0
    @Published var message: String?
    @Published var exportFormat: AudioFormat = .m4a
    @Published var exportKbps = 256
    @Published var volume: Float = 1 { didSet { player?.volume = volume } }

    var fpp: Double = 1000                   // trames par pixel
    var scroll: Int64 = 0                    // première trame visible
    let zoomState = ZoomState()
    var visibleFrames: Int64 { Int64(Double(viewWidth) * fpp) }
    var viewWidth: CGFloat = 800 { didSet { if oldValue != viewWidth, !userZoomed { fit() } } }
    private var userZoomed = false
    private var timer: Timer?
    static var clipboard: [Clip] = []

    var total: Int64 { model.totalFrames }
    var rate: Double { info.sampleRate }
    var laneCount: Int { Int(min(max(info.channels, 1), 2)) }
    var name: String { url.deletingPathExtension().lastPathComponent }

    init(url: URL) throws {
        self.url = url
        info = try Converter.info(of: url)
        guard info.frames > 0 else { throw ConvertError.unreadable(url.lastPathComponent) }
        model = EditModel(source: url, frames: info.frames, sampleRate: info.sampleRate)
        let f = try AVAudioFile(forReading: url).processingFormat
        player = PlayerEngine(format: f)
        player?.onFinished = { [weak self] in self?.playbackEnded() }
        startPeaks(for: url)
    }

    // MARK: - Formes d'onde

    private func startPeaks(for u: URL) {
        guard let pd = try? PeakData(url: u) else { return }
        peaks[u] = pd
        Task.detached { [weak self] in
            try? pd.build { p in
                Task { @MainActor in self?.peaksProgress = p; self?.redraw.send() }
            }
            await MainActor.run { self?.peaksProgress = 1; self?.redraw.send() }
        }
    }

    var isComputing: Bool { peaksProgress < 1 }

    /// Amplitude (0…1, max des canaux) de `count` colonnes de `perColumn` trames à partir de `start`.
    func columns(count: Int, start: Int64, perColumn: Double) -> [Float] {
        var out = [Float](repeating: 0, count: max(count, 0))
        guard count > 0, perColumn > 0 else { return out }
        let clips = model.clips
        var starts: [Int64] = [], pos: Int64 = 0
        for c in clips { starts.append(pos); pos += c.length }
        var ci = 0
        for i in 0..<count {
            let s = start + Int64(Double(i) * perColumn)
            if s >= pos { break }
            if s < 0 { continue }
            while ci + 1 < clips.count && starts[ci + 1] <= s { ci += 1 }
            while ci > 0 && starts[ci] > s { ci -= 1 }
            let c = clips[ci]
            let a = c.start + (s - starts[ci])
            let b = min(c.end, a + max(1, Int64(perColumn)))
            var amp: Float = 0
            for l in 0..<laneCount {
                let m = peaks[c.source]?.minMax(channel: l, from: a, to: b) ?? (0, 0)
                amp = max(amp, abs(m.0), abs(m.1))
            }
            out[i] = amp
        }
        return out
    }

    // MARK: - Zoom / défilement

    var maxFPP: Double { max(1, Double(total) / Double(max(viewWidth, 1))) }
    static let minFPP = 4.0
    func fit() { fpp = maxFPP; scroll = 0; userZoomed = false; syncZoom(); redraw.send() }
    private func syncZoom() {
        let r = log(fpp / maxFPP) / log(Self.minFPP / maxFPP)
        zoomState.level = r.isFinite ? min(max(r, 0), 1) : 0
    }
    /// 0 = tout le fichier, 1 = zoom maximal (échelle logarithmique).
    func setZoomLevel(_ l: Double) {
        userZoomed = l > 0.001
        let anchor = Double(scroll) + Double(viewWidth) / 2 * fpp
        fpp = maxFPP * pow(Self.minFPP / maxFPP, l)
        scroll = Int64(anchor - Double(viewWidth) / 2 * fpp)
        clampScroll(); redraw.send()
    }
    func scrollTo(centerFrame f: Int64) { scroll = f - visibleFrames / 2; clampScroll(); redraw.send() }
    func zoom(factor: Double, anchorX: CGFloat) {
        userZoomed = true
        let anchor = Double(scroll) + Double(anchorX) * fpp
        fpp = min(max(fpp * factor, Self.minFPP), maxFPP)
        scroll = Int64(anchor - Double(anchorX) * fpp)
        clampScroll(); syncZoom(); redraw.send()
    }
    func pan(byPixels dx: CGFloat) { scroll -= Int64(Double(dx) * fpp); clampScroll(); redraw.send() }
    private func clampScroll() {
        let visible = Int64(Double(viewWidth) * fpp)
        scroll = max(0, min(scroll, max(0, total - visible)))
    }
    func frame(atX x: CGFloat) -> Int64 { max(0, min(total, scroll + Int64(Double(x) * fpp))) }
    func x(forFrame f: Int64) -> CGFloat { CGFloat(Double(f - scroll) / fpp) }

    // MARK: - Sélection / position

    func setSelection(_ a: Int64, _ b: Int64) {
        let lo = min(a, b), hi = max(a, b)
        selection = hi > lo ? lo..<hi : nil
        redraw.send()
    }
    func selectAll() { selection = 0..<total; redraw.send() }
    func seek(to f: Int64) {
        let was = transport.isPlaying
        transport.playhead = max(0, min(f, total))
        if was { play() } else { redraw.send() }
    }

    // MARK: - Lecture

    func togglePlay() { transport.isPlaying ? pause() : play() }

    func play() {
        guard let player else { return }
        var from = transport.playhead
        var until: Int64? = nil
        if let s = selection {
            if from < s.lowerBound || from >= s.upperBound { from = s.lowerBound }
            until = s.upperBound
        } else if from >= total { from = 0 }
        do {
            try player.play(clips: model.clips, from: from, until: until)
            transport.playhead = from
            transport.isPlaying = true
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        } catch { message = error.localizedDescription }
    }

    func pause() {
        if let p = player?.position { transport.playhead = max(0, min(p, total)) }
        stopPlayback()
    }

    func stop() {
        stopPlayback()
        transport.playhead = selection?.lowerBound ?? 0
        redraw.send()
    }

    private func stopPlayback() {
        player?.stop(); timer?.invalidate(); timer = nil
        transport.isPlaying = false; redraw.send()
    }

    private func playbackEnded() {
        timer?.invalidate(); timer = nil
        transport.isPlaying = false
        transport.playhead = selection?.upperBound ?? total
        redraw.send()
    }

    private func tick() {
        guard let p = player?.position else { return }
        transport.playhead = max(0, min(p, total))
        let right = scroll + Int64(Double(viewWidth) * fpp)
        if transport.playhead > right || transport.playhead < scroll { scroll = transport.playhead; clampScroll() }
        redraw.send()
    }

    // MARK: - Édition

    private func edited(_ block: () -> Void) {
        if transport.isPlaying { pause() }
        block()
        selection = nil
        transport.playhead = min(transport.playhead, total)
        revision += 1
        clampScroll(); redraw.send()
    }

    func cut() { guard let s = selection else { return }; Self.clipboard = model.clips(in: s); let r = s; edited { model.delete(r); transport.playhead = r.lowerBound } }
    func copySel() { guard let s = selection else { return }; Self.clipboard = model.clips(in: s) }
    func paste() { guard !Self.clipboard.isEmpty else { return }; let at = transport.playhead; let c = Self.clipboard
        edited { model.insert(c, at: at); transport.playhead = at + c.reduce(0) { $0 + $1.length } } }
    func deleteSel() { guard let s = selection else { return }; edited { model.delete(s); transport.playhead = s.lowerBound } }
    func keepSel() { guard let s = selection else { return }; edited { model.keepOnly(s); transport.playhead = 0 } }
    func splitHere() { let f = transport.playhead; edited { model.addMarker(at: f, name: Loc.t("markerName", model.markers.count + 1)) } }
    func addMarker() { splitHere() }
    func removeMarker(_ id: UUID) { edited { model.removeMarker(id) } }
    func undo() { edited { model.undo() } }
    func redo() { edited { model.redo() } }
    var canUndo: Bool { model.canUndo }
    var canRedo: Bool { model.canRedo }

    /// Repères à la fin de chaque silence (≥ 0,5 s sous −50 dB).
    func markSilences() {
        guard let pd = peaks[url], pd.ready else { return }
        let list = pd.silences().map { Marker(frame: $0.1, name: Loc.t("markerName", 0)) }
        var n = model.markers.count
        let named = list.map { m -> Marker in n += 1; return Marker(frame: m.frame, name: Loc.t("markerName", n)) }
        edited { model.addMarkers(named.filter { $0.frame < total }) }
    }

    func appendFile(_ u: URL) {
        guard let i = try? Converter.info(of: u), i.channels == info.channels, i.sampleRate == info.sampleRate, i.frames > 0 else {
            message = Loc.t("mergeMismatch"); return
        }
        startPeaks(for: u)
        edited { model.append(Clip(source: u, start: 0, length: i.frames)) }
    }

    // MARK: - Export

    func export() {
        let sel = selection
        let clips = sel.map { model.clips(in: $0) } ?? model.clips
        guard !clips.isEmpty else { return }
        let suffix = sel != nil ? Loc.t("selSuffix") : (model.clips.count == 1 && model.clips[0].start == 0 && model.clips[0].length == info.frames ? nil : Loc.t("edited"))
        let base = name + (suffix.map { " (\($0))" } ?? "")
        let format = exportFormat, kbps = exportKbps, dir = url.deletingLastPathComponent()
        ProgressPanelController.shared.addCustom(name: base, format: format) { token, progress in
            var o = ConvertOptions(); o.bitrateKbps = kbps; o.cancelToken = token
            return try Converter().export(clips, to: format, options: o, baseName: base, directory: dir, progress: progress)
        }
    }
}

