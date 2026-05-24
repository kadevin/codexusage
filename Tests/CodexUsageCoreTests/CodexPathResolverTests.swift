import CodexUsageCore
import XCTest

final class CodexPathResolverTests: XCTestCase {
    func testUserOverrideWins() {
        let resolver = CodexPathResolver(
            environment: ["CODEX_HOME": "/env/codex"],
            homeDirectory: URL(fileURLWithPath: "/Users/example")
        )
        XCTAssertEqual(
            resolver.resolve(userOverride: "/custom/codex").path,
            "/custom/codex"
        )
    }

    func testCodexHomeEnvironmentWinsWhenNoOverride() {
        let resolver = CodexPathResolver(
            environment: ["CODEX_HOME": "/env/codex"],
            homeDirectory: URL(fileURLWithPath: "/Users/example")
        )
        XCTAssertEqual(resolver.resolve(userOverride: nil).path, "/env/codex")
    }

    func testDefaultFallsBackToDotCodex() {
        let resolver = CodexPathResolver(
            environment: [:],
            homeDirectory: URL(fileURLWithPath: "/Users/example")
        )
        XCTAssertEqual(resolver.resolve(userOverride: nil).path, "/Users/example/.codex")
    }
}
