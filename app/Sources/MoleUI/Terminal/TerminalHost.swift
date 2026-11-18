import AppKit
import MoleKit
import SwiftTerm
import SwiftUI

/// Runs one `mo` command in a real PTY. sudo prompts, y/N confirmations and
/// Space-to-skip all behave exactly as in Terminal.app.
struct TerminalHost: NSViewRepresentable {
    let spec: CommandSpec
    let executable: URL
    let environment: [String: String]
    let onExit: @MainActor (Int32?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onExit: onExit)
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        TerminalTheme.apply(to: view)
        view.processDelegate = context.coordinator
        return view
    }

    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {
        context.coordinator.onExit = onExit
        guard context.coordinator.startedID != spec.id else { return }
        context.coordinator.startedID = spec.id
        var env = environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        view.startProcess(
            executable: executable.path,
            args: spec.arguments,
            environment: env.map { "\($0.key)=\($0.value)" },
            execName: nil,
            currentDirectory: FileManager.default.homeDirectoryForCurrentUser.path
        )
        Task { @MainActor in view.window?.makeFirstResponder(view) }
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency LocalProcessTerminalViewDelegate {
        var onExit: @MainActor (Int32?) -> Void
        var startedID: UUID?

        init(onExit: @escaping @MainActor (Int32?) -> Void) {
            self.onExit = onExit
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            onExit(exitCode)
        }

        func processFailedToStart(source: TerminalView, error: LocalProcessError) {
            onExit(nil)
        }
    }
}
