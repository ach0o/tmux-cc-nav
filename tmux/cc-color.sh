#!/bin/bash
# 창 이름 {1}-{2} / {1}_{2}: {1}(@cc_g)은 그룹마다 다른 색(@cc_col), {2}(@cc_r)는 공통 회색
# 구분자 없는 이름은 이름 전체가 그룹. 그룹-색 짝은 MAP에 저장해 색이 바뀌지 않게 함
# 색 목록은 tmux 옵션 @ccnav-palette. 그룹 수가 색 수를 넘으면 처음부터 다시 돌아 겹침
PALETTE=($(tmux show -gv @ccnav-palette 2>/dev/null))
[ ${#PALETTE[@]} -gt 0 ] || PALETTE=(39 214 141 114)
MAP=~/.tmux/cc-groups
touch "$MAP"
# 인자로 창 id(@N)를 주면 그 창만, 없으면 전체
if [ -n "$1" ]; then
  tmux display -p -t "$1" '#{window_id} #{automatic-rename} #{window_name}'
else
  tmux list-windows -a -F '#{window_id} #{automatic-rename} #{window_name}'
fi |
while read -r id auto name; do
  [ "$auto" = 1 ] && continue
  [ -n "$name" ] || continue
  case $name in
    # 구분자가 맨 앞이면(-abc) 앞부분이 비므로 이름 전체를 그룹으로
    [-_]*) g=$name; sep=; rest= ;;
    *[-_]*) g=${name%%[-_]*}; sep=${name:${#g}:1}; rest=${name:${#g}+1} ;;
    *) g=$name; sep=; rest= ;;
  esac
  key=${g//$'\t'/ }   # MAP은 탭 구분이라 그룹 이름의 탭은 공백으로
  # awk -v 는 역슬래시를 해석하므로 ENVIRON 으로 넘김
  c=$(K="$key" awk -F'\t' '$1==ENVIRON["K"]{print $2; exit}' "$MAP")
  if [ -z "$c" ]; then
    c=colour${PALETTE[$(( $(wc -l < "$MAP") % ${#PALETTE[@]} ))]}
    printf '%s\t%s\n' "$key" "$c" >> "$MAP"
  fi
  tmux set -w -t "$id" @cc_col "$c" \; set -w -t "$id" @cc_g "$g" \; set -w -t "$id" @cc_s "$sep" \; set -w -t "$id" @cc_r "$rest" 2>/dev/null
done
# 도중에 창이 닫히면 tmux set이 실패해 tmux가 "returned 1"을 띄움. 무시
exit 0
