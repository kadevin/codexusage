# CodexUsage

[![Build macOS App](https://github.com/kadevin/codexusage/actions/workflows/build.yml/badge.svg)](https://github.com/kadevin/codexusage/actions/workflows/build.yml)

CodexUsage is a local macOS menu bar app for viewing official Codex quota windows, local token usage, and estimated Codex credits.

CodexUsage 是一个本地 macOS 菜单栏应用，用来查看 Codex 官方额度窗口、本地 token 用量和估算 Codex 点数。

## Features / 功能

- Reads only local Codex logs from `CODEX_HOME` or `~/.codex`.
  仅读取 `CODEX_HOME` 或 `~/.codex` 中的本地 Codex 日志。
- Reads official quota windows through the local Codex CLI and keeps them visually separate from local log estimates.
  通过本地 Codex CLI 读取官方额度窗口，并与本地日志估算结果分开展示。
- Includes both active and archived session logs, so archiving a conversation does not remove its usage from totals.
  同时统计活跃和已归档的会话日志，归档会话不会导致用量从汇总中消失。
- Lets you choose a custom Codex path in Preferences.
  可在偏好设置中指定自定义 Codex 路径。
- Shows today's usage and current-hour usage.
  展示今日用量和当前小时用量。
- Includes Codex subagent session logs so delegated and background work is reflected in usage totals.
  统计 Codex 子代理 session 日志，让委派及后台任务消耗计入用量汇总。
- Breaks totals down into input, cached input, output, and reasoning tokens when present.
  按输入、缓存输入、输出和思考 token 拆分用量。
- Counts each deduplicated, non-zero token usage event as one model call across summaries and trend details.
  将每条去重后的非零 Token 用量事件计为一次模型调用，并在汇总和趋势详情中展示。
- Shows cache rate as cached input divided by cached plus uncached input; periods without input display an unavailable value.
  缓存率按“缓存输入 /（缓存输入 + 非缓存输入）”计算；没有输入 Token 的时段显示为不可用。
- Optionally shows 24-hour and 7-day trend tables, sorted from newest to oldest.
  可选显示 24 小时和 7 天趋势表，并按最新到最早排序。
- Click a date in the 7-day trend to inspect exact token categories, all 24 hourly buckets, model usage, and estimated credits.
  点击 7 天趋势中的日期，可查看精确 Token 分类、完整 24 小时分布、模型用量和估算点数。
- Estimates Codex credits locally using the current official model rate card, including documented standard, fast, and auto speed modes.
  按照当前官方模型费率表在本地估算 Codex 点数，支持官方已说明的标准、快速和自动速度模式。
- Uses a titleless translucent panel that follows the system light or dark appearance.
  使用无标题半透明面板，并自动适配系统亮色或暗色主题。
- Lets you adjust panel opacity in Preferences.
  可在偏好设置中调整面板透明度。
- Supports English and Simplified Chinese based on system language.
  根据系统语言自动显示英文或简体中文。

## Pricing Data / 计价数据

Credit estimates use OpenAI's current [Codex pricing rate card](https://learn.chatgpt.com/docs/pricing). Fast mode follows the supported models and multipliers documented in [Codex speed settings](https://learn.chatgpt.com/docs/agent-configuration/speed).

点数估算采用 OpenAI 当前的 [Codex 官方费率表](https://learn.chatgpt.com/docs/pricing)。快速模式仅按照 [Codex 速度设置](https://learn.chatgpt.com/docs/agent-configuration/speed)中明确支持的模型和倍率计算。

GPT-6 Astra (`gpt-6-astra`) uses 250 input, 25 cached input, and 1,250 output credits per million tokens, with a 2.5× Fast multiplier. Standard, Fast, and Auto modes are supported.

GPT-6 Astra（`gpt-6-astra`）每百万 Token 的输入、缓存输入和输出分别按 250、25 和 1,250 点估算，Fast 模式为 2.5 倍，支持标准、快速和自动速度模式。

CodexUsage estimates the internal `codex-auto-review` label using the `gpt-5.6-luna` rate. This is a project-level compatibility rule because no separate official rate is published for that label.

CodexUsage 将内部的 `codex-auto-review` 标签按照 `gpt-5.6-luna` 费率估算。这是项目的兼容规则，因为官方没有为该标签单独公布费率。

OpenAI lists `gpt-5.3-codex-spark` as a research preview with a separate usage limit and does not publish numeric Codex credit rates for it. CodexUsage uses a compatibility estimate derived from the published GPT-5.3-Codex API rates: 43.75 input, 4.375 cached input, and 350 output credits per million tokens, without an additional Fast multiplier. The official Spark quota remains authoritative.

OpenAI 将 `gpt-5.3-codex-spark` 列为采用独立额度的研究预览模型，未公布明确的 Codex 点数费率。CodexUsage 根据已公布的 GPT-5.3-Codex API 费率进行兼容推算：每百万 Token 的输入、缓存输入和输出分别按 43.75、4.375 和 350 点计算，不再额外叠加 Fast 倍率。Spark 的实际额度仍以官方额度为准。

Local JSONL logs do not currently expose a reliable billing-mode marker for every event. CodexUsage therefore labels token-derived credits as local estimates; use the official quota section as the authoritative allowance status.

本地 JSONL 日志目前并非每条记录都包含可靠的计费模式标记。因此，CodexUsage 将基于 token 推算的点数明确标为本地估算；额度状态应以“官方额度”区域为准。

## Install / 安装

Download the latest `CodexUsage-macOS-universal.zip` from [GitHub Releases](https://github.com/kadevin/codexusage/releases), unzip it, then open `CodexUsage.app`. The universal build supports Apple Silicon and Intel Macs.

从 [GitHub Releases](https://github.com/kadevin/codexusage/releases) 下载最新的 `CodexUsage-macOS-universal.zip`，解压后打开 `CodexUsage.app`。通用构建同时支持 Apple Silicon 与 Intel Mac。

The CI build uses an ad-hoc signature and is not notarized. macOS may require you to allow the app in System Settings after first launch.

CI 构建产物使用 ad-hoc 签名，且未经公证。首次启动时，macOS 可能需要你在系统设置中允许打开。

## Develop / 开发

```bash
swift test
swift run CodexUsage
```

## Package / 打包

```bash
./scripts/package-app.sh
open build/CodexUsage.app
```

The packaging script builds the release executable, generates the app icon programmatically, writes `Info.plist`, and produces `build/CodexUsage.app`.

打包脚本会构建 release 可执行文件，程序化生成 app 图标，写入 `Info.plist`，并输出 `build/CodexUsage.app`。

## GitHub CI/CD / GitHub 自动构建

This repository includes `.github/workflows/build.yml`.

本仓库包含 `.github/workflows/build.yml`。

The workflow runs on GitHub-hosted macOS runners and performs:

工作流使用 GitHub 托管的 macOS runner，并执行：

1. `swift test`
2. `./scripts/package-app.sh`
3. Build native Apple Silicon and Intel executables on matching GitHub runners
4. Merge them into a universal app and verify both architectures
5. Upload the zip and SHA-256 checksum as workflow artifacts
6. Publish a GitHub Release when a `v*` tag is pushed

It runs on pushes to `main`, pull requests targeting `main`, manual `workflow_dispatch` runs, and `v*` tag pushes. Push a version tag such as `v0.1.1` to publish a release automatically.

它会在推送到 `main`、向 `main` 发起 Pull Request、手动触发 `workflow_dispatch`、以及推送 `v*` 版本 tag 时运行。推送类似 `v0.1.1` 的版本 tag 会自动发布 GitHub Release。

## Privacy / 隐私

CodexUsage reads local JSONL logs without uploading their contents. The official quota section asks the installed Codex CLI for the signed-in account's current rate-limit status.

CodexUsage 只读取本地 JSONL 日志，不上传日志内容。“官方额度”区域会通过已安装的 Codex CLI 查询当前登录账号的额度状态。

## Open Source / 开源信息

CodexUsage is released under the MIT License. See [LICENSE](LICENSE).

CodexUsage 使用 MIT License 开源，详见 [LICENSE](LICENSE)。

This project is independently implemented in Swift for macOS. It is not affiliated with OpenAI or the ccusage project.

本项目是面向 macOS 的 Swift 独立实现，与 OpenAI 或 ccusage 项目没有隶属关系。

## Acknowledgements / 致谢

Thanks to the original [ccusage](https://github.com/ryoppippi/ccusage) project and its documentation for the local-log usage analysis model, Codex data-source behavior, token breakdown ideas, and cost-estimation references.

感谢原始 [ccusage](https://github.com/ryoppippi/ccusage) 项目及其文档提供的本地日志用量分析模型、Codex 数据源行为、token 拆分思路和成本估算参考。
