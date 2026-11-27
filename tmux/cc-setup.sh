#!/bin/bash
# cc.tmux.conf 에서 불림: @ccnav-* 옵션을 읽어 키 바인딩과 hook을 건다
o() { tmux show -gv "@ccnav-$1" 2>/dev/null; }

size=$(o popup-size)
tmux bind "$(o key-popup)" display-popup -E -w "$size" -h "$size" ~/.tmux/cc-pick.sh

# 창 한 줄: 시각 · 상태 · [그룹-나머지] · 세션 제목. 색은 옵션을 화면에 그릴 때 읽음
b='colour#{@ccnav-color-bracket}'
# 상태 칸(@ccw_icon, 폭 맞춤까지)과 시각(@ccw_t)은 cc-sync.py 가 창마다 모아 둔 값
fmt='#{?window_format,#[dim]#{?@ccw_t,#{t/f/%m-%d %H%M:@ccw_t},          }#[default] #{@ccw_icon} '
fmt+="#{?#{automatic-rename},,#[bold fg=$b][#[fg=#{?@cc_col,#{@cc_col},$b}]#{?@cc_g,#{@cc_g},#{window_name}}#[fg=$b]#{@cc_s}#[fg=colour#{@ccnav-color-name}]#{@cc_r}#[fg=$b]]#[default] }"
# 제목은 가장 최근에 움직인 Claude pane(@ccw_pane) 것, 없으면 활성 pane
fmt+='#[fg=colour#{@ccnav-color-title}]#{?@ccw_pane,#{P:#{?#{==:#{pane_id},#{@ccw_pane}},#{s/^✳ //:pane_title},}},#{s/^✳ //:pane_title}}#[default],#{?pane_format,#{s/^✳ //:pane_title},#{session_windows} windows#{?session_attached, (attached),}}}'
tmux bind "$(o key-tree)" run-shell "python3 ~/.tmux/cc-sync.py" '\;' choose-tree -Zw -F "$fmt"

# 선택 줄 색: 기본 노랑 위에서는 상태 기호 색이 안 보임. none 이면 건드리지 않음
ms=$(o mode-style)
[ "$ms" != none ] && tmux set -g mode-style "$ms"

# prefix를 누르면 입력기를 영문으로 (macOS). 원래 prefix 키는 @ccnav-prefix 에 한 번만 저장
if [ "$(o ime)" = on ] && [ -x ~/.tmux/abc ]; then
  p=$(tmux show -gv prefix)
  [ "$p" != None ] && tmux set -g @ccnav-prefix "$p"
  p=$(o prefix)
  tmux set -g prefix None \; bind -n "$p" run-shell -b ~/.tmux/abc '\;' switch-client -T prefix \; bind "$p" send-keys "$p"
fi

# 창 이름 그룹 색: 이름을 직접 바꿀 때 그 창만 다시 계산
tmux set-hook -g window-renamed 'if -F "#{automatic-rename}" "" "run-shell -b \"~/.tmux/cc-color.sh #{window_id}\""'
tmux run-shell -b ~/.tmux/cc-color.sh
