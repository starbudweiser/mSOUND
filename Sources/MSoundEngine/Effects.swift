import Foundation
import AudioToolbox

/// Traitements appliqués au vol (lecture et export) : gain et rampes linéaires par segment.
public enum Effects {
    /// Applique la rampe du segment à `frames` trames entrelacées. `pos` = position dans le segment, `length` = longueur du segment (même unité).
    public static func apply(_ p: UnsafeMutablePointer<Float>, frames: Int, channels: Int, pos: Int64, length: Int64, g0: Float, g1: Float) {
        if g0 == 1 && g1 == 1 { return }
        let len = Double(max(length, 1))
        if g0 == g1 {
            for i in 0..<(frames * channels) { p[i] *= g0 }
            return
        }
        let a = Double(g0), slope = Double(g1 - g0) / len
        for f in 0..<frames {
            let g = Float(a + slope * Double(pos + Int64(f)))
            for c in 0..<channels { p[f * channels + c] *= g }
        }
    }

    /// Crête absolue (linéaire) des segments, gain compris.
    public static func peak(of clips: [Clip], progress: ((Double) -> Void)? = nil) throws -> Float {
        var infos: [URL: Converter.SourceInfo] = [:]
        for c in clips where infos[c.source] == nil { infos[c.source] = try Converter.info(of: c.source) }
        guard let first = clips.first, let i0 = infos[first.source] else { return 0 }
        let channels = i0.channels, rate = i0.sampleRate
        let reader = ClipReader(clips: clips, infos: infos, outRate: rate, channels: channels)
        let total = max(reader.totalOutFrames, 1)
        let chunk: UInt32 = 32768
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(chunk) * Int(channels) * 4, alignment: 16)
        defer { raw.deallocate() }
        var peak: Float = 0, done: Int64 = 0
        while true {
            if Task.isCancelled { throw ConvertError.cancelled }
            let n = try reader.read(into: raw, maxFrames: chunk)
            if n == 0 { break }
            let p = raw.assumingMemoryBound(to: Float.self)
            for i in 0..<(Int(n) * Int(channels)) { peak = max(peak, abs(p[i])) }
            done += Int64(n); progress?(Double(done) / Double(total))
        }
        return peak
    }
}
