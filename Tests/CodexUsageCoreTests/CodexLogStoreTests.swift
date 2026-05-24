import CodexUsageCore
import XCTest

final class CodexLogStoreTests: XCTestCase {
    func testDiscoversJsonlFilesUnderSessions() throws {
        let root = try makeTemporaryDirectory()
        let project = root.appendingPathComponent("sessions/project-a", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let session = project.appendingPathComponent("session.jsonl")
        try "".write(to: session, atomically: true, encoding: .utf8)

        let files = try CodexLogStore().discoverJSONLFiles(root: root)

        XCTAssertEqual(
            files.map { $0.resolvingSymlinksInPath().path },
            [session.resolvingSymlinksInPath().path]
        )
    }

    func testDiscoversJsonlFilesUnderRootWhenSessionsDirectoryMissing() throws {
        let root = try makeTemporaryDirectory()
        let session = root.appendingPathComponent("session.jsonl")
        try "".write(to: session, atomically: true, encoding: .utf8)

        let files = try CodexLogStore().discoverJSONLFiles(root: root)

        XCTAssertEqual(
            files.map { $0.resolvingSymlinksInPath().path },
            [session.resolvingSymlinksInPath().path]
        )
    }

    func testDiscoverySkipsHiddenAndNonJsonlFiles() throws {
        let root = try makeTemporaryDirectory()
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let visible = sessions.appendingPathComponent("session.jsonl")
        let hidden = sessions.appendingPathComponent(".hidden.jsonl")
        let text = sessions.appendingPathComponent("notes.txt")
        try "".write(to: visible, atomically: true, encoding: .utf8)
        try "".write(to: hidden, atomically: true, encoding: .utf8)
        try "".write(to: text, atomically: true, encoding: .utf8)

        let files = try CodexLogStore().discoverJSONLFiles(root: root)

        XCTAssertEqual(
            files.map { $0.resolvingSymlinksInPath().path },
            [visible.resolvingSymlinksInPath().path]
        )
    }

    func testLoadEventsUsesSessionsDirectoryAsParserRoot() throws {
        let root = try makeTemporaryDirectory()
        let project = root.appendingPathComponent("sessions/project-a", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let session = project.appendingPathComponent("session.jsonl")
        try tokenCountLine(inputTokens: 12).write(to: session, atomically: true, encoding: .utf8)

        let events = try CodexLogStore().loadEvents(root: root)

        XCTAssertEqual(events.first?.sessionId, "project-a/session")
    }

    func testDetectsPriorityServiceTier() throws {
        let root = try makeTemporaryDirectory()
        try writeConfig(#"service_tier = "priority""#, root: root)

        XCTAssertTrue(CodexLogStore().detectFastMode(root: root))
    }

    func testDetectsPriorityServiceTierWithoutSpaces() throws {
        let root = try makeTemporaryDirectory()
        try writeConfig(#"service_tier="priority""#, root: root)

        XCTAssertTrue(CodexLogStore().detectFastMode(root: root))
    }

    func testDetectsFastServiceTierWithExtraSpaces() throws {
        let root = try makeTemporaryDirectory()
        try writeConfig(#"service_tier    =    "fast""#, root: root)

        XCTAssertTrue(CodexLogStore().detectFastMode(root: root))
    }

    func testCommentedPriorityServiceTierDoesNotEnableFastMode() throws {
        let root = try makeTemporaryDirectory()
        try writeConfig(#"# service_tier = "priority""#, root: root)

        XCTAssertFalse(CodexLogStore().detectFastMode(root: root))
    }

    func testMissingConfigDoesNotEnableFastMode() throws {
        let root = try makeTemporaryDirectory()

        XCTAssertFalse(CodexLogStore().detectFastMode(root: root))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.resolvingSymlinksInPath()
    }

    private func writeConfig(_ contents: String, root: URL) throws {
        try contents.write(to: root.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
    }

    private func tokenCountLine(inputTokens: Int) -> String {
        #"{"timestamp":"2026-05-24T00:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":\#(inputTokens),"total_tokens":\#(inputTokens)}}}}"#
    }
}
