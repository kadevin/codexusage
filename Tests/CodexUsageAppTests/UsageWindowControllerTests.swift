import AppKit
@testable import CodexUsageApp
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
}
