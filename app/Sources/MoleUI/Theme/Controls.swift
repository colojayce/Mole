import AppKit
import SwiftUI

/// Uppercase group label: MEMORY, RECLAIMABLE, MONITOR.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.ui(10, weight: .semibold))
            .tracking(0.9)
            .foregroundStyle(Tokens.muted)
    }
}

/// 5 pt ink dot that breathes every 3.2 s while something is live.
///
/// The breath runs as a Core Animation layer animation in the render server.
/// A SwiftUI `repeatForever` animation re-renders the view tree every display
/// frame and held the Dashboard at 14–25% CPU (design budget < 5%).
struct LiveDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BreathingDotLayer(animated: !reduceMotion)
            .frame(width: 5, height: 5)
    }
}

private struct BreathingDotLayer: NSViewRepresentable {
    let animated: Bool
    private static let key = "breath"

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = view.layer!
        layer.backgroundColor = NSColor(Tokens.ink).cgColor
        layer.cornerRadius = 2.5
        layer.opacity = 0.35
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let layer = view.layer else { return }
        if !animated {
            layer.removeAnimation(forKey: Self.key)
        } else if layer.animation(forKey: Self.key) == nil {
            let breath = CABasicAnimation(keyPath: "opacity")
            breath.fromValue = 0.35
            breath.toValue = 0.8
            breath.duration = 1.6
            breath.autoreverses = true
            breath.repeatCount = .infinity
            breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            breath.isRemovedOnCompletion = false
            layer.add(breath, forKey: Self.key)
        }
    }
}

/// Module entrance: fade in and rise 4 pt (design doc 5.8).
struct EnterOnAppear: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 4)
            .onAppear {
                if reduceMotion {
                    shown = true
                } else {
                    withAnimation(Tokens.ease(0.4).delay(delay)) { shown = true }
                }
            }
    }
}

extension View {
    func enterOnAppear(delay: Double = 0) -> some View {
        modifier(EnterOnAppear(delay: delay))
    }
}

struct MoleButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    var kind: Kind = .secondary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let primary = kind == .primary
        return configuration.label
            .font(.ui(11.5, weight: .medium))
            .foregroundStyle(primary ? Tokens.paper : Tokens.ink)
            .padding(.horizontal, 10)
            .frame(height: 29)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(primary
                        ? (configuration.isPressed ? Color(hex: 0x2A2F27) : Tokens.ink)
                        : (configuration.isPressed ? Tokens.hover : Tokens.paper))
            )
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(primary ? Tokens.ink : Tokens.line2))
            .opacity(isEnabled ? 1 : 0.45)
            .offset(y: configuration.isPressed ? 1 : 0)
    }
}
