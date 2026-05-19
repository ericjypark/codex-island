# Localization Guide

CodexIsland localizes the app with bundled `.lproj/Localizable.strings` files.
English (`en`) is the source language and fallback. Keep translations concise:
most strings render inside narrow notch, footer, settings row, tooltip, or
accessibility surfaces.

## Supported Locales

| Locale | README | Notes |
| --- | --- | --- |
| `en` | `README.md` | Source language and fallback. |
| `zh-Hans` | `README.zh-CN.md` | Simplified Chinese. |
| `zh-Hant` | `README.zh-Hant.md` | General Traditional Chinese for Taiwan, Hong Kong, and Macau. Avoid direct simplified-to-traditional conversion when wording differs. |
| `hi` | `README.hi.md` | Hindi for first-pass India coverage. Keep common developer terms only when the Hindi or loanword form is less natural. |
| `ja` | `README.ja.md` | Japanese. Prefer concise app UI phrasing over literal English structure. |
| `ko` | `README.ko.md` | Korean. Use product UI terms familiar to macOS users. |
| `de` | `README.de.md` | German. Prefer shorter UI terms because settings rows are width constrained. |
| `fr` | `README.fr.md` | French. Keep technical brand names in English. |
| `es` | `README.es.md` | Neutral Spanish. Avoid region-specific vocabulary. |
| `pt-BR` | `README.pt-BR.md` | Brazilian Portuguese. |

## Terminology

| Concept | zh-Hans | zh-Hant | hi | ja | ko | de | fr | es | pt-BR |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Usage | 用量 | 用量 | उपयोग | 使用量 | 사용량 | Nutzung | Usage | Uso | Uso |
| Cost | 成本 | 成本 | लागत | コスト | 비용 | Kosten | Coût | Coste | Custo |
| Overview | 概览 | 概覽 | ओवरव्यू | 概要 | 개요 | Übersicht | Vue d’ensemble | Resumen | Visão geral |
| Provider | 服务 | 服務 | प्रदाता | プロバイダ | 공급자 | Anbieter | Fournisseur | Proveedor | Provedor |
| Token | Token | Token | टोकन | トークン | 토큰 | Token | token | token | token |
| Notch | 刘海 | 劉海 | नॉच | ノッチ | 노치 | Notch | encoche | notch | notch |
| Low Power Mode | 低功耗模式 | 低耗電模式 | लो पावर मोड | 低電力モード | 저전력 모드 | Energiesparmodus | Mode économie d’énergie | Modo de bajo consumo | Modo de baixo consumo |
| Refresh | 刷新 | 重新整理 | रीफ़्रेश | 更新 | 새로고침 | Aktualisieren | Actualiser | Actualizar | Atualizar |
| Syncing | 同步中 | 同步中 | सिंक हो रहा है | 同期中 | 동기화 중 | Synchronisiert | Synchronisation | Sincronizando | Sincronizando |

## Style Rules

- Keep `CodexIsland`, `Claude`, `Codex`, `GitHub`, `Homebrew`, and `Sparkle` unchanged.
- Do not translate model identifiers, plan raw values, bundle identifiers, or UserDefaults keys.
- Prefer short labels for controls. German, Hindi, and Portuguese strings often need shorter UI phrasing than README prose.
- Preserve all `%@`, `%d`, and `%%` placeholders exactly. Reordering is allowed only with positional specifiers.
- Keep compact time labels short. `5h`, `week`, and reset captions are space-constrained.
- README translations should be natural local-language documentation, not word-for-word copies of English.
- Avoid accidental same-as-English values in non-English resources. When a word
  is intentionally identical to English, add it to the validation allowlist.

## Validation

Run these checks before opening a localization PR:

```sh
plutil -lint Resources/*.lproj/Localizable.strings
./scripts/check-localization.sh
./scripts/check-readmes.sh
./scripts/verify.sh
```
