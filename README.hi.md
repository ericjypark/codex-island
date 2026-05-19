# CodexIsland

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-Hant.md) | [हिन्दी](README.hi.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md)

<p align="center">
  <img src="Assets/codexisland-logo.png" width="160" alt="CodexIsland logo">
</p>

> आपकी AI usage limits, आपके Mac notch में।

CodexIsland एक native macOS overlay है जो MacBook notch को Claude Code और Codex usage limits के लिए Dynamic-Island-जैसी live activity बना देता है। Hover करने पर 5-hour usage दिखता है; click करने पर Usage, Cost और Overview panels खुलते हैं, जिनमें reset time, charts, local log-based cost estimate और token history दिखती है।

App free, open source, unsigned और local-first है। यह Claude Code / Claude Desktop और Codex द्वारा पहले से local machine पर रखे गए credentials पढ़ता है, और सिर्फ providers के अपने usage endpoints को call करता है।

## विशेषताएँ

- **Two providers, four windows.** Claude 5h + 7d और Codex 5h + 7d एक panel में।
- **Notch-native overlay.** Notched Mac पर hardware notch के साथ align होता है; non-notched Mac पर menu-bar pill बनता है।
- **Hover और expand.** Hover पर quick 5-hour usage; click पर full Usage / Cost / Overview panels।
- **Cost और tokens.** Local Claude Code और Codex logs से आज और month-to-date USD cost, token throughput और trend estimate करता है।
- **Multiple visual styles.** Usage में Ring, Bar, Stepped, Numeric, Sparkline; Cost में USD, VALUE, TOKENS, TREND।
- **Settings.** Launch at Login, refresh interval, Low Power Mode, providers, language, chart style और cost style।
- **Sparkle updates.** GitHub Release appcast check करता है और install से पहले पूछता है।
- **Local-first privacy.** App telemetry, crash reporting, analytics या proxy service नहीं।

## इंस्टॉल करें

### Homebrew

```sh
brew install --cask ericjypark/tap/codexisland
```

पहली बार command चलाने पर `ericjypark/homebrew-tap` auto-tap होगा। CodexIsland Apple-signed नहीं है, इसलिए cask Gatekeeper quarantine हटाता है; update verification Sparkle करता है।

### सीधे डाउनलोड

[Releases](https://github.com/ericjypark/codex-island/releases) से `CodexIsland-X.Y.Z.dmg` download करें, app को `/Applications` में drag करें, फिर चलाएं:

```sh
xattr -dr com.apple.quarantine /Applications/CodexIsland.app
```

Terminal नहीं इस्तेमाल करना चाहते तो app open करने की कोशिश करें, फिर **System Settings -> Privacy & Security** में नीचे CodexIsland message पर **Open Anyway** चुनें।

## पहली बार चलाना

CodexIsland password या API key नहीं मांगता। Codex के लिए यह `~/.codex/auth.json` पढ़ता है। Claude के लिए यह `CLAUDE_CODE_OAUTH_TOKEN`, Keychain item `Claude Code-credentials`, और Anthropic OAuth refresh flow try करता है।

Codex auth missing हो तो panel `no codex auth` दिखाता है। Claude auth missing हो तो `auth required — run claude` दिखता है।

## उपयोग

- Notch पर hover करें और 5-hour usage देखें।
- Island पर click करके full panel खोलें।
- Horizontal swipe या indicator dots से **Usage**, **Cost**, **Overview** बदलें।
- Expanded panel पर Command-click करके active screen का visualization बदलें।
- Sync status पर click करके तुरंत refresh करें।
- Gear icon से सेटिंग्स खोलें।

## सेटिंग्स

सेटिंग्स एक custom `NSWindow` में खुलती हैं। Preferences UserDefaults में रखे जाते हैं: chart style `MacIsland.chartStyle`, cost style `MacIsland.costStyle`, token counting `MacIsland.tokenCountMode`, refresh interval `MacIsland.refreshInterval`, Low Power Mode `MacIsland.lowPowerMode`, और language override `MacIsland.appLanguage`।

Language का default `Auto` है, यानी app macOS language follow करता है। User manual language भी चुन सकता है; change के बाद अभी restart करें या बाद में restart करें।

## source से build करें

macOS 13+ और Xcode / Command Line Tools की Swift toolchain चाहिए।

```sh
git clone https://github.com/ericjypark/codex-island
cd codex-island
./build.sh
open build/CodexIsland.app
```

Smoke test:

```sh
./scripts/verify.sh
```

## रिलीज़

```sh
npm install --global create-dmg
./release.sh
```

`v*` tag push करने पर GitHub Actions DMG build करता है, checksum निकालता है, GitHub Release publish करता है, और token configured होने पर Homebrew cask sync करता है।

## गोपनीयता

CodexIsland telemetry, analytics, crash reporting या proxy server नहीं चलाता। Codex tokens सिर्फ local `~/.codex/auth.json` से पढ़े जाते हैं; Claude credentials environment, Keychain या official OAuth flow से लिए जाते हैं।
