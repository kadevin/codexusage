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
        self.cachedInputTokens = cachedInputTokens
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

    public init(
        inputTokens: Int,
        cachedInputTokens: Int,
        outputTokens: Int,
        reasoningTokens: Int,
        totalTokens: Int
    ) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
        self.totalTokens = totalTokens
    }

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

    public init(
        usd: Decimal?,
        hasUnknownPricing: Bool,
        usedFallbackMultiplier: Bool
    ) {
        self.usd = usd
        self.hasUnknownPricing = hasUnknownPricing
        self.usedFallbackMultiplier = usedFallbackMultiplier
    }
}

public struct UsageSummary: Equatable, Sendable {
    public let totals: TokenTotals
    public let cost: CostEstimate

    public init(totals: TokenTotals, cost: CostEstimate) {
        self.totals = totals
        self.cost = cost
    }
}

public struct HourBucket: Equatable, Identifiable, Sendable {
    public var id: Date { start }
    public let start: Date
    public let summary: UsageSummary

    public init(start: Date, summary: UsageSummary) {
        self.start = start
        self.summary = summary
    }
}

public struct DayBucket: Equatable, Identifiable, Sendable {
    public var id: Date { start }
    public let start: Date
    public let summary: UsageSummary

    public init(start: Date, summary: UsageSummary) {
        self.start = start
        self.summary = summary
    }
}

public struct ModelBreakdown: Equatable, Identifiable, Sendable {
    public var id: String { model }
    public let model: String
    public let summary: UsageSummary

    public init(model: String, summary: UsageSummary) {
        self.model = model
        self.summary = summary
    }
}

public struct UsageSnapshot: Equatable, Sendable {
    public let generatedAt: Date
    public let today: UsageSummary
    public let currentHour: UsageSummary
    public let recentHours: [HourBucket]
    public let recentDays: [DayBucket]
    public let modelBreakdown: [ModelBreakdown]
    public let warnings: [String]

    public init(
        generatedAt: Date,
        today: UsageSummary,
        currentHour: UsageSummary,
        recentHours: [HourBucket],
        recentDays: [DayBucket],
        modelBreakdown: [ModelBreakdown],
        warnings: [String]
    ) {
        self.generatedAt = generatedAt
        self.today = today
        self.currentHour = currentHour
        self.recentHours = recentHours
        self.recentDays = recentDays
        self.modelBreakdown = modelBreakdown
        self.warnings = warnings
    }
}
