import AppKit
import SwiftUI

@MainActor
final class UsageWindowController {
    private let window: NSPanel

    init(model: AppModel) {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 560),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        [.closeButton, .miniaturizeButton, .zoomButton].forEach {
            window.standardWindowButton($0)?.isHidden = true
        }
        window.minSize = NSSize(width: 360, height: 420)
        window.isReleasedWhenClosed = false
        window.isFloatingPanel = model.isAlwaysOnTop
        window.hidesOnDeactivate = false
        window.level = model.isAlwaysOnTop ? .floating : .normal
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentViewController = NSHostingController(rootView: UsageView(model: model))
        window.center()

        self.window = window
        model.onAlwaysOnTopChanged = { [weak self] enabled in
            self?.setAlwaysOnTop(enabled)
        }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if window.frame.width < window.minSize.width || window.frame.height < window.minSize.height {
            window.setFrame(NSRect(x: 0, y: 0, width: 380, height: 560), display: false)
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func setAlwaysOnTop(_ enabled: Bool) {
        window.isFloatingPanel = enabled
        window.level = enabled ? .floating : .normal
    }
}
