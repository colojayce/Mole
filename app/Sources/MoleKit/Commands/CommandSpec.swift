import Foundation

/// A `mo` invocation for the terminal channel. `arguments` excludes `mo` itself.
public struct CommandSpec: Sendable, Equatable, Identifiable {
    /// The GUI never bypasses the Trash (design doc 3).
    public static let forbiddenArguments: Set<String> = ["--permanent"]

    public let id: UUID
    public let arguments: [String]
    public let title: String
    public let mutatesSystem: Bool

    public init?(arguments: [String], title: String, mutatesSystem: Bool, id: UUID = UUID()) {
        guard !arguments.isEmpty,
              !arguments.contains(where: { Self.forbiddenArguments.contains($0) })
        else { return nil }
        self.id = id
        self.arguments = arguments
        self.title = title
        self.mutatesSystem = mutatesSystem
    }

    /// Copy-pasteable form, e.g. `mo uninstall --dry-run '腾讯会议'`.
    public var commandText: String {
        (["mo"] + arguments.map(ShellQuote.quote)).joined(separator: " ")
    }

    public var displayLine: String { "$ " + commandText }
}

public enum ShellQuote {
    private static let safe = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./=:@%+,")

    public static func quote(_ value: String) -> String {
        if !value.isEmpty, value.allSatisfy({ safe.contains($0) }) { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
