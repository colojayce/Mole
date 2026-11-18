import SwiftUI

/// Stand-in for modules that later milestones wire up. Modules with a dry-run
/// preview can already run it in the execution drawer.
struct PlaceholderModule: View {
    @Environment(AppModel.self) private var model
    let module: Module

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: module.title, context: "规划中 · \(module.milestone)") {
                if let arguments = module.previewArguments {
                    Button {
                        model.run(arguments, title: "\(module.title) 预览", mutatesSystem: false)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "eye").font(.system(size: 11))
                            Text("预览")
                        }
                    }
                    .buttonStyle(MoleButtonStyle())
                    .disabled(model.runs.isRunning)
                    .help("mo " + arguments.joined(separator: " "))
                }
            }
            VStack(spacing: 5) {
                Text("\(module.title) 在 \(module.milestone) 接入")
                    .font(.ui(11.5, weight: .semibold))
                    .foregroundStyle(Tokens.ink)
                if let arguments = module.previewArguments {
                    Text("预览会在右侧抽屉里运行 mo \(arguments.joined(separator: " "))")
                        .font(.mono(10))
                        .foregroundStyle(Tokens.muted)
                } else {
                    Text("⌘K 打开命令面板").font(.mono(10)).foregroundStyle(Tokens.muted)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
