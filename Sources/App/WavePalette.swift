import AppKit

/// Couleurs des formes d'onde : 0 = fichier d'origine (teal), 1… = échantillons importés.
enum WavePalette {
    static func color(_ tint: Int, dark: Bool) -> NSColor {
        let d: [(CGFloat, CGFloat, CGFloat)] = [(0.18, 0.83, 0.75), (1.0, 0.62, 0.04), (1.0, 0.36, 0.62), (0.69, 0.52, 1.0), (0.62, 0.86, 0.25)]
        let l: [(CGFloat, CGFloat, CGFloat)] = [(0.66, 0.41, 0.10), (0.80, 0.42, 0.02), (0.78, 0.22, 0.45), (0.45, 0.30, 0.78), (0.35, 0.55, 0.10)]
        let t = (dark ? d : l)[max(0, min(tint, d.count - 1))]
        return NSColor(srgbRed: t.0, green: t.1, blue: t.2, alpha: 1)
    }
}
