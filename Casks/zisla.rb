cask "zisla" do
  arch arm: "arm64", intel: "x86_64"

  version "0.1.6"
  sha256 arm:   "21aa93b9620981a2bfe46fe12e3690822dafd48a9d2b43548e39fdcda1f6680f",
         intel: "f34d0992221a39a1baf513de0b84dfe130b816e544200967d41be4a42b20f41a"

  url "https://github.com/wzz6423/zisla/releases/download/v#{version}/zisla-v#{version}-macOS-#{arch}.zip",
      verified: "github.com/wzz6423/zisla/"
  name "zisla"
  desc "Top workspace for media, files, system tools, and local AI activity"
  homepage "https://github.com/wzz6423/zisla"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Sparkle installs later versions itself, so `brew upgrade` replaces the app only when
  # the installed bundle really is behind the tap; Homebrew 5.1.6 and later read the
  # version inside the app, while naming the cask or --greedy goes by Homebrew's own
  # install records and can undo a Sparkle update. Sparkle reads the appcast for this
  # slice, so an in-app update keeps the install on a single architecture.
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
