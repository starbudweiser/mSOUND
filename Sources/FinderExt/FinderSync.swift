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
        for (i, f) in Prefs.menuFormats(domain: domain).enumerated() {
            let item = NSMenuItem(title: f == "edit" ? Loc.t("editWith") : Loc.t("convertTo", Prefs.displayName(f)), action: #selector(convert(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i   // representedObject ne traverse pas le processus du Finder ; le tag, si
            item.image = Self.menuIcon
            menu.addItem(item)
        }
        return menu
    }

    @objc private func convert(_ sender: NSMenuItem) {
        let formats = Prefs.menuFormats(domain: domain)
        guard formats.indices.contains(sender.tag),
              let urls = FIFinderSyncController.default().selectedItemURLs() else {
            NSLog("mSOUNDFinder: pas de sélection ou de format"); return
        }
        let format = formats[sender.tag]
        NSLog("mSOUNDFinder: conversion %{public}@ de %d fichier(s)", format, urls.count)
        var c = URLComponents()
        c.scheme = Prefs.urlScheme(forDomain: domain)
        c.host = format == "edit" ? "edit" : "convert"
        c.queryItems = (format == "edit" ? [] : [URLQueryItem(name: "format", value: format)]) + urls.map { URLQueryItem(name: "file", value: $0.path) }
        guard let url = c.url else { return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false   // mode silencieux : ne prend jamais le focus
        // On vise l'appli qui contient l'extension (…/mSOUND.app/Contents/PlugIns/x.appex), sans dépendre du schéma d'URL.
        let appURL = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: cfg) { _, error in
            if let error { NSLog("mSOUNDFinder: ouverture impossible : %{public}@", error.localizedDescription) }
            else { NSLog("mSOUNDFinder: demande envoyée à %{public}@", appURL.path) }
        }
    }

    /// Icône d'onde en bleu système (non « modèle », donc jamais noire dans le menu).
    private static let menuIcon: NSImage? = {
        let cfg = NSImage.SymbolConfiguration(paletteColors: [NSColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 1)])
        let img = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
        img?.isTemplate = false
        return img
    }()

    private static func isAudioFile(_ url: URL) -> Bool {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        return !isDir && Prefs.audioExtensions.contains(url.pathExtension.lowercased())
    }
}
