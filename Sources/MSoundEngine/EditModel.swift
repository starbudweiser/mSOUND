import Foundation

/// Un morceau d'un fichier source placé sur la ligne de temps (en trames du fichier source).
public struct Clip: Equatable, Sendable {
    public var source: URL
    public var start: Int64
    public var length: Int64
    /// Gain linéaire au début et à la fin du segment (rampe linéaire entre les deux : fondus, normalisation).
    public var g0: Float = 1
    public var g1: Float = 1
    public init(source: URL, start: Int64, length: Int64) { self.source = source; self.start = start; self.length = length }
    public var hasFX: Bool { g0 != 1 || g1 != 1 }
    public var end: Int64 { start + length }
}

public struct Marker: Equatable, Sendable, Identifiable {
    public let id: UUID
    public var frame: Int64
    public var name: String
    public init(frame: Int64, name: String, id: UUID = UUID()) { self.id = id; self.frame = frame; self.name = name }
}

/// Montage non destructif : liste de segments + repères, annuler/rétablir illimité. Le fichier d'origine n'est jamais modifié.
public final class EditModel {
    public private(set) var clips: [Clip]
    public private(set) var markers: [Marker] = []
    public let sampleRate: Double

    private struct State { var clips: [Clip]; var markers: [Marker] }
    private var undoStack: [State] = []
    private var redoStack: [State] = []

    public init(source: URL, frames: Int64, sampleRate: Double) {
        clips = [Clip(source: source, start: 0, length: frames)]
        self.sampleRate = sampleRate
    }

    public var totalFrames: Int64 { clips.reduce(0) { $0 + $1.length } }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    private func push() {
        undoStack.append(State(clips: clips, markers: markers))
        redoStack.removeAll()
    }
    public func undo() {
        guard let s = undoStack.popLast() else { return }
        redoStack.append(State(clips: clips, markers: markers)); clips = s.clips; markers = s.markers
    }
    public func redo() {
        guard let s = redoStack.popLast() else { return }
        undoStack.append(State(clips: clips, markers: markers)); clips = s.clips; markers = s.markers
    }

    private func clamp(_ r: Range<Int64>) -> Range<Int64> {
        let lo = max(0, min(r.lowerBound, totalFrames)), hi = max(lo, min(r.upperBound, totalFrames))
        return lo..<hi
    }

    /// Coupe la liste à la trame `f` (sans effet aux jonctions).
    private static func split(_ f: Int64, _ arr: inout [Clip]) {
        var pos: Int64 = 0
        for i in arr.indices {
            let end = pos + arr[i].length
            if f > pos && f < end {
                let left = f - pos
                var a = arr[i], b = arr[i]
                a.length = left; b.start += left; b.length -= left
                let mid = a.g0 + (a.g1 - a.g0) * Float(left) / Float(arr[i].length)
                a.g1 = mid; b.g0 = mid
                arr.replaceSubrange(i...i, with: [a, b]); return
            }
            pos = end
        }
    }

    /// Segments couvrant exactement `range` (copie, sans modifier le montage).
    public func clips(in range: Range<Int64>) -> [Clip] {
        let r = clamp(range)
        guard r.lowerBound < r.upperBound else { return [] }
        var c = clips
        Self.split(r.lowerBound, &c); Self.split(r.upperBound, &c)
        var out: [Clip] = [], pos: Int64 = 0
        for x in c { if pos >= r.lowerBound && pos + x.length <= r.upperBound { out.append(x) }; pos += x.length }
        return out
    }

    public func delete(_ range: Range<Int64>) {
        let r = clamp(range)
        guard r.lowerBound < r.upperBound, r.upperBound - r.lowerBound < totalFrames else { return }
        push()
        var c = clips
        Self.split(r.lowerBound, &c); Self.split(r.upperBound, &c)
        var kept: [Clip] = [], pos: Int64 = 0
        for x in c { if !(pos >= r.lowerBound && pos + x.length <= r.upperBound) { kept.append(x) }; pos += x.length }
        clips = kept
        let len = r.upperBound - r.lowerBound
        markers = markers.compactMap { m in
            if m.frame >= r.lowerBound && m.frame < r.upperBound { return nil }
            var m = m; if m.frame >= r.upperBound { m.frame -= len }; return m
        }
    }

    public func keepOnly(_ range: Range<Int64>) {
        let r = clamp(range)
        guard r.lowerBound < r.upperBound else { return }
        let sel = clips(in: r)
        push()
        clips = sel
        markers = markers.compactMap { m in
            guard m.frame >= r.lowerBound && m.frame < r.upperBound else { return nil }
            var m = m; m.frame -= r.lowerBound; return m
        }
    }

    public func insert(_ new: [Clip], at frame: Int64) {
        guard !new.isEmpty else { return }
        let f = max(0, min(frame, totalFrames))
        push()
        var c = clips
        Self.split(f, &c)
        var pos: Int64 = 0, idx = c.count
        for i in c.indices { if pos >= f { idx = i; break }; pos += c[i].length }
        c.insert(contentsOf: new, at: idx)
        clips = c
        let len = new.reduce(0) { $0 + $1.length }
        markers = markers.map { var m = $0; if m.frame >= f { m.frame += len }; return m }
    }

    /// Ajoute un fichier à la fin (fusion).
    public func append(_ clip: Clip) { insert([clip], at: totalFrames) }

    /// Remplace la plage par `new` (même durée : repères inchangés) — sert aux filtres rendus en fichier.
    public func replace(_ range: Range<Int64>, with new: [Clip]) {
        let r = clamp(range)
        guard r.lowerBound < r.upperBound, !new.isEmpty else { return }
        push()
        var c = clips
        Self.split(r.lowerBound, &c); Self.split(r.upperBound, &c)
        var out: [Clip] = [], pos: Int64 = 0, inserted = false
        for x in c {
            if pos >= r.lowerBound && pos + x.length <= r.upperBound { if !inserted { out += new; inserted = true } }
            else { out.append(x) }
            pos += x.length
        }
        clips = out
        let delta = new.reduce(0) { $0 + $1.length } - (r.upperBound - r.lowerBound)
        if delta != 0 { markers = markers.map { var m = $0; if m.frame >= r.upperBound { m.frame += delta }; return m } }
    }

    /// Multiplie le gain de la plage (normalisation, gain).
    public func applyGain(_ range: Range<Int64>, factor: Float) {
        transform(range) { c, _, _ in c.g0 *= factor; c.g1 *= factor }
    }

    /// Fondu sur toute la plage : entrant (0 → 1) ou sortant (1 → 0).
    public func fade(_ range: Range<Int64>, fadeIn: Bool) {
        let r = clamp(range), span = Float(max(r.upperBound - r.lowerBound, 1))
        transform(r) { c, pos, _ in
            var p0 = Float(pos - r.lowerBound) / span, p1 = Float(pos + c.length - r.lowerBound) / span
            if !fadeIn { p0 = 1 - p0; p1 = 1 - p1 }
            c.g0 *= p0; c.g1 *= p1
        }
    }

    private func transform(_ range: Range<Int64>, _ f: (inout Clip, Int64, Int) -> Void) {
        let r = clamp(range)
        guard r.lowerBound < r.upperBound else { return }
        push()
        var c = clips
        Self.split(r.lowerBound, &c); Self.split(r.upperBound, &c)
        var pos: Int64 = 0
        for i in c.indices {
            if pos >= r.lowerBound && pos + c[i].length <= r.upperBound { f(&c[i], pos, i) }
            pos += c[i].length
        }
        clips = c
    }

    public func addMarker(at frame: Int64, name: String) {
        push()
        markers.append(Marker(frame: max(0, min(frame, totalFrames)), name: name))
        markers.sort { $0.frame < $1.frame }
    }
    public func addMarkers(_ list: [Marker]) {
        guard !list.isEmpty else { return }
        push(); markers += list; markers.sort { $0.frame < $1.frame }
    }
    public func removeMarker(_ id: UUID) {
        guard markers.contains(where: { $0.id == id }) else { return }
        push(); markers.removeAll { $0.id == id }
    }
}
