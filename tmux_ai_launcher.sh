#!/usr/bin/env bash
# AI launcher script for tmux - prompts user to choose claude or opencode

tmux split-window -h -l 50 -c "#{pane_current_path}" \
  "echo '1) claude\n2) opencode'; read -n1 choice; case $choice in 1) exec claude;; 2) exec opencode run -t;; esac"