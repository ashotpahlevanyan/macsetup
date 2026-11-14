# shellcheck shell=bash
# The setup questions. Answers are saved to ~/.config/newmac/answers.sh so
# single steps (`newmac iterm`) can be re-run later without asking again.

ITERM_SCHEMES="My saved Material profile (from my current Mac)|Material Ocean|Material Darker|Dracula|Catppuccin Mocha|TokyoNight Storm|Nord|Gruvbox Dark|One Half Dark|Atom One Dark|Solarized Dark Higher Contrast"
FONTS="MesloLGS Nerd Font|Hack Nerd Font|JetBrains Mono Nerd Font|Fira Code Nerd Font|Menlo (built-in)"
ZSH_THEMES="agnoster (current)|powerlevel10k|robbyrussell"
PACKAGE_GROUPS="core|apps|fonts|ios|extras"

package_group_description() {
  case "$1" in
    core)   echo "git, gh, jq, mas, python, pipx, uv, swi-prolog, bash, zsh, vim, wget, tree" ;;
    apps)   echo "iTerm2, IntelliJ IDEA, VS Code, Sublime Text, BBEdit, Chrome, Firefox, Telegram, Claude desktop" ;;
    fonts)  echo "Nerd Fonts: Meslo, Hack, JetBrains Mono, Fira Code (+ plain Hack for IntelliJ)" ;;
    ios)    echo "CocoaPods, SwiftLint, xcbeautify, xcodes (Xcode/TestFlight come from the App Store step)" ;;
    extras) echo "things on my current Mac: Docker Desktop, Heroku CLI" ;;
  esac
}

ANSWER_VARS="GIT_NAME GIT_EMAIL GH_USER WORK_ENABLED WORK_EMAIL WORK_GH_USER WORK_DIR PROJECTS_DIR PACKAGE_SELECTION ZSH_THEME_CHOICE ITERM_SCHEME ITERM_FONT ITERM_FONT_SIZE KEYBOARD_LAYOUTS COMPUTER_NAME"

save_answers() {
  mkdir -p "$NEWMAC_CONFIG_DIR"
  local v val
  {
    echo "# Written by newmac on $(date). Edit freely, or run: newmac configure"
    for v in $ANSWER_VARS; do
      eval "val=\${$v:-}"
      # single-quoted, with embedded ' escaped — safe for any UTF-8 text
      printf "%s='%s'\n" "$v" "$(printf '%s' "$val" | sed "s/'/'\\\\''/g")"
    done
  } > "$NEWMAC_ANSWERS"
  chmod 600 "$NEWMAC_ANSWERS"
}

load_answers() {
  # shellcheck disable=SC1090
  [ -r "$NEWMAC_ANSWERS" ] && . "$NEWMAC_ANSWERS"
}

load_answers_or_configure() {
  if [ -r "$NEWMAC_ANSWERS" ]; then
    load_answers
  else
    warn "No saved answers yet — asking the setup questions first."
    configure_interactive
  fi
}

# index (1-based) of $1 within a '|' list $2, or $3 if absent
index_in() {
  local needle=$1 list=$2 def=$3 i=1 item
  local IFS='|'
  for item in $list; do
    [ "$item" = "$needle" ] && { echo $i; return; }
    i=$((i + 1))
  done
  echo "$def"
}

# github_noreply_email USER [FALLBACK] -> ID+USER@users.noreply.github.com
# Uses GitHub's public API (no login needed). Prints FALLBACK if the lookup fails.
github_noreply_email() {
  local user=$1 fallback=${2:-} id
  id=$(curl -fsSL --max-time 10 "https://api.github.com/users/$user" 2>/dev/null \
       | grep -m1 '"id":' | tr -cd '0-9')
  if [ -n "$id" ]; then
    echo "${id}+${user}@users.noreply.github.com"
  else
    echo "$fallback"
  fi
}

configure_interactive() {
  load_answers
  header "Setup questions (Enter keeps the [default])"

  local def_name def_email
  def_name=${GIT_NAME:-$(git config --global user.name 2>/dev/null || id -F 2>/dev/null)}
  def_email=$(git config --global user.email 2>/dev/null)

  printf '\n%sGit & GitHub%s\n' "$C_BOLD" "$C_RESET" >/dev/tty
  ask_required GIT_NAME  "Your full name (git author)" "$def_name"
  ask_required GH_USER   "Personal GitHub username" "${GH_USER:-}"
  # Default to GitHub's noreply address: accounts with "Block command line
  # pushes that expose my email" reject commits made with the real address.
  ask_required GIT_EMAIL "Commit email (also the SSH key comment)" "${GIT_EMAIL:-$(github_noreply_email "$GH_USER" "$def_email")}"

  if ask_yn "Also set up a second (work) GitHub account with its own SSH key?" "${WORK_ENABLED:-n}"; then
    WORK_ENABLED=y
    ask_required WORK_GH_USER "Work GitHub username" "${WORK_GH_USER:-}"
    ask_required WORK_EMAIL   "Work commit email" "${WORK_EMAIL:-$(github_noreply_email "$WORK_GH_USER")}"
    ask WORK_DIR "Folder whose repos should use the work identity" "${WORK_DIR:-~/MyProjects/work}"
  else
    WORK_ENABLED=n
  fi

  printf '\n%sFolders & machine%s\n' "$C_BOLD" "$C_RESET" >/dev/tty
  ask PROJECTS_DIR  "Default projects directory" "${PROJECTS_DIR:-~/MyProjects}"
  ask COMPUTER_NAME "Computer name (Enter to keep)" "${COMPUTER_NAME:-$(scutil --get ComputerName 2>/dev/null)}"

  printf '\n%sSoftware%s\n' "$C_BOLD" "$C_RESET" >/dev/tty
  local g i=1 opts='' defs=''
  local IFS_SAVE=$IFS
  IFS='|'
  for g in $PACKAGE_GROUPS; do
    opts="${opts:+$opts|}$g — $(package_group_description "$g")"
    case "|${PACKAGE_SELECTION:-core|apps|fonts|ios|extras}|" in *"|$g|"*) defs="$defs $i" ;; esac
    i=$((i + 1))
  done
  # shellcheck disable=SC2086
  set -- $opts
  IFS=$IFS_SAVE
  local picked
  choose_many picked "Package groups to install" "${defs# }" "$@"
  PACKAGE_SELECTION=$(echo "$picked" | tr '|' '\n' | sed 's/ —.*//' | paste -sd'|' -)

  printf '\n%sTerminal look%s\n' "$C_BOLD" "$C_RESET" >/dev/tty
  IFS='|'; set -- $ZSH_THEMES; IFS=$IFS_SAVE
  choose ZSH_THEME_CHOICE "oh-my-zsh prompt theme" "$(index_in "${ZSH_THEME_CHOICE:-}" "$ZSH_THEMES" 1)" "$@"

  IFS='|'; set -- $ITERM_SCHEMES; IFS=$IFS_SAVE
  choose ITERM_SCHEME "iTerm2 color scheme" "$(index_in "${ITERM_SCHEME:-}" "$ITERM_SCHEMES" 1)" "$@"

  IFS='|'; set -- $FONTS; IFS=$IFS_SAVE
  choose ITERM_FONT "Terminal font (Nerd Fonts show the prompt's arrows and icons correctly)" "$(index_in "${ITERM_FONT:-}" "$FONTS" 1)" "$@"
  ask ITERM_FONT_SIZE "Terminal font size" "${ITERM_FONT_SIZE:-18}"

  printf '\n%sKeyboard%s\n' "$C_BOLD" "$C_RESET" >/dev/tty
  local layouts names='' l
  layouts=$(grep -v '^#' "$NEWMAC_DIR/macos/input-sources.txt" | grep -v '^[[:space:]]*$')
  defs=''; i=1
  while IFS='|' read -r l _; do
    names="${names:+$names|}$l"
    case "|${KEYBOARD_LAYOUTS:-ABC|Russian|Armenian-HM QWERTY}|" in *"|$l|"*) defs="$defs $i" ;; esac
    i=$((i + 1))
  done <<EOF
$layouts
EOF
  IFS='|'; set -- $names; IFS=$IFS_SAVE
  choose_many KEYBOARD_LAYOUTS "Keyboard layouts (input sources)" "${defs# }" "$@"

  save_answers
  ok "Answers saved to $NEWMAC_ANSWERS"
}

expand_tilde() { case "$1" in "~") echo "$HOME" ;; "~/"*) echo "$HOME/${1#\~/}" ;; *) echo "$1" ;; esac; }

package_selected() { case "|${PACKAGE_SELECTION:-}|" in *"|$1|"*) return 0 ;; esac; return 1; }

# Copy the current Mac's settings back into the repo, so the next wipe
# gets whatever you changed since. Dotfiles need no capture: they are
# symlinks into this repo already.
capture_current_settings() {
  header "Capturing this Mac's settings into $NEWMAC_DIR"

  # Keyboard layouts
  local out="$NEWMAC_DIR/macos/input-sources.txt"
  defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null | /usr/bin/python3 -c '
import sys,re
txt=sys.stdin.read()
for block in re.findall(r"\{(.*?)\}", txt, re.S):
    name=re.search(r"\"KeyboardLayout Name\" = \"?([^\";]+)\"?;", block)
    lid=re.search(r"\"KeyboardLayout ID\" = \"?(-?\d+)\"?;", block)
    if name and lid: print(f"{name.group(1)}|{lid.group(1)}")
' > "$out.current"
  if [ -s "$out.current" ]; then
    # Merge: keep existing entries, add any new ones.
    cat "$out" "$out.current" | awk '!seen[$0]++' > "$out.new" && mv "$out.new" "$out"
    ok "keyboard layouts -> macos/input-sources.txt"
  fi
  rm -f "$out.current"

  # IntelliJ: newest config dir
  local j
  j=$(ls -d "$HOME/Library/Application Support/JetBrains/IntelliJIdea"* "$HOME/Library/Application Support/JetBrains/IdeaIC"* 2>/dev/null | sort | tail -1)
  if [ -n "$j" ]; then
    cp "$j"/colors/*.icls "$NEWMAC_DIR/intellij/config/colors/" 2>/dev/null
    cp "$j"/codestyles/*.xml "$NEWMAC_DIR/intellij/config/codestyles/" 2>/dev/null
    local f
    for f in "$NEWMAC_DIR"/intellij/config/options/*.xml; do
      [ -f "$j/options/$(basename "$f")" ] && cp "$j/options/$(basename "$f")" "$f"
    done
    ok "IntelliJ settings from $(basename "$j") -> intellij/config"
    warn "New plugins are not auto-detected: add their IDs to intellij/plugins.txt"
  fi

  # iTerm2: the current default profile
  if defaults read com.googlecode.iterm2 >/dev/null 2>&1; then
    defaults export com.googlecode.iterm2 - | /usr/bin/python3 "$NEWMAC_DIR/iterm/iterm_profile.py" export "$NEWMAC_DIR/iterm/profiles/material.json" \
      && ok "iTerm2 default profile -> iterm/profiles/material.json"
  fi
  info "Review with: git -C \"$NEWMAC_DIR\" diff"
}
