import Foundation
import MoleKit
import Observation

@MainActor
@Observable
final class AppModel {
    enum Setup: Equatable {
        case locating
        case ready(MoleInstallation)
        case failed(String)
    }

    var selection: Module = .dashboard
    private(set) var setup: Setup = .locating
    private(set) var status: StatusService?
    private(set) var environment: [String: String] = [:]
    let runner = DataRunner()
    let runs = CommandRunCoordinator()

    var installation: MoleInstallation? {
        if case .ready(let installation) = setup { installation } else { nil }
    }

    /// Finds and verifies mo. Safe to call again after the user edits Settings.
    func bootstrap() async {
        status?.stop()
        status = nil
        setup = .locating
        let env = MoleEnvironment.make(base: ProcessInfo.processInfo.environment)
        environment = env
        do {
            let locator = MoleLocator.fromApp(searchPath: env["PATH"] ?? "")
            let found = try await locator.locate(using: runner, environment: env)
            status = StatusService.live(runner: runner, executable: found.executableURL, environment: env)
            setup = .ready(found)
        } catch {
            setup = .failed(String(describing: error))
        }
    }

    /// Starts a command in the execution drawer. Returns false when mo is not ready,
    /// the spec is refused (for example `--permanent`), or another command is still running.
    @discardableResult
    func run(_ arguments: [String], title: String, mutatesSystem: Bool) -> Bool {
        guard installation != nil,
              let spec = CommandSpec(arguments: arguments, title: title, mutatesSystem: mutatesSystem)
        else { return false }
        guard runs.begin(spec) else {
            runs.presentDrawer()
            return false
        }
        return true
    }

    func shutdown() {
        status?.stop()
        runner.terminateAll()
    }
}
