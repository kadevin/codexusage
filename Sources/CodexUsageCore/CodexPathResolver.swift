import Foundation

public struct CodexPathResolver: Sendable {
    private let environment: [String: String]
    private let homeDirectory: URL

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
    }

    public func resolve(userOverride: String?) -> URL {
        if let userOverride = nonEmptyPath(userOverride) {
            return resolvedPath(userOverride)
        }
        if let codexHome = nonEmptyPath(environment["CODEX_HOME"]) {
            return resolvedPath(codexHome)
        }
        return homeDirectory.appendingPathComponent(".codex", isDirectory: true).standardizedFileURL
    }

    private func nonEmptyPath(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func resolvedPath(_ path: String) -> URL {
        if path == "~" {
            return homeDirectory.standardizedFileURL
        }
        if path.hasPrefix("~/") {
            let relativePath = String(path.dropFirst(2))
            return homeDirectory.appendingPathComponent(relativePath).standardizedFileURL
        }
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return homeDirectory.appendingPathComponent(path).standardizedFileURL
    }
}
