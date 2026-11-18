import AppKit
import SwiftTerm

/// The terminal is the only dark surface: ink background, paper text,
/// low-saturation ANSI colours. Red uses Vesper's on-ink signal (#F0916E),
/// because #B33B1B on ink is too dark to read.
enum TerminalTheme {
    static let backgroundHex: UInt32 = 0x161916 // Tokens.ink
    static let foregroundHex: UInt32 = 0xFCFCF8 // Tokens.paper

    /// black, red, green, yellow, blue, magenta, cyan, white, then the bright variants.
    static let ansiHex: [UInt32] = [
        0x161916, 0xF0916E, 0x9DB38A, 0xD8C27A, 0x8FA8C0, 0xB89AB5, 0x8DB8B0, 0xD5DACD,
        0x62685C, 0xF4A88B, 0xB5C9A2, 0xE6D396, 0xA9BFD4, 0xCCB2C9, 0xA6CCC4, 0xFCFCF8,
    ]

    @MainActor
    static func apply(to view: TerminalView) {
        view.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        view.nativeBackgroundColor = nsColor(backgroundHex)
        view.nativeForegroundColor = nsColor(foregroundHex)
        view.caretColor = nsColor(foregroundHex)
        view.installColors(ansiHex.map(terminalColor))
    }

    static func nsColor(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// SwiftTerm colours take 16-bit components.
    static func terminalColor(_ hex: UInt32) -> SwiftTerm.Color {
        SwiftTerm.Color(
            red: UInt16((hex >> 16) & 0xFF) * 257,
            green: UInt16((hex >> 8) & 0xFF) * 257,
            blue: UInt16(hex & 0xFF) * 257
        )
    }
}
