#!/bin/bash
# claude-tmux-status 설치: 스크립트를 ~/.tmux 에 복사하고, tmux 설정과 Claude Code hook을 연결함
set -e
here=$(cd "$(dirname "$0")" && pwd)

command -v fzf >/dev/null || [ -x /opt/homebrew/bin/fzf ] || { echo "fzf가 필요합니다: brew install fzf"; exit 1; }

mkdir -p ~/.tmux
cp "$here"/tmux/cc-hook.sh "$here"/tmux/cc-pick.sh "$here"/tmux/cc-sync.py "$here"/tmux/cc-color.sh "$here"/tmux/cc.tmux.conf "$here"/tmux/abc.swift ~/.tmux/
chmod +x ~/.tmux/cc-hook.sh ~/.tmux/cc-pick.sh ~/.tmux/cc-color.sh

# 한영 전환 도구 (macOS, 선택 기능용). 빌드 실패해도 나머지는 동작
if [ "$(uname)" = Darwin ] && command -v swiftc >/dev/null; then
  swiftc -O ~/.tmux/abc.swift -o ~/.tmux/abc 2>/dev/null && echo "abc 빌드 완료" || echo "abc 빌드 실패 (한영 전환 기능만 빠짐)"
fi

# tmux 설정 연결 (한 번만)
touch ~/.tmux.conf
grep -q 'cc.tmux.conf' ~/.tmux.conf || printf '\n# Claude Code 상태 표시\nsource-file ~/.tmux/cc.tmux.conf\n' >> ~/.tmux.conf

# Claude Code hook 추가 (기존 hook은 유지, 이미 있으면 건너뜀). 원본은 .bak-cc 로 백업
python3 - <<'PY'
import json, os, shutil
p = os.path.expanduser('~/.claude/settings.json')
os.makedirs(os.path.dirname(p), exist_ok=True)
d = json.load(open(p)) if os.path.exists(p) else {}
if os.path.exists(p): shutil.copy(p, p + '.bak-cc')
want = {
    'UserPromptSubmit': ('run', None), 'PostToolUse': ('run', None), 'Stop': ('done', None),
    'Notification': ('wait', 'permission_prompt|elicitation_dialog'), 'SessionEnd': ('end', None),
}
hooks = d.setdefault('hooks', {})
for ev, (arg, matcher) in want.items():
    cmd = f'~/.tmux/cc-hook.sh {arg}'
    groups = hooks.setdefault(ev, [])
    if any(h.get('command') == cmd for g in groups for h in g.get('hooks', [])): continue
    g = {'hooks': [{'type': 'command', 'command': cmd}]}
    if matcher: g['matcher'] = matcher
    groups.append(g)
json.dump(d, open(p, 'w'), indent=2, ensure_ascii=False)
PY

[ -n "$TMUX" ] && tmux source-file ~/.tmux.conf
echo "설치 완료. 이미 열려 있던 Claude 세션은 다시 시작해야 상태가 붙습니다."
