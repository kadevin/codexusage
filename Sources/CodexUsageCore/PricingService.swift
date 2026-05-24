import Foundation

public struct PricingService: Sendable {
    private struct ModelPrice: Sendable {
        let inputPerMillion: Decimal
        let cachedInputPerMillion: Decimal
        let outputPerMillion: Decimal
        let fastMultiplier: Decimal?
    }

    private let speedMode: SpeedMode
    private let autoDetectedFast: Bool

    public init(speedMode: SpeedMode, autoDetectedFast: Bool) {
        self.speedMode = speedMode
        self.autoDetectedFast = autoDetectedFast
    }

    public func estimate(events: [CodexUsageEvent]) -> CostEstimate {
        var total = Decimal.zero
        var hasCost = false
        var hasUnknown = false
        var usedFallback = false

        for event in events {
            guard let price = Self.price(for: event.model) else {
                hasUnknown = true
                continue
            }

            hasCost = true
            let multiplier = multiplier(for: price)
            if multiplier == Decimal(2), price.fastMultiplier == nil, effectiveFastMode {
                usedFallback = true
            }

            let uncachedInput = max(event.inputTokens - event.cachedInputTokens, 0)
            total += Decimal(uncachedInput) * price.inputPerMillion / 1_000_000 * multiplier
            total += Decimal(event.cachedInputTokens) * price.cachedInputPerMillion / 1_000_000 * multiplier
            total += Decimal(event.outputTokens) * price.outputPerMillion / 1_000_000 * multiplier
        }

        return CostEstimate(
            usd: hasCost ? total.rounded(scale: 4) : nil,
            hasUnknownPricing: hasUnknown,
            usedFallbackMultiplier: usedFallback
        )
    }

    private var effectiveFastMode: Bool {
        switch speedMode {
        case .auto: return autoDetectedFast
        case .standard: return false
        case .fast: return true
        }
    }

    private func multiplier(for price: ModelPrice) -> Decimal {
        guard effectiveFastMode else { return 1 }
        return price.fastMultiplier ?? 2
    }

    private static func price(for model: String) -> ModelPrice? {
        let normalized = model.lowercased()
        if normalized.contains("gpt-5.2-codex") || normalized == "gpt-5" {
            return ModelPrice(
                inputPerMillion: Decimal(string: "2.50")!,
                cachedInputPerMillion: Decimal(string: "0.25")!,
                outputPerMillion: Decimal(string: "10.00")!,
                fastMultiplier: nil
            )
        }
        if normalized.contains("gpt-5.3-codex") {
            return ModelPrice(
                inputPerMillion: Decimal(string: "3.00")!,
                cachedInputPerMillion: Decimal(string: "0.30")!,
                outputPerMillion: Decimal(string: "12.00")!,
                fastMultiplier: nil
            )
        }
        return nil
    }
}

extension Decimal {
    func rounded(scale: Int) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, .plain)
        return result
    }
}
