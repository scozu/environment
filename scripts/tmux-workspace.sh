#!/usr/bin/env bash

set -euo pipefail

SESSION_NAME="${TMUX_SESSION_NAME:-dev}"
WINDOW_NAME="${TMUX_WINDOW_NAME:-environment}"
WORKDIR="${TMUX_WORKDIR:-$HOME/Developer/environment}"
RIGHT_PANE_PERCENT="${TMUX_RIGHT_PANE_PERCENT:-50}"
BOTTOM_PANE_PERCENT="${TMUX_BOTTOM_PANE_PERCENT:-22}"
RESET_LAYOUT="${TMUX_RESET_LAYOUT:-0}"
WINDOW_TARGET="$SESSION_NAME:$WINDOW_NAME"

if [ "${1:-}" = "--reset-layout" ]; then
  RESET_LAYOUT=1
fi

if ! command -v tmux >/dev/null 2>&1; then
  echo "tmux is not installed."
  exit 1
fi

if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  editor_pane=$(tmux new-session -d -s "$SESSION_NAME" -n "$WINDOW_NAME" -c "$WORKDIR" -P -F '#{pane_id}')
elif [ "$RESET_LAYOUT" = "1" ]; then
  tmux kill-window -t "$WINDOW_TARGET" 2>/dev/null || true
  editor_pane=$(tmux new-window -d -t "$SESSION_NAME" -n "$WINDOW_NAME" -c "$WORKDIR" -P -F '#{pane_id}')
else
  editor_pane=""
fi

if [ -n "$editor_pane" ]; then
  tmux send-keys -t "$editor_pane" "nvim" C-m

  ai_pane=$(tmux split-window -t "$editor_pane" -h -p "$RIGHT_PANE_PERCENT" -c "$WORKDIR" -P -F '#{pane_id}')
  tmux send-keys -t "$ai_pane" "opencode" C-m

  tmux split-window -t "$editor_pane" -v -f -p "$BOTTOM_PANE_PERCENT" -c "$WORKDIR"
  tmux select-pane -t "$editor_pane"
fi

tmux set-hook -u -t "$SESSION_NAME" client-attached
tmux set-hook -u -t "$SESSION_NAME" client-resized

if [ -n "${TMUX:-}" ]; then
  tmux switch-client -t "$SESSION_NAME"
else
  tmux attach-session -t "$SESSION_NAME"
fi
