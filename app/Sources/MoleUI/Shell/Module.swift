import SwiftUI

/// Sidebar entries in display order; ⌘1–⌘9 follow this order.
enum Module: String, CaseIterable, Identifiable {
    case dashboard, clean, projects, installer, apps, slim, space, optimize, history

    enum NavGroup: String, CaseIterable {
        case monitor = "MONITOR"
        case reclaim = "RECLAIM"
        case apps = "APPS"
        case disk = "DISK"
        case care = "CARE"
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .clean: "Clean"
        case .projects: "Projects"
        case .installer: "Installer"
        case .apps: "Apps"
        case .slim: "Slim"
        case .space: "Space"
        case .optimize: "Optimize"
        case .history: "History"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.33percent"
        case .clean: "sparkles"
        case .projects: "hammer"
        case .installer: "shippingbox"
        case .apps: "square.grid.2x2"
        case .slim: "scissors"
        case .space: "square.split.2x2"
        case .optimize: "wrench.adjustable"
        case .history: "clock.arrow.circlepath"
        }
    }

    var group: NavGroup {
        switch self {
        case .dashboard: .monitor
        case .clean, .projects, .installer: .reclaim
        case .apps, .slim: .apps
        case .space: .disk
        case .optimize, .history: .care
        }
    }

    /// Milestone that wires the module up (design doc 11).
    var milestone: String {
        switch self {
        case .dashboard: "M2"
        case .apps, .slim, .history: "M4"
        case .clean, .installer: "M5"
        case .space: "M6"
        case .projects, .optimize: "M7"
        }
    }

    var shortcutDigit: Character {
        Character(String((Module.allCases.firstIndex(of: self) ?? 0) + 1))
    }
}
