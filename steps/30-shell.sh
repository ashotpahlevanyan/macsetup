# shellcheck shell=bash
#
# Steps: shell, iterm

DOTFILES=(.zshrc .bashrc .bash_profile .aliases .functions .exports .path)

# ─── shell ───────────────────────────────────────────────────────────────────

step_shell() {
  install_oh_my_zsh || return 1
  link_dotfiles
  write_zshrc_local
  install_iterm_shell_integration
  make_zsh_the_login_shell
}

install_oh_my_zsh() {
  local omz="$HOME/.oh-my-zsh"
  local custom="$omz/custom"

  if [ ! -d "$omz" ]; then
    info "Installing oh-my-zsh…"
    local installer=https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh
    # Unattended; keep our .zshrc; don't switch shells in the middle of the run.
    ZSH="$omz" RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
      sh -c "$(curl -fsSL "$installer")" "" --unattended || return 1
  fi

  clone_or_pull https://github.com/zsh-users/zsh-autosuggestions "$custom/plugins/zsh-autosuggestions"
  clone_or_pull https://github.com/zsh-users/zsh-syntax-highlighting "$custom/plugins/zsh-syntax-highlighting"
  if [[ ${ZSH_THEME_CHOICE:-} == powerlevel10k* ]]; then
    clone_or_pull https://github.com/romkatv/powerlevel10k "$custom/themes/powerlevel10k"
  fi
}

# Dotfiles are symlinks into this repo: edit ~/.aliases, then commit and push.
link_dotfiles() {
  local file target
  for file in "${DOTFILES[@]}"; do
    target="$NEWMAC_DIR/dotfiles/$file"
    [ "$(readlink "$HOME/$file")" = "$target" ] && continue
    backup "$HOME/$file"
    ln -s "$target" "$HOME/$file"
  done
  ok "dotfiles linked: ${DOTFILES[*]}"
}

# Machine-specific settings live outside the repo, in ~/.zshrc.local.
write_zshrc_local() {
  local theme projects
  case "${ZSH_THEME_CHOICE:-agnoster}" in
    powerlevel10k*) theme="powerlevel10k/powerlevel10k" ;;
    robbyrussell*) theme="robbyrussell" ;;
    *) theme="agnoster" ;;
  esac
  projects=$(expand_tilde "${PROJECTS_DIR:-~/MyProjects}")

  cat >"$HOME/.zshrc.local" <<EOF
# Written by newmac — machine-specific, not in git. Sourced by ~/.zshrc.
ZSH_THEME="$theme"
export PROJECTS_DIR="$projects"
EOF
  ok "zsh theme: $theme"
}

# Command marks, current-directory tracking, imgcat, …
install_iterm_shell_integration() {
  curl -fsSL https://iterm2.com/shell_integration/zsh -o "$HOME/.iterm2_shell_integration.zsh" &&
    ok "iTerm2 shell integration installed"
}

make_zsh_the_login_shell() {
  local current
  current=$(dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}')
  [ "$current" = /bin/zsh ] || sudo chsh -s /bin/zsh "$USER"
}

clone_or_pull() {
  local url=$1 dir=$2
  if [ -d "$dir/.git" ]; then
    git -C "$dir" pull --ff-only -q || warn "could not update $dir"
  else
    git clone --depth=1 -q "$url" "$dir" && ok "installed ${dir##*/}"
  fi
}

# ─── iterm ───────────────────────────────────────────────────────────────────

step_iterm() {
  [ -d /Applications/iTerm.app ] || {
    warn "iTerm2 not installed (package group: apps)"
    return 1
  }
  have python3 || {
    err "python3 missing (package group: core)"
    return 1
  }

  if pgrep -xq iTerm2; then
    warn "iTerm2 is running — it would overwrite the new profile when it quits."
    pause "Quit iTerm2 (⌘Q), then press Enter"
  fi

  local name=$ITERM_SCHEME scheme_json=''
  if [[ $ITERM_SCHEME == "My saved"* ]]; then
    name="My Material"
  elif ! scheme_json=$(download_iterm_scheme "$ITERM_SCHEME"); then
    warn "Could not download '$ITERM_SCHEME' — keeping the saved Material colors."
    name="My Material"
    scheme_json=''
  fi

  local font projects
  font=$(font_postscript_name "$ITERM_FONT")
  projects=$(expand_tilde "${PROJECTS_DIR:-~/MyProjects}")
  mkdir -p "$projects"

  local prefs="$NEWMAC_CONFIG_DIR/iterm.plist"
  defaults export com.googlecode.iterm2 - 2>/dev/null |
    python3 "$NEWMAC_DIR/iterm/iterm_profile.py" apply \
      "$NEWMAC_DIR/iterm/profiles/material.json" \
      ${scheme_json:+--scheme "$scheme_json"} \
      --font "$font" \
      --size "${ITERM_FONT_SIZE:-18}" \
      --dir "$projects" \
      --name "$name" \
      >"$prefs" || return 1
  defaults import com.googlecode.iterm2 "$prefs" || return 1
  rm -f "$prefs"

  ok "iTerm2 default profile: $name, $font ${ITERM_FONT_SIZE:-18}pt, opens in $projects"
}

# Download a color scheme from iTerm2-Color-Schemes, convert it to JSON and
# print the JSON file's path.
download_iterm_scheme() {
  local name=$1 dir encoded
  dir=$(mktemp -d)
  encoded=$(printf '%s' "$name" | sed 's/ /%20/g; s/+/%2B/g')

  curl -fsSL -o "$dir/scheme.itermcolors" \
    "https://raw.githubusercontent.com/mbadolato/iTerm2-Color-Schemes/master/schemes/$encoded.itermcolors" &&
    plutil -convert json -o "$dir/scheme.json" "$dir/scheme.itermcolors" &&
    echo "$dir/scheme.json"
}

# The PostScript name iTerm2 needs for a font choice, e.g. MesloLGSNFM-Regular.
# Read from the installed font file; the guess is used if that fails.
font_postscript_name() {
  local file guess
  case "$1" in
    MesloLGS*) file=MesloLGSNerdFontMono-Regular.ttf guess=MesloLGSNFM-Regular ;;
    Hack*) file=HackNerdFontMono-Regular.ttf guess=HackNFM-Regular ;;
    JetBrains*) file=JetBrainsMonoNerdFontMono-Regular.ttf guess=JetBrainsMonoNFM-Regular ;;
    Fira*) file=FiraCodeNerdFontMono-Regular.ttf guess=FiraCodeNFM-Reg ;;
    *)
      echo "Menlo-Regular"
      return
      ;;
  esac

  local path name
  for path in "$HOME/Library/Fonts/$file" "/Library/Fonts/$file"; do
    [ -f "$path" ] || continue
    name=$(mdls -raw -name com_apple_ats_name_postscript "$path" 2>/dev/null |
      tr -d '()" \n' | cut -d, -f1)
    break
  done

  if [ -n "$name" ] && [ "$name" != null ]; then
    echo "$name"
  else
    echo "$guess"
  fi
}
