import Foundation
import Testing
@testable import MoleKit

/// Hands out one controllable stream per (re)connect and counts terminations.
final class ScriptedSource: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [AsyncThrowingStream<Data, any Error>.Continuation] = []
    private var terminatedCount = 0

    var requests: Int { lock.withLock { continuations.count } }
    var terminations: Int { lock.withLock { terminatedCount } }

    func makeStream() -> AsyncThrowingStream<Data, any Error> {
        let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            self.lock.withLock { self.terminatedCount += 1 }
        }
        lock.withLock { continuations.append(continuation) }
        return stream
    }

    func send(_ line: String) {
        let latest = lock.withLock { continuations.last }
        latest?.yield(Data(line.utf8))
    }

    func finish(throwing error: (any Error)? = nil) {
        let latest = lock.withLock { continuations.last }
        latest?.finish(throwing: error)
    }
}

private func frame(cpu: Double) throws -> String {
    try Fixture.text("status-full.json")
        .replacingOccurrences(of: "\"cpu\":{\"usage\":28.56", with: "\"cpu\":{\"usage\":\(cpu)")
}

@MainActor
@Suite struct StatusServiceTests {
    private func makeService(
        _ source: ScriptedSource,
        interval: Duration = .zero,
        backoff: [Duration] = [.milliseconds(10)]
    ) -> StatusService {
        StatusService(source: { source.makeStream() }, minPublishInterval: interval, backoff: backoff)
    }

    private func isFailed(_ phase: StatusService.Phase) -> Bool {
        if case .failed = phase { true } else { false }
    }

    @Test func publishesFramesAndRecordsHistory() async throws {
        let source = ScriptedSource()
        let service = makeService(source)
        service.start()
        #expect(await waitUntil { source.requests == 1 })
        source.send(try Fixture.text("status-full.json"))
        #expect(await waitUntil { service.snapshot != nil })
        #expect(service.phase == .live)
        #expect(service.cpuHistory.last == 28.56)
        #expect(service.rxHistory.last == 0.0216)
        #expect(service.snapshot?.topProcesses.count == 3)
        service.stop()
    }

    @Test func skipsABadLineAndKeepsStreaming() async throws {
        let source = ScriptedSource()
        let service = makeService(source)
        service.start()
        #expect(await waitUntil { source.requests == 1 })
        source.send("not json")
        source.send(try Fixture.text("status-full.json"))
        #expect(await waitUntil { service.snapshot != nil })
        #expect(service.skippedLines == 1)
        #expect(service.phase == .live)
        service.stop()
    }

    @Test func fiveConsecutiveBadLinesStopWithAFailure() async {
        let source = ScriptedSource()
        let service = makeService(source)
        service.start()
        #expect(await waitUntil { source.requests == 1 })
        for _ in 0..<5 { source.send("garbage") }
        #expect(await waitUntil { isFailed(service.phase) })
        #expect(service.isRunning == false)
        #expect(source.requests == 1) // no reconnect after a parse failure
    }

    @Test func reconnectsWhenTheStreamEnds() async {
        let source = ScriptedSource()
        let service = makeService(source)
        service.start()
        #expect(await waitUntil { source.requests == 1 })
        source.finish(throwing: CommandFailure(command: "mole status", exitCode: 1, stderr: "boom"))
        #expect(await waitUntil { source.requests == 2 })
        service.stop()
    }

    @Test func stopTerminatesTheStreamAndKeepsTheLastFrame() async throws {
        let source = ScriptedSource()
        let service = makeService(source)
        service.start()
        #expect(await waitUntil { source.requests == 1 })
        source.send(try Fixture.text("status-full.json"))
        #expect(await waitUntil { service.snapshot != nil })
        service.stop()
        #expect(service.phase == .idle)
        #expect(service.snapshot != nil)
        #expect(await waitUntil { source.terminations >= 1 })
    }

    @Test func coalescesFramesThatArriveFasterThanTheInterval() async throws {
        let source = ScriptedSource()
        let service = makeService(source, interval: .milliseconds(300))
        service.start()
        #expect(await waitUntil { source.requests == 1 })
        source.send(try frame(cpu: 10))
        #expect(await waitUntil { service.snapshot?.cpu.usage == 10 })
        source.send(try frame(cpu: 50))
        source.send(try frame(cpu: 60))
        try await Task.sleep(for: .milliseconds(60))
        #expect(service.snapshot?.cpu.usage == 10)
        #expect(await waitUntil(timeout: .seconds(1)) { service.snapshot?.cpu.usage == 60 })
        #expect(service.cpuHistory.elements == [10, 60])
        service.stop()
    }

    @Test func fullFrameReplacesTheFastFrameImmediately() async throws {
        let source = ScriptedSource()
        let service = makeService(source, interval: .seconds(10))
        service.start()
        #expect(await waitUntil { source.requests == 1 })
        source.send(try Fixture.text("status-fast.json"))
        #expect(await waitUntil { service.snapshot?.isFastFrame == true })
        source.send(try Fixture.text("status-full.json"))
        #expect(await waitUntil(timeout: .seconds(1)) { service.snapshot?.isFastFrame == false })
        service.stop()
    }
}
