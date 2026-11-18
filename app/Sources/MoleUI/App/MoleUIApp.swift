import AppKit
import SwiftUI

@main
struct MoleUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ViewState private var model = AppModel()

    var body: some Scene {
        Window("Mole", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 1080, minHeight: 680)
                .preferredColorScheme(.light)
                .task {
                    appDelegate.model = model
                    await model.bootstrap()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .commands { MoleCommands(model: model) }

        Settings {
            SettingsView().environment(model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

    func applicationWillTerminate(_ notification: Notification) {
        // SIGTERM every child; mo status also exits on its own once its stdout closes.
        model?.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
