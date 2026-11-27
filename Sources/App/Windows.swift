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

/// Fenêtres secondaires (À propos, Réglages, Accueil) : une seule instance chacune, centrées sur l'éditeur ou l'écran ;
/// hauteur = celle du contenu (jamais fixe), largeur imposée pour que les marges tiennent dans les quatre langues.
@MainActor final class SecondaryWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var content: NSView?
    private let make: () -> NSView
    private let width: CGFloat
    private let title: () -> String
    var onVisibilityChange: (() -> Void)?

    init(width: CGFloat, title: @escaping () -> String, make: @escaping () -> NSView) { self.width = width; self.title = title; self.make = make }

    var isVisible: Bool { window?.isVisible ?? false }
    func close() { window?.close() }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 400), styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.collectionBehavior = [.moveToActiveSpace]      // la fenêtre vient sur le bureau actif au lieu de rester sur un autre
            w.standardWindowButton(.miniaturizeButton)?.isHidden = true
            w.standardWindowButton(.zoomButton)?.isHidden = true
            let v = make(); content = v
            w.contentView = v
            w.delegate = self
            window = w
        }
        guard let w = window else { return }
        w.title = title()
        // Hauteur du contenu à chaque affichage (liste de récents qui change, texte d'une autre langue…)
        if let v = content {
            let h = v.fittingSize.height
            if h > 80 { w.setContentSize(NSSize(width: width, height: h)) }
        }
        if !w.isVisible { w.appCenter() }
        onVisibilityChange?()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) { DispatchQueue.main.async { self.onVisibilityChange?() } }
}

func brandName(_ size: CGFloat) -> some View {
    (Text("m").foregroundColor(Theme.brand) + Text("SOUND").foregroundColor(Theme.text)).font(.system(size: size, weight: .bold))
}

// MARK: - À propos

struct AboutView: View {
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?" }
    var body: some View {
        VStack(spacing: 0) {
            // Barre de titre Socle : 30 px, filet dessous
            ZStack(alignment: .bottom) { Theme.card; Rectangle().fill(Theme.ctl).frame(height: 1) }.frame(height: 30)
            VStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84)
                VStack(spacing: 6) {
                    brandName(17)
                    Text(Loc.t("aboutVersion", version, build)).font(.system(size: 12)).foregroundColor(Theme.text2)
                }.padding(.bottom, 6)
                Group {
                    Text(Loc.t("aboutTagline")).foregroundColor(Theme.text)
                    Text(Loc.t("aboutCollection")).foregroundColor(Theme.text2)
                    Text(Loc.t("aboutAuthors")).fontWeight(.bold).foregroundColor(Theme.text)
                    Text(Loc.t("aboutLicense")).foregroundColor(Theme.text)
                    Text(Loc.t("aboutDisclaimer")).foregroundColor(Theme.text2)
                    Text(Loc.t("aboutCredit")).foregroundColor(Theme.text2)
                }.font(.system(size: 12)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(width: 300)
                Button { NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/starbudweiser")!) } label: {
                    Text("♥ " + Loc.t("support")).font(.system(size: 12, weight: .medium)).underline().foregroundColor(Theme.text)
                }.buttonStyle(.plain)
            }.padding(28).frame(maxWidth: .infinity)
        }
        .frame(width: 356).background(Theme.bg).fixedSize(horizontal: false, vertical: true)
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
            brandName(15)
            // Grille adaptative en deux colonnes de même largeur, chaque bloc garde sa hauteur (règle Socle « Modules en grille adaptative »)
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    finder
                    Card(title: Loc.t("setTheme")) { themeRow }
                    Card(title: Loc.t("setQuality")) { qualityRow }
                }.frame(width: 460)
                VStack(spacing: 16) {
                    Card(title: Loc.t("setShortcuts")) { ShortcutSettings() }
                    Card(title: Loc.t("recFolder")) { RecordFolderSetting() }
                    updates
                }.frame(width: 460)
            }
        }
        .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 28).frame(width: 992)
        .background(Theme.bg).fixedSize(horizontal: false, vertical: true)
    }

    private var themeRow: some View {
        HStack(spacing: 4) {
            ForEach([("system", "themeSystem"), ("dark", "themeDark"), ("sand", "themeSand")], id: \.0) { t in
                Button(Loc.t(t.1)) { theme = t.0; AppTheme.apply() }.buttonStyle(ChipStyle(on: theme == t.0)).lineLimit(1).fixedSize()
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity)
    }

    private var qualityRow: some View {
        HStack(spacing: 4) {
            ForEach([128, 192, 256, 320], id: \.self) { k in Button("\(k) kb/s") { bitrate = k }.buttonStyle(ChipStyle(on: bitrate == k)).lineLimit(1).fixedSize() }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity)
    }

    private var finder: some View {
        Card(title: Loc.t("setFinder")) {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 10) {
                ForEach(Prefs.defaultMenuFormats, id: \.self) { f in
                    Toggle(f == "edit" ? Loc.t("editWith") : Prefs.displayName(f), isOn: Binding(get: { formats.contains(f) }, set: { _ in toggle(f) }))
                        .toggleStyle(.checkbox).font(.system(size: 12.5)).foregroundColor(Theme.text).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(Loc.t("setFinderHint")).font(.system(size: 11.5)).foregroundColor(Theme.text2)
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
        }
    }

    private var updates: some View {
        Card(title: Loc.t("updTitle")) {
            Toggle(Loc.t("updAuto"), isOn: $auto).toggleStyle(.checkbox).font(.system(size: 12.5)).foregroundColor(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Button(Loc.t("updCheck")) { Task { await updater.check() } }.buttonStyle(FlatButton()).lineLimit(1).fixedSize()
                    .disabled(updater.state == .checking || updater.state == .downloading)
                if case .available(let v) = updater.state {
                    Button(Loc.t("updInstall", v)) { Task { await updater.install() } }.buttonStyle(FlatButton(primary: true)).lineLimit(1).fixedSize().disabled(Updater.busy)
                }
                Spacer(minLength: 0)
            }.padding(.top, 2)
            Text(updStatus + (Updater.busy && updater.state != .idle && updater.state != .upToDate ? "\n" + Loc.t("updBusy") : ""))
                .font(.system(size: 11.5)).foregroundColor(Theme.text2).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        }
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
