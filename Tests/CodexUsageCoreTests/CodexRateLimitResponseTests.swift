import CodexUsageCore
import XCTest

final class CodexRateLimitResponseTests: XCTestCase {
    func testOfficialUsageWindowConvertsUsedPercentToClampedRemainingPercent() {
        XCTAssertEqual(
            OfficialUsageWindow(usedPercent: 51, durationMinutes: 10_080, resetsAt: nil)
                .remainingPercent,
            49
        )
        XCTAssertEqual(
            OfficialUsageWindow(usedPercent: -5, durationMinutes: nil, resetsAt: nil)
                .remainingPercent,
            100
        )
        XCTAssertEqual(
            OfficialUsageWindow(usedPercent: 105, durationMinutes: nil, resetsAt: nil)
                .remainingPercent,
            0
        )
    }

    func testDecodesDynamicOfficialRateLimitWindows() throws {
        let fetchedAt = Date(timeIntervalSince1970: 1_786_000_000)
        let output = Data(
            """
            {"method":"account/rateLimits/updated","params":{"rateLimits":null}}
            {"id":2,"result":{"rateLimits":{"limitId":"codex","limitName":null,"primary":{"usedPercent":46,"windowDurationMins":10080,"resetsAt":1786000100},"secondary":null,"credits":{"hasCredits":true,"unlimited":false,"balance":"12.5"},"planType":"pro"},"rateLimitsByLimitId":{"codex_bengalfox":{"limitId":"codex_bengalfox","limitName":"GPT-5.3-Codex-Spark","primary":{"usedPercent":20,"windowDurationMins":300,"resetsAt":1786000200},"secondary":{"usedPercent":35,"windowDurationMins":10080,"resetsAt":1786000300},"credits":{"hasCredits":false,"unlimited":false,"balance":null},"planType":"pro"},"codex":{"limitId":"codex","limitName":null,"primary":{"usedPercent":46,"windowDurationMins":10080,"resetsAt":1786000100},"secondary":null,"credits":{"hasCredits":true,"unlimited":false,"balance":"12.5"},"planType":"pro"}},"rateLimitResetCredits":{"availableCount":1,"credits":[]}}}
            """.utf8
        )

        let snapshot = try CodexRateLimitResponseDecoder().decode(
            appServerOutput: output,
            fetchedAt: fetchedAt
        )

        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
        XCTAssertEqual(snapshot.resetCreditsAvailable, 1)
        XCTAssertEqual(snapshot.limits.map(\.id), ["codex", "codex_bengalfox"])

        let codex = try XCTUnwrap(snapshot.limits.first { $0.id == "codex" })
        XCTAssertEqual(codex.planType, "pro")
        XCTAssertEqual(codex.windows.count, 1)
        XCTAssertEqual(codex.windows[0].usedPercent, 46)
        XCTAssertEqual(codex.windows[0].durationMinutes, 10_080)
        XCTAssertEqual(codex.windows[0].resetsAt, Date(timeIntervalSince1970: 1_786_000_100))
        XCTAssertEqual(codex.creditBalance, Decimal(string: "12.5"))

        let spark = try XCTUnwrap(snapshot.limits.first { $0.id == "codex_bengalfox" })
        XCTAssertEqual(spark.name, "GPT-5.3-Codex-Spark")
        XCTAssertEqual(spark.windows.map(\.durationMinutes), [300, 10_080])
        XCTAssertEqual(spark.windows.map(\.usedPercent), [20, 35])
    }

    func testThrowsWhenReadResponseIsMissing() {
        let output = Data(#"{"id":1,"result":{"userAgent":"CodexUsage"}}"#.utf8)

        XCTAssertThrowsError(try CodexRateLimitResponseDecoder().decode(appServerOutput: output)) { error in
            XCTAssertEqual(
                error as? CodexRateLimitError,
                .responseMissing(#"{"id":1,"result":{"userAgent":"CodexUsage"}}"#)
            )
        }
    }

    func testExecutableResolverUsesExplicitExecutable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("codex")
        try Data().write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let resolved = CodexExecutableResolver().resolve(
            explicitPath: executable.path,
            environment: [:],
            homeDirectory: directory
        )

        XCTAssertEqual(resolved?.standardizedFileURL, executable.standardizedFileURL)
    }

    func testExecutableResolverUsesPathWhenNoOverrideExists() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("codex")
        try Data().write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let resolved = CodexExecutableResolver().resolve(
            explicitPath: nil,
            environment: ["PATH": directory.path],
            homeDirectory: directory
        )

        XCTAssertEqual(resolved?.standardizedFileURL, executable.standardizedFileURL)
    }

    func testExecutableResolverFindsCodexBundledWithChatGPT() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let executable = directory
            .appendingPathComponent("ChatGPT.app/Contents/Resources/codex")
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let resolved = CodexExecutableResolver().resolve(
            explicitPath: nil,
            environment: [:],
            homeDirectory: directory,
            applicationsDirectory: directory
        )

        XCTAssertEqual(resolved?.standardizedFileURL, executable.standardizedFileURL)
    }

    func testClientReturnsAfterResponseWithoutWaitingForServerExit() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("fake-codex")
        let script = """
        #!/bin/sh
        printf '%s\\n' '{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":7,"windowDurationMins":300}}}}'
        sleep 20
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let start = Date()

        let snapshot = try await CodexRateLimitClient().fetch(
            codexExecutablePath: executable.path,
            codexHome: nil,
            maximumAge: 0
        )

        XCTAssertEqual(snapshot.limits.first?.windows.first?.usedPercent, 7)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testClientIncludesServerErrorOutput() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("fake-codex")
        let script = """
        #!/bin/sh
        echo 'app-server failed for test' >&2
        exit 3
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        do {
            _ = try await CodexRateLimitClient().fetch(
                codexExecutablePath: executable.path,
                codexHome: nil,
                maximumAge: 0
            )
            XCTFail("Expected server failure")
        } catch let CodexRateLimitError.serverFailed(status, message) {
            XCTAssertEqual(status, 3)
            XCTAssertEqual(message, "app-server failed for test")
        }
    }

    func testInstalledCodexRateLimitIntegration() async throws {
        guard ProcessInfo.processInfo.environment["CODEXUSAGE_RUN_LIVE_RATE_LIMIT_TEST"] == "1" else {
            throw XCTSkip("Set CODEXUSAGE_RUN_LIVE_RATE_LIMIT_TEST=1 to query the installed Codex CLI")
        }
        let executable = try XCTUnwrap(CodexExecutableResolver().resolve(explicitPath: nil))

        let snapshot = try await CodexRateLimitClient().fetch(
            codexExecutablePath: executable.path,
            codexHome: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"),
            maximumAge: 0
        )

        XCTAssertFalse(snapshot.limits.isEmpty)
    }
}
