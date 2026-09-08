cask "mindspace" do
  version "0.1.0"
  sha256 "78a59d8ec63b974efdb413c8fc57eae3055a528bbdf0df4927c5b03fb7704a5e"

  url "https://github.com/sanjana-venkat/mindspace/releases/download/v#{version}/Mindspace-#{version}.dmg"
  name "Mindspace"
  desc "Infinite canvas for screen captures and the thoughts behind them"
  homepage "https://github.com/sanjana-venkat/mindspace"

  depends_on macos: ">= :sonoma"

  app "Mindspace.app"

  # The build is ad-hoc signed rather than notarized, so Gatekeeper quarantines
  # it on download. Drop the quarantine flag on install; remove this block once
  # the app ships with a Developer ID signature and a notarization ticket.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Mindspace.app"],
                   sudo: false
  end

  zap trash: [
    "~/Library/Application Support/Notefy",
    "~/Library/Preferences/com.notefy.app.plist",
  ]
end
