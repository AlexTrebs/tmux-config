#!/usr/bin/env bash
# tmux-folder-explorer — unified version with reusable session logic

set -euo pipefail

# ────────────────────────────────
# CONFIG
# ────────────────────────────────
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/tmux-folder-explorer.conf"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

BASE_DIR="${BASE_DIR:-$HOME}"
SHOW_HIDDEN="${SHOW_HIDDEN:-false}"
TMUX_BIN="${TMUX_BIN:-tmux}"

# ────────────────────────────────
# HELPERS
# ────────────────────────────────
fd_flags() {
  if [[ "$SHOW_HIDDEN" == "true" ]]; then
    echo "--hidden --no-ignore"
  else
    echo "--no-hidden --ignore --exclude '.*'"
  fi
}

find_flags() {
  if [[ "$SHOW_HIDDEN" == "true" ]]; then
    echo ""
  else
    echo "-not -path '*/.*'"
  fi
}

list_entries() {
  local current_dir="$1"
  current_dir="$(realpath -m "$current_dir")"

  local entries

  if command -v fd >/dev/null 2>&1; then
    # fd respects SHOW_HIDDEN via flags
    entries=$(fd -a '' "$current_dir" \
      --max-depth 1 \
      $(fd_flags) \
      --color never)
  else
    # find version respecting SHOW_HIDDEN
    entries=$(find "$current_dir" -mindepth 1 -maxdepth 1 $(find_flags) -print 2>/dev/null)
  fi

  entries=$(echo "$entries" | grep -v "^$current_dir$" || true)

  if [[ "$current_dir" == "$BASE_DIR"* ]]; then
    while IFS= read -r e; do
      [[ -z "$e" ]] && continue
      echo "${e#$BASE_DIR/}"
    done <<<"$entries"
  else
    echo "$entries"
  fi
}

preview_entry() {
  local path="$1"
  [[ "$path" != /* ]] && path="$BASE_DIR/$path"
  if [[ -d "$path" ]]; then
    local entries
    if command -v fd >/dev/null 2>&1; then
      entries=$(fd -a '' "$path" --max-depth 1 --hidden --no-ignore --color never)
    else
      entries=$(find "$path" -mindepth 1 -maxdepth 1 -print 2>/dev/null)
    fi
    [[ -z "$entries" ]] && { echo "(empty folder)"; return; }
    while IFS= read -r entry; do
      [[ -z "$entry" ]] && continue
      if [[ -d "$entry" ]]; then
        printf "%s/\n" "$(basename "$entry")"
      else
        printf "%s\n" "$(basename "$entry")"
      fi
    done <<<"$entries" | sort
  else
    bat --color=always --style=plain --line-range=:200 "$path" 2>/dev/null || head -200 "$path"
  fi
}

# ────────────────────────────────
# SHARED TMUX LOGIC
# ────────────────────────────────
open_in_tmux() {
  local target="$1"
  target="$BASE_DIR/$target"
  target="$(realpath -m "$target")"

  local target_dir session
  if [[ -d "$target" ]]; then
    target_dir="$target"
  else
    target_dir="$(dirname "$target")"
  fi

  session="$(basename "$target_dir")"
  session="${session//./_}"
  session="${session// /_}"

  # inside tmux: avoid nesting
  if [[ -n "${TMUX:-}" ]]; then
    if $TMUX_BIN has-session -t "=$session" 2>/dev/null; then
      $TMUX_BIN switch-client -t "=$session"
    else
      $TMUX_BIN new-session -ds "$session" -c "$target_dir"
      $TMUX_BIN switch-client -t "=$session"
    fi
  else
    $TMUX_BIN new-session -A -s "$session" -c "$target_dir"
  fi

  # Always open in nvim, adjust command based on type
  if [[ -f "$target" ]]; then
    nvim_cmd="nvim '$target'"
  else
    nvim_cmd="nvim ."
  fi

  $TMUX_BIN send-keys -t "=$session" "$nvim_cmd" C-m
}

# ────────────────────────────────
# ACTIONS
# ────────────────────────────────
LEFT() {
  local parent
  parent="$(dirname "$current_dir")"
  parent="$(realpath -m "$parent")"

  current_dir="$parent"
}

RIGHT() {
  if [[ -f "$selection" ]]; then
    current_dir="$current_dir"
  else
    local path="$selection"
    [[ "$path" != /* ]] && path="$BASE_DIR/$path"
    [[ -d "$path" ]] && current_dir="$path"
  fi
}

ENTER() {
  open_in_tmux "$selection"
}

FILES() {
  local file
  file=$(fd -t f --hidden --no-ignore --color never . "$current_dir" |
         fzf --ansi --reverse --header "📄 Fuzzy find file in: $current_dir" \
             --preview 'bat --color=always --style=plain --line-range=:200 {} 2>/dev/null || head -200 {}')
  [[ -z "$file" ]] && return
  open_in_tmux "$file"
}

GREP() {
  local term file line
  read -rp "🔍 Search term: " term
  [[ -z "$term" ]] && return

  IFS=: read -r file line _ < <(
    rg --hidden --no-ignore --color=always -n "$term" "$current_dir" 2>/dev/null |
    fzf --ansi --delimiter : \
        --header "Matches for '$term' in $current_dir" \
        --preview 'bat --style=plain --color=always --highlight-line {2} {1} 2>/dev/null || head -200 {1}'
  )
  [[ -z "$file" ]] && return

  open_in_tmux "$file"
  [[ -n "$line" ]] && $TMUX_BIN send-keys ":+$line" C-m
}

# ────────────────────────────────
# MAIN LOOP
# ────────────────────────────────
explore() {
  # Track first-time usage
  local state_file="${XDG_CACHE_HOME:-$HOME/.cache}/tmux-explorer-state"

  if [[ ! -f "$state_file" ]]; then
    # First time: start from home
    current_dir="$HOME"
    mkdir -p "$(dirname "$state_file")"
    touch "$state_file"
  else
    # Otherwise: start from parent directory of current location
    current_dir="$(dirname "$PWD")"
  fi

  export -f preview_entry
  export current_dir BASE_DIR

  while true; do
    mapfile -t out < <(
      list_entries "$current_dir" |
      fzf --ansi --reverse \
          --expect=right,left,enter,ctrl-f,ctrl-g \
          --header "📁 $current_dir — [→] enter | [←] up | [Enter] open | [Ctrl+F] fuzzy | [Ctrl+G] grep" \
          --preview "bash -c 'preview_entry {}'" \
          --preview-window=right:50%:wrap
    ) || break

    key="${out[0]}"
    selection="${out[1]}"

    case "$key" in
      right) RIGHT ;;
      left)  LEFT ;;
      enter) ENTER ;;
      ctrl-f) FILES ;;
      ctrl-g) GREP ;;
      *) [[ -n "$selection" && -d "$selection" ]] && current_dir="$selection" ;;
    esac
  done
}

# if called as: tmux-folder-explorer --explore
if [[ "${1:-}" == "--explore" ]]; then
  explore
  exit 0
fi

current_dir="$(tmux display-message -p -F "#{pane_current_path}")"
if tmux list-windows -a | grep -E -q '^[^:]+:[0-9]+:[[:space:]]+explorer[*-]?'; then
  # Extract the session name that has it
  session_name="$(tmux list-windows -a | grep -E '^[^:]+:[0-9]+:[[:space:]]+explorer[*-]?' | head -n1 | cut -d: -f1)"

  # Change its directory and switch to it
  tmux switch-client -t "$session_name"
  tmux select-window -t "${session_name}:explorer"
else
  # Create new explorer window in current session, current dir
  tmux new-window -n explorer -c "$current_dir" "$0 --explore"
fi
