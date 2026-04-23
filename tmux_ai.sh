#!/usr/bin/env bash
set -euo pipefail

# Lightweight, robust AI launcher for tmux
# - Simple menu with 2 built-ins: claude and opencode
# - Optional ai.conf entries added as additional rows
# - RECENT support (basic)

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_DIR="$XDG_CONFIG_HOME/tmux"
DATA_DIR="$XDG_DATA_HOME/tmux-ai"
RECENT_FILE="$DATA_DIR/recent"

ENABLE_RECENT=true
mkdir -p "$DATA_DIR"

# Build simple lists
declare -a cmds
declare -a descs
declare -a icons

# Defaults
cmds+=("claude")
descs+=("Claude Code")
icons+=("🦊")

cmds+=("opencode")
descs+=("OpenCode")
icons+=("⚡")

# Load ai.conf extras
AI_CONF="$CONFIG_DIR/ai.conf"
if [[ -f "$AI_CONF" ]]; then
  while IFS=':' read -r name desc icon color; do
    [[ -z "$name" || "$name" == "#"* ]] && continue
    cmds+=("$name")
    descs+=("$desc")
    icons+=("${icon:-} ")
  done < "$AI_CONF"
fi

# RECENT row
if [[ -f "$RECENT_FILE" && -s "$RECENT_FILE" ]] && $ENABLE_RECENT; then
  cmds+=("RECENT")
  descs+=("Recent Sessions")
  icons+=("📂")
fi

len=${#cmds[@]}
selected=0

show_recent_menu() {
  local -a rcmds=()
  [[ -f "$RECENT_FILE" && -s "$RECENT_FILE" ]] || { echo "No recent sessions"; sleep 1; return 1; }
  while IFS='|' read -r _ cmd; do
    [[ -n "$cmd" ]] && rcmds+=("$cmd")
  done < <(tac "$RECENT_FILE" | awk -F'|' '!seen[$2]++' | head -10)
  [[ ${#rcmds[@]} -eq 0 ]] && { echo "No recent sessions"; sleep 1; return 1; }
  local rsel=0 rlen=${#rcmds[@]} rkey resc
  while true; do
    clear; echo "Recent Sessions"; echo "---------------"
    for i in "${!rcmds[@]}"; do
      [[ $i -eq $rsel ]] && printf "> %d %s\n" "$((i+1))" "${rcmds[$i]}" || printf "  %d %s\n" "$((i+1))" "${rcmds[$i]}"
    done
    echo; echo "Enter=select  q=back  arrows=move"
    read -r -s -n1 rkey
    case "$rkey" in
      q|Q) return 1 ;;
      [0-9]) local ri=$((rkey-1)); [[ $ri -ge 0 && $ri -lt $rlen ]] && rsel=$ri ;;
      $'\x1b') read -r -s -n2 -t 0.1 resc
        [[ "$resc" == '[A' && $rsel -gt 0 ]] && ((rsel--))
        [[ "$resc" == '[B' && $rsel -lt $((rlen-1)) ]] && ((rsel++)) ;;
      "") printf '%s' "${rcmds[$rsel]}"; return 0 ;;
    esac
  done
}

render() {
  clear
  echo "AI Launcher v2.0"
  echo "-----------------"
  for i in "${!cmds[@]}"; do
    num=$((i + 1))
    if [[ "$i" -eq "$selected" ]]; then
      printf "> %s %s %s: %s\n" "$num" "${icons[$i]}" "${cmds[$i]}" "${descs[$i]}"
    else
      printf "  %s %s %s: %s\n" "$num" "${icons[$i]}" "${cmds[$i]}" "${descs[$i]}"
    fi
  done
  echo
  echo "Enter to select, number to jump, q to quit"
}

# Resolve binary locations robustly (support PATH or common install paths)
CLAUDE_BIN=$(command -v claude 2>/dev/null || true)
OPENCODE_BIN=$(command -v opencode 2>/dev/null || true)
if [[ -z "$CLAUDE_BIN" ]]; then
  CLAUDE_BIN="$HOME/.local/bin/claude"
fi
if [[ -z "$OPENCODE_BIN" ]]; then
  OPENCODE_BIN="$HOME/.local/share/pnpm/opencode"
fi

launch() {
  local idx=$selected
  local c="${cmds[$idx]}"
  clear
  case "$c" in
    RECENT)
      local rcmd
      rcmd=$(show_recent_menu) || return
      case "$rcmd" in
        claude) [[ -x "$CLAUDE_BIN" ]] && "$CLAUDE_BIN" || { echo "claude not found"; sleep 1; } ;;
        opencode) [[ -x "$OPENCODE_BIN" ]] && "$OPENCODE_BIN" || { echo "opencode not found"; sleep 1; } ;;
        *) command -v "$rcmd" >/dev/null 2>&1 && "$rcmd" || { echo "Not found: $rcmd"; sleep 1; } ;;
      esac
      ;;
    claude)
      if [[ -x "$CLAUDE_BIN" ]]; then
        echo "$(date +%s)|claude" >> "$RECENT_FILE"
        "$CLAUDE_BIN"
      else
        echo "claude not found or not executable"; sleep 1
      fi
      ;;
    opencode)
      if [[ -x "$OPENCODE_BIN" ]]; then
        echo "$(date +%s)|opencode" >> "$RECENT_FILE"
        "$OPENCODE_BIN"
      else
        echo "opencode not found or not executable"; sleep 1
      fi
      ;;
    *)
      if command -v "$c" >/dev/null 2>&1; then
        echo "$(date +%s)|$c" >> "$RECENT_FILE"
        "$c"
      elif [[ -x "$CONFIG_DIR/$c" ]]; then
        echo "$(date +%s)|$c" >> "$RECENT_FILE"
        "$CONFIG_DIR/$c"
      else
        echo "Unknown command: $c"; sleep 1
      fi
      ;;
  esac
}

render
while true; do
  read -r -n1 -s key
  case "$key" in
    q|Q)
      clear; exit 0
      ;;
    [0-9])
      idx=$((key - 1))
      if [[ "$idx" -ge 0 && "$idx" -lt "$len" ]]; then
        selected=$idx
        render
      fi
      ;;
    $'\x1b')
      read -r -s -n2 -t 0.1 esc
      case "$esc" in
        '[A') [[ $selected -gt 0 ]] && ((selected--)); render ;;
        '[B') [[ $selected -lt $((len-1)) ]] && ((selected++)); render ;;
      esac
      ;;
    "")
      launch; render
      ;;
  esac
done
