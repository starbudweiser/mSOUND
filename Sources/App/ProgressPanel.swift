import SwiftUI
import AppKit
import MSoundEngine
import MSoundShared

/// Couleurs Flat Round : sombre, ou clair sable.
enum Theme {
    private static func dyn(_ dark: UInt32, _ light: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { a in
            let isDark = a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let v = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
        })
    }
    static let bg = dyn(0x131316, 0xECE3D0)
    static let card = dyn(0x232327, 0xF7F1E3)
    static let ctl = dyn(0x2C2C31, 0xE1D6BD)
    static let text = dyn(0xF5F5F7, 0x2B2619)
    static let text2 = dyn(0x98989F, 0x7D725A)
    static let accent = dyn(0x0A84FF, 0xB9731A)
    static let ok = dyn(0x30D158, 0x3F8F5A)
    static let warn = dyn(0xFF9F0A, 0xB7791F)
    static let danger = dyn(0xFF453A, 0xC0392B)
    static let brand = Color(red: 0x14 / 255, green: 0xB8 / 255, blue: 0xA6 / 255)
    static let radius: CGFloat = 4
}

struct FlatButton: ButtonStyle {
    var primary = false
    func makeBody(configuration c: Configuration) -> some View {
        c.label.font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(primary ? Theme.accent : Theme.ctl)
            .foregroundColor(primary ? .white : Theme.text)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            .opacity(c.isPressed ? 0.75 : 1)
    }
}

struct ProgressRowView: View {
    let row: ProgressModel.Row
    var body: some View {
        HStack(spacing: 12) {
            Text(row.format.rawValue.uppercased())
                .font(.system(size: 9.5, weight: .bold)).foregroundColor(.white)
                .frame(width: 38, height: 34)
                .background(Theme.ok.opacity(0.9)).clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            VStack(alignment: .leading, spacing: 5) {
                Text(row.name).font(.system(size: 12.5, weight: .semibold)).foregroundColor(Theme.text).lineLimit(1).truncationMode(.middle)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Theme.ctl)
                        RoundedRectangle(cornerRadius: 3).fill(barColor).frame(width: g.size.width * row.progress)
                    }
                }.frame(height: 6)
                if case .failed(let m) = row.state { Text(m).font(.system(size: 11)).foregroundColor(Theme.danger).lineLimit(2) }
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text(status).font(.system(size: 11, weight: .semibold)).foregroundColor(statusColor)
                if !row.sizes.isEmpty { Text(row.sizes).font(.system(size: 11)).foregroundColor(Theme.text2) }
            }.frame(width: 120, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }
    private var barColor: Color { if case .done = row.state { return Theme.ok }; if case .failed = row.state { return Theme.danger }; return Theme.accent }
    private var status: String {
        switch row.state {
        case .waiting: return Loc.t("waiting")
        case .running: return "\(Loc.t("running")) · \(Int(row.progress * 100)) %"
        case .done: return Loc.t("done")
        case .failed: return Loc.t("failed")
        case .cancelled: return Loc.t("cancelled")
        case .skipped: return Loc.t("sameFormat")
        }
    }
    private var statusColor: Color {
        switch row.state { case .done: return Theme.ok; case .failed: return Theme.danger; default: return Theme.text2 }
    }
}

struct ProgressContentView: View {
    @ObservedObject var model: ProgressModel
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                (Text("m").foregroundColor(Theme.brand) + Text("SOUND").foregroundColor(Theme.text)).font(.system(size: 15, weight: .bold))
                Spacer()
                Text(Loc.t("summary", model.finished, model.rows.count)).font(.system(size: 12)).foregroundColor(Theme.text2)
            }
            ScrollView { VStack(spacing: 6) { ForEach(model.rows) { ProgressRowView(row: $0) } } }
                .frame(maxHeight: 320)
            HStack {
                Spacer()
                if model.isRunning { Button(Loc.t("cancel")) { model.cancelAll() }.buttonStyle(FlatButton()) }
                Button(Loc.t("showInFinder")) { NSWorkspace.shared.activateFileViewerSelecting(model.outputs) }
                    .buttonStyle(FlatButton(primary: true)).disabled(model.outputs.isEmpty)
            }
        }
        .padding(16).frame(width: 560).background(Theme.bg)
    }
}

/// Petite fenêtre flottante qui n'active jamais l'appli (mode silencieux).
@MainActor
final class ProgressPanelController {
    let model = ProgressModel()
    private let panel: NSPanel
    private var closeWork: DispatchWorkItem?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 200),
                        styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
                        backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar   // au-dessus des fenêtres normales
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        let host = NSHostingController(rootView: ProgressContentView(model: model))
        host.sizingOptions = [.preferredContentSize]
        panel.contentViewController = host
        model.onAllFinished = { [weak self] in self?.scheduleClose() }
    }

    func add(files: [URL], format: AudioFormat) {
        closeWork?.cancel()
        model.add(files: files, format: format)
        if !panel.isVisible { place() }
        panel.orderFrontRegardless()
    }

    /// En haut à droite de l'écran où se trouve le pointeur (là où l'utilisateur travaille), sans prendre le focus.
    private func place() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let f = screen?.visibleFrame else { panel.center(); return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: f.maxX - size.width - 24, y: f.maxY - size.height - 24))
    }

    private func scheduleClose() {
        guard !model.hasFailure else { return }   // les erreurs restent affichées
        let w = DispatchWorkItem { [weak self] in
            guard let self, !self.model.isRunning else { return }
            self.panel.orderOut(nil)
        }
        closeWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: w)
    }
}
