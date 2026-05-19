# CodexIsland

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-Hant.md) | [हिन्दी](README.hi.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md)

<p align="center">
  <img src="Assets/codexisland-logo.png" width="160" alt="CodexIsland logo">
</p>

> Seus limites de uso de IA no notch do Mac.

CodexIsland é um overlay nativo para macOS que transforma o notch do MacBook em uma atividade estilo Dynamic Island para Claude Code e Codex. Ao passar o cursor, ele mostra o uso de 5 horas; ao clicar, abre os painéis Usage, Cost e Overview com tempos de reset, gráficos, estimativas de custo e histórico de tokens a partir de logs locais.

O app é gratuito, open source, não assinado pela Apple e local-first. Ele lê credenciais já gravadas pelo Claude Code / Claude Desktop e Codex e chama apenas os endpoints oficiais de uso dos provedores.

## Recursos

- **Dois provedores, quatro janelas.** Claude 5 h + 7 d e Codex 5 h + 7 d em um painel.
- **Overlay nativo do notch.** Alinha ao notch físico e usa uma pílula na barra de menus em Macs sem notch.
- **Prévia e expansão.** Passe o cursor para ver uso de 5 h; clique para Usage / Cost / Overview.
- **Custo e tokens.** Estima custo em USD, throughput de tokens e tendências a partir dos logs locais do Claude Code e Codex.
- **Vários estilos.** Usage: Ring, Bar, Stepped, Numeric, Sparkline. Cost: USD, VALUE, TOKENS, TREND.
- **Ajustes.** Abrir ao iniciar sessão, intervalo de atualização, baixo consumo, provedores, idioma, gráficos e visão de custo.
- **Atualizações via Sparkle.** Verifica o appcast do GitHub Release e pede confirmação antes de instalar.
- **Privacidade.** Sem telemetria, crash reporting, analytics ou proxy.

## Instalação

### Homebrew

```sh
brew install --cask ericjypark/tap/codexisland
```

Na primeira execução, `ericjypark/homebrew-tap` é adicionado automaticamente. Como CodexIsland não é assinado pela Apple, o cask remove o atributo Gatekeeper quarantine; o Sparkle verifica as atualizações.

### Download direto

Baixe `CodexIsland-X.Y.Z.dmg` em [Releases](https://github.com/ericjypark/codex-island/releases), arraste o app para `/Applications` e execute:

```sh
xattr -dr com.apple.quarantine /Applications/CodexIsland.app
```

Se não quiser usar Terminal, abra o app uma vez e depois vá em **Ajustes do Sistema -> Privacidade e Segurança** para escolher **Abrir Mesmo Assim**.

## Primeiro uso

CodexIsland não pede senha nem API key. Para Codex, lê `~/.codex/auth.json`. Para Claude, tenta `CLAUDE_CODE_OAUTH_TOKEN`, o item `Claude Code-credentials` no Keychain e o refresh OAuth da Anthropic.

Se a auth do Codex faltar, aparece `no codex auth`. Se a auth do Claude faltar, aparece `auth required — run claude`.

## Uso

- Passe o cursor sobre o notch para ver o uso de 5 horas.
- Clique na ilha para abrir o painel completo.
- Deslize horizontalmente ou use os pontos para alternar entre **Usage**, **Cost** e **Overview**.
- Command-clique no painel aberto para alternar a visualização ativa.
- Clique no status de sincronização para atualizar agora.
- A engrenagem no canto inferior esquerdo abre os ajustes.

## Ajustes

Os ajustes ficam em uma `NSWindow` personalizada. As preferências são salvas em UserDefaults: estilo de gráfico `MacIsland.chartStyle`, visualização de custo `MacIsland.costStyle`, contagem de tokens `MacIsland.tokenCountMode`, intervalo de atualização `MacIsland.refreshInterval`, modo de baixo consumo `MacIsland.lowPowerMode`, idioma `MacIsland.appLanguage`.

O idioma padrão é `Auto`, seguindo o macOS. Ao escolher um idioma manualmente, o app oferece reiniciar agora ou aplicar no próximo início.

## Compilar a partir do código-fonte

Requer macOS 13+ e a toolchain Swift do Xcode / Command Line Tools.

```sh
git clone https://github.com/ericjypark/codex-island
cd codex-island
./build.sh
open build/CodexIsland.app
```

Teste rápido:

```sh
./scripts/verify.sh
```

## Publicação

```sh
npm install --global create-dmg
./release.sh
```

Uma tag `v*` aciona o GitHub Actions, gera o DMG, calcula o checksum, publica a GitHub Release e sincroniza o cask do Homebrew se o token estiver configurado.

## Privacidade

CodexIsland não tem telemetria, analytics, crash reporting nem proxy. Tokens do Codex são lidos localmente de `~/.codex/auth.json`; credenciais do Claude vêm do ambiente, Keychain ou OAuth oficial.
