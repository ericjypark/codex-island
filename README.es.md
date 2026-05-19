# CodexIsland

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-Hant.md) | [हिन्दी](README.hi.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Português (Brasil)](README.pt-BR.md)

<p align="center">
  <img src="Assets/codexisland-logo.png" width="160" alt="CodexIsland logo">
</p>

> Tus límites de uso de IA en el notch del Mac.

CodexIsland es un overlay nativo de macOS que convierte el notch del MacBook en una actividad estilo Dynamic Island para Claude Code y Codex. Al pasar el cursor muestra el uso de 5 horas; al hacer clic abre los paneles Usage, Cost y Overview con tiempos de reinicio, gráficos, estimaciones de coste e historial de tokens desde logs locales.

La app es gratis, open source, no está firmada por Apple y es local-first. Lee las credenciales que Claude Code / Claude Desktop y Codex ya guardaron en tu Mac y solo llama a los endpoints de uso de cada proveedor.

## Funciones

- **Dos proveedores, cuatro ventanas.** Claude 5 h + 7 d y Codex 5 h + 7 d en un panel.
- **Overlay nativo del notch.** Se alinea con el notch físico y cae a una píldora de barra de menú en Macs sin notch.
- **Vista rápida y expansión.** Cursor para el uso de 5 h; clic para Usage / Cost / Overview.
- **Coste y tokens.** Estima coste en USD, throughput de tokens y tendencias desde los logs locales de Claude Code y Codex.
- **Varios estilos.** Usage: Ring, Bar, Stepped, Numeric, Sparkline. Cost: USD, VALUE, TOKENS, TREND.
- **Ajustes.** Inicio con sesión, intervalo de actualización, bajo consumo, proveedores, idioma, gráficos y vista de coste.
- **Actualizaciones Sparkle.** Revisa el appcast de GitHub Release y pide confirmación antes de instalar.
- **Privacidad.** Sin telemetría, informes de fallos, analytics ni proxy.

## Instalación

### Homebrew

```sh
brew install --cask ericjypark/tap/codexisland
```

La primera ejecución añade `ericjypark/homebrew-tap`. Como CodexIsland no está firmado por Apple, el cask elimina el atributo Gatekeeper quarantine; Sparkle verifica las actualizaciones.

### Descarga directa

Descarga `CodexIsland-X.Y.Z.dmg` desde [Releases](https://github.com/ericjypark/codex-island/releases), arrastra la app a `/Applications` y ejecuta:

```sh
xattr -dr com.apple.quarantine /Applications/CodexIsland.app
```

Si no quieres usar Terminal, abre la app una vez y luego ve a **Ajustes del Sistema -> Privacidad y seguridad** para elegir **Abrir igualmente**.

## Primer uso

CodexIsland no pide contraseñas ni API keys. Para Codex lee `~/.codex/auth.json`. Para Claude prueba `CLAUDE_CODE_OAUTH_TOKEN`, el item `Claude Code-credentials` del Keychain y el refresh OAuth de Anthropic.

Si falta auth de Codex, verás `no codex auth`. Si falta auth de Claude, verás `auth required — run claude`.

## Uso

- Pasa el cursor por el notch para ver el uso de 5 horas.
- Haz clic en la isla para abrir el panel completo.
- Desliza horizontalmente o usa los puntos para cambiar entre **Usage**, **Cost** y **Overview**.
- Command-clic en el panel abierto cambia la visualización activa.
- Haz clic en el estado de sincronización para actualizar ahora.
- El engranaje inferior izquierdo abre los ajustes.

## Ajustes

Los ajustes se muestran en una `NSWindow` personalizada. Las preferencias se guardan en UserDefaults: estilo de gráfico `MacIsland.chartStyle`, vista de coste `MacIsland.costStyle`, conteo de tokens `MacIsland.tokenCountMode`, intervalo de actualización `MacIsland.refreshInterval`, modo de bajo consumo `MacIsland.lowPowerMode`, idioma `MacIsland.appLanguage`.

El idioma por defecto es `Auto` y sigue macOS. Si eliges un idioma manualmente, la app ofrece reiniciar ahora o aplicar el cambio en el próximo inicio.

## Compilar desde el código

Requiere macOS 13+ y la toolchain Swift de Xcode / Command Line Tools.

```sh
git clone https://github.com/ericjypark/codex-island
cd codex-island
./build.sh
open build/CodexIsland.app
```

Prueba rápida:

```sh
./scripts/verify.sh
```

## Publicación

```sh
npm install --global create-dmg
./release.sh
```

Un tag `v*` activa GitHub Actions, construye el DMG, calcula el checksum, publica la GitHub Release y sincroniza el cask de Homebrew si hay token configurado.

## Privacidad

CodexIsland no tiene telemetría, analytics, informes de fallos ni proxy. Los tokens de Codex se leen localmente desde `~/.codex/auth.json`; las credenciales de Claude vienen del entorno, Keychain o el OAuth oficial.
