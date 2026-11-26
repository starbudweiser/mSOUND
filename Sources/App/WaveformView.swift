import AppKit
import Combine
import MSoundEngine
import MSoundShared

/// Vue de la forme d'onde : dessin direct (CoreGraphics), sélection à la souris, zoom au pincement ou ⌘+défilement.
final class WaveformView: NSView {
    private let doc: EditorDocument
    private var bag = Set<AnyCancellable>()
    private let rulerH: CGFloat = 22
    private var dragAnchor: Int64?
    private var dragged = false

    init(doc: EditorDocument) {
        self.doc = doc
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Theme.radius
        layer?.masksToBounds = true
        doc.redraw.receive(on: RunLoop.main).sink { [weak self] in self?.needsDisplay = true }.store(in: &bag)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func layout() { super.layout(); doc.viewWidth = bounds.width }

    private var isDark: Bool { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

    // MARK: Dessin
    override func draw(_ dirty: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let dark = isDark
        let bg = dark ? NSColor(srgbRed: 0.09, green: 0.09, blue: 0.10, alpha: 1) : NSColor(srgbRed: 0.95, green: 0.92, blue: 0.85, alpha: 1)
        let wave = dark ? NSColor(srgbRed: 0.18, green: 0.83, blue: 0.75, alpha: 1) : NSColor(srgbRed: 0.66, green: 0.41, blue: 0.10, alpha: 1)
        let accent = dark ? NSColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 1) : NSColor(srgbRed: 0.73, green: 0.45, blue: 0.10, alpha: 1)
        let muted = dark ? NSColor(white: 0.6, alpha: 1) : NSColor(srgbRed: 0.49, green: 0.45, blue: 0.35, alpha: 1)
        let head = dark ? NSColor(srgbRed: 0.18, green: 0.83, blue: 0.75, alpha: 1) : NSColor(srgbRed: 0.05, green: 0.58, blue: 0.53, alpha: 1)
        bg.setFill(); bounds.fill()

        let w = Int(bounds.width), lanes = doc.laneCount
        let area = bounds.height - rulerH
        let laneH = area / CGFloat(lanes)
        let cols = doc.columns(width: w)

        // Ligne médiane
        ctx.setStrokeColor(muted.withAlphaComponent(0.25).cgColor); ctx.setLineWidth(1)
        for l in 0..<lanes {
            let mid = rulerH + laneH * (CGFloat(l) + 0.5)
            ctx.move(to: CGPoint(x: 0, y: mid)); ctx.addLine(to: CGPoint(x: bounds.width, y: mid))
        }
        ctx.strokePath()
        // Onde
        ctx.setStrokeColor(wave.cgColor)
        for l in 0..<lanes {
            let mid = rulerH + laneH * (CGFloat(l) + 0.5), amp = laneH * 0.5 * 0.94
            for (x, c) in cols[l].enumerated() {
                let y1 = mid - CGFloat(min(1, c.1)) * amp
                var y2 = mid - CGFloat(max(-1, c.0)) * amp
                if y2 - y1 < 1 { y2 = y1 + 1 }
                ctx.move(to: CGPoint(x: CGFloat(x) + 0.5, y: y1)); ctx.addLine(to: CGPoint(x: CGFloat(x) + 0.5, y: y2))
            }
        }
        ctx.strokePath()
        if lanes == 2 {
            ctx.setStrokeColor(muted.withAlphaComponent(0.35).cgColor)
            ctx.move(to: CGPoint(x: 0, y: rulerH + laneH)); ctx.addLine(to: CGPoint(x: bounds.width, y: rulerH + laneH)); ctx.strokePath()
        }
        // Sélection
        if let s = doc.selection {
            let x0 = max(0, doc.x(forFrame: s.lowerBound)), x1 = min(bounds.width, doc.x(forFrame: s.upperBound))
            if x1 > x0 {
                accent.withAlphaComponent(0.26).setFill()
                NSRect(x: x0, y: rulerH, width: x1 - x0, height: area).fill()
                accent.setFill()
                if doc.x(forFrame: s.lowerBound) >= 0 { NSRect(x: x0, y: rulerH, width: 2, height: area).fill() }
                if doc.x(forFrame: s.upperBound) <= bounds.width { NSRect(x: x1 - 2, y: rulerH, width: 2, height: area).fill() }
            }
        }
        // Repères
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: muted]
        for m in doc.model.markers {
            let x = doc.x(forFrame: m.frame)
            guard x >= 0 && x <= bounds.width else { continue }
            muted.withAlphaComponent(0.6).setFill(); NSRect(x: x, y: rulerH, width: 1, height: area).fill()
            (m.name as NSString).draw(at: NSPoint(x: x + 4, y: rulerH + 3), withAttributes: attrs)
        }
        // Règle
        drawRuler(muted: muted, ctx: ctx)
        // Tête de lecture
        let px = doc.x(forFrame: doc.transport.playhead)
        if px >= 0 && px <= bounds.width {
            head.setFill(); NSRect(x: px - 1, y: 0, width: 2, height: bounds.height).fill()
            let tri = NSBezierPath(); tri.move(to: NSPoint(x: px - 5, y: 0)); tri.line(to: NSPoint(x: px + 5, y: 0)); tri.line(to: NSPoint(x: px, y: 7)); tri.fill()
        }
        if doc.isComputing {
            let t = Loc.t("loading") as NSString
            t.draw(at: NSPoint(x: bounds.width - 190, y: bounds.height - 20), withAttributes: attrs)
        }
    }

    private func drawRuler(muted: NSColor, ctx: CGContext) {
        let secPerPx = doc.fpp / doc.rate
        let steps: [Double] = [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1800, 3600]
        let step = steps.first { $0 / secPerPx >= 90 } ?? 3600
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular), .foregroundColor: muted]
        let t0 = Double(doc.scroll) / doc.rate
        var t = (t0 / step).rounded(.down) * step
        ctx.setStrokeColor(muted.withAlphaComponent(0.5).cgColor)
        while true {
            let x = CGFloat((t - t0) / secPerPx)
            if x > bounds.width { break }
            if x >= 0 {
                ctx.move(to: CGPoint(x: x + 0.5, y: rulerH - 6)); ctx.addLine(to: CGPoint(x: x + 0.5, y: rulerH)); ctx.strokePath()
                (Self.label(t, step: step) as NSString).draw(at: NSPoint(x: x + 4, y: 4), withAttributes: attrs)
            }
            t += step
        }
    }

    static func label(_ t: Double, step: Double) -> String {
        let h = Int(t) / 3600, m = (Int(t) % 3600) / 60, s = Int(t) % 60
        let base = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
        if step >= 1 { return base }
        return base + String(format: ".%02d", Int((t - t.rounded(.down)) * 100))
    }

    // MARK: Souris
    override func mouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self)
        let x = convert(e.locationInWindow, from: nil).x
        let f = doc.frame(atX: x)
        if e.clickCount == 2 { doc.selectAll(); return }
        if e.modifierFlags.contains(.shift), let s = doc.selection {
            let anchor = abs(f - s.lowerBound) < abs(f - s.upperBound) ? s.upperBound : s.lowerBound
            dragAnchor = anchor; dragged = true; doc.setSelection(anchor, f)
        } else {
            dragAnchor = f; dragged = false
        }
    }
    override func mouseDragged(with e: NSEvent) {
        guard let a = dragAnchor else { return }
        let x = convert(e.locationInWindow, from: nil).x
        if abs(Double(doc.frame(atX: x) - a)) / doc.fpp > 2 { dragged = true }
        if dragged { doc.setSelection(a, doc.frame(atX: x)) }
    }
    override func mouseUp(with e: NSEvent) {
        defer { dragAnchor = nil }
        guard let a = dragAnchor else { return }
        if !dragged {
            doc.selection = nil
            doc.seek(to: a)
        } else if let s = doc.selection, !doc.transport.isPlaying {
            doc.transport.playhead = s.lowerBound; doc.redraw.send()
        }
    }

    override func scrollWheel(with e: NSEvent) {
        let x = convert(e.locationInWindow, from: nil).x
        if e.modifierFlags.contains(.command) || e.modifierFlags.contains(.option) {
            doc.zoom(factor: exp(-Double(e.scrollingDeltaY) * 0.01), anchorX: x)
        } else {
            let d = abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) ? e.scrollingDeltaX : e.scrollingDeltaY
            doc.pan(byPixels: d)
        }
    }
    override func magnify(with e: NSEvent) {
        doc.zoom(factor: 1 - Double(e.magnification), anchorX: convert(e.locationInWindow, from: nil).x)
    }
    override func keyDown(with e: NSEvent) {
        switch e.charactersIgnoringModifiers {
        case " ": doc.togglePlay()
        case "m": doc.addMarker()
        default: super.keyDown(with: e)
        }
    }
}
