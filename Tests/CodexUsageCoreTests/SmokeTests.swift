import CodexUsageCore
import XCTest

final class SmokeTests: XCTestCase {
    func testTokenTotalsZero() {
        XCTAssertEqual(TokenTotals.zero.totalTokens, 0)
        XCTAssertEqual(SpeedMode.allCases, [.auto, .standard, .fast])
    }
}
