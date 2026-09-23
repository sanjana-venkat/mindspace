cask "mindspace" do
  version "0.1.6"
  sha256 "a5d36f7a70aa5cf10664be2f84b7e910d747076aa25ad2da6899a394b14a2d23"

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
