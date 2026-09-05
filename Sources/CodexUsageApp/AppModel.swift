import CodexUsageCore
import Darwin
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var snapshot: UsageSnapshot
    var strings: AppStrings
    var statusMessage: String
    var officialUsage: OfficialUsageSnapshot?
    var isOfficialUsageUnavailable: Bool
    var isAlwaysOnTop: Bool {
        didSet {
            UserDefaults.standard.set(isAlwaysOnTop, forKey: Self.alwaysOnTopKey)
            onAlwaysOnTopChanged?(isAlwaysOnTop)
        }
    }
    var refreshInterval: RefreshInterval {
        didSet {
            UserDefaults.standard.set(refreshInterval.rawValue, forKey: Self.refreshIntervalKey)
            restartTimerIfRunning()
        }
    }
    var speedMode: SpeedMode {
        didSet {
            UserDefaults.standard.set(speedMode.rawValue, forKey: Self.speedModeKey)
        }
    }
    var pathOverride: String {
        didSet {
            UserDefaults.standard.set(pathOverride, forKey: Self.pathOverrideKey)
        }
    }
    var codexExecutablePath: String {
        didSet {
            UserDefaults.standard.set(codexExecutablePath, forKey: Self.codexExecutablePathKey)
        }
    }
    var panelOpacity: Double {
        didSet {
            UserDefaults.standard.set(panelOpacity, forKey: Self.panelOpacityKey)
        }
    }

    @ObservationIgnored var onAlwaysOnTopChanged: ((Bool) -> Void)?

    @ObservationIgnored private let resolver = CodexPathResolver()
    @ObservationIgnored private let store = CodexLogStore(parser: CodexUsageParser())
    @ObservationIgnored private let rateLimitClient = CodexRateLimitClient()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var timerTask: Task<Void, Never>?

    private static let alwaysOnTopKey = "alwaysOnTop"
    private static let refreshIntervalKey = "refreshInterval"
    private static let speedModeKey = "speedMode"
    private static let pathOverrideKey = "pathOverride"
    private static let panelOpacityKey = "panelOpacity"
    private static let codexExecutablePathKey = "codexExecutablePath"

    init(strings: AppStrings = AppStrings(), startsImmediately: Bool = true) {
        self.strings = strings
        self.statusMessage = ""
        self.officialUsage = nil
        self.isOfficialUsageUnavailable = false
        self.isAlwaysOnTop = UserDefaults.standard.bool(forKey: Self.alwaysOnTopKey)

        let savedInterval = UserDefaults.standard.integer(forKey: Self.refreshIntervalKey)
        self.refreshInterval = RefreshInterval(rawValue: savedInterval) ?? .sixtySeconds

        let savedSpeed = UserDefaults.standard.string(forKey: Self.speedModeKey)
        self.speedMode = savedSpeed.flatMap(SpeedMode.init(rawValue:)) ?? .auto
        self.pathOverride = Self.initialPathOverride(
            savedPath: UserDefaults.standard.string(forKey: Self.pathOverrideKey)
        )
        self.codexExecutablePath = Self.initialExecutablePath(
            savedPath: UserDefaults.standard.string(forKey: Self.codexExecutablePathKey)
        )
        self.panelOpacity = UserDefaults.standard.object(forKey: Self.panelOpacityKey) as? Double ?? 0.92
        self.snapshot = Self.emptySnapshot()
        if startsImmediately {
            refresh()
        }
    }

    func refresh() {
        refreshTask?.cancel()
        statusMessage = strings.loading

        let path = resolver.resolve(userOverride: pathOverride.isEmpty ? nil : pathOverride)
        let speedMode = speedMode
        let strings = strings
        let store = store
        let codexExecutablePath = codexExecutablePath
        let rateLimitClient = rateLimitClient

        refreshTask = Task {
            do {
                let result = try await Self.makeRefreshResult(
                    path: path,
                    speedMode: speedMode,
                    store: store,
                    codexExecutablePath: codexExecutablePath,
                    rateLimitClient: rateLimitClient
                )
                try Task.checkCancellation()

                self.snapshot = result.snapshot
                if let officialUsage = result.officialUsage {
                    self.officialUsage = officialUsage
                }
                self.isOfficialUsageUnavailable = result.officialUsage == nil
                self.statusMessage = result.hasEvents ? result.path : strings.noData
            } catch is CancellationError {
                return
            } catch {
                self.snapshot = Self.emptySnapshot()
                self.statusMessage = strings.unreadablePath
            }
        }
    }

    func startTimerIfNeeded() {
        guard timerTask == nil else {
            return
        }

        timerTask = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(refreshInterval.rawValue))
                } catch {
                    return
                }
                refresh()
            }
        }
    }

    private func restartTimerIfRunning() {
        guard timerTask != nil else {
            return
        }

        timerTask?.cancel()
        timerTask = nil
        startTimerIfNeeded()
    }

    deinit {
        refreshTask?.cancel()
        timerTask?.cancel()
    }

    private static func initialPathOverride(savedPath: String?) -> String {
        CodexPathResolver().resolve(userOverride: savedPath).path
    }

    private static func initialExecutablePath(savedPath: String?) -> String {
        if let savedPath, !savedPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return savedPath
        }
        return CodexExecutableResolver().resolve(explicitPath: nil)?.path ?? ""
    }

    private nonisolated static func makeRefreshResult(
        path: URL,
        speedMode: SpeedMode,
        store: CodexLogStore,
        codexExecutablePath: String,
        rateLimitClient: CodexRateLimitClient
    ) async throws -> AppRefreshResult {
        defer {
            _ = malloc_zone_pressure_relief(nil, 0)
        }

        let localResult = try autoreleasepool {
            try Task.checkCancellation()

            let now = Date()
            let calendar = Calendar.current
            let dayStart = calendar.startOfDay(for: now)
            let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
            let recentStart = calendar.date(byAdding: .hour, value: -23, to: hourStart) ?? dayStart
            let recentDaysStart = calendar.date(byAdding: .day, value: -6, to: dayStart) ?? dayStart
            let since = min(dayStart, recentStart, recentDaysStart)
            let events = try store.loadEvents(root: path, since: since)
            try Task.checkCancellation()

            let autoDetectedFast = store.detectFastMode(root: path)
            try Task.checkCancellation()

            let pricing = PricingService(speedMode: speedMode, autoDetectedFast: autoDetectedFast)
            let snapshot = UsageAggregator(calendar: calendar, pricing: pricing).snapshot(events: events, now: now)
            try Task.checkCancellation()

            return AppRefreshResult(
                snapshot: snapshot,
                hasEvents: !events.isEmpty,
                path: path.path,
                officialUsage: nil
            )
        }

        let officialUsage = try? await rateLimitClient.fetch(
            codexExecutablePath: codexExecutablePath.isEmpty ? nil : codexExecutablePath,
            codexHome: path,
            force: true
        )
        return AppRefreshResult(
            snapshot: localResult.snapshot,
            hasEvents: localResult.hasEvents,
            path: localResult.path,
            officialUsage: officialUsage
        )
    }

    private static func emptySnapshot() -> UsageSnapshot {
        let zeroSummary = UsageSummary(
            totals: .zero,
            cost: CostEstimate(
                credits: Decimal.zero,
                hasUnknownPricing: false
            )
        )

        return UsageSnapshot(
            generatedAt: Date(),
            today: zeroSummary,
            currentHour: zeroSummary,
            recentHours: [],
            recentDays: [],
            modelBreakdown: [],
            warnings: []
        )
    }
}

private struct AppRefreshResult: Sendable {
    let snapshot: UsageSnapshot
    let hasEvents: Bool
    let path: String
    let officialUsage: OfficialUsageSnapshot?
}
