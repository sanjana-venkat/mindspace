cask "mindspace" do
  version "0.1.1"
  sha256 "13fd2594362794dd5138ab5482cccc9ef8270d70019fea92688ba1f256381462"

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
