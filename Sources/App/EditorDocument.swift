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
    @Published var exportKbps = Prefs.bitrate
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
    func columns(count: Int, start: Int64, perColumn: Double) -> [Float] { columnData(count: count, start: start, perColumn: perColumn).amps }

    /// Comme `columns`, avec la couleur (tint) du segment de chaque colonne.
    func columnData(count: Int, start: Int64, perColumn: Double) -> (amps: [Float], tints: [UInt8]) {
        var out = [Float](repeating: 0, count: max(count, 0))
        var tints = [UInt8](repeating: 0, count: max(count, 0))
        guard count > 0, perColumn > 0 else { return (out, tints) }
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
            out[i] = amp; tints[i] = UInt8(truncatingIfNeeded: c.tint)
        }
        return (out, tints)
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
    /// Vrai dès que l'utilisateur a placé la tête de lecture : l'import s'y insère, sinon il se place à la fin.
    var playheadMoved = false
    func seek(to f: Int64) {
        playheadMoved = true
        let was = transport.isPlaying
        transport.playhead = max(0, min(f, total))
        if was { play() } else { redraw.send() }
    }

    // MARK: - Lecture

    func togglePlay() { transport.isPlaying ? pause() : play() }

    func play() {
        guard working == nil else { return }
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

    struct Working { var title: String; var progress: Double }
    @Published var working: Working?
    private var workToken: CancelToken?

    /// Applique une chaîne de filtres à la sélection (ou à tout) : rendu en arrière-plan, puis remplacement annulable dans le montage.
    private var workDone: (() -> Void)?
    func process(_ steps: [FilterStep], title: String, whole: Bool = false, completion: (() -> Void)? = nil) {
        guard working == nil, total > 0 else { completion?(); return }
        workDone = completion
        if transport.isPlaying { pause() }
        let range = (whole ? nil : selection) ?? 0..<total
        let hadSel = !whole && selection != nil
        let clips = model.clips(in: range)
        guard !clips.isEmpty else { workDone = nil; completion?(); return }
        let tint = clips[0].tint
        let token = CancelToken(); workToken = token
        working = Working(title: title, progress: 0)
        Task.detached { [weak self] in
            do {
                let r = try Filters.apply(steps, to: clips, token: token) { p in Task { @MainActor in self?.working?.progress = p } }
                await MainActor.run { self?.finishWork(range: range, hadSel: hadSel, url: r.url, frames: r.frames, tint: tint) }
            } catch {
                await MainActor.run { self?.failWork(error) }
            }
        }
    }
    func cancelWork() { workToken?.cancel() }
    private func finishWork(range: Range<Int64>, hadSel: Bool, url: URL, frames: Int64, tint: Int) {
        working = nil
        startPeaks(for: url)
        var nc = Clip(source: url, start: 0, length: frames); nc.tint = tint
        edited { model.replace(range, with: [nc]) }
        if hadSel { selection = range; redraw.send() }
        let d = workDone; workDone = nil; d?()
    }
    private func failWork(_ e: Error) {
        working = nil
        if (e as? ConvertError) == .cancelled { return }
        message = (e as? FilterError) != nil ? Loc.t("filterSilent") : e.localizedDescription
        let d = workDone; workDone = nil; d?()
    }

    private func edited(_ block: () -> Void) {
        guard working == nil else { return }
        if transport.isPlaying { pause() }
        block()
        selection = nil
        transport.playhead = min(transport.playhead, total)
        revision += 1
        clampScroll(); redraw.send()
    }

    /// Presse-papiers commun à toutes les timelines (et fenêtres) : copier/couper dans l'une, coller dans une autre.
    static var clipboardNames: [Int: String] = [:]
    static weak var clipboardOrigin: EditorDocument?

    private func stash(_ s: Range<Int64>) {
        Self.clipboard = model.clips(in: s)
        Self.clipboardOrigin = self
        Self.clipboardNames = sourceNames.merging([0: name]) { a, _ in a }
    }
    func cut() { guard let s = selection else { return }; stash(s); let r = s; edited { model.delete(r); transport.playhead = r.lowerBound } }
    func copySel() { guard let s = selection else { return }; stash(s) }

    func paste() {
        guard working == nil, !Self.clipboard.isEmpty else { return }
        if transport.isPlaying { pause() }
        let at = transport.playhead
        var clips = Self.clipboard
        // Couleurs : un bloc venu d'une autre timeline reçoit ses propres couleurs (la couleur 0 est celle du fichier de chaque timeline).
        if Self.clipboardOrigin !== self {
            var map: [Int: Int] = [:], next = (model.clips.map { $0.tint }.max() ?? 0)
            for i in clips.indices {
                let t = clips[i].tint
                if map[t] == nil { next = next % 4 + 1; map[t] = next; sourceNames[next] = Self.clipboardNames[t] ?? Self.clipboardOrigin?.name ?? "—" }
                clips[i].tint = map[t]!
            }
        }
        // Fréquence ou canaux différents : le bloc est d'abord rendu au format de cette timeline.
        let rate = info.sampleRate, ch = Int(info.channels)
        let mismatch = clips.contains { c in
            guard let i = try? Converter.info(of: c.source) else { return false }
            return i.sampleRate != rate || Int(i.channels) != ch
        }
        if !mismatch { finishPaste(clips, at: at); return }
        let token = CancelToken(); workToken = token
        working = Working(title: Loc.t("importing"), progress: 0)
        let tint = clips[0].tint, toRender = clips
        Task.detached { [weak self] in
            do {
                let r = try Filters.render(toRender, rate: rate, channels: ch, token: token) { p in Task { @MainActor in self?.working?.progress = p } }
                var c = Clip(source: r.url, start: 0, length: r.frames); c.tint = tint
                await MainActor.run { self?.working = nil; self?.finishPaste([c], at: at) }
            } catch { await MainActor.run { self?.failWork(error) } }
        }
    }
    private func finishPaste(_ clips: [Clip], at: Int64) {
        for c in clips where peaks[c.source] == nil { startPeaks(for: c.source) }
        edited { model.insert(clips, at: at); transport.playhead = at + clips.reduce(0) { $0 + $1.length } }
        playheadMoved = true
    }
    func deleteSel() { guard let s = selection else { return }; edited { model.delete(s); transport.playhead = s.lowerBound } }
    func keepSel() { guard let s = selection else { return }; edited { model.keepOnly(s); transport.playhead = 0 } }
    /// Retouche d'effet qui garde la sélection et relance la lecture si elle tournait.
    private func effect(_ block: () -> Void) {
        guard working == nil else { return }
        let sel = selection, was = transport.isPlaying, pos = transport.playhead
        edited(block)
        selection = sel
        if was { transport.playhead = pos; play() }
        redraw.send()
    }

    /// Gain en dB sur la sélection, ou sur tout l'échantillon sans sélection. `coalesce` : une seule annulation pour une série de retouches.
    func gain(db: Float, coalesce: Bool = false) {
        guard total > 0 else { return }
        let r = selection ?? 0..<total, f = powf(10, db / 20)
        effect { model.applyGain(r, factor: f, coalesce: coalesce) }
    }
    /// Fondu sur la sélection ; sans sélection : 1 s (au plus la moitié) au début ou à la fin de l'échantillon.
    func fadeIn() {
        guard total > 0 else { return }
        let r = selection ?? 0..<min(Int64(rate), total / 2)
        effect { model.fade(r, fadeIn: true) }
    }
    func fadeOut() {
        guard total > 0 else { return }
        let r = selection ?? (total - min(Int64(rate), total / 2))..<total
        effect { model.fade(r, fadeIn: false) }
    }
    /// Amène la crête de la sélection (ou de tout l'échantillon) à −1 dBFS.
    func normalize() {
        guard working == nil, total > 0 else { return }
        let range = selection ?? 0..<total
        let clips = model.clips(in: range)
        guard !clips.isEmpty else { return }
        working = Working(title: Loc.t("normalizing"), progress: 0)
        Task.detached { [weak self] in
            let peak = (try? Effects.peak(of: clips)) ?? 0
            await MainActor.run {
                guard let self else { return }
                self.working = nil
                guard peak > 0.000_01 else { self.message = Loc.t("silentSel"); return }
                let f = powf(10, -1.0 / 20) / peak
                self.effect { self.model.applyGain(range, factor: f) }
            }
        }
    }

    /// Déplace la tête de lecture de `frames` trames (flèches gauche/droite), en gardant la vue sur elle.
    func nudgePlayhead(by frames: Int64) {
        let f = max(0, min(total, transport.playhead + frames))
        seek(to: f)
        if transport.playhead < scroll || transport.playhead > scroll + visibleFrames { scrollTo(centerFrame: f) }
        redraw.send()
    }
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

    /// Noms des échantillons par couleur (légende de l'inspecteur).
    @Published var sourceNames: [Int: String] = [:]
    var tintsInUse: [Int] { Array(Set(model.clips.map { $0.tint })).sorted() }

    /// Importe des échantillons à la tête de lecture (si elle a été placée) ou à la suite du montage. Fréquence et canaux sont
    /// adaptés au besoin. Chaque fichier garde sa couleur ; l'ensemble est sélectionné après l'import.
    func importFiles(_ urls: [URL]) {
        guard working == nil, !urls.isEmpty else { return }
        if transport.isPlaying { pause() }
        let at = playheadMoved ? min(transport.playhead, total) : total
        let rate = info.sampleRate, ch = Int(info.channels)
        let token = CancelToken(); workToken = token
        working = Working(title: Loc.t("importing"), progress: 0)
        Task.detached { [weak self] in
            var prepared: [(URL, URL, Int64)] = []        // original, fichier utilisé, trames
            do {
                for (k, u) in urls.enumerated() {
                    let r = try Filters.conform(u, rate: rate, channels: ch, token: token) { p in
                        Task { @MainActor in self?.working?.progress = (Double(k) + p) / Double(urls.count) }
                    }
                    guard r.frames > 0 else { continue }
                    prepared.append((u, r.url, r.frames))
                }
                await MainActor.run { self?.finishImport(prepared, at: at) }
            } catch {
                await MainActor.run { self?.failWork(error) }
            }
        }
    }
    private func finishImport(_ list: [(URL, URL, Int64)], at: Int64) {
        working = nil
        guard !list.isEmpty else { return }
        var tint = (model.clips.map { $0.tint }.max() ?? 0)
        var clips: [Clip] = []
        for (orig, used, frames) in list {
            tint = tint % 4 + 1
            var c = Clip(source: used, start: 0, length: frames); c.tint = tint
            sourceNames[tint] = orig.deletingPathExtension().lastPathComponent
            startPeaks(for: used)
            clips.append(c)
        }
        let len = clips.reduce(0) { $0 + $1.length }
        edited { model.insert(clips, at: at) }
        transport.playhead = at; playheadMoved = true
        selection = at..<(at + len)
        scrollTo(centerFrame: at + len / 2)
        redraw.send()
    }

    // MARK: - Export

    func export(whole: Bool = false) {
        let sel = whole ? nil : selection
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

