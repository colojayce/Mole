import SwiftUI

struct MoleCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("前往") {
            ForEach(Module.allCases) { module in
                Button(module.title) { model.selection = module }
                    .keyboardShortcut(KeyEquivalent(module.shortcutDigit), modifiers: .command)
            }
            Divider()
            Button("命令面板") { model.isPaletteOpen.toggle() }
                .keyboardShortcut("k", modifiers: .command)
        }
    }
}
