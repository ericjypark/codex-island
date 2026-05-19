# CodexIsland

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-Hant.md) | [हिन्दी](README.hi.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md)

<p align="center">
  <img src="Assets/codexisland-logo.png" width="160" alt="CodexIsland logo">
</p>

> Vos limites d’usage IA dans l’encoche du Mac.

CodexIsland est un overlay macOS natif qui transforme l’encoche du MacBook en activité façon Dynamic Island pour Claude Code et Codex. Au survol, il affiche l’usage sur 5 heures ; au clic, il ouvre les panneaux Usage, Cost et Overview avec les réinitialisations, les graphiques, les estimations de coût et l’historique des tokens issus des journaux locaux.

L’app est gratuite, open source, non signée par Apple et local-first. Elle lit uniquement les identifiants déjà présents pour Claude Code / Claude Desktop et Codex, puis appelle les endpoints d’usage des fournisseurs.

## Fonctionnalités

- **Deux fournisseurs, quatre fenêtres.** Claude 5 h + 7 j et Codex 5 h + 7 j dans un seul panneau.
- **Overlay adapté à l’encoche.** Aligné sur l’encoche matérielle, avec repli en pastille de barre de menus sur les Mac sans encoche.
- **Survol et ouverture.** Survol pour l’usage 5 h, clic pour Usage / Cost / Overview.
- **Coût et tokens.** Estimation du coût en USD, du débit de tokens et des tendances à partir des journaux locaux Claude Code et Codex.
- **Styles visuels.** Usage : Ring, Bar, Stepped, Numeric, Sparkline. Cost : USD, VALUE, TOKENS, TREND.
- **Réglages.** Lancement à la connexion, intervalle d’actualisation, économie d’énergie, fournisseurs, langue, styles de graphique et de coût.
- **Mises à jour Sparkle.** Vérifie l’appcast GitHub Release et demande confirmation avant installation.
- **Confidentialité.** Pas de télémétrie, crash reporting, analytics ni proxy.

## Installation

### Homebrew

```sh
brew install --cask ericjypark/tap/codexisland
```

La première commande ajoute automatiquement `ericjypark/homebrew-tap`. CodexIsland n’étant pas signé par Apple, le cask retire l’attribut Gatekeeper quarantine ; Sparkle vérifie les mises à jour.

### Téléchargement direct

Téléchargez `CodexIsland-X.Y.Z.dmg` depuis [Releases](https://github.com/ericjypark/codex-island/releases), glissez l’app dans `/Applications`, puis exécutez :

```sh
xattr -dr com.apple.quarantine /Applications/CodexIsland.app
```

Sans Terminal : ouvrez l’app une première fois, puis allez dans **Réglages Système -> Confidentialité et sécurité** et choisissez **Ouvrir quand même**.

## Premier lancement

CodexIsland ne demande ni mot de passe ni clé API. Pour Codex, il lit `~/.codex/auth.json`. Pour Claude, il tente `CLAUDE_CODE_OAUTH_TOKEN`, l’entrée Keychain `Claude Code-credentials`, puis le refresh OAuth d’Anthropic.

Sans auth Codex, le panneau affiche `no codex auth`. Sans auth Claude, il affiche `auth required — run claude`.

## Utilisation

- Survolez l’encoche pour voir l’usage sur 5 heures.
- Cliquez l’île pour ouvrir le panneau complet.
- Balayez horizontalement ou utilisez les points pour passer entre **Usage**, **Cost** et **Overview**.
- Command-clic sur le panneau ouvert pour changer de visualisation.
- Cliquez l’état de synchronisation pour actualiser immédiatement.
- Cliquez l’engrenage en bas à gauche pour ouvrir les réglages.

## Réglages

Les réglages sont une fenêtre `NSWindow` personnalisée. Les préférences sont dans UserDefaults : style de graphique `MacIsland.chartStyle`, affichage du coût `MacIsland.costStyle`, comptage des tokens `MacIsland.tokenCountMode`, intervalle d’actualisation `MacIsland.refreshInterval`, mode économie d’énergie `MacIsland.lowPowerMode`, langue `MacIsland.appLanguage`.

La langue est sur `Auto` par défaut et suit macOS. En sélection manuelle, l’app propose de redémarrer maintenant ou d’appliquer le changement au prochain lancement.

## Build depuis les sources

Requiert macOS 13+ et la toolchain Swift de Xcode / Command Line Tools.

```sh
git clone https://github.com/ericjypark/codex-island
cd codex-island
./build.sh
open build/CodexIsland.app
```

Test rapide :

```sh
./scripts/verify.sh
```

## Publication

```sh
npm install --global create-dmg
./release.sh
```

Un tag `v*` déclenche GitHub Actions, construit le DMG, calcule le checksum, publie la GitHub Release et synchronise le cask Homebrew si le token est configuré.

## Confidentialité

CodexIsland n’a ni télémétrie, ni analytics, ni crash reporting, ni proxy. Les tokens Codex sont lus localement dans `~/.codex/auth.json`; les identifiants Claude viennent de l’environnement, du Keychain ou du flux OAuth officiel.
