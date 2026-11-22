import AppKit
import SwiftUI

// Herdr only reports what each agent is doing now, so the history behind the trace is recorded here.

// MARK: - Recording

struct Span: Codable, Equatable {
    var state: String
    var start: Double       // seconds since 1970
    var end: Double?        // nil while it is still going
}

struct LaneMeta: Codable {
    var space: String
    var spaceID: String
    var machine: String
    var title: String
    var app: String
    var parent: String?
}

struct YouSpan: Codable {
    var spaceID: String
    var space: String
    var start: Double
    var end: Double?
}

struct Transition {
    let agent: Agent
    let to: AgentState
}

final class Recorder {
    struct Disk: Codable {
        var since: Double
        var spans: [String: [Span]] = [:]
        var meta: [String: LaneMeta] = [:]
        var you: [YouSpan] = []
    }

    var disk: Disk
    static let keep: Double = 24 * 3600
    private let url: URL
    private let persist: Bool
    private var lastSave = 0.0

    init(persist: Bool = true) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Herdr Notch", isDirectory: true)
        url = dir.appendingPathComponent("history.json")
        self.persist = persist
        let now = Date().timeIntervalSince1970
        if persist, let data = try? Data(contentsOf: url), var d = try? JSONDecoder().decode(Disk.self, from: data) {
            // The app was not watching while it was closed: end whatever was open at the last save.
            let stopped = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate?.timeIntervalSince1970) ?? now
            for k in d.spans.keys { if let i = d.spans[k]?.indices.last, d.spans[k]![i].end == nil { d.spans[k]![i].end = stopped } }
            if let i = d.you.indices.last, d.you[i].end == nil { d.you[i].end = stopped }
            // Earlier builds split one unchanged stretch at every restart, which made old agents look freshly changed.
            for (k, list) in d.spans {
                var merged: [Span] = []
                for s in list {
                    if let last = merged.last, last.state == s.state { merged[merged.count - 1].end = s.end } else { merged.append(s) }
                }
                d.spans[k] = merged
            }
            disk = d
        } else {
            disk = Disk(since: now)
        }
        if persist { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
    }

    /// Fold the current agents into the history. Returns what changed since the last look.
    func record(_ agents: [Agent], now: Double) -> [Transition] {
        var changed: [Transition] = []
        var seen = Set<String>()
        for a in agents {
            seen.insert(a.id)
            disk.meta[a.id] = LaneMeta(space: a.space, spaceID: a.spaceID, machine: a.machine, title: a.title, app: a.app, parent: a.parent)
            let since = a.statusMs > 0 ? min(now, a.statusMs / 1000) : now
            var list = disk.spans[a.id] ?? []
            if let last = list.last, last.end == nil {
                if last.state != a.state.rawValue {
                    let at = max(last.start, since)
                    list[list.count - 1].end = at
                    list.append(Span(state: a.state.rawValue, start: at, end: nil))
                    changed.append(Transition(agent: a, to: a.state))
                }
            } else if let last = list.last {
                // Seen before, then lost for a while (the app was closed, or the machine dropped off).
                if last.state == a.state.rawValue {
                    list[list.count - 1].end = nil          // nothing changed meanwhile: it is the same stretch
                } else {
                    list.append(Span(state: a.state.rawValue, start: max(last.end ?? since, since), end: nil))
                }
            } else {
                list.append(Span(state: a.state.rawValue, start: max(since, now - Self.keep), end: nil))
            }
            disk.spans[a.id] = list
        }
        for (id, list) in disk.spans where !seen.contains(id) {
            if let i = list.indices.last, list[i].end == nil { disk.spans[id]![i].end = now }
        }
        prune(now)
        if now - lastSave > 20 || !changed.isEmpty { save(now) }
        return changed
    }

    /// Where your attention is: the Herdr space in front of you, or nil when Herdr is not the front app.
    func recordYou(spaceID: String?, space: String, now: Double) {
        if let i = disk.you.indices.last, disk.you[i].end == nil {
            if disk.you[i].spaceID == spaceID { return }
            disk.you[i].end = now
        }
        if let id = spaceID { disk.you.append(YouSpan(spaceID: id, space: space, start: now, end: nil)) }
    }

    private func prune(_ now: Double) {
        let cut = now - Self.keep
        for (id, list) in disk.spans {
            let kept = list.filter { ($0.end ?? now) > cut }
            if kept.isEmpty { disk.spans[id] = nil; disk.meta[id] = nil } else if kept.count != list.count { disk.spans[id] = kept }
        }
        disk.you.removeAll { ($0.end ?? now) <= cut }
    }

    func save(_ now: Double) {
        lastSave = now
        guard persist else { return }
        if let data = try? JSONEncoder().encode(disk) { try? data.write(to: url, options: .atomic) }
    }
}
