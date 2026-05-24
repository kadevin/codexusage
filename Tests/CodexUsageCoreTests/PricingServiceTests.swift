import CodexUsageCore
import XCTest

final class PricingServiceTests: XCTestCase {
    func testKnownModelCostUsesStandardPricing() {
        let service = PricingService(speedMode: .standard, autoDetectedFast: false)
        let estimate = service.estimate(
            events: [
                CodexUsageEvent(
                    sessionId: "s1",
                    timestamp: Date(timeIntervalSince1970: 0),
                    model: "gpt-5.2-codex",
                    inputTokens: 1_000_000,
                    cachedInputTokens: 0,
                    outputTokens: 1_000_000,
                    reasoningTokens: 0,
                    totalTokens: 2_000_000,
                    sourceFile: URL(fileURLWithPath: "/tmp/a.jsonl")
                )
            ]
        )
        XCTAssertEqual(estimate.hasUnknownPricing, false)
        XCTAssertEqual(estimate.usedFallbackMultiplier, false)
        XCTAssertEqual(estimate.usd, Decimal(string: "12.50"))
    }

    func testUnknownModelMarksUnknownPricing() {
        let service = PricingService(speedMode: .standard, autoDetectedFast: false)
        let estimate = service.estimate(
            events: [
                CodexUsageEvent(
                    sessionId: "s1",
                    timestamp: Date(timeIntervalSince1970: 0),
                    model: "unknown-model",
                    inputTokens: 1,
                    cachedInputTokens: 0,
                    outputTokens: 1,
                    reasoningTokens: 0,
                    totalTokens: 2,
                    sourceFile: URL(fileURLWithPath: "/tmp/a.jsonl")
                )
            ]
        )
        XCTAssertNil(estimate.usd)
        XCTAssertEqual(estimate.hasUnknownPricing, true)
    }

    func testFastModeUsesTwoTimesFallbackWhenModelHasNoSpecificMultiplier() {
        let service = PricingService(speedMode: .fast, autoDetectedFast: false)
        let estimate = service.estimate(
            events: [
                CodexUsageEvent(
                    sessionId: "s1",
                    timestamp: Date(timeIntervalSince1970: 0),
                    model: "gpt-5.2-codex",
                    inputTokens: 1_000_000,
                    cachedInputTokens: 0,
                    outputTokens: 0,
                    reasoningTokens: 0,
                    totalTokens: 1_000_000,
                    sourceFile: URL(fileURLWithPath: "/tmp/a.jsonl")
                )
            ]
        )
        XCTAssertEqual(estimate.usd, Decimal(string: "5.00"))
        XCTAssertEqual(estimate.usedFallbackMultiplier, true)
    }
}
