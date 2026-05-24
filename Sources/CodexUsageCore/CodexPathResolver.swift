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
        if let userOverride, userOverride.isEmpty == false {
            return URL(fileURLWithPath: NSString(string: userOverride).expandingTildeInPath)
        }
        if let codexHome = environment["CODEX_HOME"], codexHome.isEmpty == false {
            return URL(fileURLWithPath: NSString(string: codexHome).expandingTildeInPath)
        }
        return homeDirectory.appendingPathComponent(".codex", isDirectory: true)
    }
}
