import Foundation

public struct BatchJob: Identifiable, Sendable {
    public let id = UUID()
    public let source: URL
    public let token = CancelToken()
    public init(source: URL) { self.source = source }
}

public enum BatchEvent: Sendable {
    case started(BatchJob)
    case progress(BatchJob, Double)
    case finished(BatchJob, URL)
    case failed(BatchJob, ConvertError)
}

/// File de conversions par lot : parallélisme limité, annulable par annulation de Task.
public struct BatchQueue: Sendable {
    public var maxConcurrent: Int
    public init(maxConcurrent: Int = max(1, min(4, ProcessInfo.processInfo.activeProcessorCount / 2))) {
        self.maxConcurrent = maxConcurrent
    }

    public func run(_ jobs: [BatchJob], to format: AudioFormat, options: ConvertOptions = ConvertOptions(),
                    onEvent: @escaping @Sendable (BatchEvent) -> Void) async {
        await withTaskGroup(of: Void.self) { group in
            var it = jobs.makeIterator()
            var running = 0
            func next() -> BatchJob? { it.next() }
            while true {
                while running < maxConcurrent, let job = next() {
                    running += 1
                    group.addTask {
                        onEvent(.started(job))
                        do {
                            var o = options; o.cancelToken = job.token
                            let out = try Converter().convert(job.source, to: format, options: o) {
                                onEvent(.progress(job, $0))
                            }
                            onEvent(.finished(job, out))
                        } catch let e as ConvertError {
                            onEvent(.failed(job, e))
                        } catch {
                            onEvent(.failed(job, .encoderFailed(error.localizedDescription)))
                        }
                    }
                }
                if running == 0 { break }
                await group.next()
                running -= 1
            }
        }
    }
}
