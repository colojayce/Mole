import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Vesper direction: ink on cool paper, vermilion only for what needs you (design doc 5).
enum Tokens {
    static let shell = Color(hex: 0xE6E7E0)
    static let canvas = Color(hex: 0xF7F8F3)
    static let paper = Color(hex: 0xFCFCF8)
    static let ink = Color(hex: 0x161916)
    static let ink2 = Color(hex: 0x3F453A)
    static let muted = Color(hex: 0x5E6458)
    static let faint = Color(hex: 0x62685C)
    static let line = Color(hex: 0xD8DBD0)
    static let line2 = Color(hex: 0xBFC4B6)
    static let signal = Color(hex: 0xB33B1B)
    static let signalInk = Color(hex: 0x8A2C16)
    static let signalWash = Color(hex: 0xFBF0EA)
    static let signalLine = Color(hex: 0xE7C3B4)
    static let hover = Color(hex: 0xF1F3EA)
    static let rowHover = Color(hex: 0xEDEFE6)
    static let selectedRow = Color(hex: 0xEEF1E4)
    static let track = Color(hex: 0xE4E7DC)
    static let doneDot = Color(hex: 0x8A9082)
    /// Text on an ink background (selected nav row, palette selection, toast).
    static let onInkMuted = Color(hex: 0xAEB4A6)
    static let onInkSignal = Color(hex: 0xF0916E)

    enum Size {
        static let sidebarWidth: CGFloat = 224
        static let gutter: CGFloat = 8
        static let radius: CGFloat = 7
        static let topBar: CGFloat = 56
        static let summary: CGFloat = 224
        static let tabBar: CGFloat = 48
        static let tableHeader: CGFloat = 32
        static let row: CGFloat = 48
        static let footer: CGFloat = 30
        static let drawerWidth: CGFloat = 640
    }

    /// Vesper's cubic-bezier(.2,.8,.25,1).
    static func ease(_ duration: Double) -> Animation {
        .timingCurve(0.2, 0.8, 0.25, 1, duration: duration)
    }
}

extension Font {
    /// Numbers, paths, PIDs, commands, sizes and times.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced).monospacedDigit()
    }

    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}
