import Foundation

public struct PricingService: Sendable {
    private struct ModelPrice: Sendable {
        let inputCreditsPerMillion: Decimal
        let cachedInputCreditsPerMillion: Decimal
        let outputCreditsPerMillion: Decimal
        let fastMultiplier: Decimal?
    }

    private let speedMode: SpeedMode
    private let autoDetectedFast: Bool

    public init(speedMode: SpeedMode, autoDetectedFast: Bool) {
        self.speedMode = speedMode
        self.autoDetectedFast = autoDetectedFast
    }

    public func estimate(events: [CodexUsageEvent]) -> CostEstimate {
        guard !events.isEmpty else {
            return CostEstimate(credits: .zero, hasUnknownPricing: false)
        }

        var total = Decimal.zero
        var hasKnownPricing = false
        var hasUnknownPricing = false

        for event in events {
            guard let price = Self.price(for: event.model) else {
                hasUnknownPricing = true
                continue
            }

            hasKnownPricing = true
            let multiplier = usesFastMode(for: event) ? price.fastMultiplier ?? 1 : 1
            total += Decimal(event.inputTokens) * price.inputCreditsPerMillion / 1_000_000 * multiplier
            total += Decimal(event.cachedInputTokens) * price.cachedInputCreditsPerMillion / 1_000_000 * multiplier
            total += Decimal(event.outputTokens) * price.outputCreditsPerMillion / 1_000_000 * multiplier
        }

        return CostEstimate(
            credits: hasKnownPricing ? total.rounded(scale: 4) : nil,
            hasUnknownPricing: hasUnknownPricing
        )
    }

    private func usesFastMode(for event: CodexUsageEvent) -> Bool {
        switch speedMode {
        case .auto:
            switch event.serviceTier {
            case .fast: return true
            case .standard: return false
            case nil: return autoDetectedFast
            }
        case .standard: return false
        case .fast: return true
        }
    }

    private static func price(for model: String) -> ModelPrice? {
        let normalized = model
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let modelName = normalized.split(separator: "/").last.map(String.init) ?? normalized

        if modelName == "gpt-5.6" {
            return priceTable["gpt-5.6-sol"]
        }
        if modelName == "codex-auto-review" {
            return priceTable["gpt-5.6-luna"]
        }
        if let exact = priceTable[modelName] {
            return exact
        }

        return priceTable
            .filter { modelName.hasPrefix($0.key + "-") }
            .max { $0.key.count < $1.key.count }?
            .value
    }

    // Official Codex credit rates plus documented compatibility estimates, updated 2026-09-30.
    private static let priceTable: [String: ModelPrice] = [
        "gpt-6-astra": ModelPrice(
            inputCreditsPerMillion: 250,
            cachedInputCreditsPerMillion: 25,
            outputCreditsPerMillion: 1_250,
            fastMultiplier: Decimal(string: "2.5")!
        ),
        "gpt-6.1-sol": ModelPrice(
            inputCreditsPerMillion: 50,
            cachedInputCreditsPerMillion: Decimal(string: "2.5")!,
            outputCreditsPerMillion: 250,
            fastMultiplier: Decimal(string: "2.5")!
        ),
        "gpt-6-sol": ModelPrice(
            inputCreditsPerMillion: 50,
            cachedInputCreditsPerMillion: 5,
            outputCreditsPerMillion: 250,
            fastMultiplier: Decimal(string: "2.5")!
        ),
        "gpt-6-luna": ModelPrice(
            inputCreditsPerMillion: Decimal(string: "2.5")!,
            cachedInputCreditsPerMillion: Decimal(string: "0.25")!,
            outputCreditsPerMillion: Decimal(string: "12.5")!,
            fastMultiplier: Decimal(string: "2.5")!
        ),
        "gpt-5.6-sol": ModelPrice(
            inputCreditsPerMillion: 100,
            cachedInputCreditsPerMillion: 10,
            outputCreditsPerMillion: 500,
            fastMultiplier: Decimal(string: "2.5")!
        ),
        "gpt-5.6-terra": ModelPrice(
            inputCreditsPerMillion: 50,
            cachedInputCreditsPerMillion: 5,
            outputCreditsPerMillion: 300,
            fastMultiplier: Decimal(string: "2.5")!
        ),
        "gpt-5.6-luna": ModelPrice(
            inputCreditsPerMillion: 5,
            cachedInputCreditsPerMillion: Decimal(string: "0.5")!,
            outputCreditsPerMillion: 30,
            fastMultiplier: Decimal(string: "2.5")!
        ),
        "gpt-5.5": ModelPrice(
            inputCreditsPerMillion: 125,
            cachedInputCreditsPerMillion: Decimal(string: "12.5")!,
            outputCreditsPerMillion: 750,
            fastMultiplier: Decimal(string: "2.5")!
        ),
        "gpt-5.4": ModelPrice(
            inputCreditsPerMillion: Decimal(string: "62.5")!,
            cachedInputCreditsPerMillion: Decimal(string: "6.25")!,
            outputCreditsPerMillion: 375,
            fastMultiplier: 2
        ),
        "gpt-5.4-mini": ModelPrice(
            inputCreditsPerMillion: Decimal(string: "18.75")!,
            cachedInputCreditsPerMillion: Decimal(string: "1.875")!,
            outputCreditsPerMillion: 113,
            fastMultiplier: nil
        ),
        "gpt-5.3-codex-spark": ModelPrice(
            inputCreditsPerMillion: Decimal(string: "43.75")!,
            cachedInputCreditsPerMillion: Decimal(string: "4.375")!,
            outputCreditsPerMillion: 350,
            fastMultiplier: nil
        )
    ]
}

extension Decimal {
    func rounded(scale: Int) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, .plain)
        return result
    }
}
