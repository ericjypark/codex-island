# CodexIsland

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-Hant.md) | [हिन्दी](README.hi.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md)

<p align="center">
  <img src="Assets/codexisland-logo.png" width="160" alt="CodexIsland logo">
</p>

> AI の使用上限を、Mac のノッチに。

CodexIsland は、MacBook のノッチを Claude Code と Codex の使用状況を表示する Dynamic Island 風のライブ表示に変える、ネイティブ macOS オーバーレイです。ホバーで 5 時間枠を確認し、クリックで Usage / Cost / Overview の各パネルを開けます。リセット時刻、チャート、ローカルログから推定したコスト、token 履歴を表示します。

無料・オープンソース・未署名で、local-first に設計されています。Claude Code / Claude Desktop と Codex がすでに保存している認証情報を読み取り、各 provider の公式 usage endpoint だけを呼び出します。

## 機能

- **2 つの provider、4 つの枠。** Claude 5h + 7d、Codex 5h + 7d を 1 つのパネルで表示。
- **ノッチに沿う表示。** ノッチ付き Mac ではハードウェアのノッチに合わせ、ノッチなし Mac ではメニューバーの pill 表示に切り替えます。
- **ホバーと展開。** ホバーで 5 時間使用量、クリックで Usage / Cost / Overview を表示。
- **コストと token。** Claude Code / Codex のローカルログから今日と月次の USD コスト、token throughput、trend を推定。
- **複数の表示スタイル。** Usage は Ring / Bar / Stepped / Numeric / Sparkline、Cost は USD / VALUE / TOKENS / TREND。
- **設定。** ログイン時起動、更新間隔、低電力モード、provider 表示、言語、チャート、コスト表示を変更できます。
- **Sparkle 更新。** GitHub Release の appcast を確認し、インストール前に確認します。
- **プライバシー。** テレメトリ、クラッシュ送信、分析、proxy service はありません。

## インストール

### Homebrew

```sh
brew install --cask ericjypark/tap/codexisland
```

初回実行時に `ericjypark/homebrew-tap` が自動で tap されます。CodexIsland は Apple 署名されていないため、cask が Gatekeeper quarantine を削除します。更新の検証は Sparkle が行います。

### 直接ダウンロード

[Releases](https://github.com/ericjypark/codex-island/releases) から `CodexIsland-X.Y.Z.dmg` をダウンロードし、app を `/Applications` にドラッグしてから実行します。

```sh
xattr -dr com.apple.quarantine /Applications/CodexIsland.app
```

Terminal を使わない場合は、一度 app を開いて macOS にブロックさせた後、**システム設定 -> プライバシーとセキュリティ** の下部で **このまま開く** を選びます。

## 初回起動

CodexIsland は password や API key を求めません。Codex では `~/.codex/auth.json` を読みます。Claude では `CLAUDE_CODE_OAUTH_TOKEN`、Keychain の `Claude Code-credentials`、Anthropic OAuth refresh flow を順に試します。

Codex の認証がない場合は `no codex auth`、Claude の認証がない場合は `auth required — run claude` と表示されます。

## 使い方

- ノッチにホバーして 5 時間使用量を確認します。
- Island をクリックしてフルパネルを開きます。
- 横スワイプまたは dots で **Usage**、**Cost**、**Overview** を切り替えます。
- 展開パネルで Command-click すると表示スタイルを切り替えます。
- 同期ステータスをクリックするとすぐに更新します。
- 歯車アイコンから設定を開きます。

## 設定

設定画面はカスタム `NSWindow` です。主な設定は UserDefaults に保存されます：チャートスタイル `MacIsland.chartStyle`、コスト表示 `MacIsland.costStyle`、トークン集計 `MacIsland.tokenCountMode`、更新間隔 `MacIsland.refreshInterval`、低電力モード `MacIsland.lowPowerMode`、言語設定 `MacIsland.appLanguage`。

言語の初期値は `Auto` で、macOS の言語に従います。手動で言語を選ぶこともでき、変更後は今すぐ再起動するか、あとで手動再起動できます。

## ソースからビルド

macOS 13+ と Xcode / Command Line Tools の Swift toolchain が必要です。

```sh
git clone https://github.com/ericjypark/codex-island
cd codex-island
./build.sh
open build/CodexIsland.app
```

スモークテスト:

```sh
./scripts/verify.sh
```

## リリース

```sh
npm install --global create-dmg
./release.sh
```

`v*` tag を push すると GitHub Actions が DMG をビルドし、checksum を計算して GitHub Release を公開します。token が設定されていれば Homebrew cask も同期されます。

## プライバシー

CodexIsland は telemetry、analytics、crash reporting、proxy server を持ちません。Codex token は local の `~/.codex/auth.json` から読み取り、Claude の認証情報は environment、Keychain、または公式 OAuth flow だけを使います。
