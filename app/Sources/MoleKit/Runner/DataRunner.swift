import Foundation

/// A data-channel command exited non-zero.
public struct CommandFailure: Error, Sendable, Equatable, CustomStringConvertible {
    public let command: String
    public let exitCode: Int32
    public let stderr: String

    public var description: String {
        let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty
            ? "\(command) 退出码 \(exitCode)"
            : "\(command) 退出码 \(exitCode)：\(detail)"
    }
}

/// One child process with piped stdout/stderr and no stdin.
/// All mutable state sits behind `lock`; blocking calls never run on the main thread.
final class ChildProcess: @unchecked Sendable {
    let process = Process()
    let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let stderrDone = DispatchGroup()
    private let lock = NSLock()
    private var stderrBuffer = Data()
    private var terminatedByUs = false
    let commandLine: String

    init(executable: URL, arguments: [String], environment: [String: String]?) {
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        commandLine = ([executable.lastPathComponent] + arguments).joined(separator: " ")
    }

    func start() throws {
        try process.run()
        stderrDone.enter()
        let handle = stderrPipe.fileHandleForReading
        DispatchQueue.global(qos: .utility).async { [self] in
            let data = (try? handle.readToEnd()) ?? Data()
            lock.withLock { stderrBuffer = Data(data.prefix(65_536)) }
            stderrDone.leave()
        }
    }

    /// Blocks the calling thread until the process exits and stderr is drained.
    func waitForExit() -> Int32 {
        process.waitUntilExit()
        stderrDone.wait()
        return process.terminationStatus
    }

    var stderrText: String { lock.withLock { String(decoding: stderrBuffer, as: UTF8.self) } }
    var wasTerminatedByUs: Bool { lock.withLock { terminatedByUs } }

    /// SIGTERM now, SIGKILL after `grace` if the process is still alive.
    func terminate(grace: Duration) {
        lock.withLock { terminatedByUs = true }
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        process.terminate()
        let parts = grace.components
        let seconds = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds) { [self] in
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }
}

/// Holds the line splitter for a stream. The readability handler and the
/// end-of-stream drain run on different queues, so the splitter lives here.
final class StreamReadState: @unchecked Sendable {
    private let lock = NSLock()
    private var splitter = LineSplitter()

    func append(_ chunk: Data) -> [Data] { lock.withLock { splitter.append(chunk) } }
    func finish() -> Data? { lock.withLock { splitter.finish() } }
}

/// Children registered synchronously at launch, so `terminateAll` never misses one.
final class ProcessRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var children: [ObjectIdentifier: ChildProcess] = [:]

    func insert(_ child: ChildProcess) { lock.withLock { children[ObjectIdentifier(child)] = child } }
    func remove(_ child: ChildProcess) { lock.withLock { _ = children.removeValue(forKey: ObjectIdentifier(child)) } }
    func all() -> [ChildProcess] { lock.withLock { Array(children.values) } }
    var count: Int { lock.withLock { children.count } }
}

/// Runs read-only `mo` commands without a TTY (design doc 3, data channel).
public final class DataRunner: Sendable {
    public let gracePeriod: Duration
    private let registry = ProcessRegistry()

    public init(gracePeriod: Duration = .milliseconds(500)) {
        self.gracePeriod = gracePeriod
    }

    public var runningCount: Int { registry.count }

    public func run(
        _ executable: URL,
        _ arguments: [String],
        environment: [String: String]? = nil
    ) async throws -> Data {
        let child = ChildProcess(executable: executable, arguments: arguments, environment: environment)
        try child.start()
        registry.insert(child)
        defer { registry.remove(child) }
        let grace = gracePeriod
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, any Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let output = (try? child.stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
                    let status = child.waitForExit()
                    if child.wasTerminatedByUs {
                        continuation.resume(throwing: CancellationError())
                    } else if status != 0 {
                        continuation.resume(throwing: CommandFailure(
                            command: child.commandLine, exitCode: status, stderr: child.stderrText))
                    } else {
                        continuation.resume(returning: output)
                    }
                }
            }
        } onCancel: {
            child.terminate(grace: grace)
        }
    }

    public func stream(
        _ executable: URL,
        _ arguments: [String],
        environment: [String: String]? = nil
    ) -> AsyncThrowingStream<Data, any Error> {
        let registry = self.registry
        let grace = gracePeriod
        return AsyncThrowingStream { continuation in
            let child = ChildProcess(executable: executable, arguments: arguments, environment: environment)
            do {
                try child.start()
            } catch {
                continuation.finish(throwing: error)
                return
            }
            registry.insert(child)
            // Read through readabilityHandler instead of a blocking read: breaking
            // out of the stream only cancels the continuation, and a thread blocked
            // in read() would never notice, so the child would run forever.
            continuation.onTermination = { @Sendable termination in
                if case .cancelled = termination { child.terminate(grace: grace) }
            }
            let handle = child.stdoutPipe.fileHandleForReading
            let state = StreamReadState()
            handle.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    DispatchQueue.global(qos: .utility).async {
                        let tail = state.finish()
                        if let tail { continuation.yield(tail) }
                        let status = child.waitForExit()
                        registry.remove(child)
                        if status == 0 || child.wasTerminatedByUs {
                            continuation.finish()
                        } else {
                            continuation.finish(throwing: CommandFailure(
                                command: child.commandLine, exitCode: status, stderr: child.stderrText))
                        }
                    }
                    return
                }
                for line in state.append(chunk) { continuation.yield(line) }
            }
        }
    }

    /// Called on app termination and when the user stops everything.
    public func terminateAll() {
        for child in registry.all() { child.terminate(grace: gracePeriod) }
    }
}
