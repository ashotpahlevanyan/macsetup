#!/bin/bash
# First thing to run on a freshly wiped Mac:
#
#   curl -fsSL https://raw.githubusercontent.com/ashotpahlevanyan/macsetup/main/bootstrap.sh | bash
#
# Installs the Xcode Command Line Tools (for git), clones this repo into
# ~/MyProjects/macsetup, puts `newmac` on your PATH and starts `newmac init`.

set -eo pipefail

REPO_URL=${NEWMAC_REPO:-https://github.com/ashotpahlevanyan/macsetup.git}
DEST=${NEWMAC_DEST:-$HOME/MyProjects/macsetup}

echo "==> newmac bootstrap"

if ! xcode-select -p >/dev/null 2>&1; then
  echo "  • Installing Xcode Command Line Tools (needed for git)…"
  echo "    You may be asked for your Mac password."
  sudo -v </dev/tty
  touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  label=$(softwareupdate -l 2>/dev/null | grep -E '\*.*Command Line Tools' | sed 's/^.*\* Label: //; s/^ *\* *//' | sort -V | tail -1)
  if [ -n "$label" ]; then
    sudo softwareupdate -i "$label" --verbose </dev/null
  else
    xcode-select --install || true
    echo "    Finish the installer dialog, then press Enter."
    read -r _ </dev/tty
  fi
  rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
fi

if [ -d "$DEST/.git" ]; then
  echo "  • Updating $DEST"
  git -C "$DEST" pull --ff-only || true
else
  echo "  • Cloning $REPO_URL -> $DEST"
  mkdir -p "$(dirname "$DEST")"
  git clone "$REPO_URL" "$DEST"
fi

chmod +x "$DEST/newmac"
mkdir -p "$HOME/.local/bin"
ln -sf "$DEST/newmac" "$HOME/.local/bin/newmac"
echo "  • 'newmac' linked into ~/.local/bin"

exec "$DEST/newmac" init </dev/tty
