import SwiftUI

/// Stand-in for modules that later milestones wire up.
struct PlaceholderModule: View {
    let module: Module

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: module.title, context: "规划中 · \(module.milestone)") { EmptyView() }
            VStack(spacing: 5) {
                Text("\(module.title) 在 \(module.milestone) 接入")
                    .font(.ui(11.5, weight: .semibold))
                    .foregroundStyle(Tokens.ink)
                Text("⌘K 打开命令面板").font(.mono(10)).foregroundStyle(Tokens.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
