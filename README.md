# CodexUsage

[![Build macOS App](https://github.com/kadevin/codexusage/actions/workflows/build.yml/badge.svg)](https://github.com/kadevin/codexusage/actions/workflows/build.yml)

轻量的 macOS 菜单栏应用，一处查看 Codex 官方额度、本地 Token 用量和估算点数。

A local macOS menu bar app for Codex quota, token usage, and estimated credits.

## 安装

需要 **macOS 14 或更高版本**，支持 Apple Silicon 和 Intel Mac。

1. 从 [GitHub Releases](https://github.com/kadevin/codexusage/releases) 下载 `CodexUsage-macOS-universal.zip`。
2. 解压并打开 `CodexUsage.app`。
3. 查看官方额度前，确保本机已安装 Codex CLI 并登录账号。

应用使用 ad-hoc 签名，未经公证；首次启动时，macOS 可能要求在系统设置中允许打开。

## 功能与使用

- **额度与用量**：显示官方额度窗口、今日及本小时的 Token、调用次数、缓存率和估算点数。
- **趋势与明细**：查看最近 24 小时或 7 天的用量；点击日期查看逐小时数据和模型用量。
- **完整日志统计**：涵盖活跃、归档及子代理会话，归档不会使历史用量消失。
- **界面与设置**：支持中英文、系统深浅色和半透明面板；可调整透明度、刷新间隔、计价模式及 Codex 路径。

默认读取 `CODEX_HOME` 或 `~/.codex`，也可在偏好设置中指定路径。

| 指标 | 统计口径 |
| --- | --- |
| Token | 分别展示输入、缓存输入、输出和思考 Token；思考 Token 不重复计价 |
| 调用次数 | 每条去重后的非零 Token 用量事件计为一次调用 |
| 缓存率 | 缓存输入 ÷（缓存输入 + 非缓存输入）；没有输入时显示不可用 |

## 点数估算

**官方额度是账号状态的依据；本地点数仅供估算。** 日志中的计费信息可能不完整，估算值不等同于账单。

以下为应用内置的标准费率，更新于 **2026-11-01**，单位为点数 / 百万 Token：

| 模型 | 输入 | 缓存输入 | 输出 |
| --- | ---: | ---: | ---: |
| GPT-6 Astra | 250 | 25 | 1,250 |
| GPT-6.1 Sol | 50 | 2.5 | 250 |
| GPT-6.1 Terra | 25 | 1.25 | 125 |
| GPT-6 Sol | 50 | 5 | 250 |
| GPT-6 Luna | 2.5 | 0.25 | 12.5 |

- 支持标准、快速和自动模式；自动模式优先使用日志记录的速度档位，缺失时参考本地配置。
- 上述模型的 Fast 模式按订阅内额度的 **2.5 倍**估算，应用不区分购买点数等计费方式。
- 已知与未知模型混用时，仅汇总已知部分，并显示“部分”提示。

费率来源：[Codex 官方计价](https://learn.chatgpt.com/docs/pricing) · [速度模式说明](https://learn.chatgpt.com/docs/agent-configuration/speed)。完整内置费率见 [PricingService.swift](Sources/CodexUsageCore/PricingService.swift)。

<details>
<summary>历史模型与兼容规则</summary>

- 保留 GPT-5.6、GPT-5.5、GPT-5.4 等历史模型费率，用于统计旧日志。
- `gpt-5.6` 按 `gpt-5.6-sol` 计价；`codex-auto-review` 按 `gpt-5.6-luna` 兼容估算。
- `gpt-5.3-codex-spark` 使用项目兼容估算：输入 43.75、缓存输入 4.375、输出 350 点 / 百万 Token，不额外叠加 Fast 倍率。该规则不代表官方 Codex 点数报价。

</details>

## 开发与打包

需要支持 Swift 6 的 macOS 开发环境。在仓库根目录运行：

```bash
# 测试与启动
swift test
swift run CodexUsage

# 构建并打开应用
swift build -c release
PREBUILT_BINARY="$(swift build -c release --show-bin-path)/CodexUsage" ./scripts/package-app.sh
open build/CodexUsage.app
```

[GitHub Actions](.github/workflows/build.yml) 在推送 `main`、提交 PR 或手动触发时运行测试并生成通用应用、ZIP 和 SHA-256 校验文件；推送 `v*` 标签时发布 GitHub Release。

## 隐私与许可

日志在本地读取，不上传内容；官方额度通过本机 Codex CLI 查询已登录账号的状态。

本项目采用 [MIT License](LICENSE)，与 OpenAI 及 [ccusage](https://github.com/ryoppippi/ccusage) 无隶属关系。感谢 ccusage 提供的本地日志分析、Token 拆分及成本估算思路。
