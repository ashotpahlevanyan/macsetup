# shellcheck shell=bash
#
# Steps: git, ssh
#
# One ed25519 key per GitHub account, and a host alias per account:
#
#   personal   git@github.com:user/repo.git
#   work       git@github-work:org/repo.git
#
# Repos under WORK_DIR also commit with the work email (git includeIf).

# ─── git ─────────────────────────────────────────────────────────────────────

step_git() {
  have git || return 1

  git config --global user.name "$GIT_NAME"
  git config --global user.email "$GIT_EMAIL"
  git config --global init.defaultBranch main
  git config --global pull.rebase false
  git config --global push.autoSetupRemote true
  git config --global core.excludesfile "$HOME/.gitignore_global"
  write_global_gitignore

  [ "${WORK_ENABLED:-n}" = y ] && configure_work_identity

  # HTTPS remotes authenticate through gh (as on the previous Mac).
  have gh && gh auth setup-git >/dev/null 2>&1

  ok "git: $GIT_NAME <$GIT_EMAIL>"
}

write_global_gitignore() {
  [ -f "$HOME/.gitignore_global" ] && return 0
  cat >"$HOME/.gitignore_global" <<'EOF'
.DS_Store
.idea/
*.iml
.vscode/
node_modules/
.env
EOF
}

configure_work_identity() {
  local work_dir
  work_dir=$(expand_tilde "$WORK_DIR")

  cat >"$HOME/.gitconfig-work" <<EOF
[user]
	email = $WORK_EMAIL
[core]
	sshCommand = ssh -i ~/.ssh/id_ed25519_github_work -o IdentitiesOnly=yes
EOF
  git config --global "includeIf.gitdir:${work_dir%/}/.path" "$HOME/.gitconfig-work"
  ok "repos under $work_dir use $WORK_EMAIL and the work key"
}

# ─── ssh ─────────────────────────────────────────────────────────────────────

step_ssh() {
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"

  create_ssh_key personal "$GIT_EMAIL" || return 1
  if [ "${WORK_ENABLED:-n}" = y ]; then
    create_ssh_key work "$WORK_EMAIL" || return 1
  fi

  write_ssh_config
  add_github_host_keys

  have gh || {
    warn "gh not installed — upload keys later with: newmac ssh"
    return 1
  }
  upload_key_to_github "$GH_USER" personal || return 1
  if [ "${WORK_ENABLED:-n}" = y ]; then
    upload_key_to_github "$WORK_GH_USER" work || warn "work key not uploaded"
    gh auth switch --hostname github.com --user "$GH_USER" >/dev/null 2>&1
  fi
  gh auth setup-git >/dev/null 2>&1

  switch_this_repo_to_ssh
  test_github_ssh
}

# create_ssh_key LABEL EMAIL  ->  ~/.ssh/id_ed25519_github_LABEL
create_ssh_key() {
  local label=$1 email=$2
  local key="$HOME/.ssh/id_ed25519_github_$label"

  if [ -f "$key" ]; then
    ok "key exists: $key"
  else
    info "Creating SSH key for $email ($label). Choose a passphrase (it is kept in Keychain):"
    ssh-keygen -t ed25519 -C "$email" -f "$key" </dev/tty >/dev/tty 2>&1 || return 1
  fi

  ssh-add --apple-use-keychain "$key" </dev/tty >/dev/tty 2>&1 ||
    warn "could not add $key to the SSH agent"
}

# The newmac block goes at the top of ~/.ssh/config; anything you add below
# it is kept on re-runs.
write_ssh_config() {
  [ -f "$HOME/.ssh/config" ] && cp "$HOME/.ssh/config" "$HOME/.ssh/config.bak"

  {
    cat <<EOF
# Defaults for all hosts
Host *
  AddKeysToAgent yes
  UseKeychain yes
  IdentitiesOnly yes

# GitHub - personal ($GH_USER): git@github.com:user/repo.git
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

  chmod 600 "$HOME/.ssh/config"
  ok "$HOME/.ssh/config written"
}

# Trust GitHub's host keys as published on its HTTPS API, instead of
# accepting whatever answers on first connect.
add_github_host_keys() {
  have jq || return 0
  ssh-keygen -R github.com >/dev/null 2>&1
  curl -fsSL https://api.github.com/meta |
    jq -r '.ssh_keys[]' |
    sed 's/^/github.com /' >>"$HOME/.ssh/known_hosts" &&
    ok "GitHub host keys added to known_hosts"
}

# upload_key_to_github GITHUB_USER LABEL
upload_key_to_github() {
  local user=$1 label=$2
  local public_key="$HOME/.ssh/id_ed25519_github_$label.pub"
  local title
  title="$(scutil --get ComputerName 2>/dev/null || hostname) ($label)"

  log_in_to_github "$user" "$label" || return 1

  local logged_in_as
  logged_in_as=$(gh api user --jq .login 2>/dev/null)
  if [ "$logged_in_as" != "$user" ]; then
    err "gh is logged in as '$logged_in_as', expected '$user'. Skipping the $label key."
    return 1
  fi

  local fingerprint
  fingerprint=$(awk '{print $2}' "$public_key")
  if gh ssh-key list 2>/dev/null | grep -q "$fingerprint"; then
    ok "$label key already on GitHub ($user)"
  else
    gh ssh-key add "$public_key" --title "$title" --type authentication &&
      ok "$label key uploaded to GitHub ($user)"
  fi
}

# Make USER the active gh account, logging in through the browser if needed.
# Uploading keys needs the admin:public_key scope.
log_in_to_github() {
  local user=$1 label=$2

  if gh auth status --hostname github.com 2>/dev/null | grep -q "account $user"; then
    gh auth switch --hostname github.com --user "$user" >/dev/null 2>&1
    if ! gh auth status --hostname github.com 2>&1 | grep -A6 "account $user" | grep -q 'admin:public_key'; then
      gh auth refresh --hostname github.com --scopes admin:public_key </dev/tty >/dev/tty 2>&1
    fi
    return
  fi

  info "Log in to GitHub as ${BOLD}$user${RESET}${CYAN} in the browser that opens."
  if [ "$label" = work ]; then
    warn "Sign out of $GH_USER on github.com first (or use a private window),"
    warn "otherwise you authorize the wrong account."
  fi
  gh auth login --hostname github.com --git-protocol ssh --skip-ssh-key --web \
    --scopes admin:public_key </dev/tty >/dev/tty 2>&1
}

# bootstrap.sh cloned this repo over HTTPS; switch it to SSH so you can push.
switch_this_repo_to_ssh() {
  local origin
  origin=$(git -C "$NEWMAC_DIR" remote get-url origin 2>/dev/null)
  case "$origin" in
    https://github.com/*)
      local repo=${origin#https://github.com/}
      git -C "$NEWMAC_DIR" remote set-url origin "git@github.com:${repo%.git}.git" &&
        ok "macsetup remote -> SSH"
      ;;
  esac
}

test_github_ssh() {
  info "Testing SSH to GitHub…"
  ssh -T git@github.com 2>&1 | grep -qi 'successfully authenticated' &&
    ok "personal SSH works"
  if [ "${WORK_ENABLED:-n}" = y ]; then
    ssh -T git@github-work 2>&1 | grep -qi 'successfully authenticated' &&
      ok "work SSH works"
  fi
  return 0
}
