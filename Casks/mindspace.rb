cask "mindspace" do
  version "0.1.10"
  sha256 "8713f943787f3e495dab2c5409826e3009310ede57018c46896d6f037052c559"

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
