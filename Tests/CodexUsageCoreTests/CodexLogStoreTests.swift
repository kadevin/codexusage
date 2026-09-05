@testable import CodexUsageCore
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

    func testDiscoversJsonlFilesUnderSessionsAndArchivedSessions() throws {
        let root = try makeTemporaryDirectory()
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let archivedSessions = root.appendingPathComponent("archived_sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archivedSessions, withIntermediateDirectories: true)
        let active = sessions.appendingPathComponent("active.jsonl")
        let archived = archivedSessions.appendingPathComponent("archived.jsonl")
        try "".write(to: active, atomically: true, encoding: .utf8)
        try "".write(to: archived, atomically: true, encoding: .utf8)

        let files = try CodexLogStore().discoverJSONLFiles(root: root)

        XCTAssertEqual(
            files.map { $0.resolvingSymlinksInPath().path },
            [active, archived].map { $0.resolvingSymlinksInPath().path }.sorted()
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

    func testLoadEventsIncludesSubagentSessionUsage() throws {
        let root = try makeTemporaryDirectory()
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let session = sessions.appendingPathComponent("subagent.jsonl")
        let contents = [
            #"{"timestamp":"2026-05-24T00:00:00.000Z","type":"session_meta","payload":{"thread_source":"subagent","source":{"subagent":{"thread_spawn":{"parent_thread_id":"parent"}}}}}"#,
            tokenCountLine(inputTokens: 23)
        ].joined(separator: "\n")
        try contents.write(to: session, atomically: true, encoding: .utf8)

        let events = try CodexLogStore().loadEvents(root: root)

        XCTAssertEqual(events.map(\.inputTokens), [23])
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

    func testLoadEventsWithSinceIncludesArchivedSession() throws {
        let root = try makeTemporaryDirectory()
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let archivedSessions = root.appendingPathComponent("archived_sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archivedSessions, withIntermediateDirectories: true)
        let archived = archivedSessions.appendingPathComponent(
            "rollout-2026-05-24T00-01-00-session.jsonl"
        )
        try tokenCountLine(inputTokens: 9).write(to: archived, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: try date("2026-05-24T01:00:00Z")],
            ofItemAtPath: archived.path
        )

        let events = try CodexLogStore().loadEvents(
            root: root,
            since: try date("2026-05-24T00:00:00Z")
        )

        XCTAssertEqual(events.map(\.inputTokens), [9])
        XCTAssertEqual(events.first?.sourceFile.resolvingSymlinksInPath(), archived.resolvingSymlinksInPath())
    }

    func testSecondLoadReusesUnchangedFileWithoutReadingItAgain() throws {
        let root = try makeTemporaryDirectory()
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let session = sessions.appendingPathComponent("session.jsonl")
        try (tokenCountLine(inputTokens: 12) + "\n")
            .write(to: session, atomically: true, encoding: .utf8)
        let store = CodexLogStore()

        let firstEvents = try store.loadEvents(root: root)
        let firstMetrics = store.lastLoadMetrics
        let secondEvents = try store.loadEvents(root: root)
        let secondMetrics = store.lastLoadMetrics

        XCTAssertEqual(firstEvents, secondEvents)
        XCTAssertEqual(firstMetrics.parsedFileCount, 1)
        XCTAssertGreaterThan(firstMetrics.bytesRead, 0)
        XCTAssertEqual(secondMetrics.parsedFileCount, 0)
        XCTAssertEqual(secondMetrics.reusedFileCount, 1)
        XCTAssertEqual(secondMetrics.bytesRead, 0)
    }

    func testGrowingFileReadsOnlyAppendedBytesAndPreservesUsageDeltaState() throws {
        let root = try makeTemporaryDirectory()
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let session = sessions.appendingPathComponent("session.jsonl")
        try (totalTokenCountLine(totalInputTokens: 100, minute: 1) + "\n")
            .write(to: session, atomically: true, encoding: .utf8)
        let store = CodexLogStore()
        XCTAssertEqual(try store.loadEvents(root: root).map(\.inputTokens), [100])

        let appended = totalTokenCountLine(totalInputTokens: 150, minute: 2) + "\n"
        let handle = try FileHandle(forWritingTo: session)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(appended.utf8))
        try handle.close()

        let events = try store.loadEvents(root: root)
        let metrics = store.lastLoadMetrics

        XCTAssertEqual(events.map(\.inputTokens), [100, 50])
        XCTAssertEqual(metrics.parsedFileCount, 1)
        XCTAssertEqual(metrics.bytesRead, UInt64(appended.utf8.count))
    }

    func testLoadEventsRetainsOnlyEventsAtOrAfterSinceWhilePreservingCumulativeDelta() throws {
        let root = try makeTemporaryDirectory()
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let session = sessions.appendingPathComponent("session.jsonl")
        let contents = [
            totalTokenCountLine(totalInputTokens: 100, minute: 1),
            totalTokenCountLine(totalInputTokens: 150, minute: 2)
        ].joined(separator: "\n") + "\n"
        try contents.write(to: session, atomically: true, encoding: .utf8)
        let store = CodexLogStore()

        let events = try store.loadEvents(
            root: root,
            since: try date("2026-05-24T00:02:00Z")
        )

        XCTAssertEqual(events.map(\.inputTokens), [50])
        XCTAssertEqual(store.lastLoadMetrics.retainedEventCount, 1)
    }

    func testRequestingEarlierWindowReparsesAWindowedCache() throws {
        let root = try makeTemporaryDirectory()
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let session = sessions.appendingPathComponent("session.jsonl")
        let contents = [
            totalTokenCountLine(totalInputTokens: 100, minute: 1),
            totalTokenCountLine(totalInputTokens: 150, minute: 2)
        ].joined(separator: "\n") + "\n"
        try contents.write(to: session, atomically: true, encoding: .utf8)
        let store = CodexLogStore()

        XCTAssertEqual(
            try store.loadEvents(root: root, since: try date("2026-05-24T00:02:00Z")).map(\.inputTokens),
            [50]
        )
        let restored = try store.loadEvents(root: root)

        XCTAssertEqual(restored.map(\.inputTokens), [100, 50])
        XCTAssertEqual(store.lastLoadMetrics.parsedFileCount, 1)
        XCTAssertGreaterThan(store.lastLoadMetrics.bytesRead, 0)
        XCTAssertEqual(store.lastLoadMetrics.retainedEventCount, 2)
    }

    func testPriorityServiceTierDoesNotEnableFastMode() throws {
        let root = try makeTemporaryDirectory()
        try writeConfig(#"service_tier = "priority""#, root: root)

        XCTAssertFalse(CodexLogStore().detectFastMode(root: root))
    }

    func testFastServiceTierRequiresFeatureFlag() throws {
        let root = try makeTemporaryDirectory()
        try writeConfig(#"service_tier = "fast""#, root: root)

        XCTAssertFalse(CodexLogStore().detectFastMode(root: root))
    }

    func testDetectsFastServiceTierWithFeatureFlag() throws {
        let root = try makeTemporaryDirectory()
        try writeConfig(
            """
            service_tier = "fast"

            [features]
            fast_mode = true
            """,
            root: root
        )

        XCTAssertTrue(CodexLogStore().detectFastMode(root: root))
    }

    func testFastModeFeatureFlagOutsideFeaturesSectionIsIgnored() throws {
        let root = try makeTemporaryDirectory()
        try writeConfig(
            """
            service_tier = "fast"
            fast_mode = true
            """,
            root: root
        )

        XCTAssertFalse(CodexLogStore().detectFastMode(root: root))
    }

    func testCommentedFastConfigurationDoesNotEnableFastMode() throws {
        let root = try makeTemporaryDirectory()
        try writeConfig(
            """
            # service_tier = "fast"
            [features]
            # fast_mode = true
            """,
            root: root
        )

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

    private func totalTokenCountLine(totalInputTokens: Int, minute: Int) -> String {
        #"{"timestamp":"2026-05-24T00:0\#(minute):00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(totalInputTokens),"total_tokens":\#(totalInputTokens)}}}}"#
    }

    private func date(_ string: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: string) else {
            throw CocoaError(.coderInvalidValue)
        }
        return date
    }
}
