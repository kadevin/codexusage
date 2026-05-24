import Foundation

public struct CodexUsageParser: Sendable {
    public init() {}

    public func parseFile(
        _ fileURL: URL,
        sessionsRoot: URL,
        fallbackModifiedDate: Date
    ) throws -> [CodexUsageEvent] {
        let data = try Data(contentsOf: fileURL)
        let text = String(decoding: data, as: UTF8.self)
        let sessionId = Self.sessionId(for: fileURL, sessionsRoot: sessionsRoot)
        var events: [CodexUsageEvent] = []
        var currentModel: String?
        var previousTotalUsage: RawUsage?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard
                let lineData = String(rawLine).data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else {
                continue
            }

            if object["type"] as? String == "turn_context" {
                if
                    let payload = object["payload"] as? [String: Any],
                    let model = payload["model"] as? String,
                    !model.isEmpty
                {
                    currentModel = model
                }
                continue
            }

            guard
                object["type"] as? String == "event_msg",
                let payload = object["payload"] as? [String: Any],
                payload["type"] as? String == "token_count"
            else {
                continue
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
                continue
            }

            let payloadModel = payload["model"] as? String
            let infoModel = info?["model"] as? String
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

        return events
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
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        if let value = value as? String {
            return Int(value)
        }
        return nil
    }
}
