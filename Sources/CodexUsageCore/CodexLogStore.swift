import Foundation

public final class CodexLogStore: @unchecked Sendable {
    private let parser: CodexUsageParser
    private let loadLock = NSLock()
    private var cache: [String: CachedFile] = [:]
    private var cachedSessionsRoot: String?
    private var metrics = CodexLogStoreLoadMetrics.zero

    public init(parser: CodexUsageParser = CodexUsageParser()) {
        self.parser = parser
    }

    var lastLoadMetrics: CodexLogStoreLoadMetrics {
        loadLock.lock()
        defer { loadLock.unlock() }
        return metrics
    }

    public func loadEvents(root: URL, since: Date? = nil) throws -> [CodexUsageEvent] {
        loadLock.lock()
        defer { loadLock.unlock() }

        let files = try discoverJSONLFiles(root: root, since: since)
        let sessionsRoot = sessionsDirectoryRoot(for: root).resolvingSymlinksInPath()
        if cachedSessionsRoot != sessionsRoot.path {
            cache.removeAll(keepingCapacity: false)
            cachedSessionsRoot = sessionsRoot.path
        }

        let descriptors = try files.enumerated().map { index, file in
            try FileDescriptor(index: index, url: file.resolvingSymlinksInPath())
        }
        var eventsByFile = Array(repeating: [CodexUsageEvent](), count: descriptors.count)
        var workItems: [FileLoadWork] = []
        var reusedFileCount = 0

        for descriptor in descriptors {
            try Task.checkCancellation()
            let key = descriptor.url.path
            let cachedForWindow = cache[key].flatMap { cached in
                cached.canServe(since: since) ? cached.retainingEvents(since: since) : nil
            }
            if let cachedForWindow, cachedForWindow.isUnchanged(from: descriptor) {
                eventsByFile[descriptor.index] = cachedForWindow.events
                cache[key] = cachedForWindow
                reusedFileCount += 1
                continue
            }

            let canAppend = cachedForWindow.map { $0.canAppend(from: descriptor) } ?? false
            workItems.append(FileLoadWork(
                descriptor: descriptor,
                cached: canAppend ? cachedForWindow : nil
            ))
        }

        let scheduledWorkItems = workItems
        let results = ParallelLoadResults(count: scheduledWorkItems.count)
        let chunks = chunkWorkIndexesBySize(scheduledWorkItems, workerCount: min(2, scheduledWorkItems.count))

        DispatchQueue.concurrentPerform(iterations: chunks.count) { chunkIndex in
            for workIndex in chunks[chunkIndex] {
                if results.shouldStop {
                    return
                }

                do {
                    try Task.checkCancellation()
                    let result = try loadEvents(
                        work: scheduledWorkItems[workIndex],
                        sessionsRoot: sessionsRoot,
                        since: since
                    )
                    results.set(result: result, at: workIndex)
                } catch {
                    results.set(error: error)
                    return
                }
            }
        }

        var bytesRead: UInt64 = 0
        for result in try results.resolved() {
            eventsByFile[result.fileIndex] = result.cached.events
            cache[result.path] = result.cached
            bytesRead = bytesRead.saturatingAdd(result.bytesRead)
        }

        let activePaths = Set(descriptors.map { $0.url.path })
        cache = cache.filter { activePaths.contains($0.key) }
        let retainedEvents = eventsByFile.flatMap { $0 }
        metrics = CodexLogStoreLoadMetrics(
            parsedFileCount: scheduledWorkItems.count,
            reusedFileCount: reusedFileCount,
            bytesRead: bytesRead,
            retainedEventCount: retainedEvents.count
        )
        return retainedEvents
    }

    private func loadEvents(work: FileLoadWork, sessionsRoot: URL, since: Date?) throws -> FileLoadResult {
        let descriptor = work.descriptor
        let offset = work.cached?.offset ?? 0
        let parseResult = try parser.parseFileIncrementally(
            descriptor.url,
            sessionsRoot: sessionsRoot,
            fallbackModifiedDate: descriptor.modified,
            fromOffset: offset,
            state: work.cached?.parserState,
            eventCutoff: since
        )

        let events = work.cached.map { $0.events + parseResult.events } ?? parseResult.events

        let refreshedDescriptor = try? FileDescriptor(index: descriptor.index, url: descriptor.url)
        let finalDescriptor = refreshedDescriptor?.identity == descriptor.identity
            ? refreshedDescriptor ?? descriptor
            : descriptor
        let cached = CachedFile(
            identity: finalDescriptor.identity,
            modified: finalDescriptor.modified,
            offset: parseResult.endOffset,
            parserState: parseResult.state,
            events: events,
            retainedSince: since
        )
        return FileLoadResult(
            fileIndex: descriptor.index,
            path: descriptor.url.path,
            cached: cached,
            bytesRead: parseResult.bytesRead
        )
    }

    public func discoverJSONLFiles(root: URL, since: Date? = nil) throws -> [URL] {
        try validateReadableDirectory(root)
        var files: [URL] = []

        for scanRoot in sessionDataRoots(for: root) {
            try validateReadableDirectory(scanRoot)
            guard let enumerator = FileManager.default.enumerator(
                at: scanRoot,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

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
        }

        return files.sorted { $0.path < $1.path }
    }

    public func detectFastMode(root: URL) -> Bool {
        let config = root.appendingPathComponent("config.toml")
        guard let contents = try? String(contentsOf: config, encoding: .utf8) else {
            return false
        }

        var section = ""
        var hasFastServiceTier = false
        var hasFastModeFeature = false

        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let uncommented = rawLine
                .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                .first
                .map(String.init) ?? ""
            let line = uncommented.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("["), line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            let parts = line.split(separator: "=", maxSplits: 1).map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard parts.count == 2 else { continue }

            let value = parts[1]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: #""'"#))

            if section.isEmpty, parts[0] == "service_tier" {
                hasFastServiceTier = value == "fast"
            } else if section == "features", parts[0] == "fast_mode" {
                hasFastModeFeature = value == "true"
            }
        }

        return hasFastServiceTier && hasFastModeFeature
    }

    private func sessionsDirectoryRoot(for root: URL) -> URL {
        let sessionsRoot = root.appendingPathComponent("sessions", isDirectory: true)
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: sessionsRoot.path, isDirectory: &isDirectory) && isDirectory.boolValue
            ? sessionsRoot
            : root
    }

    private func sessionDataRoots(for root: URL) -> [URL] {
        let sessionsRoot = sessionsDirectoryRoot(for: root)
        guard sessionsRoot.path != root.path else {
            return [root]
        }

        var roots = [sessionsRoot]
        let archivedRoot = root.appendingPathComponent("archived_sessions", isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: archivedRoot.path, isDirectory: &isDirectory), isDirectory.boolValue {
            roots.append(archivedRoot)
        }
        return roots
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

    private func chunkWorkIndexesBySize(_ workItems: [FileLoadWork], workerCount: Int) -> [[Int]] {
        guard workerCount > 0 else {
            return []
        }
        var weightedIndexes = workItems.indices.map { index in
            (index: index, size: workItems[index].estimatedBytesToRead)
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

struct CodexLogStoreLoadMetrics: Equatable {
    let parsedFileCount: Int
    let reusedFileCount: Int
    let bytesRead: UInt64
    let retainedEventCount: Int

    static let zero = CodexLogStoreLoadMetrics(
        parsedFileCount: 0,
        reusedFileCount: 0,
        bytesRead: 0,
        retainedEventCount: 0
    )
}

private struct FileIdentity: Equatable {
    let systemNumber: UInt64
    let fileNumber: UInt64
}

private struct FileDescriptor {
    let index: Int
    let url: URL
    let identity: FileIdentity
    let size: UInt64
    let modified: Date

    init(index: Int, url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        self.index = index
        self.url = url
        self.identity = FileIdentity(
            systemNumber: (attributes[.systemNumber] as? NSNumber)?.uint64Value ?? 0,
            fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        )
        self.size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        self.modified = attributes[.modificationDate] as? Date ?? Date()
    }
}

private struct CachedFile {
    let identity: FileIdentity
    let modified: Date
    let offset: UInt64
    let parserState: CodexUsageParserState
    let events: [CodexUsageEvent]
    let retainedSince: Date?

    func isUnchanged(from descriptor: FileDescriptor) -> Bool {
        identity == descriptor.identity && offset == descriptor.size && modified == descriptor.modified
    }

    func canAppend(from descriptor: FileDescriptor) -> Bool {
        identity == descriptor.identity
            && descriptor.size > offset
            && parserState.canResumeFromEOF
    }

    func canServe(since requestedSince: Date?) -> Bool {
        guard let retainedSince else {
            return true
        }
        guard let requestedSince else {
            return false
        }
        return requestedSince >= retainedSince
    }

    func retainingEvents(since requestedSince: Date?) -> CachedFile {
        guard let requestedSince else {
            return self
        }
        let effectiveSince = max(retainedSince ?? requestedSince, requestedSince)
        return CachedFile(
            identity: identity,
            modified: modified,
            offset: offset,
            parserState: parserState,
            events: events.filter { $0.timestamp >= effectiveSince },
            retainedSince: effectiveSince
        )
    }
}

private struct FileLoadWork {
    let descriptor: FileDescriptor
    let cached: CachedFile?

    var estimatedBytesToRead: UInt64 {
        descriptor.size - min(cached?.offset ?? 0, descriptor.size)
    }
}

private struct FileLoadResult {
    let fileIndex: Int
    let path: String
    let cached: CachedFile
    let bytesRead: UInt64
}

private extension UInt64 {
    func saturatingAdd(_ other: UInt64) -> UInt64 {
        let (result, overflow) = addingReportingOverflow(other)
        return overflow ? UInt64.max : result
    }
}

private final class ParallelLoadResults: @unchecked Sendable {
    private let lock = NSLock()
    private var loadedFiles: [FileLoadResult?]
    private var firstError: Error?

    init(count: Int) {
        self.loadedFiles = Array(repeating: nil, count: count)
    }

    var shouldStop: Bool {
        lock.lock()
        defer { lock.unlock() }
        return firstError != nil
    }

    func set(result: FileLoadResult, at index: Int) {
        lock.lock()
        loadedFiles[index] = result
        lock.unlock()
    }

    func set(error: Error) {
        lock.lock()
        if firstError == nil {
            firstError = error
        }
        lock.unlock()
    }

    func resolved() throws -> [FileLoadResult] {
        lock.lock()
        defer { lock.unlock() }
        if let firstError {
            throw firstError
        }
        return loadedFiles.compactMap { $0 }
    }
}
