# shellcheck shell=bash
# macOS preferences captured from my previous Mac, and Xcode / App Store apps.

step_macos() {
  # --- Trackpad --------------------------------------------------------------
  # Scrolling: NOT "natural" (content follows the fingers like a mouse wheel)
  defaults write -g com.apple.swipescrolldirection -bool false
  local d
  for d in com.apple.AppleMultitouchTrackpad com.apple.driver.AppleBluetoothMultitouch.trackpad; do
    defaults write "$d" Clicking -int 1                      # tap to click
    defaults write "$d" TrackpadRightClick -int 1            # two-finger secondary click
    defaults write "$d" TrackpadCornerSecondaryClick -int 0
    defaults write "$d" TrackpadThreeFingerDrag -int 0
    defaults write "$d" TrackpadThreeFingerTapGesture -int 0 # no look-up on 3-finger tap
    defaults write "$d" TrackpadTwoFingerDoubleTapGesture -int 1
    defaults write "$d" TrackpadTwoFingerFromRightEdgeSwipeGesture -int 3
    defaults write "$d" TrackpadThreeFingerHorizSwipeGesture -int 2
    defaults write "$d" TrackpadThreeFingerVertSwipeGesture -int 2
    defaults write "$d" TrackpadFourFingerHorizSwipeGesture -int 2
    defaults write "$d" TrackpadFourFingerVertSwipeGesture -int 2
    defaults write "$d" TrackpadPinch -int 1
    defaults write "$d" TrackpadRotate -int 1
    defaults write "$d" TrackpadMomentumScroll -int 1
    defaults write "$d" ActuateDetents -int 1
    defaults write "$d" FirstClickThreshold -int 1
    defaults write "$d" SecondClickThreshold -int 1
  done
  defaults -currentHost write -g com.apple.mouse.tapBehavior -int 1
  defaults write -g com.apple.mouse.tapBehavior -int 1
  defaults write -g com.apple.trackpad.scaling -float 2.5     # tracking speed
  ok "trackpad: tap to click, non-natural scrolling, speed 2.5"

  # --- Keyboard -------------------------------------------------------------
  defaults write -g KeyRepeat -int 5
  defaults write -g InitialKeyRepeat -int 25
  ok "key repeat: 5 / delay 25"

  # Input sources (keyboard languages)
  local entries='' name id
  while IFS='|' read -r name id; do
    case "$name" in ''|'#'*) continue ;; esac
    case "|$KEYBOARD_LAYOUTS|" in *"|$name|"*) ;; *) continue ;; esac
    entries="$entries<dict><key>InputSourceKind</key><string>Keyboard Layout</string><key>KeyboardLayout ID</key><integer>$id</integer><key>KeyboardLayout Name</key><string>$name</string></dict>
"
  done < "$NEWMAC_DIR/macos/input-sources.txt"
  if [ -n "$entries" ]; then
    local args=() line
    while IFS= read -r line; do [ -n "$line" ] && args+=("$line"); done <<EOF
$entries
EOF
    args+=('<dict><key>Bundle ID</key><string>com.apple.CharacterPaletteIM</string><key>InputSourceKind</key><string>Non Keyboard Input Method</string></dict>')
    defaults write com.apple.HIToolbox AppleEnabledInputSources -array "${args[@]}"
    # Show the input menu in the menu bar
    defaults write com.apple.TextInputMenu visible -bool true
    ok "keyboard layouts: $(echo "$KEYBOARD_LAYOUTS" | sed 's/|/, /g') (active after logout)"
  fi

  # --- Computer name -------------------------------------------------------
  if [ -n "${COMPUTER_NAME:-}" ] && [ "$COMPUTER_NAME" != "$(scutil --get ComputerName 2>/dev/null)" ]; then
    local host; host=$(printf '%s' "$COMPUTER_NAME" | tr -cs 'A-Za-z0-9' '-' | sed 's/^-*//; s/-*$//')
    sudo scutil --set ComputerName "$COMPUTER_NAME"
    sudo scutil --set LocalHostName "$host"
    sudo scutil --set HostName "$host"
    ok "computer name: $COMPUTER_NAME ($host.local)"
  fi

  # Apply what can be applied without logging out.
  killall cfprefsd 2>/dev/null
  /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true
  return 0
}

# mas_get ID NAME — install a free Mac App Store app (needs App Store sign-in)
mas_get() {
  local id=$1 name=$2
  if mas list 2>/dev/null | grep -q "^ *$id "; then
    ok "$name already installed"; return 0
  fi
  info "App Store: $name"
  mas get "$id" </dev/tty || mas install "$id" </dev/tty
}

step_xcode() {
  have mas || { err "mas missing (packages: core)"; return 1; }

  if ! mas_get 899247664 TestFlight; then
    warn "App Store install failed. Open the App Store app and sign in with your Apple Account."
    open -a "App Store"
    pause "Signed in? Press Enter to retry"
    mas_get 899247664 TestFlight || warn "TestFlight not installed"
  fi
  mas_get 640199958 "Developer (Apple)" || warn "Developer app not installed"

  if [ ! -d /Applications/Xcode.app ]; then
    info "Downloading Xcode (~10+ GB, this takes a while)…"
    mas_get 497799835 Xcode || { err "Xcode install failed — retry with: newmac xcode"; return 1; }
  fi

  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  sudo xcodebuild -license accept
  sudo xcodebuild -runFirstLaunch
  ok "$(xcodebuild -version | head -1) selected, license accepted"

  info "Downloading the latest iOS platform (SDK + Simulator runtime)…"
  xcodebuild -downloadPlatform iOS || warn "iOS platform download failed — retry: xcodebuild -downloadPlatform iOS"
  # Xcode 26+ ships the Metal toolchain separately; harmless if not needed.
  xcodebuild -downloadComponent MetalToolchain >/dev/null 2>&1 || true

  xcrun simctl list runtimes 2>/dev/null | grep -i ios | tail -3 | sed 's/^/    /'
}
