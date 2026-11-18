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

    func shutdown() {
        status?.stop()
        runner.terminateAll()
    }
}
