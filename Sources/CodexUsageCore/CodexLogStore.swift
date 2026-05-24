import Foundation

public struct CodexLogStore: Sendable {
    private let parser: CodexUsageParser

    public init(parser: CodexUsageParser = CodexUsageParser()) {
        self.parser = parser
    }

    public func loadEvents(root: URL, since: Date? = nil) throws -> [CodexUsageEvent] {
        let files = try discoverJSONLFiles(root: root, since: since)
        let sessionsRoot = sessionsDirectoryRoot(for: root).resolvingSymlinksInPath()

        guard files.count > 1 else {
            return try files.flatMap { file in
                try Task.checkCancellation()
                return try loadEvents(file: file, sessionsRoot: sessionsRoot)
            }
        }

        let workerCount = min(max(ProcessInfo.processInfo.activeProcessorCount, 1), files.count)
        let chunks = chunkFileIndexesBySize(files, workerCount: workerCount)
        let results = ParallelLoadResults(count: files.count)

        DispatchQueue.concurrentPerform(iterations: chunks.count) { chunkIndex in
            for fileIndex in chunks[chunkIndex] {
                if results.shouldStop {
                    return
                }

                do {
                    try Task.checkCancellation()
                    let events = try loadEvents(file: files[fileIndex], sessionsRoot: sessionsRoot)
                    results.set(events: events, at: fileIndex)
                } catch {
                    results.set(error: error)
                    return
                }
            }
        }

        return try results.flattened()
    }

    private func loadEvents(file: URL, sessionsRoot: URL) throws -> [CodexUsageEvent] {
        let resolvedFile = file.resolvingSymlinksInPath()
        let modified = try? FileManager.default
            .attributesOfItem(atPath: file.path)[.modificationDate] as? Date

        return try parser.parseFile(
            resolvedFile,
            sessionsRoot: sessionsRoot,
            fallbackModifiedDate: modified ?? Date()
        )
    }

    private func loadEventsSequential(files: [URL], sessionsRoot: URL) throws -> [CodexUsageEvent] {
        var events: [CodexUsageEvent] = []
        for file in files {
            try Task.checkCancellation()
            events.append(contentsOf: try loadEvents(file: file, sessionsRoot: sessionsRoot))
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

            let value = parts[1].split(separator: "#", maxSplits: 1).first.map(String.init) ?? parts[1]
            let normalized = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: #""'"#))

            return normalized == "priority" || normalized == "fast"
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

    private func chunkFileIndexesBySize(_ files: [URL], workerCount: Int) -> [[Int]] {
        var weightedIndexes: [(index: Int, size: UInt64)] = []
        weightedIndexes.reserveCapacity(files.count)
        for (index, file) in files.enumerated() {
            let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?
                .uint64Value ?? 0
            weightedIndexes.append((index, size))
        }

        weightedIndexes.sort {
            if $0.size == $1.size {
                return $0.index < $1.index
            }
            return $0.size > $1.size
        }

        var chunks = Array(repeating: [Int](), count: workerCount)
        var chunkSizes = Array(repeating: UInt64.zero, count: workerCount)
        for weightedIndex in weightedIndexes {
            let target = chunkSizes.indices.min { chunkSizes[$0] < chunkSizes[$1] } ?? 0
            chunks[target].append(weightedIndex.index)
            chunkSizes[target] = chunkSizes[target].saturatingAdd(weightedIndex.size)
        }

        return chunks.filter { !$0.isEmpty }
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

private extension UInt64 {
    func saturatingAdd(_ other: UInt64) -> UInt64 {
        let (result, overflow) = addingReportingOverflow(other)
        return overflow ? UInt64.max : result
    }
}

private final class ParallelLoadResults: @unchecked Sendable {
    private let lock = NSLock()
    private var loadedFiles: [[CodexUsageEvent]]
    private var firstError: Error?

    init(count: Int) {
        self.loadedFiles = Array(repeating: [CodexUsageEvent](), count: count)
    }

    var shouldStop: Bool {
        lock.lock()
        defer { lock.unlock() }
        return firstError != nil
    }

    func set(events: [CodexUsageEvent], at index: Int) {
        lock.lock()
        loadedFiles[index] = events
        lock.unlock()
    }

    func set(error: Error) {
        lock.lock()
        if firstError == nil {
            firstError = error
        }
        lock.unlock()
    }

    func flattened() throws -> [CodexUsageEvent] {
        lock.lock()
        defer { lock.unlock() }
        if let firstError {
            throw firstError
        }
        return loadedFiles.flatMap { $0 }
    }
}
