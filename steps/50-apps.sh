# shellcheck shell=bash
#
# Steps: intellij, browsers

# ─── intellij ────────────────────────────────────────────────────────────────

step_intellij() {
  local app
  app=$(find_intellij) || {
    warn "IntelliJ IDEA not installed (package group: apps)"
    return 1
  }

  if pgrep -f "$app/Contents/MacOS" >/dev/null; then
    pause "Quit IntelliJ IDEA (⌘Q), then press Enter"
  fi

  local config
  config=$(intellij_config_dir "$app") || {
    err "Could not read IntelliJ's product-info.json"
    return 1
  }

  copy_intellij_settings "$config"
  install_intellij_plugins "$app" "$config"
}

find_intellij() {
  local app
  for app in \
    "/Applications/IntelliJ IDEA.app" \
    "/Applications/IntelliJ IDEA CE.app" \
    "/Applications/IntelliJ IDEA Community Edition.app"; do
    [ -d "$app" ] && echo "$app" && return 0
  done
  return 1
}

# ~/Library/Application Support/JetBrains/<dataDirectoryName>, where the name
# (e.g. IntelliJIdea2026.3) comes from the app's product-info.json.
intellij_config_dir() {
  local name
  name=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["dataDirectoryName"])' \
    "$1/Contents/Resources/product-info.json" 2>/dev/null) || return 1
  [ -n "$name" ] && echo "$HOME/Library/Application Support/JetBrains/$name"
}

# Copy only files that aren't there yet, so a re-run never overwrites changes
# made in the IDE. (`newmac capture` goes the other way.)
copy_intellij_settings() {
  local config=$1 kind file copied=0
  for kind in options colors codestyles; do
    mkdir -p "$config/$kind"
    for file in "$NEWMAC_DIR/intellij/config/$kind"/*; do
      [ -f "$file" ] || continue
      [ -f "$config/$kind/${file##*/}" ] && continue
      cp "$file" "$config/$kind/" && copied=$((copied + 1))
    done
  done
  ok "IntelliJ settings: $copied files copied into ${config##*/}"
}

# Plugin IDs from intellij/plugins.txt, installed by the IDE's own CLI.
install_intellij_plugins() {
  local app=$1 config=$2 ids
  ids=$(grep -v '^#' "$NEWMAC_DIR/intellij/plugins.txt" | awk 'NF {print $1}')

  info "Installing plugins: $(echo "$ids" | tr '\n' ' ')"
  # shellcheck disable=SC2086
  "$app/Contents/MacOS/idea" installPlugins $ids 2>&1 |
    grep -vE '^\s*$|WARN|SLF4J' | tail -5

  find "$config/plugins" -mindepth 1 -maxdepth 1 -exec basename {} \; 2>/dev/null | sed 's/^/    /'
}

# ─── browsers ────────────────────────────────────────────────────────────────

step_browsers() {
  add_adblock_to_chrome
  add_adblock_to_firefox
}

# Chrome installs "external extensions" listed in this folder on its next
# start and asks you to enable them.
# https://developer.chrome.com/docs/extensions/how-to/distribute/install-extensions
add_adblock_to_chrome() {
  local adblock_plus_id=cfhdojbkjhnklbpkdaibdccddilifddb
  local folder="$HOME/Library/Application Support/Google/Chrome/External Extensions"

  mkdir -p "$folder"
  echo '{ "external_update_url": "https://clients2.google.com/service/update2/crx" }' \
    >"$folder/$adblock_plus_id.json"
  ok "Chrome: Adblock Plus queued (enable it when Chrome asks)"
}

# Firefox enterprise policy: install Adblock Plus once (you can remove it).
add_adblock_to_firefox() {
  local firefox=/Applications/Firefox.app
  [ -d "$firefox" ] || {
    warn "Firefox not installed (package group: apps)"
    return 0
  }

  local folder="$firefox/Contents/Resources/distribution"
  local policy='{
  "policies": {
    "Extensions": {
      "Install": ["https://addons.mozilla.org/firefox/downloads/latest/adblock-plus/latest.xpi"]
    }
  }
}'

  # Homebrew installs Firefox as you; fall back to sudo if it isn't writable.
  if ! write_firefox_policy "$folder" "$policy" 2>/dev/null &&
    ! write_firefox_policy "$folder" "$policy" sudo; then
    warn "Firefox policy not written"
    return 1
  fi
  ok "Firefox: Adblock Plus installs on next start"
}

# write_firefox_policy FOLDER JSON [sudo]
write_firefox_policy() {
  local folder=$1 policy=$2 sudo=${3:-}
  $sudo mkdir -p "$folder" &&
    echo "$policy" | $sudo tee "$folder/policies.json" >/dev/null
}
