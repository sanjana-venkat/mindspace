cask "mindspace" do
  version "0.1.3"
  sha256 "83fcb891763f997a3ebca4ed6a095cb4aa01a6f2fd11fdb4b8cbdd28026f0351"

  url "https://github.com/sanjana-venkat/mindspace/releases/download/v#{version}/Mindspace-#{version}.dmg"
  name "Mindspace"
  desc "Infinite canvas for screen captures and the thoughts behind them"
  homepage "https://github.com/sanjana-venkat/mindspace"

  depends_on macos: :sonoma

  app "Mindspace.app"

  # Signed with a Developer ID and notarized, with the ticket stapled to the
  # DMG, so Gatekeeper lets it open on the first try — no right-click → Open,
  # and no trip through Privacy & Security.

  zap trash: [
    "~/Library/Application Support/Notefy",
    "~/Library/Preferences/com.notefy.app.plist",
  ]
end
