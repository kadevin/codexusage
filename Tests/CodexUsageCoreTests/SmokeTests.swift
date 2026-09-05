import CodexUsageCore
import XCTest

final class SmokeTests: XCTestCase {
    func testTokenTotalsZero() {
        XCTAssertEqual(TokenTotals.zero.totalTokens, 0)
        XCTAssertEqual(SpeedMode.allCases, [.auto, .standard, .fast])
    }

    func testPublicSummaryInitializers() {
        let totals = TokenTotals(
            inputTokens: 100,
            cachedInputTokens: 25,
            outputTokens: 40,
            reasoningTokens: 10,
            totalTokens: 140
        )
        let cost = CostEstimate(
            credits: Decimal(string: "0.12"),
            hasUnknownPricing: false
        )
        let summary = UsageSummary(totals: totals, cost: cost)

        XCTAssertEqual(summary.totals.inputTokens, 100)
        XCTAssertEqual(summary.totals.cachedInputTokens, 25)
        XCTAssertEqual(summary.cost.credits, Decimal(string: "0.12"))
        XCTAssertFalse(summary.cost.hasUnknownPricing)
    }

    func testCodexUsageEventKeepsCachedInputTokensSeparate() {
        let event = CodexUsageEvent(
            sessionId: "session-1",
            timestamp: Date(timeIntervalSince1970: 0),
            model: "codex-test",
            inputTokens: 10,
            cachedInputTokens: 25,
            outputTokens: 5,
            reasoningTokens: 2,
            totalTokens: 15,
            sourceFile: URL(fileURLWithPath: "/tmp/session.jsonl")
        )

        XCTAssertEqual(event.cachedInputTokens, 25)
    }

    func testCacheRateUsesOnlyCachedAndUncachedInputTokens() throws {
        let totals = TokenTotals(
            inputTokens: 25,
            cachedInputTokens: 75,
            outputTokens: 900,
            reasoningTokens: 300,
            totalTokens: 1_000
        )

        XCTAssertEqual(try XCTUnwrap(totals.cacheRate), 0.75, accuracy: 0.000_001)
    }

    func testCacheRateHandlesZeroAndFullyCachedInput() throws {
        let uncached = TokenTotals(
            inputTokens: 100,
            cachedInputTokens: 0,
            outputTokens: 0,
            reasoningTokens: 0,
            totalTokens: 100
        )
        let cached = TokenTotals(
            inputTokens: 0,
            cachedInputTokens: 100,
            outputTokens: 0,
            reasoningTokens: 0,
            totalTokens: 100
        )

        XCTAssertEqual(try XCTUnwrap(uncached.cacheRate), 0, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(cached.cacheRate), 1, accuracy: 0.000_001)
    }

    func testCacheRateIsNilWithoutInputTokens() {
        let totals = TokenTotals(
            inputTokens: 0,
            cachedInputTokens: 0,
            outputTokens: 100,
            reasoningTokens: 50,
            totalTokens: 100
        )

        XCTAssertNil(totals.cacheRate)
    }
}
