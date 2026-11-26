import AppKit
import SwiftUI
import MSoundEngine
import MSoundShared

@MainActor final class EditorWindowController: NSObject, NSWindowDelegate {
    let doc: EditorDocument
    let window: NSWindow
    var onClose: ((EditorWindowController) -> Void)?

    init(doc: EditorDocument) {
        self.doc = doc
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 680),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        window.title = doc.url.lastPathComponent
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        // La taille de la fenêtre est celle de l'utilisateur, jamais dictée par le contenu SwiftUI (sinon elle peut s'écraser).
        let host = NSHostingView(rootView: EditorView(doc: doc, onOpenFiles: { urls in
            MainActor.assumeIsolated { urls.forEach { (NSApp.delegate as? AppDelegate)?.openEditor($0) } }
        }))
        host.sizingOptions = []
        window.contentView = host
        window.contentMinSize = NSSize(width: 1000, height: 560)
        window.delegate = self
        window.center()
    }
    func windowWillClose(_ notification: Notification) { doc.stop(); onClose?(self) }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var editors: [EditorWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Agent discret tant qu'aucune fenêtre d'éditeur n'est ouverte (les conversions du Finder restent silencieuses).
        NSApp.setActivationPolicy(.accessory)
        MainMenu.install(target: self)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func application(_ app: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.isFileURL { openEditor(url); continue }
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let files = items.filter { $0.name == "file" }.compactMap { $0.value }.map { URL(fileURLWithPath: $0) }
            guard !files.isEmpty else { continue }
            if url.host == "edit" { files.forEach(openEditor); continue }
            guard url.host == "convert", let fmt = items.first(where: { $0.name == "format" })?.value,
                  let format = AudioFormat(rawValue: fmt) else { continue }
            // Fenêtre de progression : lots (plusieurs fichiers) ; un fichier seul depuis le Finder = jauge sur son icône.
            ProgressPanelController.shared.add(files: files, format: format, showWindow: files.count > 1)
        }
    }

    // MARK: Éditeurs
    func openEditor(_ url: URL) {
        if let e = editors.first(where: { $0.doc.url == url }) { e.window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        do {
            let doc = try EditorDocument(url: url)
            let c = EditorWindowController(doc: doc)
            c.onClose = { [weak self] c in
                self?.editors.removeAll { $0 === c }
                if self?.editors.isEmpty == true { NSApp.setActivationPolicy(.accessory) }
            }
            editors.append(c)
            NSApp.setActivationPolicy(.regular)
            c.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            let a = NSAlert(); a.messageText = Loc.t("openFailed"); a.informativeText = url.lastPathComponent; a.runModal()
        }
    }

    var current: EditorDocument? {
        editors.first { $0.window === NSApp.keyWindow }?.doc ?? editors.last?.doc
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let d = current else { return item.action == #selector(openAction) || item.action == #selector(aboutAction) }
        switch item.action {
        case #selector(undoAction): return d.canUndo
        case #selector(redoAction): return d.canRedo
        case #selector(cutAction), #selector(copyAction), #selector(deleteAction), #selector(keepAction),
             #selector(fadeInAction), #selector(fadeOutAction): return d.selection != nil
        case #selector(pasteAction): return !EditorDocument.clipboard.isEmpty
        default: return true
        }
    }

    // MARK: Actions de menu
    @objc func openAction() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.audio]; p.allowsMultipleSelection = true
        if p.runModal() == .OK { p.urls.forEach(openEditor) }
    }
    @objc func closeAction() { NSApp.keyWindow?.performClose(nil) }
    @objc func exportAction() { current?.export() }
    @objc func undoAction() { current?.undo() }
    @objc func redoAction() { current?.redo() }
    @objc func cutAction() { current?.cut() }
    @objc func copyAction() { current?.copySel() }
    @objc func pasteAction() { current?.paste() }
    @objc func deleteAction() { current?.deleteSel() }
    @objc func keepAction() { current?.keepSel() }
    @objc func normalizeAction() { current?.normalize() }
    @objc func fadeInAction() { current?.fadeIn() }
    @objc func fadeOutAction() { current?.fadeOut() }
    @objc func gainUpAction() { current?.gain(db: 3) }
    @objc func gainDownAction() { current?.gain(db: -3) }
    @objc func selectAllAction() { current?.selectAll() }
    @objc func markerAction() { current?.addMarker() }
    @objc func playAction() { current?.togglePlay() }
    @objc func startAction() { current?.seek(to: 0) }
    @objc func endAction() { if let d = current { d.seek(to: d.total) } }
    @objc func zoomInAction() { if let d = current { d.zoom(factor: 0.5, anchorX: d.viewWidth / 2) } }
    @objc func zoomOutAction() { if let d = current { d.zoom(factor: 2, anchorX: d.viewWidth / 2) } }
    @objc func fitAction() { current?.fit() }
    @objc func aboutAction() { NSApp.orderFrontStandardAboutPanel(nil) }
    @objc func quitAction() { NSApp.terminate(nil) }
}

@MainActor enum MainMenu {
    static func install(target t: AppDelegate) {
        let main = NSMenu()
        func item(_ title: String, _ sel: Selector, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: key); i.target = t; i.keyEquivalentModifierMask = mods; return i
        }
        func add(_ title: String, _ items: [NSMenuItem]) {
            let m = NSMenu(title: title)
            items.forEach { $0.isSeparatorItem ? m.addItem(.separator()) : m.addItem($0) }
            let top = NSMenuItem(); top.submenu = m; main.addItem(top)
        }
        let sep = NSMenuItem.separator()
        add("mSOUND", [item(Loc.t("about"), #selector(AppDelegate.aboutAction)), .separator(), item(Loc.t("quit"), #selector(AppDelegate.quitAction), "q")])
        add(Loc.t("menuFile"), [item(Loc.t("open"), #selector(AppDelegate.openAction), "o"), item(Loc.t("close"), #selector(AppDelegate.closeAction), "w"),
                                .separator(), item(Loc.t("export"), #selector(AppDelegate.exportAction), "e")])
        add(Loc.t("menuEdit"), [item(Loc.t("undo"), #selector(AppDelegate.undoAction), "z"), item(Loc.t("redo"), #selector(AppDelegate.redoAction), "z", [.command, .shift]),
                                .separator(), item(Loc.t("cut"), #selector(AppDelegate.cutAction), "x"), item(Loc.t("copy"), #selector(AppDelegate.copyAction), "c"),
                                item(Loc.t("paste"), #selector(AppDelegate.pasteAction), "v"),
                                item(Loc.t("delete"), #selector(AppDelegate.deleteAction), "\u{8}", []),
                                item(Loc.t("keep"), #selector(AppDelegate.keepAction), "k"),
                                item(Loc.t("selectAll"), #selector(AppDelegate.selectAllAction), "a"),
                                .separator(), item(Loc.t("marker"), #selector(AppDelegate.markerAction), "m", [])])
        add(Loc.t("menuEffects"), [item(Loc.t("normalize"), #selector(AppDelegate.normalizeAction), "n", [.command, .shift]),
                                   item(Loc.t("fadeIn"), #selector(AppDelegate.fadeInAction), "", []), item(Loc.t("fadeOut"), #selector(AppDelegate.fadeOutAction), "", []),
                                   .separator(), item(Loc.t("gainUp"), #selector(AppDelegate.gainUpAction), "", []), item(Loc.t("gainDown"), #selector(AppDelegate.gainDownAction), "", [])])
        add(Loc.t("menuPlay"), [item(Loc.t("playPause"), #selector(AppDelegate.playAction), "p"), item(Loc.t("toStart"), #selector(AppDelegate.startAction), "\u{F729}", .command),
                                item(Loc.t("toEnd"), #selector(AppDelegate.endAction), "\u{F72B}", .command), .separator(),
                                item(Loc.t("zoomIn"), #selector(AppDelegate.zoomInAction), "+"), item(Loc.t("zoomOut"), #selector(AppDelegate.zoomOutAction), "-"),
                                item(Loc.t("fit"), #selector(AppDelegate.fitAction), "0")])
        _ = sep
        NSApp.mainMenu = main
    }
}
