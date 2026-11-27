import AppKit
import SwiftUI
import MSoundShared

// Alertes de l'appli : centrées sur la fenêtre de l'appli, icône et textes centrés (règles Socle « Fenêtres secondaires centrées » et
// « Textes centrés dans les alertes ») ; reprend `runCenteredOnAppWindow` de _tools/shared/UpdaterView.swift.

extension NSWindow {
    /// Centre la fenêtre sur la fenêtre de l'appli (principale, sinon une autre visible) ; sans fenêtre d'appli, sur l'écran du pointeur.
    @MainActor func appCenter() {
        let candidates = NSApp.windows.filter { $0 !== self && $0.isVisible && $0.styleMask.contains(.titled) && !($0 is NSPanel) }
        if let host = candidates.first(where: { $0.isKeyWindow || $0.isMainWindow }) ?? candidates.first {
            setFrameOrigin(NSPoint(x: host.frame.midX - frame.width / 2, y: host.frame.midY - frame.height / 2))
            return
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens[0]
        let v = screen.visibleFrame
        setFrameOrigin(NSPoint(x: v.midX - frame.width / 2, y: v.midY - frame.height / 2))
    }
}

extension NSAlert {
    @MainActor @discardableResult func runCenteredOnAppWindow() -> NSApplication.ModalResponse {
        layout()
        centerContent()
        window.appCenter()
        for delay in [0.0, 0.05, 0.2] {
            let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.window.appCenter() } }
            RunLoop.main.add(t, forMode: .common)
        }
        let response = NSApp.runModal(for: window)
        window.orderOut(nil)
        return response
    }

    @MainActor private func centerContent() {
        guard let content = window.contentView else { return }
        func walk(_ view: NSView) {
            for v in view.subviews {
                if let field = v as? NSTextField, !field.isEditable {
                    field.alignment = .center
                    if let text = field.attributedStringValue.mutableCopy() as? NSMutableAttributedString, text.length > 0 {
                        let p = NSMutableParagraphStyle(); p.alignment = .center
                        text.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: text.length))
                        field.attributedStringValue = text
                    }
                } else if let image = v as? NSImageView, image.frame.width <= 128 {
                    image.setFrameOrigin(NSPoint(x: ((view.bounds.width - image.frame.width) / 2).rounded(), y: image.frame.origin.y))
                }
                walk(v)
            }
        }
        walk(content)
    }
}

enum AppAlert {
    @MainActor static func show(_ message: String, info: String? = nil) {
        let a = NSAlert(); a.messageText = message; if let info { a.informativeText = info }
        a.addButton(withTitle: "OK")
        a.runCenteredOnAppWindow()
    }
}

/// `.appAlert($texte)` : affiche l'alerte centrée quand le texte apparaît, puis le remet à nil.
struct AppAlertModifier: ViewModifier {
    @Binding var message: String?
    func body(content: Content) -> some View {
        content.onChange(of: message) { _, new in
            guard let new else { return }
            DispatchQueue.main.async { AppAlert.show(new); message = nil }
        }
    }
}
extension View { func appAlert(_ message: Binding<String?>) -> some View { modifier(AppAlertModifier(message: message)) } }
