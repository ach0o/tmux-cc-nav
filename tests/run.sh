#!/bin/bash
# tmux-cc-nav 테스트. 임시 HOME과 격리된 tmux 서버에서만 돌고, 쓰는 중인 tmux와 Claude 설정은 건드리지 않음.
# 실행: tests/run.sh   (필요: tmux, python3, fzf는 없어도 됨)
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
pass=0; fail=0; failed=()
ok()   { pass=$((pass+1)); }
bad()  { fail=$((fail+1)); failed+=("$1"); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "${@:2}"; }
eq()   { if [ "$2" = "$3" ]; then ok; else bad "$1" "기대: [$3]" "실제: [$2]"; fi; }
has()  { case $2 in *"$3"*) ok;; *) bad "$1" "[$3] 가 없음" "실제: [$2]";; esac; }
hasnt(){ case $2 in *"$3"*) bad "$1" "[$3] 가 있으면 안 됨" "실제: [$2]";; *) ok;; esac; }
strip(){ LC_ALL=C sed 's/\x1b\[[0-9;]*m//g'; }
plist(){ "$HOME/.tmux/cc-pick.sh" --list "$1" | tr '\0' '\n' | grep $'\t'; }  # 항목 첫 줄만
section(){ printf '\n== %s\n' "$1"; }

PIDS=()
new_home() {
  T=$(mktemp -d); export HOME=$T TMUX_TMPDIR=$T/sock; mkdir -p "$TMUX_TMPDIR"; unset TMUX TMUX_PANE
}
start_tmux() {  # $1 = tmux.conf 내용
  printf '%s\n' "$1" > "$HOME/.tmux.conf.pre"
  cat "$HOME/.tmux.conf.pre" "$HOME/.tmux.conf" 2>/dev/null > "$HOME/.tmux.conf.new"; mv "$HOME/.tmux.conf.new" "$HOME/.tmux.conf"
  tmux -f "$HOME/.tmux.conf" new-session -d -s s -x 150 -y 40
  sleep 0.3
  export TMUX="$(tmux display -p '#{socket_path}'),0,0"
}
end_home() { tmux kill-server 2>/dev/null; unset TMUX; for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null; done; PIDS=(); rm -rf "$T"; }
fake_session() {  # $1 pane, $2 busy|idle, [$3 window id 덮어쓰기]  → 살아 있는 pid로 세션 파일
  sleep 600 >/dev/null 2>&1 & local pid=$!; disown $pid; PIDS+=("$pid")
  local win=${3:-$(tmux display -p -t "$1" '#{window_id}')}
  mkdir -p "$HOME/.claude/sessions"
  printf '{"pid":%s,"tmux":"s:%s.%s","status":"%s","statusUpdatedAt":%s000}\n' "$pid" "$win" "$1" "$2" "$(date +%s)" > "$HOME/.claude/sessions/$pid.json"
}
hook() { printf '%s' "${3:-{\}}" | TMUX_PANE=$1 "$HOME/.tmux/cc-hook.sh" "$2"; }
popt() { tmux show -pv -t "$1" "$2" 2>/dev/null; }
wopt() { tmux show -wv -t "$1" "$2" 2>/dev/null; }

# ───────────────────────────────────────────────
section "설치 (install.sh)"
new_home
out=$(bash "$R/install.sh" 2>&1); has "settings.json 없어도 설치됨" "$out" "설치 완료"
eq "hook 5개 추가" "$(python3 -c "import json;d=json.load(open('$HOME/.claude/settings.json'));print(sum(1 for v in d['hooks'].values() for g in v for h in g['hooks'] if 'cc-hook.sh' in h['command']))")" 5
eq "tmux.conf에 source 줄 1개" "$(grep -c 'source-file ~/.tmux/cc.tmux.conf' "$HOME/.tmux.conf")" 1
bash "$R/install.sh" >/dev/null 2>&1
eq "다시 설치해도 hook 중복 없음" "$(grep -o 'cc-hook.sh' "$HOME/.claude/settings.json" | wc -l | tr -d ' ')" 5
eq "다시 설치해도 source 줄 중복 없음" "$(grep -c 'source-file ~/.tmux/cc.tmux.conf' "$HOME/.tmux.conf")" 1
eq "Notification은 권한 확인/질문만" "$(python3 -c "import json;d=json.load(open('$HOME/.claude/settings.json'));print(d['hooks']['Notification'][0]['matcher'])")" "permission_prompt|elicitation_dialog"
end_home

new_home; mkdir -p "$HOME/.claude"
echo '{"model":"x","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo mine"}]}]}}' > "$HOME/.claude/settings.json"
bash "$R/install.sh" >/dev/null 2>&1
s=$(cat "$HOME/.claude/settings.json")
has "기존 hook 유지" "$s" "echo mine"; has "기존 다른 설정 유지" "$s" '"model": "x"'
[ -f "$HOME/.claude/settings.json.bak-cc" ] && ok || bad "settings.json 백업"
end_home

# ───────────────────────────────────────────────
section "hook (cc-hook.sh)"
new_home; bash "$R/install.sh" >/dev/null 2>&1; start_tmux ""
P=$(tmux display -p -t s:0 '#{pane_id}')
out=$(printf '{}' | env -u TMUX_PANE "$HOME/.tmux/cc-hook.sh" run; echo "rc=$?")
eq "tmux 밖(TMUX_PANE 없음)이면 조용히 끝남" "$out" "rc=0"
out=$(hook "$P" run '{"cwd":"/tmp"}'); eq "출력 없음 (UserPromptSubmit 출력은 Claude 대화에 들어가므로)" "$out" ""
eq "run 기록" "$(popt "$P" @ccp)" run
case $(popt "$P" @ccp_t) in ''|*[!0-9]*) bad "시각은 숫자";; *) ok;; esac
eq "작업 폴더 기록" "$(popt "$P" @ccp_cwd)" /tmp
hook "$P" wait; eq "wait 기록" "$(popt "$P" @ccp)" wait
eq "cwd 없는 입력은 폴더 유지" "$(popt "$P" @ccp_cwd)" /tmp
hook "$P" done '{"session_id":"x","cwd":"/a b/한글 폴더","tool_input":{"cwd":"/evil"}}'
eq "맨 앞 cwd만 씀, 공백·한글 유지" "$(popt "$P" @ccp_cwd)" "/a b/한글 폴더"
hook "$P" done '{"cwd":"/q\"uo\\te\/x"}'
eq "JSON 이스케이프 풀기" "$(popt "$P" @ccp_cwd)" '/q"uo\te/x'
hook "$P" done '{
  "cwd": "/pretty"
}'
eq "여러 줄 JSON" "$(popt "$P" @ccp_cwd)" /pretty
hook "$P" end
eq "end면 상태 지움" "$(popt "$P" @ccp)$(popt "$P" @ccp_t)$(popt "$P" @ccp_cwd)" ""
eq "창 옵션은 안 건드림" "$(wopt s:0 @ccp)" ""
out=$(hook %999 run; echo "rc=$?"); eq "없는 pane이어도 오류 없이 끝남" "$out" "rc=0"
end_home

# ───────────────────────────────────────────────
section "상태 모으기 · 바로잡기 (cc-sync.py)"
new_home; bash "$R/install.sh" >/dev/null 2>&1; start_tmux ""
tmux split-window -d -t s:0; tmux split-window -d -t s:0; tmux split-window -d -t s:0; tmux split-window -d -t s:0
tmux select-layout -t s:0 tiled >/dev/null
PS=($(tmux list-panes -t s:0 -F "#{pane_id}"))
eq "pane 5개 준비" "${#PS[@]}" 5
fake_session "${PS[0]}" busy; fake_session "${PS[1]}" idle; fake_session "${PS[2]}" busy; fake_session "${PS[3]}" idle; fake_session "${PS[4]}" idle
hook "${PS[0]}" run; hook "${PS[1]}" run; hook "${PS[2]}" wait; sleep 1; hook "${PS[3]}" done '{"cwd":"/latest"}'
python3 "$HOME/.tmux/cc-sync.py"
eq "idle인데 run이면 done (Esc 중단)" "$(popt "${PS[1]}" @ccp)" done
eq "busy이면서 wait는 유지" "$(popt "${PS[2]}" @ccp)" wait
eq "hook 기록 없는 Claude pane은 세션 파일로 채움" "$(popt "${PS[4]}" @ccp)" done
exp=$(tmux list-panes -t s:0 -F '#{pane_top} #{pane_left} #{@ccp}' | sort -n -k1,1 -k2,2 | awk '{c=substr($3,1,1); printf "%s", (c==""?"-":c)}' | cut -c1-4)
eq "창 상태 코드: 화면 위치 순서, 최대 4개" "$(wopt s:0 @ccw_st)" "$exp"
eq "대표 pane = 가장 최근에 움직인 pane" "$(wopt s:0 @ccw_pane)" "${PS[3]}"
has "여러 개는 색 원 (prefix W)" "$(wopt s:0 @ccw_icon)" "●#[fg="
hasnt "아이콘 스타일에 쉼표 없음 (tmux 조건식이 깨짐)" "$(wopt s:0 @ccw_icon)" ","

# 2x2 pane 배치: 왼쪽 열을 먼저 나누면 pane 번호 순서(왼위, 왼아래, 오위, 오아래)와 화면 자리가 다름
tmux new-window -d -t s:5; tmux split-window -d -h -t s:5.0; tmux split-window -d -v -t s:5.0; tmux split-window -d -v -t s:5.2
for pos in "0 0 r" "0 1 w" "1 0 d" "1 1 r"; do set -- $pos
  pid=$(tmux list-panes -t s:5 -F '#{pane_top} #{pane_left} #{pane_id}' | sort -n -k1,1 -k2,2 | awk -v r=$1 -v c=$2 'BEGIN{n=r*2+c} NR==n+1{print $3}')
  case $3 in r) st=run b=busy;; w) st=wait b=busy;; d) st=done b=idle;; esac
  hook "$pid" "$st"; fake_session "$pid" "$b"
done
python3 "$HOME/.tmux/cc-sync.py"
eq "원 순서가 화면 위치 순서 (왼위·오위·왼아래·오아래)" "$(wopt s:5 @ccw_st)" rwdr
tmux kill-window -t s:5

# 비정상 종료: 세션 파일이 사라진 pane의 hook 기록은 지움
rm "$HOME/.claude/sessions/"*.json; fake_session "${PS[0]}" busy
python3 "$HOME/.tmux/cc-sync.py"
eq "세션 파일 없는 pane 기록 지움" "$(popt "${PS[3]}" @ccp_t)" ""
eq "남은 Claude 1개면 기호 하나" "$(wopt s:0 @ccw_st)" r

# 죽은 pid의 세션 파일은 무시
sleep 600 >/dev/null 2>&1 & dead=$!; kill $dead; wait $dead 2>/dev/null
printf '{"pid":%s,"tmux":"s:%s.%s","status":"busy"}\n' "$dead" "$(tmux display -p -t s:0 '#{window_id}')" "${PS[1]}" > "$HOME/.claude/sessions/dead.json"
echo '{broken' > "$HOME/.claude/sessions/broken.json"
python3 "$HOME/.tmux/cc-sync.py"; rc=$?
eq "깨진 JSON이 있어도 동작" "$rc" 0
eq "죽은 pid 세션은 Claude로 안 봄" "$(popt "${PS[1]}" @ccp)" ""

# 다른 tmux 서버의 같은 pane 번호: 창 번호가 다르고 hook 기록이 없으면 무시
tmux new-window -d -t s:1; Q=$(tmux display -p -t s:1 '#{pane_id}')
fake_session "$Q" busy "@9999"
python3 "$HOME/.tmux/cc-sync.py"
eq "창 번호 다른 세션은 무시" "$(popt "$Q" @ccp)" ""
# 같은 pane이 다른 창으로 옮겨진 경우: hook 기록이 있으면 유지
hook "$Q" wait; python3 "$HOME/.tmux/cc-sync.py"
eq "hook 기록 있으면 창 번호 달라도 유지" "$(popt "$Q" @ccp)" wait

# 예전 버전이 창에 남긴 옵션 정리
tmux set -w -t s:0 @cc run \; set -w -t s:0 @cc_t 1 \; set -w -t s:0 @cc_cwd /old
python3 "$HOME/.tmux/cc-sync.py"
eq "예전 창 옵션(@cc) 정리" "$(wopt s:0 @cc)$(wopt s:0 @cc_t)$(wopt s:0 @cc_cwd)" ""

# Claude가 다 끝난 창은 창 옵션도 지움
rm "$HOME/.claude/sessions/"*.json; hook "${PS[0]}" end
mkdir -p "$HOME/.claude/sessions"; fake_session "$Q" busy
python3 "$HOME/.tmux/cc-sync.py"
eq "Claude 없어진 창은 @ccw_* 지움" "$(wopt s:0 @ccw_st)$(wopt s:0 @ccw_pane)" ""
end_home

# 세션 파일을 안 쓰는 Claude Code 버전: hook 기록을 그대로 믿음
new_home; bash "$R/install.sh" >/dev/null 2>&1; start_tmux ""
P=$(tmux display -p -t s:0 '#{pane_id}')
hook "$P" run; python3 "$HOME/.tmux/cc-sync.py"
eq "세션 파일 없으면 hook 기록 유지" "$(wopt s:0 @ccw_st)" r
end_home

# ───────────────────────────────────────────────
section "그룹 색 (cc-color.sh)"
new_home; bash "$R/install.sh" >/dev/null 2>&1; start_tmux ""
names=('API-결제' 'API-인증' 'WEB_대시-보드' '-앞에구분자' '이름만' 'back\slash-x' "따옴'표-\"쌍\"" '50%-$HOME')
i=0; for n in "${names[@]}"; do tmux new-window -d -t "s:$((i+1))" -n "$n"; i=$((i+1)); done
tmux new-window -d -t s:20   # 이름 안 붙인 창 (자동 이름)
bash "$HOME/.tmux/cc-color.sh"; rc=$?
eq "오류 없이 끝남" "$rc" 0
eq "API-결제: 앞부분" "$(wopt s:1 @cc_g)|$(wopt s:1 @cc_s)|$(wopt s:1 @cc_r)" "API|-|결제"
eq "같은 그룹은 같은 색" "$(wopt s:1 @cc_col)" "$(wopt s:2 @cc_col)"
eq "첫 구분자에서 나눔 (_)" "$(wopt s:3 @cc_g)|$(wopt s:3 @cc_s)|$(wopt s:3 @cc_r)" "WEB|_|대시-보드"
eq "구분자로 시작하면 이름 전체가 그룹" "$(wopt s:4 @cc_g)|$(wopt s:4 @cc_r)" "-앞에구분자|"
eq "구분자 없으면 이름 전체" "$(wopt s:5 @cc_g)" "이름만"
eq "역슬래시 이름" "$(wopt s:6 @cc_g)" 'back\slash'
eq "따옴표 이름" "$(wopt s:7 @cc_g)|$(wopt s:7 @cc_r)" "따옴'표|\"쌍\""
eq "% \$ 이름" "$(wopt s:8 @cc_g)|$(wopt s:8 @cc_r)" '50%|$HOME'
eq "자동 이름 창은 건너뜀" "$(wopt s:20 @cc_g)" ""
eq "그룹 색 파일: 그룹 7개" "$(wc -l < "$HOME/.tmux/cc-groups" | tr -d ' ')" 7
eq "그룹마다 다른 색" "$(cut -f2 "$HOME/.tmux/cc-groups" | sort -u | wc -l | tr -d ' ')" 7
before=$(cat "$HOME/.tmux/cc-groups"); bash "$HOME/.tmux/cc-color.sh"
eq "다시 돌려도 색 그대로" "$(cat "$HOME/.tmux/cc-groups")" "$before"
tmux rename-window -t s:5 'NEW-그룹'; sleep 0.5
eq "이름 바꾸면 그 창만 다시 계산 (hook)" "$(wopt s:5 @cc_g)" NEW
end_home

# ───────────────────────────────────────────────
section "목록 (cc-pick.sh)"
new_home; bash "$R/install.sh" >/dev/null 2>&1; start_tmux ""
tmux rename-window -t s:0 'B-둘'; tmux new-window -d -t s:1 -n 'A-하나'; tmux new-window -d -t s:2 -n 'C-셋'; tmux new-window -d -t s:3
tmux split-window -d -t s:0
P0=$(tmux display -p -t s:0.0 '#{pane_id}'); P0b=$(tmux display -p -t s:0.1 '#{pane_id}')
P1=$(tmux display -p -t s:1 '#{pane_id}'); P2=$(tmux display -p -t s:2 '#{pane_id}')
tmux select-pane -t "$P0" -T '✳ 셸 제목'; tmux select-pane -t "$P0b" -T '✳ Claude 제목 %s $(x) `y`'
tmux select-pane -t s:0.0   # 활성 pane은 셸 쪽
hook "$P1" done '{"cwd":"/tmp"}'; sleep 1; hook "$P2" wait; sleep 1; hook "$P0b" run '{"cwd":"/tmp"}'
bash "$HOME/.tmux/cc-color.sh"; python3 "$HOME/.tmux/cc-sync.py"
L=$(plist time)
eq "최근 순: 0,2,1, 기록 없는 창은 마지막" "$(cut -f1 <<<"$L" | tr '\n' ' ')" "0 2 1 3 "
eq "대표 pane은 Claude pane" "$(head -1 <<<"$L" | cut -f2)" "$P0b"
row=$(head -1 <<<"$L" | cut -f3 | strip)
has "제목은 Claude pane 것 (특수문자 그대로)" "$row" 'Claude 제목 %s $(x) `y`'
hasnt "셸 제목은 안 나옴" "$row" "셸 제목"
has "창 이름 표시" "$row" "[B-둘]"
G=$(plist group)
eq "그룹 순: A, B, C, 이름 없는 창 마지막" "$(cut -f1 <<<"$G" | tr '\n' ' ')" "1 0 2 3 "
# 상태 칸 폭: 기호 1개든 원 4개든 화면 4칸
for st in '' r rw rwd rwdw; do
  tmux set -w -t s:3 @ccw_st "$st"
  # 시각(11칸) + 공백 뒤 4칸이 상태, 그다음이 공백이어야 제목이 안 밀림
  w=$(plist time | awk -F'\t' '$1==3{print $3}' | strip | python3 -c 'import sys;r=sys.stdin.read();print(repr(r[12:17]))')
  case $w in "'"????" '") ok;; *) bad "상태 칸 폭 4 ($st)" "실제: $w";; esac
done
tmux set -wu -t s:3 @ccw_st
tmux set -w -t s:3 @ccw_st rwd \; set -w -t s:3 @ccw_t 1
item=$("$HOME/.tmux/cc-pick.sh" --list time | python3 -c 'import sys;print([x for x in sys.stdin.read().split("\0") if x.startswith("3\t")][0])')
has "2x2 윗줄: 왼위 노랑, 오위 빨강" "$item" $'\e[33m●\e[31m●'
has "2x2 아랫줄: 시각 칸 아래, 왼아래 초록" "$item" $'\n            \e[32m●'
eq "항목 수 = 창 수 (두 줄 항목도 하나)" "$("$HOME/.tmux/cc-pick.sh" --list time | tr -cd '\0' | wc -c | tr -d ' ')" "$(tmux list-windows | wc -l | tr -d ' ')"
tmux set -w -t s:3 @ccw_st rw
item=$("$HOME/.tmux/cc-pick.sh" --list time | python3 -c 'import sys;print([x for x in sys.stdin.read().split("\0") if x.startswith("3\t")][0])')
hasnt "2개면 한 줄" "$item" $'\n'
pv=$("$HOME/.tmux/cc-pick.sh" --preview "$P0b" | head -1 | strip)
eq "미리보기 첫 줄은 Claude 작업 폴더" "$pv" "/tmp"
end_home

# ───────────────────────────────────────────────
section "설정 옵션 · 키 (cc.tmux.conf, cc-setup.sh)"
new_home; bash "$R/install.sh" >/dev/null 2>&1
start_tmux 'set -g prefix C-a
set -g @ccnav-key-popup C-j
set -g @ccnav-color-bracket 33
set -g @ccnav-mode-style none
set -g @ccnav-ime on'
has "fzf 목록 키 바꾸기" "$(tmux list-keys -T prefix C-j)" "cc-pick.sh"
has "기본 목록 키에 choose-tree까지 묶임" "$(tmux list-keys -T prefix W)" "choose-tree"
eq "색 옵션" "$(tmux show -gv @ccnav-color-bracket)" 33
eq "적지 않은 옵션은 기본값" "$(tmux show -gv @ccnav-preview)" "40%"
hasnt "mode-style none이면 안 건드림" "$(tmux show -g mode-style)" "colour238"
if [ -x "$HOME/.tmux/abc" ]; then
  eq "한영 전환: prefix를 직접 처리" "$(tmux show -gv prefix)" None
  eq "원래 prefix 저장" "$(tmux show -gv @ccnav-prefix)" C-a
  has "root 키에 입력기 전환 + prefix 모드" "$(tmux list-keys -T root C-a)" "switch-client -T prefix"
  tmux source-file "$HOME/.tmux.conf"
  eq "설정 다시 읽어도 prefix 유지" "$(tmux show -gv @ccnav-prefix)" C-a
  has "설정 다시 읽어도 root 키 유지" "$(tmux list-keys -T root C-a)" "switch-client"
else
  printf '  (abc 빌드 안 됨: 한영 전환 테스트 건너뜀)\n'
fi

section "제거 (uninstall.sh)"
python3 - "$HOME/.claude/settings.json" <<'PY'
import json,sys; p=sys.argv[1]; d=json.load(open(p))
d['hooks']['Stop'].append({'hooks':[{'type':'command','command':'echo mine'}]}); json.dump(d,open(p,'w'))
PY
bash "$R/uninstall.sh" >/dev/null 2>&1; rc=$?
eq "오류 없이 끝남" "$rc" 0
s=$(cat "$HOME/.claude/settings.json")
hasnt "우리 hook 제거" "$s" "cc-hook.sh"; has "다른 hook 유지" "$s" "echo mine"
eq "source 줄 제거" "$(grep -c 'cc.tmux.conf' "$HOME/.tmux.conf")" 0
eq "파일 제거" "$(ls "$HOME/.tmux" 2>/dev/null | grep -c '^cc')" 0
if [ -n "$(tmux show -gv @ccnav-prefix 2>/dev/null)$(tmux show -gv prefix)" ]; then
  eq "prefix 원래대로" "$(tmux show -gv prefix)" C-a
  eq "root 키 제거" "$(tmux list-keys -T root C-a 2>/dev/null | wc -l | tr -d ' ')" 0
fi
has "w는 기본 창 목록으로" "$(tmux list-keys -T prefix w)" "choose-tree"
end_home

new_home; out=$(bash "$R/uninstall.sh" 2>&1; echo "rc=$?")
has "설치 안 된 상태에서 제거해도 오류 없음" "$out" "rc=0"
end_home

# ───────────────────────────────────────────────
printf '\n통과 %d, 실패 %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || { printf '실패: %s\n' "${failed[@]}"; exit 1; }
