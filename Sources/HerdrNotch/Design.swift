import AppKit
import SwiftUI

// Sizes, colours, motion and the frosted-glass surface shared by every view.

// MARK: - Design values

struct Geometry {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    static let ear: CGFloat = 58
    static let wideEar: CGFloat = 98           // room for a wait time, or for an announcement under the notch
    static let panelWidth: CGFloat = 420
    static let traceWidth: CGFloat = 720
    static let announceHeight: CGFloat = 30
    static let maxPanelHeight: CGFloat = 540
    static let cardWidth: CGFloat = 340
    static let cardGap: CGFloat = 10
    static let margin: CGFloat = 44          // room around everything for shadows

    /// How far below the top of the screen the open panel floats.
    var detach: CGFloat { notchHeight + 8 }

    func closedWidth(ear: CGFloat) -> CGFloat { notchWidth + 2 * ear }
}

/// Text strengths. The weakest still clears 4.5:1 on the frosted surface over a bright window.
enum Ink {
    static let primary = Color.white.opacity(0.95)
    static let secondary = Color.white.opacity(0.72)
    static let tertiary = Color.white.opacity(0.62)
    static let hairline = Color.white.opacity(0.09)
    static let hover = Color.white.opacity(0.09)
    static let selected = Color.white.opacity(0.14)
}

enum Motion {
    static let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    static let quick = Animation.easeOut(duration: 0.14)
    static var open: Animation { reduced ? quick : .spring(response: 0.5, dampingFraction: 0.84) }
    static var close: Animation { reduced ? quick : .spring(response: 0.36, dampingFraction: 1) }
    static var card: Animation { reduced ? quick : .spring(response: 0.38, dampingFraction: 0.9) }
    static var select: Animation { reduced ? quick : .spring(response: 0.34, dampingFraction: 0.86) }
    static var glide: Animation { reduced ? quick : .spring(response: 0.26, dampingFraction: 0.88) }
}

// MARK: - Frost

/// The system's frosted glass: a live blur of whatever is behind the window.
/// A behind-window blur ignores ordinary clipping, so it is cut to shape with a mask drawn from the very same
/// path as the visible edge, at the view's real size. One source for both means the corners cannot disagree.
final class FrostView: NSVisualEffectView {
    var radius: CGFloat = 0 { didSet { if radius != oldValue { masked = .zero; needsLayout = true } } }
    var topRadius: CGFloat = 0 { didSet { if topRadius != oldValue { masked = .zero; needsLayout = true } } }
    private var masked = NSSize.zero

    override func layout() {
        super.layout()
        let size = bounds.size
        guard size != masked, size.width > 0, size.height > 0 else { return }
        masked = size
        let path = NotchShape(radius: radius, topRadius: topRadius).path(in: CGRect(origin: .zero, size: size)).cgPath
        maskImage = NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.addPath(path); ctx.setFillColor(.black); ctx.fillPath()
            return true
        }
    }
}

struct Frost: NSViewRepresentable {
    var radius: CGFloat
    var topRadius: CGFloat

    func makeNSView(context: Context) -> FrostView {
        let v = FrostView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .vibrantDark)
        v.radius = radius; v.topRadius = topRadius
        return v
    }
    func updateNSView(_ v: FrostView, context: Context) { v.radius = radius; v.topRadius = topRadius }
}

/// The notch's surface: frosted glass both closed, where it hugs the hardware notch, and open, where it floats free.
struct PanelBackdrop: View {
    let open: Bool
    var closedRadius: CGFloat = 10
    var body: some View {
        ZStack {
            Frost(radius: open ? 22 : closedRadius, topRadius: open ? 22 : 0)
            Color.black.opacity(open ? 0.2 : 0.28)
        }
    }
}

/// Content arrives out of a blur and leaves back into one.
struct FrostFade: ViewModifier {
    let amount: CGFloat
    func body(content: Content) -> some View {
        content.blur(radius: Motion.reduced ? 0 : amount * 9).opacity(1 - amount)
    }
}
extension AnyTransition {
    static var frost: AnyTransition { .modifier(active: FrostFade(amount: 1), identity: FrostFade(amount: 0)) }
}
