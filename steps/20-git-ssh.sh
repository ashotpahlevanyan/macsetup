# shellcheck shell=bash
# git + ssh: one ed25519 key per GitHub account, ~/.ssh/config with a host
# alias per account, keys uploaded to GitHub with `gh`.
#
#   personal:  git@github.com:user/repo.git
#   work:      git@github-work:org/repo.git   (repos under WORK_DIR also
#              commit with the work email via includeIf)

step_git() {
  have git || return 1
  git config --global user.name  "$GIT_NAME"
  git config --global user.email "$GIT_EMAIL"
  git config --global init.defaultBranch main
  git config --global pull.rebase false
  git config --global push.autoSetupRemote true
  git config --global core.excludesfile "$HOME/.gitignore_global"
  [ -f "$HOME/.gitignore_global" ] || printf '.DS_Store\n.idea/\n*.iml\n.vscode/\nnode_modules/\n.env\n' > "$HOME/.gitignore_global"

  if [ "${WORK_ENABLED:-n}" = y ]; then
    local wd; wd=$(expand_tilde "$WORK_DIR")
    printf '[user]\n\temail = %s\n[core]\n\tsshCommand = ssh -i ~/.ssh/id_ed25519_github_work -o IdentitiesOnly=yes\n' "$WORK_EMAIL" > "$HOME/.gitconfig-work"
    git config --global "includeIf.gitdir:${wd%/}/.path" "$HOME/.gitconfig-work"
    ok "repos under $wd use $WORK_EMAIL and the work key"
  fi

  if have gh; then
    # HTTPS remotes authenticate through gh (as on the old Mac).
    gh auth setup-git >/dev/null 2>&1 || true
  fi
  ok "git: $GIT_NAME <$GIT_EMAIL>"
}

# make_key LABEL EMAIL -> creates ~/.ssh/id_ed25519_github_LABEL if missing
make_key() {
  local label=$1 email=$2 key="$HOME/.ssh/id_ed25519_github_$1"
  if [ -f "$key" ]; then
    ok "key exists: $key"
  else
    info "Creating SSH key for $email ($label). Choose a passphrase (stored in Keychain):"
    ssh-keygen -t ed25519 -C "$email" -f "$key" </dev/tty >/dev/tty 2>&1 || return 1
  fi
  ssh-add --apple-use-keychain "$key" </dev/tty >/dev/tty 2>&1 || warn "could not add $key to the agent"
}

# gh_login_and_upload GH_USER LABEL
gh_login_and_upload() {
  local user=$1 label=$2 pub="$HOME/.ssh/id_ed25519_github_$2.pub" title
  title="$(scutil --get ComputerName 2>/dev/null || hostname) ($label)"

  if gh auth status --hostname github.com 2>/dev/null | grep -q "account $user"; then
    gh auth switch --hostname github.com --user "$user" >/dev/null 2>&1
    # Need the scope to upload keys.
    if ! gh auth status --hostname github.com 2>&1 | grep -A6 "account $user" | grep -q 'admin:public_key'; then
      gh auth refresh --hostname github.com --scopes admin:public_key </dev/tty >/dev/tty 2>&1 || return 1
    fi
  else
    info "Log in to GitHub as ${C_BOLD}$user${C_RESET}${C_CYAN} in the browser that opens."
    [ "$label" = work ] && warn "Sign out of $GH_USER on github.com first (or use a private window), or you'll authorize the wrong account."
    gh auth login --hostname github.com --git-protocol ssh --skip-ssh-key --web \
      --scopes admin:public_key </dev/tty >/dev/tty 2>&1 || return 1
  fi

  local who; who=$(gh api user --jq .login 2>/dev/null)
  if [ "$who" != "$user" ]; then
    err "gh is logged in as '$who', expected '$user'. Skipping key upload for $label."
    return 1
  fi

  local fp; fp=$(awk '{print $2}' "$pub")
  if gh ssh-key list 2>/dev/null | grep -q "$fp"; then
    ok "$label key already on GitHub ($user)"
  else
    gh ssh-key add "$pub" --title "$title" --type authentication && ok "$label key uploaded to GitHub ($user)"
  fi
}

step_ssh() {
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"

  make_key personal "$GIT_EMAIL" || return 1
  [ "${WORK_ENABLED:-n}" = y ] && { make_key work "$WORK_EMAIL" || return 1; }

  # ~/.ssh/config: managed block on top, anything you add below it is kept.
  [ -f "$HOME/.ssh/config" ] && cp "$HOME/.ssh/config" "$HOME/.ssh/config.bak"
  {
    cat <<EOF
# Defaults for all hosts
Host *
  AddKeysToAgent yes
  UseKeychain yes
  IdentitiesOnly yes

# GitHub - personal ($GH_USER, default): git@github.com:user/repo.git
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_github_personal
EOF
    if [ "${WORK_ENABLED:-n}" = y ]; then
      cat <<EOF

# GitHub - work ($WORK_GH_USER): git@github-work:org/repo.git
Host github-work
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_github_work
EOF
    fi
  } | write_managed_block "$HOME/.ssh/config" ssh
  # A pre-existing unmanaged "Host *" block below ours would duplicate options
  # harmlessly (ssh uses the first value it sees).
  chmod 600 "$HOME/.ssh/config"
  ok "~/.ssh/config written"

  # GitHub host keys from GitHub's HTTPS API, not blind trust-on-first-use.
  if have jq; then
    ssh-keygen -R github.com >/dev/null 2>&1
    curl -fsSL https://api.github.com/meta | jq -r '.ssh_keys[]' | sed 's/^/github.com /' >> "$HOME/.ssh/known_hosts" \
      && ok "GitHub host keys added to known_hosts"
  fi

  have gh || { warn "gh not installed — upload keys later with: newmac ssh"; return 1; }
  gh_login_and_upload "$GH_USER" personal || return 1
  if [ "${WORK_ENABLED:-n}" = y ]; then
    gh_login_and_upload "$WORK_GH_USER" work || warn "work key not uploaded"
    gh auth switch --hostname github.com --user "$GH_USER" >/dev/null 2>&1
  fi
  gh auth setup-git >/dev/null 2>&1 || true

  # The repo was cloned over HTTPS by bootstrap.sh; switch it to SSH so you
  # can push changes to your dotfiles.
  local origin; origin=$(git -C "$NEWMAC_DIR" remote get-url origin 2>/dev/null)
  case "$origin" in
    https://github.com/*)
      local slug=${origin#https://github.com/}
      git -C "$NEWMAC_DIR" remote set-url origin "git@github.com:${slug%.git}.git" && ok "macsetup remote -> SSH" ;;
  esac

  info "Testing SSH to GitHub…"
  ssh -T git@github.com 2>&1 | grep -i 'successfully authenticated' && ok "personal SSH works"
  [ "${WORK_ENABLED:-n}" = y ] && ssh -T git@github-work 2>&1 | grep -i 'successfully authenticated' && ok "work SSH works"
  return 0
}
