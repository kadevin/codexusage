import Foundation

public struct CodexLogStore: @unchecked Sendable {
    private let parser: CodexUsageParser
    private let fileManager: FileManager

    public init(
        parser: CodexUsageParser = CodexUsageParser(),
        fileManager: FileManager = .default
    ) {
        self.parser = parser
        self.fileManager = fileManager
    }

    public func loadEvents(root: URL) throws -> [CodexUsageEvent] {
        let files = try discoverJSONLFiles(root: root)
        return try files.flatMap { file in
            let modified = try? fileManager
                .attributesOfItem(atPath: file.path)[.modificationDate] as? Date

            return try parser.parseFile(
                file,
                sessionsRoot: root,
                fallbackModifiedDate: modified ?? Date()
            )
        }
    }

    public func discoverJSONLFiles(root: URL) throws -> [URL] {
        let sessionsRoot = root.appendingPathComponent("sessions", isDirectory: true)
        var isDirectory: ObjCBool = false
        let scanRoot = fileManager.fileExists(atPath: sessionsRoot.path, isDirectory: &isDirectory) && isDirectory.boolValue
            ? sessionsRoot
            : root

        guard let enumerator = fileManager.enumerator(
            at: scanRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true, file.pathExtension == "jsonl" else {
                continue
            }
            files.append(file)
        }

        return files.sorted { $0.path < $1.path }
    }

    public func detectFastMode(root: URL) -> Bool {
        let config = root.appendingPathComponent("config.toml")
        guard let contents = try? String(contentsOf: config, encoding: .utf8) else {
            return false
        }

        return contents.contains(#"service_tier = "priority""#)
            || contents.contains(#"service_tier = "fast""#)
    }
}
