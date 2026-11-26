import Foundation
import MSoundEngine

// Usage : msound-cli <format> <fichier>…   (mp3 m4a flac wav aiff alac)
let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2, let format = AudioFormat(rawValue: args[0].lowercased()) else {
    FileHandle.standardError.write(Data("Usage : msound-cli <mp3|m4a|flac|wav|aiff|alac> <fichier>…\n".utf8))
    exit(2)
}
let jobs = args.dropFirst().map { BatchJob(source: URL(fileURLWithPath: $0)) }
var failed = false
let lock = NSLock()
await BatchQueue().run(jobs, to: format) { ev in
    lock.lock(); defer { lock.unlock() }
    switch ev {
    case .finished(let j, let out): print("✓ \(j.source.lastPathComponent) → \(out.lastPathComponent)")
    case .failed(let j, let e): failed = true; print("✗ \(j.source.lastPathComponent) : \(e.localizedDescription)")
    default: break
    }
}
exit(failed ? 1 : 0)
