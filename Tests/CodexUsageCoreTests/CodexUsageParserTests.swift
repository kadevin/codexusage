import CodexUsageCore
import XCTest

final class CodexUsageParserTests: XCTestCase {
    func testGpt6AstraUsageIsPricedAcrossSummaries() throws {
        let fixture = try makeJSONL([
            #"{"timestamp":"2026-09-05T10:00:00.000Z","type":"turn_context","payload":{"model":"gpt-6-astra"}}"#,
            #"{"timestamp":"2026-09-05T10:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":400,"output_tokens":100,"reasoning_output_tokens":50,"total_tokens":1100}}}}"#,
            #"{"timestamp":"2026-09-05T10:02:00.000Z","type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"service_tier":"priority"}}}"#,
            #"{"timestamp":"2026-09-05T10:03:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":400,"output_tokens":100,"reasoning_output_tokens":50,"total_tokens":1100}}}}"#
        ])
        defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }
        let events = try CodexUsageParser().parseFile(
            fixture,
            sessionsRoot: fixture.deletingLastPathComponent(),
            fallbackModifiedDate: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(events.map(\.model), ["gpt-6-astra", "gpt-6-astra"])
        XCTAssertFalse(events.contains(where: \.isFallbackModel))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-05T10:30:00Z"))
        let snapshot = UsageAggregator(
            calendar: calendar,
            pricing: PricingService(speedMode: .auto, autoDetectedFast: false)
        ).snapshot(events: events, now: now)
        let day = try XCTUnwrap(snapshot.recentDays.last)
        let summaries = [
            snapshot.today,
            snapshot.currentHour,
            try XCTUnwrap(snapshot.recentHours.last).summary,
            try XCTUnwrap(snapshot.modelBreakdown.first).summary,
            day.summary,
            day.hourlyBreakdown[10].summary,
            try XCTUnwrap(day.modelBreakdown.first).summary
        ]

        for summary in summaries {
            XCTAssertEqual(summary.cost.credits, Decimal(string: "0.9975"))
            XCTAssertFalse(summary.cost.hasUnknownPricing)
            XCTAssertEqual(summary.callCount, 2)
            XCTAssertEqual(summary.totals.totalTokens, 2200)
        }
    }

    func testParsesLastUsageAndTotalUsageDelta() throws {
        let fixture = Bundle.module.url(
            forResource: "codex-session",
            withExtension: "jsonl",
            subdirectory: "Fixtures"
        )!
        let parser = CodexUsageParser()
        let events = try parser.parseFile(
            fixture,
            sessionsRoot: fixture.deletingLastPathComponent(),
            fallbackModifiedDate: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].model, "gpt-5.2-codex")
        XCTAssertEqual(events[0].inputTokens, 800)
        XCTAssertEqual(events[0].cachedInputTokens, 200)
        XCTAssertEqual(events[0].outputTokens, 100)
        XCTAssertEqual(events[0].reasoningTokens, 25)
        XCTAssertEqual(events[0].totalTokens, 1100)
        XCTAssertEqual(events[1].inputTokens, 400)
        XCTAssertEqual(events[1].cachedInputTokens, 100)
        XCTAssertEqual(events[1].outputTokens, 40)
        XCTAssertEqual(events[1].reasoningTokens, 10)
        XCTAssertEqual(events[1].totalTokens, 540)
    }

    func testRepeatedTotalUsageSnapshotIsNotCountedAgain() throws {
        let fixture = try makeJSONL([
            #"{"timestamp":"2026-05-24T00:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"total_tokens":100},"total_token_usage":{"input_tokens":100,"total_tokens":100}}}}"#,
            #"{"timestamp":"2026-05-24T00:02:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"total_tokens":100},"total_token_usage":{"input_tokens":100,"total_tokens":100}}}}"#
        ])

        let events = try CodexUsageParser().parseFile(
            fixture,
            sessionsRoot: fixture.deletingLastPathComponent(),
            fallbackModifiedDate: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].totalTokens, 100)
    }

    func testSubagentSessionUsageIsIncluded() throws {
        let fixture = try makeJSONL([
            #"{"timestamp":"2026-05-24T00:10:00.000Z","type":"session_meta","payload":{"id":"subagent-session","thread_source":"subagent","source":{"subagent":{"thread_spawn":{"parent_thread_id":"parent"}}}}}"#,
            #"{"timestamp":"2026-05-24T00:05:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"total_tokens":100}}}}"#,
            #"{"timestamp":"2026-05-24T00:11:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":130,"total_tokens":130}}}}"#
        ])

        let events = try CodexUsageParser().parseFile(
            fixture,
            sessionsRoot: fixture.deletingLastPathComponent(),
            fallbackModifiedDate: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].sessionId, "subagent-session")
        XCTAssertEqual(events[0].inputTokens, 30)
        XCTAssertEqual(events[0].totalTokens, 30)
    }

    func testThreadSettingsApplyServiceTierToFollowingUsage() throws {
        let fixture = try makeJSONL([
            #"{"timestamp":"2026-05-24T00:00:00.000Z","type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"service_tier":"default"}}}"#,
            #"{"timestamp":"2026-05-24T00:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":10,"total_tokens":10}}}}"#,
            #"{"timestamp":"2026-05-24T00:02:00.000Z","type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"service_tier":"priority"}}}"#,
            #"{"timestamp":"2026-05-24T00:03:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":20,"total_tokens":20}}}}"#
        ])

        let events = try CodexUsageParser().parseFile(
            fixture,
            sessionsRoot: fixture.deletingLastPathComponent(),
            fallbackModifiedDate: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(events.map(\.serviceTier), [.standard, .fast])
    }

    func testWhitespaceModelFallsBackAndMarksFallback() throws {
        let fallbackDate = Date(timeIntervalSince1970: 1)
        let fixture = try makeJSONL([
            #"{"timestamp":"2026-05-24T00:00:00.000Z","type":"turn_context","payload":{"model":"   "}}"#,
            #"{"timestamp":"2026-05-24T00:01:00.000Z","type":"event_msg","payload":{"type":"token_count","model":"  ","info":{"model":" ","last_token_usage":{"input_tokens":1,"total_tokens":1}}}}"#
        ])

        let events = try CodexUsageParser().parseFile(
            fixture,
            sessionsRoot: fixture.deletingLastPathComponent(),
            fallbackModifiedDate: fallbackDate
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].model, "gpt-5")
        XCTAssertTrue(events[0].isFallbackModel)
    }

    func testPayloadAndInfoModelsAreTrimmedAndNotFallback() throws {
        let payloadFixture = try makeJSONL([
            #"{"timestamp":"2026-05-24T00:01:00.000Z","type":"event_msg","payload":{"type":"token_count","model":"  payload-model  ","info":{"last_token_usage":{"input_tokens":1,"total_tokens":1}}}}"#
        ])
        let infoFixture = try makeJSONL([
            #"{"timestamp":"2026-05-24T00:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"model":"  info-model  ","last_token_usage":{"input_tokens":1,"total_tokens":1}}}}"#
        ])

        let payloadEvents = try CodexUsageParser().parseFile(
            payloadFixture,
            sessionsRoot: payloadFixture.deletingLastPathComponent(),
            fallbackModifiedDate: Date(timeIntervalSince1970: 0)
        )
        let infoEvents = try CodexUsageParser().parseFile(
            infoFixture,
            sessionsRoot: infoFixture.deletingLastPathComponent(),
            fallbackModifiedDate: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(payloadEvents[0].model, "payload-model")
        XCTAssertFalse(payloadEvents[0].isFallbackModel)
        XCTAssertEqual(infoEvents[0].model, "info-model")
        XCTAssertFalse(infoEvents[0].isFallbackModel)
    }

    func testMalformedNumericFieldsDoNotProduceUsage() throws {
        let fixture = try makeJSONL([
            #"{"timestamp":"2026-05-24T00:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":true,"cached_input_tokens":-1,"output_tokens":1.5,"reasoning_output_tokens":"   ","total_tokens":"999999999999999999999999999999"}}}}"#
        ])

        let events = try CodexUsageParser().parseFile(
            fixture,
            sessionsRoot: fixture.deletingLastPathComponent(),
            fallbackModifiedDate: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(events, [])
    }

    func testInvalidOrMissingTimestampUsesFallbackModifiedDate() throws {
        let fallbackDate = Date(timeIntervalSince1970: 1234)
        let fixture = try makeJSONL([
            #"{"timestamp":"not-a-date","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1,"total_tokens":1}}}}"#,
            #"{"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":2,"total_tokens":2}}}}"#
        ])

        let events = try CodexUsageParser().parseFile(
            fixture,
            sessionsRoot: fixture.deletingLastPathComponent(),
            fallbackModifiedDate: fallbackDate
        )

        XCTAssertEqual(events.map(\.timestamp), [fallbackDate, fallbackDate])
    }

    func testNumericMillisecondTimestampParsesCorrectly() throws {
        let fixture = try makeJSONL([
            #"{"timestamp":1779580800123,"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1,"total_tokens":1}}}}"#
        ])

        let events = try CodexUsageParser().parseFile(
            fixture,
            sessionsRoot: fixture.deletingLastPathComponent(),
            fallbackModifiedDate: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(events[0].timestamp, Date(timeIntervalSince1970: 1_779_580_800.123))
    }

    func testAliasFieldsParseCorrectly() throws {
        let fixture = try makeJSONL([
            #"{"timestamp":"2026-05-24T00:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"prompt_tokens":"10","cache_read_input_tokens":4,"completion_tokens":3,"reasoning_tokens":2}}}}"#
        ])

        let events = try CodexUsageParser().parseFile(
            fixture,
            sessionsRoot: fixture.deletingLastPathComponent(),
            fallbackModifiedDate: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(events[0].inputTokens, 6)
        XCTAssertEqual(events[0].cachedInputTokens, 4)
        XCTAssertEqual(events[0].outputTokens, 3)
        XCTAssertEqual(events[0].reasoningTokens, 2)
        XCTAssertEqual(events[0].totalTokens, 13)
    }

    func testZeroTokenUsageAndNullInfoAreSkipped() throws {
        let fixture = try makeJSONL([
            #"{"timestamp":"2026-05-24T00:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":0,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":0}}}}"#,
            #"{"timestamp":"2026-05-24T00:02:00.000Z","type":"event_msg","payload":{"type":"token_count","info":null}}"#
        ])

        let events = try CodexUsageParser().parseFile(
            fixture,
            sessionsRoot: fixture.deletingLastPathComponent(),
            fallbackModifiedDate: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(events, [])
    }

    func testTotalOnlyUsageIsSkipped() throws {
        let fixture = try makeJSONL([
            #"{"timestamp":"2026-05-24T00:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":25}}}}"#
        ])

        let events = try CodexUsageParser().parseFile(
            fixture,
            sessionsRoot: fixture.deletingLastPathComponent(),
            fallbackModifiedDate: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(events, [])
    }

    func testLargeIrrelevantLinesDoNotBlockUsageParsing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("large-session.jsonl")

        var data = Data(repeating: UInt8(ascii: "x"), count: 16 * 1024 * 1024)
        data.append(UInt8(ascii: "\n"))
        data.append(Data(#"{"timestamp":"2026-05-24T00:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":7,"total_tokens":7}}}}"#.utf8))
        try data.write(to: file)

        let startedAt = Date()
        let events = try CodexUsageParser().parseFile(
            file,
            sessionsRoot: directory,
            fallbackModifiedDate: Date(timeIntervalSince1970: 0)
        )
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertEqual(events.map(\.inputTokens), [7])
        XCTAssertLessThan(elapsed, 1.0)
    }

    func testNestedPathSessionIdIsRelativeToSessionsRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nested = root.appendingPathComponent("2026/05", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let fixture = nested.appendingPathComponent("session.jsonl")
        try #"{"timestamp":"2026-05-24T00:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1,"total_tokens":1}}}}"#
            .write(to: fixture, atomically: true, encoding: .utf8)

        let events = try CodexUsageParser().parseFile(
            fixture,
            sessionsRoot: root,
            fallbackModifiedDate: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(events[0].sessionId, "2026/05/session")
    }

    private func makeJSONL(_ lines: [String]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("session.jsonl")
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}
