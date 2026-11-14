# shellcheck shell=bash
# homebrew, packages, projects, claude

step_homebrew() {
  if ! xcode-select -p >/dev/null 2>&1; then
    info "Installing Xcode Command Line Tools (a system dialog may appear)…"
    # Headless install via softwareupdate; falls back to the GUI prompt.
    touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    local label
    label=$(softwareupdate -l 2>/dev/null | grep -E '\*.*Command Line Tools' | sed 's/^.*\* Label: //; s/^ *\* *//' | sort -V | tail -1)
    if [ -n "$label" ]; then
      sudo softwareupdate -i "$label" --verbose
    else
      xcode-select --install
      pause "Finish the Command Line Tools install dialog, then press Enter"
    fi
    rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  fi
  xcode-select -p >/dev/null 2>&1 && ok "Command Line Tools: $(xcode-select -p)"

  if [ "$(uname -m)" = arm64 ] && ! /usr/bin/pgrep -q oahd; then
    info "Installing Rosetta 2 (some apps still need it)…"
    sudo softwareupdate --install-rosetta --agree-to-license || warn "Rosetta install failed — not fatal."
  fi

  if ! have brew; then
    info "Installing Homebrew…"
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || return 1
    load_tool_env
  fi
  have brew || return 1
  brew analytics off >/dev/null 2>&1
  brew update
}

step_packages() {
  have brew || { err "Homebrew missing — run: newmac homebrew"; return 1; }
  local g rc=0
  # core first, always: everything else depends on it.
  for g in core $(echo "${PACKAGE_SELECTION:-core}" | tr '|' ' '); do
    [ "$g" = core ] && [ -n "${_core_done:-}" ] && continue
    [ -f "$NEWMAC_DIR/packages/$g.Brewfile" ] || continue
    info "brew bundle: $g"
    HOMEBREW_NO_AUTO_UPDATE=1 brew bundle --file="$NEWMAC_DIR/packages/$g.Brewfile" || { warn "some $g packages failed"; rc=1; }
    [ "$g" = core ] && _core_done=1
  done
  unset _core_done
  return $rc
}

step_projects() {
  local d; d=$(expand_tilde "${PROJECTS_DIR:-~/MyProjects}")
  mkdir -p "$d" && ok "projects dir: $d"
  if [ "${WORK_ENABLED:-n}" = y ] && [ -n "${WORK_DIR:-}" ]; then
    mkdir -p "$(expand_tilde "$WORK_DIR")" && ok "work dir: $(expand_tilde "$WORK_DIR")"
  fi
}

step_claude() {
  if have claude; then
    ok "Claude Code already installed: $(claude --version 2>/dev/null)"
    return 0
  fi
  # Native installer (auto-updates itself; installs to ~/.local/bin).
  curl -fsSL https://claude.ai/install.sh | bash || return 1
  load_tool_env
  have claude && ok "Claude Code $(claude --version 2>/dev/null) — run 'claude' to sign in"
}
