import Foundation

/// Reads fixtures straight from the source tree, so no SwiftPM resource bundle is needed.
enum Fixture {
    static func url(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: url(name))
    }

    static func text(_ name: String) throws -> String {
        String(decoding: try data(name), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Polls `condition` until it holds or `timeout` passes. Runs on the main actor
/// so it can read @MainActor services; the sleeps let their tasks progress.
@MainActor
func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}
