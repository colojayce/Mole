import Foundation
import Testing
@testable import MoleKit

@Suite struct CommandSpecTests {
    @Test func refusesPermanentAndEmptyArguments() {
        #expect(CommandSpec(arguments: ["uninstall", "--permanent", "Slack"], title: "x", mutatesSystem: true) == nil)
        #expect(CommandSpec(arguments: [], title: "x", mutatesSystem: false) == nil)
        #expect(CommandSpec(arguments: ["clean", "--dry-run"], title: "x", mutatesSystem: false) != nil)
    }

    @Test func quotesArgumentsForDisplay() throws {
        let spec = try #require(CommandSpec(
            arguments: ["uninstall", "--dry-run", "腾讯会议", "Bob's App"],
            title: "预览卸载",
            mutatesSystem: false
        ))
        #expect(spec.commandText == "mo uninstall --dry-run '腾讯会议' 'Bob'\\''s App'")
        #expect(spec.displayLine == "$ " + spec.commandText)
        #expect(ShellQuote.quote("") == "''")
        #expect(ShellQuote.quote("--interval=1s") == "--interval=1s")
    }
}

@MainActor
@Suite struct CommandRunCoordinatorTests {
    private func spec(_ arguments: [String], mutates: Bool = false) -> CommandSpec {
        CommandSpec(arguments: arguments, title: arguments.joined(separator: " "), mutatesSystem: mutates)!
    }

    @Test func runsOneCommandAtATime() {
        let runs = CommandRunCoordinator()
        let first = spec(["clean", "--dry-run"])
        let start = Date(timeIntervalSince1970: 100)
        #expect(runs.begin(first, now: start))
        #expect(runs.isRunning)
        #expect(runs.isDrawerPresented)
        #expect(runs.current == first)
        #expect(runs.glyph == .pending)

        #expect(runs.begin(spec(["optimize", "--dry-run"])) == false)
        #expect(runs.current == first)

        runs.finish(first.id, exitCode: 0, now: start.addingTimeInterval(12))
        #expect(runs.state == .finished(first, exitCode: 0, duration: 12))
        #expect(runs.completedRuns == 1)
        #expect(runs.glyph == .done)
        #expect(runs.begin(spec(["optimize", "--dry-run"])))
    }



    @Test func drawerCannotCloseWhileRunning() {
        let runs = CommandRunCoordinator()
        let command = spec(["clean", "--dry-run"])
        runs.begin(command)
        #expect(runs.dismissDrawer() == false)
        #expect(runs.isDrawerPresented)
        runs.finish(command.id, exitCode: 1)
        #expect(runs.dismissDrawer())
        #expect(runs.isDrawerPresented == false)
        runs.presentDrawer()
        #expect(runs.isDrawerPresented)
    }

    @Test func recentKeepsFiveReadOnlyCommandsNewestFirst() {
        let runs = CommandRunCoordinator()
        func run(_ command: CommandSpec) {
            runs.begin(command)
            runs.finish(command.id, exitCode: 0)
        }
        run(spec(["clean"], mutates: true))
        for name in ["a", "b", "c", "d", "e", "f"] { run(spec([name, "--dry-run"])) }
        run(spec(["c", "--dry-run"]))
        #expect(runs.recent.map(\.arguments.first) == ["c", "f", "e", "d", "b"])
    }
}
