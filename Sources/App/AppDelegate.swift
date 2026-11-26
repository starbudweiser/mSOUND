import AppKit
import MSoundEngine
import MSoundShared

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: ProgressPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Agent discret : pas d'icône de Dock tant qu'aucune fenêtre d'éditeur n'est ouverte (étape 3).
        NSApp.setActivationPolicy(.accessory)
    }

    func application(_ app: NSApplication, open urls: [URL]) {
        for url in urls where url.host == "convert" {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard let fmt = items.first(where: { $0.name == "format" })?.value,
                  let format = AudioFormat(rawValue: fmt) else { continue }
            let files = items.filter { $0.name == "file" }.compactMap { $0.value }.map { URL(fileURLWithPath: $0) }
            guard !files.isEmpty else { continue }
            if panel == nil { panel = ProgressPanelController() }
            panel?.add(files: files, format: format)
        }
    }
}
