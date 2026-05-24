import AppKit
import CodexUsageCore
import SwiftUI

@main
struct CodexUsageApp: App {
    @State private var model = AppModel()
    @State private var windowController: UsageWindowController?

    var body: some Scene {
        MenuBarExtra(model.strings.codexUsageTitle, systemImage: "bolt.horizontal.circle") {
            Button(model.strings.codexUsageTitle) {
                showWindow()
            }
            Button(model.strings.refresh) {
                model.refresh()
            }
            Divider()
            SettingsLink {
                Text(model.strings.preferences)
            }
            Button(model.strings.quit) {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            PreferencesView(model: model)
        }
    }

    private func showWindow() {
        if windowController == nil {
            windowController = UsageWindowController(model: model)
        }
        windowController?.show()
        model.startTimerIfNeeded()
    }
}
