# ~/.zshrc — symlinked from the macsetup repo (dotfiles/.zshrc).
# Machine-specific bits (theme, projects dir) live in ~/.zshrc.local.

# PATH and env load BEFORE oh-my-zsh so its plugins find the binaries they
# probe for (docker, nvm, …). Aliases/functions load at the END so they
# override the ones those plugins define.
for file in ~/.{path,exports}; do
  [ -r "$file" ] && source "$file"
done
unset file

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="agnoster"
[ -r ~/.zshrc.local ] && source ~/.zshrc.local

DEFAULT_USER=$(id -un)   # agnoster: hide user@host when it's me

# nvm: loaded by the oh-my-zsh nvm plugin below.
export NVM_DIR="$HOME/.nvm"

plugins=(
  git
  docker
  docker-compose
  yarn
  mvn
  npm
  nvm
  node
  heroku
  python
  zsh-autosuggestions
  zsh-syntax-highlighting
  web-search
  sudo
  copybuffer
  copypath
  copyfile
  dirhistory
  history
  jsontools
  vi-mode
)

[ -r "$ZSH/oh-my-zsh.sh" ] && source "$ZSH/oh-my-zsh.sh"

# powerlevel10k config, if that theme was chosen (run `p10k configure`)
[[ "$ZSH_THEME" == powerlevel10k* && -r ~/.p10k.zsh ]] && source ~/.p10k.zsh

# SSH keys: load the ones stored in the macOS Keychain
ssh-add --apple-load-keychain 2>/dev/null

test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"

prompt_context() {}   # agnoster: never show user@host segment

# SDKMAN — keep near the end so it can set JAVA_HOME / PATH.
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"

# If SDKMAN has no Java yet, JAVA_HOME points at a dead "current" path and
# Gradle refuses to start. Fall back to any installed JDK in that case.
if [[ ! -x "${JAVA_HOME}/bin/java" && -x /usr/libexec/java_home ]]; then
  export JAVA_HOME="$(/usr/libexec/java_home 2>/dev/null)"
fi

export PATH="$HOME/.local/bin:$PATH"

# Sourced last so these win over oh-my-zsh plugin aliases.
for file in ~/.{aliases,functions}; do
  [ -r "$file" ] && source "$file"
done
unset file
