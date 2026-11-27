import SwiftUI
import MSoundEngine
import MSoundShared

/// La carte : quatre recettes toutes prêtes, cinq filtres à préréglages, quelques réglages de niveau.
struct EffectsPanel: View {
    let doc: EditorDocument
    @ObservedObject var session: EditorSession
    var close: () -> Void
    @State private var allTimelines = false
    @State private var strength: Strength = .medium
    @State private var eq: EQPreset = .voice
    @State private var comp: CompPreset = .studio
    @State private var target: Double = -16

    private func run(_ steps: [FilterStep], _ title: String) {
        close()
        if allTimelines && session.docs.count > 1 { session.processAll(steps, title: title) } else { doc.process(steps, title: title) }
    }

    private func row<Chips: View>(_ title: String, _ desc: String, apply: @escaping () -> Void, @ViewBuilder chips: () -> Chips) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                Spacer(minLength: 8)
                chips()
                Button(Loc.t("fxApply"), action: apply).buttonStyle(FlatButton(primary: true)).lineLimit(1).fixedSize().padding(.leading, 4)
            }
            Text(desc).font(.system(size: 11.5)).foregroundColor(Theme.text2).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Carte de groupe : 24 px de marge intérieure, rangées séparées par un filet.
    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.5).foregroundColor(Theme.text2)
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        }
    }
    private var rule: some View { Rectangle().fill(Theme.ctl).frame(height: 1) }

    private func chip<T: Equatable>(_ label: String, _ value: T, _ sel: Binding<T>) -> some View {
        Button(label) { sel.wrappedValue = value }.buttonStyle(ChipStyle(on: sel.wrappedValue == value)).lineLimit(1).fixedSize()
    }

    private func header(_ s: String) -> some View {
        Text(s.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.5).foregroundColor(Theme.text2).padding(.top, 6)
    }

    var body: some View {
        let hasSel = doc.selection != nil
        let all = allTimelines && session.docs.count > 1
        VStack(alignment: .leading, spacing: 16) {
            if session.docs.count > 1 {
                HStack(spacing: 4) {
                    chip(Loc.t("scopeThis"), false, $allTimelines)
                    chip(Loc.t("scopeAll", session.docs.count), true, $allTimelines)
                    Spacer()
                }
            }
            Text(all ? Loc.t("fxScopeAll") : (hasSel ? Loc.t("fxScopeSel") : Loc.t("fxScopeAll")))
                .font(.system(size: 12, weight: .medium)).foregroundColor(Theme.text2)
            group(Loc.t("fxRecipes")) {
                ForEach(Array(Recipe.allCases.enumerated()), id: \.element) { i, r in
                    if i > 0 { rule }
                    let (t, d) = recipeText(r)
                    row(t, d, apply: { run(r.steps, t) }) { EmptyView() }
                }
            }
            group(Loc.t("fxFilters")) {
                row(Loc.t("fDenoise"), Loc.t("fDenoiseD"), apply: { run([.denoise(strength)], Loc.t("fDenoise")) }) {
                    chip(Loc.t("sLight"), Strength.light, $strength); chip(Loc.t("sMedium"), Strength.medium, $strength); chip(Loc.t("sStrong"), Strength.strong, $strength)
                }
                rule
                row(Loc.t("fClean"), Loc.t("fCleanD"), apply: { run([.clean(highpassHz: 80)], Loc.t("fClean")) }) { EmptyView() }
                rule
                row(Loc.t("fEQ"), Loc.t("fEQD"), apply: { run([.eq(eq)], Loc.t("fEQ")) }) {
                    chip(Loc.t("eqVoice"), EQPreset.voice, $eq); chip(Loc.t("eqWarm"), EQPreset.warm, $eq); chip(Loc.t("eqBright"), EQPreset.bright, $eq)
                }
                rule
                row(Loc.t("fComp"), Loc.t("fCompD"), apply: { run([.compress(comp)], Loc.t("fComp")) }) {
                    chip(Loc.t("cSoft"), CompPreset.soft, $comp); chip(Loc.t("cStudio"), CompPreset.studio, $comp); chip(Loc.t("cRadio"), CompPreset.radio, $comp)
                }
                rule
                row(Loc.t("fLoud"), Loc.t("fLoudD"), apply: { run([.loudness(target)], Loc.t("fLoud")) }) {
                    chip(Loc.t("lTV"), -23.0, $target); chip(Loc.t("lPod"), -16.0, $target); chip(Loc.t("lStream"), -14.0, $target)
                }
            }
            if !all {
                group(Loc.t("fxLevels")) {
                    HStack(spacing: 6) {
                        Button(Loc.t("normalize")) { close(); doc.normalize() }.buttonStyle(FlatButton())
                        Button(Loc.t("fadeInShort")) { close(); doc.fadeIn() }.buttonStyle(FlatButton())
                        Button(Loc.t("fadeOutShort")) { close(); doc.fadeOut() }.buttonStyle(FlatButton())
                        Button("+3 dB") { close(); doc.gain(db: 3) }.buttonStyle(FlatButton())
                        Button("−3 dB") { close(); doc.gain(db: -3) }.buttonStyle(FlatButton())
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(28).frame(width: 600).background(Theme.bg)
    }

    private func recipeText(_ r: Recipe) -> (String, String) {
        switch r {
        case .voicePro: return (Loc.t("rVoicePro"), Loc.t("rVoiceProD"))
        case .noisyInterview: return (Loc.t("rInterview"), Loc.t("rInterviewD"))
        case .warmNarration: return (Loc.t("rNarration"), Loc.t("rNarrationD"))
        case .instrument: return (Loc.t("rInstrument"), Loc.t("rInstrumentD"))
        }
    }
}
