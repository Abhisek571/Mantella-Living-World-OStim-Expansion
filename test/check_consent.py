"""Static checks for consent, children and standing (no game needed).

1. Action files: the adult actions are gated on "intimate", redress and affection on "close"; undress, redress and
   sex between NPCs carry this module's own identifiers, are not radiant and never tell the model to obey event logs.
2. MAE_Npc registers exactly those identifiers and checks every named NPC: conversation members only, children,
   standing (intimate or close), consent, and a child anywhere in the talk; sex with the player goes to the box.
3. MAE_Ask and MAE_Affection: conversation members only, the intimate standing fails closed, consent and a child in
   the talk are checked before the box and again after the wait, a failed start is reported, and the test answer
   works only in test mode.
4. No scene line, summary or favourites line while a child is in the talk (MAE_Live, MAE_Positions).
5. Affection: the intimate kinds (lap dance, dance from a chair) need the intimate standing in PickScene and the fact;
   hug and cuddle have any-pair lists; a kind that works only one way round says so.
6. Change position in a same-sex or group scene points to OStim's menu instead of failing every time.
7. The Actions For Mantella fix (D:/coding/ActionsForMantella-OStim, when present): conversation members only, no
   child.
8. The Hub's standing (Mantella-Living-World-Hub next to this repo): an absolute command makes an NPC close and
   intimate for these re-checks only after the child check, only until its game time, and never in the NPC file
   Mantella's side reads; the hotkey flags no child.
9. The NPC decides: the scene actions carry a required decision (accept or decline) and reason; a decline is handled
   before anything resolves or starts, is shown and told to the talk, and says nothing with a child in the talk.
10. No control characters in the sources (a backspace once stood in a regex where a word boundary was meant).
11. The Hub's intimate standing checks for a child first, in every Intimacy mode.

usage: py -3 check_consent.py [--afm D:/coding/ActionsForMantella-OStim]
Exit code 1 on any failure.
"""
import argparse, json, os, re, sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ACTIONS = os.path.join(REPO, 'SKSE', 'Plugins', 'MantellaSoftware', 'data', 'actions')
SCRIPTS = os.path.join(REPO, 'Source', 'Scripts')
AFF = os.path.join(REPO, 'SKSE', 'Plugins', 'StorageUtilData', 'MantellaAdultExpansion', 'affection.json')
fails = []

GATES = {
    'mantella_npc_sex.json': ('mantella_mlw_sex', 'intimate'),
    'mantella_npc_sex_group.json': ('mantella_mlw_sex_group', 'intimate'),
    'mantella_npc_sex_npc.json': ('mantella_mlw_sex_npc', 'intimate'),
    'mantella_npc_undress.json': ('mantella_mlw_undress', 'intimate'),
    'mantella_npc_redress.json': ('mantella_mlw_redress', 'close'),
    'mantella_mae_change_position.json': ('mantella_mae_change_position', 'intimate+scene'),
    'mantella_mae_rate_positions.json': ('mantella_mae_rate_positions', 'intimate+unrated+scene'),
    'mantella_mlw_affection.json': ('mantella_mlw_affection', 'adult+affection=1'),  # the couple dance is open to anyone
}
OBEY = re.compile(r'event log|CONSECUTIVE OVERRIDE|PLAYER EVENT|CRITICAL SYSTEM COMMAND', re.I)


def check(ok, msg):
    if ok:
        print('  ok   ' + msg)
    else:
        fails.append(msg)
        print('  FAIL ' + msg)


def read(path):
    return open(path, encoding='utf-8', errors='replace').read()


def code(path):
    """The script without comments and doc blocks."""
    out = []
    for line in read(path).split('\n'):
        q = False
        for i, ch in enumerate(line):
            if ch == '"':
                q = not q
            elif ch == ';' and not q:
                line = line[:i]
                break
        out.append(line)
    return re.sub(r'\{[^}]*\}', '', '\n'.join(out))


def function(src, name):
    m = re.search(r'^\s*(?:\w+(?:\[\])?\s+)?(?:Function|Event)\s+' + name + r'\(.*?^\s*End(?:Function|Event)', src, re.M | re.S | re.I)
    return m.group(0) if m else ''


def actions():
    print('== action files')
    for fn, (ident, gate) in GATES.items():
        d = json.load(open(os.path.join(ACTIONS, fn), encoding='utf-8'))
        check(d.get('identifier') == ident, f'{fn}: identifier {d.get("identifier")} (want {ident})')
        check(d.get('lw_gate') == gate, f'{fn}: gate {d.get("lw_gate")} (want {gate})')
        check(d.get('radiant') is False, f'{fn}: not radiant')
        check(not OBEY.search(d.get('prompt', '')), f'{fn}: prompt has no event-log or override clauses')
        if ident.startswith('mantella_mlw_') and ident not in ('mantella_mlw_affection',):
            check('child' in d['prompt'].lower(), f'{fn}: prompt says never to name a child')
        deps = d.get('_dependencies', [])
        check(not any('ActionsForMantella' in x for x in deps), f'{fn}: handled by this module, not Actions For Mantella')


def npc_script():
    print('== MAE_Npc')
    src = code(os.path.join(SCRIPTS, 'MAE_Npc.psc'))
    for ident in ('mantella_mlw_undress', 'mantella_mlw_redress', 'mantella_mlw_sex_npc'):
        check(f'"{ident}"' in src and 'RegisterForModEvent("MantellaConversation_Advanced_Action_" + ACTION_' in src,
              f'registers {ident}')
    check('GetActorByName' not in src, 'never resolves a name to someone merely nearby (no GetActorByName)')
    allowed = function(src, 'Allowed')
    for need in ('MAE_Text.TalkActor', 'MAE_Text.IsChildActor', 'IntimateValue', 'CloseValue', 'MAE_Text.CannotConsent'):
        check(need in allowed, f'Allowed checks {need}')
    check('!channel ||' in allowed, 'Allowed refuses when the Hub cannot be read')
    for ev, need in (('OnUndressAdvanced', 'NEED_INTIMATE'), ('OnRedressAdvanced', 'NEED_CLOSE'), ('OnSexNpcAdvanced', 'NEED_INTIMATE')):
        body = function(src, ev)
        check(need in body and 'Allowed(' in body, f'{ev} checks each NPC for {need}')
    for ev in ('OnUndressAdvanced', 'OnSexNpcAdvanced'):
        check('MinorPresent()' in function(src, ev), f'{ev} refuses while a child is in the talk')
    sex = function(src, 'OnSexNpcAdvanced')
    check(re.search(r'target == PlayerRef.*?Ask\.Request\(', sex, re.S) is not None, 'sex with the player goes to the Ask First box')
    check(sex.find('Ask.Request(') < sex.find('OThread.QuickStart('), 'the player case returns before any QuickStart')
    check('QuickStart(actors) < 0' in sex, 'a failed NPC scene start is reported')
    check('MAE_Text.CannotConsent(source) || MAE_Text.CannotConsent(target) || MAE_Text.MinorInTalk()' in sex,
          'consent and children are checked again after the restart wait')


def ask_and_affection():
    print('== MAE_Ask and MAE_Affection')
    ask = code(os.path.join(SCRIPTS, 'MAE_Ask.psc'))
    check('GetActorByName' not in ask, 'MAE_Ask resolves names among conversation members only')
    check('IsIntimate(npc)' in function(ask, 'Resolve'), 'Resolve keeps only intimate NPCs')
    for f in ('IsIntimate', 'IsClose'):
        body = function(ask, f)
        check('Return channel &&' in body, f'{f} fails closed when the Hub cannot be read')
    req = function(ask, 'RequestScene')
    box = req.find('Ask(akNpcs)')
    for need in ('MAE_Text.MinorInTalk()', 'MAE_Text.CannotConsent(', 'MAE_Text.PlayerCanConsent()'):
        i = req.find(need)
        check(0 <= i < box, f'RequestScene checks {need} before the box')
        check(req.find(need, box) > box, f'RequestScene checks {need} again after the wait')
    check('QuickStart(actors) < 0' in req, 'a failed start is reported to Mantella')
    askf = function(ask, 'Ask')
    check(re.search(r'testAnswer != ""\s*If MAE_TestMode\.GetValueInt\(\) == 1\s*Return testAnswer', askf) is not None,
          'the test answer is used only in test mode')
    text = code(os.path.join(SCRIPTS, 'MAE_Text.psc'))
    cc = function(text, 'CannotConsent')
    for need in ('IsDead', 'IsDisabled', 'GetSleepState() >= 3', 'IsUnconscious', 'IsBleedingOut', '"Paralysis"',
                 'GetActorKnockState', 'IsInCombat', 'OActor.IsInOStim'):
        check(need in cc, f'CannotConsent checks {need}')
    pc = function(text, 'PlayerCanConsent')
    check('0x0CDD84' in pc and '0x00283A' in pc and 'IsInCombat' in pc, 'PlayerCanConsent: combat, werewolf, vampire lord')
    check('GetActorInConversationByIndex' in function(text, 'MinorInTalk'), 'MinorInTalk walks the conversation')
    talk = function(text, 'TalkActor')
    check('GetActorInConversation(' in talk and 'GetActorByName' not in talk, 'TalkActor never falls back to nearby actors')
    aff = code(os.path.join(SCRIPTS, 'MAE_Affection.psc'))
    req = function(aff, 'RequestScene')
    check('MAE_Text.CannotConsent(akNpc) || !MAE_Text.PlayerCanConsent() || MAE_Text.MinorInTalk()' in req,
          'MAE_Affection refuses without consent or with a child in the talk')
    check('Ask.IsClose(akNpc)' in req, 'affection stays on the close standing')


def child_lines():
    print('== no scene lines with a child in the talk')
    live = code(os.path.join(SCRIPTS, 'MAE_Live.psc'))
    for f in ('SendLine', 'AddEvent', 'SendSummary'):
        check('MAE_Text.MinorInTalk()' in function(live, f), f'MAE_Live.{f} stays quiet with a child in the talk')
    pos = code(os.path.join(SCRIPTS, 'MAE_Positions.psc'))
    for f in ('OnNpcAdded', 'OnThreadStart'):
        check('MAE_Text.MinorInTalk()' in function(pos, f), f'MAE_Positions.{f} sends no favourites line with a child in the talk')
    change = function(pos, 'OnChangeAdvanced')
    check('Flows.PartnerOf(threadID)' in change and "OStim's own menu" in change and 'toldMenuThread' in change,
          'change position in a same-sex or group scene points to OStim\'s menu, once per scene')


def affection_kinds():
    print('== affection kinds')
    wl = json.load(open(AFF, encoding='utf-8'))
    lists = wl['stringList']
    check(sorted(lists.get('intimate_kinds', [])) == ['lap_dance', 'solo_dance'], 'intimate_kinds: lap_dance and solo_dance')
    check('dance' not in lists.get('intimate_kinds', []), 'the couple dance stays on close')
    check(all(x.startswith('ShadowmanBallroom') for x in lists.get('dance_mf', [])), 'the couple dance list holds only ballroom dances')
    check(len(lists.get('hug', [])) >= 1, 'hug has an any-pair list')
    check(len(lists.get('cuddle', [])) >= 1, 'cuddle has an any-pair list')
    aff = code(os.path.join(SCRIPTS, 'MAE_Affection.psc'))
    pick = function(aff, 'PickScene')
    check('IntimateKind(asKind) && !Ask.IsIntimate(akNpc)' in pick, 'PickScene skips intimate kinds for NPCs who are not intimate')
    check('Ask.IsIntimate(akNpc)' in function(aff, 'KindsFor'), 'the fact names the intimate kinds only for intimate NPCs')
    check('KindsFor(akNpc)' in function(aff, 'WriteFact'), 'the fact and gate follow the standing on every refresh')
    avail = function(aff, 'AvailableKinds')
    check('(only you do it)' in avail and '(only the player does it)' in avail, 'a one-way kind says who does it')
    check('NoSceneFor(' in function(aff, 'RequestScene') and 'Only the player can do that here' in function(aff, 'NoSceneFor'),
          'a wrong-direction request says it works only the other way round')


def identity():
    print('== leveled sex, male partner climax, neutral wording')
    for name in ('MAE_Affection.psc', 'MAE_Flows.psc'):
        src = code(os.path.join(SCRIPTS, name))
        check('GetActorBase().GetSex()' not in src, f'{name}: sex read from the leveled base')
    flows = code(os.path.join(SCRIPTS, 'MAE_Flows.psc'))
    up = function(flows, 'OnUpdate')
    check('partner.GetLeveledActorBase().GetSex() == 1 && NotSatisfied(partner)' in up,
          'a new chain only after a woman partner climaxes and is not satisfied')
    for fn in ('mantella_mlw_affection.json', 'mantella_mae_change_position.json'):
        d = json.load(open(os.path.join(ACTIONS, fn), encoding='utf-8'))
        check(not re.search(r'\b(she|her)\b', d['description'], re.I), f'{fn}: description uses neutral wording')


def afm(path):
    print('== Actions For Mantella fix')
    src_path = os.path.join(path, 'Source', 'ActionsForMantellaScript.psc')
    if not os.path.exists(src_path):
        print(f'  skip {src_path} not found')
        return
    src = code(src_path)
    for ev in ('OnNpcActionSexReceived', 'OnNpcActionSexNpcReceived', 'OnNpcActionUndressReceived', 'OnNpcActionRedressReceived'):
        body = function(src, ev)
        check('GetActorByName' not in body and ('GetActorInConversation' in body or 'TalkActor(' in body),
              f'{ev}: conversation members only')
        check('IsChildActor(' in body, f'{ev}: never a child')
    child = function(src, 'IsChildActor')
    check('IsChild()' in child and '"Child"' in child, 'IsChildActor checks the flag and the race')


def hub_commands(hub):
    print("== absolute commands in the Hub's standing")
    channel_path = os.path.join(hub, 'Source', 'Scripts', 'MLW_Channel.psc')
    command_path = os.path.join(hub, 'Source', 'Scripts', 'MLW_Command.psc')
    if not (os.path.exists(channel_path) and os.path.exists(command_path)):
        print(f'  skip {hub} not found')
        return
    channel, command = code(channel_path), code(command_path)
    for value, standing in (('IntimateValue', 'IntimateStanding'), ('CloseValue', 'CloseStanding')):
        body = function(channel, value)
        check(re.search(r'\(Actor akNpc\)', body.strip().split('\n')[0]) is not None, f'{value} keeps its one-argument signature')
        check(standing + '(akNpc)' in body and '!IsMinor(akNpc) && Commanded(akNpc)' in body,
              f'{value}: a command counts only after the child check')
        check(function(channel, standing).find('IsMinor(akNpc)') >= 0 and 'Commanded' not in function(channel, standing),
              f'{standing}: child check, no command')
    commanded = function(channel, 'Commanded')
    check('"MLW_CommandUntil"' in commanded and 'GetCurrentGameTime()' in commanded, 'Commanded ends by game time')
    write = function(channel, 'WriteNpc')
    check('CloseStanding(akNpc)' in write and 'IntimateStanding(akNpc)' in write and 'CloseValue(' not in write and 'IntimateValue(' not in write,
          "the NPC file holds the standing without commands (Mantella's side adds and ends them)")
    flag = function(command, 'FlagNpcs')
    check('!akChannel.IsMinor(npc)' in flag and '"MLW_CommandUntil"' in flag, 'the hotkey never flags a child')
    check('FlagNpcs(' in function(command, 'Give'), 'Give flags the NPCs it gave the command to')


SCENE_ACTIONS = {'mantella_npc_sex.json': 'OnSexAdvanced', 'mantella_npc_sex_group.json': 'OnGroupAdvanced',
                 'mantella_npc_sex_npc.json': 'OnSexNpcAdvanced'}


def decisions():
    print("== the NPC decides: decision and reason on the scene actions, a decline starts nothing")
    for fn in SCENE_ACTIONS:
        d = json.load(open(os.path.join(ACTIONS, fn), encoding='utf-8'))
        params = d.get('parameters', {})
        check(params.get('decision', {}).get('enum') == ['accept', 'decline'], f'{fn}: decision is accept or decline')
        check(params.get('reason', {}).get('type') == 'string', f'{fn}: a reason')
        check({'decision', 'reason'} <= set(d.get('required', [])), f'{fn}: decision and reason are required')
        check('decline' in d['prompt'] and 'may refuse' in d['prompt'], f'{fn}: the prompt lets the NPC refuse')
    ask = code(os.path.join(SCRIPTS, 'MAE_Ask.psc'))
    for ev in ('OnSexAdvanced', 'OnGroupAdvanced'):
        body = function(ask, ev)
        check(0 <= body.find('Declined(') < body.find('Resolve('), f'{ev}: a decline is handled before anything resolves')
    dec = function(ask, 'Declined')
    check('getString(aiArguments, "decision", "") != "decline"' in dec and 'Return false' in dec,
          'only "decline" declines; no decision (keyword actions, an older Mantella) goes on as before')
    check('MAE_Text.MinorInTalk()' in dec and dec.find('MAE_Text.MinorInTalk()') < dec.find('MLW_Notify.Result('),
          'nothing is said about it with a child in the talk')
    check('MAE_Text.IsChildActor(npc)' in dec and 'MAE_Text.TalkActor(' in dec, 'a decline names conversation members only, never a child')
    check('MLW_Notify.Result(hud, fact)' in dec, 'a decline is a HUD line and an event line (remembered with the talk)')
    check('QuickStart' not in dec and 'Request(' not in dec and 'Ask(' not in dec, 'a decline starts nothing and asks nothing')
    check('getString(aiArguments, "reason", "")' in function(ask, 'Reason'), 'the reason is read')
    npc = function(code(os.path.join(SCRIPTS, 'MAE_Npc.psc')), 'OnSexNpcAdvanced')
    i = npc.find('Ask.Declined(')
    check(0 <= i < npc.find('Allowed(') and i < npc.find('Ask.Request(') and npc.find('MinorPresent()') < i,
          'SexWithNPC: a decline is handled after the child check and before anything starts')
    before = npc[:i]
    check('"sex with " + targetName' not in before and re.search(r'"sex with " \+ \w+\.GetDisplayName\(\)', before) is not None,
          "SexWithNPC decline: the target is named by its game name, never by the model's text")
    named = re.search(r'If (.*?)\n\s*what = "sex with " \+ target\.GetDisplayName\(\)', before)
    check(named is not None and 'target' in named.group(1) and '!MAE_Text.IsChildActor(target)' in named.group(1)
          and 'MAE_Text.TalkActor(conversation, targetName)' in before,
          'SexWithNPC decline: a target is named only when it is an adult in the conversation, else not named at all')


def control_chars():
    print('== no control characters in sources (a backspace once stood where \\b was meant)')
    bad = []
    for top in ('test', 'tools', 'Source', 'SKSE'):
        for d, _, files in os.walk(os.path.join(REPO, top)):
            for f in files:
                if f.endswith(('.py', '.psc', '.json', '.sh', '.cmd', '.txt')):
                    data = open(os.path.join(d, f), 'rb').read()
                    if re.search(rb'[\x00-\x08\x0b\x0c\x0e-\x1f]', data):
                        bad.append(os.path.relpath(os.path.join(d, f), REPO))
    check(not bad, f'no control characters other than tab and line ends: {bad}')


def hub_intimacy(hub):
    print("== the Hub's intimacy standing: the child block in every mode")
    path = os.path.join(hub, 'Source', 'Scripts', 'MLW_Channel.psc')
    if not os.path.exists(path):
        print(f'  skip {hub} not found')
        return
    channel = code(path)
    standing = function(channel, 'IntimateStanding')
    minor, never, mode = standing.find('IsMinor(akNpc)'), standing.find('"never_intimate"'), standing.find('IntimacyCheckPasses(akNpc)')
    check(0 <= minor < never < mode, 'IntimateStanding: the child check first, then Intimacy: never, then the Intimacy setting')
    child = function(channel, 'IsMinor')
    check('akActor.IsChild()' in child and '"Child"' in child and 'GetRaceEditorID' in child, 'IsMinor: the child flag and the race')
    check('IntimacyMode() == 1' in function(channel, 'IntimacyCheckPasses'), 'NPC decides (1) opens the gate for adults only')


def scene_without_talk():
    """Live test 12: two OStim scenes with Gerdur ended before any Mantella talk ran, and nothing was recorded. A scene
    that ends with no talk running is kept on each adult partner (at most MAX_PENDING) and told to her next talk."""
    print("== a scene with no talk running is kept for the partner's next talk")
    live = code(os.path.join(SCRIPTS, 'MAE_Live.psc'))
    summary = function(live, 'SendSummary')
    keep, run, minor = summary.find('KeepForLater(line)'), summary.find('!ConversationRunning()'), summary.find('MAE_Text.MinorInTalk()')
    check(0 <= run < keep < minor, 'SendSummary: with no talk running the line is kept (before the child-in-talk check, which needs a talk)')
    later = function(live, 'KeepForLater')
    check('!MAE_Text.IsChildActor(partner)' in later and 'partner != PlayerRef' in later and 'MAX_PENDING' in later
          and 'StorageUtil.StringListRemoveAt(partner, KEY_PENDING, 0)' in later
          and 'StorageUtil.AdjustIntValue(partner, KEY_PENDING_EARLIER, 1)' in later, 'KeepForLater: adult partners only; past MAX_PENDING the oldest is counted, not lost')
    added_text = function(live, 'OnNpcAdded')
    check('KEY_PENDING_EARLIER' in added_text and 'more scene(s) together before these' in added_text, 'OnNpcAdded tells the counted earlier scenes too')
    raw = read(os.path.join(SCRIPTS, 'MAE_Live.psc'))  # raw source: code() drops {...} doc blocks, even inside strings
    check('" {t=" + StringUtil.Substring(entry, 0, bar) + "}"' in raw, "OnNpcAdded adds the scene game time for the Hub to date and pair it")
    added = function(live, 'OnNpcAdded')
    check('RegisterForModEvent("MantellaConversation_NPC_Added", "OnNpcAdded")' in function(live, 'Register'),
          'MAE_Live listens for a partner joining a talk')
    check('MAE_Text.MinorInTalk()' in added and 'AgoText(' in added and 'StorageUtil.StringListClear(npc, KEY_PENDING)' in added
          and added.find('AddEvent(') < added.find('StringListClear'), 'OnNpcAdded: told with how long ago, then cleared; kept while a child is in the talk')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--afm', default=os.path.join(os.path.dirname(REPO), 'ActionsForMantella-OStim'))
    ap.add_argument('--hub', default=os.path.join(os.path.dirname(REPO), 'Mantella-Living-World-Hub'))
    a = ap.parse_args()
    actions()
    npc_script()
    ask_and_affection()
    child_lines()
    affection_kinds()
    identity()
    afm(a.afm)
    hub_commands(a.hub)
    decisions()
    control_chars()
    hub_intimacy(a.hub)
    scene_without_talk()
    print(f'\n{len(fails)} failures')
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
