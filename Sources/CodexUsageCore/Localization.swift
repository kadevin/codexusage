import Foundation

public struct AppStrings: Equatable, Sendable {
    public enum Language: Equatable, Sendable {
        case english
        case simplifiedChinese
    }

    public let language: Language

    public init(preferredLanguages: [String] = Locale.preferredLanguages) {
        let first = preferredLanguages.first?.lowercased() ?? "en"
        self.language = first.hasPrefix("zh") ? .simplifiedChinese : .english
    }

    public var codexUsageTitle: String { text(en: "Codex Usage", zh: "Codex 用量") }
    public var today: String { text(en: "Today", zh: "今日") }
    public var thisHour: String { text(en: "This Hour", zh: "本小时") }
    public var recentHours: String { text(en: "Recent 24h", zh: "最近 24 小时") }
    public var models: String { text(en: "Models", zh: "模型") }
    public var refresh: String { text(en: "Refresh", zh: "刷新") }
    public var preferences: String { text(en: "Preferences", zh: "偏好设置") }
    public var alwaysOnTop: String { text(en: "Always on Top", zh: "窗口置顶") }
    public var refreshInterval: String { text(en: "Refresh Interval", zh: "刷新间隔") }
    public var speedMode: String { text(en: "Speed Pricing", zh: "速度计价") }
    public var codexPath: String { text(en: "Codex Path", zh: "Codex 路径") }
    public var noData: String { text(en: "No Codex data found", zh: "未找到 Codex 数据") }
    public var unreadablePath: String { text(en: "Path is not readable", zh: "路径不可读取") }
    public var unknownPricing: String { text(en: "Unknown pricing", zh: "未知价格") }
    public var estimated: String { text(en: "Estimated", zh: "估算") }
    public var lastUpdated: String { text(en: "Updated", zh: "更新于") }

    public func intervalLabel(_ interval: RefreshInterval) -> String {
        switch (language, interval) {
        case (.english, .fifteenSeconds): return "15 seconds"
        case (.english, .thirtySeconds): return "30 seconds"
        case (.english, .sixtySeconds): return "60 seconds"
        case (.english, .fiveMinutes): return "5 minutes"
        case (.simplifiedChinese, .fifteenSeconds): return "15 秒"
        case (.simplifiedChinese, .thirtySeconds): return "30 秒"
        case (.simplifiedChinese, .sixtySeconds): return "60 秒"
        case (.simplifiedChinese, .fiveMinutes): return "5 分钟"
        }
    }

    private func text(en: String, zh: String) -> String {
        language == .simplifiedChinese ? zh : en
    }
}
