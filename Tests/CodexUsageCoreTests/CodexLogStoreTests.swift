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

    func testDetectsPriorityServiceTier() throws {
        let root = try makeTemporaryDirectory()
        let config = root.appendingPathComponent("config.toml")
        try #"service_tier = "priority""#.write(to: config, atomically: true, encoding: .utf8)

        XCTAssertTrue(CodexLogStore().detectFastMode(root: root))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.resolvingSymlinksInPath()
    }
}
