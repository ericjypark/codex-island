# CodexIsland

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-Hant.md) | [हिन्दी](README.hi.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md)

<p align="center">
  <img src="Assets/codexisland-logo.png" width="160" alt="CodexIsland logo">
</p>

> 你的 AI 用量限額，住在 Mac 劉海裡。

CodexIsland 是原生 macOS 懸浮工具，會把 MacBook 劉海變成類似 Dynamic Island 的 Claude Code 與 Codex 用量狀態。它可以在懸停時預覽 5 小時用量，點擊後展開 Usage、Cost、Overview 面板，顯示重置時間、圖表、成本估算與本機 token 歷史。

CodexIsland 免費、開源、未經 Apple 簽署，並採本機優先設計。它只讀取 Claude Code / Claude Desktop 與 Codex 已寫入本機的憑證，並呼叫對應服務自己的用量 API。

## 功能

- **兩個服務，四個窗口。** Claude 5 小時 + 7 天、Codex 5 小時 + 7 天集中在一個面板。
- **貼合劉海。** 有劉海的 Mac 會對齊硬體劉海；沒有劉海的 Mac 會使用選單列膠囊。
- **懸停預覽，點擊展開。** 快速查看 5 小時用量，也可展開查看 Usage / Cost / Overview。
- **成本與 token。** 從本機 Claude Code 與 Codex 日誌估算今天與本月至今的美元成本、token 吞吐量與趨勢。
- **多種視覺樣式。** Usage 支援 Ring、Bar、Stepped、Numeric、Sparkline；Cost 支援 USD、VALUE、TOKENS、TREND。
- **可調整設定。** 支援登入時啟動、重新整理間隔、低耗電模式、服務顯示、語言、圖表與成本樣式。
- **Sparkle 更新。** 啟動時與每日檢查 GitHub Release appcast，安裝前會詢問。
- **隱私本機優先。** 沒有遙測、崩潰回報、第三方分析或代理服務。

## 安裝

### Homebrew

```sh
brew install --cask ericjypark/tap/codexisland
```

首次執行會自動 tap `ericjypark/homebrew-tap`。因為 CodexIsland 沒有 Apple 簽署，cask 會自動移除 Gatekeeper quarantine 屬性；更新驗證由 Sparkle 處理。

### 直接下載

從 [Releases](https://github.com/ericjypark/codex-island/releases) 下載 `CodexIsland-X.Y.Z.dmg`，拖到 `/Applications`，然後執行：

```sh
xattr -dr com.apple.quarantine /Applications/CodexIsland.app
```

不想使用終端機時，先嘗試開啟 app，然後到 **系統設定 -> 隱私權與安全性** 底部選擇 **仍要打開**。

## 首次執行

CodexIsland 不會要求密碼或 API key。Codex 會讀取 `~/.codex/auth.json`；Claude 會依序嘗試 `CLAUDE_CODE_OAUTH_TOKEN`、Keychain 中的 `Claude Code-credentials`，以及 Anthropic OAuth refresh 流程。

如果缺少 Codex 憑證，面板會顯示 `no codex auth`。如果 Claude 憑證不可用，面板會顯示 `auth required — run claude`。

## 使用

- 懸停劉海可預覽 5 小時用量。
- 點擊島可展開完整面板。
- 水平滑動或點擊底部圓點，在 **Usage**、**Cost**、**Overview** 間切換。
- Command 點擊展開面板可切換目前頁面的視覺樣式。
- 點擊同步狀態可立即重新整理。
- 點擊左下角齒輪開啟 Settings。

## 設定

設定視窗是自訂 `NSWindow`，不是系統 Settings scene。偏好會存到 UserDefaults，例如：圖表樣式 `MacIsland.chartStyle`、成本樣式 `MacIsland.costStyle`、token 統計 `MacIsland.tokenCountMode`、重新整理間隔 `MacIsland.refreshInterval`、低耗電模式 `MacIsland.lowPowerMode`、語言覆蓋 `MacIsland.appLanguage`。

語言預設為 Auto，會跟隨 macOS。也可以手動選擇語言；選擇後可立即重啟生效，或稍後自行重啟。

## 從原始碼建置

需要 macOS 13+ 與 Xcode / Command Line Tools 的 Swift 工具鏈。

```sh
git clone https://github.com/ericjypark/codex-island
cd codex-island
./build.sh
open build/CodexIsland.app
```

原生 app 冒煙測試：

```sh
./scripts/verify.sh
```

## 發布

```sh
npm install --global create-dmg
./release.sh
```

推送 `v*` tag 會觸發 GitHub Actions，在 macOS runner 上建置 DMG、計算 checksum、發布 GitHub Release，並在設定 token 時同步 Homebrew cask。

## 隱私

CodexIsland 沒有 app 遙測、分析、崩潰回報或代理伺服器。Codex token 只從本機 `~/.codex/auth.json` 讀取；Claude 憑證只從環境變數、Keychain 或官方 OAuth 流程取得。
