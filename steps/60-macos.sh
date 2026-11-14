# shellcheck shell=bash
#
# Steps: macos (preferences from my previous Mac), xcode (App Store apps)

# ─── macos ───────────────────────────────────────────────────────────────────

step_macos() {
  configure_trackpad
  configure_key_repeat
  configure_keyboard_layouts
  set_computer_name

  # Apply what can be applied without logging out.
  killall cfprefsd 2>/dev/null
  /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null
  return 0
}

configure_trackpad() {
  # Scrolling: NOT "natural" (content moves like with a mouse wheel).
  defaults write -g com.apple.swipescrolldirection -bool false

  # Built-in and Bluetooth trackpads keep separate settings.
  local domain
  for domain in com.apple.AppleMultitouchTrackpad com.apple.driver.AppleBluetoothMultitouch.trackpad; do
    defaults write "$domain" Clicking -int 1           # tap to click
    defaults write "$domain" TrackpadRightClick -int 1 # two-finger secondary click
    defaults write "$domain" TrackpadCornerSecondaryClick -int 0
    defaults write "$domain" TrackpadThreeFingerDrag -int 0
    defaults write "$domain" TrackpadThreeFingerTapGesture -int 0 # no "look up" on three-finger tap
    defaults write "$domain" TrackpadTwoFingerDoubleTapGesture -int 1
    defaults write "$domain" TrackpadTwoFingerFromRightEdgeSwipeGesture -int 3
    defaults write "$domain" TrackpadThreeFingerHorizSwipeGesture -int 2
    defaults write "$domain" TrackpadThreeFingerVertSwipeGesture -int 2
    defaults write "$domain" TrackpadFourFingerHorizSwipeGesture -int 2
    defaults write "$domain" TrackpadFourFingerVertSwipeGesture -int 2
    defaults write "$domain" TrackpadPinch -int 1
    defaults write "$domain" TrackpadRotate -int 1
    defaults write "$domain" TrackpadMomentumScroll -int 1
    defaults write "$domain" ActuateDetents -int 1
    defaults write "$domain" FirstClickThreshold -int 1
    defaults write "$domain" SecondClickThreshold -int 1
  done

  defaults -currentHost write -g com.apple.mouse.tapBehavior -int 1
  defaults write -g com.apple.mouse.tapBehavior -int 1
  defaults write -g com.apple.trackpad.scaling -float 2.5 # tracking speed

  ok "trackpad: tap to click, non-natural scrolling, speed 2.5"
}

configure_key_repeat() {
  defaults write -g KeyRepeat -int 5
  defaults write -g InitialKeyRepeat -int 25
  ok "key repeat: 5, delay until repeat: 25"
}

# Enable the chosen layouts from macos/input-sources.txt ("Name|ID" lines).
configure_keyboard_layouts() {
  local sources=() name id
  while IFS='|' read -r name id; do
    case "$name" in '' | '#'*) continue ;; esac
    list_contains "$KEYBOARD_LAYOUTS" "$name" || continue
    sources+=("$(keyboard_layout_plist "$name" "$id")")
  done <"$NEWMAC_DIR/macos/input-sources.txt"

  [ ${#sources[@]} -gt 0 ] || return 0

  # The emoji & symbols viewer, which macOS keeps in the same list.
  sources+=('<dict><key>Bundle ID</key><string>com.apple.CharacterPaletteIM</string><key>InputSourceKind</key><string>Non Keyboard Input Method</string></dict>')

  defaults write com.apple.HIToolbox AppleEnabledInputSources -array "${sources[@]}"
  defaults write com.apple.TextInputMenu visible -bool true # input menu in the menu bar
  ok "keyboard layouts: ${KEYBOARD_LAYOUTS//|/, } (active after logout)"
}

keyboard_layout_plist() {
  printf '<dict>%s%s%s</dict>' \
    '<key>InputSourceKind</key><string>Keyboard Layout</string>' \
    "<key>KeyboardLayout ID</key><integer>$2</integer>" \
    "<key>KeyboardLayout Name</key><string>$1</string>"
}

set_computer_name() {
  [ -n "${COMPUTER_NAME:-}" ] || return 0
  [ "$COMPUTER_NAME" = "$(scutil --get ComputerName 2>/dev/null)" ] && return 0

  # "Ashot's MacBook Pro" -> "Ashot-s-MacBook-Pro" for the network names.
  local hostname
  hostname=$(printf '%s' "$COMPUTER_NAME" | tr -cs 'A-Za-z0-9' '-' | sed 's/^-*//; s/-*$//')

  sudo scutil --set ComputerName "$COMPUTER_NAME"
  sudo scutil --set LocalHostName "$hostname"
  sudo scutil --set HostName "$hostname"
  ok "computer name: $COMPUTER_NAME ($hostname.local)"
}

# ─── xcode ───────────────────────────────────────────────────────────────────

# Mac App Store IDs
APP_STORE_TESTFLIGHT=899247664
APP_STORE_DEVELOPER=640199958
APP_STORE_XCODE=497799835

step_xcode() {
  have mas || {
    err "mas missing (package group: core)"
    return 1
  }

  install_testflight
  install_from_app_store $APP_STORE_DEVELOPER "Developer (Apple)" ||
    warn "Developer app not installed"
  install_xcode || return 1

  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  sudo xcodebuild -license accept
  sudo xcodebuild -runFirstLaunch
  ok "$(xcodebuild -version | head -1) selected, license accepted"

  download_ios_platform
}

# install_from_app_store ID NAME — needs you signed in to the App Store app.
install_from_app_store() {
  local id=$1 name=$2
  if mas list 2>/dev/null | grep -q "^ *$id "; then
    ok "$name already installed"
    return 0
  fi
  info "App Store: $name"
  mas get "$id" </dev/tty || mas install "$id" </dev/tty
}

# TestFlight goes first: if the App Store sign-in is missing, we find out
# here, before the big Xcode download.
install_testflight() {
  install_from_app_store $APP_STORE_TESTFLIGHT TestFlight && return 0

  warn "App Store install failed. Open the App Store app and sign in with your Apple Account."
  open -a "App Store"
  pause "Signed in? Press Enter to retry"
  install_from_app_store $APP_STORE_TESTFLIGHT TestFlight || warn "TestFlight not installed"
}

install_xcode() {
  [ -d /Applications/Xcode.app ] && return 0
  info "Downloading Xcode (10+ GB, this takes a while)…"
  install_from_app_store $APP_STORE_XCODE Xcode || {
    err "Xcode install failed — retry with: newmac xcode"
    return 1
  }
}

download_ios_platform() {
  info "Downloading the latest iOS platform (SDK + Simulator runtime)…"
  xcodebuild -downloadPlatform iOS ||
    warn "iOS platform download failed — retry: xcodebuild -downloadPlatform iOS"

  # Xcode 26+ ships the Metal toolchain separately; harmless if not needed.
  xcodebuild -downloadComponent MetalToolchain >/dev/null 2>&1

  xcrun simctl list runtimes 2>/dev/null | grep -i ios | tail -3 | sed 's/^/    /'
}
