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

struct TimeView: View {
    @ObservedObject var transport: Transport
    let rate: Double
    var body: some View {
        Text(timeString(transport.playhead, rate: rate))
            .font(.system(size: 17, weight: .semibold, design: .monospaced)).foregroundColor(Theme.text)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }
}

struct TransportBar: View {
    @ObservedObject var transport: Transport
    let doc: EditorDocument
    var body: some View {
        HStack(spacing: 6) {
            IconButton(symbol: "backward.end.fill", help: Loc.t("toStart"), enabled: true) { doc.seek(to: 0) }
            Button { doc.togglePlay() } label: {
                Image(systemName: transport.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 13, weight: .medium)).frame(width: 30, height: 24)
            }.buttonStyle(FlatButton(primary: true)).help(Loc.t("playPause"))
            IconButton(symbol: "stop.fill", help: "Stop", enabled: true) { doc.stop() }
            IconButton(symbol: "forward.end.fill", help: Loc.t("toEnd"), enabled: true) { doc.seek(to: doc.total) }
            TimeView(transport: transport, rate: doc.rate).padding(.leading, 6)
        }
    }
}

struct EditorView: View {
    @ObservedObject var doc: EditorDocument
    var onOpenFiles: ([URL]) -> Void = { _ in }
    @State private var dropping = false

    private var infoLine: String {
        let ch = doc.info.channels == 1 ? "mono" : doc.info.channels == 2 ? "stéréo" : "\(doc.info.channels) canaux"
        return "\(String(format: "%g", doc.info.sampleRate / 1000)) kHz · \(doc.info.bitDepth) bits · \(ch) · \(timeString(doc.total, rate: doc.rate, ms: false))"
    }

    var body: some View {
        let _ = doc.revision
        VStack(spacing: 0) {
            // Barre du haut
            HStack(spacing: 12) {
                (Text("m").foregroundColor(Theme.brand) + Text("SOUND").foregroundColor(Theme.text)).font(.system(size: 15, weight: .bold))
                Text("\(doc.url.lastPathComponent) · \(infoLine)").font(.system(size: 12)).foregroundColor(Theme.text2).lineLimit(1)
                Spacer()
                TransportBar(transport: doc.transport, doc: doc)
            }.padding(.leading, 84).padding(.trailing, 28).frame(height: 56)

            HStack(alignment: .top, spacing: 24) {
                sidebar.frame(width: 240)
                VStack(spacing: 12) {
                    toolbar
                    WaveformRepresentable(doc: doc).frame(minHeight: 200)
                    statusLine
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                inspector.frame(width: 260)
            }.padding(.horizontal, 28).padding(.vertical, 8).frame(maxHeight: .infinity)
            exportBar
        }
        .frame(minWidth: 1200, minHeight: 620)
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
                    DispatchQueue.main.async { onOpenFiles([u]) }
                }
            }
            return true
        }
        .alert(doc.message ?? "", isPresented: Binding(get: { doc.message != nil }, set: { if !$0 { doc.message = nil } })) { Button("OK") {} }
    }

    // MARK: Zones
    private var toolbar: some View {
        let hasSel = doc.selection != nil
        return HStack(spacing: 4) {
            IconButton(symbol: "arrow.uturn.backward", help: Loc.t("undo"), enabled: doc.canUndo) { doc.undo() }
            IconButton(symbol: "arrow.uturn.forward", help: Loc.t("redo"), enabled: doc.canRedo) { doc.redo() }
            Divider().frame(height: 18).padding(.horizontal, 4)
            IconButton(symbol: "scissors", help: Loc.t("cut"), enabled: hasSel) { doc.cut() }
            IconButton(symbol: "doc.on.doc", help: Loc.t("copy"), enabled: hasSel) { doc.copySel() }
            IconButton(symbol: "doc.on.clipboard", help: Loc.t("paste"), enabled: !EditorDocument.clipboard.isEmpty) { doc.paste() }
            IconButton(symbol: "trash", help: Loc.t("delete"), enabled: hasSel) { doc.deleteSel() }
            IconButton(symbol: "crop", help: Loc.t("keep"), enabled: hasSel) { doc.keepSel() }
            Divider().frame(height: 18).padding(.horizontal, 4)
            IconButton(symbol: "flag", help: Loc.t("marker") + " (M)", enabled: true) { doc.addMarker() }
            IconButton(symbol: "plus.rectangle.on.rectangle", help: Loc.t("merge"), enabled: true) { pickAndAppend() }
            Spacer()
            IconButton(symbol: "minus.magnifyingglass", help: Loc.t("zoomOut"), enabled: true) { doc.zoom(factor: 2, anchorX: doc.viewWidth / 2) }
            IconButton(symbol: "plus.magnifyingglass", help: Loc.t("zoomIn"), enabled: true) { doc.zoom(factor: 0.5, anchorX: doc.viewWidth / 2) }
            IconButton(symbol: "arrow.left.and.right", help: Loc.t("fit"), enabled: true) { doc.fit() }
        }
    }

    private var statusLine: some View {
        HStack {
            if let s = doc.selection {
                Text("\(Loc.t("selection")) \(timeString(s.lowerBound, rate: doc.rate)) → \(timeString(s.upperBound, rate: doc.rate)) · \(timeString(s.upperBound - s.lowerBound, rate: doc.rate, ms: false))")
            } else { Text(Loc.t("whole")) }
            Spacer()
        }.font(.system(size: 11.5)).foregroundColor(Theme.text2)
    }

    private var sidebar: some View {
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
                .frame(maxWidth: .infinity, alignment: .center).padding(.top, 6)   // bouton centré en bas de la carte
        }.frame(maxHeight: .infinity)
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card(title: Loc.t("file")) {
                KV(k: "Format", v: doc.url.pathExtension.uppercased())
                KV(k: Loc.t("sampleRate"), v: "\(String(format: "%g", doc.info.sampleRate / 1000)) kHz")
                KV(k: Loc.t("channels"), v: "\(doc.info.channels)")
                KV(k: Loc.t("bitDepth"), v: "\(doc.info.bitDepth) bits")
                KV(k: Loc.t("size"), v: fileSize())
            }
            Card(title: Loc.t("montage")) {
                KV(k: Loc.t("duration"), v: timeString(doc.total, rate: doc.rate, ms: false))
                KV(k: Loc.t("segments"), v: "\(doc.model.clips.count)")
                KV(k: Loc.t("markers"), v: "\(doc.model.markers.count)")
            }
            Card(title: Loc.t("selection"), fill: true) {
                if let s = doc.selection {
                    KV(k: Loc.t("start"), v: timeString(s.lowerBound, rate: doc.rate))
                    KV(k: Loc.t("end"), v: timeString(s.upperBound, rate: doc.rate))
                    KV(k: Loc.t("duration"), v: timeString(s.upperBound - s.lowerBound, rate: doc.rate))
                } else {
                    Spacer()
                    Text(Loc.t("noSelection")).font(.system(size: 12)).multilineTextAlignment(.center).foregroundColor(Theme.text2)
                        .frame(maxWidth: .infinity)
                    Spacer()
                }
            }.frame(maxHeight: .infinity)
        }
    }

    private var exportBar: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(Loc.t("exportTitle").uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.5).foregroundColor(Theme.text2)
                HStack(spacing: 4) {
                    ForEach(AudioFormat.allCases, id: \.self) { f in
                        Button(Prefs.displayName(f.rawValue)) { doc.exportFormat = f }
                            .buttonStyle(ChipStyle(on: doc.exportFormat == f))
                    }
                }
            }
            if !doc.exportFormat.isLossless {
                VStack(alignment: .leading, spacing: 5) {
                    Text(Loc.t("quality").uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.5).foregroundColor(Theme.text2)
                    HStack(spacing: 4) {
                        ForEach([128, 192, 256, 320], id: \.self) { k in
                            Button("\(k)") { doc.exportKbps = k }.buttonStyle(ChipStyle(on: doc.exportKbps == k))
                        }
                    }
                }
            }
            Spacer()
            Text("\(Loc.t("scope")) : ").font(.system(size: 12)).foregroundColor(Theme.text2)
                + Text(doc.selection != nil ? Loc.t("selection") : Loc.t("whole")).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text)
            Button(doc.selection != nil ? Loc.t("exportSelection") : Loc.t("exportWhole")) { doc.export() }
                .buttonStyle(FlatButton(primary: true))
        }
        .padding(.horizontal, 28).padding(.vertical, 14).background(Theme.card.opacity(0.6))
    }

    // MARK: Utilitaires
    private func fileSize() -> String {
        let b = (try? FileManager.default.attributesOfItem(atPath: doc.url.path)[.size] as? Int) ?? 0
        return String(format: "%.1f Mo", Double(b) / 1_048_576)
    }
    private func pickAndAppend() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.audio]; p.allowsMultipleSelection = false
        if p.runModal() == .OK, let u = p.url { doc.appendFile(u) }
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
