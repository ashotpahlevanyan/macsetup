# shellcheck shell=bash
# Output + prompt helpers. Written for macOS's stock bash 3.2 (no associative
# arrays, no ${var,,}). Prompts read from /dev/tty so they still work when the
# script itself arrives through a pipe (curl ... | bash).

if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'
else
  C_RESET=''; C_BOLD=''; C_DIM=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_CYAN=''
fi

header() { printf '\n%s==> %s%s\n' "$C_BOLD$C_BLUE" "$*" "$C_RESET"; }
info()   { printf '%s  • %s%s\n' "$C_CYAN" "$*" "$C_RESET"; }
ok()     { printf '%s  ✓ %s%s\n' "$C_GREEN" "$*" "$C_RESET"; }
warn()   { printf '%s  ! %s%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2; }
err()    { printf '%s  ✗ %s%s\n' "$C_RED" "$*" "$C_RESET" >&2; }
die()    { err "$*"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# ask VAR "Question" "default"
ask() {
  local __var=$1 __q=$2 __def=${3:-} __ans
  if [ -n "$__def" ]; then
    printf '%s? %s%s [%s]: ' "$C_BOLD" "$__q" "$C_RESET" "$__def" >/dev/tty
  else
    printf '%s? %s%s: ' "$C_BOLD" "$__q" "$C_RESET" >/dev/tty
  fi
  IFS= read -r __ans </dev/tty || true
  [ -z "$__ans" ] && __ans=$__def
  eval "$__var=\$__ans"
}

# ask_required VAR "Question" "default" — re-asks until non-empty
ask_required() {
  local __v
  while :; do
    ask __v "$2" "${3:-}"
    [ -n "$__v" ] && break
    warn "A value is required."
  done
  eval "$1=\$__v"
}

# ask_yn "Question" y|n  -> returns 0 for yes
ask_yn() {
  local q=$1 def=${2:-y} ans hint
  [ "$def" = y ] && hint='Y/n' || hint='y/N'
  while :; do
    printf '%s? %s%s [%s]: ' "$C_BOLD" "$q" "$C_RESET" "$hint" >/dev/tty
    IFS= read -r ans </dev/tty || true
    [ -z "$ans" ] && ans=$def
    case "$ans" in
      y|Y|yes|YES|Yes) return 0 ;;
      n|N|no|NO|No) return 1 ;;
    esac
  done
}

# choose VAR "Question" default_index option1 option2 ...
# Stores the chosen option text in VAR.
choose() {
  local __var=$1 __q=$2 __def=$3; shift 3
  local __i=1 __o __ans
  printf '%s? %s%s\n' "$C_BOLD" "$__q" "$C_RESET" >/dev/tty
  for __o in "$@"; do
    if [ "$__i" = "$__def" ]; then
      printf '   %s%2d) %s  (default)%s\n' "$C_GREEN" "$__i" "$__o" "$C_RESET" >/dev/tty
    else
      printf '   %2d) %s\n' "$__i" "$__o" >/dev/tty
    fi
    __i=$((__i + 1))
  done
  while :; do
    printf '   choice [%s]: ' "$__def" >/dev/tty
    IFS= read -r __ans </dev/tty || true
    [ -z "$__ans" ] && __ans=$__def
    case "$__ans" in *[!0-9]*|'') continue ;; esac
    if [ "$__ans" -ge 1 ] && [ "$__ans" -le $# ]; then
      eval "$__var=\${$__ans}"
      return 0
    fi
  done
}

# choose_many VAR "Question" "default indexes e.g. 1 3" option1 option2 ...
# Stores chosen options joined by '|' in VAR.
choose_many() {
  local __var=$1 __q=$2 __def=$3; shift 3
  local __i=1 __o __ans __n __out='' __bad
  printf '%s? %s%s %s(space-separated numbers)%s\n' "$C_BOLD" "$__q" "$C_RESET" "$C_DIM" "$C_RESET" >/dev/tty
  for __o in "$@"; do
    case " $__def " in
      *" $__i "*) printf '   %s%2d) [x] %s%s\n' "$C_GREEN" "$__i" "$__o" "$C_RESET" >/dev/tty ;;
      *)          printf '   %2d) [ ] %s\n' "$__i" "$__o" >/dev/tty ;;
    esac
    __i=$((__i + 1))
  done
  while :; do
    printf '   choices [%s]: ' "$__def" >/dev/tty
    IFS= read -r __ans </dev/tty || true
    [ -z "$__ans" ] && __ans=$__def
    __out=''; __bad=''
    for __n in $__ans; do
      case "$__n" in *[!0-9]*) __bad=1; break ;; esac
      if [ "$__n" -ge 1 ] && [ "$__n" -le $# ]; then
        eval "__o=\${$__n}"
        __out="${__out:+$__out|}$__o"
      else
        __bad=1; break
      fi
    done
    [ -z "$__bad" ] && [ -n "$__out" ] && break
  done
  eval "$__var=\$__out"
}

pause() {
  printf '%s  ↵ %s%s' "$C_YELLOW" "${1:-Press Enter to continue}" "$C_RESET" >/dev/tty
  IFS= read -r _ </dev/tty || true
}

# Back up a file/dir (if it is real, not our symlink) before we replace it.
backup() {
  local target=$1
  [ -e "$target" ] || [ -L "$target" ] || return 0
  mkdir -p "$NEWMAC_BACKUP_DIR"
  mv "$target" "$NEWMAC_BACKUP_DIR/" && info "backed up $(basename "$target") -> $NEWMAC_BACKUP_DIR"
}

# Replace a block delimited by '# >>> newmac NAME >>>' / '# <<< newmac NAME <<<'
# inside FILE with the content on stdin, keeping everything else intact.
write_managed_block() {
  local file=$1 name=$2 begin end tmp
  begin="# >>> newmac $name >>>"; end="# <<< newmac $name <<<"
  tmp=$(mktemp)
  touch "$file"
  awk -v b="$begin" -v e="$end" '
    $0==b {skip=1; next}
    $0==e {skip=0; after=1; next}
    after && $0=="" {after=0; next}
    {after=0}
    !skip {print}
  ' "$file" > "$tmp.rest"
  { echo "$begin"; cat; echo "$end"; echo; cat "$tmp.rest"; } > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp" "$tmp.rest"
}
