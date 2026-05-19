# CodexIsland

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-Hant.md) | [हिन्दी](README.hi.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md)

<p align="center">
  <img src="Assets/codexisland-logo.png" width="160" alt="CodexIsland logo">
</p>

> Deine AI-Nutzungslimits in der Notch.

CodexIsland ist ein natives macOS-Overlay, das die MacBook-Notch in eine Dynamic-Island-ähnliche Live-Anzeige für Claude Code und Codex verwandelt. Beim Hover zeigt es das 5-Stunden-Fenster; per Klick öffnet es Usage, Cost und Overview mit Reset-Zeiten, Diagrammen, lokalen Kostenschätzungen und Token-Verlauf.

Die App ist kostenlos, Open Source, nicht von Apple signiert und local-first. Sie liest nur bereits vorhandene Anmeldedaten von Claude Code / Claude Desktop und Codex und ruft ausschließlich die Usage-Endpunkte der Anbieter auf.

## Funktionen

- **Zwei Anbieter, vier Fenster.** Claude 5 h + 7 d und Codex 5 h + 7 d in einem Panel.
- **Notch-natives Overlay.** Auf MacBooks mit Notch wird es an der Hardware ausgerichtet; ohne Notch wird es zur Menüleisten-Pill.
- **Hover und Expand.** Hover zeigt die 5-h-Nutzung, Klick öffnet Usage / Cost / Overview.
- **Kosten und Token.** Lokale Claude-Code- und Codex-Logs liefern Schätzungen für heutige und monatliche USD-Kosten, Token-Durchsatz und Trend.
- **Mehrere Ansichten.** Usage: Ring, Bar, Stepped, Numeric, Sparkline. Cost: USD, VALUE, TOKENS, TREND.
- **Einstellungen.** Login-Start, Aktualisierungsintervall, Energiesparmodus, Anbieter, Sprache, Diagramm- und Kostenstil.
- **Sparkle-Updates.** Prüft das Appcast der neuesten GitHub Release und fragt vor der Installation.
- **Datenschutz.** Keine Telemetrie, Crashreports, Analytics oder Proxy-Dienste.

## Installation

### Homebrew

```sh
brew install --cask ericjypark/tap/codexisland
```

Beim ersten Aufruf wird `ericjypark/homebrew-tap` automatisch hinzugefügt. Da CodexIsland nicht von Apple signiert ist, entfernt das Cask das Gatekeeper-Quarantäneattribut. Sparkle prüft Updates separat.

### Direktdownload

Lade `CodexIsland-X.Y.Z.dmg` unter [Releases](https://github.com/ericjypark/codex-island/releases), ziehe die App nach `/Applications` und führe aus:

```sh
xattr -dr com.apple.quarantine /Applications/CodexIsland.app
```

Ohne Terminal: App einmal öffnen, blockieren lassen, dann unter **Systemeinstellungen -> Datenschutz & Sicherheit** unten **Dennoch öffnen** wählen.

## Erster Start

CodexIsland fragt nicht nach Passwort oder API-Key. Für Codex liest es `~/.codex/auth.json`. Für Claude versucht es `CLAUDE_CODE_OAUTH_TOKEN`, den Keychain-Eintrag `Claude Code-credentials` und den OAuth-Refresh von Anthropic.

Fehlt Codex-Auth, erscheint `no codex auth`. Fehlt Claude-Auth, erscheint `auth required — run claude`.

## Nutzung

- Über die Notch hovern, um die 5-h-Nutzung zu sehen.
- Island klicken, um das volle Panel zu öffnen.
- Horizontal wischen oder die Punkte nutzen, um **Usage**, **Cost** und **Overview** zu wechseln.
- Command-Klick im geöffneten Panel wechselt die aktive Visualisierung.
- Sync-Status anklicken, um sofort zu aktualisieren.
- Das Zahnrad unten links öffnet die Einstellungen.

## Einstellungen

Die Einstellungen sind ein eigenes `NSWindow`. Sie liegen in UserDefaults: Chart-Stil `MacIsland.chartStyle`, Kostenansicht `MacIsland.costStyle`, Token-Zählung `MacIsland.tokenCountMode`, Aktualisierungsintervall `MacIsland.refreshInterval`, Energiesparmodus `MacIsland.lowPowerMode`, Sprachwahl `MacIsland.appLanguage`.

Die Sprache steht standardmäßig auf `Auto` und folgt macOS. Bei manueller Auswahl fragt die App, ob sie sofort neu starten oder erst später beim nächsten Start wechseln soll.

## Aus dem Quellcode bauen

Erfordert macOS 13+ und die Swift-Toolchain aus Xcode / Command Line Tools.

```sh
git clone https://github.com/ericjypark/codex-island
cd codex-island
./build.sh
open build/CodexIsland.app
```

Smoke-Test:

```sh
./scripts/verify.sh
```

## Veröffentlichung

```sh
npm install --global create-dmg
./release.sh
```

Ein `v*`-Tag startet GitHub Actions, baut das DMG, berechnet die Prüfsumme, veröffentlicht die GitHub Release und synchronisiert bei konfiguriertem Token das Homebrew Cask.

## Datenschutz

CodexIsland hat keine Telemetrie, Analytics, Crashreports oder Proxy-Server. Codex-Tokens werden nur aus `~/.codex/auth.json` gelesen; Claude-Zugangsdaten kommen aus Environment, Keychain oder offiziellem OAuth.
