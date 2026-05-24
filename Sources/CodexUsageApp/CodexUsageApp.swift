import CodexUsageCore
import SwiftUI

@main
struct CodexUsageApp: App {
    var body: some Scene {
        MenuBarExtra("Codex Usage", systemImage: "bolt.horizontal.circle") {
            Text("Codex Usage")
        }
        .menuBarExtraStyle(.menu)
    }
}
