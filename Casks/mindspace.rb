cask "mindspace" do
  version "0.1.1"
  sha256 "13fd2594362794dd5138ab5482cccc9ef8270d70019fea92688ba1f256381462"

  url "https://github.com/sanjana-venkat/mindspace/releases/download/v#{version}/Mindspace-#{version}.dmg"
  name "Mindspace"
  desc "Infinite canvas for screen captures and the thoughts behind them"
  homepage "https://github.com/sanjana-venkat/mindspace"

  depends_on macos: :sonoma

  app "Mindspace.app"

  # Ad-hoc signed rather than notarized, so Homebrew quarantines it and a
  # postflight xattr can't help — the flag is applied after postflight runs.
  # Installs need --no-quarantine until this ships with a Developer ID.

  zap trash: [
    "~/Library/Application Support/Notefy",
    "~/Library/Preferences/com.notefy.app.plist",
  ]
end
