#!/usr/bin/env python3
"""Claude pane 상태를 바로잡고 창마다 모아 창 옵션에 적는다. 목록을 열 때 불림.

pane 옵션 (hook이 기록): @ccp = run|wait|done, @ccp_t = 시각, @ccp_cwd = 작업 폴더
창 옵션 (여기서 기록):   @ccw_st   = pane 순서대로 상태 코드 (r w d -), 최대 4개
                         @ccw_icon = 같은 내용을 tmux 스타일로 그린 것 (prefix W 목록용)
                         @ccw_t    = 가장 최근 시각, @ccw_pane = 가장 최근에 움직인 Claude pane
바로잡기: Esc로 중단하면 Stop hook이 안 불려 run으로 남음. ~/.claude/sessions/<pid>.json 의 busy/idle 로 맞춤.
"""
import glob, json, os, subprocess

def tmux(*a):
    return subprocess.run(['tmux', *a], capture_output=True, text=True).stdout

sess = {}  # pane_id -> (status, updated_sec)
for f in glob.glob(os.path.expanduser('~/.claude/sessions/*.json')):
    try: d = json.load(open(f))
    except Exception: continue
    t = d.get('tmux', '')
    if '.%' in t:
        sess['%' + t.split('.%')[1]] = (d.get('status'), (d.get('statusUpdatedAt') or d.get('updatedAt') or 0) // 1000)

F = '\x1f'
rows = tmux('list-panes', '-a', '-F', F.join(['#{window_id}', '#{pane_id}', '#{@ccp}', '#{@ccp_t}', '#{@ccw_st}', '#{@cc}']))
wins, cmds, had, old = {}, [], set(), set()
for line in rows.splitlines():
    win, pane, st, t, wst, legacy = line.split(F)
    if wst: had.add(win)
    if legacy: old.add(win)  # 예전 버전이 창에 남긴 @cc
    if pane not in sess:
        if st or t: cmds += [['set', '-pu', '-t', pane, '@ccp'], ['set', '-pu', '-t', pane, '@ccp_t']]
        continue
    busy, upd = sess[pane]
    new = st
    if busy == 'idle' and st in ('run', ''): new = 'done'
    elif busy == 'busy' and st not in ('run', 'wait'): new = 'run'
    if new != st: cmds.append(['set', '-p', '-t', pane, '@ccp', new])
    if not t:
        t = str(upd); cmds.append(['set', '-p', '-t', pane, '@ccp_t', t])
    wins.setdefault(win, []).append((pane, new, int(t)))

COL = {'r': 'yellow', 'w': 'red', 'd': 'green', '-': 'colour240'}
def icon(codes):
    # 1개: 기호 그대로. 2~4개: 반칸 블록 ▀ 두 칸으로 2x2 (윗칸=글자색, 아랫칸=배경색)
    if len(codes) == 1:
        return {'r': '#[fg=yellow]●', 'w': '#[fg=red]?', 'd': '#[fg=green]✓', '-': '#[fg=colour240]·'}[codes] + '#[default] '
    c = list(codes) + [''] * (4 - len(codes))
    out = ''
    for top, bot in ((c[0], c[2]), (c[1], c[3])):
        if top and bot: out += f'#[fg={COL[top]} bg={COL[bot]}]▀'
        elif top: out += f'#[fg={COL[top]} bg=default]▀'
        elif bot: out += f'#[fg={COL[bot]} bg=default]▄'
        else: out += '#[default] '
    return out + '#[default]'

for win, panes in wins.items():
    codes = ''.join({'run': 'r', 'wait': 'w', 'done': 'd'}.get(s, '-') for _, s, _ in panes)[:4]
    last = max(panes, key=lambda p: p[2])
    cmds += [['set', '-w', '-t', win, k, v] for k, v in
             (('@ccw_st', codes), ('@ccw_icon', icon(codes)), ('@ccw_t', str(last[2])), ('@ccw_pane', last[0]))]
for win in had - set(wins):
    cmds += [['set', '-wu', '-t', win, k] for k in ('@ccw_st', '@ccw_icon', '@ccw_t', '@ccw_pane')]

for win in old:
    cmds += [['set', '-wu', '-t', win, k] for k in ('@cc', '@cc_t', '@cc_cwd')]

# 한 번의 tmux 호출로 적용 (창 50개면 호출 수백 번이 아니라 1번)
if cmds:
    args = []
    for c in cmds: args += c + [';']
    subprocess.run(['tmux', *args[:-1]], capture_output=True)
