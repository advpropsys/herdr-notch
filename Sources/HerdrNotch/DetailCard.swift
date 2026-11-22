import AppKit
import SwiftUI

// The card that slides out beside the panel when the pointer rests on a workspace.

/// What is going on inside one workspace: every agent in it, and the latest lines from the most urgent one.
struct DetailCard: View {
    @ObservedObject var store: Store
    let space: Workspace

    var path: String {
        let home = NSHomeDirectory()
        let cwd = space.top.cwd
        return cwd.hasPrefix(home) ? "~" + cwd.dropFirst(home.count) : cwd
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(space.name).font(.system(size: 15, weight: .semibold)).foregroundColor(Ink.primary).lineLimit(1)
                Text("\(machineName(space.machine))  ·  \(path)").font(.system(size: 11.5)).foregroundColor(Ink.secondary)
                    .lineLimit(1).truncationMode(.middle)
                if !space.top.summary.isEmpty {
                    Text(space.top.summary).font(.system(size: 12.5)).foregroundColor(Ink.primary.opacity(0.85))
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true).padding(.top, 5)
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            Rectangle().fill(Ink.hairline).frame(height: 1)

            VStack(spacing: 0) {
                ForEach(space.agents.prefix(5)) { a in AgentLine(agent: a) { store.jump(to: a) } }
                if space.agents.count > 5 {
                    Text("and \(space.agents.count - 5) more").font(.system(size: 11.5)).foregroundColor(Ink.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).frame(height: 24)
                }
            }.padding(.vertical, 5)

            Rectangle().fill(Ink.hairline).frame(height: 1)

            VStack(alignment: .leading, spacing: 8) {
                Text("Latest from \(space.top.appName)").font(.system(size: 11.5, weight: .semibold)).foregroundColor(Ink.tertiary)
                if let parts = store.tail {
                    if parts.isEmpty {
                        Text("Nothing readable on its screen yet.").font(.system(size: 12.5)).foregroundColor(Ink.secondary)
                    } else {
                        // The newest message reads as the answer; the one before it is quieter context.
                        VStack(alignment: .leading, spacing: 9) {
                            ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                                let newest = i == parts.count - 1
                                Text(part).font(.system(size: 12.5)).lineSpacing(3.5)
                                    .foregroundColor(newest ? Ink.primary : Ink.secondary)
                                    .lineLimit(newest ? 7 : 3).truncationMode(.tail)
                                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .id(parts).transition(.frost)
                    }
                } else {
                    Skeleton().accessibilityLabel("Reading the terminal").transition(.frost)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, 11).padding(.bottom, 14)
            .animation(Motion.card, value: store.tail)
        }
        .frame(width: Geometry.cardWidth)
        .background(ZStack { Frost(radius: 18, topRadius: 18); Color.black.opacity(0.2) })
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .circular))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .circular).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .compositingGroup()
        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
        .background(GeometryReader { g in
            Color.clear.onAppear { store.cardHeight = g.size.height }
                .onChange(of: g.size.height) { store.cardHeight = $0 }
        })
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Stand-in lines while the terminal is being read, the same size as the text that replaces them.
struct Skeleton: View {
    @State private var on = false
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach([0.92, 0.7, 0.84, 0.46], id: \.self) { w in
                Capsule().fill(Color.white.opacity(0.1)).frame(width: (Geometry.cardWidth - 32) * w, height: 7)
            }
        }
        .padding(.vertical, 4)
        .opacity(on ? 0.45 : 1)
        .onAppear {
            guard !Motion.reduced else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { on = true }
        }
    }
}

struct AgentLine: View {
    let agent: Agent
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Mark(state: agent.state, size: agent.isChild ? 6 : 8).frame(width: 12)
                    .padding(.leading, agent.isChild ? 12 : 0)
                Text(agent.appName).font(.system(size: 12.5, weight: .medium)).foregroundColor(Ink.primary).fixedSize()
                Text(agent.title).font(.system(size: 12)).foregroundColor(Ink.secondary).lineLimit(1)
                Spacer(minLength: 6)
                Text(agent.state == .idle || agent.state == .done ? ago(agent.statusMs) : agent.state.label)
                    .font(.system(size: 11.5)).monospacedDigit().foregroundColor(agent.state == .blocked ? agent.state.color : Ink.tertiary).fixedSize()
            }
            .padding(.horizontal, 10).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hover ? Ink.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle()).padding(.horizontal, 6)
        .onHover { h in withAnimation(Motion.quick) { hover = h } }
        .accessibilityLabel("\(agent.appName), \(agent.state.label), \(agent.title)")
    }
}
