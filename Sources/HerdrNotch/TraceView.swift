import AppKit
import SwiftUI

// The trace drawn like a profiler: a lane for you, a lane per agent, and a mini version for the closed notch.

// MARK: - Trace view

enum TraceLayout {
    static let label: CGFloat = 232
    static let figure: CGFloat = 76
    static let lane: CGFloat = 30
    static let childLane: CGFloat = 20
    static let youLane: CGFloat = 30
    static let axis: CGFloat = 24
    static let controls: CGFloat = 34
    static let finding: CGFloat = 30
    static let ranges: [(String, Double)] = [("1h", 3600), ("6h", 6 * 3600), ("24h", 24 * 3600)]

    static func height(_ t: Trace) -> CGFloat {
        let lanes = t.lanes.reduce(CGFloat(0)) { $0 + ($1.isChild ? childLane : lane) }
        return controls + finding + youLane + 6 + (t.lanes.isEmpty ? 56 : lanes) + axis + (t.hidden > 0 ? 22 : 0) + 8
    }
}

struct TraceView: View {
    @ObservedObject var store: Store
    let trace: Trace
    @Namespace private var ns

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            controls.frame(height: TraceLayout.controls)
            finding.frame(height: TraceLayout.finding)
            GeometryReader { g in
                let track = g.size.width - TraceLayout.label - TraceLayout.figure - 18
                ZStack(alignment: .topLeading) {
                    Grid(trace: trace, range: store.range).frame(width: track).offset(x: TraceLayout.label)
                    VStack(alignment: .leading, spacing: 0) {
                        youLane(track)
                        Rectangle().fill(Ink.hairline).frame(height: 1).padding(.vertical, 2.5)
                        if trace.lanes.isEmpty {
                            Text("Nothing ran in this window. Agents appear here as they work.")
                                .font(.system(size: 12.5)).foregroundColor(Ink.secondary)
                                .frame(maxWidth: .infinity).frame(height: 56)
                        }
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(trace.lanes) { lane in LaneRow(store: store, trace: trace, lane: lane, track: track, ns: ns) }
                                if trace.hidden > 0 {
                                    Text("and \(trace.hidden) quieter agents").font(.system(size: 11.5)).foregroundColor(Ink.tertiary)
                                        .padding(.leading, 18).frame(height: 22)
                                }
                            }
                        }
                        Axis(trace: trace, range: store.range, track: track).frame(height: TraceLayout.axis)
                    }
                }
            }
        }
    }

    var controls: some View {
        HStack(spacing: 2) {
            ForEach(TraceLayout.ranges, id: \.1) { name, seconds in
                let on = store.range == seconds
                Button { withAnimation(Motion.select) { store.range = seconds } } label: {
                    Text(name).font(.system(size: 12, weight: on ? .semibold : .medium)).monospacedDigit()
                        .foregroundColor(on ? Ink.primary : Ink.secondary)
                        .padding(.horizontal, 10).frame(height: 26)
                        .background { if on { Capsule().fill(Ink.selected).matchedGeometryEffect(id: "range", in: ns) } }
                        .contentShape(Capsule())
                }.buttonStyle(PressStyle())
            }
            Spacer()
            if trace.recordingSince > trace.start {
                Text("Recording since \(clock(trace.recordingSince))").font(.system(size: 11.5)).foregroundColor(Ink.tertiary)
                    .help("Herdr only reports what agents are doing now, so the trace starts when this app first ran.")
            }
        }
        .padding(.leading, 10).padding(.trailing, 18)
    }

    /// The one finding the trace exists to show.
    var finding: some View {
        HStack(spacing: 7) {
            if trace.waitedTotal > 0 {
                Mark(state: .blocked, size: 8)
                Text("Agents waited on you for \(duration(trace.waitedTotal))")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundColor(Ink.primary)
                Text("across \(trace.waitingAgents) \(trace.waitingAgents == 1 ? "agent" : "agents")")
                    .font(.system(size: 12.5)).foregroundColor(Ink.secondary)
            } else {
                Text("Nothing waited on you in this window.").font(.system(size: 12.5)).foregroundColor(Ink.secondary)
            }
            Spacer()
        }.padding(.horizontal, 18)
    }

    func youLane(_ track: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text("You").font(.system(size: 12.5, weight: .semibold)).foregroundColor(Ink.primary)
                .frame(width: TraceLayout.label - 18, alignment: .leading).padding(.leading, 18)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.05)).frame(width: track, height: 14)
                ForEach(Array(trace.you.enumerated()), id: \.offset) { _, y in
                    let a = trace.x(max(y.start, trace.start), track), b = trace.x(min(y.end ?? trace.end, trace.end), track)
                    let w = max(2, b - a)
                    RoundedRectangle(cornerRadius: 3.5).fill(Color.white.opacity(0.82))
                        .overlay(alignment: .leading) {
                            if w > 54 {
                                Text(y.space).font(.system(size: 10.5, weight: .semibold)).foregroundColor(.black.opacity(0.78))
                                    .lineLimit(1).padding(.horizontal, 5)
                            }
                        }
                        .frame(width: w, height: 14).offset(x: a)
                        .help("You were in \(y.space), \(clock(y.start)) to \(y.end.map(clock) ?? "now")")
                }
            }.frame(width: track, alignment: .leading)
            Spacer(minLength: 0)
        }.frame(height: TraceLayout.youLane)
    }
}

struct LaneRow: View {
    @ObservedObject var store: Store
    let trace: Trace
    let lane: Lane
    let track: CGFloat
    let ns: Namespace.ID
    @State private var hover = false

    var body: some View {
        let h = lane.isChild ? TraceLayout.childLane : TraceLayout.lane
        let bar: CGFloat = lane.isChild ? 6 : 12
        Button { store.jump(toAgent: lane.id) } label: {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    if lane.isChild {
                        Text(lane.meta.title.isEmpty ? "helper" : lane.meta.title).font(.system(size: 11.5)).foregroundColor(Ink.tertiary).lineLimit(1)
                    } else {
                        // Several agents can share a workspace, so each lane also says what its agent is doing.
                        (Text(lane.meta.space).font(.system(size: 12.5, weight: .medium)).foregroundColor(Ink.primary)
                         + Text(lane.meta.title.isEmpty ? "" : "   \(lane.meta.title)").font(.system(size: 11.5)).foregroundColor(Ink.secondary))
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
                .frame(width: TraceLayout.label - (lane.isChild ? 40 : 28), alignment: .leading)
                .padding(.leading, lane.isChild ? 30 : 18).padding(.trailing, 10)

                ZStack(alignment: .leading) {
                    ForEach(lane.segments) { s in
                        let a = trace.x(s.start, track), w = max(s.state == .idle ? 0 : 2, trace.x(s.end, track) - a)
                        segment(s, bar).frame(width: w).offset(x: a)
                            .help("\(lane.meta.space): \(s.state.label), \(clock(s.start)) to \(s.end >= trace.end - 1 ? "now" : clock(s.end)) (\(duration(s.length)))")
                    }
                    // Your time in this agent's space, as a thin line under its bar: where your attention overlapped it.
                    ForEach(lane.yours) { y in
                        let a = trace.x(y.start, track)
                        Capsule().fill(Color.white.opacity(0.8)).frame(width: max(2, trace.x(y.end, track) - a), height: 2)
                            .offset(x: a, y: bar / 2 + 3.5)
                    }
                }.frame(width: track, height: h, alignment: .leading)

                Group {
                    if lane.waited >= 60 {
                        Text("waited \(duration(lane.waited))").foregroundColor(AgentState.blocked.color)
                            .help(lane.unattended >= 60 ? "\(duration(lane.unattended)) of that while you were somewhere else" : "You were with it the whole time")
                    } else if lane.ran >= 60 && !lane.isChild {
                        Text("ran \(duration(lane.ran))").foregroundColor(Ink.tertiary)
                    }
                }
                .font(.system(size: 11.5)).monospacedDigit().lineLimit(1)
                .frame(width: TraceLayout.figure, alignment: .trailing).padding(.trailing, 18)
            }
            .frame(height: h)
            .background(RoundedRectangle(cornerRadius: 7).fill(hover || store.hoveredID == lane.meta.spaceID ? Ink.hover : .clear).padding(.horizontal, 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { on in
            withAnimation(Motion.quick) { hover = on }
            if on { store.requestHover(lane.meta.spaceID) } else { store.cancelPendingHover() }
        }
        .accessibilityLabel("\(lane.meta.space), waited \(duration(lane.waited)), ran \(duration(lane.ran))")
    }

    /// Needing you is the loud one. Working is steady. Finished is a quiet trail until you look at it.
    @ViewBuilder func segment(_ s: Segment, _ bar: CGFloat) -> some View {
        switch s.state {
        case .blocked: RoundedRectangle(cornerRadius: bar / 4).fill(s.state.color).frame(height: bar)
        case .working: RoundedRectangle(cornerRadius: bar / 4).fill(s.state.color.opacity(0.78)).frame(height: bar)
        case .done: Capsule().fill(s.state.color.opacity(0.5)).frame(height: max(3, bar / 3))
        case .idle: Color.clear.frame(height: bar)
        }
    }
}

/// Faint vertical lines at each tick, behind every lane.
struct Grid: View {
    let trace: Trace
    let range: Double
    var body: some View {
        GeometryReader { g in
            ForEach(Axis.ticks(trace, range), id: \.self) { t in
                Rectangle().fill(Ink.hairline).frame(width: 1).offset(x: trace.x(t, g.size.width))
            }
            Rectangle().fill(Color.white.opacity(0.28)).frame(width: 1).offset(x: g.size.width - 1)
        }
    }
}

struct Axis: View {
    let trace: Trace
    let range: Double
    let track: CGFloat

    static func ticks(_ t: Trace, _ range: Double) -> [Double] {
        let step: Double = range <= 3600 ? 900 : (range <= 6 * 3600 ? 3600 : 6 * 3600)
        var out: [Double] = []
        var x = (t.start / step).rounded(.up) * step
        while x < t.end - step * 0.25 { out.append(x); x += step }
        return out
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Self.ticks(trace, range), id: \.self) { t in
                Text(clock(t)).font(.system(size: 11.5)).monospacedDigit().foregroundColor(Ink.tertiary)
                    .fixedSize().offset(x: TraceLayout.label + trace.x(t, track) + 4, y: 5)
            }
            Text("now").font(.system(size: 11.5, weight: .medium)).foregroundColor(Ink.secondary)
                .fixedSize().offset(x: TraceLayout.label + track + 5, y: 5)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// The last hour in the space of a counter: the four lanes that matter most, as hairline bars.
/// It balances the closed notch and shows at a glance whether things are moving or waiting.
struct MiniTrace: View {
    let trace: Trace?
    static let width: CGFloat = 38
    static let lanes = 4

    var body: some View {
        let tops = (trace?.lanes ?? []).filter { !$0.isChild }.prefix(Self.lanes)
        VStack(spacing: 1.5) {
            ForEach(0..<Self.lanes, id: \.self) { i in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.13)).frame(width: Self.width, height: 2.5)
                    if let trace, i < tops.count {
                        ForEach(tops[tops.startIndex + i].segments) { s in
                            if s.state == .blocked || s.state == .working {
                                let a = trace.x(s.start, Self.width)
                                Capsule().fill(s.state.color)
                                    .frame(width: max(2.5, trace.x(s.end, Self.width) - a), height: 2.5).offset(x: a)
                            }
                        }
                    }
                }.frame(width: Self.width, alignment: .leading).clipShape(Capsule())
            }
        }
        .accessibilityLabel("Agent activity over the last hour")
    }
}
