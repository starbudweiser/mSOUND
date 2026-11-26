import Cocoa
import FinderSync
import MSoundShared

/// Extension Finder : entrées de menu contextuel plates (niveau 1) pour convertir les fichiers audio sélectionnés.
@objc(MSoundFinderSync)
final class MSoundFinderSync: FIFinderSync {
    private let domain = Prefs.appDomain(forBundleID: Bundle.main.bundleIdentifier ?? "fr.stephan.msound.finder")

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems,
              let urls = FIFinderSyncController.default().selectedItemURLs(), !urls.isEmpty,
              urls.allSatisfy(Self.isAudioFile) else { return nil }
        let menu = NSMenu(title: "mSOUND")
        for f in Prefs.menuFormats(domain: domain) {
            let item = NSMenuItem(title: Loc.t("convertTo", Prefs.displayName(f)), action: #selector(convert(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = f
            item.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)
            menu.addItem(item)
        }
        return menu
    }

    @objc private func convert(_ sender: NSMenuItem) {
        guard let format = sender.representedObject as? String,
              let urls = FIFinderSyncController.default().selectedItemURLs() else { return }
        var c = URLComponents()
        c.scheme = Prefs.urlScheme(forDomain: domain)
        c.host = "convert"
        c.queryItems = [URLQueryItem(name: "format", value: format)] + urls.map { URLQueryItem(name: "file", value: $0.path) }
        guard let url = c.url else { return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false   // mode silencieux : ne prend jamais le focus
        NSWorkspace.shared.open(url, configuration: cfg, completionHandler: nil)
    }

    private static func isAudioFile(_ url: URL) -> Bool {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        return !isDir && Prefs.audioExtensions.contains(url.pathExtension.lowercased())
    }
}
