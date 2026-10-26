"""Builds the scene-flow catalogue for Mantella Living World - OStim Expansion from the OStim packs enabled in an MO2 profile.

Each pack is split into sets (one position with numbered stages, ordered by the pack's own navigation), and every
set is written as an OStim sequence. The game then chains sets live, one roll at a time (MAE_Flows), so this tool
only describes the building blocks: each set's pose, intensity, furniture and theme, the sets grouped by pack, how
often each pose naturally leads to each other pose across all packs, and every scene's pose. The catalogue is JSON
read through PapyrusUtil JsonUtil (lowercase keys).

usage: py -3 flowgen.py --mo2 "D:/Modlists/NGVO" --profile Default --out "<mod folder>"
"""
import argparse, collections, json, os, re, sys

CLIMAX_ACTIONS = {'facial', 'cumonbelly', 'cumonbutt', 'cumonchest', 'cumonvulva', 'cumshot', 'ejaculation', 'creampie',
                  'analcreampie', 'cuminmouth', 'cumonface', 'cumonfeet', 'cumonback', 'cumonbreasts'}
PENETRATION = {'vaginalsex', 'analsex'}
ORAL = {'blowjob', 'cunnilingus', 'deepthroat', 'lickingvagina', 'lickingpenis', 'anallicking', 'lickingnipples', 'rimjob'}
MANUAL = {'handjob', 'vaginalfingering', 'analfingering', 'boobjob', 'footjob', 'rubbingclitoris', 'thighjob', 'buttjob'}
SOFT = {'kissing', 'hugging', 'hug', 'cuddling', 'gropingbreast', 'gropingbutt', 'holdinghand', 'kissingcheek', 'kissingneck'}
RANK = {'foreplay': 0, 'manual': 1, 'oral': 1, 'sex': 2, 'finish': 3}
STANDARD_POSES = ['sixtynine', 'facesitting', 'spitroast', 'reversecowgirl', 'cowgirl', 'doggystyle', 'missionary', 'prone']
POSES = ['standing face to face', 'standing from behind', 'carry', 'kneeling', 'sitting / lap', 'missionary', 'lying on back',
         'spooning', 'sixtynine', 'prone', 'doggystyle', 'cowgirl', 'reversecowgirl', 'facesitting']
FURNITURE_WORDS = ['table', 'bed', 'chair', 'bench', 'wall', 'shelf', 'throne', 'stool', 'counter', 'cookingpot', 'alchemy', 'enchant', 'smithing']
# Sets with these words in their name never go into flows (props, restraints, creatures, test scenes).
EXCLUDE_WORDS = ['test', 'tied', 'choke', 'riekling', 'creature', 'rune', 'spear', 'levitation', 'armbinder', 'cuffed', 'wheel',
                 'gloryhole', 'glory hole', 'stuck', 'stocks', 'pillory', 'drunk', 'sleeping', 'unconscious',
                 'hypnosis', 'hypnotiz', 'mind control', 'slave', 'thrall', 'enthrall',
                 # after-the-climax idles would play mid-scene
                 'post-climax', 'postclimax', 'post climax',
                 # never: anything framed around minors
                 'shota', 'loli', 'child', 'kid', 'teen', 'underage', 'young']
SEQ_PREFIX = 'MAEF'


def load_json(path):
    text = open(path, encoding='utf-8-sig', errors='replace').read()
    try:
        return json.loads(text)
    except ValueError:
        text = re.sub(r'(?m)(^|[^:"])//.*$', r'\1', text)
        text = re.sub(r',(\s*[\]}])', r'\1', text)
        return json.loads(text)


def enabled_mods(mo2, profile):
    lines = open(os.path.join(mo2, 'profiles', profile, 'modlist.txt'), encoding='utf-8').read().splitlines()
    return [l[1:].strip() for l in lines if l.startswith('+')]  # highest priority first


def read_scenes(mo2, mods, skip_mod):
    scenes, owner = {}, {}
    for mod in reversed(mods):  # lowest priority first, so winners overwrite
        if mod == skip_mod:
            continue
        folder = os.path.join(mo2, 'mods', mod, 'SKSE', 'Plugins', 'OStim', 'scenes')
        if not os.path.isdir(folder):
            continue
        for root, _, files in os.walk(folder):
            for f in files:
                if f.lower().endswith('.json'):
                    sid = f[:-5].lower()
                    try:
                        scenes[sid] = (f[:-5], load_json(os.path.join(root, f)))
                        owner[sid] = mod
                    except ValueError:
                        pass
    return scenes, owner


class Library:
    def __init__(self, scenes, owner):
        self.raw, self.owner = scenes, owner
        self.data = {sid: j for sid, (_, j) in scenes.items()}
        self.real_id = {sid: rid for sid, (rid, _) in scenes.items()}
        # sorted list: set iteration order changes per run and would make builds differ
        self.mf = sorted(sid for sid, j in self.data.items() if self.is_mf(j) and not self.is_transition(j))
        self.mf_set = set(self.mf)

    @staticmethod
    def is_transition(j):
        return bool(j.get('transition')) or 'transition' in [str(t).lower() for t in (j.get('tags') or [])]

    @staticmethod
    def is_mf(j):
        actors = j.get('actors') or []
        if len(actors) != 2:
            return False
        sexes = sorted(str(a.get('intendedSex', '')).lower() for a in actors)
        return sexes in (['female', 'male'], ['', 'female'], ['', 'male'], ['', ''])

    def actions(self, sid):
        return {str(a.get('type', '')).lower() for a in (self.data[sid].get('actions') or [])}

    def activity(self, sid):
        a = self.actions(sid)
        if a & CLIMAX_ACTIONS: return 'finish'
        if a & PENETRATION: return 'sex'
        if a & ORAL: return 'oral'
        if a & MANUAL: return 'manual'
        if a & SOFT: return 'foreplay'
        return 'idle'

    def pose(self, sid):
        j = self.data[sid]
        tags = [str(t).lower() for t in (j.get('tags') or [])]
        for s in STANDARD_POSES:
            if s in tags and s in POSES: return s
        if 'doggy' in tags: return 'doggystyle'
        actors = j.get('actors') or []
        fem = next((a for a in actors if str(a.get('intendedSex', '')).lower() == 'female'), actors[1] if len(actors) > 1 else {})
        f = {str(t).lower() for t in (fem.get('tags') or [])}
        if 'suspended' in f or 'carry' in tags: return 'carry'
        if 'allfours' in f: return 'doggystyle'
        if 'standing' in f: return 'standing from behind' if {'facingaway', 'bendover'} & f else 'standing face to face'
        if 'kneeling' in f or 'squatting' in f: return 'kneeling'
        if 'lyingback' in f: return 'missionary' if self.activity(sid) == 'sex' else 'lying on back'
        if 'lyingfront' in f: return 'prone'
        if 'lyingside' in f: return 'spooning'
        if 'ontop' in f: return 'cowgirl'
        if 'sitting' in f: return 'sitting / lap'
        return None

    def theme(self, sid):
        """Flows never mix themes: actor size variant, femdom, futa, and mood (romantic / dom / neutral)."""
        j = self.data[sid]
        tags = {str(t).lower() for t in (j.get('tags') or [])}
        text = (str(j.get('name', '')) + ' ' + sid).lower()
        bigguy = 'bigguy' in tags or re.search(r'big ?guy|basescale', text) is not None
        mood = 'romantic' if 'romantic' in tags else ('dom' if 'dom' in tags or 'aggressive' in tags else 'neutral')
        return ('bigguy' if bigguy else 'normal', 'femdom' in tags or 'femdom' in text, 'futa' in tags or 'futa' in text, mood)

    def excluded(self, sid):
        text = (str(self.data[sid].get('name', '')) + ' ' + sid).lower()
        return any(w in text for w in EXCLUDE_WORDS)

    def furniture(self, sid):
        j = self.data[sid]
        f = str(j.get('furniture', '') or '').lower()
        if not f:
            text = (str(j.get('name', '')) + ' ' + sid).lower()
            f = next((w for w in FURNITURE_WORDS if w in text), 'none')
        return furniture_family(f)

    def resolve(self, sid, depth=0):
        j = self.data.get(sid)
        if j is None or depth > 6: return None
        if self.is_transition(j):
            dst = str((j.get('transition') or {}).get('destination', '')).lower()
            if not dst:
                navs = j.get('navigations') or []
                dst = str(navs[0].get('destination', '')).lower() if navs else ''
            return self.resolve(dst, depth + 1) if dst else None
        return sid

    def forward(self, sid, same_pack=True):
        out = []
        for n in (self.data[sid].get('navigations') or []):
            if (n.get('priority') or 0) < 0 or str(n.get('description', '')).lower().startswith('return'):
                continue
            d = self.resolve(str(n.get('destination', '')).lower())
            if d and d in self.mf_set and d != sid and (not same_pack or self.owner[d] == self.owner[sid]):
                out.append(d)
        return out


def natural_moves(lib):
    """pose -> Counter(next pose) from forward links between non-idle scenes of different poses, all packs."""
    moves = collections.defaultdict(collections.Counter)
    for sid in lib.mf:
        a, pa = lib.activity(sid), lib.pose(sid)
        if a == 'idle' or not pa: continue
        for d in lib.forward(sid, same_pack=False):
            pd = lib.pose(d)
            if lib.activity(d) != 'idle' and pd and pd != pa:
                moves[pa][pd] += 1
    return moves


def build_sets(lib, pack):
    members = [s for s in lib.mf if lib.owner[s] == pack and lib.activity(s) != 'idle' and lib.pose(s)]
    adj = collections.defaultdict(set)
    for s in members:
        for d in lib.forward(s):
            if d in adj or d in members:
                adj[s].add(d); adj[d].add(s)
    seen, sets = set(), []
    for s in sorted(members):
        if s in seen: continue
        group, stack = [], [s]
        seen.add(s)
        while stack:
            x = stack.pop(); group.append(x)
            for y in adj[x]:
                if y not in seen and y in members:
                    seen.add(y); stack.append(y)
        incoming = collections.Counter(d for m in group for d in lib.forward(m) if d in group)
        start = min(group, key=lambda m: (incoming[m], m))
        order, used = [start], {start}
        while True:
            nxt = [d for d in lib.forward(order[-1]) if d in group and d not in used]
            if not nxt: break
            order.append(nxt[0]); used.add(nxt[0])
        acts = collections.Counter(lib.activity(m) for m in order)
        finish = acts['finish'] > 0
        act = 'finish' if finish else max((a for a in acts if a != 'finish'), key=lambda a: (RANK[a], acts[a]))
        name = str(lib.data[order[0]].get('name') or lib.real_id[order[0]])
        sets.append({'pack': pack, 'pose': collections.Counter(lib.pose(m) for m in order).most_common(1)[0][0],
                     'act': act, 'rank': RANK[act], 'furniture': collections.Counter(lib.furniture(m) for m in order).most_common(1)[0][0],
                     'theme': collections.Counter(lib.theme(m) for m in order).most_common(1)[0][0],
                     'excluded': any(lib.excluded(m) for m in order),
                     'label': nice_label(name), 'stages': [lib.real_id[m] for m in order]})
    return sets


def sequence(stage_ids, seconds):
    return {'scenes': [{'id': sid, 'duration': seconds} for sid in stage_ids], 'tags': ['mrbflow']}


def furniture_family(f):
    """OStim furniture type id -> the family flows match on. MRB_Flows.FurnitureFamily does the same in game."""
    f = f.lower()
    if 'bed' in f: return 'bed'
    if 'alchemy' in f: return 'alchemytable'
    if 'enchant' in f: return 'enchantingtable'
    if 'table' in f or 'counter' in f: return 'table'
    if 'wardrobe' in f: return 'wardrobe'
    return f or 'none'


def nice_label(name):
    """A readable set name: drops trailing numbers; OStim's own translation keys keep who is in the scene:
    $OStim2PCowgirlMF -> "OStim: Cowgirl (MF)", $OStim3PLyingMFF -> "OStim: Lying (MFF)"."""
    label = re.sub(r'\s*\d+$', '', name).strip()
    m = re.fullmatch(r'\$OStim(\w+?)([MF]{2,})?', label)
    if m:
        words = re.sub(r'\d+P?', ' ', m.group(1))        # actor-count markers: 2P, 3P, a bare 2
        label = 'OStim: ' + ' '.join(re.sub(r'(?<=[a-z])(?=[A-Z])', ' ', words).split())
        if m.group(2):
            label += f' ({m.group(2)})'
    return label


def theme_key(theme):
    size, femdom, futa, mood = theme
    return '|'.join([size, 'femdom' if femdom else '-', 'futa' if futa else '-', mood])


def short_pack(pack):
    p = re.sub(r'^\[NoDelete\]\s*', '', pack)
    return re.sub(r"\s+(for|For)\s+O[Ss]tim.*$", '', p).strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--mo2', required=True)
    ap.add_argument('--profile', default='Default')
    ap.add_argument('--out', required=True, help='mod folder to write into (sequences + catalogue)')
    ap.add_argument('--seconds', type=float, default=25.0, help='seconds per stage')
    args = ap.parse_args()

    out_mod = os.path.basename(os.path.normpath(args.out))
    mods = enabled_mods(args.mo2, args.profile)
    lib = Library(*read_scenes(args.mo2, mods, skip_mod=out_mod))
    moves = natural_moves(lib)
    packs = sorted({lib.owner[s] for s in lib.mf})

    seq_dir = os.path.join(args.out, 'SKSE', 'Plugins', 'OStim', 'sequences')
    cat_dir = os.path.join(args.out, 'SKSE', 'Plugins', 'StorageUtilData', 'MantellaAdultExpansion')
    os.makedirs(seq_dir, exist_ok=True); os.makedirs(cat_dir, exist_ok=True)
    for f in os.listdir(seq_dir):  # previous build
        if f.startswith(SEQ_PREFIX) and f.endswith('.json'): os.remove(os.path.join(seq_dir, f))

    all_sets, pack_names, pack_start, pack_count = [], [], [], []
    for pack in packs:
        sets = [s for s in build_sets(lib, pack) if not s['excluded']]  # never offered at all
        if not sets: continue
        pack_names.append(short_pack(pack)); pack_start.append(len(all_sets)); pack_count.append(len(sets))
        for s in sets:
            s['seq'] = f'{SEQ_PREFIX}_S{len(all_sets) + 1}'
            s['packIndex'] = len(pack_names) - 1
            all_sets.append(s)
    for s in all_sets:
        json.dump(sequence(s['stages'], args.seconds), open(os.path.join(seq_dir, s['seq'] + '.json'), 'w', encoding='utf-8'), indent=1)

    posed = [sid for sid in lib.mf if lib.pose(sid) and lib.activity(sid) != 'idle' and not lib.excluded(sid)]
    # moveWeight[a * len(POSES) + b] = forward links from pose a to pose b across all packs
    weights = [moves.get(a, {}).get(b, 0) for a in POSES for b in POSES]
    cat = {
        'int': {'version': 2, 'setCount': len(all_sets), 'packCount': len(pack_names), 'poseCount': len(POSES), 'stageSeconds': int(args.seconds)},
        'stringList': {
            'poses': POSES,
            'packName': pack_names,
            'setSeq': [s['seq'] for s in all_sets],
            'setLabel': [s['label'] for s in all_sets],
            'setFurniture': [s['furniture'] for s in all_sets],
            'setTheme': [theme_key(s['theme']) for s in all_sets],
            'setStages': [','.join(st.lower() for st in s['stages']) for s in all_sets],
            'sceneId': posed,
        },
        'intList': {
            'packStart': pack_start,
            'packSetCount': pack_count,
            'setPack': [s['packIndex'] for s in all_sets],
            'setPose': [POSES.index(s['pose']) for s in all_sets],
            'setRank': [s['rank'] for s in all_sets],
            'setStageCount': [len(s['stages']) for s in all_sets],
            # 1 when the pack has another set to move on to from this one (same furniture and theme, rank from this
            # one's up to sex): openers prefer these, so a scene doesn't open on a dead end
            'setCanGo': [int(any(j != k and t['packIndex'] == s['packIndex'] and t['furniture'] == s['furniture']
                                 and t['theme'] == s['theme'] and s['rank'] <= t['rank'] < 3 for j, t in enumerate(all_sets)))
                         for k, s in enumerate(all_sets)],
            'moveWeight': weights,
            'scenePose': [POSES.index(lib.pose(sid)) for sid in posed],
            # every finish set, for borrowing one when the scene's own pack has none
            'finishSets': [i for i, s in enumerate(all_sets) if s['rank'] == 3],
        },
    }
    # JsonUtil lowercases every key it looks up, so the file must use lowercase keys.
    cat = {section: {k.lower(): v for k, v in values.items()} for section, values in cat.items()}
    json.dump(cat, open(os.path.join(cat_dir, 'flows.json'), 'w', encoding='utf-8'), indent=1)

    with open(os.path.join(args.out, 'flows-report.txt'), 'w', encoding='utf-8') as r:
        r.write(f'{len(all_sets)} sets from {len(pack_names)} packs ({len(lib.mf)} two-person scenes)\n\n')
        for i, name in enumerate(pack_names):
            r.write(f'{name}: {pack_count[i]} sets\n')
            for s in all_sets[pack_start[i]:pack_start[i] + pack_count[i]]:
                r.write(f'    {s["seq"]}  {s["label"]}  ({s["pose"]}, {s["act"]}, {s["furniture"]}, {theme_key(s["theme"])}, {len(s["stages"])} stages)\n')
    print(f'Flows built: {len(all_sets)} sets from {len(pack_names)} packs -> {args.out}')


if __name__ == '__main__':
    sys.exit(main())
