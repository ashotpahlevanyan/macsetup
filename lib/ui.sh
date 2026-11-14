# shellcheck shell=bash
#
# Output and prompt helpers.
#
# Written for the bash 3.2 that ships with macOS: no associative arrays, no
# ${var,,}, no mapfile. Prompts read from /dev/tty, so they still work when the
# script itself arrives through a pipe (curl ... | bash).

# ─── Colors ──────────────────────────────────────────────────────────────────

if [ -t 1 ]; then
  BOLD=$'\033[1m' DIM=$'\033[2m' RESET=$'\033[0m'
  RED=$'\033[31m' GREEN=$'\033[32m' YELLOW=$'\033[33m'
  BLUE=$'\033[34m' CYAN=$'\033[36m'
else
  BOLD='' DIM='' RESET='' RED='' GREEN='' YELLOW='' BLUE='' CYAN=''
fi

# ─── Messages ────────────────────────────────────────────────────────────────

header() { printf '\n%s==> %s%s\n' "$BOLD$BLUE" "$*" "$RESET"; }
info() { printf '%s  • %s%s\n' "$CYAN" "$*" "$RESET"; }
ok() { printf '%s  ✓ %s%s\n' "$GREEN" "$*" "$RESET"; }
warn() { printf '%s  ! %s%s\n' "$YELLOW" "$*" "$RESET" >&2; }
err() { printf '%s  ✗ %s%s\n' "$RED" "$*" "$RESET" >&2; }
die() {
  err "$*"
  exit 1
}

# A bold sub-heading inside the question flow.
section() { printf '\n%s%s%s\n' "$BOLD" "$*" "$RESET" >/dev/tty; }

have() { command -v "$1" >/dev/null 2>&1; }

# ─── Prompts ─────────────────────────────────────────────────────────────────
#
# Every prompt stores its answer in the variable named by its first argument:
#
#   ask          NAME "Question" "default"
#   ask_required NAME "Question" "default"         (re-asks until non-empty)
#   ask_yn            "Question" y|n               (exit status: 0 = yes)
#   choose       NAME "Question" "default" option…  (one option)
#   choose_many  NAME "Question" "a|b"     option…  (several, joined with |)
#   pause             "Message"

# Read one line from the terminal into the variable named $1.
read_line() { IFS= read -r "$1" </dev/tty || true; }

ask() {
  local var=$1 question=$2 default=${3:-} answer
  if [ -n "$default" ]; then
    printf '%s? %s%s [%s]: ' "$BOLD" "$question" "$RESET" "$default" >/dev/tty
  else
    printf '%s? %s%s: ' "$BOLD" "$question" "$RESET" >/dev/tty
  fi
  read_line answer
  printf -v "$var" '%s' "${answer:-$default}"
}

ask_required() {
  local var=$1 question=$2 default=${3:-}
  while :; do
    ask "$var" "$question" "$default"
    [ -n "${!var}" ] && return 0
    warn "A value is required."
  done
}

ask_yn() {
  local question=$1 default=${2:-y} hint answer
  [ "$default" = y ] && hint='Y/n' || hint='y/N'
  while :; do
    printf '%s? %s%s [%s]: ' "$BOLD" "$question" "$RESET" "$hint" >/dev/tty
    read_line answer
    case "${answer:-$default}" in
      [yY] | yes | Yes | YES) return 0 ;;
      [nN] | no | No | NO) return 1 ;;
    esac
  done
}

# Is $1 a whole number between $2 and $3?
in_range() {
  case "$1" in '' | *[!0-9]*) return 1 ;; esac
  [ "$1" -ge "$2" ] && [ "$1" -le "$3" ]
}

choose() {
  local var=$1 question=$2 default=$3
  shift 3
  local options=("$@") default_index=1 i answer

  printf '%s? %s%s\n' "$BOLD" "$question" "$RESET" >/dev/tty
  for i in "${!options[@]}"; do
    if [ "${options[i]}" = "$default" ]; then
      default_index=$((i + 1))
      printf '   %s%2d) %s  (default)%s\n' "$GREEN" $((i + 1)) "${options[i]}" "$RESET" >/dev/tty
    else
      printf '   %2d) %s\n' $((i + 1)) "${options[i]}" >/dev/tty
    fi
  done

  while :; do
    printf '   choice [%s]: ' "$default_index" >/dev/tty
    read_line answer
    answer=${answer:-$default_index}
    if in_range "$answer" 1 "${#options[@]}"; then
      printf -v "$var" '%s' "${options[answer - 1]}"
      return 0
    fi
  done
}

choose_many() {
  local var=$1 question=$2 selected=$3
  shift 3
  local options=("$@") defaults='' i n answer result invalid

  printf '%s? %s%s %s(numbers separated by spaces)%s\n' \
    "$BOLD" "$question" "$RESET" "$DIM" "$RESET" >/dev/tty
  for i in "${!options[@]}"; do
    if list_contains "$selected" "${options[i]}"; then
      defaults="$defaults $((i + 1))"
      printf '   %s%2d) [x] %s%s\n' "$GREEN" $((i + 1)) "${options[i]}" "$RESET" >/dev/tty
    else
      printf '   %2d) [ ] %s\n' $((i + 1)) "${options[i]}" >/dev/tty
    fi
  done
  defaults=${defaults# }

  while :; do
    printf '   choices [%s]: ' "$defaults" >/dev/tty
    read_line answer
    result='' invalid=''
    for n in ${answer:-$defaults}; do
      if in_range "$n" 1 "${#options[@]}"; then
        result="${result:+$result|}${options[n - 1]}"
      else
        invalid=1
      fi
    done
    if [ -z "$invalid" ] && [ -n "$result" ]; then
      printf -v "$var" '%s' "$result"
      return 0
    fi
  done
}

pause() {
  printf '%s  ↵ %s%s' "$YELLOW" "${1:-Press Enter to continue}" "$RESET" >/dev/tty
  read_line _
}

# ─── Small utilities ─────────────────────────────────────────────────────────

# Does the '|'-separated list $1 contain the item $2?
list_contains() {
  case "|$1|" in *"|$2|"*) return 0 ;; esac
  return 1
}

# "~/MyProjects" -> "/Users/me/MyProjects"
expand_tilde() {
  # shellcheck disable=SC2088  # the quoted ~ is the literal text we look for
  case "$1" in
    "~") echo "$HOME" ;;
    "~/"*) echo "$HOME/${1#\~/}" ;;
    *) echo "$1" ;;
  esac
}

# Move an existing file out of the way (into this run's backup folder).
backup() {
  local target=$1
  [ -e "$target" ] || [ -L "$target" ] || return 0
  mkdir -p "$NEWMAC_BACKUP_DIR"
  mv "$target" "$NEWMAC_BACKUP_DIR/" &&
    info "backed up $(basename "$target") -> $NEWMAC_BACKUP_DIR"
}

# Replace the block between
#     # >>> newmac NAME >>>
#     # <<< newmac NAME <<<
# in FILE with the text on stdin, leaving the rest of the file alone.
# The block goes at the top of the file.
write_managed_block() {
  local file=$1 name=$2
  local begin="# >>> newmac $name >>>"
  local end="# <<< newmac $name <<<"
  local block rest
  block=$(cat)
  touch "$file"

  rest=$(awk -v begin="$begin" -v end="$end" '
    $0 == begin { skipping = 1; next }
    $0 == end   { skipping = 0; just_ended = 1; next }
    just_ended && $0 == "" { just_ended = 0; next }   # blank line we added
    { just_ended = 0 }
    !skipping   { print }
  ' "$file")

  printf '%s\n%s\n%s\n\n%s\n' "$begin" "$block" "$end" "$rest" >"$file"
}
