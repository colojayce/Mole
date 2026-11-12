import Foundation
import Observation

/// Decoded output of one `mo status --watch` line.
enum StatusFrameEvent: Sendable {
    case frame(StatusSnapshot)
    case badLine
}

/// Owns the `mo status --watch` stream for the Dashboard (design doc 4.1, 7, 8).
/// Decoding runs off the main actor; the main actor sees at most one published
/// snapshot per `minPublishInterval`.
@MainActor
@Observable
public final class StatusService {
    public enum Phase: Equatable, Sendable {
        case idle
        case connecting
        case live
        case reconnecting(String)
        case failed(String)
    }

    public typealias LineSource = @Sendable () -> AsyncThrowingStream<Data, any Error>

    public nonisolated static let historyCapacity = 120
    public nonisolated static let maxConsecutiveBadLines = 5

    public private(set) var phase: Phase = .idle
    public private(set) var snapshot: StatusSnapshot?
    public private(set) var cpuHistory = RingBuffer<Double>(capacity: 120)
    public private(set) var rxHistory = RingBuffer<Double>(capacity: 120)
    public private(set) var txHistory = RingBuffer<Double>(capacity: 120)
    public private(set) var diskReadHistory = RingBuffer<Double>(capacity: 120)
    public private(set) var diskWriteHistory = RingBuffer<Double>(capacity: 120)
    public private(set) var skippedLines = 0

    private let source: LineSource
    private let minPublishInterval: Duration
    private let backoff: [Duration]
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var pending: StatusSnapshot?
    @ObservationIgnored private var lastPublish: ContinuousClock.Instant?

    public init(
        source: @escaping LineSource,
        minPublishInterval: Duration = .seconds(1),
        backoff: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(30)]
    ) {
        self.source = source
        self.minPublishInterval = minPublishInterval
        self.backoff = backoff
    }

    public static func live(runner: DataRunner, executable: URL, environment: [String: String]) -> StatusService {
        StatusService(source: {
            runner.stream(executable, ["status", "--watch", "--interval", "1s"], environment: environment)
        })
    }

    public var isRunning: Bool { loopTask != nil }

    public func start() {
        guard loopTask == nil else { return }
        phase = .connecting
        loopTask = Task { [weak self] in await self?.runLoop() }
    }

    public func stop() {
        loopTask?.cancel()
        loopTask = nil
        flushTask?.cancel()
        flushTask = nil
        pending = nil
        phase = .idle
    }

    // MARK: - Loop

    private enum Outcome {
        case ended(String)
        case tooManyBadLines
    }

    private func runLoop() async {
        var attempt = 0
        while !Task.isCancelled {
            let (outcome, receivedFrame) = await consume(Self.decodedEvents(source()))
            if Task.isCancelled { return }
            if receivedFrame { attempt = 0 }
            switch outcome {
            case .tooManyBadLines:
                phase = .failed("mo status 连续 \(Self.maxConsecutiveBadLines) 行无法解析。在终端运行 mo status --watch 查看原始输出。")
                loopTask = nil
                return
            case .ended(let reason):
                phase = .reconnecting(reason)
                let delay = backoff.isEmpty ? Duration.seconds(1) : backoff[min(attempt, backoff.count - 1)]
                attempt += 1
                try? await Task.sleep(for: delay)
            }
        }
    }

    private func consume(_ events: AsyncThrowingStream<StatusFrameEvent, any Error>) async -> (Outcome, Bool) {
        var badRun = 0
        var receivedFrame = false
        do {
            for try await event in events {
                switch event {
                case .badLine:
                    skippedLines += 1
                    badRun += 1
                    if badRun >= Self.maxConsecutiveBadLines { return (.tooManyBadLines, receivedFrame) }
                case .frame(let snapshot):
                    badRun = 0
                    receivedFrame = true
                    offer(snapshot)
                }
            }
            return (.ended("mo status 已退出"), receivedFrame)
        } catch {
            return (.ended(String(describing: error)), receivedFrame)
        }
    }

    /// Decodes lines on a detached task. Cancelling the returned stream cancels
    /// the task, which cancels `lines` and so terminates the child process.
    nonisolated static func decodedEvents(
        _ lines: AsyncThrowingStream<Data, any Error>
    ) -> AsyncThrowingStream<StatusFrameEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .utility) {
                do {
                    for try await line in lines {
                        if let snapshot = try? StatusSnapshot.decode(line) {
                            continuation.yield(.frame(snapshot))
                        } else {
                            continuation.yield(.badLine)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Publishing

    private func offer(_ snapshot: StatusSnapshot) {
        let now = ContinuousClock.now
        let showingFastFrame = self.snapshot?.isFastFrame ?? false
        if let last = lastPublish, now - last < minPublishInterval, !showingFastFrame {
            pending = snapshot
            guard flushTask == nil else { return }
            let wait = minPublishInterval - (now - last)
            flushTask = Task { [weak self] in
                try? await Task.sleep(for: wait)
                guard let self, !Task.isCancelled else { return }
                self.flushTask = nil
                if let next = self.pending {
                    self.pending = nil
                    self.publish(next)
                }
            }
        } else {
            publish(snapshot)
        }
    }

    private func publish(_ snapshot: StatusSnapshot) {
        lastPublish = .now
        self.snapshot = snapshot
        phase = .live
        cpuHistory.append(snapshot.cpu.usage)
        rxHistory.append(snapshot.network.reduce(0) { $0 + $1.rxRateMbs })
        txHistory.append(snapshot.network.reduce(0) { $0 + $1.txRateMbs })
        diskReadHistory.append(snapshot.diskIo.readRate)
        diskWriteHistory.append(snapshot.diskIo.writeRate)
    }
}
