import Foundation
import AppKit
import MSoundEngine
import MSoundShared

@MainActor
final class ProgressModel: ObservableObject {
    enum State: Equatable { case waiting, running, done(URL), failed(String), cancelled, skipped }

    struct Row: Identifiable {
        let id: UUID
        let name: String
        let format: AudioFormat
        var progress: Double = 0
        var state: State = .waiting
        var sizes: String = ""
    }

    @Published var rows: [Row] = []
    private var tasks: [Task<Void, Never>] = []
    var onAllFinished: (() -> Void)?

    var finished: Int { rows.filter { $0.state != .waiting && $0.state != .running }.count }
    var isRunning: Bool { rows.contains { $0.state == .waiting || $0.state == .running } }
    var hasFailure: Bool { rows.contains { if case .failed = $0.state { return true }; return false } }
    var outputs: [URL] { rows.compactMap { if case .done(let u) = $0.state { return u }; return nil } }

    func add(files: [URL], format: AudioFormat) {
        let jobs = files.map { BatchJob(source: $0) }
        rows += jobs.map { Row(id: $0.id, name: $0.source.lastPathComponent, format: format) }
        let sources = Dictionary(uniqueKeysWithValues: jobs.map { ($0.id, $0.source) })
        let task = Task { [weak self] in
            await BatchQueue().run(jobs, to: format) { ev in
                Task { @MainActor in self?.apply(ev, sources: sources) }
            }
            await MainActor.run { self?.checkFinished() }
        }
        tasks.append(task)
    }

    func cancelAll() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        for i in rows.indices where rows[i].state == .waiting || rows[i].state == .running { rows[i].state = .cancelled }
    }

    private func apply(_ ev: BatchEvent, sources: [UUID: URL]) {
        func idx(_ j: BatchJob) -> Int? { rows.firstIndex { $0.id == j.id } }
        switch ev {
        case .started(let j): if let i = idx(j), rows[i].state != .cancelled { rows[i].state = .running }
        case .progress(let j, let p): if let i = idx(j), rows[i].state == .running { rows[i].progress = p }
        case .finished(let j, let out):
            if let i = idx(j) {
                rows[i].progress = 1
                rows[i].state = .done(out)
                let a = (try? FileManager.default.attributesOfItem(atPath: sources[j.id]?.path ?? "")[.size] as? Int) ?? 0
                let b = (try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? 0
                rows[i].sizes = "\(Self.mb(a)) → \(Self.mb(b))"
            }
        case .failed(let j, let e):
            if let i = idx(j), rows[i].state != .cancelled {
                rows[i].state = e == .cancelled ? .cancelled : e == .sameFormat ? .skipped : .failed(e.errorDescription ?? "")
            }
        }
    }

    private func checkFinished() { if !isRunning { onAllFinished?() } }

    private static func mb(_ b: Int) -> String {
        let v = Double(b) / 1_048_576
        return v >= 10 ? String(format: "%.0f Mo", v) : String(format: "%.1f Mo", v)
    }
}
