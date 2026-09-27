import CodexUsageCore
@testable import CodexUsageApp
import XCTest

@MainActor
final class AppModelTests: XCTestCase {
    func testManualRefreshBypassesOfficialUsageCache() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let counter = directory.appendingPathComponent("counter")
        let executable = directory.appendingPathComponent("fake-codex")
        let script = """
        #!/bin/sh
        count=0
        if [ -f "\(counter.path)" ]; then
          count=$(cat "\(counter.path)")
        fi
        count=$((count + 1))
        printf '%s' "$count" > "\(counter.path)"
        printf '{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":%s,"windowDurationMins":10080}}}}\\n' "$count"
        sleep 20
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let defaults = UserDefaults.standard
        let previousPath = defaults.object(forKey: "pathOverride")
        let previousExecutable = defaults.object(forKey: "codexExecutablePath")
        defer {
            restorePreference(previousPath, key: "pathOverride")
            restorePreference(previousExecutable, key: "codexExecutablePath")
        }

        let model = AppModel(strings: AppStrings(preferredLanguages: ["en"]), startsImmediately: false)
        model.pathOverride = directory.path
        model.codexExecutablePath = executable.path

        model.refresh()
        try await waitUntil { model.officialUsage?.limits.first?.windows.first?.usedPercent == 1 }

        model.refresh()
        try await waitUntil { model.statusMessage != model.strings.loading }

        XCTAssertEqual(model.officialUsage?.limits.first?.windows.first?.usedPercent, 2)
    }

    func testPathOverrideDefaultsToResolvedCodexPathWhenPreferenceIsMissing() {
        withTemporaryPathOverridePreference(nil) {
            let model = AppModel(strings: AppStrings(preferredLanguages: ["en"]), startsImmediately: false)

            XCTAssertEqual(
                model.pathOverride,
                CodexPathResolver().resolve(userOverride: nil).path
            )
        }
    }

    func testFailedQuotaRefreshPreservesLastSnapshotAndRecoveryClearsWarning() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fake-codex")
        let response = directory.appendingPathComponent("response")
        try "#!/bin/sh\ncat '\(response.path)'\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let defaults = UserDefaults.standard
        let previousPath = defaults.object(forKey: "pathOverride")
        let previousExecutable = defaults.object(forKey: "codexExecutablePath")
        defer {
            restorePreference(previousPath, key: "pathOverride")
            restorePreference(previousExecutable, key: "codexExecutablePath")
        }
        let model = AppModel(startsImmediately: false)
        model.pathOverride = directory.path
        model.codexExecutablePath = executable.path
        try #"{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":29,"windowDurationMins":10080}}}}"#
            .write(to: response, atomically: true, encoding: .utf8)
        model.refresh()
        try await waitUntil { model.officialUsage != nil }
        let lastSuccessfulSnapshot = try XCTUnwrap(model.officialUsage)
        XCTAssertFalse(model.isOfficialUsageUnavailable)

        try "invalid response".write(to: response, atomically: true, encoding: .utf8)
        model.refresh()
        try await waitUntil { model.statusMessage != model.strings.loading }
        XCTAssertTrue(model.isOfficialUsageUnavailable)
        XCTAssertEqual(model.officialUsage, lastSuccessfulSnapshot)

        try #"{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":5,"windowDurationMins":10080}}}}"#
            .write(to: response, atomically: true, encoding: .utf8)
        model.refresh()
        try await waitUntil { model.statusMessage != model.strings.loading }
        XCTAssertFalse(model.isOfficialUsageUnavailable)
        XCTAssertEqual(model.officialUsage?.limits.first?.windows.first?.remainingPercent, 95)
        XCTAssertGreaterThan(try XCTUnwrap(model.officialUsage?.fetchedAt), lastSuccessfulSnapshot.fetchedAt)
    }

    func testMissingSavedExecutableFallsBackToDetectedCLI() throws {
        guard let detected = CodexExecutableResolver().resolve(explicitPath: nil) else {
            throw XCTSkip("No installed Codex CLI available for fallback verification")
        }
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("codex").path
        withTemporaryPreference(key: "codexExecutablePath", value: missingPath) {
            let model = AppModel(startsImmediately: false)
            XCTAssertEqual(model.codexExecutablePath, detected.path)
        }
    }

    func testPathOverrideDefaultsToResolvedCodexPathWhenPreferenceIsEmpty() {
        withTemporaryPathOverridePreference("") {
            let model = AppModel(strings: AppStrings(preferredLanguages: ["en"]), startsImmediately: false)

            XCTAssertEqual(
                model.pathOverride,
                CodexPathResolver().resolve(userOverride: nil).path
            )
        }
    }

    func testExecutablePathDefaultsToResolvedCodexExecutableWhenPreferenceIsEmpty() {
        withTemporaryPreference(key: "codexExecutablePath", value: "") {
            let model = AppModel(strings: AppStrings(preferredLanguages: ["en"]), startsImmediately: false)

            XCTAssertEqual(
                model.codexExecutablePath,
                CodexExecutableResolver().resolve(explicitPath: nil)?.path ?? ""
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

    private func withTemporaryPreference(key: String, value: String?, perform work: () -> Void) {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: key)
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        work()
    }

    private func restorePreference(_ value: Any?, key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func waitUntil(
        timeoutAttempts: Int = 150,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<timeoutAttempts {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for refresh")
    }
}
