# shellcheck shell=bash
# Java (SDKMAN), Node (nvm), Python (Homebrew).

step_java() {
  export SDKMAN_DIR="$HOME/.sdkman"
  if [ ! -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]; then
    info "Installing SDKMAN…"
    # rcupdate=false: our .zshrc / .bash_profile already load SDKMAN.
    curl -fsSL "https://get.sdkman.io?rcupdate=false" | bash || return 1
  fi
  # Never stop for "Do you want java X to be set as default? (Y/n)"
  sed -i '' 's/^sdkman_auto_answer=.*/sdkman_auto_answer=true/' "$SDKMAN_DIR/etc/config"

  # SDKMAN's scripts are not `set -u` safe; run them in a subshell.
  (
    set +u
    # shellcheck disable=SC1091
    . "$SDKMAN_DIR/bin/sdkman-init.sh"
    sdk update >/dev/null 2>&1
    # Latest Temurin (Eclipse Adoptium) GA build, e.g. 25.0.1-tem
    latest=$(sdk list java 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)*-tem' | sort -uV | tail -1)
    if [ -n "$latest" ]; then
      info "Installing Java $latest"
      sdk install java "$latest" && sdk default java "$latest"
    else
      warn "Could not detect latest Temurin; installing SDKMAN's default Java"
      sdk install java
    fi
    sdk install maven
    sdk install gradle
    java -version 2>&1 | head -1
  )
}

step_node() {
  export NVM_DIR="$HOME/.nvm"
  if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    local tag
    tag=$(curl -fsSL https://api.github.com/repos/nvm-sh/nvm/releases/latest | grep -m1 '"tag_name"' | cut -d'"' -f4)
    info "Installing nvm ${tag:-(latest)}…"
    # PROFILE=/dev/null: don't touch our dotfiles; the oh-my-zsh nvm plugin loads it.
    PROFILE=/dev/null bash -c "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/${tag:-master}/install.sh | bash" || return 1
  fi
  (
    set +u
    # shellcheck disable=SC1091
    . "$NVM_DIR/nvm.sh"
    nvm install --lts --latest-npm || exit 1
    nvm alias default 'lts/*'
    nvm use default >/dev/null
    npm install -g yarn pnpm
    printf 'node %s, npm %s, yarn %s, pnpm %s\n' "$(node -v)" "$(npm -v)" "$(yarn -v)" "$(pnpm -v)"
  )
}

step_python() {
  have brew || return 1
  brew list python >/dev/null 2>&1 || brew install python
  have pipx || brew install pipx
  have uv || brew install uv
  pipx ensurepath >/dev/null 2>&1
  ok "$(python3 --version) at $(command -v python3)"
  # `python` / `pip` (unversioned) come from Homebrew's libexec/bin, which
  # dotfiles/.path puts on PATH.
}
