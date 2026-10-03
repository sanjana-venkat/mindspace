cask "mindspace" do
  version "0.1.16"
  sha256 "a22c6e577724c0484cda1a4183abce7990849084fb40a455c8b1e159054cd2a8"

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
