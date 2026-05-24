import Foundation

public struct CodexUsageParser: Sendable {
    public init() {}

    public func parseFile(
        _ fileURL: URL,
        sessionsRoot: URL,
        fallbackModifiedDate: Date
    ) throws -> [CodexUsageEvent] {
        let sessionId = Self.sessionId(for: fileURL, sessionsRoot: sessionsRoot)
        var events: [CodexUsageEvent] = []
        var currentModel: String?
        var previousTotalUsage: RawUsage?
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }
        var buffer = Data()

        while true {
            try Task.checkCancellation()
            let chunk = try handle.read(upToCount: 128 * 1024) ?? Data()
            if chunk.isEmpty {
                break
            }
            buffer.append(chunk)

            while let newline = buffer.firstRange(of: Self.newlineData) {
                let line = buffer.subdata(in: buffer.startIndex..<newline.lowerBound)
                Self.parseLine(
                    line,
                    sessionId: sessionId,
                    fileURL: fileURL,
                    fallbackModifiedDate: fallbackModifiedDate,
                    events: &events,
                    currentModel: &currentModel,
                    previousTotalUsage: &previousTotalUsage
                )
                buffer.removeSubrange(buffer.startIndex..<newline.upperBound)
            }
        }

        if !buffer.isEmpty {
            Self.parseLine(
                buffer,
                sessionId: sessionId,
                fileURL: fileURL,
                fallbackModifiedDate: fallbackModifiedDate,
                events: &events,
                currentModel: &currentModel,
                previousTotalUsage: &previousTotalUsage
            )
        }

        return events
    }

    private static func parseLine(
        _ lineData: Data,
        sessionId: String,
        fileURL: URL,
        fallbackModifiedDate: Date,
        events: inout [CodexUsageEvent],
        currentModel: inout String?,
        previousTotalUsage: inout RawUsage?
    ) {
        guard
            lineMightContainUsage(lineData),
            let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
        else {
            return
        }

        if object["type"] as? String == "turn_context" {
            if let payload = object["payload"] as? [String: Any], payload.keys.contains("model") {
                currentModel = Self.normalizedModel(payload["model"])
            }
            return
        }

        guard
            object["type"] as? String == "event_msg",
            let payload = object["payload"] as? [String: Any],
            payload["type"] as? String == "token_count"
        else {
            return
        }

        let timestamp = Self.parseTimestamp(object["timestamp"]) ?? fallbackModifiedDate
        let info = payload["info"] as? [String: Any]
        let lastUsage = (info?["last_token_usage"] as? [String: Any]).flatMap(RawUsage.init)
        let totalUsage = (info?["total_token_usage"] as? [String: Any]).flatMap(RawUsage.init)
        let usage = lastUsage ?? totalUsage.map { $0.subtracting(previousTotalUsage) }

        if let totalUsage {
            previousTotalUsage = totalUsage
        }

        guard let usage, usage.hasTokens else {
            return
        }

        let payloadModel = Self.normalizedModel(payload["model"])
        let infoModel = Self.normalizedModel(info?["model"])
        let model = payloadModel ?? infoModel ?? currentModel ?? "gpt-5"
        let isFallbackModel = payloadModel == nil && infoModel == nil && currentModel == nil

        events.append(CodexUsageEvent(
            sessionId: sessionId,
            timestamp: timestamp,
            model: model,
            inputTokens: usage.inputTokens,
            cachedInputTokens: usage.cachedInputTokens,
            outputTokens: usage.outputTokens,
            reasoningTokens: usage.reasoningTokens,
            totalTokens: usage.totalTokens,
            sourceFile: fileURL,
            isFallbackModel: isFallbackModel
        ))
    }

    private static func lineMightContainUsage(_ lineData: Data) -> Bool {
        relevantMarkers.contains { marker in
            lineData.range(of: marker) != nil
        }
    }

    private static func normalizedModel(_ value: Any?) -> String? {
        guard let string = value as? String else {
            return nil
        }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func sessionId(for fileURL: URL, sessionsRoot: URL) -> String {
        let rootPath = sessionsRoot.standardizedFileURL.path
        let filePath = fileURL.deletingPathExtension().standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else {
            return fileURL.deletingPathExtension().lastPathComponent
        }

        let relativePath = filePath.dropFirst(rootPath.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relativePath.isEmpty ? fileURL.deletingPathExtension().lastPathComponent : relativePath
    }

    private static func parseTimestamp(_ value: Any?) -> Date? {
        if let string = value as? String {
            if let date = iso8601Date(from: string, fractionalSeconds: true) {
                return date
            }
            return iso8601Date(from: string, fractionalSeconds: false)
        }

        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue / 1000)
        }

        return nil
    }

    private static func iso8601Date(from string: String, fractionalSeconds: Bool) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private static let newlineData = Data([0x0A])
    private static let relevantMarkers = [
        Data(#""turn_context""#.utf8),
        Data(#""token_count""#.utf8),
        Data(#""usage""#.utf8),
        Data(#""input_tokens""#.utf8),
        Data(#""prompt_tokens""#.utf8)
    ]
}

private struct RawUsage: Equatable {
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let reasoningTokens: Int
    let totalTokens: Int

    init?(_ dictionary: [String: Any]) {
        let input = Self.int(dictionary["input_tokens"])
            ?? Self.int(dictionary["prompt_tokens"])
            ?? Self.int(dictionary["input"])
            ?? 0
        let cached = Self.int(dictionary["cached_input_tokens"])
            ?? Self.int(dictionary["cache_read_input_tokens"])
            ?? Self.int(dictionary["cached_tokens"])
            ?? 0
        let output = Self.int(dictionary["output_tokens"])
            ?? Self.int(dictionary["completion_tokens"])
            ?? Self.int(dictionary["output"])
            ?? 0
        let reasoning = Self.int(dictionary["reasoning_output_tokens"])
            ?? Self.int(dictionary["reasoning_tokens"])
            ?? 0
        let total = Self.int(dictionary["total_tokens"]) ?? input + output + reasoning

        self.init(
            inputTokens: input,
            cachedInputTokens: cached,
            outputTokens: output,
            reasoningTokens: reasoning,
            totalTokens: total
        )
    }

    var hasTokens: Bool {
        inputTokens + cachedInputTokens + outputTokens + reasoningTokens + totalTokens > 0
    }

    func subtracting(_ previous: RawUsage?) -> RawUsage {
        guard let previous else {
            return self
        }

        return RawUsage(
            inputTokens: max(inputTokens - previous.inputTokens, 0),
            cachedInputTokens: max(cachedInputTokens - previous.cachedInputTokens, 0),
            outputTokens: max(outputTokens - previous.outputTokens, 0),
            reasoningTokens: max(reasoningTokens - previous.reasoningTokens, 0),
            totalTokens: max(totalTokens - previous.totalTokens, 0)
        )
    }

    private init(
        inputTokens: Int,
        cachedInputTokens: Int,
        outputTokens: Int,
        reasoningTokens: Int,
        totalTokens: Int
    ) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = min(cachedInputTokens, inputTokens)
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
        self.totalTokens = totalTokens
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? NSNumber {
            guard CFGetTypeID(value) != CFBooleanGetTypeID() else {
                return nil
            }

            let decimal = value.decimalValue
            guard decimal >= 0, decimal <= Decimal(Int.max) else {
                return nil
            }

            var source = decimal
            var rounded = Decimal()
            NSDecimalRound(&rounded, &source, 0, .plain)
            guard rounded == decimal else {
                return nil
            }

            return value.intValue
        }

        if let value = value as? Int {
            return value >= 0 ? value : nil
        }

        if let value = value as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let parsed = Int(trimmed), parsed >= 0 else {
                return nil
            }
            return parsed
        }

        return nil
    }
}
