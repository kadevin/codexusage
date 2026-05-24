import CodexUsageCore
import XCTest

final class CodexUsageParserTests: XCTestCase {
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
        XCTAssertEqual(events[0].inputTokens, 1000)
        XCTAssertEqual(events[0].cachedInputTokens, 200)
        XCTAssertEqual(events[0].outputTokens, 100)
        XCTAssertEqual(events[0].reasoningTokens, 25)
        XCTAssertEqual(events[1].inputTokens, 500)
        XCTAssertEqual(events[1].cachedInputTokens, 100)
        XCTAssertEqual(events[1].outputTokens, 40)
        XCTAssertEqual(events[1].reasoningTokens, 10)
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

        XCTAssertEqual(events[0].inputTokens, 10)
        XCTAssertEqual(events[0].cachedInputTokens, 4)
        XCTAssertEqual(events[0].outputTokens, 3)
        XCTAssertEqual(events[0].reasoningTokens, 2)
        XCTAssertEqual(events[0].totalTokens, 15)
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
