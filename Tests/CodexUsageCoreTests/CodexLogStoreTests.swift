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

    func testMissingRootThrowsWhenDiscoveringJsonlFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        XCTAssertThrowsError(try CodexLogStore().discoverJSONLFiles(root: root))
    }

    func testReadableEmptyRootReturnsNoJsonlFiles() throws {
        let root = try makeTemporaryDirectory()

        let files = try CodexLogStore().discoverJSONLFiles(root: root)

        XCTAssertEqual(files, [])
    }

    func testUnreadableSessionsDirectoryThrowsWhenDiscoveringJsonlFiles() throws {
        let root = try makeTemporaryDirectory()
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: sessions.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: sessions.path)
        }

        guard !FileManager.default.isReadableFile(atPath: sessions.path) else {
            throw XCTSkip("Current filesystem did not make chmod 000 directory unreadable")
        }

        XCTAssertThrowsError(try CodexLogStore().discoverJSONLFiles(root: root))
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

    func testLoadEventsWithSinceSkipsOldSessionFiles() throws {
        let root = try makeTemporaryDirectory()
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let oldDirectory = sessions.appendingPathComponent("2026/05/22", isDirectory: true)
        let recentDirectory = sessions.appendingPathComponent("2026/05/24", isDirectory: true)
        try FileManager.default.createDirectory(at: oldDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: recentDirectory, withIntermediateDirectories: true)

        let oldSession = oldDirectory.appendingPathComponent("old.jsonl")
        let recentSession = recentDirectory.appendingPathComponent("recent.jsonl")
        try tokenCountLine(inputTokens: 1).write(to: oldSession, atomically: true, encoding: .utf8)
        try tokenCountLine(inputTokens: 7).write(to: recentSession, atomically: true, encoding: .utf8)

        let oldDate = try date("2026-05-22T01:00:00Z")
        let recentDate = try date("2026-05-24T01:00:00Z")
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldSession.path)
        try FileManager.default.setAttributes([.modificationDate: recentDate], ofItemAtPath: recentSession.path)

        let since = try date("2026-05-24T00:00:00Z")
        let events = try CodexLogStore().loadEvents(root: root, since: since)

        XCTAssertEqual(events.map(\.inputTokens), [7])
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

    func testDetectsQuotedPriorityServiceTierWithInlineComment() throws {
        let root = try makeTemporaryDirectory()
        try writeConfig(#"service_tier = 'priority' # use higher tier"#, root: root)

        XCTAssertTrue(CodexLogStore().detectFastMode(root: root))
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

    private func date(_ string: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: string) else {
            throw CocoaError(.coderInvalidValue)
        }
        return date
    }
}
