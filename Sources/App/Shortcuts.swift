import SwiftUI
import MSoundEngine
import MSoundShared

/// Raccourcis d'effets de la fenêtre principale : trois emplacements, réglables dans les Réglages.
enum ShortcutAction: String, CaseIterable {
    case normalize, isolate, compress, voicePro, eqVoice, loudness

    static let defaults = "normalize,isolate,compress"
    static func parse(_ raw: String) -> [ShortcutAction] { raw.split(separator: ",").compactMap { ShortcutAction(rawValue: String($0)) } }

    var symbol: String {
        switch self {
        case .normalize: return "waveform.path.badge.plus"
        case .isolate: return "wand.and.stars"
        case .compress: return "waveform.path.ecg"
        case .voicePro: return "mic"
        case .eqVoice: return "slider.horizontal.3"
        case .loudness: return "speaker.wave.2"
        }
    }
    var shortTitle: String { Loc.t("sc_" + rawValue + "_s") }
    var title: String { Loc.t("sc_" + rawValue) }

    /// Chaîne de filtres ; nil pour « Normaliser » (traitement propre au document).
    var steps: [FilterStep]? {
        switch self {
        case .normalize: return nil
        case .isolate: return [.clean(highpassHz: 80), .denoise(.medium)]
        case .compress: return [.compress(.studio)]
        case .voicePro: return Recipe.voicePro.steps
        case .eqVoice: return [.eq(.voice)]
        case .loudness: return [.loudness(-16)]
        }
    }

    /// Sélection ou tout l'échantillon ; avec ⌥ : toutes les timelines.
    @MainActor func run(doc: EditorDocument, session: EditorSession) {
        let all = NSEvent.modifierFlags.contains(.option) && session.docs.count > 1
        if let steps {
            if all { session.processAll(steps, title: title) } else { doc.process(steps, title: title) }
        } else if all { session.docs.forEach { $0.normalize() } } else { doc.normalize() }
    }
}

/// Les boutons de raccourcis dans la barre d'outils.
struct ShortcutButtons: View {
    let doc: EditorDocument
    let session: EditorSession
    @AppStorage("shortcuts") private var raw = ShortcutAction.defaults
    var body: some View {
        ForEach(ShortcutAction.parse(raw), id: \.self) { a in
            Button { a.run(doc: doc, session: session) } label: {
                HStack(spacing: 6) {
                    Image(systemName: a.symbol).font(.system(size: 13, weight: .medium))
                    Text(a.shortTitle).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                }.foregroundColor(Theme.text).padding(.horizontal, 10).frame(height: 30).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(doc.working != nil).opacity(doc.working != nil ? 0.4 : 1)
                .help(a.title + (session.docs.count > 1 ? " — ⌥ : " + Loc.t("scopeAll", session.docs.count) : ""))
        }
    }
}

/// Réglage des trois emplacements.
struct ShortcutSettings: View {
    @AppStorage("shortcuts") private var raw = ShortcutAction.defaults
    private var slots: [ShortcutAction] {
        var l = ShortcutAction.parse(raw)
        for d in ShortcutAction.parse(ShortcutAction.defaults) where l.count < 3 { l.append(d) }
        return Array(l.prefix(3))
    }
    private func set(_ i: Int, _ a: ShortcutAction) {
        var l = slots; l[i] = a
        raw = l.map { $0.rawValue }.joined(separator: ",")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                HStack {
                    Text("\(i + 1)").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text2).frame(width: 16)
                    Picker("", selection: Binding(get: { slots[i] }, set: { set(i, $0) })) {
                        ForEach(ShortcutAction.allCases, id: \.self) { a in Text(a.title).tag(a) }
                    }.labelsHidden().frame(maxWidth: 260)
                    Spacer()
                }
            }
        }
    }
}
