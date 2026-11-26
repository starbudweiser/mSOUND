import SwiftUI
import UniformTypeIdentifiers
import MSoundEngine
import MSoundShared

/// Fenêtre d'accueil : déposer ou ouvrir un fichier, reprendre un fichier récent, accéder aux réglages.
struct HomeView: View {
    var open: ([URL]) -> Void
    var openPanel: () -> Void
    var record: () -> Void
    @ObservedObject private var rec = Recorder.shared
    var settings: () -> Void
    @State private var dropping = false
    private var recents: [URL] { Array(NSDocumentController.shared.recentDocumentURLs.prefix(5)) }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                brandName(22)
                Text(Loc.t("aboutTagline")).font(.system(size: 12)).foregroundColor(Theme.text2).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(.top, 8)
            if rec.isRecording { RecordingPanel { record() } } else {
            VStack(spacing: 14) {
                Image(systemName: "waveform").font(.system(size: 34, weight: .light)).foregroundColor(dropping ? Theme.accent : Theme.text2)
                Text(Loc.t("homeDrop")).font(.system(size: 14, weight: .medium)).foregroundColor(Theme.text)
                HStack(spacing: 8) {
                    Button(Loc.t("homeOpen"), action: openPanel).buttonStyle(FlatButton(primary: true))
                    Button(action: record) { HStack(spacing: 6) { Image(systemName: "record.circle").foregroundColor(Theme.danger); Text(Loc.t("recStart")) } }.buttonStyle(FlatButton())
                }
            }
            .frame(maxWidth: .infinity, minHeight: 190)
            .background(dropping ? Theme.accent.opacity(0.12) : Theme.card)
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(dropping ? Theme.accent : Theme.ctl, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
                for p in providers {
                    p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                        guard let d = item as? Data, let u = URL(dataRepresentation: d, relativeTo: nil),
                              Prefs.audioExtensions.contains(u.pathExtension.lowercased()) else { return }
                        DispatchQueue.main.async { open([u]) }
                    }
                }
                return true
            }
            }
            if !recents.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Loc.t("homeRecent").uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.5).foregroundColor(Theme.text2)
                    ForEach(recents, id: \.self) { u in
                        Button { open([u]) } label: {
                            HStack { Image(systemName: "music.note").foregroundColor(Theme.text2)
                                Text(u.lastPathComponent).lineLimit(1).truncationMode(.middle).foregroundColor(Theme.text); Spacer() }
                                .font(.system(size: 12.5)).padding(.vertical, 5).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            HStack {
                Text(Loc.t("homeHint")).font(.system(size: 11.5)).foregroundColor(Theme.text2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button(Loc.t("settings"), action: settings).buttonStyle(FlatButton()).lineLimit(1).fixedSize()
            }
        }
        .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.bg)
    }
}
