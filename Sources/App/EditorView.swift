import SwiftUI
import UniformTypeIdentifiers
import AppKit
import MSoundEngine
import MSoundShared

struct WaveformRepresentable: NSViewRepresentable {
    let doc: EditorDocument
    func makeNSView(context: Context) -> WaveformView { WaveformView(doc: doc) }
    func updateNSView(_ v: WaveformView, context: Context) { v.needsDisplay = true }
}

struct OverviewRepresentable: NSViewRepresentable {
    let doc: EditorDocument
    func makeNSView(context: Context) -> OverviewView { OverviewView(doc: doc) }
    func updateNSView(_ v: OverviewView, context: Context) { v.needsDisplay = true }
}

/// Bouton d'outil : icône seule, fond au survol, légende en infobulle.
struct ToolIcon: View {
    let symbol: String, title: String, enabled: Bool, action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium)).frame(width: 32, height: 30)
                .background(hover && enabled ? Theme.ctl : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius)).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundColor(Theme.text).disabled(!enabled).opacity(enabled ? 1 : 0.32)
            .onHover { hover = $0 }.help(title)
    }
}

/// Groupe d'outils sur une pastille.
struct ToolGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 0) { content }.padding(2).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }
}

struct ZoomSlider: View {
    @ObservedObject var zoom: ZoomState
    let doc: EditorDocument
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "minus.magnifyingglass").foregroundColor(Theme.text2)
            Slider(value: Binding(get: { zoom.level }, set: { doc.setZoomLevel($0) }), in: 0...1).frame(width: 90).tint(Theme.accent)
            Image(systemName: "plus.magnifyingglass").foregroundColor(Theme.text2)
        }.font(.system(size: 12))
    }
}

/// Barre du bas : zoom à gauche, lecture au centre, volume à droite.
/// Bouton d'enregistrement du micro (rouge) : démarre ou arrête.
struct RecordButton: View {
    @ObservedObject var rec = Recorder.shared
    var body: some View {
        Button { (NSApp.delegate as? AppDelegate)?.recordAction() } label: {
            Image(systemName: rec.isRecording ? "stop.circle.fill" : "record.circle").font(.system(size: 18, weight: .medium))
                .foregroundColor(Theme.danger).frame(width: 32, height: 30).contentShape(Rectangle())
        }.buttonStyle(.plain).help(Loc.t("recStart") + "  ⌘R")
    }
}

struct BottomTransport: View {
    @ObservedObject var transport: Transport
    @ObservedObject var doc: EditorDocument
    var body: some View {
        let rate = doc.rate
        let remaining = (doc.selection?.upperBound ?? doc.total) - transport.playhead
        ZStack {
            HStack {
                ZoomSlider(zoom: doc.zoomState, doc: doc)
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill").foregroundColor(Theme.text2)
                    Slider(value: Binding(get: { Double(doc.volume) }, set: { doc.volume = Float($0) }), in: 0...1).frame(width: 90).tint(Theme.accent)
                    Image(systemName: "speaker.wave.3.fill").foregroundColor(Theme.text2)
                }.font(.system(size: 12))
            }
            HStack(spacing: 10) {
                RecordButton()
                Text(timeString(transport.playhead, rate: rate)).font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundColor(Theme.text).frame(width: 96, alignment: .trailing)
                ToolIcon(symbol: "backward.end.fill", title: Loc.t("toStart"), enabled: true) { doc.seek(to: 0) }
                Button { doc.togglePlay() } label: {
                    Image(systemName: transport.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 15, weight: .medium)).frame(width: 46, height: 30)
                }.buttonStyle(FlatButton(primary: true)).help(Loc.t("playPause"))
                ToolIcon(symbol: "stop.fill", title: "Stop", enabled: true) { doc.stop() }
                ToolIcon(symbol: "forward.end.fill", title: Loc.t("toEnd"), enabled: true) { doc.seek(to: doc.total) }
                Text("\u{2212}" + timeString(max(0, remaining), rate: rate)).font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundColor(Theme.text2).frame(width: 96, alignment: .leading)
            }
        }
        .padding(.horizontal, 24).frame(height: 56)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }
}

func timeString(_ frames: Int64, rate: Double, ms: Bool = true) -> String {
    let t = max(0, Double(frames) / max(rate, 1))
    let h = Int(t) / 3600, m = (Int(t) % 3600) / 60, s = Int(t) % 60
    let base = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    return ms ? base + String(format: ".%03d", Int((t - t.rounded(.down)) * 1000)) : base
}

struct IconButton: View {
    let symbol: String, help: String, enabled: Bool, action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 13, weight: .medium)).frame(width: 30, height: 24) }
            .buttonStyle(FlatButton()).disabled(!enabled).opacity(enabled ? 1 : 0.4).help(help)
    }
}

struct Card<Content: View>: View {
    let title: String
    var fill = false
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.5).foregroundColor(Theme.text2)
            VStack(spacing: 6) { content }.frame(maxHeight: fill ? .infinity : nil, alignment: .top)
                .padding(.horizontal, 24).padding(.vertical, 20).frame(maxWidth: .infinity)
                .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        }
    }
}

struct KV: View {
    let k: String, v: String
    var body: some View {
        HStack { Text(k).foregroundColor(Theme.text2); Spacer(); Text(v).fontWeight(.semibold).foregroundColor(Theme.text) }
            .font(.system(size: 12))
    }
}

struct EditorView: View {
    @ObservedObject var doc: EditorDocument
    @ObservedObject var session: EditorSession
    @State private var dropping = false
    @State private var fxOpen = false
    @ObservedObject private var rec = Recorder.shared
    @AppStorage("inspectorVisible") private var inspectorVisible = false

    private var infoLine: String {
        let ch = doc.info.channels == 1 ? Loc.t("chMono") : doc.info.channels == 2 ? Loc.t("chStereo") : Loc.t("chMany", doc.info.channels)
        return "\(String(format: "%g", doc.info.sampleRate / 1000)) kHz · \(doc.info.bitDepth) bits · \(ch) · \(timeString(doc.total, rate: doc.rate, ms: false))"
    }

    var body: some View {
        let _ = doc.revision
        VStack(spacing: 0) {
            titleBar
                .alert(rec.error ?? "", isPresented: Binding(get: { rec.error != nil }, set: { if !$0 { rec.error = nil } })) { Button("OK") {} }
            if session.docs.count > 1 { TimelineTabs(session: session) }
            toolRow
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 12) {
                    if rec.isRecording {
                        RecordingPanel { rec.stop(save: true) }
                    } else {
                        OverviewRepresentable(doc: doc).frame(height: 44).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                        WaveformRepresentable(doc: doc).frame(minHeight: 200).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                    }
                    BottomTransport(transport: doc.transport, doc: doc)
                }.frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                if inspectorVisible { inspector.frame(width: 260) }
            }.padding(.horizontal, 28).padding(.top, 4).padding(.bottom, 24).frame(maxHeight: .infinity)
        }
        .frame(minWidth: 1120, minHeight: 560)
        .background(Theme.bg)
        .overlay {
            if dropping {
                RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .background(Theme.accent.opacity(0.12)).padding(10).allowsHitTesting(false)
                    .overlay(Text(Loc.t("dropHint")).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text))
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            for p in providers {
                p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let d = item as? Data, let u = URL(dataRepresentation: d, relativeTo: nil),
                          Prefs.audioExtensions.contains(u.pathExtension.lowercased()) else { return }
                    DispatchQueue.main.async { session.open([u]) }
                }
            }
            return true
        }
        .alert(doc.message ?? "", isPresented: Binding(get: { doc.message != nil }, set: { if !$0 { doc.message = nil } })) { Button("OK") {} }
    }

    // MARK: Zones

    /// Zone de la barre de titre : nom du fichier au centre, export à droite.
    /// Barre de titre sur une seule ligne : nom de l'appli, fichier et sa fiche technique, export à droite.
    private var titleBar: some View {
        HStack(spacing: 16) {
            brandName(15)
            HStack(spacing: 10) {
                Text(doc.url.lastPathComponent).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                    .lineLimit(1).truncationMode(.middle).layoutPriority(1)
                Text(infoLine).font(.system(size: 11.5)).foregroundColor(Theme.text2).lineLimit(1).fixedSize()
            }.frame(maxWidth: .infinity, alignment: .center)
            exportCluster
        }.padding(.leading, 84).padding(.trailing, 28).frame(height: 56)
    }

    private var exportCluster: some View {
        HStack(spacing: 8) {
            Menu {
                Picker(Loc.t("exportTitle"), selection: $doc.exportFormat) {
                    ForEach(AudioFormat.allCases, id: \.self) { f in Text(Prefs.displayName(f.rawValue)).tag(f) }
                }.pickerStyle(.inline)
                if !doc.exportFormat.isLossless {
                    Picker(Loc.t("quality"), selection: $doc.exportKbps) {
                        ForEach([128, 192, 256, 320], id: \.self) { k in Text("\(k) kb/s").tag(k) }
                    }.pickerStyle(.inline)
                }
            } label: {
                Text(Prefs.displayName(doc.exportFormat.rawValue) + (doc.exportFormat.isLossless ? "" : " · \(doc.exportKbps)"))
                    .font(.system(size: 12.5, weight: .medium)).foregroundColor(Theme.text)
                    .padding(.horizontal, 12).frame(height: 30).background(Theme.ctl)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            Button(doc.selection != nil ? Loc.t("exportSelection") : Loc.t("exportWhole")) { doc.export() }
                .buttonStyle(FlatButton(primary: true))
        }
    }

    /// Rangée d'outils : groupes sur pastilles, icônes seules ; sélection à droite.
    private var toolRow: some View {
        let hasSel = doc.selection != nil
        return HStack(spacing: 10) {
            ToolGroup {
                ToolIcon(symbol: "arrow.uturn.backward", title: Loc.t("undo"), enabled: doc.canUndo) { doc.undo() }
                ToolIcon(symbol: "arrow.uturn.forward", title: Loc.t("redo"), enabled: doc.canRedo) { doc.redo() }
            }
            ToolGroup {
                ToolIcon(symbol: "scissors", title: Loc.t("cut"), enabled: hasSel) { doc.cut() }
                ToolIcon(symbol: "doc.on.doc", title: Loc.t("copy"), enabled: hasSel) { doc.copySel() }
                ToolIcon(symbol: "doc.on.clipboard", title: Loc.t("paste"), enabled: !EditorDocument.clipboard.isEmpty) { doc.paste() }
                ToolIcon(symbol: "trash", title: Loc.t("delete"), enabled: hasSel) { doc.deleteSel() }
                ToolIcon(symbol: "crop", title: Loc.t("keep"), enabled: hasSel) { doc.keepSel() }
            }
            ToolGroup {
                Button { fxOpen.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 14, weight: .medium))
                        Text(Loc.t("menuEffects")).font(.system(size: 12.5, weight: .medium))
                    }.foregroundColor(Theme.text).padding(.horizontal, 10).frame(height: 30).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(doc.working != nil)
                    .popover(isPresented: $fxOpen, arrowEdge: .bottom) { EffectsPanel(doc: doc, session: session) { fxOpen = false } }
                ShortcutButtons(doc: doc, session: session)
            }
            ToolGroup {
                ToolIcon(symbol: "flag", title: Loc.t("marker"), enabled: true) { doc.addMarker() }
                Menu {
                    Button(Loc.t("insertHere")) { pickAndImport() }
                    Button(Loc.t("newTimelines")) { pickAndOpen() }
                } label: {
                    Image(systemName: "plus.rectangle.on.rectangle").font(.system(size: 14, weight: .medium)).frame(width: 32, height: 30)
                        .foregroundColor(Theme.text).contentShape(Rectangle())
                }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().help(Loc.t("mergeShort"))
                ToolIcon(symbol: "arrow.left.and.right", title: Loc.t("fit"), enabled: true) { doc.fit() }
            }
            Spacer(minLength: 12)
            if let w = doc.working {
                Text("\(w.title) — \(Int(w.progress * 100)) %").font(.system(size: 12, weight: .medium)).foregroundColor(Theme.text).lineLimit(1)
                ProgressView(value: w.progress).progressViewStyle(.linear).tint(Theme.accent).frame(width: 120)
                Button(Loc.t("cancel")) { doc.cancelWork() }.buttonStyle(FlatButton())
            } else if let s = doc.selection {
                Text("\(timeString(s.lowerBound, rate: doc.rate)) → \(timeString(s.upperBound, rate: doc.rate))  ·  \(timeString(s.upperBound - s.lowerBound, rate: doc.rate, ms: false))")
                    .font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundColor(Theme.text2).lineLimit(1)
            }
            ToolGroup {
                ToolIcon(symbol: "sidebar.right", title: Loc.t("inspector"), enabled: true) { inspectorVisible.toggle() }
                    .foregroundColor(inspectorVisible ? Theme.accent : Theme.text)
            }
        }.padding(.horizontal, 28).padding(.bottom, 8).frame(height: 44)
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card(title: Loc.t("markers"), fill: true) {
                if doc.model.markers.isEmpty {
                    Spacer()
                    Text(Loc.t("noMarkers")).font(.system(size: 12)).multilineTextAlignment(.center).foregroundColor(Theme.text2)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(doc.model.markers) { m in
                                HStack {
                                    Text(m.name).foregroundColor(Theme.text)
                                    Spacer()
                                    Text(timeString(m.frame, rate: doc.rate, ms: false)).foregroundColor(Theme.text2)
                                }
                                .font(.system(size: 12)).padding(.vertical, 5).contentShape(Rectangle())
                                .onTapGesture { doc.selection = nil; doc.seek(to: m.frame) }
                                .contextMenu { Button(Loc.t("delete")) { doc.removeMarker(m.id) } }
                            }
                        }
                    }.frame(maxHeight: .infinity)
                }
                Button(Loc.t("detectSilences")) { doc.markSilences() }.buttonStyle(FlatButton())
                    .frame(maxWidth: .infinity, alignment: .center).padding(.top, 6)
            }.frame(maxHeight: .infinity)
            if doc.tintsInUse.count > 1 {
                Card(title: Loc.t("samples")) {
                    ForEach(doc.tintsInUse, id: \.self) { t in
                        HStack(spacing: 8) {
                            Circle().fill(Color(nsColor: WavePalette.color(t, dark: true))).frame(width: 9, height: 9)
                            Text(t == 0 ? doc.name : (doc.sourceNames[t] ?? "—")).font(.system(size: 12)).foregroundColor(Theme.text)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                        }
                    }
                }
            }
            Card(title: Loc.t("file")) {
                KV(k: "Format", v: doc.url.pathExtension.uppercased())
                KV(k: Loc.t("sampleRate"), v: "\(String(format: "%g", doc.info.sampleRate / 1000)) kHz")
                KV(k: Loc.t("channels"), v: "\(doc.info.channels)")
                KV(k: Loc.t("bitDepth"), v: "\(doc.info.bitDepth) bits")
                KV(k: Loc.t("size"), v: fileSize())
                KV(k: Loc.t("segments"), v: "\(doc.model.clips.count)")
            }
        }
    }

    // MARK: Utilitaires
    private func fileSize() -> String {
        let b = (try? FileManager.default.attributesOfItem(atPath: doc.url.path)[.size] as? Int) ?? 0
        return Loc.size(b)
    }
    private func pickAndOpen() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.audio]; p.allowsMultipleSelection = true
        if p.runModal() == .OK { session.open(p.urls) }
    }
    private func pickAndImport() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.audio]; p.allowsMultipleSelection = true
        if p.runModal() == .OK { doc.importFiles(p.urls) }
    }
}

struct ChipStyle: ButtonStyle {
    let on: Bool
    func makeBody(configuration c: Configuration) -> some View {
        c.label.font(.system(size: 12, weight: on ? .semibold : .regular))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(on ? Theme.accent : Theme.ctl)
            .foregroundColor(on ? .white : Theme.text)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }
}
