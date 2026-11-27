#!/bin/bash
# tmux-cc-nav 제거: install.sh가 넣은 파일, tmux 설정 줄, Claude Code hook을 지움
set -e

# Claude Code hook 제거 (~/.tmux/cc-hook.sh 를 부르는 것만). 원본은 .bak-cc-uninstall 로 백업
python3 - <<'PY'
import json, os, shutil
p = os.path.expanduser('~/.claude/settings.json')
if os.path.exists(p):
    shutil.copy(p, p + '.bak-cc-uninstall')
    d = json.load(open(p))
    hooks = d.get('hooks', {})
    for ev in list(hooks):
        groups = []
        for g in hooks[ev]:
            g['hooks'] = [h for h in g.get('hooks', []) if 'cc-hook.sh' not in h.get('command', '')]
            if g['hooks']: groups.append(g)
        if groups: hooks[ev] = groups
        else: del hooks[ev]
    if not hooks: d.pop('hooks', None)
    json.dump(d, open(p, 'w'), indent=2, ensure_ascii=False)
PY

# ~/.tmux.conf 에서 install.sh가 넣은 두 줄 제거
if [ -f ~/.tmux.conf ]; then
  grep -v -e '^source-file ~/.tmux/cc.tmux.conf$' -e '^# Claude Code 상태 표시$' ~/.tmux.conf > ~/.tmux.conf.tmp-cc || true
  mv ~/.tmux.conf.tmp-cc ~/.tmux.conf
fi

rm -f ~/.tmux/cc-hook.sh ~/.tmux/cc-setup.sh ~/.tmux/cc-pick.sh ~/.tmux/cc-sync.py ~/.tmux/cc-color.sh ~/.tmux/cc.tmux.conf ~/.tmux/cc-groups ~/.tmux/abc ~/.tmux/abc.swift

# 실행 중인 tmux에서 키와 hook을 기본값으로 되돌림
if [ -n "$TMUX" ]; then
  o() { tmux show -gv "@ccnav-$1" 2>/dev/null; }
  kp=$(o key-popup); kt=$(o key-tree); p=$(o prefix)
  [ -n "$kp" ] && tmux unbind "$kp"; [ -n "$kt" ] && tmux unbind "$kt"
  tmux bind w choose-tree -Zw \; set -gu mode-style \; set-hook -gu window-renamed
  # 영문 전환(@ccnav-ime)을 썼으면 원래 prefix 키로 되돌림
  if [ -n "$p" ]; then tmux unbind -n "$p" \; set -g prefix "$p" \; bind "$p" send-prefix; fi
  for k in $(tmux show -g | awk '/^@ccnav-/{print $1}'); do tmux set -gu "$k"; done
  tmux source-file ~/.tmux.conf
fi
echo "제거 완료. 열려 있는 Claude 세션은 다시 시작하면 hook이 빠진 채로 뜹니다."
