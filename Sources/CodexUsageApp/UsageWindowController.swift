import AppKit
import SwiftUI

@MainActor
final class UsageWindowController {
    private let window: NSPanel
    private var lastFittedContentHeight: CGFloat = 0

    private static let contentWidth: CGFloat = 360
    private static let defaultContentHeight: CGFloat = 540
    private static let minContentHeight: CGFloat = 420
    private static let contentHeightReserve: CGFloat = 28
    private static let screenVerticalMargin: CGFloat = 72

    init(model: AppModel) {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: Self.defaultContentHeight),
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
        window.minSize = NSSize(width: Self.contentWidth, height: Self.minContentHeight)
        window.isReleasedWhenClosed = false
        window.isFloatingPanel = model.isAlwaysOnTop
        window.hidesOnDeactivate = false
        window.level = model.isAlwaysOnTop ? .floating : .normal
        window.collectionBehavior = Self.collectionBehavior(alwaysOnTop: model.isAlwaysOnTop)

        self.window = window

        window.contentViewController = NSHostingController(
            rootView: UsageView(
                model: model,
                onContentHeightChanged: { [weak self] height in
                    self?.fitWindow(toContentHeight: height)
                }
            )
        )
        window.center()

        model.onAlwaysOnTopChanged = { [weak self] enabled in
            self?.setAlwaysOnTop(enabled)
        }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if window.frame.width < window.minSize.width || window.frame.height < window.minSize.height {
            window.setFrame(
                NSRect(x: 0, y: 0, width: Self.contentWidth, height: Self.defaultContentHeight),
                display: false
            )
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func setAlwaysOnTop(_ enabled: Bool) {
        window.isFloatingPanel = enabled
        window.level = enabled ? .floating : .normal
        window.collectionBehavior = Self.collectionBehavior(alwaysOnTop: enabled)
    }

    static func collectionBehavior(alwaysOnTop: Bool) -> NSWindow.CollectionBehavior {
        alwaysOnTop ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.managed]
    }

    private func fitWindow(toContentHeight contentHeight: CGFloat) {
        guard contentHeight.isFinite, contentHeight > 0 else {
            return
        }

        let targetContentHeight = min(
            max(ceil(contentHeight + Self.contentHeightReserve), Self.minContentHeight),
            maxAvailableContentHeight()
        )
        guard abs(targetContentHeight - lastFittedContentHeight) >= 2 else {
            return
        }
        lastFittedContentHeight = targetContentHeight

        let targetFrameSize = window.frameRect(
            forContentRect: NSRect(
                x: 0,
                y: 0,
                width: Self.contentWidth,
                height: targetContentHeight
            )
        ).size
        let currentFrame = window.frame
        var targetOrigin = NSPoint(
            x: currentFrame.minX,
            y: currentFrame.maxY - targetFrameSize.height
        )

        if let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            targetOrigin.x = clamp(
                targetOrigin.x,
                lower: visibleFrame.minX + 24,
                upper: visibleFrame.maxX - targetFrameSize.width - 24
            )
            targetOrigin.y = clamp(
                targetOrigin.y,
                lower: visibleFrame.minY + 24,
                upper: visibleFrame.maxY - targetFrameSize.height - 24
            )
        }

        window.setFrame(
            NSRect(origin: targetOrigin, size: targetFrameSize),
            display: true,
            animate: false
        )
    }

    private func maxAvailableContentHeight() -> CGFloat {
        guard let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else {
            return Self.defaultContentHeight
        }

        return max(Self.minContentHeight, visibleFrame.height - Self.screenVerticalMargin)
    }

    private func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard lower <= upper else {
            return lower
        }

        return min(max(value, lower), upper)
    }
}
