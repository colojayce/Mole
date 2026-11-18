import Foundation
import Observation

/// Single-slot state for the execution drawer: one terminal command at a time
/// (mo holds its own locks and sudo session, so parallel runs gain nothing).
@MainActor
@Observable
public final class CommandRunCoordinator {
    public enum State: Equatable, Sendable {
        case idle
        case running(CommandSpec, startedAt: Date)
        case finished(CommandSpec, exitCode: Int32?, duration: TimeInterval)
    }

    public nonisolated static let recentLimit = 5

    public private(set) var state: State = .idle
    /// Increments after every finished command; modules watch it to refresh stale data.
    public private(set) var completedRuns = 0
    public private(set) var recent: [CommandSpec] = []
    public private(set) var isDrawerPresented = false

    public init() {}

    public var current: CommandSpec? {
        switch state {
        case .idle: nil
        case .running(let spec, _), .finished(let spec, _, _): spec
        }
    }

    public var isRunning: Bool {
        if case .running = state { true } else { false }
    }

    public var glyph: StatusGlyphKind {
        switch state {
        case .idle: .done
        case .running: .pending
        case .finished(_, let exitCode, _): Signals.exit(exitCode)
        }
    }

    @discardableResult
    public func begin(_ spec: CommandSpec, now: Date = Date()) -> Bool {
        guard !isRunning else { return false }
        state = .running(spec, startedAt: now)
        isDrawerPresented = true
        if !spec.mutatesSystem {
            recent.removeAll { $0.arguments == spec.arguments }
            recent.insert(spec, at: 0)
            if recent.count > Self.recentLimit { recent.removeLast(recent.count - Self.recentLimit) }
        }
        return true
    }

    public func finish(_ id: UUID, exitCode: Int32?, now: Date = Date()) {
        guard case .running(let spec, let startedAt) = state, spec.id == id else { return }
        state = .finished(spec, exitCode: exitCode, duration: now.timeIntervalSince(startedAt))
        completedRuns += 1
    }

    public func presentDrawer() {
        if current != nil { isDrawerPresented = true }
    }

    /// Refused while a command runs: the PTY must stay visible until mo exits.
    @discardableResult
    public func dismissDrawer() -> Bool {
        guard !isRunning else { return false }
        isDrawerPresented = false
        return true
    }
}
