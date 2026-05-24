import AppKit
import SwiftUI

@MainActor
final class UsageWindowController {
    private let panel: NSPanel
    private static let frameAutosaveName = "CodexUsageUsagePanelFrame"

    init(model: AppModel) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = model.strings.codexUsageTitle
        panel.isFloatingPanel = model.isAlwaysOnTop
        panel.level = model.isAlwaysOnTop ? .floating : .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(rootView: UsageView(model: model))
        if !panel.setFrameUsingName(Self.frameAutosaveName) {
            panel.center()
        }
        panel.setFrameAutosaveName(Self.frameAutosaveName)

        self.panel = panel
        model.onAlwaysOnTopChanged = { [weak self] enabled in
            self?.setAlwaysOnTop(enabled)
        }
    }

    func show() {
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setAlwaysOnTop(_ enabled: Bool) {
        panel.isFloatingPanel = enabled
        panel.level = enabled ? .floating : .normal
    }
}
