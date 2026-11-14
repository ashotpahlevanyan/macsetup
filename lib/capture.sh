# shellcheck shell=bash
#
# `newmac capture` — copy this Mac's current settings back into the repo, so
# the next wipe gets whatever you changed since. Dotfiles need no capture:
# they are already symlinks into this repo.

capture_current_settings() {
  header "Capturing this Mac's settings into $NEWMAC_DIR"
  capture_keyboard_layouts
  capture_intellij_settings
  capture_iterm_profile
  info "Review with: git -C \"$NEWMAC_DIR\" diff"
}

# Append any enabled keyboard layout that macos/input-sources.txt lacks.
capture_keyboard_layouts() {
  local list="$NEWMAC_DIR/macos/input-sources.txt" current
  current=$(
    defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null |
      /usr/bin/python3 "$NEWMAC_DIR/macos/parse_input_sources.py"
  )
  [ -n "$current" ] || return 0

  local line added=0
  while IFS= read -r line; do
    if ! grep -qxF "$line" "$list"; then
      echo "$line" >>"$list"
      added=$((added + 1))
    fi
  done <<<"$current"
  ok "keyboard layouts: $added new -> macos/input-sources.txt"
}

capture_intellij_settings() {
  local jetbrains="$HOME/Library/Application Support/JetBrains" config file
  # Newest IntelliJ config folder, e.g. IntelliJIdea2026.3
  config=$(find "$jetbrains" -maxdepth 1 -type d \( -name 'IntelliJIdea*' -o -name 'IdeaIC*' \) 2>/dev/null |
    sort | tail -1)
  [ -n "$config" ] || return 0

  local repo="$NEWMAC_DIR/intellij/config"
  cp "$config"/colors/*.icls "$repo/colors/" 2>/dev/null
  cp "$config"/codestyles/*.xml "$repo/codestyles/" 2>/dev/null
  # Only refresh the option files we already track.
  for file in "$repo"/options/*.xml; do
    [ -f "$config/options/${file##*/}" ] && cp "$config/options/${file##*/}" "$file"
  done

  ok "IntelliJ settings from ${config##*/} -> intellij/config"
  warn "New plugins are not detected: add their IDs to intellij/plugins.txt"
}

capture_iterm_profile() {
  defaults read com.googlecode.iterm2 >/dev/null 2>&1 || return 0
  defaults export com.googlecode.iterm2 - |
    /usr/bin/python3 "$NEWMAC_DIR/iterm/iterm_profile.py" export "$NEWMAC_DIR/iterm/profiles/material.json" &&
    ok "iTerm2 default profile -> iterm/profiles/material.json"
}
