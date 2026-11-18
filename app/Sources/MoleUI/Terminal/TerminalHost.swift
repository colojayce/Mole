import AppKit
import MoleKit
import SwiftTerm
import SwiftUI

/// Owns the PTY view of the most recent command, outside the SwiftUI drawer.
///
/// The drawer view is torn down whenever it closes. If the terminal lived in
/// it, reopening the drawer would build a fresh view and start the command a
/// second time, and a run whose drawer disappeared would never report its exit
/// code. Keeping one view per command here means it starts exactly once,
/// reopening shows its output, and the exit code always reaches the coordinator.
@MainActor
final class TerminalSession: NSObject, @preconcurrency LocalProcessTerminalViewDelegate {
    /// Called with the command id and exit code (nil when it failed to start or was signalled).
    var onExit: (@MainActor (UUID, Int32?) -> Void)?
    private var view: FocusingTerminalView?
    private var specID: UUID?

    /// The terminal for `spec`, created and started the first time it is asked for.
    func view(for spec: CommandSpec, executable: URL, environment: [String: String]) -> NSView {
        if let view, specID == spec.id {
            view.removeFromSuperview()
            return view
        }
        let view = FocusingTerminalView(frame: .zero)
        TerminalTheme.apply(to: view)
        view.processDelegate = self
        self.view = view
        specID = spec.id
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
        return view
    }

    /// Returns keyboard focus to the terminal, e.g. after the palette closes over a sudo prompt.
    func focus() {
        guard let view, let window = view.window else { return }
        window.makeFirstResponder(view)
    }

    /// SIGTERM to the running command; used when the app quits.
    func terminate() {
        view?.terminate()
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        report(source, exitCode)
    }

    func processFailedToStart(source: TerminalView, error: LocalProcessError) {
        report(source, nil)
    }

    private func report(_ source: TerminalView, _ exitCode: Int32?) {
        guard source === view, let specID else { return }
        onExit?(specID, exitCode)
    }
}

/// Takes keyboard focus whenever it enters a window, so sudo prompts and y/N
/// confirmations receive typing without an extra click.
final class FocusingTerminalView: LocalProcessTerminalView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
}

/// Runs one `mo` command in a real PTY. sudo prompts, y/N confirmations and
/// Space-to-skip all behave exactly as in Terminal.app.
struct TerminalHost: NSViewRepresentable {
    let spec: CommandSpec
    let executable: URL
    let environment: [String: String]
    let session: TerminalSession

    func makeNSView(context: Context) -> NSView {
        session.view(for: spec, executable: executable, environment: environment)
    }

    func updateNSView(_ view: NSView, context: Context) {}
}
