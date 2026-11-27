import AppKit
import SwiftUI
import MSoundEngine
import MSoundShared

/// Une fenêtre d'édition = plusieurs timelines indépendantes (une par fichier), chacune avec son montage, sa sélection, ses annulations.
@MainActor final class EditorSession: ObservableObject {
    @Published private(set) var docs: [EditorDocument]
    @Published private(set) var active: EditorDocument
    @Published private(set) var batchRunning = false
    var onEmpty: (() -> Void)?
    private var batchCancelled = false

    init(first: EditorDocument) { docs = [first]; active = first }

    func doc(for url: URL) -> EditorDocument? { docs.first { $0.url == url } }

    func select(_ d: EditorDocument) {
        guard d !== active else { return }
        active.stop(); active = d
    }

    /// Ouvre des fichiers dans de nouvelles timelines (un fichier déjà ouvert est simplement sélectionné).
    func open(_ urls: [URL]) {
        var failed: [URL] = []
        for u in urls {
            if let d = doc(for: u) { select(d); continue }
            do { let d = try EditorDocument(url: u); docs.append(d); select(d) } catch { failed.append(u) }
        }
        if let f = failed.first {
            AppAlert.show(Loc.t("openFailed"), info: f.lastPathComponent)
        }
    }

    func close(_ d: EditorDocument) {
        d.stop()
        guard let i = docs.firstIndex(where: { $0 === d }) else { return }
        docs.remove(at: i)
        if docs.isEmpty { onEmpty?(); return }
        if active === d { active = docs[min(i, docs.count - 1)] }
    }

    func closeAll() { docs.forEach { $0.stop() } }

    /// Applique la même chaîne de filtres à toutes les timelines, l'une après l'autre (un seul calcul lourd à la fois).
    func processAll(_ steps: [FilterStep], title: String) {
        guard !batchRunning, docs.allSatisfy({ $0.working == nil }) else { return }
        batchRunning = true; batchCancelled = false
        let list = docs
        func next(_ i: Int) {
            guard !batchCancelled, i < list.count else { batchRunning = false; return }
            list[i].process(steps, title: title, whole: true) { next(i + 1) }
        }
        next(0)
    }

    func cancelBatch() {
        batchCancelled = true
        docs.forEach { $0.cancelWork() }
    }

    func exportAll() { docs.forEach { $0.export(whole: true) } }
}

/// Barre des timelines : onglets, « tout exporter ».
struct TimelineTabs: View {
    @ObservedObject var session: EditorSession
    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) { ForEach(session.docs, id: \.url) { d in TimelineTab(session: session, doc: d) } }
            }
            Button(Loc.t("exportAll")) { session.exportAll() }.buttonStyle(FlatButton()).lineLimit(1).fixedSize()
        }.padding(.horizontal, 28).padding(.bottom, 8).frame(height: 40)
    }
}

private struct TimelineTab: View {
    @ObservedObject var session: EditorSession
    @ObservedObject var doc: EditorDocument
    var body: some View {
        let on = session.active === doc
        HStack(spacing: 6) {
            if let w = doc.working { ProgressView(value: w.progress).progressViewStyle(.circular).controlSize(.small) }
            Text(doc.url.lastPathComponent).font(.system(size: 12, weight: on ? .semibold : .regular)).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 170)
            Button { session.close(doc) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).opacity(0.7) }
                .buttonStyle(.plain).help(Loc.t("close"))
        }
        .padding(.horizontal, 10).frame(height: 28)
        .background(on ? Theme.accent : Theme.ctl).foregroundColor(on ? .white : Theme.text)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .contentShape(Rectangle()).onTapGesture { session.select(doc) }
    }
}

struct EditorRoot: View {
    @ObservedObject var session: EditorSession
    var body: some View {
        EditorView(doc: session.active, session: session).id(ObjectIdentifier(session.active))
            .ignoresSafeArea(.container, edges: .top)          // la rangée du haut remonte sur la ligne des boutons de fenêtre
    }
}
