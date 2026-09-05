import CodexUsageCore
import XCTest

final class LocalizationTests: XCTestCase {
    func testChinesePreferredLanguageUsesChinese() {
        let strings = AppStrings(preferredLanguages: ["zh-Hans-US", "en-US"])
        XCTAssertEqual(strings.codexUsageTitle, "Codex 用量")
        XCTAssertEqual(strings.today, "今日")
        XCTAssertEqual(strings.thisHour, "本小时")
        XCTAssertEqual(strings.primaryModelToday, "今日主要模型")
        XCTAssertEqual(strings.quit, "退出")
        XCTAssertEqual(strings.auto, "自动")
        XCTAssertEqual(strings.standard, "标准")
        XCTAssertEqual(strings.fast, "快速")
    }

    func testEnglishFallbackForNonChineseLanguage() {
        let strings = AppStrings(preferredLanguages: ["fr-FR", "en-US"])
        XCTAssertEqual(strings.codexUsageTitle, "Codex Usage")
        XCTAssertEqual(strings.today, "Today")
        XCTAssertEqual(strings.thisHour, "This Hour")
        XCTAssertEqual(strings.primaryModelToday, "Primary model today")
        XCTAssertEqual(strings.quit, "Quit")
        XCTAssertEqual(strings.auto, "Auto")
        XCTAssertEqual(strings.standard, "Standard")
        XCTAssertEqual(strings.fast, "Fast")
    }

    func testEnglishIntervalLabels() {
        let strings = AppStrings(preferredLanguages: ["en-US"])
        let labels = RefreshInterval.allCases.map { strings.intervalLabel($0) }
        XCTAssertEqual(labels, ["15 seconds", "30 seconds", "60 seconds", "5 minutes"])
    }

    func testChineseIntervalLabels() {
        let strings = AppStrings(preferredLanguages: ["zh-Hans-US"])
        let labels = RefreshInterval.allCases.map { strings.intervalLabel($0) }
        XCTAssertEqual(labels, ["15 秒", "30 秒", "60 秒", "5 分钟"])
    }

    func testEmptyPreferredLanguagesFallsBackToEnglish() {
        let strings = AppStrings(preferredLanguages: [])
        XCTAssertEqual(strings.codexUsageTitle, "Codex Usage")
        XCTAssertEqual(strings.today, "Today")
        XCTAssertEqual(strings.thisHour, "This Hour")
    }

    func testDailyDetailLabelsFollowLanguage() {
        let english = AppStrings(preferredLanguages: ["en-US"])
        XCTAssertEqual(english.tokenDetails, "Token Details")
        XCTAssertEqual(english.hourlyBreakdown, "Hourly Breakdown")
        XCTAssertEqual(english.modelBreakdown, "Model Breakdown")
        XCTAssertEqual(english.viewDayDetails, "View day details")
        XCTAssertEqual(english.noModelUsage, "No model usage")
        XCTAssertEqual(english.calls, "Calls")
        XCTAssertEqual(english.cacheRate, "Cache Rate")

        let chinese = AppStrings(preferredLanguages: ["zh-Hans-US"])
        XCTAssertEqual(chinese.tokenDetails, "Token 详情")
        XCTAssertEqual(chinese.hourlyBreakdown, "小时分布")
        XCTAssertEqual(chinese.modelBreakdown, "模型分布")
        XCTAssertEqual(chinese.viewDayDetails, "查看日期详情")
        XCTAssertEqual(chinese.noModelUsage, "无模型用量")
        XCTAssertEqual(chinese.calls, "次数")
        XCTAssertEqual(chinese.cacheRate, "缓存率")
    }

    func testOfficialQuotaLabelsAndDynamicWindowsFollowLanguage() {
        let english = AppStrings(preferredLanguages: ["en-US"])
        XCTAssertEqual(english.officialQuota, "Official Quota")
        XCTAssertEqual(english.localEstimate, "Local Log Estimate")
        XCTAssertEqual(english.quotaWindowLabel(minutes: 300), "5 hours")
        XCTAssertEqual(english.quotaWindowLabel(minutes: 10_080), "7 days")
        XCTAssertEqual(english.remainingPercentLabel(49), "49% remaining")
        XCTAssertEqual(english.usedPercentLabel(51), "51% used")

        let chinese = AppStrings(preferredLanguages: ["zh-Hans-US"])
        XCTAssertEqual(chinese.officialQuota, "官方额度")
        XCTAssertEqual(chinese.localEstimate, "本地日志估算")
        XCTAssertEqual(chinese.quotaWindowLabel(minutes: 300), "5 小时")
        XCTAssertEqual(chinese.quotaWindowLabel(minutes: 10_080), "7 天")
        XCTAssertEqual(chinese.remainingPercentLabel(49), "剩余 49%")
        XCTAssertEqual(chinese.usedPercentLabel(51), "已用 51%")
    }
}
