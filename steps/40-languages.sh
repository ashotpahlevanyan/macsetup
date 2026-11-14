# shellcheck shell=bash
#
# Steps: java (SDKMAN), node (nvm), python (Homebrew)
#
# SDKMAN and nvm are sourced inside ( subshells ): their scripts change a lot
# of shell state that the rest of newmac should not inherit.

# ─── java ────────────────────────────────────────────────────────────────────

step_java() {
  export SDKMAN_DIR="$HOME/.sdkman"

  if [ ! -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]; then
    info "Installing SDKMAN…"
    # rcupdate=false: our dotfiles already load SDKMAN.
    curl -fsSL "https://get.sdkman.io?rcupdate=false" | bash || return 1
  fi
  # Never stop to ask "Do you want java X to be set as default? (Y/n)".
  sed -i '' 's/^sdkman_auto_answer=.*/sdkman_auto_answer=true/' "$SDKMAN_DIR/etc/config"

  (
    # shellcheck disable=SC1091
    . "$SDKMAN_DIR/bin/sdkman-init.sh"
    sdk update >/dev/null 2>&1

    # Latest Temurin (Eclipse Adoptium) build, e.g. 25.0.1-tem
    latest=$(sdk list java 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)*-tem' | sort -uV | tail -1)
    if [ -n "$latest" ]; then
      info "Installing Java $latest"
      sdk install java "$latest" && sdk default java "$latest"
    else
      warn "Could not detect the latest Temurin; installing SDKMAN's default Java"
      sdk install java
    fi

    sdk install maven
    sdk install gradle
    java -version 2>&1 | head -1
  )
}

# ─── node ────────────────────────────────────────────────────────────────────

step_node() {
  export NVM_DIR="$HOME/.nvm"

  if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    local version
    version=$(curl -fsSL https://api.github.com/repos/nvm-sh/nvm/releases/latest |
      grep -m1 '"tag_name"' | cut -d'"' -f4)
    info "Installing nvm ${version:-(latest)}…"
    # PROFILE=/dev/null: leave our dotfiles alone (oh-my-zsh's nvm plugin loads nvm).
    PROFILE=/dev/null bash -c \
      "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/${version:-master}/install.sh | bash" ||
      return 1
  fi

  (
    # shellcheck disable=SC1091
    . "$NVM_DIR/nvm.sh"
    nvm install --lts --latest-npm || exit 1
    nvm alias default 'lts/*'
    nvm use default >/dev/null
    npm install -g yarn pnpm
    echo "node $(node -v), npm $(npm -v), yarn $(yarn -v), pnpm $(pnpm -v)"
  )
}

# ─── python ──────────────────────────────────────────────────────────────────

step_python() {
  have brew || return 1

  brew list python >/dev/null 2>&1 || brew install python
  have pipx || brew install pipx
  have uv || brew install uv
  pipx ensurepath >/dev/null 2>&1

  # Unversioned `python` / `pip` come from Homebrew's libexec/bin, which
  # dotfiles/.path puts on PATH.
  ok "$(python3 --version) at $(command -v python3)"
}
