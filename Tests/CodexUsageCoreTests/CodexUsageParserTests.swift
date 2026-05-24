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
}
