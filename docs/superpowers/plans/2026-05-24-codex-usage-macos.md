# Codex Usage macOS App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu bar app that shows Codex usage and estimated cost for today and the current hour, with English/Simplified Chinese UI selected from the system language.

**Architecture:** Use a Swift Package with a reusable `CodexUsageCore` target for parsing, pricing, localization, and aggregation, plus a `CodexUsageApp` executable target for SwiftUI/AppKit window behavior. Keep Codex log parsing local-only and publish immutable snapshots from the refresh model into compact SwiftUI views.

**Tech Stack:** Swift 6.3, SwiftUI, AppKit, XCTest, Swift Package Manager, macOS 14+.

---

## File Structure

- Create `Package.swift`: Swift package definition with app, core, and test targets.
- Create `Sources/CodexUsageCore/Models.swift`: shared value types for token usage, summaries, status, preferences enums.
- Create `Sources/CodexUsageCore/Localization.swift`: English and Simplified Chinese string table with system language detection.
- Create `Sources/CodexUsageCore/CodexPathResolver.swift`: resolve `CODEX_HOME`, `~/.codex`, and user overrides.
- Create `Sources/CodexUsageCore/CodexUsageParser.swift`: parse Codex JSONL lines and convert cumulative token totals into per-turn usage events.
- Create `Sources/CodexUsageCore/PricingService.swift`: estimate model costs and expose unknown/fallback status.
- Create `Sources/CodexUsageCore/UsageAggregator.swift`: aggregate events into today, current hour, recent hourly buckets, and model breakdown.
- Create `Sources/CodexUsageCore/CodexLogStore.swift`: discover `.jsonl` files and load events from Codex home or direct JSONL directories.
- Create `Sources/CodexUsageApp/CodexUsageApp.swift`: SwiftUI app entry and menu bar commands.
- Create `Sources/CodexUsageApp/AppModel.swift`: observable app state, preferences persistence, refresh task orchestration.
- Create `Sources/CodexUsageApp/UsageWindowController.swift`: AppKit floating panel and always-on-top behavior.
- Create `Sources/CodexUsageApp/UsageView.swift`: compact usage window.
- Create `Sources/CodexUsageApp/PreferencesView.swift`: settings UI.
- Create `Tests/CodexUsageCoreTests/Fixtures/codex-session.jsonl`: redacted Codex session fixture.
- Create `Tests/CodexUsageCoreTests/CodexUsageParserTests.swift`: parser tests.
- Create `Tests/CodexUsageCoreTests/UsageAggregatorTests.swift`: aggregation tests.
- Create `Tests/CodexUsageCoreTests/PricingServiceTests.swift`: cost tests.
- Create `Tests/CodexUsageCoreTests/LocalizationTests.swift`: language detection tests.
- Create `Tests/CodexUsageCoreTests/CodexPathResolverTests.swift`: path resolution tests.
- Create `scripts/package-app.sh`: local `.app` packaging script for the SwiftPM binary.
- Create `README.md`: build, run, package, and usage instructions.

## Task 1: Scaffold Swift Package

**Files:**
- Create: `Package.swift`
- Create: `Sources/CodexUsageCore/Models.swift`
- Create: `Sources/CodexUsageApp/CodexUsageApp.swift`
- Create: `Tests/CodexUsageCoreTests/SmokeTests.swift`

- [ ] **Step 1: Create package definition**

Write `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexUsage",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexUsage", targets: ["CodexUsageApp"]),
        .library(name: "CodexUsageCore", targets: ["CodexUsageCore"])
    ],
    targets: [
        .target(name: "CodexUsageCore"),
        .executableTarget(
            name: "CodexUsageApp",
            dependencies: ["CodexUsageCore"]
        ),
        .testTarget(
            name: "CodexUsageCoreTests",
            dependencies: ["CodexUsageCore"],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
```

- [ ] **Step 2: Add initial core model file**

Write `Sources/CodexUsageCore/Models.swift`:

```swift
import Foundation

public enum SpeedMode: String, CaseIterable, Sendable {
    case auto
    case standard
    case fast
}

public enum RefreshInterval: Int, CaseIterable, Sendable {
    case fifteenSeconds = 15
    case thirtySeconds = 30
    case sixtySeconds = 60
    case fiveMinutes = 300
}

public struct CodexUsageEvent: Equatable, Sendable {
    public let sessionId: String
    public let timestamp: Date
    public let model: String
    public let inputTokens: Int
    public let cachedInputTokens: Int
    public let outputTokens: Int
    public let reasoningTokens: Int
    public let totalTokens: Int
    public let sourceFile: URL
    public let isFallbackModel: Bool

    public init(
        sessionId: String,
        timestamp: Date,
        model: String,
        inputTokens: Int,
        cachedInputTokens: Int,
        outputTokens: Int,
        reasoningTokens: Int,
        totalTokens: Int,
        sourceFile: URL,
        isFallbackModel: Bool = false
    ) {
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.model = model
        self.inputTokens = inputTokens
        self.cachedInputTokens = min(cachedInputTokens, inputTokens)
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
        self.totalTokens = totalTokens
        self.sourceFile = sourceFile
        self.isFallbackModel = isFallbackModel
    }
}

public struct TokenTotals: Equatable, Sendable {
    public var inputTokens: Int
    public var cachedInputTokens: Int
    public var outputTokens: Int
    public var reasoningTokens: Int
    public var totalTokens: Int

    public static let zero = TokenTotals(
        inputTokens: 0,
        cachedInputTokens: 0,
        outputTokens: 0,
        reasoningTokens: 0,
        totalTokens: 0
    )
}

public struct CostEstimate: Equatable, Sendable {
    public let usd: Decimal?
    public let hasUnknownPricing: Bool
    public let usedFallbackMultiplier: Bool
}

public struct UsageSummary: Equatable, Sendable {
    public let totals: TokenTotals
    public let cost: CostEstimate
}
```

- [ ] **Step 3: Add minimal app entry**

Write `Sources/CodexUsageApp/CodexUsageApp.swift`:

```swift
import CodexUsageCore
import SwiftUI

@main
struct CodexUsageApp: App {
    var body: some Scene {
        MenuBarExtra("Codex Usage", systemImage: "bolt.horizontal.circle") {
            Text("Codex Usage")
        }
        .menuBarExtraStyle(.menu)
    }
}
```

- [ ] **Step 4: Add smoke test**

Write `Tests/CodexUsageCoreTests/SmokeTests.swift`:

```swift
import CodexUsageCore
import XCTest

final class SmokeTests: XCTestCase {
    func testTokenTotalsZero() {
        XCTAssertEqual(TokenTotals.zero.totalTokens, 0)
        XCTAssertEqual(SpeedMode.allCases, [.auto, .standard, .fast])
    }
}
```

- [ ] **Step 5: Verify scaffold builds**

Run: `swift test`

Expected: build succeeds and `SmokeTests.testTokenTotalsZero` passes.

- [ ] **Step 6: Commit scaffold**

```bash
git add Package.swift Sources Tests
git commit -m "Scaffold SwiftUI macOS app"
```

## Task 2: Localization Core

**Files:**
- Create: `Sources/CodexUsageCore/Localization.swift`
- Create: `Tests/CodexUsageCoreTests/LocalizationTests.swift`

- [ ] **Step 1: Write localization tests**

Write `Tests/CodexUsageCoreTests/LocalizationTests.swift`:

```swift
import CodexUsageCore
import XCTest

final class LocalizationTests: XCTestCase {
    func testChinesePreferredLanguageUsesChinese() {
        let strings = AppStrings(preferredLanguages: ["zh-Hans-US", "en-US"])
        XCTAssertEqual(strings.codexUsageTitle, "Codex 用量")
        XCTAssertEqual(strings.today, "今日")
        XCTAssertEqual(strings.thisHour, "本小时")
    }

    func testEnglishFallbackForNonChineseLanguage() {
        let strings = AppStrings(preferredLanguages: ["fr-FR", "en-US"])
        XCTAssertEqual(strings.codexUsageTitle, "Codex Usage")
        XCTAssertEqual(strings.today, "Today")
        XCTAssertEqual(strings.thisHour, "This Hour")
    }
}
```

- [ ] **Step 2: Run localization tests to verify failure**

Run: `swift test --filter LocalizationTests`

Expected: FAIL because `AppStrings` is not defined.

- [ ] **Step 3: Implement localization table**

Write `Sources/CodexUsageCore/Localization.swift`:

```swift
import Foundation

public struct AppStrings: Equatable, Sendable {
    public enum Language: Equatable, Sendable {
        case english
        case simplifiedChinese
    }

    public let language: Language

    public init(preferredLanguages: [String] = Locale.preferredLanguages) {
        let first = preferredLanguages.first?.lowercased() ?? "en"
        self.language = first.hasPrefix("zh") ? .simplifiedChinese : .english
    }

    public var codexUsageTitle: String { text(en: "Codex Usage", zh: "Codex 用量") }
    public var today: String { text(en: "Today", zh: "今日") }
    public var thisHour: String { text(en: "This Hour", zh: "本小时") }
    public var recentHours: String { text(en: "Recent 24h", zh: "最近 24 小时") }
    public var models: String { text(en: "Models", zh: "模型") }
    public var refresh: String { text(en: "Refresh", zh: "刷新") }
    public var preferences: String { text(en: "Preferences", zh: "偏好设置") }
    public var alwaysOnTop: String { text(en: "Always on Top", zh: "窗口置顶") }
    public var refreshInterval: String { text(en: "Refresh Interval", zh: "刷新间隔") }
    public var speedMode: String { text(en: "Speed Pricing", zh: "速度计价") }
    public var codexPath: String { text(en: "Codex Path", zh: "Codex 路径") }
    public var noData: String { text(en: "No Codex data found", zh: "未找到 Codex 数据") }
    public var unreadablePath: String { text(en: "Path is not readable", zh: "路径不可读取") }
    public var unknownPricing: String { text(en: "Unknown pricing", zh: "未知价格") }
    public var estimated: String { text(en: "Estimated", zh: "估算") }
    public var lastUpdated: String { text(en: "Updated", zh: "更新于") }

    public func intervalLabel(_ interval: RefreshInterval) -> String {
        switch (language, interval) {
        case (.english, .fifteenSeconds): return "15 seconds"
        case (.english, .thirtySeconds): return "30 seconds"
        case (.english, .sixtySeconds): return "60 seconds"
        case (.english, .fiveMinutes): return "5 minutes"
        case (.simplifiedChinese, .fifteenSeconds): return "15 秒"
        case (.simplifiedChinese, .thirtySeconds): return "30 秒"
        case (.simplifiedChinese, .sixtySeconds): return "60 秒"
        case (.simplifiedChinese, .fiveMinutes): return "5 分钟"
        }
    }

    private func text(en: String, zh: String) -> String {
        language == .simplifiedChinese ? zh : en
    }
}
```

- [ ] **Step 4: Verify localization tests pass**

Run: `swift test --filter LocalizationTests`

Expected: PASS.

- [ ] **Step 5: Commit localization**

```bash
git add Sources/CodexUsageCore/Localization.swift Tests/CodexUsageCoreTests/LocalizationTests.swift
git commit -m "Add bilingual localization"
```

## Task 3: Path Resolution and Pricing

**Files:**
- Create: `Sources/CodexUsageCore/CodexPathResolver.swift`
- Create: `Sources/CodexUsageCore/PricingService.swift`
- Create: `Tests/CodexUsageCoreTests/CodexPathResolverTests.swift`
- Create: `Tests/CodexUsageCoreTests/PricingServiceTests.swift`

- [ ] **Step 1: Write path resolver tests**

Write `Tests/CodexUsageCoreTests/CodexPathResolverTests.swift`:

```swift
import CodexUsageCore
import XCTest

final class CodexPathResolverTests: XCTestCase {
    func testUserOverrideWins() {
        let resolver = CodexPathResolver(
            environment: ["CODEX_HOME": "/env/codex"],
            homeDirectory: URL(fileURLWithPath: "/Users/example")
        )
        XCTAssertEqual(
            resolver.resolve(userOverride: "/custom/codex").path,
            "/custom/codex"
        )
    }

    func testCodexHomeEnvironmentWinsWhenNoOverride() {
        let resolver = CodexPathResolver(
            environment: ["CODEX_HOME": "/env/codex"],
            homeDirectory: URL(fileURLWithPath: "/Users/example")
        )
        XCTAssertEqual(resolver.resolve(userOverride: nil).path, "/env/codex")
    }

    func testDefaultFallsBackToDotCodex() {
        let resolver = CodexPathResolver(
            environment: [:],
            homeDirectory: URL(fileURLWithPath: "/Users/example")
        )
        XCTAssertEqual(resolver.resolve(userOverride: nil).path, "/Users/example/.codex")
    }
}
```

- [ ] **Step 2: Write pricing tests**

Write `Tests/CodexUsageCoreTests/PricingServiceTests.swift`:

```swift
import CodexUsageCore
import XCTest

final class PricingServiceTests: XCTestCase {
    func testKnownModelCostUsesStandardPricing() {
        let service = PricingService(speedMode: .standard, autoDetectedFast: false)
        let estimate = service.estimate(
            events: [
                CodexUsageEvent(
                    sessionId: "s1",
                    timestamp: Date(timeIntervalSince1970: 0),
                    model: "gpt-5.2-codex",
                    inputTokens: 1_000_000,
                    cachedInputTokens: 0,
                    outputTokens: 1_000_000,
                    reasoningTokens: 0,
                    totalTokens: 2_000_000,
                    sourceFile: URL(fileURLWithPath: "/tmp/a.jsonl")
                )
            ]
        )
        XCTAssertEqual(estimate.hasUnknownPricing, false)
        XCTAssertEqual(estimate.usedFallbackMultiplier, false)
        XCTAssertEqual(estimate.usd, Decimal(string: "12.50"))
    }

    func testUnknownModelMarksUnknownPricing() {
        let service = PricingService(speedMode: .standard, autoDetectedFast: false)
        let estimate = service.estimate(
            events: [
                CodexUsageEvent(
                    sessionId: "s1",
                    timestamp: Date(timeIntervalSince1970: 0),
                    model: "unknown-model",
                    inputTokens: 1,
                    cachedInputTokens: 0,
                    outputTokens: 1,
                    reasoningTokens: 0,
                    totalTokens: 2,
                    sourceFile: URL(fileURLWithPath: "/tmp/a.jsonl")
                )
            ]
        )
        XCTAssertNil(estimate.usd)
        XCTAssertEqual(estimate.hasUnknownPricing, true)
    }

    func testFastModeUsesTwoTimesFallbackWhenModelHasNoSpecificMultiplier() {
        let service = PricingService(speedMode: .fast, autoDetectedFast: false)
        let estimate = service.estimate(
            events: [
                CodexUsageEvent(
                    sessionId: "s1",
                    timestamp: Date(timeIntervalSince1970: 0),
                    model: "gpt-5.2-codex",
                    inputTokens: 1_000_000,
                    cachedInputTokens: 0,
                    outputTokens: 0,
                    reasoningTokens: 0,
                    totalTokens: 1_000_000,
                    sourceFile: URL(fileURLWithPath: "/tmp/a.jsonl")
                )
            ]
        )
        XCTAssertEqual(estimate.usd, Decimal(string: "5.00"))
        XCTAssertEqual(estimate.usedFallbackMultiplier, true)
    }
}
```

- [ ] **Step 3: Run tests to verify failure**

Run: `swift test --filter CodexPathResolverTests && swift test --filter PricingServiceTests`

Expected: FAIL because resolver and pricing types are not defined.

- [ ] **Step 4: Implement path resolver**

Write `Sources/CodexUsageCore/CodexPathResolver.swift`:

```swift
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
```

- [ ] **Step 5: Implement pricing service**

Write `Sources/CodexUsageCore/PricingService.swift`:

```swift
import Foundation

public struct PricingService: Sendable {
    public struct ModelPrice: Sendable {
        let inputPerMillion: Decimal
        let cachedInputPerMillion: Decimal
        let outputPerMillion: Decimal
        let fastMultiplier: Decimal?
    }

    private let speedMode: SpeedMode
    private let autoDetectedFast: Bool

    public init(speedMode: SpeedMode, autoDetectedFast: Bool) {
        self.speedMode = speedMode
        self.autoDetectedFast = autoDetectedFast
    }

    public func estimate(events: [CodexUsageEvent]) -> CostEstimate {
        var total = Decimal.zero
        var hasCost = false
        var hasUnknown = false
        var usedFallback = false

        for event in events {
            guard let price = Self.price(for: event.model) else {
                hasUnknown = true
                continue
            }
            hasCost = true
            let multiplier = multiplier(for: price)
            if multiplier == Decimal(2), price.fastMultiplier == nil, effectiveFastMode {
                usedFallback = true
            }
            let uncachedInput = max(event.inputTokens - event.cachedInputTokens, 0)
            total += Decimal(uncachedInput) * price.inputPerMillion / 1_000_000 * multiplier
            total += Decimal(event.cachedInputTokens) * price.cachedInputPerMillion / 1_000_000 * multiplier
            total += Decimal(event.outputTokens) * price.outputPerMillion / 1_000_000 * multiplier
        }

        return CostEstimate(
            usd: hasCost ? total.rounded(scale: 4) : nil,
            hasUnknownPricing: hasUnknown,
            usedFallbackMultiplier: usedFallback
        )
    }

    private var effectiveFastMode: Bool {
        switch speedMode {
        case .auto: return autoDetectedFast
        case .standard: return false
        case .fast: return true
        }
    }

    private func multiplier(for price: ModelPrice) -> Decimal {
        guard effectiveFastMode else { return 1 }
        return price.fastMultiplier ?? 2
    }

    private static func price(for model: String) -> ModelPrice? {
        let normalized = model.lowercased()
        if normalized.contains("gpt-5.2-codex") || normalized == "gpt-5" {
            return ModelPrice(
                inputPerMillion: Decimal(string: "2.50")!,
                cachedInputPerMillion: Decimal(string: "0.25")!,
                outputPerMillion: Decimal(string: "10.00")!,
                fastMultiplier: nil
            )
        }
        if normalized.contains("gpt-5.3-codex") {
            return ModelPrice(
                inputPerMillion: Decimal(string: "3.00")!,
                cachedInputPerMillion: Decimal(string: "0.30")!,
                outputPerMillion: Decimal(string: "12.00")!,
                fastMultiplier: nil
            )
        }
        return nil
    }
}

extension Decimal {
    func rounded(scale: Int) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, .plain)
        return result
    }
}
```

- [ ] **Step 6: Verify tests pass**

Run: `swift test --filter CodexPathResolverTests && swift test --filter PricingServiceTests`

Expected: PASS.

- [ ] **Step 7: Commit path and pricing**

```bash
git add Sources/CodexUsageCore/CodexPathResolver.swift Sources/CodexUsageCore/PricingService.swift Tests/CodexUsageCoreTests/CodexPathResolverTests.swift Tests/CodexUsageCoreTests/PricingServiceTests.swift
git commit -m "Add Codex path resolution and pricing"
```

## Task 4: Codex Parser

**Files:**
- Create: `Sources/CodexUsageCore/CodexUsageParser.swift`
- Create: `Tests/CodexUsageCoreTests/Fixtures/codex-session.jsonl`
- Create: `Tests/CodexUsageCoreTests/CodexUsageParserTests.swift`

- [ ] **Step 1: Add Codex JSONL fixture**

Write `Tests/CodexUsageCoreTests/Fixtures/codex-session.jsonl`:

```jsonl
{"timestamp":"2026-05-24T00:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.2-codex"}}
{"timestamp":"2026-05-24T00:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":200,"output_tokens":100,"reasoning_output_tokens":25,"total_tokens":1125},"total_token_usage":{"input_tokens":1000,"cached_input_tokens":200,"output_tokens":100,"reasoning_output_tokens":25,"total_tokens":1125}}}}
{"timestamp":"2026-05-24T01:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1500,"cached_input_tokens":300,"output_tokens":140,"reasoning_output_tokens":35,"total_tokens":1675}}}}
```

- [ ] **Step 2: Write parser tests**

Write `Tests/CodexUsageCoreTests/CodexUsageParserTests.swift`:

```swift
import CodexUsageCore
import XCTest

final class CodexUsageParserTests: XCTestCase {
    func testParsesLastUsageAndTotalUsageDelta() throws {
        let fixture = Bundle.module.url(forResource: "codex-session", withExtension: "jsonl")!
        let parser = CodexUsageParser()
        let events = try parser.parseFile(
            fixture,
            sessionsRoot: fixture.deletingLastPathComponent(),
            fallbackModifiedDate: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].model, "gpt-5.2-codex")
        XCTAssertEqual(events[0].inputTokens, 1000)
        XCTAssertEqual(events[0].cachedInputTokens, 200)
        XCTAssertEqual(events[0].outputTokens, 100)
        XCTAssertEqual(events[0].reasoningTokens, 25)
        XCTAssertEqual(events[1].inputTokens, 500)
        XCTAssertEqual(events[1].cachedInputTokens, 100)
        XCTAssertEqual(events[1].outputTokens, 40)
        XCTAssertEqual(events[1].reasoningTokens, 10)
    }
}
```

- [ ] **Step 3: Run parser test to verify failure**

Run: `swift test --filter CodexUsageParserTests`

Expected: FAIL because `CodexUsageParser` is not defined.

- [ ] **Step 4: Implement parser**

Write `Sources/CodexUsageCore/CodexUsageParser.swift` with these public entry points and behavior:

```swift
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
        let sessionId = fileURL.deletingPathExtension().lastPathComponent
        var events: [CodexUsageEvent] = []
        var currentModel: String?
        var previousTotal: RawUsage?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = String(rawLine).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            if object["type"] as? String == "turn_context" {
                if let payload = object["payload"] as? [String: Any],
                   let model = payload["model"] as? String {
                    currentModel = model
                }
                continue
            }

            guard object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count"
            else { continue }

            let timestamp = Self.parseTimestamp(object["timestamp"]) ?? fallbackModifiedDate
            let info = payload["info"] as? [String: Any]
            let lastUsage = (info?["last_token_usage"] as? [String: Any]).flatMap(RawUsage.init)
            let totalUsage = (info?["total_token_usage"] as? [String: Any]).flatMap(RawUsage.init)
            let usage = lastUsage ?? totalUsage.map { current in
                current.subtracting(previousTotal)
            }
            if let totalUsage {
                previousTotal = totalUsage
            }
            guard let usage, usage.hasBillableTokens else { continue }

            let model = (payload["model"] as? String)
                ?? (info?["model"] as? String)
                ?? currentModel
                ?? "gpt-5"

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
                isFallbackModel: currentModel == nil && payload["model"] == nil && info?["model"] == nil
            ))
        }

        return events
    }

    private static func parseTimestamp(_ value: Any?) -> Date? {
        if let string = value as? String {
            return ISO8601DateFormatter.codex.date(from: string)
        }
        if let number = value as? TimeInterval {
            return Date(timeIntervalSince1970: number / 1000)
        }
        return nil
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
        self.inputTokens = input
        self.cachedInputTokens = min(cached, input)
        self.outputTokens = output
        self.reasoningTokens = reasoning
        self.totalTokens = total
    }

    var hasBillableTokens: Bool {
        inputTokens + cachedInputTokens + outputTokens + reasoningTokens > 0
    }

    func subtracting(_ previous: RawUsage?) -> RawUsage {
        guard let previous else { return self }
        return RawUsage(
            inputTokens: max(inputTokens - previous.inputTokens, 0),
            cachedInputTokens: max(cachedInputTokens - previous.cachedInputTokens, 0),
            outputTokens: max(outputTokens - previous.outputTokens, 0),
            reasoningTokens: max(reasoningTokens - previous.reasoningTokens, 0),
            totalTokens: max(totalTokens - previous.totalTokens, 0)
        )
    }

    private init(inputTokens: Int, cachedInputTokens: Int, outputTokens: Int, reasoningTokens: Int, totalTokens: Int) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = min(cachedInputTokens, inputTokens)
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
        self.totalTokens = totalTokens
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }
}

private extension ISO8601DateFormatter {
    static let codex: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
```

- [ ] **Step 5: Verify parser tests pass**

Run: `swift test --filter CodexUsageParserTests`

Expected: PASS.

- [ ] **Step 6: Commit parser**

```bash
git add Sources/CodexUsageCore/CodexUsageParser.swift Tests/CodexUsageCoreTests/Fixtures/codex-session.jsonl Tests/CodexUsageCoreTests/CodexUsageParserTests.swift
git commit -m "Parse Codex token usage logs"
```

## Task 5: Aggregation

**Files:**
- Create: `Sources/CodexUsageCore/UsageAggregator.swift`
- Create: `Tests/CodexUsageCoreTests/UsageAggregatorTests.swift`
- Modify: `Sources/CodexUsageCore/Models.swift`

- [ ] **Step 1: Extend models for app snapshots**

Add these types to `Sources/CodexUsageCore/Models.swift`:

```swift
public struct HourBucket: Equatable, Identifiable, Sendable {
    public let id: Date
    public let start: Date
    public let summary: UsageSummary
}

public struct ModelBreakdown: Equatable, Identifiable, Sendable {
    public var id: String { model }
    public let model: String
    public let summary: UsageSummary
}

public struct UsageSnapshot: Equatable, Sendable {
    public let generatedAt: Date
    public let today: UsageSummary
    public let currentHour: UsageSummary
    public let recentHours: [HourBucket]
    public let modelBreakdown: [ModelBreakdown]
    public let warnings: [String]
}
```

- [ ] **Step 2: Write aggregation tests**

Write `Tests/CodexUsageCoreTests/UsageAggregatorTests.swift`:

```swift
import CodexUsageCore
import XCTest

final class UsageAggregatorTests: XCTestCase {
    func testAggregatesTodayAndCurrentHour() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter.codexTest.date(from: "2026-05-24T10:30:00.000Z")!
        let events = [
            event("2026-05-24T09:55:00.000Z", input: 100, output: 50),
            event("2026-05-24T10:10:00.000Z", input: 200, output: 80),
            event("2026-05-23T10:10:00.000Z", input: 900, output: 900)
        ]

        let snapshot = UsageAggregator(
            calendar: calendar,
            pricing: PricingService(speedMode: .standard, autoDetectedFast: false)
        ).snapshot(events: events, now: now)

        XCTAssertEqual(snapshot.today.totals.inputTokens, 300)
        XCTAssertEqual(snapshot.currentHour.totals.inputTokens, 200)
        XCTAssertEqual(snapshot.recentHours.count, 24)
        XCTAssertEqual(snapshot.modelBreakdown.first?.model, "gpt-5.2-codex")
    }

    private func event(_ timestamp: String, input: Int, output: Int) -> CodexUsageEvent {
        CodexUsageEvent(
            sessionId: "s",
            timestamp: ISO8601DateFormatter.codexTest.date(from: timestamp)!,
            model: "gpt-5.2-codex",
            inputTokens: input,
            cachedInputTokens: 0,
            outputTokens: output,
            reasoningTokens: 0,
            totalTokens: input + output,
            sourceFile: URL(fileURLWithPath: "/tmp/s.jsonl")
        )
    }
}

private extension ISO8601DateFormatter {
    static let codexTest: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
```

- [ ] **Step 3: Run aggregation test to verify failure**

Run: `swift test --filter UsageAggregatorTests`

Expected: FAIL because `UsageAggregator` is not defined.

- [ ] **Step 4: Implement aggregator**

Write `Sources/CodexUsageCore/UsageAggregator.swift`:

```swift
import Foundation

public struct UsageAggregator: Sendable {
    private let calendar: Calendar
    private let pricing: PricingService

    public init(calendar: Calendar = .current, pricing: PricingService) {
        self.calendar = calendar
        self.pricing = pricing
    }

    public func snapshot(events: [CodexUsageEvent], now: Date) -> UsageSnapshot {
        let dayStart = calendar.startOfDay(for: now)
        let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let todayEvents = events.filter { $0.timestamp >= dayStart && $0.timestamp <= now }
        let currentHourEvents = events.filter { $0.timestamp >= hourStart && $0.timestamp <= now }
        let hourly = recentHours(events: events, now: now)
        let breakdown = Dictionary(grouping: todayEvents, by: \.model)
            .map { model, events in
                ModelBreakdown(model: model, summary: summary(events))
            }
            .sorted { lhs, rhs in
                lhs.summary.totals.totalTokens > rhs.summary.totals.totalTokens
            }
        let warnings = todayEvents.contains(where: \.isFallbackModel) ? ["fallback-model"] : []

        return UsageSnapshot(
            generatedAt: now,
            today: summary(todayEvents),
            currentHour: summary(currentHourEvents),
            recentHours: hourly,
            modelBreakdown: breakdown,
            warnings: warnings
        )
    }

    private func recentHours(events: [CodexUsageEvent], now: Date) -> [HourBucket] {
        let currentHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        return (0..<24).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .hour, value: -offset, to: currentHour),
                  let end = calendar.date(byAdding: .hour, value: 1, to: start)
            else { return nil }
            let bucketEvents = events.filter { $0.timestamp >= start && $0.timestamp < end }
            return HourBucket(id: start, start: start, summary: summary(bucketEvents))
        }
    }

    private func summary(_ events: [CodexUsageEvent]) -> UsageSummary {
        let totals = TokenTotals(
            inputTokens: events.reduce(0) { $0 + $1.inputTokens },
            cachedInputTokens: events.reduce(0) { $0 + $1.cachedInputTokens },
            outputTokens: events.reduce(0) { $0 + $1.outputTokens },
            reasoningTokens: events.reduce(0) { $0 + $1.reasoningTokens },
            totalTokens: events.reduce(0) { $0 + $1.totalTokens }
        )
        return UsageSummary(totals: totals, cost: pricing.estimate(events: events))
    }
}
```

- [ ] **Step 5: Verify aggregation tests pass**

Run: `swift test --filter UsageAggregatorTests`

Expected: PASS.

- [ ] **Step 6: Commit aggregation**

```bash
git add Sources/CodexUsageCore/Models.swift Sources/CodexUsageCore/UsageAggregator.swift Tests/CodexUsageCoreTests/UsageAggregatorTests.swift
git commit -m "Aggregate Codex usage by day and hour"
```

## Task 6: Log Store and Fast Mode Detection

**Files:**
- Create: `Sources/CodexUsageCore/CodexLogStore.swift`
- Modify: `Sources/CodexUsageCore/PricingService.swift`
- Create: `Tests/CodexUsageCoreTests/CodexLogStoreTests.swift`

- [ ] **Step 1: Write log store tests**

Write `Tests/CodexUsageCoreTests/CodexLogStoreTests.swift`:

```swift
import CodexUsageCore
import XCTest

final class CodexLogStoreTests: XCTestCase {
    func testDiscoversJsonlFilesUnderSessions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sessions = root.appendingPathComponent("sessions/project-a", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent("session.jsonl")
        try "{}\n".write(to: file, atomically: true, encoding: .utf8)

        let store = CodexLogStore(parser: CodexUsageParser())
        let files = try store.discoverJSONLFiles(root: root)
        XCTAssertEqual(files, [file])
    }

    func testDetectsPriorityServiceTier() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "service_tier = \"priority\"\n".write(
            to: root.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let store = CodexLogStore(parser: CodexUsageParser())
        XCTAssertTrue(store.detectFastMode(root: root))
    }
}
```

- [ ] **Step 2: Run log store tests to verify failure**

Run: `swift test --filter CodexLogStoreTests`

Expected: FAIL because `CodexLogStore` is not defined.

- [ ] **Step 3: Implement log store**

Write `Sources/CodexUsageCore/CodexLogStore.swift`:

```swift
import Foundation

public struct CodexLogStore: Sendable {
    private let parser: CodexUsageParser
    private let fileManager: FileManager

    public init(parser: CodexUsageParser, fileManager: FileManager = .default) {
        self.parser = parser
        self.fileManager = fileManager
    }

    public func loadEvents(root: URL) throws -> [CodexUsageEvent] {
        let files = try discoverJSONLFiles(root: root)
        return try files.flatMap { file in
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            return try parser.parseFile(file, sessionsRoot: root, fallbackModifiedDate: modified)
        }
    }

    public func discoverJSONLFiles(root: URL) throws -> [URL] {
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let scanRoot = fileManager.fileExists(atPath: sessions.path) ? sessions : root
        guard let enumerator = fileManager.enumerator(
            at: scanRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let file as URL in enumerator where file.pathExtension == "jsonl" {
            files.append(file)
        }
        return files.sorted { $0.path < $1.path }
    }

    public func detectFastMode(root: URL) -> Bool {
        let config = root.appendingPathComponent("config.toml")
        guard let text = try? String(contentsOf: config, encoding: .utf8) else {
            return false
        }
        return text.contains("service_tier = \"priority\"") || text.contains("service_tier = \"fast\"")
    }
}
```

- [ ] **Step 4: Verify log store tests pass**

Run: `swift test --filter CodexLogStoreTests`

Expected: PASS.

- [ ] **Step 5: Commit log store**

```bash
git add Sources/CodexUsageCore/CodexLogStore.swift Tests/CodexUsageCoreTests/CodexLogStoreTests.swift
git commit -m "Load Codex log files"
```

## Task 7: App State and Refresh

**Files:**
- Create: `Sources/CodexUsageApp/AppModel.swift`
- Modify: `Sources/CodexUsageApp/CodexUsageApp.swift`

- [ ] **Step 1: Implement app model**

Write `Sources/CodexUsageApp/AppModel.swift`:

```swift
import CodexUsageCore
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var snapshot: UsageSnapshot
    var strings: AppStrings
    var statusMessage: String
    var isAlwaysOnTop: Bool {
        didSet {
            UserDefaults.standard.set(isAlwaysOnTop, forKey: "alwaysOnTop")
            onAlwaysOnTopChanged?(isAlwaysOnTop)
        }
    }
    var refreshInterval: RefreshInterval {
        didSet { UserDefaults.standard.set(refreshInterval.rawValue, forKey: "refreshInterval") }
    }
    var speedMode: SpeedMode {
        didSet { UserDefaults.standard.set(speedMode.rawValue, forKey: "speedMode") }
    }
    var pathOverride: String {
        didSet { UserDefaults.standard.set(pathOverride, forKey: "pathOverride") }
    }

    private let resolver = CodexPathResolver()
    private var refreshTask: Task<Void, Never>?
    @ObservationIgnored var onAlwaysOnTopChanged: ((Bool) -> Void)?
    @ObservationIgnored private var timerTask: Task<Void, Never>?

    init(strings: AppStrings = AppStrings()) {
        self.strings = strings
        self.statusMessage = ""
        self.isAlwaysOnTop = UserDefaults.standard.bool(forKey: "alwaysOnTop")
        let savedInterval = UserDefaults.standard.integer(forKey: "refreshInterval")
        self.refreshInterval = RefreshInterval(rawValue: savedInterval) ?? .sixtySeconds
        let savedSpeed = UserDefaults.standard.string(forKey: "speedMode")
        self.speedMode = savedSpeed.flatMap(SpeedMode.init(rawValue:)) ?? .auto
        self.pathOverride = UserDefaults.standard.string(forKey: "pathOverride") ?? ""
        self.snapshot = UsageSnapshot(
            generatedAt: Date(),
            today: UsageSummary(totals: .zero, cost: CostEstimate(usd: Decimal.zero, hasUnknownPricing: false, usedFallbackMultiplier: false)),
            currentHour: UsageSummary(totals: .zero, cost: CostEstimate(usd: Decimal.zero, hasUnknownPricing: false, usedFallbackMultiplier: false)),
            recentHours: [],
            modelBreakdown: [],
            warnings: []
        )
    }

    func refresh() {
        refreshTask?.cancel()
        let path = resolver.resolve(userOverride: pathOverride.isEmpty ? nil : pathOverride)
        let speedMode = speedMode
        refreshTask = Task {
            do {
                let events = try await Task.detached {
                    try CodexLogStore(parser: CodexUsageParser()).loadEvents(root: path)
                }.value
                let fast = CodexLogStore(parser: CodexUsageParser()).detectFastMode(root: path)
                let pricing = PricingService(speedMode: speedMode, autoDetectedFast: fast)
                let snapshot = UsageAggregator(pricing: pricing).snapshot(events: events, now: Date())
                self.snapshot = snapshot
                self.statusMessage = events.isEmpty ? self.strings.noData : path.path
            } catch {
                self.statusMessage = self.strings.unreadablePath
            }
        }
    }

    func startTimerIfNeeded() {
        guard timerTask == nil else {
            return
        }
        timerTask = Task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(for: .seconds(refreshInterval.rawValue))
            }
        }
    }

    deinit {
        refreshTask?.cancel()
        timerTask?.cancel()
    }
}
```

- [ ] **Step 2: Wire app model into menu bar**

Replace `Sources/CodexUsageApp/CodexUsageApp.swift` with:

```swift
import CodexUsageCore
import SwiftUI

@main
struct CodexUsageApp: App {
    @State private var model = AppModel()
    @State private var windowController: UsageWindowController?

    var body: some Scene {
        MenuBarExtra(model.strings.codexUsageTitle, systemImage: "bolt.horizontal.circle") {
            Button(model.strings.codexUsageTitle) {
                showWindow()
            }
            Button(model.strings.refresh) {
                model.refresh()
            }
            Divider()
            SettingsLink {
                Text(model.strings.preferences)
            }
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            PreferencesView(model: model)
        }
    }

    private func showWindow() {
        if windowController == nil {
            windowController = UsageWindowController(model: model)
        }
        windowController?.show()
        model.startTimerIfNeeded()
    }
}
```

- [ ] **Step 3: Build to verify missing UI files are the only failures**

Run: `swift build`

Expected: FAIL mentioning missing `UsageWindowController` and `PreferencesView`.

- [ ] **Step 4: Commit app model after Task 8 compiles**

Do not commit this task until Task 8 adds the UI files and `swift build` passes.

## Task 8: Floating Window, Usage UI, Preferences

**Files:**
- Create: `Sources/CodexUsageApp/UsageWindowController.swift`
- Create: `Sources/CodexUsageApp/UsageView.swift`
- Create: `Sources/CodexUsageApp/PreferencesView.swift`
- Modify: `Sources/CodexUsageApp/AppModel.swift`

- [ ] **Step 1: Implement floating window controller**

Write `Sources/CodexUsageApp/UsageWindowController.swift`:

```swift
import AppKit
import SwiftUI

@MainActor
final class UsageWindowController {
    private let panel: NSPanel

    init(model: AppModel) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = model.strings.codexUsageTitle
        panel.isFloatingPanel = model.isAlwaysOnTop
        panel.level = model.isAlwaysOnTop ? .floating : .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(rootView: UsageView(model: model))
        panel.center()
        self.panel = panel
        model.onAlwaysOnTopChanged = { [weak self] enabled in
            self?.setAlwaysOnTop(enabled)
        }
    }

    func show() {
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setAlwaysOnTop(_ enabled: Bool) {
        panel.isFloatingPanel = enabled
        panel.level = enabled ? .floating : .normal
    }
}
```

- [ ] **Step 2: Implement compact usage view**

Write `Sources/CodexUsageApp/UsageView.swift`:

```swift
import CodexUsageCore
import SwiftUI

struct UsageView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.strings.codexUsageTitle)
                    .font(.headline)
                Spacer()
                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(model.strings.refresh)
            }

            HStack(spacing: 10) {
                metric(title: model.strings.today, summary: model.snapshot.today)
                metric(title: model.strings.thisHour, summary: model.snapshot.currentHour)
            }

            Text(model.strings.recentHours)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(model.snapshot.recentHours) { bucket in
                    Capsule()
                        .fill(Color.accentColor.opacity(0.65))
                        .frame(width: 7, height: barHeight(bucket.summary.totals.totalTokens))
                }
            }
            .frame(height: 36, alignment: .bottom)

            if let first = model.snapshot.modelBreakdown.first {
                Text("\(model.strings.models): \(first.model)")
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }

            Text(model.statusMessage)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 320)
    }

    private func metric(title: String, summary: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(formatTokens(summary.totals.totalTokens))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            Text(formatCost(summary.cost))
                .font(.caption)
                .foregroundStyle(summary.cost.hasUnknownPricing ? .orange : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private func barHeight(_ tokens: Int) -> CGFloat {
        max(4, min(34, CGFloat(tokens) / 200))
    }

    private func formatTokens(_ tokens: Int) -> String {
        tokens.formatted(.number.notation(.compactName))
    }

    private func formatCost(_ cost: CostEstimate) -> String {
        guard let usd = cost.usd else { return model.strings.unknownPricing }
        return "$\(NSDecimalNumber(decimal: usd).doubleValue.formatted(.number.precision(.fractionLength(2))))"
    }
}
```

- [ ] **Step 3: Implement preferences view**

Write `Sources/CodexUsageApp/PreferencesView.swift`:

```swift
import CodexUsageCore
import SwiftUI

struct PreferencesView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Toggle(model.strings.alwaysOnTop, isOn: $model.isAlwaysOnTop)

            Picker(model.strings.refreshInterval, selection: $model.refreshInterval) {
                ForEach(RefreshInterval.allCases, id: \.self) { interval in
                    Text(model.strings.intervalLabel(interval)).tag(interval)
                }
            }

            Picker(model.strings.speedMode, selection: $model.speedMode) {
                Text("Auto").tag(SpeedMode.auto)
                Text("Standard").tag(SpeedMode.standard)
                Text("Fast").tag(SpeedMode.fast)
            }

            TextField(model.strings.codexPath, text: $model.pathOverride)

            Button(model.strings.refresh) {
                model.refresh()
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
```

- [ ] **Step 4: Rebuild and fix compile errors directly reported by Swift**

Run: `swift build`

Expected: PASS. If the compiler reports missing `Observation`, `@Bindable`, or `SettingsLink` availability, keep macOS 14 in `Package.swift` and adjust imports or scene code so the build succeeds on Xcode 26.4.

- [ ] **Step 5: Run full tests**

Run: `swift test`

Expected: PASS.

- [ ] **Step 6: Commit app UI**

```bash
git add Sources/CodexUsageApp Sources/CodexUsageCore Tests
git commit -m "Add macOS usage window"
```

## Task 9: Packaging and Documentation

**Files:**
- Create: `scripts/package-app.sh`
- Create: `README.md`

- [ ] **Step 1: Add packaging script**

Write `scripts/package-app.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/CodexUsage.app"
BIN="$ROOT/.build/release/CodexUsage"

cd "$ROOT"
swift build -c release
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CodexUsage"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>CodexUsage</string>
  <key>CFBundleIdentifier</key>
  <string>local.codexusage.app</string>
  <key>CFBundleName</key>
  <string>CodexUsage</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST
echo "$APP"
```

- [ ] **Step 2: Make script executable**

Run: `chmod +x scripts/package-app.sh`

Expected: command exits with status 0.

- [ ] **Step 3: Add README**

Write `README.md`:

```markdown
# CodexUsage

CodexUsage is a local macOS menu bar app for viewing Codex token usage and estimated cost.

## Features

- Reads only local Codex logs from `CODEX_HOME` or `~/.codex`
- Shows today's usage and current-hour usage
- Estimates known model costs locally
- Supports standard, fast, and auto speed pricing modes
- Supports English and Simplified Chinese based on system language
- Provides a compact floating window that can stay above other windows

## Develop

```bash
swift test
swift run CodexUsage
```

## Package

```bash
./scripts/package-app.sh
open build/CodexUsage.app
```

## Privacy

CodexUsage reads local JSONL logs and does not upload data.
```

- [ ] **Step 4: Verify release package builds**

Run: `./scripts/package-app.sh`

Expected: prints an absolute path ending in `build/CodexUsage.app`.

- [ ] **Step 5: Smoke-run packaged app**

Run: `open build/CodexUsage.app`

Expected: app opens a menu bar item. Open the menu bar item and choose Codex Usage to show the floating window.

- [ ] **Step 6: Commit packaging and docs**

```bash
git add README.md scripts/package-app.sh
git commit -m "Add app packaging instructions"
```

## Task 10: Final Verification

**Files:**
- Read: `docs/superpowers/specs/2026-05-24-codex-usage-macos-design.md`
- Read: `README.md`

- [ ] **Step 1: Run all automated checks**

Run:

```bash
swift test
swift build
./scripts/package-app.sh
```

Expected: all commands exit with status 0.

- [ ] **Step 2: Verify language behavior manually**

Run:

```bash
swift test --filter LocalizationTests
```

Expected: PASS for Chinese preferred language and English fallback.

- [ ] **Step 3: Verify no unrelated dirty files**

Run: `git status --short`

Expected: no output.

- [ ] **Step 4: Verify commits are present**

Run: `git log --oneline --max-count=8`

Expected: recent commits include scaffold, localization, parser, aggregation, UI, packaging, and docs.

- [ ] **Step 5: Final manual smoke test**

Run: `open build/CodexUsage.app`

Expected:

- Menu bar item appears.
- Usage window opens from menu bar.
- Refresh button does not crash.
- Preferences opens.
- Refresh interval, speed mode, path, and always-on-top controls are visible.
- Missing Codex data is shown as a compact status rather than a modal alert.
