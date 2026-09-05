import Darwin
import Foundation

public struct CodexUsageParser: Sendable {
    public init() {}

    public func parseFile(
        _ fileURL: URL,
        sessionsRoot: URL,
        fallbackModifiedDate: Date
    ) throws -> [CodexUsageEvent] {
        try parseFileIncrementally(
            fileURL,
            sessionsRoot: sessionsRoot,
            fallbackModifiedDate: fallbackModifiedDate,
            fromOffset: 0,
            state: nil,
            eventCutoff: nil
        ).events
    }

    func parseFileIncrementally(
        _ fileURL: URL,
        sessionsRoot: URL,
        fallbackModifiedDate: Date,
        fromOffset: UInt64,
        state initialState: CodexUsageParserState?,
        eventCutoff: Date?
    ) throws -> CodexUsageParseResult {
        let fallbackSessionId = Self.sessionId(for: fileURL, sessionsRoot: sessionsRoot)
        var events: [CodexUsageEvent] = []
        var state = initialState ?? CodexUsageParserState()
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }
        try handle.seek(toOffset: fromOffset)

        var chunkBuffer = Data(count: Self.chunkByteCount)
        var pendingLine = Data()
        var pendingLineIsRelevant: Bool?
        var discardingLine = false
        var bytesRead: UInt64 = 0

        while true {
            try Task.checkCancellation()
            let count = try Self.readChunk(into: &chunkBuffer, fileDescriptor: handle.fileDescriptor)
            if count == 0 {
                break
            }
            bytesRead += UInt64(count)

            try Self.parseChunk(
                chunkBuffer,
                validRange: chunkBuffer.startIndex..<(chunkBuffer.startIndex + count),
                pendingLine: &pendingLine,
                pendingLineIsRelevant: &pendingLineIsRelevant,
                discardingLine: &discardingLine,
                fallbackSessionId: fallbackSessionId,
                fileURL: fileURL,
                fallbackModifiedDate: fallbackModifiedDate,
                eventCutoff: eventCutoff,
                events: &events,
                state: &state
            )
        }

        let canResumeFromEOF = pendingLine.isEmpty && !discardingLine
        if !pendingLine.isEmpty {
            Self.parseLine(
                pendingLine,
                fallbackSessionId: fallbackSessionId,
                fileURL: fileURL,
                fallbackModifiedDate: fallbackModifiedDate,
                eventCutoff: eventCutoff,
                events: &events,
                state: &state
            )
        }

        state.canResumeFromEOF = canResumeFromEOF
        return CodexUsageParseResult(
            events: events,
            state: state,
            endOffset: fromOffset + bytesRead,
            bytesRead: bytesRead
        )
    }

    private static func parseChunk(
        _ chunk: Data,
        validRange: Range<Data.Index>,
        pendingLine: inout Data,
        pendingLineIsRelevant: inout Bool?,
        discardingLine: inout Bool,
        fallbackSessionId: String,
        fileURL: URL,
        fallbackModifiedDate: Date,
        eventCutoff: Date?,
        events: inout [CodexUsageEvent],
        state: inout CodexUsageParserState
    ) throws {
        var lineStart = validRange.lowerBound

        while lineStart < validRange.upperBound {
            try Task.checkCancellation()
            if discardingLine {
                guard let newlineIndex = Self.newlineIndex(
                    in: chunk,
                    range: lineStart..<validRange.upperBound
                ) else {
                    return
                }
                discardingLine = false
                lineStart = chunk.index(after: newlineIndex)
                continue
            }

            guard let newlineIndex = Self.newlineIndex(
                in: chunk,
                range: lineStart..<validRange.upperBound
            ) else {
                let remainder = lineStart..<validRange.upperBound
                if pendingLineIsRelevant == true {
                    pendingLine.append(contentsOf: chunk[remainder])
                    return
                }

                let bytesNeeded = max(Self.markerProbeByteCount - pendingLine.count, 0)
                let probeEnd = min(remainder.upperBound, remainder.lowerBound + bytesNeeded)
                pendingLine.append(contentsOf: chunk[remainder.lowerBound..<probeEnd])
                guard pendingLine.count >= Self.markerProbeByteCount else {
                    return
                }

                if Self.lineMightContainUsage(pendingLine) {
                    pendingLineIsRelevant = true
                    pendingLine.append(contentsOf: chunk[probeEnd..<remainder.upperBound])
                } else {
                    pendingLine.removeAll(keepingCapacity: false)
                    pendingLineIsRelevant = nil
                    discardingLine = true
                }
                return
            }

            if pendingLine.isEmpty {
                let lineRange = lineStart..<newlineIndex
                if Self.rangeMightContainUsage(chunk, range: lineRange) {
                    Self.parseLine(
                        chunk.subdata(in: lineRange),
                        fallbackSessionId: fallbackSessionId,
                        fileURL: fileURL,
                        fallbackModifiedDate: fallbackModifiedDate,
                        eventCutoff: eventCutoff,
                        events: &events,
                        state: &state
                    )
                }
            } else {
                pendingLine.append(contentsOf: chunk[lineStart..<newlineIndex])
                Self.parseLine(
                    pendingLine,
                    fallbackSessionId: fallbackSessionId,
                    fileURL: fileURL,
                    fallbackModifiedDate: fallbackModifiedDate,
                    eventCutoff: eventCutoff,
                    events: &events,
                    state: &state
                )
                pendingLine.removeAll(keepingCapacity: false)
                pendingLineIsRelevant = nil
            }

            lineStart = chunk.index(after: newlineIndex)
        }
    }

    private static func readChunk(into data: inout Data, fileDescriptor: Int32) throws -> Int {
        var result: Int
        repeat {
            result = data.withUnsafeMutableBytes { buffer in
                Darwin.read(fileDescriptor, buffer.baseAddress, buffer.count)
            }
        } while result < 0 && errno == EINTR

        guard result >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return result
    }

    private static func parseLine(
        _ lineData: Data,
        fallbackSessionId: String,
        fileURL: URL,
        fallbackModifiedDate: Date,
        eventCutoff: Date?,
        events: inout [CodexUsageEvent],
        state: inout CodexUsageParserState
    ) {
        guard lineMightContainUsage(lineData) else {
            return
        }

        autoreleasepool {
            guard let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                return
            }

            if object["type"] as? String == "session_meta" {
                guard let payload = object["payload"] as? [String: Any] else {
                    return
                }
                state.currentSessionId = Self.normalizedModel(payload["id"]) ?? state.currentSessionId
                state.sessionStartedAt = Self.parseTimestamp(object["timestamp"]) ?? state.sessionStartedAt
                state.parentSessionId = Self.parentSessionId(from: payload)
                return
            }

            if object["type"] as? String == "turn_context" {
                if let payload = object["payload"] as? [String: Any], payload.keys.contains("model") {
                    state.currentModel = Self.normalizedModel(payload["model"])
                }
                return
            }

            if
                object["type"] as? String == "event_msg",
                let payload = object["payload"] as? [String: Any],
                payload["type"] as? String == "thread_settings_applied",
                let settings = payload["thread_settings"] as? [String: Any]
            {
                if settings.keys.contains("model") {
                    state.currentModel = Self.normalizedModel(settings["model"])
                }
                if settings.keys.contains("service_tier") {
                    state.currentServiceTier = Self.serviceTier(from: settings["service_tier"])
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
            let usage = totalUsage.map { $0.subtracting(state.previousTotalUsage) } ?? lastUsage

            if let totalUsage {
                state.previousTotalUsage = totalUsage
            }

            guard let usage, usage.hasTokens else {
                return
            }

            let payloadModel = Self.normalizedModel(payload["model"])
            let infoModel = Self.normalizedModel(info?["model"])
            if
                state.parentSessionId != nil,
                let sessionStartedAt = state.sessionStartedAt,
                timestamp < sessionStartedAt
            {
                return
            }
            if let eventCutoff, timestamp < eventCutoff {
                return
            }

            let model = payloadModel ?? infoModel ?? state.currentModel ?? "gpt-5"
            let isFallbackModel = payloadModel == nil && infoModel == nil && state.currentModel == nil

            events.append(CodexUsageEvent(
                sessionId: state.currentSessionId ?? fallbackSessionId,
                timestamp: timestamp,
                model: model,
                inputTokens: usage.inputTokens,
                cachedInputTokens: usage.cachedInputTokens,
                outputTokens: usage.outputTokens,
                reasoningTokens: usage.reasoningTokens,
                totalTokens: usage.totalTokens,
                sourceFile: fileURL,
                isFallbackModel: isFallbackModel,
                serviceTier: state.currentServiceTier
            ))
        }
    }

    private static func parentSessionId(from payload: [String: Any]) -> String? {
        guard
            let source = payload["source"] as? [String: Any],
            let subagent = source["subagent"] as? [String: Any],
            let threadSpawn = subagent["thread_spawn"] as? [String: Any]
        else {
            return nil
        }
        return normalizedModel(threadSpawn["parent_thread_id"])
    }

    private static func serviceTier(from value: Any?) -> UsageServiceTier? {
        switch normalizedModel(value)?.lowercased() {
        case "default", "standard":
            return .standard
        case "fast", "priority":
            return .fast
        default:
            return nil
        }
    }

    private static func lineMightContainUsage(_ lineData: Data) -> Bool {
        relevantMarkers.contains { marker in
            lineData.range(of: marker) != nil
        }
    }

    private static func rangeMightContainUsage(_ data: Data, range: Range<Data.Index>) -> Bool {
        relevantMarkers.contains { marker in
            data.range(of: marker, in: range) != nil
        }
    }

    private static func newlineIndex(in data: Data, range: Range<Data.Index>) -> Data.Index? {
        data.range(of: newlineMarker, in: range)?.lowerBound
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

    private static let chunkByteCount = 1024 * 1024
    private static let markerProbeByteCount = 4 * 1024
    private static let newlineByte = UInt8(ascii: "\n")
    private static let newlineMarker = Data([newlineByte])
    private static let relevantMarkers = [
        Data(#""session_meta""#.utf8),
        Data(#""turn_context""#.utf8),
        Data(#""thread_settings_applied""#.utf8),
        Data(#""token_count""#.utf8)
    ]
}

struct CodexUsageParserState {
    var currentSessionId: String?
    var parentSessionId: String?
    var sessionStartedAt: Date?
    var currentModel: String?
    var currentServiceTier: UsageServiceTier?
    var previousTotalUsage: RawUsage?
    var canResumeFromEOF = true
}

struct CodexUsageParseResult {
    let events: [CodexUsageEvent]
    let state: CodexUsageParserState
    let endOffset: UInt64
    let bytesRead: UInt64
}

struct RawUsage: Equatable {
    let rawInputTokens: Int
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let reasoningTokens: Int
    let totalTokens: Int
    let explicitTotalTokens: Int?

    init?(_ dictionary: [String: Any]) {
        let rawInput = Self.int(dictionary["input_tokens"])
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
        self.init(
            rawInputTokens: rawInput,
            cachedInputTokens: cached,
            outputTokens: output,
            reasoningTokens: reasoning,
            explicitTotalTokens: Self.int(dictionary["total_tokens"])
        )
    }

    var hasTokens: Bool {
        rawInputTokens + cachedInputTokens + outputTokens + reasoningTokens > 0
    }

    func subtracting(_ previous: RawUsage?) -> RawUsage {
        guard let previous else {
            return self
        }

        return RawUsage(
            rawInputTokens: max(rawInputTokens - previous.rawInputTokens, 0),
            cachedInputTokens: max(cachedInputTokens - previous.cachedInputTokens, 0),
            outputTokens: max(outputTokens - previous.outputTokens, 0),
            reasoningTokens: max(reasoningTokens - previous.reasoningTokens, 0),
            explicitTotalTokens: explicitTotalTokens.map { current in
                max(current - (previous.explicitTotalTokens ?? 0), 0)
            }
        )
    }

    private init(
        rawInputTokens: Int,
        cachedInputTokens: Int,
        outputTokens: Int,
        reasoningTokens: Int,
        explicitTotalTokens: Int?
    ) {
        let inputTokens = max(rawInputTokens - cachedInputTokens, 0)
        let calculatedTotal = inputTokens + cachedInputTokens + outputTokens

        self.rawInputTokens = rawInputTokens
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
        self.totalTokens = calculatedTotal > 0 ? calculatedTotal : (explicitTotalTokens ?? 0)
        self.explicitTotalTokens = explicitTotalTokens
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
