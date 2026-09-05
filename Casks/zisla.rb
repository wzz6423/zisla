cask "zisla" do
  version "0.1.6"
  sha256 "0d51249e87801ca17faba6a6b8044d89fbcbd4a8aa701ec29f4a90ce39675d4d"

  url "https://github.com/wzz6423/zisla/releases/download/v#{version}/zisla-v#{version}-macOS-universal.zip",
      verified: "github.com/wzz6423/zisla/"
  name "zisla"
  desc "Top workspace for media, files, system tools, and local AI activity"
  homepage "https://github.com/wzz6423/zisla"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Sparkle installs later versions itself, so `brew upgrade` replaces the app only
  # when the cask is named explicitly or --greedy is passed.
  auto_updates true
  depends_on macos: :sonoma

  app "zisla.app"

  zap trash: [
    "~/Library/Application Support/zisla",
    "~/Library/Caches/dev.wzz.zisla",
    "~/Library/HTTPStorages/dev.wzz.zisla",
    "~/Library/Preferences/dev.wzz.zisla.plist",
    "~/Library/Saved Application State/dev.wzz.zisla.savedState",
  ]

  caveats <<~EOS
    zisla ships with an ad-hoc signature and is not notarized, so macOS quarantines
    it on first launch. Open it once from System Settings > Privacy & Security by
    choosing "Open Anyway", or clear the quarantine attribute yourself:

      xattr -d com.apple.quarantine "#{appdir}/zisla.app"

    zisla needs Accessibility and Screen Recording permissions for the top-edge
    workspace, and asks for them on first use.
  EOS
end
