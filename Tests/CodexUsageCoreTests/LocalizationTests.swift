import CodexUsageCore
import XCTest

final class LocalizationTests: XCTestCase {
    func testChinesePreferredLanguageUsesChinese() {
        let strings = AppStrings(preferredLanguages: ["zh-Hans-US", "en-US"])
        XCTAssertEqual(strings.codexUsageTitle, "Codex 用量")
        XCTAssertEqual(strings.today, "今日")
        XCTAssertEqual(strings.thisHour, "本小时")
    }

    func testEnglishFallbackForNonChineseLanguage() {
        let strings = AppStrings(preferredLanguages: ["fr-FR", "en-US"])
        XCTAssertEqual(strings.codexUsageTitle, "Codex Usage")
        XCTAssertEqual(strings.today, "Today")
        XCTAssertEqual(strings.thisHour, "This Hour")
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
}
