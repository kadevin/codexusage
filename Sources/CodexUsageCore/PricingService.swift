import Foundation

public struct PricingService: Sendable {
    private struct ModelPrice: Sendable {
        let inputPerMillion: Decimal
        let cachedInputPerMillion: Decimal
        let outputPerMillion: Decimal
        let fastMultiplier: Decimal
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
            if effectiveFastMode, price.fastMultiplier == 1 {
                usedFallback = true
            }

            total += Decimal(event.inputTokens) * price.inputPerMillion / 1_000_000 * multiplier
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
        return price.fastMultiplier == 1 ? 2 : price.fastMultiplier
    }

    private static func price(for model: String) -> ModelPrice? {
        let normalized = model.lowercased()
        if let exact = priceTable.first(where: { $0.model == normalized }) {
            return exact.price
        }

        return priceTable
            .filter { normalized.contains($0.model) || $0.model.contains(normalized) }
            .max { lhs, rhs in
                if lhs.model.count == rhs.model.count {
                    return lhs.model > rhs.model
                }
                return lhs.model.count < rhs.model.count
            }?
            .price
    }

    private static let priceTable: [(model: String, price: ModelPrice)] = [
        (
            "gpt-5.5",
            ModelPrice(
                inputPerMillion: Decimal(string: "5.00")!,
                cachedInputPerMillion: Decimal(string: "0.50")!,
                outputPerMillion: Decimal(string: "30.00")!,
                fastMultiplier: Decimal(string: "2.5")!
            )
        ),
        (
            "gpt-5.4-mini",
            ModelPrice(
                inputPerMillion: Decimal(string: "0.75")!,
                cachedInputPerMillion: Decimal(string: "0.075")!,
                outputPerMillion: Decimal(string: "4.50")!,
                fastMultiplier: 1
            )
        ),
        (
            "gpt-5.4-nano",
            ModelPrice(
                inputPerMillion: Decimal(string: "0.20")!,
                cachedInputPerMillion: Decimal(string: "0.020")!,
                outputPerMillion: Decimal(string: "1.25")!,
                fastMultiplier: 1
            )
        ),
        (
            "gpt-5.4",
            ModelPrice(
                inputPerMillion: Decimal(string: "2.50")!,
                cachedInputPerMillion: Decimal(string: "0.25")!,
                outputPerMillion: Decimal(string: "15.00")!,
                fastMultiplier: 2
            )
        ),
        (
            "gpt-5.3-codex",
            ModelPrice(
                inputPerMillion: Decimal(string: "1.75")!,
                cachedInputPerMillion: Decimal(string: "0.175")!,
                outputPerMillion: Decimal(string: "14.00")!,
                fastMultiplier: 2
            )
        ),
        (
            "gpt-5.2-codex",
            ModelPrice(
                inputPerMillion: Decimal(string: "1.75")!,
                cachedInputPerMillion: Decimal(string: "0.175")!,
                outputPerMillion: Decimal(string: "14.00")!,
                fastMultiplier: 1
            )
        ),
        (
            "gpt-5.2",
            ModelPrice(
                inputPerMillion: Decimal(string: "1.75")!,
                cachedInputPerMillion: Decimal(string: "0.175")!,
                outputPerMillion: Decimal(string: "14.00")!,
                fastMultiplier: 1
            )
        ),
        (
            "gpt-5",
            ModelPrice(
                inputPerMillion: Decimal(string: "1.75")!,
                cachedInputPerMillion: Decimal(string: "0.175")!,
                outputPerMillion: Decimal(string: "14.00")!,
                fastMultiplier: 1
            )
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
