cask "mindspace" do
  version "0.1.15"
  sha256 "0cc171f2f0b8e4e0fababda1a6f4ed3bae60c2fbe7bcdf04480e7f1ee249900a"

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
