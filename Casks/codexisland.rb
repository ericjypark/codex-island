cask "codexisland" do
  version "0.1.0"
  sha256 "REPLACE_AT_RELEASE_TIME"

  url "https://github.com/eric-jy-park/codexisland/releases/download/v#{version}/CodexIsland-#{version}.dmg"
  name "CodexIsland"
  desc "Notch-based live activity for Claude Code and Codex API rate limits"
  homepage "https://github.com/eric-jy-park/codexisland"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "CodexIsland.app"

  zap trash: [
    "~/Library/Preferences/dev.codexisland.CodexIsland.plist",
    "~/Library/Application Support/CodexIsland",
  ]
end
