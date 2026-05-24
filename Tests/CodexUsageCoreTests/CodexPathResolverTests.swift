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

    func testUserOverrideExpandsTildeUsingHomeDirectory() {
        let resolver = CodexPathResolver(
            environment: [:],
            homeDirectory: URL(fileURLWithPath: "/Users/example")
        )
        XCTAssertEqual(resolver.resolve(userOverride: "~/archive/codex").path, "/Users/example/archive/codex")
    }

    func testEmptyOverrideFallsThroughToCodexHomeEnvironment() {
        let resolver = CodexPathResolver(
            environment: ["CODEX_HOME": "/env/codex"],
            homeDirectory: URL(fileURLWithPath: "/Users/example")
        )
        XCTAssertEqual(resolver.resolve(userOverride: "").path, "/env/codex")
    }

    func testWhitespaceOnlyOverrideFallsThroughToCodexHomeEnvironment() {
        let resolver = CodexPathResolver(
            environment: ["CODEX_HOME": "/env/codex"],
            homeDirectory: URL(fileURLWithPath: "/Users/example")
        )
        XCTAssertEqual(resolver.resolve(userOverride: "   ").path, "/env/codex")
    }

    func testWhitespaceOnlyCodexHomeFallsThroughToDefault() {
        let resolver = CodexPathResolver(
            environment: ["CODEX_HOME": "   "],
            homeDirectory: URL(fileURLWithPath: "/Users/example")
        )
        XCTAssertEqual(resolver.resolve(userOverride: nil).path, "/Users/example/.codex")
    }

    func testRelativeOverrideResolvesUnderHomeDirectory() {
        let resolver = CodexPathResolver(
            environment: ["CODEX_HOME": "/env/codex"],
            homeDirectory: URL(fileURLWithPath: "/Users/example")
        )
        XCTAssertEqual(resolver.resolve(userOverride: "archive/codex").path, "/Users/example/archive/codex")
    }
}
