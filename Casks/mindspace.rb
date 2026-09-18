cask "mindspace" do
  version "0.1.2"
  sha256 "63fd0d43495a7c45c14f0f915b59468b4cf023868b3afe9f47e7978d50a2abdb"

  url "https://github.com/sanjana-venkat/mindspace/releases/download/v#{version}/Mindspace-#{version}.dmg"
  name "Mindspace"
  desc "Infinite canvas for screen captures and the thoughts behind them"
  homepage "https://github.com/sanjana-venkat/mindspace"

  depends_on macos: :sonoma

  app "Mindspace.app"

  # Ad-hoc signed rather than notarized, so Homebrew quarantines it. A
  # postflight xattr can't help (the flag lands after postflight runs) and
  # Homebrew 6 dropped --no-quarantine, so the first launch needs right-click →
  # Open. Goes away with a Developer ID signature.

  zap trash: [
    "~/Library/Application Support/Notefy",
    "~/Library/Preferences/com.notefy.app.plist",
  ]
end
