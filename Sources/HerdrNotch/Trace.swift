import AppKit
import SwiftUI

// The trace model: recorded history cut to a time window and sorted by what cost you the most.

// MARK: - Trace model

struct Segment: Identifiable {
    let id: Int
    let state: AgentState
    let start: Double
    let end: Double
    var length: Double { end - start }
}

struct Lane: Identifiable {
    let id: String              // agent address
    let meta: LaneMeta
    let segments: [Segment]     // clipped to the window
    let yours: [Segment]        // when you had this agent's space in front of you
    let waited: Double          // seconds it needed you, in the window
    let unattended: Double      // of those, seconds you were somewhere else
    let ran: Double
    let current: AgentState?
    let isChild: Bool
    let lastChange: Double
}

struct Trace {
    let start: Double
    let end: Double
    let you: [YouSpan]
    let lanes: [Lane]
    let hidden: Int
    let waitedTotal: Double
    let waitingAgents: Int
    let recordingSince: Double

    func x(_ t: Double, _ width: CGFloat) -> CGFloat { CGFloat((t - start) / (end - start)) * width }
}

func duration(_ s: Double) -> String {
    if s < 60 { return "under 1m" }
    if s < 3600 { return "\(Int(s / 60))m" }
    let h = Int(s / 3600), m = Int(s.truncatingRemainder(dividingBy: 3600) / 60)
    return m == 0 ? "\(h)h" : "\(h)h \(m)m"
}

func clock(_ t: Double) -> String {
    let f = DateFormatter(); f.dateFormat = "HH:mm"
    return f.string(from: Date(timeIntervalSince1970: t))
}

extension Recorder {
    /// The trace for the last `range` seconds. Lanes that needed you come first, longest wait on top; then what is
    /// running; then the rest by how recently they changed. Helpers sit directly under the agent that started them.
    func trace(range: Double, now: Double, machine: String?, limit: Int = 12) -> Trace {
        let start = now - range
        let you = disk.you.filter { ($0.end ?? now) > start }

        func overlap(_ a0: Double, _ a1: Double, in spaceID: String) -> Double {
            you.reduce(0) { sum, y in
                guard y.spaceID == spaceID else { return sum }
                return sum + max(0, min(a1, y.end ?? now) - max(a0, y.start))
            }
        }

        var all: [Lane] = []
        for (id, spans) in disk.spans {
            guard let meta = disk.meta[id], machine == nil || meta.machine == machine else { continue }
            var segs: [Segment] = []
            var waited = 0.0, unattended = 0.0, ran = 0.0, lastChange = 0.0
            for (i, s) in spans.enumerated() {
                guard let state = AgentState(rawValue: s.state) else { continue }
                let a = max(s.start, start), b = min(s.end ?? now, now)
                lastChange = max(lastChange, s.start)
                guard b > a else { continue }
                segs.append(Segment(id: i, state: state, start: a, end: b))
                if state == .blocked { waited += b - a; unattended += (b - a) - overlap(a, b, in: meta.spaceID) }
                if state == .working { ran += b - a }
            }
            let live = spans.last?.end == nil ? spans.last.flatMap { AgentState(rawValue: $0.state) } : nil
            // Idle and long-finished agents are not part of the story in this window.
            let changedInWindow = spans.contains { $0.start > start && $0.state != AgentState.idle.rawValue }
            guard waited > 0 || ran > 0 || changedInWindow else { continue }
            let yours = you.enumerated().compactMap { (i, y) -> Segment? in
                guard y.spaceID == meta.spaceID else { return nil }
                let a = max(y.start, start), b = min(y.end ?? now, now)
                return b > a ? Segment(id: i, state: .idle, start: a, end: b) : nil
            }
            all.append(Lane(id: id, meta: meta, segments: segs, yours: yours, waited: waited, unattended: max(0, unattended),
                            ran: ran, current: live, isChild: meta.parent != nil, lastChange: lastChange))
        }

        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        func rank(_ l: Lane) -> (Int, Double) {
            if l.current == .blocked { return (0, -l.waited) }
            if l.waited > 0 { return (1, -l.waited) }
            if l.current == .working { return (2, -l.ran) }
            return (3, -l.lastChange)
        }
        let tops = all.filter { $0.meta.parent == nil || byID[$0.meta.parent!] == nil }.sorted { rank($0) < rank($1) }
        var lanes: [Lane] = []
        for top in tops.prefix(limit) {
            lanes.append(top)
            let kids = all.filter { $0.meta.parent == top.id }.sorted { ($0.segments.first?.start ?? 0) < ($1.segments.first?.start ?? 0) }
            lanes.append(contentsOf: kids.prefix(4))
        }
        return Trace(start: start, end: now, you: you, lanes: lanes, hidden: max(0, tops.count - limit),
                     waitedTotal: all.reduce(0) { $0 + $1.waited }, waitingAgents: all.filter { $0.waited > 0 }.count,
                     recordingSince: disk.since)
    }
}
