import Foundation

public enum SpeedMode: String, CaseIterable, Sendable {
    case auto
    case standard
    case fast
}

public enum RefreshInterval: Int, CaseIterable, Sendable {
    case fifteenSeconds = 15
    case thirtySeconds = 30
    case sixtySeconds = 60
    case fiveMinutes = 300
}

public struct CodexUsageEvent: Equatable, Sendable {
    public let sessionId: String
    public let timestamp: Date
    public let model: String
    public let inputTokens: Int
    public let cachedInputTokens: Int
    public let outputTokens: Int
    public let reasoningTokens: Int
    public let totalTokens: Int
    public let sourceFile: URL
    public let isFallbackModel: Bool

    public init(
        sessionId: String,
        timestamp: Date,
        model: String,
        inputTokens: Int,
        cachedInputTokens: Int,
        outputTokens: Int,
        reasoningTokens: Int,
        totalTokens: Int,
        sourceFile: URL,
        isFallbackModel: Bool = false
    ) {
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.model = model
        self.inputTokens = inputTokens
        self.cachedInputTokens = min(cachedInputTokens, inputTokens)
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
        self.totalTokens = totalTokens
        self.sourceFile = sourceFile
        self.isFallbackModel = isFallbackModel
    }
}

public struct TokenTotals: Equatable, Sendable {
    public var inputTokens: Int
    public var cachedInputTokens: Int
    public var outputTokens: Int
    public var reasoningTokens: Int
    public var totalTokens: Int

    public static let zero = TokenTotals(
        inputTokens: 0,
        cachedInputTokens: 0,
        outputTokens: 0,
        reasoningTokens: 0,
        totalTokens: 0
    )
}

public struct CostEstimate: Equatable, Sendable {
    public let usd: Decimal?
    public let hasUnknownPricing: Bool
    public let usedFallbackMultiplier: Bool
}

public struct UsageSummary: Equatable, Sendable {
    public let totals: TokenTotals
    public let cost: CostEstimate
}
