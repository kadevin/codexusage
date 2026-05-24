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
        XCTAssertEqual(estimate.usd, Decimal(string: "15.75"))
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
        XCTAssertEqual(estimate.usd, Decimal(string: "3.50"))
        XCTAssertEqual(estimate.usedFallbackMultiplier, true)
    }

    func testCachedInputUsesCachedInputPricing() {
        let service = PricingService(speedMode: .standard, autoDetectedFast: false)
        let estimate = service.estimate(
            events: [
                CodexUsageEvent(
                    sessionId: "s1",
                    timestamp: Date(timeIntervalSince1970: 0),
                    model: "gpt-5.2-codex",
                    inputTokens: 1_000_000,
                    cachedInputTokens: 400_000,
                    outputTokens: 0,
                    reasoningTokens: 0,
                    totalTokens: 1_000_000,
                    sourceFile: URL(fileURLWithPath: "/tmp/a.jsonl")
                )
            ]
        )
        XCTAssertEqual(estimate.usd, Decimal(string: "1.12"))
        XCTAssertEqual(estimate.hasUnknownPricing, false)
        XCTAssertEqual(estimate.usedFallbackMultiplier, false)
    }

    func testReasoningTokensAreNotDoubleBilledAsOutput() {
        let service = PricingService(speedMode: .standard, autoDetectedFast: false)
        let estimate = service.estimate(
            events: [
                CodexUsageEvent(
                    sessionId: "s1",
                    timestamp: Date(timeIntervalSince1970: 0),
                    model: "gpt-5.2-codex",
                    inputTokens: 0,
                    cachedInputTokens: 0,
                    outputTokens: 100_000,
                    reasoningTokens: 200_000,
                    totalTokens: 300_000,
                    sourceFile: URL(fileURLWithPath: "/tmp/a.jsonl")
                )
            ]
        )

        XCTAssertEqual(estimate.usd, Decimal(string: "1.40"))
        XCTAssertEqual(estimate.hasUnknownPricing, false)
    }

    func testGpt53CodexUsesExplicitFastMultiplier() {
        let service = PricingService(speedMode: .fast, autoDetectedFast: false)
        let estimate = service.estimate(
            events: [
                CodexUsageEvent(
                    sessionId: "s1",
                    timestamp: Date(timeIntervalSince1970: 0),
                    model: "openai/gpt-5.3-codex",
                    inputTokens: 1_000_000,
                    cachedInputTokens: 0,
                    outputTokens: 0,
                    reasoningTokens: 0,
                    totalTokens: 1_000_000,
                    sourceFile: URL(fileURLWithPath: "/tmp/a.jsonl")
                )
            ]
        )

        XCTAssertEqual(estimate.usd, Decimal(string: "3.50"))
        XCTAssertEqual(estimate.usedFallbackMultiplier, false)
    }

    func testGpt54PricingMatchesCodexPricingTable() {
        let service = PricingService(speedMode: .standard, autoDetectedFast: false)
        let estimate = service.estimate(
            events: [
                CodexUsageEvent(
                    sessionId: "s1",
                    timestamp: Date(timeIntervalSince1970: 0),
                    model: "gpt-5.4",
                    inputTokens: 1_000_000,
                    cachedInputTokens: 0,
                    outputTokens: 1_000_000,
                    reasoningTokens: 0,
                    totalTokens: 2_000_000,
                    sourceFile: URL(fileURLWithPath: "/tmp/a.jsonl")
                )
            ]
        )

        XCTAssertEqual(estimate.usd, Decimal(string: "17.50"))
        XCTAssertEqual(estimate.hasUnknownPricing, false)
    }

    func testAutoModeUsesFallbackMultiplierWhenFastIsDetected() {
        let service = PricingService(speedMode: .auto, autoDetectedFast: true)
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
        XCTAssertEqual(estimate.usd, Decimal(string: "3.50"))
        XCTAssertEqual(estimate.usedFallbackMultiplier, true)
    }

    func testMixedKnownAndUnknownEventsReturnKnownCostAndUnknownFlag() {
        let service = PricingService(speedMode: .standard, autoDetectedFast: false)
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
                ),
                CodexUsageEvent(
                    sessionId: "s1",
                    timestamp: Date(timeIntervalSince1970: 0),
                    model: "unknown-model",
                    inputTokens: 1_000_000,
                    cachedInputTokens: 0,
                    outputTokens: 0,
                    reasoningTokens: 0,
                    totalTokens: 1_000_000,
                    sourceFile: URL(fileURLWithPath: "/tmp/b.jsonl")
                )
            ]
        )
        XCTAssertEqual(estimate.usd, Decimal(string: "1.75"))
        XCTAssertEqual(estimate.hasUnknownPricing, true)
    }
}
