#!/bin/bash
# Claude Code 창 목록을 fzf로 보여주고, 고른 창으로 이동
# 정렬: time = 마지막 작업 시각(@ccw_t) 최근 순, group = 이름 앞부분(@cc_g) 순 → 그룹 안에서 최근 순
# 구분자 \x1f: 탭은 IFS 공백이라 빈 칸(@cc 없음 등)이 사라짐
# 색과 미리보기 크기는 tmux 옵션 @ccnav-* (cc.tmux.conf 에 기본값)
IFS='|' read -r CB CN CT PV <<<"$(tmux display -p '#{@ccnav-color-bracket}|#{@ccnav-color-name}|#{@ccnav-color-title}|#{@ccnav-preview}')"
# 상태 코드(r w d -) → 상태 칸. 폭은 @ccw_width (Claude가 가장 많은 창의 개수, cc-sync.py가 정함)
# Claude 1개는 기호(● ? ✓), 2개 이상은 색 원을 화면 위치 순서로
WD=$(tmux show -gv @ccw_width 2>/dev/null); WD=${WD:-1}
icon() {
  local c=$1 e=$'\e' out='' i
  if [ ${#c} -eq 1 ]; then
    case $c in r) out="$e[33m●";; w) out="$e[31m?";; d) out="$e[32m✓";; *) out="$e[38;5;240m·";; esac
  else
    for ((i=0; i<${#c}; i++)); do
      case ${c:$i:1} in r) out+="$e[33m●";; w) out+="$e[31m●";; d) out+="$e[32m●";; *) out+="$e[38;5;240m●";; esac
    done
  fi
  [ -n "$out" ] && out+="$e[0m"
  local n=$((WD - ${#c})); [ $n -lt 0 ] && n=0   # 폭 값이 오래된 경우 대비
  printf '%s%*s' "$out" $n ''
}
list() {
  # 창마다 한 줄. 대표 pane = 가장 최근에 움직인 Claude pane(@ccw_pane), 없으면 활성 pane
  tmux list-panes -s -f '#{?@ccw_pane,#{==:#{pane_id},#{@ccw_pane}},#{pane_active}}' \
    -F $'#{?@ccw_t,#{@ccw_t},0}\x1f#{window_index}\x1f#{pane_id}\x1f#{@ccw_st}\x1f#{?#{automatic-rename},,#{window_name}}\x1f#{@cc_g}\x1f#{@cc_s}\x1f#{@cc_r}\x1f#{s/colour//:#{?@cc_col,#{@cc_col},colour#{@ccnav-color-bracket}}}\x1f#{window_activity}\x1f#{s/^✳ //:pane_title}' |
  if [ "$1" = group ]; then
    # 그룹 키를 맨 앞에 붙여 정렬 후 떼어냄. 이름 없는 창은 맨 뒤(~)
    awk -F$'\x1f' -v OFS=$'\x1f' '{k=($6!="")?$6:(($5!="")?$5:"~"); print k,$0}' | LC_ALL=C sort -t$'\x1f' -k1,1 -k2,2nr | cut -d$'\x1f' -f2-
  else
    sort -t$'\x1f' -k1,1nr -k2,2n
  fi |
  while IFS=$'\x1f' read -r t idx pane st wn g sep rest col act title; do
    # Claude 기록이 없는 창은 tmux 마지막 출력 시각을 회색으로 (정렬은 그대로 맨 뒤)
    d=$t tc=2; [ "$t" = 0 ] && d=$act tc='2;38;5;240'
    when=$(date -r "$d" '+%m-%d %H:%M' 2>/dev/null || date -d "@$d" '+%m-%d %H:%M')
    e=$'\e'
    [ -n "$wn" ] && wn="$e[1;38;5;${CB}m[$e[38;5;${col}m${g:-$wn}$e[38;5;${CB}m$sep$e[38;5;${CN}m$rest$e[38;5;${CB}m]$e[0m "
    printf '%s\t%s\t\e['"$tc"'m%s\e[0m %s %s\e[38;5;'"$CT"'m%s\e[0m\n' "$idx" "$pane" "$when" "$(icon "$st")" "$wn" "$title"
  done
}
[ "$1" = --list ] && { list "$2"; exit; }
# 미리보기: 맨 위에 경로와 git 브랜치, 그 아래 pane 화면
if [ "$1" = --preview ]; then
  # $2 = pane id. Claude가 지금 일하는 폴더(@ccp_cwd, hook이 기록). 없으면 시작 폴더
  d=$(tmux display -p -t "$2" '#{?@ccp_cwd,#{@ccp_cwd},#{pane_current_path}}')
  b=$(git -C "$d" branch --show-current 2>/dev/null)
  printf '\e[38;5;'"$CB"'m%s\e[0m%s\n' "${d/#$HOME/~}" "${b:+  $'\e[38;5;214m'⎇ $b$'\e[0m'}"
  # 화면 아래 빈 줄은 지움 (follow로 맨 아래를 보여줄 때 빈 줄만 보이지 않게)
  tmux capture-pane -ep -t "$2" | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}'
  exit
fi

me=~/.tmux/cc-pick.sh
keys='j,k,g,G,q,p,s,t,/'
python3 ~/.tmux/cc-sync.py
cur=$(tmux display -p '#{window_index}')
items=$(list time)
# 열 때 커서를 지금 창 줄에 둠
pos=$(printf '%s\n' "$items" | awk -F'\t' -v c="$cur" '$1==c{print NR; exit}')
printf '%s\n' "$items" |
"$(command -v fzf || echo /opt/homebrew/bin/fzf)" --bind "load:pos(${pos:-1})" --ansi --delimiter=$'\t' --with-nth=3.. --no-sort --reverse --cycle --prompt='최근> ' \
  --preview "$me --preview {2}" --preview-window="down,$PV,border-top,follow,~1" \
  --header='j/k 이동 · Enter 이동 · / 검색(esc 복귀) · t 최근순 · s 그룹순 · p 미리보기 크기 · q 닫기' \
  --bind "j:down,k:up,g:first,G:last,q:abort" \
  --bind "p:change-preview-window(down,70%,border-top,follow,~1|hidden|down,$PV,border-top,follow,~1)+refresh-preview" \
  --bind "t:reload($me --list time)+change-prompt(최근> )+first,s:reload($me --list group)+change-prompt(그룹> )+first" \
  --bind "/:unbind($keys)+change-prompt(search> ),esc:rebind($keys)+clear-query+change-prompt(> )" |
cut -f1,2 | { IFS=$'\t' read -r w p && [ -n "$w" ] && tmux select-window -t ":$w" \; select-pane -t "$p"; }
