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
}
