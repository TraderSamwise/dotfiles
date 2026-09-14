#!/usr/bin/env bash
# macOS preferences. Idempotent; run directly or via `bootstrap.sh --macos`.
# Restarts Dock, Finder and SystemUIServer at the end so most changes apply now.
set -euo pipefail

write() {
  defaults write "$@"
  echo "set    $1 $2"
}

write NSGlobalDomain KeyRepeat -int 2
write NSGlobalDomain InitialKeyRepeat -int 15
write NSGlobalDomain ApplePressAndHoldEnabled -bool false
write NSGlobalDomain com.apple.swipescrolldirection -bool false
write NSGlobalDomain AppleShowAllExtensions -bool true
write NSGlobalDomain AppleInterfaceStyle -string Dark

for trackpad in com.apple.AppleMultitouchTrackpad com.apple.driver.AppleBluetoothMultitouch.trackpad; do
  write "$trackpad" Clicking -bool true
  write "$trackpad" TrackpadThreeFingerHorizSwipeGesture -int 1
done

write com.apple.dock autohide -bool true
write com.apple.dock launchanim -bool false
write com.apple.dock mru-spaces -bool false

write com.apple.finder ShowPathbar -bool true
write com.apple.finder FXPreferredViewStyle -string Nlsv
write com.apple.finder FXDefaultSearchScope -string SCcf
write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true

screenshots="$HOME/Desktop/screenshots"
mkdir -p "$screenshots"
for location_key in location location-screenshot location-screenrecording; do
  write com.apple.screencapture "$location_key" -string "$screenshots"
done
write com.apple.screencapture style -string window

# Spotlight (64) moves from ⌘Space to ⌘⌥Space so Raycast can take ⌘Space.
# Finder search window (65) defaults to ⌘⌥Space, so it is disabled to avoid the clash.
option_command_space='<key>value</key><dict><key>type</key><string>standard</string><key>parameters</key><array><integer>32</integer><integer>49</integer><integer>1572864</integer></array></dict>'
write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 "<dict><key>enabled</key><true/>$option_command_space</dict>"
write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 65 "<dict><key>enabled</key><false/>$option_command_space</dict>"
if ! /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u; then
  echo "!! could not reload keyboard shortcuts; log out and back in to apply ⌘⌥Space" >&2
fi

# The universalaccess domain is protected: writing it needs Full Disk Access.
if defaults write com.apple.universalaccess reduceTransparency -bool true \
  && [ "$(defaults read com.apple.universalaccess reduceTransparency)" = 1 ]; then
  echo "set    com.apple.universalaccess reduceTransparency"
else
  echo "!! reduceTransparency NOT set: give your terminal Full Disk Access (System Settings > Privacy & Security), then rerun" >&2
fi

for app in Dock Finder SystemUIServer; do
  if killall "$app" 2>/dev/null; then
    echo "restart $app"
  fi
done
