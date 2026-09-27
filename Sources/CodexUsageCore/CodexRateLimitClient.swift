import Foundation

public struct CodexExecutableResolver: Sendable {
    public init() {}

    public func resolve(
        explicitPath: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationsDirectory: URL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    ) -> URL? {
        var candidates: [URL] = []
        if let explicitPath, !explicitPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidates.append(URL(fileURLWithPath: NSString(string: explicitPath).expandingTildeInPath))
        }

        candidates.append(contentsOf: (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0), isDirectory: true).appendingPathComponent("codex") })

        candidates.append(contentsOf: [
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
            applicationsDirectory.appendingPathComponent("ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"),
            applicationsDirectory.appendingPathComponent("ChatGPT.app/Contents/Resources/codex"),
            applicationsDirectory.appendingPathComponent("Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"),
            applicationsDirectory.appendingPathComponent("Codex.app/Contents/Resources/codex"),
            homeDirectory.appendingPathComponent(".local/bin/codex"),
            homeDirectory.appendingPathComponent(".npm-global/bin/codex"),
            homeDirectory.appendingPathComponent(".volta/bin/codex"),
            homeDirectory.appendingPathComponent(".bun/bin/codex")
        ])

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

public actor CodexRateLimitClient {
    private let resolver: CodexExecutableResolver
    private let decoder: CodexRateLimitResponseDecoder
    private var cachedSnapshot: OfficialUsageSnapshot?
    private var cachedConfiguration: Configuration?

    public init(
        resolver: CodexExecutableResolver = CodexExecutableResolver(),
        decoder: CodexRateLimitResponseDecoder = CodexRateLimitResponseDecoder()
    ) {
        self.resolver = resolver
        self.decoder = decoder
    }

    public func fetch(
        codexExecutablePath: String?,
        codexHome: URL?,
        maximumAge: TimeInterval = 300,
        force: Bool = false,
        now: Date = Date()
    ) throws -> OfficialUsageSnapshot {
        guard let executable = resolver.resolve(explicitPath: codexExecutablePath) else {
            throw CodexRateLimitError.executableNotFound
        }
        let configuration = Configuration(
            executablePath: executable.standardizedFileURL.path,
            codexHomePath: codexHome?.standardizedFileURL.path
        )
        if
            !force,
            cachedConfiguration == configuration,
            let cachedSnapshot,
            now.timeIntervalSince(cachedSnapshot.fetchedAt) < maximumAge
        {
            return cachedSnapshot
        }

        let output = try Self.runAppServer(
            executable: executable,
            codexHome: codexHome
        )
        let snapshot = try decoder.decode(appServerOutput: output, fetchedAt: now)
        cachedSnapshot = snapshot
        cachedConfiguration = configuration
        return snapshot
    }

    private static func runAppServer(executable: URL, codexHome: URL?) throws -> Data {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        let collector = AppServerOutputCollector()
        let errorCollector = ProcessOutputBuffer()

        process.executableURL = executable
        process.arguments = ["app-server"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        if let codexHome {
            var environment = ProcessInfo.processInfo.environment
            environment["CODEX_HOME"] = codexHome.path
            process.environment = environment
        }
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                collector.markProcessEnded()
            } else {
                collector.append(data)
            }
        }
        error.fileHandleForReading.readabilityHandler = { handle in
            errorCollector.append(handle.availableData)
        }
        process.terminationHandler = { _ in collector.markProcessEnded() }

        try process.run()
        defer {
            try? input.fileHandleForWriting.close()
        }
        let requests = """
        {"id":1,"method":"initialize","params":{"clientInfo":{"name":"codexusage","title":"CodexUsage","version":"0.1"},"capabilities":{"experimentalApi":true}}}
        {"method":"initialized"}
        {"id":2,"method":"account/rateLimits/read","params":null}

        """
        try input.fileHandleForWriting.write(contentsOf: Data(requests.utf8))

        guard collector.wait(timeout: .now() + 8) else {
            process.terminate()
            output.fileHandleForReading.readabilityHandler = nil
            error.fileHandleForReading.readabilityHandler = nil
            throw CodexRateLimitError.timedOut
        }

        output.fileHandleForReading.readabilityHandler = nil
        error.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        if collector.receivedResponse {
            return collector.collectedData
        }
        collector.append(output.fileHandleForReading.readDataToEndOfFile())
        errorCollector.append(error.fileHandleForReading.readDataToEndOfFile())

        let data = collector.collectedData
        if collector.receivedResponse {
            return data
        }
        guard process.terminationStatus == 0 else {
            let message = String(data: errorCollector.collectedData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw CodexRateLimitError.serverFailed(process.terminationStatus, message)
        }
        throw CodexRateLimitError.responseMissing(
            String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }
}

private struct Configuration: Equatable {
    let executablePath: String
    let codexHomePath: String?
}

private final class AppServerOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let completion = DispatchSemaphore(value: 0)
    private var data = Data()
    private var hasResponse = false
    private var hasCompleted = false

    var collectedData: Data {
        lock.withLock { data }
    }

    var receivedResponse: Bool {
        lock.withLock { hasResponse }
    }

    func append(_ chunk: Data) {
        let shouldSignal = lock.withLock {
            data.append(chunk)
            guard !hasResponse, Self.containsRateLimitResponse(data) else {
                return false
            }
            hasResponse = true
            guard !hasCompleted else {
                return false
            }
            hasCompleted = true
            return true
        }
        if shouldSignal {
            completion.signal()
        }
    }

    func markProcessEnded() {
        let shouldSignal = lock.withLock {
            guard !hasCompleted else {
                return false
            }
            hasCompleted = true
            return true
        }
        if shouldSignal {
            completion.signal()
        }
    }

    func wait(timeout: DispatchTime) -> Bool {
        completion.wait(timeout: timeout) == .success
    }

    private static func containsRateLimitResponse(_ data: Data) -> Bool {
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard
                let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                (object["id"] as? NSNumber)?.intValue == 2
            else {
                continue
            }
            return true
        }
        return false
    }
}

private final class ProcessOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    var collectedData: Data {
        lock.withLock { data }
    }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else {
            return
        }
        lock.withLock {
            data.append(chunk)
        }
    }
}
