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

    @ObservationIgnored var onAlwaysOnTopChanged: ((Bool) -> Void)?

    @ObservationIgnored private let resolver = CodexPathResolver()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var timerTask: Task<Void, Never>?

    private static let alwaysOnTopKey = "alwaysOnTop"
    private static let refreshIntervalKey = "refreshInterval"
    private static let speedModeKey = "speedMode"
    private static let pathOverrideKey = "pathOverride"

    init(strings: AppStrings = AppStrings()) {
        self.strings = strings
        self.statusMessage = ""
        self.isAlwaysOnTop = UserDefaults.standard.bool(forKey: Self.alwaysOnTopKey)

        let savedInterval = UserDefaults.standard.integer(forKey: Self.refreshIntervalKey)
        self.refreshInterval = RefreshInterval(rawValue: savedInterval) ?? .sixtySeconds

        let savedSpeed = UserDefaults.standard.string(forKey: Self.speedModeKey)
        self.speedMode = savedSpeed.flatMap(SpeedMode.init(rawValue:)) ?? .auto
        self.pathOverride = UserDefaults.standard.string(forKey: Self.pathOverrideKey) ?? ""
        self.snapshot = Self.emptySnapshot()
    }

    func refresh() {
        refreshTask?.cancel()

        let path = resolver.resolve(userOverride: pathOverride.isEmpty ? nil : pathOverride)
        let speedMode = speedMode
        let strings = strings

        refreshTask = Task {
            do {
                let result = try await Task.detached {
                    let store = CodexLogStore(parser: CodexUsageParser())
                    return (
                        events: try store.loadEvents(root: path),
                        autoDetectedFast: store.detectFastMode(root: path)
                    )
                }.value

                guard !Task.isCancelled else {
                    return
                }

                let pricing = PricingService(
                    speedMode: speedMode,
                    autoDetectedFast: result.autoDetectedFast
                )
                let snapshot = UsageAggregator(pricing: pricing)
                    .snapshot(events: result.events, now: Date())

                self.snapshot = snapshot
                self.statusMessage = result.events.isEmpty ? strings.noData : path.path
            } catch {
                guard !Task.isCancelled else {
                    return
                }
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

    deinit {
        refreshTask?.cancel()
        timerTask?.cancel()
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
            modelBreakdown: [],
            warnings: []
        )
    }
}
