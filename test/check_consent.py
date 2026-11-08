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
    'mantella_mae_change_position.json': ('mantella_mae_change_position', 'intimate'),
    'mantella_mae_rate_positions.json': ('mantella_mae_rate_positions', 'intimate+unrated'),
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
        check(not re.search(r'(she|her)', d['description'], re.I), f'{fn}: description uses neutral wording')


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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--afm', default=os.path.join(os.path.dirname(REPO), 'ActionsForMantella-OStim'))
    a = ap.parse_args()
    actions()
    npc_script()
    ask_and_affection()
    child_lines()
    affection_kinds()
    identity()
    afm(a.afm)
    print(f'\n{len(fails)} failures')
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
