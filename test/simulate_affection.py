"""Offline state-machine model of MAE_Affection.psc and MAE_Ask.psc, run under random interleavings.

Papyrus runs every event handler on its own thread. A thread keeps the script's lock only until it calls out:
every native, latent or other-script call is a point where any other thread may run. Here each handler is a
Python generator that yields at those points (comments give the .psc line), and a scheduler picks which thread
runs next, when queued events are delivered and when the world does something (Mantella actions, the box, OStim
events, the talk ending, combat, death, the chair, a save loaded mid-walk). Time only moves when every thread is
waiting, since a native call takes a frame and waits take seconds.

Invariants checked on every run:
  overlap     no scene start while another live scene holds one of its actors
  gap         no scene start within 5 s of the end of a scene with one of its actors
  talk        no affection start after the talk that asked for it ended
  stuck       a fresh affection request and a fresh sex request still work after everything settles,
              and no affection scene is left running with nothing to end it
  timer       the affection timer only stops the scene it was set for
  stop        nothing here stops a scene that isn't an affection scene
  score       MLW_ScoreEvent only after an affection scene with that NPC really played (and once)
  announce    nothing told to Mantella that didn't happen (lines, switch lines, end lines, "ready now")
  chair       no chair scene started on a chair someone else took
  none        no scene start with a missing actor
  fact        the fact left in the NPC file matches the kinds and closeness the save holds
  intimate    no intimate kind (the lap dance) starts, is switched to, or is named in the fact for an NPC who is not
              intimate with the player
  close       no kind but an open one (the couple dance) starts or is switched to with an NPC who is not close

Each fix in the scripts is a named switch here (FIXES). The directed scenarios are the minimal failing sequences,
written out: each must fail on the code before the fixes, fail with its own fix left out, and pass with all of them.
Random runs are shrunk to a minimal choice sequence. 'talk-latency' and 'gap-latency' are residual: an end event that
has not reached the script yet, which no Papyrus check can see; they are reported and don't fail the run.
'intimate-latency' and 'close-latency' are residual too: the player changed the NPC's standing after the request had
passed its check.

usage: py -3 simulate_affection.py [--runs 3000] [--seed 1] [--steps 160] [--original] [--without FIX] [--traces]
  --original   the code as it was before the fixes; --without FIX leaves one fix out
  --traces     prints each scenario's trace and the shrunk random failures
Exit code 1 when a scenario does not behave as above or a non-residual invariant fails.
"""
import argparse, random, sys

PLAYER, A, B, C = 'player', 'A', 'B', 'C'
KINDS = ['kiss', 'neck_kiss', 'lap_dance', 'dance']  # a plain kind, a who_ kind, a chair kind and an open kind
WHO_KINDS = {'neck_kiss', 'lap_dance'}
CHAIR_KINDS = {'lap_dance'}
INTIMATE_KINDS = {'lap_dance'}                       # affection.json "intimate_kinds"
OPEN_KINDS = {'dance'}                               # affection.json "open_kinds": any NPC who can talk
START_TIMEOUT, ASK_TIMEOUT, RESTART_GAP = 240.0, 120.0, 5.0
SECONDS = {'kiss': 30.0, 'neck_kiss': 30.0, 'lap_dance': 60.0, 'dance': 60.0}


class Fail(Exception):
    def __init__(self, cat, msg):
        super().__init__(f'{cat}: {msg}')
        self.cat = cat


class Choices:
    """The run's decisions. Past the end every decision is 0, the most boring option."""
    def __init__(self, seq):
        self.seq, self.i = list(seq), 0

    def take(self, n):
        v = self.seq[self.i] if self.i < len(self.seq) else 0
        self.i += 1
        return v % n if n > 1 else 0

    def raw(self):
        v = self.seq[self.i] if self.i < len(self.seq) else 0
        self.i += 1
        return v


class OThreadRec:
    uid_counter = 0

    def __init__(self, actors, meta, scene, chair):
        OThreadRec.uid_counter += 1
        self.uid = OThreadRec.uid_counter
        self.actors, self.meta, self.scene, self.chair = actors, meta, scene, chair
        self.phase = 'walking'      # walking -> running -> ended
        self.played = False
        self.scored = False
        self.born = None
        self.id = -1


# ---------------------------------------------------------------------------
# The world: OStim, Mantella, time, the event queue
# ---------------------------------------------------------------------------

class World:
    def __init__(self, ch, fixes, trace):
        self.ch, self.fixes, self.trace_on = ch, set(fixes), trace
        self.t = 0.0
        self.threads = []           # script threads: dict(name, gen, wake)
        self.events = []            # (name, args) waiting for delivery
        self.timed = []             # (time, kind, payload): walks, natural ends, the update timer
        self.ostim = []             # every OThreadRec ever
        self.last_end = {}          # actor -> real time of the last end
        self.stamp = -1000.0        # StorageUtil MAE_SceneEndedAt
        self.talk_active, self.talk_ends, self.talk_end_time = True, 0, -100.0
        self.dead = set(); self.combat = set(); self.chair_free = True; self.chair_user = None
        self.closeness = {A: 1, B: 1, C: 1}
        self.intimacy = {A: 1, B: 1, C: 1}  # the Hub's IntimateValue
        self.intimacy_changed = {}  # npc -> time the player last changed it
        self.closeness_changed = {}
        self.kinds_open = {}        # StorageUtil MAE_AffectionKindsOpen per NPC
        self.kinds_su = {}          # StorageUtil MAE_AffectionKinds per NPC
        self.kinds_int = {}         # StorageUtil MAE_AffectionKindsIntimate per NPC
        self.facts = {}             # the NPC file's fact_affection
        self.timer = None           # (due, owner uid)
        self.log = []
        self.stops_by = []
        self.aff = Affection(self)
        self.ask = Ask(self)
        self.avail = {}             # (kind, who) -> scene installed for the pair
        for k in KINDS:
            for w in ('npc', 'player'):
                self.avail[(k, w)] = True
        self.step_count = 0
        self.force_walk = []

    def has(self, fix):
        return fix in self.fixes

    # --- tracing
    def note(self, s):
        if self.trace_on:
            self.log.append(f'{self.t:7.2f}  {s}')

    # --- OStim
    def live(self):
        return [o for o in self.ostim if o.phase != 'ended']

    def by_id(self, i):
        for o in self.live():
            if o.id == i:
                return o
        return None

    def in_ostim(self, actor):
        return any(actor in o.actors for o in self.live())

    def engine_start(self, actors, meta, scene, chair, who):
        """OThreadBuilder.Start / OThread.QuickStart, with the invariants for our own starts."""
        if None in actors:
            raise Fail('none', f'{who} started a scene with a missing actor {actors}')
        for o in self.live():
            if set(o.actors) & set(actors):
                raise Fail('overlap', f'{who} started {actors} while thread uid{o.uid} {o.actors} ({o.phase}) was live')
        for a in actors:
            if a in self.last_end and self.t - self.last_end[a] < RESTART_GAP:
                late = any(e[0] == 'ostim_thread_end' and a in e[1][1].actors for e in self.events)
                raise Fail('gap-latency' if late else 'gap', f'{who} started {actors} {self.t - self.last_end[a]:.2f} s after a scene with {a} ended')
        if chair is not None and (not self.chair_free) and self.chair_user != 'us':
            raise Fail('chair', f'{who} started a chair scene on a chair someone else took')
        if 'mlw_affection' in meta:
            self.check_intimate(scene, [a for a in actors if a != PLAYER], who + ' started')
            self.check_close(scene, [a for a in actors if a != PLAYER], who + ' started')
        rec = OThreadRec(actors, meta, scene, chair)
        used = {o.id for o in self.live()}
        rec.id = 0 if 0 not in used else max(used) + 1       # OStim gives the player's thread id 0, so ids repeat
        rec.born = self.t
        self.ostim.append(rec)
        if self.force_walk:
            walk = self.force_walk.pop(0)
        else:
            walk = [45.0, 2.0, 0.5, 300.0, -1.0][self.ch.take(5)]   # -1: the walk fails, the thread ends unstarted
        if walk < 0:
            self.timed.append((self.t + 3.0, 'walkfail', rec))
        else:
            self.timed.append((self.t + walk, 'running', rec))
        if not meta:
            self.timed.append((self.t + max(walk, 0) + 120.0, 'natural', rec))   # sex scenes end by themselves
        if chair is not None:
            self.chair_free, self.chair_user = False, 'us'
        self.note(f'OSTIM start uid{rec.uid} id={rec.id} {actors} meta={meta} scene={scene} walk={walk} by {who}')
        return rec.id

    def check_close(self, scene, npcs, what):
        if scene.split('-')[0] in OPEN_KINDS:
            return
        for npc in npcs:
            if not self.closeness.get(npc, 0):
                late = self.closeness_changed.get(npc, -1.0) >= self.aff.actionAt
                raise Fail('close-latency' if late else 'close', f'{what} {scene} with {npc}, who is not close')

    def check_intimate(self, scene, npcs, what):
        if scene.split('-')[0] not in INTIMATE_KINDS:
            return
        for npc in npcs:
            if not self.intimacy.get(npc, 0):
                late = self.intimacy_changed.get(npc, -1.0) >= self.aff.actionAt
                raise Fail('intimate-latency' if late else 'intimate', f'{what} {scene} with {npc}, who is not intimate')

    def engine_end(self, rec, why):
        if rec.phase == 'ended':
            return
        if rec.born is None:
            rec.born = self.t
        rec.phase = 'ended'
        for a in rec.actors:
            self.last_end[a] = self.t
        if rec.chair is not None:
            self.chair_free, self.chair_user = True, None
        self.note(f'OSTIM end uid{rec.uid} id={rec.id} ({why})')
        self.events.append(('ostim_thread_end', (rec.id, rec)))

    def stop(self, tid, by, timer_owner=None):
        rec = self.by_id(tid)
        if rec is None:
            return
        if 'mlw_affection' not in rec.meta:
            raise Fail('stop', f'{by} stopped thread uid{rec.uid} {rec.actors}, which is not an affection scene')
        if by == 'timer' and timer_owner != rec.uid:
            raise Fail('timer', f'a timer set for uid{timer_owner} stopped uid{rec.uid}')
        self.engine_end(rec, 'Stop by ' + by)

    # --- Mantella
    def announce(self, text, valid, why=''):
        self.note(f'MANTELLA "{text}"')
        if not valid:
            raise Fail('announce', f'told Mantella "{text}" but {why}')

    # --- scripts
    def spawn(self, name, gen):
        self.threads.append({'name': name, 'gen': gen, 'wake': None})

    def deliver(self, ev):
        name, args = ev
        self.note(f'EVENT {name} {args if name not in ("ostim_thread_start", "ostim_thread_end") else args[0]}')
        a = self.aff
        if name == 'affection':
            self.spawn('Affection.OnAffectionAdvanced', a.OnAffectionAdvanced(*args))
        elif name == 'npc_added':
            self.spawn('Affection.OnNpcAdded', a.OnNpcAdded(*args))
        elif name == 'refresh':
            self.spawn('Affection.OnRefreshNpc', a.OnRefreshNpc(*args))
        elif name == 'ended':
            self.spawn('Affection.OnConversationEnded', a.OnConversationEnded())
        elif name == 'ostim_thread_start':
            self.spawn('Affection.OnThreadStart', a.OnThreadStart(*args))
        elif name == 'ostim_thread_end':
            self.spawn('Affection.OnThreadEnd', a.OnThreadEnd(*args))
        elif name == 'update':
            self.spawn('Affection.OnUpdate', a.OnUpdate(*args))
        elif name == 'menu_close':
            self.spawn('Affection.OnMenuClose', a.OnMenuClose())
        elif name == 'sex':
            self.spawn('Ask.OnSexAdvanced', self.ask.OnSexAdvanced(*args))
        elif name == 'group':
            self.spawn('Ask.OnGroupAdvanced', self.ask.OnGroupAdvanced(*args))

    # --- the world's own moves
    def external(self, k):
        ch = self.ch
        npc = [A, B][ch.take(2)]
        if k == 0 and self.talk_active:
            kind = KINDS[ch.take(len(KINDS))]
            who = ['', 'player'][ch.take(2)]
            self.note(f'WORLD {npc} uses Affection kind={kind} who={who or "npc"}')
            self.events.append(('affection', (npc, kind, who, self.talk_ends)))
        elif k == 1 and self.talk_active:
            self.note(f'WORLD {npc} uses the sex action')
            self.events.append(('sex', (npc,)))
        elif k == 2 and self.talk_active:
            self.note('WORLD group sex action with A and B')
            self.events.append(('group', ((A, B),)))
        elif k == 3 and self.talk_active:
            self.talk_active = False; self.talk_ends += 1; self.talk_end_time = self.t
            self.note('WORLD the talk ends')
            self.events.append(('ended', ()))
        elif k == 4 and not self.talk_active and self.t - self.talk_end_time >= 2.0 and not self.events:
            # A new talk takes the player some seconds to start, and Mantella's last events are in by then.
            self.talk_active = True
            self.note('WORLD a new talk starts with A and B')
            self.events.append(('npc_added', (A,))); self.events.append(('npc_added', (B,)))
        elif k == 5 and not self.in_ostim(PLAYER):
            self.note(f'WORLD the player starts an OStim scene with {npc} by hand')
            rec = OThreadRec([PLAYER, npc], (), 'manual', None)
            used = {o.id for o in self.live()}
            rec.id = 0 if 0 not in used else max(used) + 1
            if npc in [x for o in self.live() for x in o.actors]:
                return
            rec.born = self.t
            self.ostim.append(rec)
            self.timed.append((self.t + 2.0, 'running', rec)); self.timed.append((self.t + 40.0, 'natural', rec))
        elif k == 6:
            self.combat ^= {PLAYER}
            self.note(f'WORLD player combat={PLAYER in self.combat}')
        elif k == 7 and npc not in self.dead:
            self.dead.add(npc)
            self.note(f'WORLD {npc} dies')
            for o in self.live():
                if npc in o.actors and self.t - o.born >= 0.5:   # a scene lasts at least the frames of its setup
                    self.engine_end(o, f'{npc} died')
        elif k == 8:
            if self.chair_free:
                self.chair_free, self.chair_user = False, 'other'
                self.note('WORLD someone sits on the chair')
            elif self.chair_user == 'other':
                self.chair_free, self.chair_user = True, None
                self.note('WORLD the chair is free again')
        elif k == 9:
            self.closeness[npc] = 1 - self.closeness[npc]
            self.closeness_changed[npc] = self.t
            self.note(f'WORLD {npc} closeness={self.closeness[npc]}, MLW_RefreshNpc sent')
            self.events.append(('refresh', (npc,)))
        elif k == 10:
            self.load()
        elif k == 11:
            kind = KINDS[ch.take(len(KINDS))]; w = ['npc', 'player'][ch.take(2)]
            self.avail[(kind, w)] = not self.avail[(kind, w)]
            self.note(f'WORLD scenes for {kind}/{w} installed={self.avail[(kind, w)]}')
        elif k == 13 and self.talk_active:
            self.note(f'WORLD {npc} joins the talk')
            self.events.append(('npc_added', (npc,)))
        elif k == 14:
            self.intimacy[npc] = 1 - self.intimacy[npc]
            self.intimacy_changed[npc] = self.t
            self.note(f'WORLD {npc} intimacy={self.intimacy[npc]}, MLW_RefreshNpc sent')
            self.events.append(('refresh', (npc,)))
        elif k == 12:
            for o in self.live():
                if 'mlw_affection' not in o.meta and self.t - o.born >= 0.5:
                    self.engine_end(o, 'the player ends their scene')

    def load(self):
        """A save loaded mid-walk: OStim threads are gone without end events, queued events are lost, script threads
        and registrations stay (the save was made just now), and the Loading Menu closes."""
        self.note('WORLD a save is loaded')
        for o in self.live():
            o.phase = 'ended'
            if o.chair is not None:
                self.chair_free, self.chair_user = True, None
        # OStim's own events for the vanished threads are gone; other mod events still arrive. Nothing of the old
        # threads is left to crash on, so the restart gap starts afresh.
        self.events = [e for e in self.events if e[0] not in ('ostim_thread_start', 'ostim_thread_end')]
        self.timed = [x for x in self.timed if x[1] not in ('running', 'walkfail', 'natural')]
        self.last_end = {}
        if self.ch.take(2):
            self.talk_active = False; self.talk_ends += 1; self.talk_end_time = self.t
            self.events.append(('ended', ()))
        self.events.append(('menu_close', ()))

    def runnable(self):
        return [th for th in self.threads if th['wake'] is None or th['wake'] <= self.t + 1e-9]

    def advance(self):
        """Moves time to the next thing that will happen; False if nothing will."""
        cands = [th['wake'] for th in self.threads if th['wake'] is not None]
        cands += [x[0] for x in self.timed]
        if self.timer:
            cands.append(self.timer[0])
        if not cands:
            return False
        self.t = max(self.t, min(cands))
        self.fire_timed()
        return True

    def advance_by(self, dt):
        end = self.t + dt
        while True:
            cands = [th['wake'] for th in self.threads if th['wake'] is not None] + [x[0] for x in self.timed]
            if self.timer:
                cands.append(self.timer[0])
            cands = [c for c in cands if c <= end]
            if not cands:
                self.t = end
                return
            self.t = max(self.t, min(cands))
            self.fire_timed()
            if self.runnable() or self.events:
                return

    def fire_timed(self):
        due = [x for x in self.timed if x[0] <= self.t + 1e-9]
        self.timed = [x for x in self.timed if x[0] > self.t + 1e-9]
        for _, kind, rec in due:
            if rec.phase == 'ended':
                continue
            if kind == 'running' and rec.phase == 'walking':
                rec.phase = 'running'; rec.played = True
                self.note(f'OSTIM uid{rec.uid} id={rec.id} is running')
                self.events.append(('ostim_thread_start', (rec.id, rec)))
            elif kind == 'walkfail' and rec.phase == 'walking':
                self.engine_end(rec, 'walk failed')
            elif kind == 'natural':
                self.engine_end(rec, 'scene over')
        if self.timer and self.timer[0] <= self.t + 1e-9:
            self.note('TIMER fires')
            self.events.append(('update', (self.timer[1],)))
            self.timer = None

    def step_thread(self, th):
        try:
            v = next(th['gen'])
            th['wake'] = self.t + v[1] if isinstance(v, tuple) and v[0] == 'wait' else None
        except StopIteration:
            self.threads.remove(th)

    def step(self, external_ok):
        self.step_count += 1
        R, E = self.runnable(), list(self.events)
        n_ext = 15 if external_ok else 0
        c = self.ch.raw() if external_ok else 0
        if c == 0:
            if R:
                self.step_thread(R[0])
            elif E:
                self.events.remove(E[0]); self.deliver(E[0])
            else:
                return self.advance()
            return True
        c -= 1
        if c < len(R):
            self.step_thread(R[c]); return True
        c -= len(R)
        if c < len(E):
            self.events.remove(E[c]); self.deliver(E[c]); return True
        c -= len(E)
        k = c % (n_ext + 1)
        if k == n_ext:
            if not R and not E:
                self.advance_by([1.0, 5.0, 30.0, 60.0, 250.0][self.ch.take(5)])
            return True
        self.external(k)
        return True


def N(world, fn=None):
    """A native or other-script call: other threads may run before and after it."""
    yield
    r = fn() if fn else None
    yield
    return r


def Wait(world, seconds):
    yield ('wait', max(seconds, 0.0))


# ---------------------------------------------------------------------------
# MAE_Text
# ---------------------------------------------------------------------------

def SecondsSinceSceneEnd(w):                                   # MAE_Text.psc 32-39
    now = yield from N(w, lambda: w.t)
    ended = yield from N(w, lambda: w.stamp)
    return 100000.0 if ended > now else now - ended


def WaitAfterScene(w):                                         # MAE_Text.psc 42-47
    left = RESTART_GAP - (yield from SecondsSinceSceneEnd(w))
    if left > 0:
        yield from Wait(w, left)


# ---------------------------------------------------------------------------
# MAE_Affection
# ---------------------------------------------------------------------------

class Affection:
    def __init__(self, w):
        self.w = w
        self.starting = self.started = self.stopOnStart = self.silentEnd = False   # 34-39
        self.thread = -1; self.partner = None; self.doer = None                     # 40-43
        self.currentKind = self.currentFurniture = ''; self.actionAt = self.startAt = 0.0
        self.afterEnd = self.nextKind = self.nextWho = ''; self.pickedDoer = None; self.talkEnds = 0
        self.truth_doer = None
        self.fileLock = False
        self.requesting = False; self.requestAt = 0.0; self.requestToken = 0; self.timerDue = 0.0   # the fixes
        self.origin = 0          # model only: talk end count when the request that owns the scene came in

    def Log(self, s):
        self.w.note(f'  AFFECT|{s}')
        yield from N(self.w)                                    # 631-639: GetValueInt, GetFormFromFile, hub.Log

    # --- gate and fact (73-123)
    def AvailableKinds(self, npc):                              # AvailableKinds
        """Three lists: only the open kinds (MAE_AffectionKindsOpen), without the intimate kinds (MAE_AffectionKinds) and
        with them (MAE_AffectionKindsIntimate)."""
        found = []
        chair = None
        for kind in KINDS:
            fits = True
            if kind in CHAIR_KINDS:
                if chair is None:
                    chair = (yield from self.FreeFurniture('chair')) is not None
                fits = chair
            if fits:
                s1 = yield from self.PickScene(kind, npc, '', any_standing=True)
                s2 = yield from self.PickScene(kind, npc, 'player', any_standing=True)
                if s1 or s2:
                    found.append(kind)
        full = ','.join(found)
        opened = ','.join(k for k in found if k in OPEN_KINDS)
        if not self.w.has('intimate'):
            return opened, full, full
        return opened, ','.join(k for k in found if k not in INTIMATE_KINDS), full

    def OnNpcAdded(self, npc):                                  # 74-91
        w = self.w
        opened, kinds, full = yield from self.AvailableKinds(npc)
        yield from N(w, lambda: w.kinds_open.__setitem__(npc, opened))
        yield from N(w, lambda: w.kinds_su.__setitem__(npc, kinds))
        yield from N(w, lambda: w.kinds_int.__setitem__(npc, full))
        yield from N(w)                                         # 84 RegisterForModEvent
        yield from self.LockFile()
        yield from self.WriteFact(npc)                          # 88
        yield from N(w)                                         # 89 Save
        self.fileLock = False
        yield from self.Log(f'GATE|{npc}|{kinds}')

    def OnRefreshNpc(self, npc):                                # 94-103
        yield from self.LockFile()
        yield from self.WriteFact(npc)
        yield from N(self.w)                                    # 101 Save
        self.fileLock = False

    def LockFile(self):
        """fix: one writer of the NPC file at a time (the join and a refresh used to interleave)."""
        if not self.w.has('file_lock'):
            return
        tries = 0
        while self.fileLock and tries < 50:
            yield from Wait(self.w, 0.1)
            tries += 1
        self.fileLock = True

    def WriteFact(self, npc):                                   # 106-123
        w = self.w
        intimate = True
        if w.has('intimate'):
            intimate = yield from N(w, lambda: w.intimacy[npc])       # KindsFor: IsIntimate
        if intimate and w.has('intimate'):
            store = w.kinds_int
        else:
            close = yield from N(w, lambda: w.closeness[npc])         # KindsFor: IsClose
            store = w.kinds_su if close > 0 else w.kinds_open
        kinds = yield from N(w, lambda: store.get(npc, ''))           # KindsFor
        yield from N(w)                                               # gate
        old = yield from N(w, lambda: w.facts.get(npc, ''))
        fact = ''
        if kinds:
            yield from N(w)                                           # GetCurrentGameTime
            fact = kinds
        if fact == old:
            return False
        yield from N(w, lambda: w.facts.__setitem__(npc, fact))       # 118/120
        return True

    # --- scenes
    def PickScene(self, kind, npc, who, current='', any_standing=False):   # PickScene
        w = self.w
        if not kind:
            return ''
        if w.has('intimate') and not any_standing and kind in INTIMATE_KINDS:
            intimate = yield from N(w, lambda: w.intimacy[npc])     # Ask.IsIntimate
            if not intimate:
                return ''
        yield from N(w)                                         # 193 GetAllScenes (when not passed)
        yield from N(w)                                         # 195 SortedPair -> OActorUtil.Sort
        yield from N(w)                                         # 197 GetSex
        yield from N(w)                                         # 204-206 JsonUtil lists
        wanted = 'player' if who == 'player' else 'npc'
        if kind not in WHO_KINDS:
            ok, doer = w.avail[(kind, 'npc')] or w.avail[(kind, 'player')], npc
        else:
            yield from N(w)                                     # 217 Doer -> OMetadata
            ok, doer = w.avail[(kind, wanted)], (PLAYER if wanted == 'player' else npc)
        if not ok:
            return ''
        yield from N(w)                                         # 229 RandomInt
        self.pickedDoer = doer                                  # 233
        w.note(f'  pick {kind} {npc} {wanted} -> {doer}')
        self.truth_doer = doer                                  # model: what this pick really meant
        return f'{kind}-{wanted}'

    def FreeFurniture(self, typ):                               # 270-283
        w = self.w
        if not typ:
            return None
        free = yield from N(w, lambda: w.chair_free)            # 274 FindFurniture
        yield from N(w)                                         # 277 GetFurnitureType
        return 'chair' if free else None

    def Furniture(self, kind):                                  # 264-266
        r = yield from N(self.w, lambda: 'chair' if kind in CHAIR_KINDS else '')
        return r

    # --- the action
    def OnAffectionAdvanced(self, npc, kind, who, origin):     # OnAffectionAdvanced
        w = self.w
        yield from N(w)                                         # getString + Trim
        yield from N(w)
        if w.has('talk_count'):
            count = yield from N(w, lambda: w.talk_active)       # fix: CountActorsInConversation, emptied before the end
            if not count:
                yield from self.Log('REFUSED|the talk has ended')
                return
        yield from self.Request(npc, kind, who, origin)

    def Request(self, npc, kind, who='', origin=None):
        w = self.w
        if origin is None:
            origin = w.talk_ends
        ends = self.talkEnds if w.has('talk_count') else None   # fix: counted first
        if not w.has('request_lock'):
            yield from self.RequestBody(npc, kind, who, origin, None, ends)
            return
        now = yield from N(w, lambda: w.t)                       # fix: one request at a time
        if self.requesting and now >= self.requestAt and now - self.requestAt < START_TIMEOUT:
            yield from self.Log('REFUSED|still starting')
            return
        self.requesting = True; self.requestAt = now; self.requestToken += 1
        token = self.requestToken
        grow = yield from self.RequestBody(npc, kind, who, origin, now, ends)
        if self.requestToken == token:
            self.requesting = False
        if grow:
            yield from self.w.ask.RequestAfterAffection(npc)

    def RequestBody(self, npc, kind, who, origin, now, ends):
        w = self.w
        if now is None:
            now = yield from N(w, lambda: w.t)                  # 298
        yield from N(w)                                         # 299 IsChildActor
        close = yield from N(w, lambda: w.closeness[npc])       # Ask.IsClose
        if not close and kind not in OPEN_KINDS:
            yield from self.Log(f'REFUSED|not close|{kind}')
            return False
        if w.has('box_check'):
            asking = yield from w.ask.Asking()                  # fix: the Ask First box is open
            if asking:
                yield from self.Log('REFUSED|the box is open')
                return False
        yield from self.Log(f'ACTION|{kind}|{npc}|who={who}')   # 303
        if self.starting and (now < self.actionAt or now - self.actionAt >= START_TIMEOUT):   # 304
            self.Forget()
            if w.has('timer'):
                yield from N(w)                                 # UnregisterForUpdate
        if self.starting:                                       # 307
            yield from self.Log('REFUSED|still starting')
            return False
        if self.started and npc == self.partner:                # 310
            running = yield from N(w, lambda t=self.thread: w.by_id(t) is not None)
            if running:
                meta = yield from N(w, lambda t=self.thread: (w.by_id(t) is not None and 'mlw_affection' in w.by_id(t).meta))
                if meta:
                    yield from self.Switch(kind, who, origin)
                    return False
        bad = False                                             # 314
        for f in (lambda: npc in w.dead, lambda: False, lambda: npc in w.combat, lambda: PLAYER in w.combat):
            r = yield from N(w, f)
            bad = bad or r
            if bad:
                break
        if bad:
            yield from self.Log('REFUSED|dead, disabled or in combat')
            yield from self.NoScene(npc, kind)
            return False
        p = yield from N(w, lambda: w.in_ostim(PLAYER))         # 319
        q = p or (yield from N(w, lambda: w.in_ostim(npc)))
        if p or q:
            yield from self.Log('REFUSED|someone is in a scene')
            return False
        furnitureRef = None
        ftype = yield from self.Furniture(kind)                 # 324
        if ftype:
            furnitureRef = yield from self.FreeFurniture(ftype)  # 326
            if not furnitureRef:
                yield from self.NoFurniture(npc, ftype)
                return False
        scene = yield from self.PickScene(kind, npc, who)       # 332
        if not scene:
            yield from self.NoScene(npc, kind)
            return False
        self.starting = True; self.started = False; self.stopOnStart = False; self.silentEnd = False   # 337-347
        self.afterEnd = ''; self.thread = -1; self.partner = npc; self.doer = self.pickedDoer
        self.currentKind = kind; self.currentFurniture = ftype; self.actionAt = now; self.origin = origin
        if ends is None:
            ends = self.talkEnds                                # 348
        if w.has('timer'):
            self.timerDue = 1e6                                 # fix: no timer of this scene yet
        yield from WaitAfterScene(w)                            # 349
        if self.talkEnds != ends:                               # 350
            yield from self.Log('STOP|talk ended before the call')
            self.Forget()
            return False
        if w.has('forgotten') and not (self.starting and self.partner == npc):
            yield from self.Log('STOP|forgotten during the wait (a load)')   # fix
            return False
        if self.stopOnStart:                                    # 355
            grow = self.afterEnd == 'grow'
            yield from self.Log('STOP|sex request before the call')
            self.Forget()
            if grow:
                if not w.has('request_lock'):
                    yield from w.ask.RequestAfterAffection(npc)  # 361
                    return False
                return True                                     # fix: after this request lets go
            return False
        p = yield from N(w, lambda: w.in_ostim(PLAYER))         # 364
        q = p or (yield from N(w, lambda: w.in_ostim(npc)))
        if p or q:
            yield from self.Log('REFUSED|someone is in a scene')
            self.Forget()
            return False
        if w.has('chair_again') and ftype:
            furnitureRef = yield from self.FreeFurniture(ftype)  # fix: the chair may be taken during the wait
            if not furnitureRef:
                self.Forget()
                yield from self.NoFurniture(npc, ftype)
                return False
        yield from SecondsSinceSceneEnd(w)                      # 370
        yield from self.Log(f'CALL|{kind}|{scene}')
        result = yield from self.StartThread(scene, furnitureRef)   # 371
        if result == 'cancelled':                               # fix: the talk ended or sex was asked meanwhile
            grow = self.afterEnd == 'grow'
            yield from self.Log('STOP|ended before the call')
            self.Forget()
            return grow
        if not result:
            self.Forget()
            yield from self.NoScene(npc, kind)
        return False

    def StartThread(self, scene, furniture):                    # 377-400
        w = self.w
        actors = yield from N(w, lambda: sorted([PLAYER, self.partner], key=lambda x: (x is None, str(x))) if self.partner else [PLAYER, None])
        yield from N(w)                                         # 378 Create
        for _ in range(7):                                      # 383-393 builder settings
            yield from N(w)
        if w.has('cancel') and self.stopOnStart:                 # fix: nothing starts once cancelled
            yield from N(w)                                     # OThreadBuilder.Cancel
            return 'cancelled'
        if self.origin != w.talk_ends:
            # The talk that asked for this ended before the start call.
            cat = 'talk' if self.talkEnds >= w.talk_ends else 'talk-latency'   # latency: its end event not yet in

            def start():
                raise Fail(cat, f'affection start {actors} after the talk ended')
        else:
            def start():
                return w.engine_start(actors, ('mlw_affection',), scene, furniture, 'Affection.StartThread')
        self.thread = yield from N(w, start)                    # 394
        if self.thread < 0:
            yield from self.Log('FAILED|start')
            return False
        return True

    def Switch(self, kind, who, origin):                        # 404-437
        w = self.w
        sid = self.thread
        current = yield from N(w, lambda t=self.thread: w.by_id(t).scene if w.by_id(t) else '')   # 405
        ftype = yield from self.Furniture(kind)                 # 406
        if ftype != self.currentFurniture:                      # 407
            if ftype and not (yield from self.FreeFurniture(ftype)):
                yield from self.NoFurniture(self.partner, ftype); return
            elif not (yield from self.PickScene(kind, self.partner, who)):
                yield from self.NoScene(self.partner, kind); return
            yield from self.Log(f'RESTART|{self.currentKind} to {kind}')
            self.afterEnd = 'kind'; self.nextKind = kind; self.nextWho = who; self.origin = origin
            if w.has('stamp'):
                yield from self.StopThread(sid, 'Switch')
            else:
                yield from N(w, lambda t=self.thread: w.stop(t, 'Switch'))   # 419
            return
        scene = yield from self.PickScene(kind, self.partner, who, current)   # 422
        picked = self.pickedDoer                                # fix: read before the next call
        truth = self.truth_doer
        if not scene:
            yield from self.NoScene(self.partner, kind); return
        landed = {'ok': False}

        def warp(t=self.thread):
            rec = w.by_id(t)
            if rec and 'mlw_affection' in rec.meta:
                w.check_intimate(scene, [a for a in rec.actors if a != PLAYER], 'Switch warped to')
                w.check_close(scene, [a for a in rec.actors if a != PLAYER], 'Switch warped to')
                rec.scene = scene; landed['ok'] = True
        if scene != current:
            yield from N(w, warp)                               # 428
        else:
            landed['ok'] = w.by_id(self.thread) is not None
        new_doer = self.pickedDoer if not w.has('switch') else picked
        if kind != self.currentKind or new_doer != self.doer:  # 430
            self.currentKind = kind; self.doer = new_doer
            line_ok = landed['ok'] and self.started
            if w.has('switch'):
                if not (self.started and self.thread == sid):
                    return                                      # fix: the scene ended meanwhile, nothing to say
            ok = line_ok and new_doer == truth
            yield from N(w, lambda: w.announce(f'{kind}: {self.doer} does it, partner {self.partner}', ok,
                                               'the scene had ended' if not line_ok else f'{truth} does it, not {new_doer}'))
        yield from self.Log(f'SWITCH|{kind}')
        yield from self.Register(SECONDS[kind])                 # 436

    def StopThread(self, tid, by, owner=None):
        """fix: stamps the end, then stops."""
        w = self.w
        yield from N(w, lambda: w.__setattr__('stamp', w.t))
        yield from N(w, lambda: w.stop(tid, by, owner))

    def Register(self, seconds):
        w = self.w
        def reg(t=self.thread):
            rec = w.by_id(t)
            w.timer = (w.t + seconds, rec.uid if rec else None)
        if w.has('timer'):
            now = yield from N(w, lambda: w.t)                  # fix: StartTimer sets timerDue
            self.timerDue = now + seconds
        yield from N(w, reg)

    def Grow(self, npc):                                        # 441-460
        w = self.w
        if not npc or npc != self.partner:
            return False
        busy = yield from self.Busy()
        if not busy:
            return False
        self.afterEnd = 'grow'; self.silentEnd = True
        if self.starting:
            self.stopOnStart = True
            yield from self.Log('GROW|while starting')
            return True
        yield from N(w)                                         # 453 GetSex
        valid = any(o for o in w.live() if 'mlw_affection' in o.meta and npc in o.actors) or self.starting
        yield from N(w, lambda: w.announce(f'{npc} pulls back for a moment', valid, 'no affection scene was on'))
        yield from self.Log('GROW')
        if w.has('stamp'):
            yield from self.StopThread(self.thread, 'Grow')
        else:
            yield from N(w, lambda t=self.thread: w.stop(t, 'Grow'))  # 458
        return True

    def Busy(self):                                             # 464-467
        now = yield from N(self.w, lambda: self.w.t)
        if self.w.has('request_lock') and self.requesting and now >= self.requestAt and now - self.requestAt < START_TIMEOUT:
            return True                                         # fix: a request between its checks and the claim
        return self.started or (self.starting and now >= self.actionAt and now - self.actionAt < START_TIMEOUT)

    def NoScene(self, npc, kind):
        yield from N(self.w, lambda: self.w.announce(f'no way to do {kind} here', True))

    def NoFurniture(self, npc, typ):
        yield from N(self.w, lambda: self.w.announce(f'no free {typ}', True))

    # --- the thread
    def OnThreadStart(self, tid, rec):                          # 521-539
        w = self.w
        meta = yield from N(w, lambda: 'mlw_affection' in rec.meta)   # 523
        if not meta:
            return
        self.thread = tid; self.starting = False; self.started = True  # 526-528
        yield from N(w)                                          # 529 GetCurrentRealTime
        yield from self.Log(f'TIMING|start|{self.currentKind}')  # 530 (GetScene too)
        if self.stopOnStart or not self.partner:                 # 531
            yield from self.Log('STOP|ended before the start')
            if w.has('stamp'):
                yield from self.StopThread(tid, 'OnThreadStart')
            else:
                yield from N(w, lambda: w.stop(tid, 'OnThreadStart'))
            return
        live = rec.phase == 'running'
        yield from N(w, lambda: w.announce(f'{self.currentKind}: {self.doer} does it, partner {self.partner}',
                                           rec.phase == 'running' and self.partner in rec.actors,
                                           f'thread uid{rec.uid} is {rec.phase} with {rec.actors}'))   # 537
        yield from self.Register(SECONDS.get(self.currentKind, 30.0))   # 538

    def OnUpdate(self, owner):                                   # 542-547
        w = self.w
        if w.has('timer'):
            t = self.thread
            if not self.started:
                return
            now = yield from N(w, lambda: w.t)
            if now < self.timerDue - 0.5:                        # fix: an older timer than the scene's own
                return
            running = yield from N(w, lambda: w.by_id(t) is not None)
            meta = running and (yield from N(w, lambda: w.by_id(t) is not None and 'mlw_affection' in w.by_id(t).meta))
            if meta:
                yield from self.Log('TIMER')
                if w.has('stamp'):
                    yield from self.StopThread(t, 'timer', owner)
                else:
                    yield from N(w, lambda: w.stop(t, 'timer', owner))
            return
        if self.started:
            t = self.thread
            running = yield from N(w, lambda: w.by_id(t) is not None)
            if running:
                meta = yield from N(w, lambda: w.by_id(t) is not None and 'mlw_affection' in w.by_id(t).meta)
                if meta:
                    yield from self.Log('TIMER')
                    yield from N(w, lambda: w.stop(self.thread, 'timer', owner))   # 545

    def OnThreadEnd(self, tid, rec):                             # 550-582
        w = self.w
        now = yield from N(w, lambda: w.t)                       # 551
        yield from N(w, lambda: w.__setattr__('stamp', now))     # 552
        if tid != self.thread or (not self.starting and not self.started):   # 553
            return
        yield from self.Log('TIMING|end')                        # 556
        npc = self.partner
        played = self.started and not self.stopOnStart and npc is not None   # 558
        if played and not self.silentEnd:
            yield from N(w, lambda: w.announce(f'{npc} and the player stop', rec.played and npc in rec.actors,
                                               f'thread uid{rec.uid} never played with {npc}'))
        after, kind, who, origin = self.afterEnd, self.nextKind, self.nextWho, self.origin   # 562-564
        self.Forget()                                            # 565
        if w.has('timer'):
            yield from N(w)                                      # UnregisterForUpdate (in Forget)
        if played:
            yield from self.Score(npc, rec)                      # 567
        if npc is None or after == '':
            return
        ends = self.talkEnds
        yield from WaitAfterScene(w)                             # 573
        if self.talkEnds != ends:
            yield from self.Log(f'STOP|talk ended before {after}')
        elif after == 'grow':
            yield from w.ask.RequestAfterAffection(npc)
        elif after == 'kind':
            yield from self.Request(npc, kind, who, origin)

    def Score(self, npc, rec):                                   # 585-594
        w = self.w
        def send():
            good = [o for o in w.ostim if 'mlw_affection' in o.meta and npc in o.actors and o.played and o.phase == 'ended' and not o.scored]
            if not good:
                raise Fail('score', f'score event for {npc} without a played affection scene (ended uid{rec.uid} played={rec.played})')
            good[-1].scored = True
            w.note(f'SCORE {npc}')
        yield from N(w, send)

    def OnConversationEnded(self):                               # 596-606
        w = self.w
        self.talkEnds += 1; self.afterEnd = ''
        if self.starting:
            self.stopOnStart = True
        elif self.started:
            t = self.thread
            running = yield from N(w, lambda: w.by_id(t) is not None)
            if running:
                meta = yield from N(w, lambda: w.by_id(t) is not None and 'mlw_affection' in w.by_id(t).meta)
                if meta:
                    self.silentEnd = True
                    yield from self.Log('STOP|talk ended')
                    if w.has('stamp'):
                        yield from self.StopThread(self.thread, 'OnConversationEnded')
                    else:
                        yield from N(w, lambda: w.stop(self.thread, 'OnConversationEnded'))

    def OnMenuClose(self):                                       # 609-613
        w = self.w
        if self.starting or self.started:
            p = yield from N(w, lambda: w.in_ostim(PLAYER))
            if not p:
                self.Forget()
                if w.has('timer'):
                    yield from N(w)

    def Forget(self):                                            # 615-628
        self.starting = self.started = self.stopOnStart = self.silentEnd = False
        self.thread = -1; self.partner = None; self.doer = None
        self.currentKind = self.currentFurniture = ''; self.afterEnd = self.nextKind = self.nextWho = ''
        if self.w.has('timer'):
            self.timerDue = 0.0
            self.w.timer = None                                  # fix: UnregisterForUpdate


# ---------------------------------------------------------------------------
# MAE_Ask
# ---------------------------------------------------------------------------

class Ask:
    def __init__(self, w):
        self.w = w
        self.asking = False; self.askedAt = 0.0

    def Log(self, s):
        self.w.note(f'  ASK|{s}')
        yield from N(self.w)

    def OnSexAdvanced(self, npc):                                # 35-40
        yield from N(self.w)                                     # Resolve: getStringArray, GetActorByName
        yield from self.Request([npc])

    def OnGroupAdvanced(self, npcs):                             # 42-47
        yield from N(self.w)
        yield from self.Request(list(npcs))

    def Asking(self):                                            # fix: Affection checks it
        now = yield from N(self.w, lambda: self.w.t)
        return self.asking and now >= self.askedAt and now - self.askedAt < ASK_TIMEOUT

    def Request(self, npcs, after=False):                        # 72-118
        w = self.w
        now = yield from N(w, lambda: w.t)                       # 73
        if self.asking and now >= self.askedAt and now - self.askedAt < ASK_TIMEOUT:   # 74
            return
        if w.has('ask_lock'):
            self.asking = True; self.askedAt = now               # fix: claimed before any call
        r = yield from self.RequestBody(npcs, after, now)
        if w.has('ask_lock') and self.askedAt == now:
            self.asking = False

    def RequestBody(self, npcs, after, now):
        w = self.w
        aff = w.aff
        yield from N(w)                                          # 77 GetFormFromFile
        p = yield from N(w, lambda: w.in_ostim(PLAYER))          # 78
        busy = p or (yield from aff.Busy())
        if busy:
            if len(npcs) == 1:
                g = yield from aff.Grow(npcs[0])                 # 80
                if g:
                    yield from self.Log('GROW')
            return
        for n in npcs:                                           # 86-91
            yield from N(w)                                      # IsChildActor
            q = yield from N(w, lambda n=n: w.in_ostim(n))
            if q:
                return
        if not w.has('ask_lock'):
            self.asking = True; self.askedAt = now               # 92-93
        combat = PLAYER in w.combat
        answers = ['Yes', 'No'] if combat else ['Yes', 'No', 'Skip']
        answer = answers[w.ch.take(len(answers))]
        dur = [3.0, 0.5, 15.0, 60.0, 130.0][w.ch.take(5)]
        yield from N(w)                                          # 95 GetValueInt
        yield from Wait(w, dur)                                  # 96 the box (latent)
        if not w.has('ask_lock'):
            self.asking = False                                  # 98
        yield from self.Log(f'ANSWER|{answer}|{npcs}')
        if answer == 'Yes':
            actors = [PLAYER] + list(npcs)
            if not w.has('ask_recheck'):
                if after:                                        # 108-110
                    yield from N(w, lambda: w.announce(f'{npcs} is ready now, and they start having sex',
                                                       not (w.in_ostim(PLAYER) or any(w.in_ostim(n) for n in npcs)) and not any(n in w.dead for n in npcs),
                                                       'the start can not happen now'))
                yield from WaitAfterScene(w)                     # 111
                w.note('  (QuickStart call)')
                yield from N(w, lambda: w.engine_start(actors, (), 'quickstart', None, 'Ask.QuickStart'))   # 112
            else:
                yield from WaitAfterScene(w)
                busy = yield from N(w, lambda: w.in_ostim(PLAYER))   # fix: someone may have started a scene meanwhile
                busy = busy or (yield from aff.Busy())
                for n in npcs:
                    q = yield from N(w, lambda n=n: w.in_ostim(n) or n in w.dead)
                    busy = busy or q
                if busy:
                    yield from self.Log('REFUSED|someone is in a scene')
                    return
                w.note('  (QuickStart call)')
                tid = yield from N(w, lambda: w.engine_start(actors, (), 'quickstart', None, 'Ask.QuickStart'))
                if after and tid >= 0:
                    yield from N(w, lambda: w.announce(f'{npcs} is ready now, and they start having sex', True))
        elif answer == 'Skip':
            yield from N(w); yield from Wait(w, 0.7); yield from N(w); yield from N(w)    # 145-148
            for _ in npcs:
                yield from N(w); yield from N(w)
            yield from Wait(w, 2.0)                              # 158
            yield from N(w); yield from N(w)
            yield from N(w, lambda: w.announce(f'{npcs} and the player finished having sex', True))
        else:
            yield from N(w, lambda: w.announce(f'{npcs} wanted sex, the player said no', True))

    def RequestAfterAffection(self, npc):                        # 121-126
        yield from N(self.w)                                     # GetDisplayName, SecondsSinceSceneEnd
        yield from SecondsSinceSceneEnd(self.w)
        yield from self.Log(f'AFTER AFFECTION|{npc}')
        yield from self.Request([npc], True)


# ---------------------------------------------------------------------------
# Runs
# ---------------------------------------------------------------------------

def settle(w, cap=40000):
    n = 0
    while n < cap:
        n += 1
        if not w.step(False):
            return
    raise Fail('stuck', 'the scripts never settled (a loop that keeps going)')


def final_checks(w):
    """After everything has settled: nothing left running for ever, facts consistent, new requests still work."""
    w.advance_by(600.0); settle(w)
    for o in w.live():
        if 'mlw_affection' in o.meta:
            raise Fail('stuck', f'affection scene uid{o.uid} with {o.actors} is still running 600 s after the last thing happened')
    for npc, fact in w.facts.items():
        if not w.intimacy[npc] and any(k in fact.split(',') for k in INTIMATE_KINDS):
            raise Fail('intimate', f'{npc} file names "{fact}", but {npc} is not intimate with the player')
        if w.intimacy[npc] and w.has('intimate'):
            store = w.kinds_int
        else:
            store = w.kinds_su if w.closeness[npc] > 0 else w.kinds_open
        want = store.get(npc, '')
        if fact != want:
            raise Fail('fact', f'{npc} file says "{fact}", the save holds kinds "{w.kinds_su.get(npc, "")}" and closeness {w.closeness[npc]}')
    # A fresh request with a fresh NPC, everything in its favour; from here every decision is the boring one.
    w.ch.i = max(w.ch.i, len(w.ch.seq))
    for o in w.live():
        w.engine_end(o, 'cleared for the probe')
    w.combat.clear(); w.chair_free, w.chair_user = True, None
    for k in w.avail:
        w.avail[k] = True
    if not w.talk_active:
        w.talk_active = True
    w.advance_by(300.0); settle(w)
    before = len(w.ostim)
    w.note('PROBE C uses Affection kind=kiss')
    w.events.append(('affection', (C, 'kiss', '', w.talk_ends)))
    settle(w)
    if not any(o for o in w.ostim[before:] if 'mlw_affection' in o.meta and C in o.actors):
        raise Fail('stuck', 'a fresh affection request was refused after everything settled')
    w.advance_by(600.0); settle(w)
    for o in w.live():
        w.engine_end(o, 'cleared for the probe')
    w.advance_by(300.0); settle(w)
    before = len(w.ostim)
    w.note('PROBE C uses the sex action, the box says Yes')
    w.events.append(('sex', (C,)))
    settle(w)
    if not any(o for o in w.ostim[before:] if not o.meta and C in o.actors):
        raise Fail('stuck', 'a fresh sex request (box Yes) never started a scene after everything settled')


FIXES = ['request_lock', 'box_check', 'ask_lock', 'ask_recheck', 'talk_count', 'cancel', 'forgotten', 'chair_again',
         'switch', 'timer', 'stamp', 'file_lock', 'intimate']


def run(seq, fixes, trace=False, steps=160):
    OThreadRec.uid_counter = 0
    w = World(Choices(seq), fixes, trace)
    w.events.append(('npc_added', (A,))); w.events.append(('npc_added', (B,)))
    try:
        for _ in range(steps):
            w.step(True)
        settle(w)
        final_checks(w)
    except Fail as f:
        return f, w
    return None, w


def gen_seq(rng, n):
    return [0 if rng.random() < 0.5 else rng.randint(1, 40) for _ in range(n)]


def shrink(seq, cat, fixes, steps):
    def fails(s):
        f, _ = run(s, fixes, steps=steps)
        return f is not None and f.cat == cat
    cur = list(seq)
    while cur and cur[-1] == 0:
        cur.pop()
    changed = True
    while changed:
        changed = False
        for size in (16, 8, 4, 2, 1):
            i = 0
            while i < len(cur):
                cand = cur[:i] + cur[i + size:]
                if fails(cand):
                    cur, changed = cand, True
                else:
                    i += size
        for i in range(len(cur)):
            for v in sorted({0, cur[i] // 2, cur[i] - 1} - {cur[i]}):
                if v >= 0:
                    cand = cur[:i] + [v] + cur[i + 1:]
                    if fails(cand):
                        cur[i], changed = v, True
                        break
        while cur and cur[-1] == 0:
            cur.pop()
    return cur


RESIDUAL = {'talk-latency', 'gap-latency', 'intimate-latency', 'close-latency'}   # an end event not yet delivered: nothing in Papyrus can see it


# ---------------------------------------------------------------------------
# Directed scenarios: the minimal sequences, written out
# ---------------------------------------------------------------------------

class Sc:
    def __init__(self, fixes):
        OThreadRec.uid_counter = 0
        self.w = World(Choices([]), fixes, True)

    def ev(self, name, *args):
        self.w.deliver((name, args))

    def th(self, prefix, i=0):
        m = [t for t in self.w.threads if t['name'].startswith(prefix)]
        return m[i] if i < len(m) else None

    def until(self, prefix, text, i=0, cap=500):
        th = self.th(prefix, i)
        assert th, f'no thread {prefix}'
        n = len(self.w.log)
        for _ in range(cap):
            if th not in self.w.threads:
                return
            self.w.step_thread(th)
            if any(text in l for l in self.w.log[n:]):
                return
        raise AssertionError(f'{prefix} never logged {text}')

    def lockstep(self, prefix, n=400):
        """Steps every thread of that name in turn, one suspension each, so they pass the same lines together."""
        for _ in range(n):
            ths = [t for t in self.w.runnable() if t['name'].startswith(prefix)]
            if not ths:
                return
            for t in ths:
                if t in self.w.threads:
                    self.w.step_thread(t)

    def finish(self, prefix, i=0):
        th = self.th(prefix, i)
        while th and th in self.w.threads and th['wake'] is None:
            self.w.step_thread(th)

    def deliver(self, name):
        for e in self.w.events:
            if e[0] == name:
                self.w.events.remove(e); self.w.deliver(e); return
        raise AssertionError(f'no {name} event queued')

    def settle(self):
        w = self.w
        while w.runnable() or w.events:
            w.step(False)

    def adv(self, dt):
        end = self.w.t + dt
        while self.w.t < end - 1e-9:
            self.w.advance_by(end - self.w.t)
            self.settle()

    def talk_end(self):
        w = self.w
        w.talk_active = False; w.talk_ends += 1; w.talk_end_time = w.t
        w.note('WORLD the talk ends')
        self.ev('ended')

    def talk_start(self):
        self.w.talk_active = True; self.w.note('WORLD a new talk starts')

    def manual(self, npc):
        w = self.w
        w.note(f'WORLD the player starts an OStim scene with {npc} by hand')
        rec = OThreadRec([PLAYER, npc], (), 'manual', None)
        rec.id = 0 if 0 not in {o.id for o in w.live()} else max(o.id for o in w.live()) + 1
        rec.born = w.t
        w.ostim.append(rec)
        w.timed.append((w.t + 2.0, 'running', rec))
        return rec

    def recent_end(self):
        """A scene of the player's ended a moment ago, so the next start waits the restart gap."""
        rec = self.manual(B)
        self.adv(2.5)
        self.w.engine_end(rec, 'the player ends it'); self.settle()
        self.adv(1.0)


def sc_box_then_affection(s):
    """The player says Yes in the Ask First box; an affection action comes as the sex scene is being started."""
    s.ev('sex', A); s.settle()                     # the box is up
    s.w.advance_by(3.0)                            # the player says Yes
    s.until('Ask.OnSexAdvanced', 'QuickStart call')
    s.ev('affection', A, 'kiss', '', 0); s.finish('Affection.OnAffectionAdvanced')
    s.settle(); s.adv(60)


def sc_two_affection_actions(s):
    """The same NPC's Affection action comes twice at once (two replies close together, or the same action twice)."""
    s.ev('affection', A, 'kiss', '', 0); s.ev('affection', A, 'kiss', '', 0)
    s.lockstep('Affection.OnAffectionAdvanced')
    s.settle(); s.adv(60)


def sc_two_sex_actions(s):
    """Two NPCs both use the sex action in the same reply; the player says Yes to both boxes."""
    s.ev('sex', A); s.ev('sex', B)
    s.lockstep('Ask.OnSexAdvanced')
    s.w.advance_by(3.0)                            # both boxes answered Yes at the same moment
    s.lockstep('Ask.OnSexAdvanced')
    s.settle(); s.adv(60)


def sc_own_scene_during_box(s):
    """While the box is up the player starts a scene by hand, then says Yes."""
    s.ev('sex', A); s.settle()
    s.manual(B); s.adv(60)


def sc_talk_ends_after_action(s):
    """The talk ends right after the affection action came in, before the request got to its claim."""
    s.ev('affection', A, 'kiss', '', 0)
    s.until('Affection.OnAffectionAdvanced', 'ACTION')
    s.talk_end(); s.finish('Affection.OnConversationEnded'); s.settle(); s.adv(60)


def sc_talk_ends_during_setup(s):
    """The talk ends while the thread is being set up (after the last check, before OThreadBuilder.Start)."""
    s.ev('affection', A, 'kiss', '', 0)
    s.until('Affection.OnAffectionAdvanced', 'CALL')
    s.talk_end(); s.finish('Affection.OnConversationEnded'); s.settle(); s.adv(60)


def sc_load_during_wait(s):
    """A save is loaded during the restart wait (the talk survives the load)."""
    s.recent_end()
    s.ev('affection', A, 'kiss', '', 0); s.settle()           # waiting out the gap
    s.w.ch = Choices([0]); s.w.load(); s.settle(); s.adv(60)


def sc_chair_taken(s):
    """Someone sits on the chair during the restart wait before a lap dance."""
    s.recent_end()
    s.ev('affection', A, 'lap_dance', '', 0); s.settle()
    s.w.chair_free, s.w.chair_user = False, 'other'; s.w.note('WORLD someone sits on the chair')
    s.adv(60)


def sc_old_timer(s):
    """A kiss ends early (the talk ended); its timer is still set and fires just as the next kiss starts."""
    s.ev('affection', A, 'kiss', '', 0); s.settle(); s.adv(46)    # playing, timer due at 75
    s.adv(4); s.talk_end(); s.settle()                           # t=50: stopped by the talk end
    s.adv(3); s.talk_start(); s.adv(20)                          # t=73
    s.w.force_walk = [2.0]
    s.ev('affection', A, 'kiss', '', s.w.talk_ends); s.settle()
    s.w.advance_by(2.0)                                          # t=75: the walk ends and the old timer fires
    if any(e[0] == 'ostim_thread_start' for e in s.w.events):
        s.deliver('ostim_thread_start'); s.until('Affection.OnThreadStart', 'TIMING|start')
    s.settle(); s.adv(60)


def sc_switch_while_npc_joins(s):
    """During a neck kiss the player asks to kiss her neck instead; B joins the talk at that moment."""
    s.ev('affection', A, 'neck_kiss', '', 0); s.settle(); s.adv(46)
    s.ev('affection', A, 'neck_kiss', 'player', 0)
    s.until('Affection.OnAffectionAdvanced', 'pick neck_kiss A player')
    s.ev('npc_added', B); s.until('Affection.OnNpcAdded', 'pick kiss B')
    s.settle(); s.adv(60)


def sc_scene_ends_during_switch(s):
    """A switch to a neck kiss is under way when A dies and the scene ends."""
    s.ev('affection', A, 'kiss', '', 0); s.settle(); s.adv(46)
    s.ev('affection', A, 'neck_kiss', '', 0)
    s.until('Affection.OnAffectionAdvanced', 'pick neck_kiss A npc')
    s.w.dead.add(A); s.w.note('WORLD A dies')
    s.w.engine_end(s.w.by_id(0), 'A died'); s.deliver('ostim_thread_end'); s.finish('Affection.OnThreadEnd')
    s.settle(); s.adv(60)


def sc_join_and_refresh(s):
    """A joins the talk and the Arousal module's refresh for A arrives at the same moment."""
    s.ev('npc_added', A); s.ev('refresh', A)
    for _ in range(4):                                       # until the refresh has read the kinds
        s.w.step_thread(s.th('Affection.OnRefreshNpc'))
    s.finish('Affection.OnNpcAdded'); s.settle()


def sc_grow_then_own_scene(s):
    """The talk goes from a kiss to sex; while the box is up the player starts a scene with B by hand."""
    s.ev('affection', A, 'kiss', '', 0); s.settle(); s.adv(46)
    s.ev('sex', A); s.settle(); s.adv(5.5)                       # the kiss ended, the box is up
    s.manual(B); s.adv(60)


def sc_action_as_timer_ends(s):
    """The timer ends a kiss and another affection action comes before the end event does."""
    s.ev('affection', A, 'kiss', '', 0); s.settle(); s.adv(46)
    s.w.advance_by(30.0)                                         # the timer fires
    s.deliver('update'); s.finish('Affection.OnUpdate')
    s.ev('affection', A, 'kiss', '', 0); s.finish('Affection.OnAffectionAdvanced')
    s.settle(); s.adv(60)


def sc_lap_dance_not_intimate(s):
    """A is close but not intimate: A joins (the fact must not offer a lap dance), then asks for one anyway."""
    s.w.intimacy[A] = 0
    s.ev('npc_added', A); s.settle()
    s.ev('affection', A, 'lap_dance', '', 0); s.settle(); s.adv(60)


def sc_intimacy_ends_mid_talk(s):
    """A is intimate on joining; the player takes intimacy back mid-talk (the Hub sends MLW_RefreshNpc)."""
    s.ev('npc_added', A); s.settle()
    s.w.intimacy[A] = 0; s.w.intimacy_changed[A] = s.w.t
    s.ev('refresh', A); s.settle(); s.adv(5)


SCENARIOS = [  # (function, the fix it needs)
    (sc_box_then_affection, 'box_check'), (sc_two_affection_actions, 'request_lock'), (sc_two_sex_actions, 'ask_lock'),
    (sc_own_scene_during_box, 'ask_recheck'), (sc_talk_ends_after_action, 'talk_count'), (sc_talk_ends_during_setup, 'cancel'),
    (sc_load_during_wait, 'forgotten'), (sc_chair_taken, 'chair_again'), (sc_old_timer, 'timer'),
    (sc_switch_while_npc_joins, 'switch'), (sc_scene_ends_during_switch, 'switch'), (sc_join_and_refresh, 'file_lock'),
    (sc_grow_then_own_scene, 'ask_recheck'), (sc_action_as_timer_ends, 'stamp'),
    (sc_lap_dance_not_intimate, 'intimate'), (sc_intimacy_ends_mid_talk, 'intimate'),
]


def run_scenario(fn, fixes):
    s = Sc(fixes)
    try:
        fn(s)
        final_checks(s.w)
    except Fail as f:
        return f, s.w
    return None, s.w


def scenarios(verbose):
    bad = 0
    print('    scenario                    needs         original        fix removed     all fixes')
    for fn, fix in SCENARIOS:
        o, wo = run_scenario(fn, [])
        r, _ = run_scenario(fn, [x for x in FIXES if x != fix])
        f, wf = run_scenario(fn, FIXES)
        ok = o is not None and r is not None and f is None
        bad += not ok
        cell = lambda x: (x.cat if x else 'pass')
        print(f'{"ok  " if ok else "FAIL"}{fn.__name__[3:]:28} {fix:13} {cell(o):15} {cell(r):15} {cell(f)}')
        if verbose or not ok:
            print(f'      {fn.__doc__}')
            for label, res, w in (('original', o, wo), ('all fixes', f, wf)):
                print(f'      {label}: {res or "no invariant failed"}')
                if verbose:
                    for line in w.log:
                        if 'pick ' not in line and 'GATE' not in line and 'PROBE' not in line:
                            print('        ' + line)
    return bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--runs', type=int, default=3000)
    ap.add_argument('--seed', type=int, default=1)
    ap.add_argument('--steps', type=int, default=160)
    ap.add_argument('--original', action='store_true', help='model the code before the fixes')
    ap.add_argument('--without', action='append', default=[], help='leave one fix out (ablation)')
    ap.add_argument('--traces', action='store_true', help='print the scenario traces and shrunk random failures')
    a = ap.parse_args()
    fixes = [] if a.original else [x for x in FIXES if x not in a.without]
    bad = 0
    if not a.original and not a.without:
        bad += scenarios(a.traces)
        print()
    rng = random.Random(a.seed)
    found, counts = {}, {}
    for r in range(a.runs):
        seq = gen_seq(rng, a.steps * 2)
        f, w = run(seq, fixes, steps=a.steps)
        if f:
            counts[f.cat] = counts.get(f.cat, 0) + 1
            found.setdefault(f.cat, seq)
    label = 'original code' if a.original else ('fixed code' + (f' without {", ".join(a.without)}' if a.without else ''))
    print(f'{a.runs} random runs of {a.steps} steps, {label}: ' + (', '.join(f'{k} {v}' for k, v in sorted(counts.items())) or 'no invariant failed'))
    for cat, seq in sorted(found.items()):
        small = shrink(seq, cat, fixes, a.steps)
        f, w = run(small, fixes, trace=True, steps=a.steps)
        print(f'  {cat}{" (residual)" if cat in RESIDUAL else ""}: shrunk to {len(small)} choices: {f}')
        if a.traces:
            for line in w.log:
                if 'pick ' not in line:
                    print('      ' + line)
    bad += len([c for c in found if c not in RESIDUAL])
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
