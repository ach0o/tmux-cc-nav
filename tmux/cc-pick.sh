#!/bin/bash
# Claude Code 창 목록을 fzf로 보여주고, 고른 창으로 이동
# 정렬: time = 마지막 작업 시각(@cc_t) 최근 순, group = 이름 앞부분(@cc_g) 순 → 그룹 안에서 최근 순
# 구분자 \x1f: 탭은 IFS 공백이라 빈 칸(@cc 없음 등)이 사라짐
list() {
  tmux list-windows -F $'#{?@cc_t,#{@cc_t},0}\x1f#{window_index}\x1f#{@cc}\x1f#{?#{automatic-rename},,#{window_name}}\x1f#{@cc_g}\x1f#{@cc_s}\x1f#{@cc_r}\x1f#{s/colour//:#{?@cc_col,#{@cc_col},colour44}}\x1f#{s/^✳ //:pane_title}' |
  if [ "$1" = group ]; then
    # 그룹 키를 맨 앞에 붙여 정렬 후 떼어냄. 이름 없는 창은 맨 뒤(~)
    awk -F$'\x1f' -v OFS=$'\x1f' '{k=($5!="")?$5:(($4!="")?$4:"~"); print k,$0}' | LC_ALL=C sort -t$'\x1f' -k1,1 -k2,2nr | cut -d$'\x1f' -f2-
  else
    sort -t$'\x1f' -k1,1nr -k2,2n
  fi |
  while IFS=$'\x1f' read -r t idx st wn g sep rest col title; do
    if [ "$t" = 0 ]; then when='           '; else when=$(date -r "$t" '+%m-%d %H:%M' 2>/dev/null || date -d "@$t" '+%m-%d %H:%M'); fi
    case $st in
      run)  s=$'\e[33m●\e[0m' ;;
      wait) s=$'\e[31m?\e[0m' ;;
      done) s=$'\e[32m✓\e[0m' ;;
      *)    s=' ' ;;
    esac
    [ -n "$wn" ] && wn=$'\e[1;38;5;44m[\e[38;5;'"$col"'m'"${g:-$wn}"$'\e[38;5;44m'"$sep"$'\e[38;5;255m'"$rest"$'\e[38;5;44m]\e[0m '
    printf '%s\t\e[2m%s\e[0m %s %s\e[38;5;250m%s\e[0m\n' "$idx" "$when" "$s" "$wn" "$title"
  done
}
[ "$1" = --list ] && { list "$2"; exit; }
# 미리보기: 맨 위에 경로와 git 브랜치, 그 아래 창 화면
if [ "$1" = --preview ]; then
  # Claude가 지금 일하는 폴더(@cc_cwd, hook이 기록). 없으면 시작 폴더
  d=$(tmux display -p -t ":$2" '#{?@cc_cwd,#{@cc_cwd},#{pane_current_path}}')
  b=$(git -C "$d" branch --show-current 2>/dev/null)
  printf '\e[38;5;44m%s\e[0m%s\n' "${d/#$HOME/~}" "${b:+  $'\e[38;5;214m'⎇ $b$'\e[0m'}"
  # 화면 아래 빈 줄은 지움 (follow로 맨 아래를 보여줄 때 빈 줄만 보이지 않게)
  tmux capture-pane -ep -t ":$2" | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}'
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
"$(command -v fzf || echo /opt/homebrew/bin/fzf)" --bind "load:pos(${pos:-1})" --ansi --delimiter=$'\t' --with-nth=2.. --no-sort --reverse --cycle --prompt='최근> ' \
  --preview "$me --preview {1}" --preview-window='down,40%,border-top,follow,~1' \
  --header='j/k 이동 · Enter 이동 · / 검색(esc 복귀) · t 최근순 · s 그룹순 · p 미리보기 크기 · q 닫기' \
  --bind "j:down,k:up,g:first,G:last,q:abort" \
  --bind "p:change-preview-window(down,70%,border-top,follow,~1|hidden|down,40%,border-top,follow,~1)+refresh-preview" \
  --bind "t:reload($me --list time)+change-prompt(최근> )+first,s:reload($me --list group)+change-prompt(그룹> )+first" \
  --bind "/:unbind($keys)+change-prompt(search> ),esc:rebind($keys)+clear-query+change-prompt(> )" |
cut -f1 | xargs -I{} tmux select-window -t :{}
