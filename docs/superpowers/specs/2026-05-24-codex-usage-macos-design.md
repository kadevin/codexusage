# Codex Usage macOS App Design

Date: 2026-05-24

## Goal

Build an independent macOS app that extracts only the Codex usage reporting behavior from ccusage and presents it as a small always-on-top utility window.

The app should help a Codex user answer two questions quickly:

- How much Codex have I used today?
- How much Codex have I used this hour, and what is the estimated cost?

The app is local-only. It reads Codex logs from disk, computes usage and estimated cost on the Mac, and does not upload usage data.

## Non-Goals

- Do not build a general ccusage clone.
- Do not support Claude Code, OpenCode, Amp, Gemini, or other sources.
- Do not require a local web server.
- Do not depend on ccusage as a shell command at runtime.
- Do not show cloud billing or scrape provider dashboards.
- Do not estimate token counts from prompt text.

## Product Shape

The app is a native SwiftUI macOS menu bar app with a compact floating window.

Core surfaces:

- Menu bar icon for opening and hiding the usage window.
- Floating usage window sized around 320 x 220 points by default.
- Preferences window for refresh interval, Codex data path, speed pricing mode, and always-on-top behavior.

Window behavior:

- The usage window can stay above normal windows.
- The user can hide it back to the menu bar.
- The app remembers window position, topmost setting, refresh interval, selected Codex path, and speed pricing mode.
- The app remains useful as a lightweight utility, not a dashboard page.

## User Interface

The main floating window uses a compact tool UI, not a marketing layout.

Visible regions:

- Header: `Codex Usage`, last refresh time, manual refresh button.
- Primary metrics:
  - Today: total tokens and estimated USD cost from local midnight to now.
  - This Hour: total tokens and estimated USD cost from the current hour start to now.
- Secondary region:
  - Small recent 24-hour strip or list showing hourly token totals.
  - Model breakdown for the selected current scope, sorted by cost or total tokens.
- Footer:
  - Active data path.
  - Status text for loading, no data, stale data, unknown pricing, or parse errors.
  - Preferences entry.

Controls:

- Refresh button.
- Toggle for always-on-top in Preferences.
- Refresh interval picker: 15 seconds, 30 seconds, 60 seconds, 5 minutes.
- Speed pricing picker: auto, standard, fast.
- Codex path selector with default `${CODEX_HOME}` or `~/.codex`.

Localization:

- Support English and Simplified Chinese UI text in the first release.
- Detect the system language automatically at launch.
- Use Chinese when the preferred system language starts with `zh`; otherwise use English.
- Keep all user-facing strings behind a localization layer so parser, pricing, and aggregation code do not contain UI copy.

## Data Source

Default source resolution:

1. If `CODEX_HOME` is set, use it.
2. Otherwise use `~/.codex`.
3. Allow the user to override the path in Preferences.

Supported path forms:

- A Codex home directory containing `sessions/`.
- A direct directory of JSONL files exported or archived from Codex.
- A comma-separated list is not required in the first UI version, but the parser should not make that impossible later.

Codex logs:

- Read JSONL files under Codex session locations.
- Parse entries relevant to Codex token accounting.
- Use `turn_context` metadata to associate token events with a model when available.
- Use `event_msg` entries where `payload.type` is `token_count` as cumulative token counters.
- Convert cumulative counters into per-turn deltas before aggregation.

If a log entry does not expose usable token counts, the app ignores it and records a debug-level parse note. It must not infer token counts from text.

## Usage Model

Internal normalized event shape:

```swift
struct CodexUsageEvent {
    let sessionId: String
    let timestamp: Date
    let model: String
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let reasoningTokens: Int
    let totalTokens: Int
    let sourceFile: URL
}
```

Aggregation scopes:

- Today: start of local calendar day to now.
- This hour: start of current local hour to now.
- Recent hours: 24 hourly buckets ending at the current hour.
- Model breakdown: grouped by model within the visible scope.

Timezone:

- Use the Mac's current local timezone for day and hour grouping.
- Future versions can add a timezone override if needed.

## Cost Model

The app estimates cost from token counts and model pricing.

Pricing rules:

- Keep an internal pricing table for common Codex/OpenAI models.
- Track separate prices for input, cached input, and output where available.
- Treat reasoning tokens as part of output accounting unless a model-specific rule says otherwise.
- Unknown models still display token counts and show cost as unknown instead of pretending accuracy.

Speed pricing:

- `auto`: inspect Codex `config.toml` in the selected Codex home. Treat `service_tier = "priority"` or legacy `service_tier = "fast"` as fast mode.
- `standard`: use standard prices.
- `fast`: use fast prices or a model-specific multiplier. If no multiplier is known, use a 2x fallback multiplier and mark the estimate source as fallback.

The UI must disclose when costs are estimates or when any model has unknown pricing.

## Refresh Behavior

Refresh triggers:

- App launch.
- Floating window open.
- Manual refresh.
- Timer based on selected interval.
- Best-effort file-system change notification using macOS file observation. This is helpful but not required for first-release correctness because timer refresh remains the source of truth.

Default interval:

- 60 seconds.

Performance strategy:

- Maintain a file index with path, size, modification time, and last parsed byte offset where safe.
- Re-read only changed files when possible.
- Fall back to full parse if a file shrinks, rotates, or the parser detects invalid incremental state.
- Keep parsing off the main actor.
- Publish a single immutable snapshot to SwiftUI after each refresh.

Refresh result states:

- Loaded with data.
- No Codex data found.
- Path not found or not readable.
- Partial parse warnings.
- Unknown pricing warnings.

## Architecture

Proposed modules:

- `CodexUsageApp`: SwiftUI app entry, menu bar scene, window setup.
- `UsageWindowController`: manages floating window visibility and topmost behavior.
- `PreferencesStore`: stores refresh interval, path override, speed mode, topmost preference, and window state.
- `Localization`: resolves English or Simplified Chinese strings from the system language.
- `CodexPathResolver`: resolves environment and user-selected data paths.
- `CodexLogStore`: discovers JSONL files and tracks incremental file metadata.
- `CodexUsageParser`: parses Codex JSONL records into normalized usage events.
- `UsageAggregator`: groups events into today, current hour, recent hours, and model breakdown.
- `PricingService`: maps model and speed mode to estimated cost.
- `RefreshScheduler`: owns timer, file-change triggers, cancellation, and refresh task lifecycle.
- `UsageView`: compact SwiftUI floating window UI.
- `PreferencesView`: simple settings surface.

State ownership:

- Root app owns a single observable app model.
- Parsing and aggregation services are injected into the app model.
- SwiftUI views receive immutable snapshots and send user intents back to the model.

## Error Handling

Errors should be visible but compact:

- Missing path: show `No Codex data found` and the path checked.
- Permission problem: show `Path is not readable`.
- Unknown model price: show token totals and mark cost as unknown or partial.
- Parse failures: skip malformed records, count warnings, and continue with valid data.

The app should avoid modal alerts for routine data problems. Preferences can show more detail for path and pricing diagnostics.

## Testing Strategy

Unit tests:

- Parse token_count JSONL records.
- Convert cumulative counters to deltas.
- Associate events with model context.
- Aggregate by local day and hour.
- Calculate costs for standard, fast, and unknown models.
- Resolve paths from environment and preferences.
- Resolve English and Simplified Chinese localized strings from preferred system languages.

Fixture tests:

- Include small redacted Codex JSONL fixtures.
- Include a legacy or missing-model fixture to verify graceful handling.
- Include file-growth fixture for incremental parsing.

UI tests or manual verification:

- Launch app and open the floating window.
- Toggle always-on-top.
- Change refresh interval.
- Select a custom Codex path.
- Confirm manual refresh updates displayed values.
- Confirm the UI uses Chinese when the preferred language is Chinese and English otherwise.

Build verification:

- Build with Xcode or `xcodebuild`.
- Run unit tests.
- Smoke-test the app on macOS.

## First Release Scope

The first release is complete when:

- A native macOS app builds and launches.
- Menu bar entry opens a compact floating usage window.
- The window can be kept always on top.
- The app reads Codex logs from `${CODEX_HOME}` or `~/.codex`.
- It displays today's usage and current-hour usage.
- It shows estimated cost for known models.
- It refreshes manually and on a timer.
- Preferences persist path, refresh interval, speed mode, and topmost behavior.
- It automatically displays English or Simplified Chinese based on the Mac system language.
- Unknown pricing and missing data are represented honestly.

## Open Risks

- Codex log format is still evolving, so the parser must be defensive.
- Cost estimates may drift when model pricing changes.
- Some historical Codex logs may not contain enough model metadata.
- File-system watching may not catch all archive or external-volume changes, so timer refresh remains required.

## Decisions Confirmed

- Build as a native SwiftUI macOS application.
- Support only Codex usage.
- Prioritize a small topmost utility window.
- Support daily and hourly usage/cost refresh.
- Support English and Simplified Chinese with automatic system language detection.
- Keep all parsing and calculation local.
