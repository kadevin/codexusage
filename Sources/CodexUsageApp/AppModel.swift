import CodexUsageCore
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var snapshot: UsageSnapshot
    var strings: AppStrings
    var statusMessage: String
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
    var panelOpacity: Double {
        didSet {
            UserDefaults.standard.set(panelOpacity, forKey: Self.panelOpacityKey)
        }
    }

    @ObservationIgnored var onAlwaysOnTopChanged: ((Bool) -> Void)?

    @ObservationIgnored private let resolver = CodexPathResolver()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var timerTask: Task<Void, Never>?

    private static let alwaysOnTopKey = "alwaysOnTop"
    private static let refreshIntervalKey = "refreshInterval"
    private static let speedModeKey = "speedMode"
    private static let pathOverrideKey = "pathOverride"
    private static let panelOpacityKey = "panelOpacity"

    init(strings: AppStrings = AppStrings()) {
        self.strings = strings
        self.statusMessage = ""
        self.isAlwaysOnTop = UserDefaults.standard.bool(forKey: Self.alwaysOnTopKey)

        let savedInterval = UserDefaults.standard.integer(forKey: Self.refreshIntervalKey)
        self.refreshInterval = RefreshInterval(rawValue: savedInterval) ?? .sixtySeconds

        let savedSpeed = UserDefaults.standard.string(forKey: Self.speedModeKey)
        self.speedMode = savedSpeed.flatMap(SpeedMode.init(rawValue:)) ?? .auto
        self.pathOverride = Self.initialPathOverride(
            savedPath: UserDefaults.standard.string(forKey: Self.pathOverrideKey)
        )
        self.panelOpacity = UserDefaults.standard.object(forKey: Self.panelOpacityKey) as? Double ?? 0.92
        self.snapshot = Self.emptySnapshot()
        refresh()
    }

    func refresh() {
        refreshTask?.cancel()
        statusMessage = strings.loading

        let path = resolver.resolve(userOverride: pathOverride.isEmpty ? nil : pathOverride)
        let speedMode = speedMode
        let strings = strings

        refreshTask = Task {
            do {
                let result = try await Self.makeRefreshResult(path: path, speedMode: speedMode)
                try Task.checkCancellation()

                self.snapshot = result.snapshot
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
                refresh()
                try? await Task.sleep(for: .seconds(refreshInterval.rawValue))
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

    private nonisolated static func makeRefreshResult(
        path: URL,
        speedMode: SpeedMode
    ) async throws -> AppRefreshResult {
        try Task.checkCancellation()

        let store = CodexLogStore(parser: CodexUsageParser())
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
            path: path.path
        )
    }

    private static func emptySnapshot() -> UsageSnapshot {
        let zeroSummary = UsageSummary(
            totals: .zero,
            cost: CostEstimate(
                usd: Decimal.zero,
                hasUnknownPricing: false,
                usedFallbackMultiplier: false
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
}
