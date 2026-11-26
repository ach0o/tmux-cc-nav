#!/usr/bin/env python3
# Claude Code가 남기는 ~/.claude/sessions/<pid>.json의 status(busy/idle)로 @cc를 바로잡음.
# 중단(Esc)은 Stop hook이 안 불려 @cc가 run으로 남기 때문.
import glob, json, os, subprocess
st = {}
for f in glob.glob(os.path.expanduser('~/.claude/sessions/*.json')):
    try: d = json.load(open(f))
    except Exception: continue
    t = d.get('tmux', '')
    if '.%' in t: st['%' + t.split('.%')[1]] = d.get('status')
out = subprocess.run(['tmux', 'list-panes', '-a', '-F', '#{pane_id} #{window_id} #{@cc}'], capture_output=True, text=True).stdout
for line in out.splitlines():
    pane, win, *cc = line.split(' ')
    cc = cc[0] if cc else ''
    s = st.get(pane)
    if s == 'idle' and cc == 'run':
        subprocess.run(['tmux', 'set', '-w', '-t', win, '@cc', 'done'])
    elif s == 'busy' and cc not in ('run', 'wait'):
        subprocess.run(['tmux', 'set', '-w', '-t', win, '@cc', 'run'])
