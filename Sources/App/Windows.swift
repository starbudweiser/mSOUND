import AppKit
import SwiftUI
import MSoundEngine
import MSoundShared

/// Thème de l'appli : automatique (système), sombre ou sable (clair).
enum AppTheme {
    static var current: String { UserDefaults.standard.string(forKey: "theme") ?? "system" }
    @MainActor static func apply() {
        switch current {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "sand": NSApp.appearance = NSAppearance(named: .aqua)
        default: NSApp.appearance = nil
        }
    }
}

/// Fenêtres secondaires (À propos, Réglages) : une seule instance chacune, centrées sur l'éditeur ou l'écran.
@MainActor final class SecondaryWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let make: () -> NSView
    private let size: NSSize
    private let title: () -> String
    var onVisibilityChange: (() -> Void)?

    init(size: NSSize, title: @escaping () -> String, make: @escaping () -> NSView) { self.size = size; self.title = title; self.make = make }

    var isVisible: Bool { window?.isVisible ?? false }
    func close() { window?.close() }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.standardWindowButton(.miniaturizeButton)?.isHidden = true
            w.standardWindowButton(.zoomButton)?.isHidden = true
            let host = NSHostingView(rootView: AnyView(NSViewWrapper(view: make())))
            host.sizingOptions = []
            w.contentView = host
            w.delegate = self
            window = w
        }
        window?.title = title()
        if let w = window, !w.isVisible {
            if let host = NSApp.windows.first(where: { $0 !== w && $0.isVisible && $0.canBecomeMain }) {
                let f = host.frame
                w.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.midY - size.height / 2))
            } else { w.center() }
        }
        onVisibilityChange?()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) { DispatchQueue.main.async { self.onVisibilityChange?() } }
}

private struct NSViewWrapper: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ v: NSView, context: Context) {}
}

func brandName(_ size: CGFloat) -> some View {
    (Text("m").foregroundColor(Theme.brand) + Text("SOUND").foregroundColor(Theme.text)).font(.system(size: size, weight: .bold))
}

// MARK: - À propos

struct AboutView: View {
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?" }
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84)
            brandName(17)
            Text(Loc.t("aboutVersion", version, build)).font(.system(size: 12)).foregroundColor(Theme.text2).padding(.bottom, 6)
            Group {
                Text(Loc.t("aboutTagline")).foregroundColor(Theme.text)
                Text(Loc.t("aboutCollection")).foregroundColor(Theme.text2)
                Text(Loc.t("aboutAuthors")).fontWeight(.bold).foregroundColor(Theme.text)
                Text(Loc.t("aboutLicense")).foregroundColor(Theme.text)
                Text(Loc.t("aboutDisclaimer")).foregroundColor(Theme.text2)
                Text(Loc.t("aboutCredit")).foregroundColor(Theme.text2)
            }.font(.system(size: 12)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 300)
            Button { NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/starbudweiser")!) } label: {
                Text("♥ " + Loc.t("support")).font(.system(size: 12, weight: .medium)).underline().foregroundColor(Theme.text)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 28).padding(.top, 44).padding(.bottom, 28).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }
}

// MARK: - Réglages

struct SettingsView: View {
    @AppStorage("theme") private var theme = "system"
    @AppStorage("bitrate") private var bitrate = 256
    @State private var formats = Prefs.menuFormats(domain: Bundle.main.bundleIdentifier ?? "fr.stephan.msound")
    @ObservedObject private var updater = Updater.shared
    @AppStorage("autoUpdate") private var auto = true

    private func toggle(_ f: String) {
        var s = Set(formats)
        if s.contains(f) { if s.count > 1 { s.remove(f) } } else { s.insert(f) }
        formats = Prefs.defaultMenuFormats.filter { s.contains($0) }
        UserDefaults.standard.set(formats, forKey: "menuFormats")
    }

    private var updStatus: String {
        switch updater.state {
        case .idle: return Loc.t("updVersion", updater.currentVersion)
        case .checking: return Loc.t("updChecking")
        case .upToDate: return Loc.t("updUpToDate", updater.currentVersion)
        case .available(let v): return Loc.t("updAvailable", v)
        case .downloading: return Loc.t("updDownloading")
        case .failed(let e): return Loc.t("updFailed", e)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            brandName(15).padding(.top, 6)
            Card(title: Loc.t("setFinder")) {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 8) {
                    ForEach(Prefs.defaultMenuFormats, id: \.self) { f in
                        Toggle(f == "edit" ? Loc.t("editWith") : Prefs.displayName(f), isOn: Binding(get: { formats.contains(f) }, set: { _ in toggle(f) }))
                            .toggleStyle(.checkbox).font(.system(size: 12.5)).foregroundColor(Theme.text)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(Loc.t("setFinderHint")).font(.system(size: 11.5)).foregroundColor(Theme.text2)
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            }
            Card(title: Loc.t("setShortcuts")) { ShortcutSettings() }
            Card(title: Loc.t("recFolder")) { RecordFolderSetting() }
            Card(title: Loc.t("setQuality")) {
                HStack(spacing: 4) {
                    ForEach([128, 192, 256, 320], id: \.self) { k in Button("\(k) kb/s") { bitrate = k }.buttonStyle(ChipStyle(on: bitrate == k)) }
                    Spacer()
                }
            }
            Card(title: Loc.t("setTheme")) {
                HStack(spacing: 4) {
                    ForEach([("system", "themeSystem"), ("dark", "themeDark"), ("sand", "themeSand")], id: \.0) { t in
                        Button(Loc.t(t.1)) { theme = t.0; AppTheme.apply() }.buttonStyle(ChipStyle(on: theme == t.0))
                    }
                    Spacer()
                }
            }
            Card(title: Loc.t("updTitle")) {
                Toggle(Loc.t("updAuto"), isOn: $auto).toggleStyle(.checkbox).font(.system(size: 12.5)).foregroundColor(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Button(Loc.t("updCheck")) { Task { await updater.check() } }.buttonStyle(FlatButton())
                        .disabled(updater.state == .checking || updater.state == .downloading)
                    if case .available(let v) = updater.state {
                        Button(Loc.t("updInstall", v)) { Task { await updater.install() } }.buttonStyle(FlatButton(primary: true)).disabled(Updater.busy)
                    }
                    Spacer()
                }.padding(.top, 2)
                Text(updStatus + (Updater.busy && updater.state != .idle && updater.state != .upToDate ? "\n" + Loc.t("updBusy") : ""))
                    .font(.system(size: 11.5)).foregroundColor(Theme.text2).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 28).padding(.top, 36).padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.bg)
    }
}

/// Dossier où sont rangés les enregistrements du micro.
struct RecordFolderSetting: View {
    @AppStorage("recordFolder") private var folder = ""
    var body: some View {
        HStack {
            Text((folder.isEmpty ? Recorder.folder.path : folder).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                .font(.system(size: 12)).foregroundColor(Theme.text).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button(Loc.t("recChoose")) {
                let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
                p.directoryURL = Recorder.folder
                if p.runModal() == .OK, let u = p.url { folder = u.path }
            }.buttonStyle(FlatButton())
        }
    }
}
