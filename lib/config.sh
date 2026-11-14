# shellcheck shell=bash
#
# The setup questions.
#
# Answers are saved to ~/.config/newmac/answers.sh, so single steps
# (e.g. `newmac iterm`) can be re-run later without asking again.

# ─── Choices offered ─────────────────────────────────────────────────────────

ZSH_THEMES=(
  "agnoster (current)"
  "powerlevel10k"
  "robbyrussell"
)

ITERM_SCHEMES=(
  "My saved Material profile (from my current Mac)"
  "Material Ocean"
  "Material Darker"
  "Dracula"
  "Catppuccin Mocha"
  "TokyoNight Storm"
  "Nord"
  "Gruvbox Dark"
  "One Half Dark"
  "Atom One Dark"
  "Solarized Dark Higher Contrast"
)

FONTS=(
  "MesloLGS Nerd Font"
  "Hack Nerd Font"
  "JetBrains Mono Nerd Font"
  "Fira Code Nerd Font"
  "Menlo (built-in)"
)

# One packages/<group>.Brewfile per group. "core" is always installed.
PACKAGE_GROUPS=(core apps fonts ios extras)

package_group_description() {
  case "$1" in
    core) echo "git, gh, jq, mas, python, pipx, uv, swi-prolog, bash, zsh, vim, wget, tree" ;;
    apps) echo "iTerm2, IntelliJ IDEA, VS Code, Sublime Text, BBEdit, Chrome, Firefox, Telegram, Claude desktop" ;;
    fonts) echo "Nerd Fonts: Meslo, Hack, JetBrains Mono, Fira Code (+ plain Hack for IntelliJ)" ;;
    ios) echo "CocoaPods, SwiftLint, xcbeautify, xcodes (Xcode/TestFlight come from the App Store step)" ;;
    extras) echo "things on my previous Mac: Docker Desktop, Heroku CLI" ;;
  esac
}

# ─── Saving and loading answers ──────────────────────────────────────────────

ANSWER_VARS=(
  GIT_NAME GIT_EMAIL GH_USER
  WORK_ENABLED WORK_EMAIL WORK_GH_USER WORK_DIR
  PROJECTS_DIR COMPUTER_NAME
  PACKAGE_SELECTION
  ZSH_THEME_CHOICE ITERM_SCHEME ITERM_FONT ITERM_FONT_SIZE
  KEYBOARD_LAYOUTS
)

# Print $1 single-quoted for the shell: it's   ->   'it'\''s'
shell_quote() {
  local escaped=${1//\'/\'\\\'\'}
  printf "'%s'" "$escaped"
}

save_answers() {
  mkdir -p "$NEWMAC_CONFIG_DIR"
  local name
  {
    echo "# Written by newmac on $(date). Edit freely, or run: newmac configure"
    for name in "${ANSWER_VARS[@]}"; do
      echo "$name=$(shell_quote "${!name}")"
    done
  } >"$NEWMAC_ANSWERS"
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

# ─── Helpers ─────────────────────────────────────────────────────────────────

# github_noreply_email USER [FALLBACK]
#   -> 1234567+USER@users.noreply.github.com
#
# Uses GitHub's public API (no login needed); prints FALLBACK if that fails.
github_noreply_email() {
  local user=$1 fallback=${2:-} id
  id=$(curl -fsSL --max-time 10 "https://api.github.com/users/$user" 2>/dev/null |
    grep -m1 '"id":' | tr -cd '0-9')

  if [ -n "$id" ]; then
    echo "$id+$user@users.noreply.github.com"
  else
    echo "$fallback"
  fi
}

# Keyboard layout names from macos/input-sources.txt (one per line).
keyboard_layout_names() {
  grep -v -e '^#' -e '^[[:space:]]*$' "$NEWMAC_DIR/macos/input-sources.txt" | cut -d'|' -f1
}

package_selected() { list_contains "${PACKAGE_SELECTION:-}" "$1"; }

# ─── The questions ───────────────────────────────────────────────────────────

configure_interactive() {
  load_answers
  header "Setup questions (Enter keeps the [default])"

  ask_git_questions
  ask_machine_questions
  ask_software_questions
  ask_terminal_questions
  ask_keyboard_questions

  save_answers
  ok "Answers saved to $NEWMAC_ANSWERS"
}

ask_git_questions() {
  section "Git & GitHub"

  local current_name current_email
  current_name=$(git config --global user.name 2>/dev/null || id -F 2>/dev/null)
  current_email=$(git config --global user.email 2>/dev/null)

  ask_required GIT_NAME "Your full name (git author)" "${GIT_NAME:-$current_name}"
  ask_required GH_USER "Personal GitHub username" "${GH_USER:-}"

  # GitHub's noreply address is the default: accounts that block "command line
  # pushes that expose my email" refuse commits made with the real address.
  ask_required GIT_EMAIL "Commit email (also the SSH key comment)" \
    "${GIT_EMAIL:-$(github_noreply_email "$GH_USER" "$current_email")}"

  if ask_yn "Also set up a second (work) GitHub account with its own SSH key?" "${WORK_ENABLED:-n}"; then
    WORK_ENABLED=y
    ask_required WORK_GH_USER "Work GitHub username" "${WORK_GH_USER:-}"
    ask_required WORK_EMAIL "Work commit email" \
      "${WORK_EMAIL:-$(github_noreply_email "$WORK_GH_USER")}"
    ask WORK_DIR "Folder whose repos should use the work identity" "${WORK_DIR:-~/MyProjects/work}"
  else
    WORK_ENABLED=n
  fi
}

ask_machine_questions() {
  section "Folders & machine"
  ask PROJECTS_DIR "Default projects directory" "${PROJECTS_DIR:-~/MyProjects}"
  ask COMPUTER_NAME "Computer name (Enter to keep)" \
    "${COMPUTER_NAME:-$(scutil --get ComputerName 2>/dev/null)}"
}

ask_software_questions() {
  section "Software"

  # Show "group — description", store just the group names.
  local labels=() selected_labels='' group label picked
  for group in "${PACKAGE_GROUPS[@]}"; do
    label="$group — $(package_group_description "$group")"
    labels+=("$label")
    if list_contains "${PACKAGE_SELECTION:-core|apps|fonts|ios|extras}" "$group"; then
      selected_labels="${selected_labels:+$selected_labels|}$label"
    fi
  done

  choose_many picked "Package groups to install" "$selected_labels" "${labels[@]}"
  PACKAGE_SELECTION=$(echo "$picked" | tr '|' '\n' | sed 's/ —.*//' | paste -sd'|' -)
}

ask_terminal_questions() {
  section "Terminal look"
  choose ZSH_THEME_CHOICE "oh-my-zsh prompt theme" \
    "${ZSH_THEME_CHOICE:-${ZSH_THEMES[0]}}" "${ZSH_THEMES[@]}"
  choose ITERM_SCHEME "iTerm2 color scheme" \
    "${ITERM_SCHEME:-${ITERM_SCHEMES[0]}}" "${ITERM_SCHEMES[@]}"
  choose ITERM_FONT "Terminal font (Nerd Fonts show the prompt's arrows and icons)" \
    "${ITERM_FONT:-${FONTS[0]}}" "${FONTS[@]}"
  ask ITERM_FONT_SIZE "Terminal font size" "${ITERM_FONT_SIZE:-18}"
}

ask_keyboard_questions() {
  section "Keyboard"
  local layouts=() name
  while IFS= read -r name; do
    layouts+=("$name")
  done < <(keyboard_layout_names)

  choose_many KEYBOARD_LAYOUTS "Keyboard layouts (input sources)" \
    "${KEYBOARD_LAYOUTS:-ABC|Russian|Armenian-HM QWERTY}" "${layouts[@]}"
}
