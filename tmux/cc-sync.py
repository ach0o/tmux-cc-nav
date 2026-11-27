#!/usr/bin/env python3
"""Claude pane 상태를 바로잡고 창마다 모아 창 옵션에 적는다. 목록을 열 때 불림.

pane 옵션 (hook이 기록): @ccp = run|wait|done, @ccp_t = 시각, @ccp_cwd = 작업 폴더
창 옵션 (여기서 기록):   @ccw_st   = 화면 위치 순서(왼쪽 위부터)로 상태 코드 (r w d -), 최대 4개
                         @ccw_icon = 같은 내용을 tmux 스타일로 그린 것 (prefix W 목록용, 4칸 폭)
                         @ccw_t    = 가장 최근 시각, @ccw_pane = 가장 최근에 움직인 Claude pane
바로잡기: Esc로 중단하면 Stop hook이 안 불려 run으로 남음. ~/.claude/sessions/<pid>.json 의 busy/idle 로 맞춤.
"""
import glob, json, os, re, subprocess

def tmux(*a):
    return subprocess.run(['tmux', *a], capture_output=True, text=True).stdout

sess = {}  # pane_id -> (window_id, status, updated_sec)
trusted = False  # 세션 파일에 tmux 위치가 적혀 있는지 (Claude Code 버전에 따라 없을 수 있음)
for f in glob.glob(os.path.expanduser('~/.claude/sessions/*.json')):
    try: d = json.load(open(f))
    except Exception: continue
    # "tmux": "<세션>:@<창>.%<pane>". pane 번호는 tmux 서버마다 따로라, 창 번호까지 맞아야 같은 pane으로 봄
    m = re.fullmatch(r'(.*):(@\d+)\.(%\d+)', str(d.get('tmux', '')))
    if not m: continue
    trusted = True
    try: os.kill(int(d.get('pid')), 0)   # 비정상 종료로 남은 파일은 건너뜀
    except (OSError, TypeError, ValueError): continue
    upd = d.get('statusUpdatedAt') or d.get('updatedAt') or 0
    sess[m.group(3)] = (m.group(2), d.get('status'), int(upd) // 1000 if str(upd).isdigit() else 0)

F = '\x1f'
rows = tmux('list-panes', '-a', '-F', F.join(['#{window_id}', '#{pane_id}', '#{@ccp}', '#{@ccp_t}', '#{@ccw_st}', '#{@cc}', '#{pane_top}', '#{pane_left}']))
wins, cmds, had, old = {}, [], set(), set()
for line in rows.splitlines():
    win, pane, st, t, wst, legacy, top, left = line.split(F)
    if wst: had.add(win)
    if legacy: old.add(win)  # 예전 버전이 창에 남긴 @cc
    info = sess.get(pane)
    # 창 번호가 다르면 다른 tmux 서버의 같은 번호 pane일 수 있음. 단 hook 기록이 있으면 이 pane이 맞음
    # (join-pane 등으로 pane이 다른 창으로 옮겨진 경우)
    if info and info[0] != win and not t: info = None
    if not info:
        # 세션 파일이 없는 pane: hook 기록(@ccp_t)이 있으면 Claude pane으로 믿음.
        # 다만 이 Claude Code가 세션 파일을 쓰는 버전인데(trusted) 목록에 없으면 비정상 종료로 남은 기록이라 지움
        if not t: continue
        if trusted and pane not in sess:
            cmds += [['set', '-pu', '-t', pane, k] for k in ('@ccp', '@ccp_t', '@ccp_cwd')]
            continue
        new = st
    else:
        _, busy, upd = info
        new = st
        if busy == 'idle' and st in ('run', ''): new = 'done'
        elif busy == 'busy' and st not in ('run', 'wait'): new = 'run'
        if new != st: cmds.append(['set', '-p', '-t', pane, '@ccp', new])
        if not t.isdigit():
            t = str(upd); cmds.append(['set', '-p', '-t', pane, '@ccp_t', t])
    wins.setdefault(win, []).append((int(top), int(left), pane, new, int(t) if t.isdigit() else 0))

COL = {'r': 'yellow', 'w': 'red', 'd': 'green', '-': 'colour240'}
def icon(codes):
    # 항상 4칸 폭. 1개: 기호(● ? ✓). 2~4개: 색 원을 화면 위치 순서로
    if len(codes) == 1:
        return {'r': '#[fg=yellow]●', 'w': '#[fg=red]?', 'd': '#[fg=green]✓', '-': '#[fg=colour240]·'}[codes] + '#[default]   '
    return ''.join(f'#[fg={COL[c]}]●' for c in codes) + '#[default]' + ' ' * (4 - len(codes))

for win, panes in wins.items():
    # 화면 위치 순서(위 → 아래, 왼쪽 → 오른쪽)로 원을 놓아 실제 pane 배치를 읽는 순서와 같게 함
    panes.sort()
    codes = ''.join({'run': 'r', 'wait': 'w', 'done': 'd'}.get(s, '-') for _, _, _, s, _ in panes)[:4]
    last = max(panes, key=lambda p: p[4])
    cmds += [['set', '-w', '-t', win, k, v] for k, v in
             (('@ccw_st', codes), ('@ccw_icon', icon(codes)), ('@ccw_t', str(last[4])), ('@ccw_pane', last[2]))]
for win in had - set(wins):
    cmds += [['set', '-wu', '-t', win, k] for k in ('@ccw_st', '@ccw_icon', '@ccw_t', '@ccw_pane')]

for win in old:
    cmds += [['set', '-wu', '-t', win, k] for k in ('@cc', '@cc_t', '@cc_cwd')]

# 한 번의 tmux 호출로 적용 (창 50개면 호출 수백 번이 아니라 1번)
if cmds:
    args = []
    for c in cmds: args += c + [';']
    subprocess.run(['tmux', *args[:-1]], capture_output=True)
