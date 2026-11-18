import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Tokens.Size.gutter) {
            Sidebar()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Tokens.canvas)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Size.radius))
                .overlay(RoundedRectangle(cornerRadius: Tokens.Size.radius).strokeBorder(Tokens.line2))
        }
        .padding(Tokens.Size.gutter)
        .background(Tokens.shell)
        .overlay(alignment: .trailing) { drawer }
        .animation(reduceMotion ? nil : Tokens.ease(0.32), value: model.runs.isDrawerPresented)
        .ignoresSafeArea()
    }

    @ViewBuilder private var content: some View {
        switch model.setup {
        case .locating:
            SetupStateView(title: "正在查找 mo…", detail: nil, retry: nil)
        case .failed(let message):
            SetupStateView(title: "找不到可用的 mo", detail: message) {
                Task { await model.bootstrap() }
            }
        case .ready:
            ModuleHost(module: model.selection)
        }
    }

    @ViewBuilder private var drawer: some View {
        if model.runs.isDrawerPresented, let installation = model.installation {
            ExecutionDrawer(runs: model.runs, installation: installation)
                .padding(Tokens.Size.gutter)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}

struct ModuleHost: View {
    let module: Module

    var body: some View {
        Group {
            switch module {
            case .dashboard: DashboardView()
            default: PlaceholderModule(module: module)
            }
        }
        .id(module)
    }
}

struct SetupStateView: View {
    let title: String
    let detail: String?
    let retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            if detail == nil { LiveDot() } else { StatusGlyph(kind: .failure) }
            Text(title).font(.ui(11.5, weight: .semibold)).foregroundStyle(Tokens.ink)
            if let detail {
                Text(detail)
                    .font(.ui(10.5))
                    .foregroundStyle(Tokens.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .textSelection(.enabled)
            }
            if let retry {
                Button("重新查找", action: retry)
                    .buttonStyle(MoleButtonStyle())
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
