import CodexUsageCore
@testable import CodexUsageApp
import XCTest

@MainActor
final class AppModelTests: XCTestCase {
    func testPathOverrideDefaultsToResolvedCodexPathWhenPreferenceIsMissing() {
        withTemporaryPathOverridePreference(nil) {
            let model = AppModel(strings: AppStrings(preferredLanguages: ["en"]))

            XCTAssertEqual(
                model.pathOverride,
                CodexPathResolver().resolve(userOverride: nil).path
            )
        }
    }

    func testPathOverrideDefaultsToResolvedCodexPathWhenPreferenceIsEmpty() {
        withTemporaryPathOverridePreference("") {
            let model = AppModel(strings: AppStrings(preferredLanguages: ["en"]))

            XCTAssertEqual(
                model.pathOverride,
                CodexPathResolver().resolve(userOverride: nil).path
            )
        }
    }

    private func withTemporaryPathOverridePreference(
        _ value: String?,
        perform work: () -> Void
    ) {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: "pathOverride")
        if let value {
            defaults.set(value, forKey: "pathOverride")
        } else {
            defaults.removeObject(forKey: "pathOverride")
        }
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: "pathOverride")
            } else {
                defaults.removeObject(forKey: "pathOverride")
            }
        }

        work()
    }
}
