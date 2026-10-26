"""Offline simulator of MAE_Flows' live dice. Same rules and weights as the Papyrus script, so it can show how
scenes come out over thousands of runs (variety, repeats, chain lengths) and check that no rule is ever broken.

usage: py -3 simulate.py <flows.json> [--scenes 5000] [--seed 1]
"""
import argparse, collections, json, random

# Keep in step with MAE_Flows.psc
CHAIN_SETS = 4            # sets per chain before holding for the finish
MAX_POSE_PER_CHAIN = 2    # any pose at most twice per chain
W_REPEAT = 3.0            # same pose again, different set
W_REPEAT_FAV = 3.0        # extra when that pose is a favourite
W_UNNATURAL = 0.5         # a pose the packs never move to from here
FAV_MULT = 3.0
RECENT_MULT = 0.5         # pose used in her last scene with the player
RANK_JUMP_MULT = 0.5      # skipping a whole intensity step
ALLOWED_THEMES = ('normal|-|-|neutral', 'normal|-|-|romantic')


class Catalogue:
    def __init__(self, path):
        c = json.load(open(path, encoding='utf-8'))
        s, i = c['stringList'], c['intList']
        self.poses = s['poses']
        self.n = c['int']['setcount']
        self.pack = i['setpack']; self.pose = i['setpose']; self.rank = i['setrank']; self.stages = i['setstagecount']
        self.cango = i.get('setcango', [1] * self.n)
        self.furn = s['setfurniture']; self.theme = s['settheme']; self.label = s['setlabel']
        self.packname = s['packname']
        p = len(self.poses)
        self.w = [i['moveweight'][a * p:(a + 1) * p] for a in range(p)]
        self.wmax = [max(row) or 1 for row in self.w]


def move_weight(cat, cur_pose, pose):
    w = cat.w[cur_pose][pose]
    return W_UNNATURAL if w == 0 else 1.0 + 9.0 * w / cat.wmax[cur_pose]


def opener(cat, furniture, favs, recent, rng):
    """A pack first (every pack with a fitting opener equally likely, so big packs don't crowd out the rest),
    then a soft opener inside it; sex openers only when no pack has a soft one. Openers the pack can move on from
    first; dead ends only when nothing else fits."""
    for need_go, max_rank in ((True, 1), (True, 2), (False, 1), (False, 2)):
        fits = [i for i in range(cat.n) if cat.rank[i] <= max_rank and cat.stages[i] >= 2 and cat.furn[i] == furniture and cat.theme[i] in ALLOWED_THEMES
                and (cat.cango[i] or not need_go)]
        if not fits: continue
        pack = rng.choice(sorted({cat.pack[i] for i in fits}))
        c = [i for i in fits if cat.pack[i] == pack]
        wts = [(FAV_MULT if cat.pose[i] in favs else 1.0) * (RECENT_MULT if cat.pose[i] in recent else 1.0) for i in c]
        return rng.choices(c, wts)[0]
    return None


def next_set(cat, cur, used, pose_count, favs, recent, rng, min_rank=None):
    lo = cat.rank[cur] if min_rank is None else min_rank
    c, wts = [], []
    for i in range(cat.n):
        if (cat.pack[i] != cat.pack[cur] or cat.rank[i] >= 3 or i in used or cat.rank[i] < lo
                or cat.furn[i] != cat.furn[cur] or cat.theme[i] != cat.theme[cur] or pose_count[cat.pose[i]] >= MAX_POSE_PER_CHAIN):
            continue
        if cat.pose[i] == cat.pose[cur]:
            w = W_REPEAT + (W_REPEAT_FAV if cat.pose[i] in favs else 0.0)
        else:
            w = move_weight(cat, cat.pose[cur], cat.pose[i])
            if cat.pose[i] in favs: w *= FAV_MULT
        if cat.pose[i] in recent: w *= RECENT_MULT
        if cat.rank[i] - cat.rank[cur] > 1: w *= RANK_JUMP_MULT
        c.append(i); wts.append(w)
    return rng.choices(c, wts)[0] if c else None


def scene(cat, furniture, favs, recent, chains, rng):
    first = opener(cat, furniture, favs, recent, rng)
    if first is None:
        return []
    used, out = {first}, []
    cur = first
    for chain in range(chains):
        pose_count = collections.Counter([cat.pose[cur]])
        seq = [cur]
        while len(seq) < CHAIN_SETS:
            nxt = next_set(cat, cur, used, pose_count, favs, recent, rng)
            if nxt is None: break
            used.add(nxt); pose_count[cat.pose[nxt]] += 1; seq.append(nxt); cur = nxt
        out.append(seq)
        # not satisfied after the climax: a new chain from the same pack, restarting at oral/manual intensity
        nxt = next_set(cat, cur, used, collections.Counter(), favs, recent, rng, min_rank=1)
        if nxt is None: break
        used.add(nxt); cur = nxt
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('catalogue'); ap.add_argument('--scenes', type=int, default=5000); ap.add_argument('--seed', type=int, default=1)
    a = ap.parse_args()
    cat = Catalogue(a.catalogue); rng = random.Random(a.seed)
    stats = collections.Counter(); lengths = collections.Counter(); packs = collections.Counter(); set_use = collections.Counter()
    broken = collections.Counter(); example = []
    for k in range(a.scenes):
        favs = set(rng.sample(range(len(cat.poses)), 2)); recent = set(rng.sample(range(len(cat.poses)), 3))
        chains = rng.choice([1, 1, 2, 3])
        out = scene(cat, rng.choice(['none'] * 8 + ['bed', 'chair', 'wall', 'table']), favs, recent, chains, rng)
        if not out:
            stats['no opener'] += 1; continue
        stats['scenes'] += 1
        for seq in out:
            lengths[len(seq)] += 1; packs[cat.packname[cat.pack[seq[0]]]] += 1
            pc = collections.Counter(cat.pose[i] for i in seq)
            if any(v > MAX_POSE_PER_CHAIN for v in pc.values()): broken['pose over cap'] += 1
            for x, y in zip(seq, seq[1:]):
                stats['steps'] += 1
                if cat.pose[x] == cat.pose[y]: stats['same pose twice in a row'] += 1
                if cat.rank[y] < cat.rank[x]: broken['intensity dropped'] += 1
                if cat.pack[y] != cat.pack[x]: broken['pack changed'] += 1
                if cat.furn[y] != cat.furn[x]: broken['furniture changed'] += 1
                if cat.theme[y] != cat.theme[x]: broken['theme changed'] += 1
                if cat.pose[y] in favs: stats['steps into a favourite'] += 1
            if len(set(pc)) < len(seq): stats['chains revisiting a pose'] += 1
            for i in seq: set_use[i] += 1
            stats['chains'] += 1
        if len(example) < 4:
            example.append([[f'{cat.label[i]} ({cat.poses[cat.pose[i]]})' for i in seq] for seq in out])
    print(f"scenes {stats['scenes']} (no opener for the furniture: {stats['no opener']}), chains {stats['chains']}")
    print('sets per chain:', dict(sorted(lengths.items())))
    st = stats['steps'] or 1
    print(f"same pose twice in a row: {100 * stats['same pose twice in a row'] / st:.1f}% of steps")
    print(f"chains revisiting a pose: {100 * stats['chains revisiting a pose'] / max(stats['chains'], 1):.1f}%")
    print(f"steps into one of her 2 favourite poses: {100 * stats['steps into a favourite'] / st:.1f}% (no-bias baseline ~{200 / len(cat.poses):.0f}%)")
    print(f'distinct sets used: {len(set_use)} of {cat.n}')
    print('chains per pack:', dict(packs.most_common()))
    print('RULE BREAKS:', dict(broken) if broken else 'none')
    for e in example:
        print('example scene:')
        for seq in e: print('   ', ' -> '.join(seq))


if __name__ == '__main__':
    main()
