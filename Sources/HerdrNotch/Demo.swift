import Foundation

// Invented agents and history, used only by `--render --demo` to make screenshots that show no one's real work.

enum Demo {
    static func agents(now: Double) -> [Agent] {
        func agent(_ id: String, _ machine: String, _ space: String, _ app: String, _ state: AgentState, _ title: String,
                   minutesAgo: Double, parent: String? = nil, summary: String = "") -> Agent {
            let address = machine.isEmpty ? id : "\(machine)/\(id)"
            return Agent(id: address, machine: machine, spaceID: (machine.isEmpty ? "" : machine + "/") + "sp-" + space,
                         space: space, app: app, state: state, title: title, summary: summary,
                         cwd: (machine.isEmpty ? NSHomeDirectory() + "/code/" : "/srv/") + space,
                         isChild: parent != nil, parent: parent.map { machine.isEmpty ? $0 : "\(machine)/\($0)" },
                         statusMs: (now - minutesAgo * 60) * 1000)
        }
        return [
            agent("t1", "", "checkout-api", "claude-code", .blocked, "Add idempotency keys to refunds", minutesAgo: 9,
                  summary: "Refund retries must not charge twice"),
            agent("t2", "", "checkout-api", "codex", .done, "Review the webhook retry change", minutesAgo: 31),
            agent("t3", "", "docs-site", "claude-code", .working, "Rewrite the quickstart", minutesAgo: 35),
            agent("t4", "build-box", "mobile-app", "claude-code", .working, "Fix the offline sync queue", minutesAgo: 22),
            agent("t5", "build-box", "mobile-app", "claude-code", .working, "Reproduce the crash on a cold start", minutesAgo: 18, parent: "t4"),
            agent("t6", "build-box", "mobile-app", "claude-code", .done, "List the queue's failure modes", minutesAgo: 12, parent: "t4"),
            agent("t7", "build-box", "data-pipeline", "codex", .done, "Backfill last week's events", minutesAgo: 12),
            agent("t8", "gpu-rig", "search-index", "claude-code", .working, "Rebuild the embeddings", minutesAgo: 14),
            agent("t9", "gpu-rig", "billing-export", "codex", .idle, "Monthly export", minutesAgo: 600),
        ]
    }

    /// History for the last hour, as (state, minutes ago it started, minutes ago it ended; 0 = still going).
    static func fill(_ recorder: Recorder, agents: [Agent], now: Double) {
        let history: [String: [(String, Double, Double)]] = [
            "t1": [("working", 58, 41), ("blocked", 41, 22), ("working", 22, 9), ("blocked", 9, 0)],
            "t2": [("working", 50, 31), ("done", 31, 0)],
            "t3": [("working", 35, 0)],
            "build-box/t4": [("blocked", 47, 38), ("working", 38, 30), ("done", 30, 22), ("working", 22, 0)],
            "build-box/t5": [("working", 18, 0)],
            "build-box/t6": [("working", 20, 12), ("done", 12, 0)],
            "build-box/t7": [("working", 56, 52), ("done", 52, 44), ("working", 44, 12), ("done", 12, 0)],
            "gpu-rig/t8": [("working", 14, 0)],
        ]
        for (id, spans) in history {
            recorder.disk.spans[id] = spans.map { Span(state: $0.0, start: now - $0.1 * 60, end: $0.2 == 0 ? nil : now - $0.2 * 60) }
        }
        let visits: [(String, Double, Double)] = [("docs-site", 57, 44), ("checkout-api", 22, 15), ("build-box/mobile-app", 15, 10), ("checkout-api", 2, 0)]
        recorder.disk.you = visits.map { v in
            let name = v.0.components(separatedBy: "/").last!
            let id = v.0.contains("/") ? v.0.replacingOccurrences(of: "/", with: "/sp-") : "sp-" + v.0
            return YouSpan(spaceID: id, space: name, start: now - v.1 * 60, end: v.2 == 0 ? nil : now - v.2 * 60)
        }
        recorder.disk.since = now - 3 * 3600
    }

    static let tail = [
        "The refund handler now stores an idempotency key per request and returns the first result on a retry. The unit tests pass; I have not run it against the payment sandbox.",
        "I need a decision before going on: should a retry with the same key but a different amount be rejected, or treated as a new refund?",
    ]
}
