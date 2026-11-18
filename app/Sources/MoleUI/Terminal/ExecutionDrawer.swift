import AppKit
import MoleKit
import SwiftUI

struct ExecutionDrawer: View {
    @Environment(AppModel.self) private var model
    let runs: CommandRunCoordinator
    let installation: MoleInstallation
    @ViewState private var copied = false

    var body: some View {
        if let spec = runs.current {
            VStack(spacing: 0) {
                header(spec)
                TerminalHost(
                    spec: spec,
                    executable: installation.executableURL,
                    environment: model.environment
                ) { exitCode in
                    runs.finish(spec.id, exitCode: exitCode)
                }
                .id(spec.id)
                .padding(10)
                .background(Tokens.ink)
            }
            .frame(width: Tokens.Size.drawerWidth)
            .frame(maxHeight: .infinity)
            .background(Tokens.paper)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Size.radius))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Size.radius).strokeBorder(Tokens.line2))
            .shadow(color: Tokens.ink.opacity(0.08), radius: 2, y: 2)
            .shadow(color: Tokens.ink.opacity(0.3), radius: 45, y: 30)
        }
    }

    private func header(_ spec: CommandSpec) -> some View {
        HStack(spacing: 8) {
            Text(spec.displayLine)
                .font(.mono(11, weight: .medium))
                .foregroundStyle(Tokens.ink2)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(spec.commandText, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Tokens.muted)
            .help("复制命令")
            Spacer(minLength: 8)
            RunStatusChip(state: runs.state)
            Button {
                runs.dismissDrawer()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(runs.isRunning ? Tokens.line2 : Tokens.ink2)
            .disabled(runs.isRunning)
            .keyboardShortcut(.cancelAction)
            .help(runs.isRunning ? "命令运行中，结束后才能关闭" : "关闭（Esc）")
        }
        .padding(.leading, 17)
        .padding(.trailing, 12)
        .frame(height: 52)
        .overlay(alignment: .bottom) { Rectangle().fill(Tokens.line).frame(height: 1) }
    }
}

struct RunStatusChip: View {
    let state: CommandRunCoordinator.State

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .running(_, let startedAt):
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                chip(.pending, "运行中 · \(Format.elapsed(Int(context.date.timeIntervalSince(startedAt))))", signal: false)
            }
        case .finished(_, let exitCode, let duration):
            chip(
                Signals.exit(exitCode),
                "\(exitCode.map { "退出 \($0)" } ?? "已中断") · \(Format.elapsed(Int(duration)))",
                signal: exitCode != 0
            )
        }
    }

    private func chip(_ glyph: StatusGlyphKind, _ text: String, signal: Bool) -> some View {
        HStack(spacing: 5) {
            StatusGlyph(kind: glyph)
            Text(text).font(.mono(10, weight: .semibold))
        }
        .foregroundStyle(signal ? Tokens.signalInk : Tokens.ink2)
        .padding(.horizontal, 7)
        .frame(height: 21)
        .background(RoundedRectangle(cornerRadius: 2).fill(signal ? Tokens.signalWash : Tokens.canvas))
        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(signal ? Tokens.signalLine : Tokens.line))
    }
}
