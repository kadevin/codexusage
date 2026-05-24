# CodexUsage

CodexUsage is a local macOS menu bar app for viewing Codex token usage and estimated cost.

## Features

- Reads only local Codex logs from `CODEX_HOME` or `~/.codex`
- Lets you choose a custom Codex path in Preferences
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
