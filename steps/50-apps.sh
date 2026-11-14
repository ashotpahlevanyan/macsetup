# shellcheck shell=bash
# IntelliJ plugins + settings, browser ad blocking.

intellij_app() {
  local a
  for a in "/Applications/IntelliJ IDEA.app" "/Applications/IntelliJ IDEA CE.app" "/Applications/IntelliJ IDEA Community Edition.app"; do
    [ -d "$a" ] && { echo "$a"; return 0; }
  done
  return 1
}

step_intellij() {
  local app; app=$(intellij_app) || { warn "IntelliJ IDEA not installed (packages: apps)"; return 1; }
  if pgrep -f "$app/Contents/MacOS" >/dev/null; then
    pause "Quit IntelliJ IDEA (⌘Q), then press Enter"
  fi

  # Config dir name = <dataDirectoryName> from the app's product-info.json,
  # e.g. IntelliJIdea2026.3
  local dataname cfg
  dataname=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["dataDirectoryName"])' "$app/Contents/Resources/product-info.json" 2>/dev/null)
  [ -n "$dataname" ] || { err "could not read IntelliJ product-info.json"; return 1; }
  cfg="$HOME/Library/Application Support/JetBrains/$dataname"
  mkdir -p "$cfg/options" "$cfg/colors" "$cfg/codestyles"

  # Settings: copy only if not already present, so a re-run never clobbers
  # changes you made in the IDE. Use `newmac capture` to go the other way.
  local f d n=0
  for d in options colors codestyles; do
    for f in "$NEWMAC_DIR/intellij/config/$d"/*; do
      [ -f "$f" ] || continue
      if [ ! -f "$cfg/$d/$(basename "$f")" ]; then
        cp "$f" "$cfg/$d/" && n=$((n + 1))
      fi
    done
  done
  ok "IntelliJ settings: $n files copied into $dataname"

  # Plugins from intellij/plugins.txt via the IDE's own installer.
  local ids
  ids=$(grep -v '^#' "$NEWMAC_DIR/intellij/plugins.txt" | awk '{print $1}' | grep -v '^$' | tr '\n' ' ')
  info "Installing plugins: $ids"
  # shellcheck disable=SC2086
  "$app/Contents/MacOS/idea" installPlugins $ids 2>&1 | grep -vE '^\s*$|WARN|SLF4J' | tail -5
  ls "$cfg/plugins" 2>/dev/null | sed 's/^/    /'
}

step_browsers() {
  local rc=0
  # Chrome: "external extension" file — Chrome installs Adblock Plus on next
  # start and asks you to enable it. https://developer.chrome.com/docs/extensions/how-to/distribute/install-extensions
  local abp_chrome=cfhdojbkjhnklbpkdaibdccddilifddb
  local ext_dir="$HOME/Library/Application Support/Google/Chrome/External Extensions"
  mkdir -p "$ext_dir"
  printf '{ "external_update_url": "https://clients2.google.com/service/update2/crx" }\n' > "$ext_dir/$abp_chrome.json"
  ok "Chrome: Adblock Plus queued (enable it when Chrome asks)"

  # Firefox: enterprise policy that installs Adblock Plus once (removable).
  local ff="/Applications/Firefox.app"
  if [ -d "$ff" ]; then
    local dist="$ff/Contents/Resources/distribution"
    mkdir -p "$dist" 2>/dev/null || sudo mkdir -p "$dist"
    local json='{
  "policies": {
    "Extensions": {
      "Install": ["https://addons.mozilla.org/firefox/downloads/latest/adblock-plus/latest.xpi"]
    }
  }
}'
    if printf '%s\n' "$json" > "$dist/policies.json" 2>/dev/null || printf '%s\n' "$json" | sudo tee "$dist/policies.json" >/dev/null; then
      ok "Firefox: Adblock Plus installs on next start"
    else
      warn "Firefox policy not written"; rc=1
    fi
  else
    warn "Firefox not installed (packages: apps)"
  fi
  return $rc
}
