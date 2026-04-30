cask "codexisland" do
  version "0.0.1"
  sha256 "8ba2378eb4c620440ae129aba9bb03b0020f3411deac66481e002daee6cafcf5"

  url "https://github.com/ericjypark/codex-island/releases/download/v#{version}/CodexIsland-#{version}.dmg"
  name "CodexIsland"
  desc "Notch-based live activity for Claude Code and Codex API rate limits"
  homepage "https://github.com/ericjypark/codex-island"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "CodexIsland.app"

  # Homebrew removed --no-quarantine in late 2025. CodexIsland is unsigned by
  # Apple (Sparkle handles update verification independently), so without this
  # the first launch hits a "damaged or unidentified developer" Gatekeeper
  # block. Strip the quarantine xattr post-install so users can just open it.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-d", "com.apple.quarantine", "#{appdir}/CodexIsland.app"],
                   sudo: false
  end

  zap trash: [
    "~/Library/Preferences/dev.codexisland.CodexIsland.plist",
    "~/Library/Application Support/CodexIsland",
  ]
end
