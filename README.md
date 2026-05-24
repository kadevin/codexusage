# CodexUsage

[![Build macOS App](https://github.com/kadevin/codexusage/actions/workflows/build.yml/badge.svg)](https://github.com/kadevin/codexusage/actions/workflows/build.yml)

CodexUsage is a local macOS menu bar app for viewing Codex token usage and estimated cost.

CodexUsage 是一个本地 macOS 菜单栏应用，用来查看 Codex token 用量和估算成本。

## Features / 功能

- Reads only local Codex logs from `CODEX_HOME` or `~/.codex`.
  仅读取 `CODEX_HOME` 或 `~/.codex` 中的本地 Codex 日志。
- Lets you choose a custom Codex path in Preferences.
  可在偏好设置中指定自定义 Codex 路径。
- Shows today's usage and current-hour usage.
  展示今日用量和当前小时用量。
- Breaks totals down into input, cached input, output, and reasoning tokens when present.
  按输入、缓存输入、输出和思考 token 拆分用量。
- Optionally shows 24-hour and 7-day trend tables, sorted from newest to oldest.
  可选显示 24 小时和 7 天趋势表，并按最新到最早排序。
- Estimates known model costs locally, including standard, fast, and auto speed pricing modes.
  本地估算已知模型成本，支持标准、快速和自动速度计价模式。
- Uses a titleless translucent panel that follows the system light or dark appearance.
  使用无标题半透明面板，并自动适配系统亮色或暗色主题。
- Lets you adjust panel opacity in Preferences.
  可在偏好设置中调整面板透明度。
- Supports English and Simplified Chinese based on system language.
  根据系统语言自动显示英文或简体中文。

## Install / 安装

Download the latest GitHub Actions artifact from the [Build macOS App workflow](https://github.com/kadevin/codexusage/actions/workflows/build.yml), unzip it, then open `CodexUsage.app`.

从 [Build macOS App 工作流](https://github.com/kadevin/codexusage/actions/workflows/build.yml) 下载最新构建产物，解压后打开 `CodexUsage.app`。

The CI build is unsigned. macOS may require you to allow the app in System Settings after first launch.

CI 构建产物未签名。首次启动时，macOS 可能需要你在系统设置中允许打开。

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
3. Zip `build/CodexUsage.app`
4. Upload the zip as a workflow artifact

It runs on pushes to `main`, pull requests targeting `main`, and manual `workflow_dispatch` runs.

它会在推送到 `main`、向 `main` 发起 Pull Request、以及手动触发 `workflow_dispatch` 时运行。

## Privacy / 隐私

CodexUsage reads local JSONL logs and does not upload usage data.

CodexUsage 只读取本地 JSONL 日志，不上传用量数据。

## Open Source / 开源信息

CodexUsage is released under the MIT License. See [LICENSE](LICENSE).

CodexUsage 使用 MIT License 开源，详见 [LICENSE](LICENSE)。

This project is independently implemented in Swift for macOS. It is not affiliated with OpenAI or the ccusage project.

本项目是面向 macOS 的 Swift 独立实现，与 OpenAI 或 ccusage 项目没有隶属关系。

## Acknowledgements / 致谢

Thanks to the original [ccusage](https://github.com/ryoppippi/ccusage) project and its documentation for the local-log usage analysis model, Codex data-source behavior, token breakdown ideas, and cost-estimation references.

感谢原始 [ccusage](https://github.com/ryoppippi/ccusage) 项目及其文档提供的本地日志用量分析模型、Codex 数据源行为、token 拆分思路和成本估算参考。
