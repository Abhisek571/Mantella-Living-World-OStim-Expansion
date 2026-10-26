"""Checks a test.log written in test mode (MAE_TestMode = 1, driven by MAE_Test) against the flow rules
that test\\simulate.py checks offline, plus what each scenario expects to happen.

usage: py -3 validate.py <test.log> <flows.json>
Exit code 1 on any failure.
"""
import json, re, sys

ALLOWED_THEMES = ('normal|-|-|neutral', 'normal|-|-|romantic')
CHAIN_SETS, MAX_POSE_PER_CHAIN = 4, 2

# What a scenario must (and must not) log, by its MAE_Test.Begin name.
EXPECT = {   # regex; a literal | is \|
    'flow': {'must': [r'MUTE\|outfit tracking off', r'SET\|opener', r'SET\|next', r'EVENT\|.* have started: '], 'not': [r'TAKEOVER\|']},
    'finish': {'must': [r'SET\|finish|HOLD\|no finish set fits'], 'not': [r'TAKEOVER\|']},
    'climax-satisfied': {'must': [r'CLIMAX\|', r'EVENT\|.* just climaxed\.'], 'not': [r'SET\|new chain', r'TAKEOVER\|']},
    'climax-more': {'must': [r'CLIMAX\|', r'SET\|new chain'], 'not': [r'TAKEOVER\|']},
    'takeover': {'must': [r'TAKEOVER\|'], 'not': []},
    'request': {'must': [r'REQUEST\|', r'SET\|request'], 'not': ['none fits']},
    'request-bad': {'must': [r'EVENT\|There is no way to do '], 'not': [r'SET\|request']},
    'favourites': {'must': [r"EVENT\|.*'s favourite sex positions: "], 'not': []},
    'unrated': {'must': [r'EVENT\|.* have not been rated yet\.'], 'not': []},
    'summary': {'must': [r'END\|', r'EVENT\|.* finished having sex'], 'not': []},
    'bystander': {'must': [r'EVENT\|.* watching from the side'], 'not': []},
}


def load(path):
    rows = []
    for raw in open(path, encoding='utf-8', errors='replace'):
        raw = raw.rstrip('\n')
        if '|' in raw:
            rows.append(raw.split('|', 1)[1])
    return rows


def matches(line, pattern):
    return re.search(pattern, line, re.I) is not None


def field(parts, name):
    for p in parts:
        if p.startswith(name + '='):
            return p[len(name) + 1:]
    return None


def main():
    log, cat_path = sys.argv[1], sys.argv[2]
    c = json.load(open(cat_path, encoding='utf-8'))
    poses = c['stringList']['poses']
    finish_at = None
    fails, notes = [], []
    scenarios = []          # [name, [lines]]
    for line in load(log):
        if line.lower().startswith('test|setup|finish='):
            finish_at = float(line.split('=')[1])
        if line.lower().startswith('test|begin|'):
            scenarios.append([line.split('|')[2].lower(), []])
        elif scenarios:
            scenarios[-1][1].append(line)
    if not scenarios:
        print('FAIL: no scenarios in the log'); sys.exit(1)

    for name, lines in scenarios:
        bad = []
        prev = None; used = set(); chain_poses = {}; excited = {}
        takeover = False; after_climax = None; satisfied = None; requested = None; finish_in_chain = False
        sets = 0
        for line in lines:
            parts = line.split('|')
            if line.lower().startswith('test|excite|'):
                excited[parts[2]] = float(parts[3])
            elif line.lower().startswith('test|satisfied|'):
                satisfied = parts[3] == '1'
            elif line.lower().startswith('flow|takeover|'):
                takeover = True
            elif line.lower().startswith('flow|climax|'):
                after_climax = True
            elif line.lower().startswith('flow|request|') and len(parts) == 3:
                requested = parts[2]
            elif line.lower().startswith('flow|set|'):
                sets += 1
                why, idx = parts[2].lower(), int(parts[3])
                s = {k: (field(parts, k) or '').lower() for k in ('pack', 'pose', 'rank', 'furn', 'chain')}
                s['theme'] = re.search(r'\|theme=(.*?)\|chain=', line).group(1).lower()
                pose, rank, chain = int(s['pose']), int(s['rank']), int(s['chain'])
                where = f'{name}: set {idx} ({why})'
                if s['theme'] not in ALLOWED_THEMES:
                    bad.append(f'{where}: theme {s["theme"]} not allowed')
                if takeover and why != 'request':
                    bad.append(f'{where}: played after the player took over')
                if why == 'finish':
                    if rank != 3: bad.append(f'{where}: finish set has rank {rank}')
                    if finish_at is not None and not any(v >= finish_at for v in excited.values()):
                        bad.append(f'{where}: finish before anyone reached excitement {finish_at}')
                    if finish_in_chain: bad.append(f'{where}: second finish in one chain')
                    finish_in_chain = True
                else:
                    if rank >= 3: bad.append(f'{where}: rank {rank} outside a finish')
                    if idx in used: bad.append(f'{where}: set reused in the scene')
                    used.add(idx)
                if why == 'opener':
                    if rank > 2: bad.append(f'{where}: opener rank {rank}')
                    chain_poses = {}
                elif why == 'next' and prev:
                    if s['pack'] != prev['pack']: bad.append(f'{where}: pack changed {prev["pack"]} -> {s["pack"]}')
                    if s['furn'] != prev['furn']: bad.append(f'{where}: furniture changed')
                    if s['theme'] != prev['theme']: bad.append(f'{where}: theme changed')
                    if rank < int(prev['rank']): bad.append(f'{where}: intensity dropped {prev["rank"]} -> {rank}')
                elif why == 'new chain':
                    if not after_climax: bad.append(f'{where}: new chain without her climax')
                    if satisfied: bad.append(f'{where}: new chain although she was satisfied')
                    if prev and s['pack'] != prev['pack']: bad.append(f'{where}: new chain changed pack')
                    chain_poses = {}; finish_in_chain = False
                elif why == 'request':
                    if requested is None or poses[pose].lower() != requested.lower():
                        bad.append(f'{where}: request for {requested} played {poses[pose]}')
                    takeover = False; finish_in_chain = False
                if why != 'finish':
                    chain_poses[pose] = chain_poses.get(pose, 0) + 1
                    if why != 'request' and chain_poses[pose] > MAX_POSE_PER_CHAIN:
                        bad.append(f'{where}: pose {poses[pose]} {chain_poses[pose]} times in a chain')
                    if chain > CHAIN_SETS: bad.append(f'{where}: chain at {chain} sets')
                if why != 'finish':
                    prev = s   # a finish may be borrowed from another pack; the chain goes on from its own set
        exp = EXPECT.get(name.split(':')[0], {'must': [], 'not': []})
        for pat in exp['must']:
            if not any(matches(l, pat) for l in lines):
                bad.append(f'{name}: expected "{pat}" never logged')
        for pat in exp['not']:
            if any(matches(l, pat) for l in lines):
                bad.append(f'{name}: "{pat}" logged but should not be')
        status = 'ok' if not bad else 'FAIL'
        print(f'{status:4} {name}: {sets} sets, {len(lines)} lines')
        for b in bad:
            print('     ' + b)
        fails += bad
    print(f'\n{len(scenarios)} scenarios, {len(fails)} failures')
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
