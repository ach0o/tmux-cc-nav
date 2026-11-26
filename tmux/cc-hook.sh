#!/bin/bash
# Claude Code hook: tmux 창에 상태(@cc), 시각(@cc_t), 현재 작업 폴더(@cc_cwd)를 남김
# 인자: run | wait | done | end. stdin은 hook 입력 JSON (cwd 필드 사용)
[ -n "$TMUX_PANE" ] || exit 0
in=$(cat)
cwd=$(printf '%s' "$in" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
case $1 in
  end) tmux set -wu -t "$TMUX_PANE" @cc ;;
  run|done) tmux set -w -t "$TMUX_PANE" @cc "$1" \; set -w -t "$TMUX_PANE" @cc_t "$(date +%s)" ;;
  *) tmux set -w -t "$TMUX_PANE" @cc "$1" ;;
esac 2>/dev/null
[ -n "$cwd" ] && tmux set -w -t "$TMUX_PANE" @cc_cwd "$cwd" 2>/dev/null
exit 0
