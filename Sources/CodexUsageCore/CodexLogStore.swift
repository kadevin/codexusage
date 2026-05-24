import Foundation

public struct CodexLogStore: Sendable {
    private let parser: CodexUsageParser

    public init(parser: CodexUsageParser = CodexUsageParser()) {
        self.parser = parser
    }

    public func loadEvents(root: URL, since: Date? = nil) throws -> [CodexUsageEvent] {
        let files = try discoverJSONLFiles(root: root, since: since)
        let sessionsRoot = sessionsDirectoryRoot(for: root).resolvingSymlinksInPath()

        var events: [CodexUsageEvent] = []
        for file in files {
            try Task.checkCancellation()
            let resolvedFile = file.resolvingSymlinksInPath()
            let modified = try? FileManager.default
                .attributesOfItem(atPath: file.path)[.modificationDate] as? Date

            events.append(contentsOf: try parser.parseFile(
                resolvedFile,
                sessionsRoot: sessionsRoot,
                fallbackModifiedDate: modified ?? Date()
            ))
        }

        return events
    }

    public func discoverJSONLFiles(root: URL, since: Date? = nil) throws -> [URL] {
        try validateReadableDirectory(root)
        let scanRoot = sessionsDirectoryRoot(for: root)
        try validateReadableDirectory(scanRoot)

        guard let enumerator = FileManager.default.enumerator(
            at: scanRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let file as URL in enumerator {
            try Task.checkCancellation()
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values.isRegularFile == true, file.pathExtension == "jsonl" else {
                continue
            }
            if let since, !shouldInclude(file: file, modified: values.contentModificationDate, since: since) {
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

        return contents.split(separator: "\n").contains { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.hasPrefix("#") else {
                return false
            }

            let parts = line.split(separator: "=", maxSplits: 1).map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard parts.count == 2, parts[0] == "service_tier" else {
                return false
            }

            return parts[1] == #""priority""# || parts[1] == #""fast""#
        }
    }

    private func sessionsDirectoryRoot(for root: URL) -> URL {
        let sessionsRoot = root.appendingPathComponent("sessions", isDirectory: true)
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: sessionsRoot.path, isDirectory: &isDirectory) && isDirectory.boolValue
            ? sessionsRoot
            : root
    }

    private func shouldInclude(file: URL, modified: Date?, since: Date) -> Bool {
        if let modified, modified >= since {
            return true
        }

        guard let sessionDay = sessionDayFromPath(file.path) else {
            return false
        }

        return sessionDay >= Calendar.current.startOfDay(for: since)
    }

    private func sessionDayFromPath(_ path: String) -> Date? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 3 else {
            return nil
        }

        for index in 0...(parts.count - 3) {
            guard
                parts[index].count == 4,
                parts[index + 1].count == 2,
                parts[index + 2].count == 2,
                let year = Int(parts[index]),
                let month = Int(parts[index + 1]),
                let day = Int(parts[index + 2])
            else {
                continue
            }

            var components = DateComponents()
            components.calendar = Calendar(identifier: .gregorian)
            components.timeZone = .current
            components.year = year
            components.month = month
            components.day = day
            return components.date
        }

        return nil
    }

    private func validateReadableDirectory(_ root: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        guard FileManager.default.isReadableFile(atPath: root.path) else {
            throw CocoaError(.fileReadNoPermission)
        }
    }
}
