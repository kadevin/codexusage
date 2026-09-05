import AppKit
@testable import CodexUsageApp
import CodexUsageCore
import SwiftUI
import XCTest

@MainActor
final class UsageWindowControllerTests: XCTestCase {
    func testPinnedPanelCanJoinFullscreenSpaces() {
        let behavior = UsageWindowController.collectionBehavior(alwaysOnTop: true)

        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
    }

    func testUnpinnedPanelDoesNotJoinFullscreenSpaces() {
        let behavior = UsageWindowController.collectionBehavior(alwaysOnTop: false)

        XCTAssertFalse(behavior.contains(.canJoinAllSpaces))
        XCTAssertFalse(behavior.contains(.fullScreenAuxiliary))
    }

    func testWindowDragHandleAllowsWindowMovement() {
        let dragHandle = WindowDragHandleNSView(frame: .zero)

        XCTAssertTrue(dragHandle.mouseDownCanMoveWindow)
    }

    func testWindowDragHandleAcceptsFirstClickWhilePanelIsInactive() {
        let dragHandle = WindowDragHandleNSView(frame: .zero)

        XCTAssertTrue(dragHandle.acceptsFirstMouse(for: nil))
    }

    func testChartInteractionSurfaceSelectsNearestHourAcrossEntireWidth() {
        XCTAssertEqual(
            ChartHoverDragSurfaceNSView.nearestIndex(x: 0, width: 100, pointCount: 5),
            0
        )
        XCTAssertEqual(
            ChartHoverDragSurfaceNSView.nearestIndex(x: 50, width: 100, pointCount: 5),
            2
        )
        XCTAssertEqual(
            ChartHoverDragSurfaceNSView.nearestIndex(x: 100, width: 100, pointCount: 5),
            4
        )
        XCTAssertEqual(
            ChartHoverDragSurfaceNSView.nearestIndex(x: 130, width: 100, pointCount: 5),
            4
        )
        XCTAssertNil(
            ChartHoverDragSurfaceNSView.nearestIndex(x: 20, width: 0, pointCount: 5)
        )
        XCTAssertNil(
            ChartHoverDragSurfaceNSView.nearestIndex(x: 20, width: 100, pointCount: 0)
        )
    }

    func testChartInteractionSurfaceAllowsWindowMovement() {
        let surface = ChartHoverDragSurfaceNSView(frame: .zero)

        XCTAssertTrue(surface.mouseDownCanMoveWindow)
    }

    func testQuotaProgressBarsDoNotUseInactiveNativeProgressIndicators() {
        let model = AppModel(strings: AppStrings(preferredLanguages: ["en"]), startsImmediately: false)
        model.officialUsage = OfficialUsageSnapshot(
            fetchedAt: Date(),
            limits: [
                OfficialUsageLimit(
                    id: "codex",
                    name: "Codex",
                    planType: "pro",
                    windows: [OfficialUsageWindow(usedPercent: 40, durationMinutes: 300, resetsAt: nil)],
                    hasCredits: false,
                    creditsUnlimited: false,
                    creditBalance: nil
                )
            ],
            resetCreditsAvailable: 0
        )
        let hostingView = NSHostingView(rootView: UsageView(model: model))
        hostingView.frame = NSRect(x: 0, y: 0, width: 360, height: 900)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertFalse(hostingView.containsSubview(ofType: NSProgressIndicator.self))
    }
}

private extension NSView {
    func containsSubview<T: NSView>(ofType type: T.Type) -> Bool {
        self is T || subviews.contains { $0.containsSubview(ofType: type) }
    }
}
