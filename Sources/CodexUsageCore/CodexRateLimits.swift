import Foundation

public struct OfficialUsageSnapshot: Equatable, Sendable {
    public let fetchedAt: Date
    public let limits: [OfficialUsageLimit]
    public let resetCreditsAvailable: Int

    public init(fetchedAt: Date, limits: [OfficialUsageLimit], resetCreditsAvailable: Int) {
        self.fetchedAt = fetchedAt
        self.limits = limits
        self.resetCreditsAvailable = resetCreditsAvailable
    }
}

public struct OfficialUsageLimit: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    public let planType: String?
    public let windows: [OfficialUsageWindow]
    public let hasCredits: Bool
    public let creditsUnlimited: Bool
    public let creditBalance: Decimal?

    public init(
        id: String,
        name: String?,
        planType: String?,
        windows: [OfficialUsageWindow],
        hasCredits: Bool,
        creditsUnlimited: Bool,
        creditBalance: Decimal?
    ) {
        self.id = id
        self.name = name
        self.planType = planType
        self.windows = windows
        self.hasCredits = hasCredits
        self.creditsUnlimited = creditsUnlimited
        self.creditBalance = creditBalance
    }
}

public struct OfficialUsageWindow: Equatable, Sendable {
    public let usedPercent: Int
    public let durationMinutes: Int?
    public let resetsAt: Date?

    public var remainingPercent: Int {
        100 - min(max(usedPercent, 0), 100)
    }

    public init(usedPercent: Int, durationMinutes: Int?, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.durationMinutes = durationMinutes
        self.resetsAt = resetsAt
    }
}

public enum CodexRateLimitError: Error, Equatable {
    case responseMissing(String)
    case executableNotFound
    case serverFailed(Int32, String)
    case timedOut
}

public struct CodexRateLimitResponseDecoder: Sendable {
    public init() {}

    public func decode(
        appServerOutput: Data,
        fetchedAt: Date = Date()
    ) throws -> OfficialUsageSnapshot {
        for line in appServerOutput.split(separator: UInt8(ascii: "\n")) {
            guard
                let envelope = try? JSONDecoder().decode(RPCEnvelope.self, from: Data(line)),
                envelope.id == 2,
                let result = envelope.result
            else {
                continue
            }
            return Self.snapshot(from: result, fetchedAt: fetchedAt)
        }
        throw CodexRateLimitError.responseMissing(
            String(data: appServerOutput, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }

    private static func snapshot(
        from result: RawResponse,
        fetchedAt: Date
    ) -> OfficialUsageSnapshot {
        var limitsByID: [String: RawLimit] = [:]
        for (key, limit) in result.rateLimitsByLimitId ?? [:] {
            limitsByID[limit.limitId ?? key] = limit
        }
        if let main = result.rateLimits {
            let id = main.limitId ?? "codex"
            if limitsByID[id] == nil {
                limitsByID[id] = main
            }
        }

        let limits = limitsByID.map { id, raw in
            OfficialUsageLimit(
                id: id,
                name: raw.limitName,
                planType: raw.planType,
                windows: [raw.primary, raw.secondary]
                    .compactMap { $0 }
                    .map { window in
                        OfficialUsageWindow(
                            usedPercent: window.usedPercent,
                            durationMinutes: window.windowDurationMins,
                            resetsAt: window.resetsAt.map(Date.init(timeIntervalSince1970:))
                        )
                    }
                    .sorted { ($0.durationMinutes ?? Int.max) < ($1.durationMinutes ?? Int.max) },
                hasCredits: raw.credits?.hasCredits ?? false,
                creditsUnlimited: raw.credits?.unlimited ?? false,
                creditBalance: raw.credits?.decimalBalance
            )
        }
        .sorted { lhs, rhs in
            if lhs.id == "codex" { return true }
            if rhs.id == "codex" { return false }
            return lhs.id < rhs.id
        }

        return OfficialUsageSnapshot(
            fetchedAt: fetchedAt,
            limits: limits,
            resetCreditsAvailable: result.rateLimitResetCredits?.availableCount ?? 0
        )
    }
}

private struct RPCEnvelope: Decodable {
    let id: Int?
    let result: RawResponse?
}

private struct RawResponse: Decodable {
    let rateLimits: RawLimit?
    let rateLimitsByLimitId: [String: RawLimit]?
    let rateLimitResetCredits: RawResetCredits?
}

private struct RawLimit: Decodable {
    let limitId: String?
    let limitName: String?
    let primary: RawWindow?
    let secondary: RawWindow?
    let credits: RawCredits?
    let planType: String?
}

private struct RawWindow: Decodable {
    let usedPercent: Int
    let windowDurationMins: Int?
    let resetsAt: TimeInterval?
}

private struct RawCredits: Decodable {
    let hasCredits: Bool
    let unlimited: Bool
    let decimalBalance: Decimal?

    private enum CodingKeys: String, CodingKey {
        case hasCredits
        case unlimited
        case balance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasCredits = try container.decode(Bool.self, forKey: .hasCredits)
        unlimited = try container.decode(Bool.self, forKey: .unlimited)
        if let value = try? container.decode(String.self, forKey: .balance) {
            decimalBalance = Decimal(string: value)
        } else if let value = try? container.decode(Decimal.self, forKey: .balance) {
            decimalBalance = value
        } else {
            decimalBalance = nil
        }
    }
}

private struct RawResetCredits: Decodable {
    let availableCount: Int
}
