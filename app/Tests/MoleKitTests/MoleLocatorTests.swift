import Foundation
import Testing
@testable import MoleKit

private func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("moleui-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Writes a tiny /bin/sh program (no .sh suffix) and marks it executable unless told not to.
@discardableResult
private func writeProgram(_ dir: URL, _ name: String, _ body: String, executable: Bool = true) throws -> String {
    let url = dir.appendingPathComponent(name)
    try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: url.path)
    return url.path
}

@Suite struct MoleLocatorTests {
    @Test func candidatesPutRepoFirstAndDropDuplicates() {
        let locator = MoleLocator(explicitPath: nil, repoPath: "/r", searchPath: "/a:/b::/a")
        #expect(locator.candidates() == ["/r/mole", "/a/mo", "/a/mole", "/b/mo", "/b/mole"])
    }

    @Test func explicitPathWins() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let explicit = try writeProgram(dir, "custom-mole", "echo 'Mole version 2.0.0'")
        try writeProgram(dir, "mole", "echo 'Mole version 1.0.0'")
        let locator = MoleLocator(explicitPath: explicit, repoPath: dir.path, searchPath: "")
        let found = try await locator.locate(using: DataRunner(), environment: [:])
        #expect(found.version == "2.0.0")
        #expect(found.executableURL.path == explicit)
    }

    @Test func explicitPathThatIsNotExecutableIsReported() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try writeProgram(dir, "mole", "echo 'Mole version 1.0.0'", executable: false)
        let locator = MoleLocator(explicitPath: path, repoPath: nil, searchPath: "")
        await #expect(throws: MoleLocatorError.notExecutable(path: path)) {
            try await locator.locate(using: DataRunner(), environment: [:])
        }
    }

    @Test func fallsBackFromRepoToPath() async throws {
        let repo = try makeTempDir()
        let bin = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: repo)
            try? FileManager.default.removeItem(at: bin)
        }
        try writeProgram(bin, "mo", "echo 'Mole version 1.71.0'")
        let locator = MoleLocator(explicitPath: nil, repoPath: repo.path, searchPath: bin.path)
        let found = try await locator.locate(using: DataRunner(), environment: [:])
        #expect(found.executableURL.path == bin.appendingPathComponent("mo").path)
        #expect(found.version == "1.71.0")
    }

    @Test func notFoundListsEverythingSearched() async {
        let locator = MoleLocator(explicitPath: nil, repoPath: "/nonexistent-repo", searchPath: "/nonexistent-bin")
        await #expect(throws: MoleLocatorError.notFound(searched: [
            "/nonexistent-repo/mole", "/nonexistent-bin/mo", "/nonexistent-bin/mole",
        ])) {
            try await locator.locate(using: DataRunner(), environment: [:])
        }
    }

    @Test func versionCommandFailureIsReported() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try writeProgram(dir, "mole", "echo broken >&2; exit 1")
        let locator = MoleLocator(explicitPath: path, repoPath: nil, searchPath: "")
        do {
            _ = try await locator.locate(using: DataRunner(), environment: [:])
            Issue.record("expected versionCheckFailed")
        } catch let error as MoleLocatorError {
            guard case .versionCheckFailed(let failedPath, let detail) = error else {
                Issue.record("wrong case \(error)")
                return
            }
            #expect(failedPath == path)
            #expect(detail.contains("broken"))
            #expect(error.description.contains("--version"))
        }
    }

    @Test func parsesVersionLine() {
        #expect(MoleLocator.parseVersion("Mole version 1.71.0\nmacOS: 27.0.1\n") == "1.71.0")
        #expect(MoleLocator.parseVersion("hello") == nil)
    }

    @Test func environmentStripsTestSwitchesAndExtendsPath() {
        let env = MoleEnvironment.make(base: [
            "PATH": "/usr/bin:/custom",
            "MOLE_TEST_NO_AUTH": "1",
            "MOLE_TEST_MODE": "1",
            "MO_NO_OPLOG": "1",
            "MOLE_DRY_RUN": "1",
            "HOME": "/Users/x",
        ])
        #expect(env["MOLE_TEST_NO_AUTH"] == nil)
        #expect(env["MOLE_TEST_MODE"] == nil)
        #expect(env["MO_NO_OPLOG"] == nil)
        #expect(env["MOLE_DRY_RUN"] == nil)
        #expect(env["HOME"] == "/Users/x")
        #expect(env["PATH"] == "/usr/bin:/custom:/opt/homebrew/bin:/usr/local/bin:/bin:/usr/sbin:/sbin")
        #expect(env["LANG"] == "en_US.UTF-8")
        #expect(MoleEnvironment.make(base: ["LANG": "zh_CN.UTF-8"])["LANG"] == "zh_CN.UTF-8")
    }
}
