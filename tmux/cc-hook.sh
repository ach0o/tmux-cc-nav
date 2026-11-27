#!/bin/bash
# Claude Code hook: Claude가 도는 tmux pane에 상태(@ccp), 시각(@ccp_t), 작업 폴더(@ccp_cwd)를 남김
# 창 단위로 모으는 일은 목록을 열 때 cc-sync.py가 함 (한 창에 Claude 여러 개 지원)
# 인자: run | wait | done | end. stdin은 hook 입력 JSON (cwd 필드 사용)
[ -n "$TMUX_PANE" ] || exit 0
p=$TMUX_PANE
# 맨 앞의 "cwd" 하나만 씀 (뒤쪽 tool_input 안에 같은 키가 있어도 무시). JSON 이스케이프 \" \\ \/ 는 풀어 줌
cwd=$(grep -o '"cwd"[[:space:]]*:[[:space:]]*"\([^"\\]\|\\.\)*"' | head -1 |
      sed -e 's/^"cwd"[[:space:]]*:[[:space:]]*"//' -e 's/"$//' -e 's/\\\(["\\/]\)/\1/g')
if [ "$1" = end ]; then
  tmux set -pu -t "$p" @ccp \; set -pu -t "$p" @ccp_t \; set -pu -t "$p" @ccp_cwd 2>/dev/null
  exit 0
fi
tmux set -p -t "$p" @ccp "$1" \; set -p -t "$p" @ccp_t "$(date +%s)" 2>/dev/null
[ -n "$cwd" ] && tmux set -p -t "$p" @ccp_cwd "$cwd" 2>/dev/null
exit 0
