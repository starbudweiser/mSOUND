import AppKit

/// Mode démo pour les captures d'écran : `MSOUND_DEMO=<fichier audio>` ouvre ce fichier sans activer l'appli
/// (fenêtre placée derrière les autres), puis pose deux repères et une sélection. Aucun effet sans la variable.
enum DemoMode {
    static var file: URL? { ProcessInfo.processInfo.environment["MSOUND_DEMO"].map { URL(fileURLWithPath: $0) } }
    static var isOn: Bool { file != nil }

    @MainActor static func stage(_ doc: EditorDocument) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let t = doc.total
            doc.transport.playhead = t * 16 / 100; doc.addMarker()
            doc.transport.playhead = t * 64 / 100; doc.addMarker()
            doc.setSelection(t * 31 / 100, t * 47 / 100)
            doc.transport.playhead = t * 36 / 100
            doc.redraw.send()
        }
    }
}
