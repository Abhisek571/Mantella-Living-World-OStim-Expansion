"""Static checks for the affection action (no game needed).

1. Every scene in affection.json against the scene file that wins in the MO2 profile's order (overwrite first, then
   the top of modlist.txt, then the stock game): two actors, the pair the list is for, only allowed (non-sexual)
   actions, no transition away, the furniture the kind needs, the who_ action that tells who does it, and the
   animation files present.
2. The Mantella action file against affection.json: the kind enum equals the listed kinds, the who description names
   exactly the who_ kinds, the chair kinds say they need a chair, and every kind has its seconds, name, line and end.
3. Every mod event MAE_Affection and MAE_Ask register for: the handler exists with the parameters its senders push
   (Mantella's own source in the profile, the Living World modules, OStim's standard 4-value events), and
   MLW_ScoreEvent's push matches its receivers.
4. StorageUtil keys shared with other scripts: same value type wherever they are read or written, and every key read
   is written somewhere.
5. GetFormFromFile calls resolve to a record with that script in the plugins' Spriggit YAML, and every Auto property
   of the two scripts is filled there.

usage: py -3 check_affection.py --mo2 <MO2 instance folder> [--profile Default] [--verbose]
Exit code 1 on any failure.
"""
import argparse, glob, json, os, re, sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CODING = os.path.dirname(REPO)
AFF = os.path.join(REPO, 'SKSE', 'Plugins', 'StorageUtilData', 'MantellaAdultExpansion', 'affection.json')
ACTION = os.path.join(REPO, 'SKSE', 'Plugins', 'MantellaSoftware', 'data', 'actions', 'mantella_mlw_affection.json')
OURS = [os.path.join(REPO, 'Source', 'Scripts', n) for n in ('MAE_Affection.psc', 'MAE_Ask.psc', 'MAE_Npc.psc')]
ALLOWED = {'kissing', 'kissingneck', 'kissinghand', 'holdinghand', 'holdinghands', 'holdingbody', 'holdinghip', 'holdingchin',
           'holdinghead', 'holdingarm', 'hug', 'hugging', 'cuddling', 'pattinghead', 'strokinghead', 'dancing', 'spectating',
           'audiblebreathing'}
BAD = re.compile(r'tied|bound|bdsm|choke|chok|sleep|drunk|child|young|teen|loli|underage|rape|force|aggress|slave|sex|nude|naked|grop|undress', re.I)
fails = []


def fail(msg):
    fails.append(msg)
    print('  FAIL ' + msg)


def load_json(path):
    raw = open(path, encoding='utf-8-sig', errors='replace').read()
    try:
        return json.loads(raw)
    except ValueError:   # some packs ship comments or trailing commas, which OStim's reader accepts
        return json.loads(re.sub(r',(\s*[}\]])', r'\1', re.sub(r'//[^\n]*', '', raw)))


def read(path):
    return open(path, encoding='utf-8', errors='replace').read()


# ---------------------------------------------------------------------------
# 1. scenes
# ---------------------------------------------------------------------------

def check_scenes(mo2, profile, verbose):
    print(f'== scenes in affection.json against the winning files in profile {profile}')
    mods = os.path.join(mo2, 'mods')
    order = [l[1:].strip() for l in open(os.path.join(mo2, 'profiles', profile, 'modlist.txt'), encoding='utf-8') if l[:1] == '+']
    sources = [os.path.join(mo2, 'overwrite')] + [os.path.join(mods, m) for m in order] + [os.path.join(mo2, 'Stock Game', 'Data')]
    files, tags = {}, {}
    for src in sources:                                  # highest priority first
        for p in glob.glob(os.path.join(glob.escape(src), 'SKSE', 'Plugins', 'OStim', 'scenes', '**', '*.json'), recursive=True):
            files.setdefault(os.path.basename(p)[:-5].lower(), []).append((src, p))
        for p in glob.glob(os.path.join(glob.escape(src), 'SKSE', 'Plugins', 'OStim', 'actions', '*.json')):
            a = load_json(p)
            for name in [os.path.basename(p)[:-5]] + a.get('aliases', []):
                tags.setdefault(name.lower(), set()).update(a.get('tags', []))
    wl = load_json(AFF)
    n = 0
    for kind in wl['stringList']['kinds']:
        who = wl['string'].get('who_' + kind, '')
        furn = wl['string'].get('furniture_' + kind, '')
        for suffix in ('', '_mf', '_ff', '_mm'):
            for sid in wl['stringList'].get(kind + suffix, []):
                n += 1
                hits = files.get(sid.lower())
                if not hits:
                    fail(f'{kind}{suffix} {sid}: no scene file in any enabled mod'); continue
                src, win = hits[0]
                s = load_json(win)
                actors = s.get('actors', [])
                sexes = ''.join((a.get('intendedSex') or 'any')[0] for a in actors)
                acts = s.get('actions', [])
                types = [str(a.get('type')).lower() for a in acts]
                problems = []
                if len(actors) != 2: problems.append(f'{len(actors)} actors')
                if suffix == '' and sexes != 'aa': problems.append(f'any-pair list but sexes {sexes}')
                if suffix and sexes not in (suffix[1:], 'aa'): problems.append(f'{suffix} list but sexes {sexes}')
                if set(types) - ALLOWED: problems.append(f'actions {sorted(set(types) - ALLOWED)}')
                if any('sexual' in tags.get(t, ()) for t in types): problems.append('sexual action')
                if s.get('destination'): problems.append('transition to ' + s['destination'])
                if s.get('autoTransitions'): problems.append(f"autoTransitions {s['autoTransitions']}")
                if (s.get('furniture') or '') != furn: problems.append(f"furniture {s.get('furniture')} (kind wants {furn or 'none'})")
                bad = BAD.findall(json.dumps({k: s.get(k) for k in ('name', 'tags')}) + json.dumps([a.get('tags') for a in actors]))
                if bad: problems.append(f'words {bad}')
                doer = ''
                if who:
                    act = next((a for a in acts if str(a.get('type')).lower() in who.split(',')), None)
                    if act is None:
                        problems.append(f'no {who} action to tell who does it')
                    else:
                        pos = act.get('actor', 0)
                        if not isinstance(pos, int) or not 0 <= pos < len(actors):
                            problems.append(f'{who} action actor {pos} is not one of the two')
                        else:
                            doer = f' doer=actor{pos}({sexes[pos]})'
                for sp in s.get('speeds', []):
                    an = sp.get('animation')
                    pat = os.path.join('meshes', '**', glob.escape(an) + '_0.hkx')
                    if not glob.glob(os.path.join(glob.escape(src), pat), recursive=True) and \
                            not any(glob.glob(os.path.join(glob.escape(o), pat), recursive=True) for o in sources):
                        problems.append(f'no {an}_0.hkx in any enabled mod')
                mod = os.path.basename(src)
                if problems:
                    fail(f"{kind}{suffix} {sid} ({mod}): {'; '.join(problems)}")
                elif verbose:
                    print(f"  ok   {kind}{suffix:3} {sid:42} {mod[:34]:34} {sexes} {','.join(types)}{doer}")
    print(f'  {n} scenes checked')


# ---------------------------------------------------------------------------
# 2. the action file
# ---------------------------------------------------------------------------

def check_action():
    print('== the Mantella action file against affection.json')
    wl, act = load_json(AFF), load_json(ACTION)
    kinds = wl['stringList']['kinds']
    enum = act['parameters']['kind']['enum']
    if enum != kinds:
        fail(f'action kind enum {enum} != affection.json kinds {kinds}')
    desc = act['parameters']['kind']['description'] + ' ' + act['description']
    for k in kinds:
        if not re.search(r'\b' + re.escape(k) + r'\b', desc):
            fail(f'kind {k} not named in the action description')
    who_kinds = [k for k in kinds if wl['string'].get('who_' + k)]
    named = re.findall(r'\b(' + '|'.join(map(re.escape, kinds)) + r')\b', act['parameters']['who']['description'])
    if sorted(set(named)) != sorted(who_kinds):
        fail(f'who description names {sorted(set(named))}, the kinds with who_ are {sorted(who_kinds)}')
    if act['parameters']['who']['enum'] != ['npc', 'player']:
        fail(f"who enum {act['parameters']['who']['enum']} (the script reads only 'player', anything else is the NPC)")
    for k in kinds:
        if wl['string'].get('furniture_' + k) == 'chair' and not re.search(re.escape(k) + r' \([^)]*chair', act['description']):
            fail(f'{k} needs a chair but the description does not say so')
        for key in ('name_', 'line_', 'end_'):
            if not wl['string'].get(key + k):
                fail(f'{key}{k} missing in affection.json')
        if k not in wl['float']:
            fail(f'no seconds for {k} in affection.json')
        if not any(wl['stringList'].get(k + s) for s in ('', '_mf', '_ff', '_mm')):
            fail(f'kind {k} has no scene list')
    for k in wl['stringList'].get('intimate_kinds', []):
        if k not in kinds:
            fail(f'intimate_kinds names {k}, which is no listed kind')
    for key in wl['stringList']:
        base = re.sub(r'_(mf|ff|mm)$', '', key)
        if key not in ('kinds', 'intimate_kinds') and base not in kinds:
            fail(f'scene list {key} belongs to no listed kind')
    for key in wl['string']:
        m = re.match(r'(who|furniture|name|line|end)_(.*)$', key)
        if not m or m.group(2) not in kinds:
            fail(f'string {key} belongs to no listed kind')
    for key in ('kind', 'who'):
        if '{' + key + '}' in act['prompt']:
            fail(f'prompt has an unfilled {{{key}}}')
    if act.get('identifier') != 'mantella_mlw_affection':
        fail(f"identifier {act.get('identifier')}")
    src = read(OURS[0])
    if '"' + act['identifier'] + '"' not in src:
        fail('MAE_Affection does not register for the action identifier')
    gate = act.get('lw_gate', '')
    if 'affection=1' in gate and not re.search(r'JsonUtil\.SetIntValue\(\w+, "affection"', src):
        fail('lw_gate reads affection but MAE_Affection does not write it')
    print(f'  {len(kinds)} kinds, who kinds {who_kinds}')


# ---------------------------------------------------------------------------
# 3. handlers and 4. StorageUtil keys
# ---------------------------------------------------------------------------

PUSH = {'PushForm': 'form', 'PushString': 'string', 'PushFloat': 'float', 'PushInt': 'int', 'PushBool': 'bool'}
STANDARD = ['string', 'string', 'float', 'form']     # SendModEvent and OStim's events


def norm(t):
    t = t.lower()
    return t if t in ('string', 'float', 'int', 'bool') else 'form'


def strip_comments(src):
    out = []
    for line in src.split('\n'):
        q = False
        for i, ch in enumerate(line):
            if ch == '"':
                q = not q
            elif ch == ';' and not q:
                line = line[:i]; break
        out.append(line)
    return re.sub(r'\{[^}]*\}', '', '\n'.join(out))


def constants(src):
    """string properties and one-line global functions returning a literal, by name."""
    c = {m.group(1): m.group(2) for m in re.finditer(r'string\s+Property\s+(\w+)\s*=\s*"([^"]*)"', src, re.I)}
    for m in re.finditer(r'string\s+Function\s+(\w+)\(\)\s*Global\s*\n\s*Return\s+"([^"]*)"', src, re.I):
        c[m.group(1) + '()'] = m.group(2)
    return c


def resolve(expr, consts):
    expr = expr.strip()
    m = re.match(r'^"([^"]*)"(\s*\+.*)?$', expr)
    if m:
        return m.group(1) + ('*' if m.group(2) else '')
    m = re.match(r'^(?:\w+\.)?(\w+\(\))$', expr)
    if m and m.group(1) in consts:
        return consts[m.group(1)]
    if expr in consts:
        return consts[expr]
    return None


def senders(src, consts):
    """event name -> list of pushed type lists, from ModEvent.Create ... Send blocks."""
    out = {}
    for m in re.finditer(r'(\w+)\s*=\s*ModEvent\.Create\(([^)\n]*)\)', src):
        var, name = m.group(1), resolve(m.group(2), consts)
        if name is None:
            continue
        rest = src[m.end():]
        end = re.search(r'ModEvent\.Send\(\s*' + var + r'\s*\)', rest)
        block = rest[:end.start()] if end else ''
        pushes = [PUSH[p] for p in re.findall(r'ModEvent\.(Push\w+)\(\s*' + var + r'\b', block) if p in PUSH]
        out.setdefault(name, []).append(pushes)
    for m in re.finditer(r'\.SendModEvent\(\s*"([^"]+)"', src):
        out.setdefault(m.group(1), []).append(STANDARD)
    return out


def handlers(src):
    """handler name -> parameter types."""
    out = {}
    for m in re.finditer(r'^\s*Event\s+(\w+)\(([^)]*)\)', src, re.M | re.I):
        params = [p.split()[0] for p in m.group(2).split(',') if p.strip()]
        out[m.group(1).lower()] = [norm(p) for p in params]
    return out


def registrations(src, consts):
    out = []
    for m in re.finditer(r'RegisterForModEvent\(([^,]+),\s*"(\w+)"\)', src):
        name = m.group(1).strip()
        parts = [resolve(p, consts) for p in name.split('+')]
        if None in parts:
            parts = [p if p is not None else '' for p in parts]
        out.append((''.join(p.rstrip('*') for p in parts), m.group(2)))
    return out


def all_sources(mo2, profile):
    order = [l[1:].strip() for l in open(os.path.join(mo2, 'profiles', profile, 'modlist.txt'), encoding='utf-8') if l[:1] == '+']
    mantella = None
    for m in order:                                      # top of the list wins
        p = os.path.join(mo2, 'mods', m, 'Scripts', 'Source', 'MantellaConversation.psc')
        if os.path.exists(p):
            mantella = p; break
    iface = None
    for m in order:
        p = os.path.join(mo2, 'mods', m, 'Scripts', 'Source', 'MantellaInterface.psc')
        if os.path.exists(p):
            iface = p; break
    modules = [p for p in glob.glob(os.path.join(CODING, 'Mantella-Living-World-*', 'Source', 'Scripts', '*.psc'))]
    return mantella, iface, modules


def check_events(mo2, profile):
    print('== mod event handlers against their senders')
    mantella, iface, modules = all_sources(mo2, profile)
    consts = {}
    for p in modules + [x for x in (iface,) if x]:
        consts.update(constants(strip_comments(read(p))))
    if iface:   # Mantella's names are auto properties with values
        for m in re.finditer(r'string\s+property\s+(\w+)\s*=\s*"([^"]*)"', read(iface), re.I):
            consts['EventInterface.' + m.group(1)] = m.group(2); consts[m.group(1)] = m.group(2)
    sent = {}
    for p in modules + [x for x in (mantella,) if x]:
        src = strip_comments(read(p))
        src = re.sub(r'EventInterface\.(\w+)', lambda m: '"' + consts.get(m.group(1), m.group(0)) + '"', src)
        for k, v in senders(src, consts).items():
            sent.setdefault(k, []).extend((os.path.basename(p), t) for t in v)
    prefix = consts.get('EVENT_ADVANCED_ACTIONS_PREFIX', 'MantellaConversation_Advanced_Action_')
    if mantella:
        msrc = strip_comments(read(mantella))
        if re.search(r'eventName\s*=\s*EventInterface\.EVENT_ADVANCED_ACTIONS_PREFIX\s*\+', msrc):
            blk = re.search(r'string eventName = EventInterface\.EVENT_ADVANCED_ACTIONS_PREFIX \+ actionIdentifier.*?ModEvent\.Send', msrc, re.S)
            pushes = [PUSH[p] for p in re.findall(r'ModEvent\.(Push\w+)\(', blk.group(0))] if blk else None
            if pushes:
                sent.setdefault(prefix + '*', []).append((os.path.basename(mantella), pushes))
    print(f'  Mantella source: {mantella}')
    for path in OURS:
        src = strip_comments(read(path))
        c = dict(consts); c.update(constants(src))
        hs = handlers(src)
        for name, handler in registrations(src, c):
            got = hs.get(handler.lower())
            label = f'{os.path.basename(path)}: {name} -> {handler}'
            if got is None:
                fail(f'{label}: no Event {handler} in the script'); continue
            if name.startswith('ostim_'):
                want = [(('OStim', STANDARD))]
            elif name.startswith(prefix):
                want = sent.get(prefix + '*', [])
            else:
                want = sent.get(name, [])
            if not want:
                fail(f'{label}: nothing sends this event'); continue
            for who, pushes in want:
                if pushes != got:
                    fail(f'{label}{tuple(got)}: {who} pushes {tuple(pushes)}')
            print(f'  ok   {label}({", ".join(got)}) <- {len(want)} sender(s)')
    # Our own MLW_ScoreEvent against its receivers.
    ours = senders(strip_comments(read(OURS[0])), constants(read(OURS[0]))).get('MLW_ScoreEvent', [])
    receivers = 0
    for p in modules:
        src = strip_comments(read(p))
        for name, handler in registrations(src, constants(src)):
            if name == 'MLW_ScoreEvent':
                receivers += 1
                got = handlers(src).get(handler.lower())
                for pushes in ours:
                    if pushes != got:
                        fail(f'MLW_ScoreEvent: MAE_Affection pushes {pushes}, {os.path.basename(p)}.{handler} takes {got}')
                kinds = re.findall(r'asKind\s*!=\s*"(\w+)"', src)
                if kinds and 'physical' not in kinds:
                    fail(f'MLW_ScoreEvent: {os.path.basename(p)} drops the kind "physical"')
                print(f'  ok   MLW_ScoreEvent -> {os.path.basename(p)}.{handler}({", ".join(got or [])})')
    if ours and not receivers:
        fail('MLW_ScoreEvent: nothing receives it')


def check_storageutil():
    print('== StorageUtil keys shared with other scripts')
    modules = glob.glob(os.path.join(CODING, 'Mantella-Living-World-*', 'Source', 'Scripts', '*.psc'))
    consts = {}
    for p in modules:
        consts.update(constants(strip_comments(read(p))))
    use = {}     # key -> [(script, op, type)]
    for p in modules:
        src = strip_comments(read(p))
        c = dict(consts); c.update(constants(src))
        for m in re.finditer(r'StorageUtil\.(Set|Get|Adjust|Unset|Has|Pluck)(Float|Int|String|Form)Value\(\s*[^,]+,\s*("[^"]*"|[\w.]+(?:\(\))?)', src):
            key = resolve(m.group(3), c)
            if key is None:
                continue
            use.setdefault(key, []).append((os.path.basename(p), m.group(1), m.group(2)))
    ours = {os.path.basename(p) for p in OURS} | {'MAE_Text.psc'}
    n = 0
    for key, uses in sorted(use.items()):
        if not any(u[0] in ours for u in uses):
            continue
        n += 1
        types = {u[2] for u in uses}
        if len(types) > 1:
            fail(f'{key}: used as {sorted(types)} in {sorted({u[0] for u in uses})}')
        reads = [u for u in uses if u[1] in ('Get', 'Has', 'Pluck', 'Adjust')]
        writes = [u for u in uses if u[1] in ('Set', 'Adjust')]
        if reads and not writes:
            fail(f'{key}: read in {sorted({u[0] for u in reads})} but never written')
        print(f'  ok   {key:28} {"/".join(sorted(types)):6} ' + ', '.join(sorted({f"{u[0]} {u[1]}" for u in uses})))
    print(f'  {n} keys')


# ---------------------------------------------------------------------------
# 5. forms and properties
# ---------------------------------------------------------------------------

def check_forms():
    print('== GetFormFromFile targets and filled properties')
    yamls = glob.glob(os.path.join(CODING, 'Mantella-Living-World-*', 'esp', '**', '*.yaml'), recursive=True)
    records = {}
    for y in yamls:
        txt = read(y)
        m = re.search(r'^FormKey:\s*(\w+):(.+)$', txt, re.M)
        if m:
            records[(m.group(1).upper(), m.group(2).strip())] = txt
    for path in OURS:
        src = strip_comments(read(path))
        for m in re.finditer(r'GetFormFromFile\(0x([0-9A-Fa-f]+),\s*(\w+|"[^"]+")\)\s*as\s+(\w+)', src):
            fid = m.group(1).upper().rjust(6, '0')[-6:]
            esp = m.group(2).strip('"')
            if not esp.endswith(('.esp', '.esm', '.esl')):
                esp = constants(src).get(esp, esp)
            rec = records.get((fid, esp))
            label = f'{os.path.basename(path)}: 0x{fid} in {esp} as {m.group(3)}'
            if rec is None:
                fail(f'{label}: no such record in any module YAML')
            elif m.group(3) not in ('GlobalVariable', 'Quest') and f'Name: {m.group(3)}' not in rec:
                fail(f'{label}: the record has no script {m.group(3)}')
            else:
                print(f'  ok   {label}')
        script = os.path.basename(path)[:-4]
        props = re.findall(r'^\s*\w+\s+Property\s+(\w+)\s+Auto\s*$', src, re.M)
        rec = next((t for t in records.values() if re.search(r'^\s*- Name: ' + script + r'\s*$', t, re.M)), None)
        if rec is None:
            fail(f'{script}: no quest YAML carries the script'); continue
        for pr in props:
            if not re.search(r'Name: ' + pr + r'\s*\n\s*Object: ', rec):
                fail(f'{script}: property {pr} is not filled in the plugin')
        print(f'  ok   {script}: properties {", ".join(props)} filled')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--mo2', required=True, help='MO2 instance folder')
    ap.add_argument('--profile', default='Default')
    ap.add_argument('--verbose', action='store_true')
    a = ap.parse_args()
    check_scenes(a.mo2, a.profile, a.verbose)
    check_action()
    check_events(a.mo2, a.profile)
    check_storageutil()
    check_forms()
    print(f'\n{len(fails)} failures')
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
