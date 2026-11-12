import Foundation
import Testing
@testable import MoleKit

private let sh = URL(fileURLWithPath: "/bin/sh")
private let sleepBin = URL(fileURLWithPath: "/bin/sleep")

@Suite struct DataRunnerTests {
    @Test func runReturnsStdout() async throws {
        let output = try await DataRunner().run(URL(fileURLWithPath: "/bin/echo"), ["hello"])
        #expect(String(decoding: output, as: UTF8.self) == "hello\n")
    }

    @Test func runThrowsCommandFailureWithStderr() async {
        do {
            _ = try await DataRunner().run(sh, ["-c", "echo oops >&2; exit 3"])
            Issue.record("expected CommandFailure")
        } catch let failure as CommandFailure {
            #expect(failure.exitCode == 3)
            #expect(failure.stderr == "oops\n")
            #expect(failure.description.contains("oops"))
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func streamYieldsLinesIncludingUnterminatedTail() async throws {
        var lines: [String] = []
        for try await line in DataRunner().stream(sh, ["-c", "printf 'a\\nb\\nc'"]) {
            lines.append(String(decoding: line, as: UTF8.self))
        }
        #expect(lines == ["a", "b", "c"])
    }

    @Test func streamThrowsAfterDeliveringLinesWhenProcessFails() async {
        var lines: [String] = []
        do {
            for try await line in DataRunner().stream(sh, ["-c", "echo one; exit 2"]) {
                lines.append(String(decoding: line, as: UTF8.self))
            }
            Issue.record("expected CommandFailure")
        } catch let failure as CommandFailure {
            #expect(failure.exitCode == 2)
        } catch {
            Issue.record("unexpected error \(error)")
        }
        #expect(lines == ["one"])
    }

    @Test func cancellingRunTerminatesChild() async {
        let runner = DataRunner()
        let task = Task { try await runner.run(sleepBin, ["30"]) }
        #expect(await waitUntil { runner.runningCount == 1 })
        let started = ContinuousClock.now
        task.cancel()
        let result = await task.result
        #expect(ContinuousClock.now - started < .seconds(3))
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(await waitUntil { runner.runningCount == 0 })
    }

    @Test func breakingOutOfStreamTerminatesChild() async throws {
        let runner = DataRunner()
        var count = 0
        for try await _ in runner.stream(sh, ["-c", "while true; do echo tick; sleep 0.05; done"]) {
            count += 1
            if count == 3 { break }
        }
        #expect(count == 3)
        #expect(await waitUntil { runner.runningCount == 0 })
    }

    @Test func escalatesToSigkillWhenTermIsIgnored() async throws {
        let runner = DataRunner(gracePeriod: .milliseconds(200))
        let task = Task { try await runner.run(sh, ["-c", "trap '' TERM; while true; do sleep 0.05; done"]) }
        #expect(await waitUntil { runner.runningCount == 1 })
        try await Task.sleep(for: .milliseconds(300)) // let sh install the trap
        let started = ContinuousClock.now
        task.cancel()
        _ = await task.result
        let elapsed = ContinuousClock.now - started
        #expect(elapsed >= .milliseconds(150)) // SIGTERM was ignored, so we waited for the grace period
        #expect(elapsed < .seconds(3))
        #expect(await waitUntil { runner.runningCount == 0 })
    }

    @Test func terminateAllStopsEveryChild() async {
        let runner = DataRunner()
        let first = Task { try await runner.run(sleepBin, ["30"]) }
        let second = Task { try await runner.run(sleepBin, ["30"]) }
        #expect(await waitUntil { runner.runningCount == 2 })
        runner.terminateAll()
        _ = await first.result
        _ = await second.result
        #expect(runner.runningCount == 0)
    }
}
