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
struct LiveDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var bright = false

    var body: some View {
        Circle()
            .fill(Tokens.ink)
            .frame(width: 5, height: 5)
            .opacity(bright ? 0.8 : 0.35)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { bright = true }
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
