# Auto-hide visuals

These are offscreen SwiftUI renders, not screenshots or recordings of a desktop.

- `before.png`: the existing General settings rows from baseline `326f980`.
- `after.png` and `after-zh-Hans.png`: the changed rows at 440 points wide,
  rendered with the production `SettingsRow`, `SettingsToggle`, localization,
  typography and colors. Row definitions were extracted from `SettingsView`.
  An isolated fixture bundle holds all rendering preferences.
- `behavior.gif`: a synthetic display illustration driven by the production
  `IslandVisibilityState` and `IslandShape`. It shows desktop, Game Mode,
  fullscreen video with Game Mode off, then desktop again. It demonstrates the
  policy; it does not exercise WindowServer events, real apps, or focus.

Rendered with `ImageRenderer` at 2x scale; the GIF uses ImageIO with 1.8 seconds
per frame. No desktop capture, provider credentials, browser content, or usage
history is included. Live verification and its gaps are recorded separately in
the pull request description.
