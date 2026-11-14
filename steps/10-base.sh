# shellcheck shell=bash
#
# Steps: homebrew, packages, projects, claude

# ─── homebrew ────────────────────────────────────────────────────────────────

step_homebrew() {
  install_command_line_tools
  install_rosetta
  install_homebrew || return 1

  brew analytics off >/dev/null 2>&1
  brew update
}

install_command_line_tools() {
  if xcode-select -p >/dev/null 2>&1; then
    ok "Command Line Tools: $(xcode-select -p)"
    return 0
  fi

  info "Installing Xcode Command Line Tools…"
  # This marker file makes `softwareupdate` list the Command Line Tools, so they
  # install without the GUI dialog.
  local marker=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  touch "$marker"

  local label
  label=$(softwareupdate -l 2>/dev/null |
    grep -E '\*.*Command Line Tools' |
    sed 's/^.*\* Label: //; s/^ *\* *//' |
    sort -V | tail -1)

  if [ -n "$label" ]; then
    sudo softwareupdate -i "$label" --verbose </dev/null
  else
    xcode-select --install
    pause "Finish the Command Line Tools install dialog, then press Enter"
  fi
  rm -f "$marker"
}

install_rosetta() {
  [ "$(uname -m)" = arm64 ] || return 0
  /usr/bin/pgrep -q oahd && return 0 # already installed

  info "Installing Rosetta 2 (some apps still need it)…"
  sudo softwareupdate --install-rosetta --agree-to-license ||
    warn "Rosetta install failed — not fatal."
}

install_homebrew() {
  if ! have brew; then
    info "Installing Homebrew…"
    local installer=https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL "$installer")" || return 1
    load_tool_env
  fi
  have brew
}

# ─── packages ────────────────────────────────────────────────────────────────

step_packages() {
  have brew || {
    err "Homebrew missing — run: newmac homebrew"
    return 1
  }

  # core first (everything else needs it), then the selected groups.
  local groups=(core) group failed=0
  for group in $(echo "${PACKAGE_SELECTION:-}" | tr '|' ' '); do
    [ "$group" = core ] || groups+=("$group")
  done

  for group in "${groups[@]}"; do
    local brewfile="$NEWMAC_DIR/packages/$group.Brewfile"
    [ -f "$brewfile" ] || continue

    info "brew bundle: $group"
    if ! HOMEBREW_NO_AUTO_UPDATE=1 brew bundle --file="$brewfile"; then
      warn "some $group packages failed"
      failed=1
    fi
  done
  return $failed
}

# ─── projects ────────────────────────────────────────────────────────────────

step_projects() {
  local projects
  projects=$(expand_tilde "${PROJECTS_DIR:-~/MyProjects}")
  mkdir -p "$projects" && ok "projects dir: $projects"

  if [ "${WORK_ENABLED:-n}" = y ] && [ -n "${WORK_DIR:-}" ]; then
    local work
    work=$(expand_tilde "$WORK_DIR")
    mkdir -p "$work" && ok "work dir: $work"
  fi
}

# ─── claude ──────────────────────────────────────────────────────────────────

step_claude() {
  if have claude; then
    ok "Claude Code already installed: $(claude --version 2>/dev/null)"
    return 0
  fi

  # The native installer puts `claude` in ~/.local/bin and keeps it updated.
  curl -fsSL https://claude.ai/install.sh | bash || return 1
  load_tool_env
  have claude && ok "Claude Code $(claude --version 2>/dev/null) — run 'claude' to sign in"
}
