import AppKit
import CodexUsageCore
import SwiftUI

@main
struct CodexUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra(appDelegate.model.strings.codexUsageTitle, systemImage: "bolt.horizontal.circle") {
            Button(appDelegate.model.strings.codexUsageTitle) {
                appDelegate.showWindow()
            }
            Button(appDelegate.model.strings.refresh) {
                appDelegate.model.refresh()
            }
            Toggle(appDelegate.model.strings.alwaysOnTop, isOn: Binding(
                get: { appDelegate.model.isAlwaysOnTop },
                set: { appDelegate.model.isAlwaysOnTop = $0 }
            ))
            Divider()
            SettingsLink {
                Text(appDelegate.model.strings.preferences)
            }
            Button(appDelegate.model.strings.quit) {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            PreferencesView(model: appDelegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var windowController: UsageWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        showWindow()
    }

    func showWindow() {
        if windowController == nil {
            windowController = UsageWindowController(model: model)
        }
        windowController?.show()
        model.startTimerIfNeeded()
    }
}
