import Foundation

public enum SpeedMode: String, CaseIterable, Sendable {
    case auto
    case standard
    case fast
}

public enum UsageServiceTier: String, Sendable {
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
    public let serviceTier: UsageServiceTier?

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
        isFallbackModel: Bool = false,
        serviceTier: UsageServiceTier? = nil
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
        self.serviceTier = serviceTier
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

    public var cacheRate: Double? {
        let totalInputTokens = Double(inputTokens) + Double(cachedInputTokens)
        guard totalInputTokens > 0 else {
            return nil
        }

        return Double(cachedInputTokens) / totalInputTokens
    }
}

public struct CostEstimate: Equatable, Sendable {
    public let credits: Decimal?
    public let hasUnknownPricing: Bool

    public init(
        credits: Decimal?,
        hasUnknownPricing: Bool
    ) {
        self.credits = credits
        self.hasUnknownPricing = hasUnknownPricing
    }
}

public struct UsageSummary: Equatable, Sendable {
    public let totals: TokenTotals
    public let cost: CostEstimate
    public let callCount: Int

    public init(totals: TokenTotals, cost: CostEstimate, callCount: Int = 0) {
        self.totals = totals
        self.cost = cost
        self.callCount = callCount
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
    public let hourlyBreakdown: [HourBucket]
    public let modelBreakdown: [ModelBreakdown]

    public init(
        start: Date,
        summary: UsageSummary,
        hourlyBreakdown: [HourBucket] = [],
        modelBreakdown: [ModelBreakdown] = []
    ) {
        self.start = start
        self.summary = summary
        self.hourlyBreakdown = hourlyBreakdown
        self.modelBreakdown = modelBreakdown
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
