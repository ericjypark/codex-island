# CodexIsland

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-Hant.md) | [हिन्दी](README.hi.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md)

<p align="center">
  <img src="Assets/codexisland-logo.png" width="160" alt="CodexIsland logo">
</p>

> Mac 노치에 머무는 AI 사용 한도.

CodexIsland는 MacBook 노치를 Claude Code와 Codex 사용량을 보여주는 Dynamic Island 스타일의 네이티브 macOS 오버레이로 바꿉니다. 호버하면 5시간 사용량을 빠르게 볼 수 있고, 클릭하면 Usage / Cost / Overview 패널이 열립니다. 리셋 시간, 차트, 로컬 로그 기반 비용 추정, token 기록을 확인할 수 있습니다.

무료 오픈소스 앱이며 Apple 서명은 없습니다. local-first 방식으로 동작하며 Claude Code / Claude Desktop과 Codex가 이미 로컬에 저장한 인증 상태를 읽고 각 provider의 공식 usage endpoint만 호출합니다.

## 기능

- **두 provider, 네 window.** Claude 5h + 7d, Codex 5h + 7d를 한 패널에서 표시합니다.
- **노치에 맞춘 오버레이.** 노치가 있는 Mac에서는 하드웨어 노치에 맞추고, 노치가 없는 Mac에서는 메뉴 막대 pill로 표시합니다.
- **호버와 확장.** 호버로 5시간 사용량을 보고 클릭으로 Usage / Cost / Overview를 엽니다.
- **비용과 token.** Claude Code와 Codex 로컬 로그에서 오늘 및 이번 달 USD 비용, token throughput, trend를 추정합니다.
- **여러 시각화.** Usage는 Ring / Bar / Stepped / Numeric / Sparkline, Cost는 USD / VALUE / TOKENS / TREND를 지원합니다.
- **설정.** 로그인 시 실행, 새로고침 간격, 저전력 모드, provider 표시, 언어, 차트와 비용 스타일을 조정합니다.
- **Sparkle 업데이트.** GitHub Release appcast를 확인하고 설치 전 사용자에게 묻습니다.
- **개인정보 보호.** telemetry, crash reporting, analytics, proxy service가 없습니다.

## 설치

### Homebrew

```sh
brew install --cask ericjypark/tap/codexisland
```

처음 실행하면 `ericjypark/homebrew-tap`을 자동으로 tap합니다. CodexIsland는 Apple 서명이 없기 때문에 cask가 Gatekeeper quarantine 속성을 제거합니다. 업데이트 검증은 Sparkle이 담당합니다.

### 직접 다운로드

[Releases](https://github.com/ericjypark/codex-island/releases)에서 `CodexIsland-X.Y.Z.dmg`를 내려받고 앱을 `/Applications`로 드래그한 뒤 실행합니다.

```sh
xattr -dr com.apple.quarantine /Applications/CodexIsland.app
```

Terminal을 쓰고 싶지 않다면 앱을 한 번 열어 macOS가 차단하게 한 다음, **시스템 설정 -> 개인정보 보호 및 보안** 아래에서 **그래도 열기**를 선택합니다.

## 첫 실행

CodexIsland는 password나 API key를 묻지 않습니다. Codex는 `~/.codex/auth.json`을 읽고, Claude는 `CLAUDE_CODE_OAUTH_TOKEN`, Keychain의 `Claude Code-credentials`, Anthropic OAuth refresh flow를 차례로 시도합니다.

Codex 인증이 없으면 `no codex auth`, Claude 인증이 없으면 `auth required — run claude`가 표시됩니다.

## 사용법

- 노치에 호버해 현재 5시간 사용량을 봅니다.
- Island를 클릭해 전체 패널을 엽니다.
- 가로 스와이프 또는 하단 dots로 **Usage**, **Cost**, **Overview**를 전환합니다.
- 펼친 패널에서 Command-click으로 현재 화면의 시각화를 바꿉니다.
- 동기화 상태를 클릭해 즉시 새로고침합니다.
- 왼쪽 아래 톱니바퀴로 설정을 엽니다.

## 설정

설정 창은 사용자 정의 `NSWindow`입니다. 주요 설정은 UserDefaults에 저장됩니다: 차트 스타일 `MacIsland.chartStyle`, 비용 표시 `MacIsland.costStyle`, 토큰 집계 `MacIsland.tokenCountMode`, 새로고침 간격 `MacIsland.refreshInterval`, 저전력 모드 `MacIsland.lowPowerMode`, 언어 설정 `MacIsland.appLanguage`.

언어 기본값은 `Auto`이며 macOS 언어를 따릅니다. 수동으로 언어를 선택할 수도 있고, 변경 후 지금 재시작하거나 나중에 직접 재시작할 수 있습니다.

## 소스에서 빌드

macOS 13+와 Xcode / Command Line Tools의 Swift toolchain이 필요합니다.

```sh
git clone https://github.com/ericjypark/codex-island
cd codex-island
./build.sh
open build/CodexIsland.app
```

스모크 테스트:

```sh
./scripts/verify.sh
```

## 릴리스

```sh
npm install --global create-dmg
./release.sh
```

`v*` tag를 push하면 GitHub Actions가 DMG를 빌드하고 checksum을 계산한 뒤 GitHub Release를 게시합니다. token이 설정되어 있으면 Homebrew cask도 동기화합니다.

## 개인정보

CodexIsland는 telemetry, analytics, crash reporting, proxy server가 없습니다. Codex token은 local `~/.codex/auth.json`에서만 읽고, Claude 인증 정보는 environment, Keychain, 공식 OAuth flow만 사용합니다.
