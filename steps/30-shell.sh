# shellcheck shell=bash
# zsh + oh-my-zsh + dotfiles, and the iTerm2 profile.

DOTFILES=".zshrc .bashrc .bash_profile .aliases .functions .exports .path"

step_shell() {
  # oh-my-zsh (unattended, keeps our .zshrc, does not switch shells mid-run)
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    info "Installing oh-my-zsh…"
    ZSH="$HOME/.oh-my-zsh" RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || return 1
  fi
  local custom="$HOME/.oh-my-zsh/custom"
  clone_or_pull https://github.com/zsh-users/zsh-autosuggestions "$custom/plugins/zsh-autosuggestions"
  clone_or_pull https://github.com/zsh-users/zsh-syntax-highlighting "$custom/plugins/zsh-syntax-highlighting"

  local theme
  case "${ZSH_THEME_CHOICE:-agnoster}" in
    powerlevel10k*)
      clone_or_pull https://github.com/romkatv/powerlevel10k "$custom/themes/powerlevel10k"
      theme="powerlevel10k/powerlevel10k" ;;
    robbyrussell*) theme=robbyrussell ;;
    *)             theme=agnoster ;;
  esac

  # Dotfiles are symlinks into this repo: edit ~/.aliases, commit, push.
  local f
  for f in $DOTFILES; do
    if [ "$(readlink "$HOME/$f" 2>/dev/null)" != "$NEWMAC_DIR/dotfiles/$f" ]; then
      backup "$HOME/$f"
      ln -s "$NEWMAC_DIR/dotfiles/$f" "$HOME/$f"
    fi
  done
  ok "dotfiles linked: $DOTFILES"

  # Machine-local settings live outside the repo.
  local projects; projects=$(expand_tilde "${PROJECTS_DIR:-~/MyProjects}")
  cat > "$HOME/.zshrc.local" <<EOF
# Written by newmac — machine-specific, not in git. Sourced by ~/.zshrc.
ZSH_THEME="$theme"
export PROJECTS_DIR="$projects"
EOF
  ok "zsh theme: $theme"

  # iTerm2 shell integration (marks, cwd tracking, imgcat …)
  curl -fsSL https://iterm2.com/shell_integration/zsh -o "$HOME/.iterm2_shell_integration.zsh" \
    && ok "iTerm2 shell integration installed"

  # macOS uses /bin/zsh by default; make sure we're on it.
  if [ "$(dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}')" != /bin/zsh ]; then
    sudo chsh -s /bin/zsh "$USER"
  fi
}

clone_or_pull() {
  if [ -d "$2/.git" ]; then
    git -C "$2" pull --ff-only -q || warn "could not update $2"
  else
    git clone --depth=1 -q "$1" "$2" && ok "installed $(basename "$2")"
  fi
}

# Map the font choice to its Homebrew-installed file and PostScript name.
font_postscript_name() {
  local file guess
  case "$1" in
    MesloLGS*)     file=MesloLGSNerdFontMono-Regular.ttf;    guess=MesloLGSNFM-Regular ;;
    Hack*)         file=HackNerdFontMono-Regular.ttf;        guess=HackNFM-Regular ;;
    JetBrains*)    file=JetBrainsMonoNerdFontMono-Regular.ttf; guess=JetBrainsMonoNFM-Regular ;;
    Fira*)         file=FiraCodeNerdFontMono-Regular.ttf;    guess=FiraCodeNFM-Reg ;;
    *)             echo "Menlo-Regular"; return ;;
  esac
  local path ps=''
  for path in "$HOME/Library/Fonts/$file" "/Library/Fonts/$file"; do
    if [ -f "$path" ]; then
      ps=$(mdls -raw -name com_apple_ats_name_postscript "$path" 2>/dev/null | tr -d '()" \n' | cut -d, -f1)
      break
    fi
  done
  [ -n "$ps" ] && [ "$ps" != null ] && echo "$ps" || echo "$guess"
}

step_iterm() {
  [ -d /Applications/iTerm.app ] || { warn "iTerm2 not installed (packages: apps)"; return 1; }
  have python3 || { err "python3 missing (packages: core)"; return 1; }

  if pgrep -xq iTerm2; then
    warn "iTerm2 is running — it would overwrite the new profile when it quits."
    pause "Quit iTerm2 (⌘Q), then press Enter"
  fi

  local base="$NEWMAC_DIR/iterm/profiles/material.json" scheme_json='' name
  case "$ITERM_SCHEME" in
    "My saved"*) name="My Material" ;;
    *)
      name=$ITERM_SCHEME
      local tmp; tmp=$(mktemp -d)
      local url="https://raw.githubusercontent.com/mbadolato/iTerm2-Color-Schemes/master/schemes/$(printf '%s' "$ITERM_SCHEME" | sed 's/ /%20/g; s/+/%2B/g').itermcolors"
      if curl -fsSL "$url" -o "$tmp/scheme.itermcolors" && plutil -convert json -o "$tmp/scheme.json" "$tmp/scheme.itermcolors"; then
        scheme_json="$tmp/scheme.json"
      else
        warn "Could not download '$ITERM_SCHEME' — keeping the saved Material colors."
        name="My Material"
      fi
      ;;
  esac

  local font; font=$(font_postscript_name "$ITERM_FONT")
  local projects; projects=$(expand_tilde "${PROJECTS_DIR:-~/MyProjects}")
  mkdir -p "$projects"

  defaults export com.googlecode.iterm2 - 2>/dev/null \
    | python3 "$NEWMAC_DIR/iterm/iterm_profile.py" apply "$base" \
        ${scheme_json:+--scheme "$scheme_json"} --font "$font" --size "${ITERM_FONT_SIZE:-18}" \
        --dir "$projects" --name "$name" \
    > "$NEWMAC_CONFIG_DIR/iterm.plist" || return 1
  defaults import com.googlecode.iterm2 "$NEWMAC_CONFIG_DIR/iterm.plist" || return 1
  rm -f "$NEWMAC_CONFIG_DIR/iterm.plist"
  ok "iTerm2 default profile: $name, $font ${ITERM_FONT_SIZE:-18}pt, opens in $projects"
}
