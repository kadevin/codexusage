import CodexUsageCore
import XCTest

final class PricingServiceTests: XCTestCase {
    func testOfficialCodexCreditRates() {
        let service = PricingService(speedMode: .standard, autoDetectedFast: false)
        let expectations: [(String, Decimal)] = [
            ("gpt-6-astra", Decimal(string: "1525")!),
            ("gpt-5.6-sol", Decimal(string: "610")!),
            ("gpt-5.6-terra", Decimal(string: "355")!),
            ("gpt-5.6-luna", Decimal(string: "35.5")!),
            ("gpt-5.5", Decimal(string: "887.5")!),
            ("gpt-5.4", Decimal(string: "443.75")!),
            ("gpt-5.4-mini", Decimal(string: "133.625")!)
        ]

        for (model, expectedCredits) in expectations {
            let estimate = service.estimate(events: [event(model: model)])

            XCTAssertEqual(estimate.credits, expectedCredits, model)
            XCTAssertFalse(estimate.hasUnknownPricing, model)
        }
    }

    func testGpt6AstraPricingAcrossModelNamesAndSpeedModes() {
        let models = ["gpt-6-astra", " GPT-6-ASTRA ", "openai/gpt-6-astra"]
        let modes: [(SpeedMode, Bool, UsageServiceTier?, Decimal)] = [
            (.standard, true, .fast, 285),
            (.fast, false, .standard, Decimal(string: "712.5")!),
            (.auto, false, nil, 285),
            (.auto, true, nil, Decimal(string: "712.5")!),
            (.auto, true, .standard, 285),
            (.auto, false, .fast, Decimal(string: "712.5")!)
        ]

        for model in models {
            for (mode, detectedFast, tier, expectedCredits) in modes {
                let service = PricingService(speedMode: mode, autoDetectedFast: detectedFast)
                let estimate = service.estimate(events: [event(
                    model: model,
                    inputTokens: 600_000,
                    cachedInputTokens: 400_000,
                    outputTokens: 100_000,
                    serviceTier: tier
                )])
                let context = "\(model), mode=\(mode), detectedFast=\(detectedFast), tier=\(String(describing: tier))"

                XCTAssertEqual(estimate.credits, expectedCredits, context)
                XCTAssertFalse(estimate.hasUnknownPricing, context)
            }
        }
    }

    func testGpt56AliasUsesSolPricing() {
        let service = PricingService(speedMode: .standard, autoDetectedFast: false)
        let estimate = service.estimate(events: [event(model: "gpt-5.6")])

        XCTAssertEqual(estimate.credits, Decimal(string: "610"))
        XCTAssertFalse(estimate.hasUnknownPricing)
    }

    func testCodexAutoReviewUsesLunaPricing() {
        let service = PricingService(speedMode: .standard, autoDetectedFast: false)
        let estimate = service.estimate(events: [event(model: "codex-auto-review")])

        XCTAssertEqual(estimate.credits, Decimal(string: "35.5"))
        XCTAssertFalse(estimate.hasUnknownPricing)
    }

    func testSparkUsesCompatibilityEstimateWithoutFastMultiplier() {
        let service = PricingService(speedMode: .fast, autoDetectedFast: false)
        let estimate = service.estimate(events: [event(model: "gpt-5.3-codex-spark")])

        XCTAssertEqual(estimate.credits, Decimal(string: "398.125"))
        XCTAssertFalse(estimate.hasUnknownPricing)
    }

    func testProviderPrefixedModelUsesExactKnownModelPricing() {
        let service = PricingService(speedMode: .standard, autoDetectedFast: false)
        let estimate = service.estimate(events: [event(model: "openai/gpt-5.6-terra")])

        XCTAssertEqual(estimate.credits, Decimal(string: "355"))
        XCTAssertFalse(estimate.hasUnknownPricing)
    }

    func testFastModeUsesDocumentedMultipliersOnly() {
        let service = PricingService(speedMode: .fast, autoDetectedFast: false)

        XCTAssertEqual(
            service.estimate(events: [event(model: "gpt-5.5", outputTokens: 0)]).credits,
            Decimal(string: "343.75")
        )
        XCTAssertEqual(
            service.estimate(events: [event(model: "gpt-5.4", outputTokens: 0)]).credits,
            Decimal(string: "137.5")
        )
    }

    func testFastModeUsesGpt56Multiplier() {
        let service = PricingService(speedMode: .fast, autoDetectedFast: false)
        let estimate = service.estimate(events: [event(model: "gpt-5.6-sol", outputTokens: 0)])

        XCTAssertEqual(estimate.credits, Decimal(string: "275"))
        XCTAssertFalse(estimate.hasUnknownPricing)
    }

    func testAutoModeUsesDetectedFastMode() {
        let service = PricingService(speedMode: .auto, autoDetectedFast: true)
        let estimate = service.estimate(events: [event(model: "gpt-5.5", outputTokens: 0)])

        XCTAssertEqual(estimate.credits, Decimal(string: "343.75"))
    }

    func testAutoModeUsesRecordedServiceTierPerEvent() {
        let service = PricingService(speedMode: .auto, autoDetectedFast: false)
        let estimate = service.estimate(events: [
            event(model: "gpt-5.6-sol", inputTokens: 1_000_000, cachedInputTokens: 0, outputTokens: 0, serviceTier: .standard),
            event(model: "gpt-5.6-sol", inputTokens: 1_000_000, cachedInputTokens: 0, outputTokens: 0, serviceTier: .fast)
        ])

        XCTAssertEqual(estimate.credits, Decimal(string: "350"))
    }

    func testCachedInputUsesCachedInputRate() {
        let service = PricingService(speedMode: .standard, autoDetectedFast: false)
        let estimate = service.estimate(
            events: [
                event(
                    model: "gpt-5.6-sol",
                    inputTokens: 600_000,
                    cachedInputTokens: 400_000,
                    outputTokens: 0
                )
            ]
        )

        XCTAssertEqual(estimate.credits, Decimal(string: "64"))
    }

    func testDeprecatedGenericModelDoesNotFuzzyMatchCurrentModel() {
        let service = PricingService(speedMode: .standard, autoDetectedFast: false)
        let estimate = service.estimate(events: [event(model: "gpt-5")])

        XCTAssertNil(estimate.credits)
        XCTAssertTrue(estimate.hasUnknownPricing)
    }

    func testMixedKnownAndUnknownEventsReturnKnownCreditsAndUnknownFlag() {
        let service = PricingService(speedMode: .standard, autoDetectedFast: false)
        let estimate = service.estimate(
            events: [
                event(model: "gpt-5.6-luna", inputTokens: 1_000_000, cachedInputTokens: 0, outputTokens: 0),
                event(model: "unknown-model", inputTokens: 1_000_000, cachedInputTokens: 0, outputTokens: 0)
            ]
        )

        XCTAssertEqual(estimate.credits, Decimal(string: "5"))
        XCTAssertTrue(estimate.hasUnknownPricing)
    }

    func testReasoningTokensAreNotDoubleCountedAsOutput() {
        let service = PricingService(speedMode: .standard, autoDetectedFast: false)
        let estimate = service.estimate(
            events: [
                event(
                    model: "gpt-5.6-sol",
                    inputTokens: 0,
                    cachedInputTokens: 0,
                    outputTokens: 100_000,
                    reasoningTokens: 200_000
                )
            ]
        )

        XCTAssertEqual(estimate.credits, Decimal(string: "50"))
    }

    func testEmptyEventsEstimateZeroCredits() {
        let service = PricingService(speedMode: .standard, autoDetectedFast: false)
        let estimate = service.estimate(events: [])

        XCTAssertEqual(estimate.credits, Decimal.zero)
        XCTAssertFalse(estimate.hasUnknownPricing)
    }

    private func event(
        model: String,
        inputTokens: Int = 1_000_000,
        cachedInputTokens: Int = 1_000_000,
        outputTokens: Int = 1_000_000,
        reasoningTokens: Int = 0,
        serviceTier: UsageServiceTier? = nil
    ) -> CodexUsageEvent {
        CodexUsageEvent(
            sessionId: UUID().uuidString,
            timestamp: Date(timeIntervalSince1970: 0),
            model: model,
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            reasoningTokens: reasoningTokens,
            totalTokens: inputTokens + outputTokens,
            sourceFile: URL(fileURLWithPath: "/tmp/test.jsonl"),
            serviceTier: serviceTier
        )
    }
}
