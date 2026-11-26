import AppKit
import Combine
import MSoundEngine

/// Vue d'ensemble du fichier entier (bâtons fins) avec le cadre de la zone affichée ; cliquer ou glisser pour naviguer.
final class OverviewView: NSView {
    private let doc: EditorDocument
    private var bag = Set<AnyCancellable>()

    init(doc: EditorDocument) {
        self.doc = doc
        super.init(frame: .zero)
        wantsLayer = true; layer?.cornerRadius = Theme.radius; layer?.masksToBounds = true
        doc.redraw.receive(on: RunLoop.main).sink { [weak self] in self?.needsDisplay = true }.store(in: &bag)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func draw(_ dirty: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let bg = dark ? NSColor(srgbRed: 0.125, green: 0.125, blue: 0.14, alpha: 1) : NSColor(srgbRed: 0.95, green: 0.92, blue: 0.85, alpha: 1)
        let wave = dark ? NSColor(srgbRed: 0.18, green: 0.83, blue: 0.75, alpha: 1) : NSColor(srgbRed: 0.66, green: 0.41, blue: 0.10, alpha: 1)
        let accent = dark ? NSColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 1) : NSColor(srgbRed: 0.73, green: 0.45, blue: 0.10, alpha: 1)
        let head = dark ? NSColor(srgbRed: 0.18, green: 0.83, blue: 0.75, alpha: 1) : NSColor(srgbRed: 0.05, green: 0.58, blue: 0.53, alpha: 1)
        bg.setFill(); bounds.fill()
        let total = max(doc.total, 1)
        let pitch: CGFloat = 3, barW: CGFloat = 2
        let n = Int(bounds.width / pitch) + 1
        let (amps, tints) = doc.columnData(count: n, start: 0, perColumn: Double(total) / Double(bounds.width) * Double(pitch))
        let mid = bounds.height / 2, maxH = bounds.height - 12
        for t in Set(tints) {
            ctx.setFillColor((t == 0 ? wave : WavePalette.color(Int(t), dark: dark)).withAlphaComponent(0.85).cgColor)
            for (i, a) in amps.enumerated() where tints[i] == t {
                let h = max(2, CGFloat(min(1, a)) * maxH)
                ctx.addPath(CGPath(roundedRect: CGRect(x: CGFloat(i) * pitch, y: mid - h / 2, width: barW, height: h), cornerWidth: 1, cornerHeight: 1, transform: nil))
            }
            ctx.fillPath()
        }
        func x(_ f: Int64) -> CGFloat { CGFloat(Double(f) / Double(total)) * bounds.width }
        if let s = doc.selection {
            accent.withAlphaComponent(0.3).setFill()
            NSRect(x: x(s.lowerBound), y: 0, width: max(2, x(s.upperBound) - x(s.lowerBound)), height: bounds.height).fill()
        }
        // Zone affichée dans l'éditeur
        let vx0 = x(doc.scroll), vx1 = min(bounds.width, x(doc.scroll + doc.visibleFrames))
        let vr = NSRect(x: vx0 + 1, y: 1, width: max(8, vx1 - vx0 - 2), height: bounds.height - 2)
        accent.withAlphaComponent(0.12).setFill(); vr.fill()
        accent.setStroke()
        let path = NSBezierPath(roundedRect: vr, xRadius: 3, yRadius: 3); path.lineWidth = 2; path.stroke()
        head.setFill(); NSRect(x: x(doc.transport.playhead) - 1, y: 0, width: 2, height: bounds.height).fill()
    }

    private func navigate(_ e: NSEvent) {
        let x = convert(e.locationInWindow, from: nil).x
        doc.scrollTo(centerFrame: Int64(Double(max(0, min(x, bounds.width)) / bounds.width) * Double(doc.total)))
    }
    override func mouseDown(with e: NSEvent) { navigate(e) }
    override func mouseDragged(with e: NSEvent) { navigate(e) }
}
