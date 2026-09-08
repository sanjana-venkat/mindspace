cask "mindspace" do
  version "0.1.0"
  sha256 "3bb62f28fc799a9fb7b1076187f04d85276e5247fb5585bd347aab19e9378327"

  url "https://github.com/sanjana-venkat/mindspace/releases/download/v#{version}/Mindspace-#{version}.dmg"
  name "Mindspace"
  desc "Infinite canvas for screen captures and the thoughts behind them"
  homepage "https://github.com/sanjana-venkat/mindspace"

  depends_on macos: ">= :sonoma"

  app "Mindspace.app"

  zap trash: [
    "~/Library/Application Support/Notefy",
    "~/Library/Preferences/com.notefy.app.plist",
  ]
end
