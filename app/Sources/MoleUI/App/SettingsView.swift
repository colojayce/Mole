import MoleKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(MoleLocator.explicitPathDefaultsKey) private var molePath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "mole 路径")
            TextField("", text: $molePath, prompt: Text("留空则自动查找"))
                .textFieldStyle(.roundedBorder)
                .font(.mono(11))
            Text("留空时依次查找：打包时写入的仓库路径、PATH 里的 mo 和 mole。")
                .font(.ui(10))
                .foregroundStyle(Tokens.muted)
            HStack {
                Text(model.installation.map { "当前：\($0.executableURL.path) · \($0.version)" } ?? "当前：未找到")
                    .font(.mono(10))
                    .foregroundStyle(Tokens.ink2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("重新查找") { Task { await model.bootstrap() } }
                    .buttonStyle(MoleButtonStyle())
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(Tokens.paper)
        .preferredColorScheme(.light)
    }
}
