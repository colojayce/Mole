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
    var isPaletteOpen = false
    private(set) var toast: String?
    private(set) var setup: Setup = .locating
    private(set) var status: StatusService?
    private(set) var environment: [String: String] = [:]
    let runner = DataRunner()
    let runs = CommandRunCoordinator()
    @ObservationIgnored let terminal = TerminalSession()
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    init() {
        terminal.onExit = { [weak self] id, exitCode in
            self?.runs.finish(id, exitCode: exitCode)
        }
    }

    var installation: MoleInstallation? {
        if case .ready(let installation) = setup { installation } else { nil }
    }

    /// Finds and verifies mo. Safe to call again after the user edits Settings.
    func bootstrap() async {
        // Re-locating swaps the executable and environment under a live PTY.
        guard !runs.isRunning else {
            showToast("命令运行中，结束后再重新查找 mo")
            runs.presentDrawer()
            return
        }
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
            showToast("已有命令在运行：\(runs.current?.commandText ?? "")")
            runs.presentDrawer()
            return false
        }
        return true
    }

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: - Command palette

    var paletteEntries: [PaletteEntry] {
        var entries = Module.allCases.map { module in
            PaletteEntry(
                id: "go.\(module.rawValue)",
                group: "前往",
                title: module.title,
                meta: "⌘\(module.shortcutDigit)",
                keywords: [module.group.rawValue]
            )
        }
        entries += Module.allCases.compactMap { module in
            module.previewArguments.map { arguments in
                PaletteEntry(
                    id: "run.\(module.rawValue)",
                    group: "操作",
                    title: "\(module.title) 预览",
                    meta: "mo " + arguments.joined(separator: " "),
                    keywords: ["preview", "dry-run"]
                )
            }
        }
        entries += runs.recent.map { spec in
            PaletteEntry(id: "recent.\(spec.id.uuidString)", group: "最近", title: spec.title, meta: spec.commandText)
        }
        return entries
    }

    func performPaletteEntry(_ id: String) {
        if id.hasPrefix("go."), let module = Module(rawValue: String(id.dropFirst(3))) {
            selection = module
        } else if id.hasPrefix("run."),
                  let module = Module(rawValue: String(id.dropFirst(4))),
                  let arguments = module.previewArguments {
            run(arguments, title: "\(module.title) 预览", mutatesSystem: false)
        } else if id.hasPrefix("recent."),
                  let spec = runs.recent.first(where: { "recent.\($0.id.uuidString)" == id }) {
            run(spec.arguments, title: spec.title, mutatesSystem: spec.mutatesSystem)
        }
    }

    func shutdown() {
        status?.stop()
        terminal.terminate()
        runner.terminateAll()
    }
}
