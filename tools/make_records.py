"""One-off scaffolding: writes the plugin's Spriggit YAML (globals + quests), the OStim MCM settings page and the
Mantella action files for Mantella - Adult Expansion - OStim. Run from the project root."""
import json, os

E = 'Mantella - Adult Expansion - OStim.esp'
G = [('000800', 'MAE_LiveSceneLines', 'GlobalShort', 1), ('000801', 'MAE_LiveSceneCooldown', 'GlobalFloat', 45),
     ('000802', 'MAE_BystanderComments', 'GlobalShort', 1), ('000803', 'MAE_BystanderChance', 'GlobalFloat', 0.25),
     ('000804', 'MAE_BystanderArousalChance', 'GlobalFloat', 0.25), ('000805', 'MAE_FlowsEnabled', 'GlobalShort', 1),
     ('000806', 'MAE_FlowFinishExcitement', 'GlobalFloat', 90), ('000807', 'MAE_TalkBandChance', 'GlobalFloat', 0.5),
     ('000808', 'MAE_TalkGap', 'GlobalFloat', 40), ('000809', 'MAE_DirtyTalk', 'GlobalShort', 1),
     ('00080A', 'MAE_Hotkey', 'GlobalShort', 199), ('00080B', 'MAE_NotifyScene', 'GlobalShort', 0),
     ('00080C', 'MAE_SetupReminder', 'GlobalShort', 1), ('00080D', 'MAE_TemperDefault', 'GlobalShort', 0),
     ('00080E', 'MAE_TemperSource', 'GlobalShort', 0), ('00080F', 'MAE_SetupDone', 'GlobalShort', 0),
     ('000810', 'MAE_NeverForceStart', 'GlobalShort', 1), ('000811', 'MAE_TestMode', 'GlobalShort', 0)]
gid = {n: f for f, n, _, _ in G}
Q = {'000820': ('MAE_QuestLive', 'MAE_Live', 'Mantella Adult Expansion - Live lines'),
     '000821': ('MAE_QuestBystander', 'MAE_Bystander', 'Mantella Adult Expansion - Bystanders'),
     '000822': ('MAE_QuestFlows', 'MAE_Flows', 'Mantella Adult Expansion - Scene flows'),
     '000823': ('MAE_QuestPositions', 'MAE_Positions', 'Mantella Adult Expansion - Positions'),
     '000824': ('MAE_QuestSetup', 'MAE_Setup', 'Mantella Adult Expansion - Setup')}
qid = {v[1]: k for k, v in Q.items()}
PROPS = {
    'MAE_Live': [('Bystander', qid['MAE_Bystander'])] + [(g, gid[g]) for g in
                 ['MAE_DirtyTalk', 'MAE_LiveSceneCooldown', 'MAE_LiveSceneLines', 'MAE_TalkBandChance', 'MAE_TalkGap', 'MAE_TestMode']],
    'MAE_Bystander': [(g, gid[g]) for g in ['MAE_BystanderArousalChance', 'MAE_BystanderChance', 'MAE_BystanderComments']],
    'MAE_Flows': [(g, gid[g]) for g in ['MAE_FlowFinishExcitement', 'MAE_FlowsEnabled', 'MAE_NotifyScene', 'MAE_TestMode']] + [('Positions', qid['MAE_Positions'])],
    'MAE_Positions': [('Flows', qid['MAE_Flows'])],
    'MAE_Setup': [('Flows', qid['MAE_Flows'])] + [(g, gid[g]) for g in
                  ['MAE_FlowsEnabled', 'MAE_Hotkey', 'MAE_SetupDone', 'MAE_SetupReminder', 'MAE_TemperDefault', 'MAE_TemperSource']],
}


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'w', encoding='utf-8', newline='\n').write(text)


for fid, name, typ, val in G:
    write(f'esp/Globals/{name} - {fid}_{E}.yaml', f'MutagenObjectType: {typ}\nFormKey: {fid}:{E}\nEditorID: {name}\nData: {val}\n')
for fid, (eid, script, name) in Q.items():
    body = ''.join(f'    - MutagenObjectType: ScriptObjectProperty\n      Name: {n}\n      Object: {f}:{E}\n' for n, f in sorted(PROPS[script]))
    body += '    - MutagenObjectType: ScriptObjectProperty\n      Name: PlayerRef\n      Object: 000014:Skyrim.esm\n'
    write(f'esp/Quests/{eid} - {fid}_{E}.yaml',
          f"FormKey: {fid}:{E}\nEditorID: {eid}\nVirtualMachineAdapter:\n  Scripts:\n  - Name: {script}\n    Properties:\n{body}  FileName: ''\n"
          f"Name:\n  TargetLanguage: English\n  Value: {name}\nFlags:\n- StartGameEnabled\nNextAliasID: 0\n")
write('esp/RecordData.yaml', f'ModKey: {E}\nGameRelease: SkyrimSE\nModHeader:\n  Flags:\n  - Small\n  Author: itsPigeon2000\n'
      '  Description: Mantella and OStim together - scene flows from your animation packs, positions, talking during scenes and bystander comments.\n'
      '  MasterReferences:\n  - Master: Skyrim.esm\n    FileSize: 0\n  - Master: Update.esm\n    FileSize: 0\n')
write('esp/spriggit-meta.json', json.dumps({'PackageName': 'Spriggit.Yaml.Skyrim', 'Version': '0.40.0', 'Release': 'SkyrimSE', 'ModKey': E}, indent=2))


def g(n):
    return {'mod': E, 'formid': '0x' + gid[n].lstrip('0')}


S = [
    {'name': 'Scene flows', 'tooltip': 'Build scenes from your animation packs (needs Build Flows.cmd).', 'type': 'toggle', 'defaultValue': True, 'variable': g('MAE_FlowsEnabled')},
    {'name': 'Finish at excitement', 'tooltip': "A pack's finish scene starts when the man's excitement reaches this.", 'type': 'slider', 'defaultValue': 90, 'valueStep': 5, 'minValue': 50, 'maxValue': 100, 'variable': g('MAE_FlowFinishExcitement')},
    {'name': 'Scene messages', 'tooltip': 'Corner messages when a new animation set starts or a position is requested.', 'type': 'toggle', 'defaultValue': False, 'variable': g('MAE_NotifyScene')},
    {'name': 'Live scene lines', 'tooltip': 'Tell Mantella about position changes, pace and climaxes during scenes.', 'type': 'toggle', 'defaultValue': True, 'variable': g('MAE_LiveSceneLines')},
    {'name': 'Talk chance per excitement band', 'tooltip': 'Chance she speaks when she warms up, gets into it, or gets close; also the climax coin flip.', 'type': 'slider', 'defaultValue': 0.5, 'valueStep': 0.05, 'minValue': 0, 'maxValue': 1, 'variable': g('MAE_TalkBandChance')},
    {'name': 'Seconds between spoken reactions', 'tooltip': 'At most one spoken scene reaction per this many seconds.', 'type': 'slider', 'defaultValue': 40, 'valueStep': 5, 'minValue': 10, 'maxValue': 180, 'variable': g('MAE_TalkGap')},
    {'name': 'Dirty talk for forward NPCs', 'tooltip': 'Forward NPCs may talk dirty during scenes.', 'type': 'toggle', 'defaultValue': True, 'variable': g('MAE_DirtyTalk')},
    {'name': 'Bystander comments', 'tooltip': 'Conversation members watching the scene comment now and then.', 'type': 'toggle', 'defaultValue': True, 'variable': g('MAE_BystanderComments')},
    {'name': 'Bystander chance when calm', 'tooltip': 'Chance per climax at arousal 0.', 'type': 'slider', 'defaultValue': 0.25, 'valueStep': 0.05, 'minValue': 0, 'maxValue': 1, 'variable': g('MAE_BystanderChance')},
    {'name': 'Bystander extra chance at peak', 'tooltip': 'Added to the chance at arousal 100.', 'type': 'slider', 'defaultValue': 0.25, 'valueStep': 0.05, 'minValue': 0, 'maxValue': 1, 'variable': g('MAE_BystanderArousalChance')},
    {'name': 'Never force-start a scene', 'tooltip': "NPCs at peak arousal beg but never start a scene without the player's yes.", 'type': 'toggle', 'defaultValue': True, 'variable': g('MAE_NeverForceStart')},
    {'name': 'Default temperament', 'tooltip': 'For NPCs without their own setting. Set per NPC with the hotkey.', 'type': 'dropdown', 'defaultIndex': 0, 'options': ['Auto', 'Reserved', 'Bold', 'Forward'], 'variable': g('MAE_TemperDefault')},
    {'name': 'Auto judges lust from', 'tooltip': "Mantella's appetite rating (OSL values until rated), or OSL Aroused values only.", 'type': 'dropdown', 'defaultIndex': 0, 'options': ['Appetite rating', 'OSL values only'], 'variable': g('MAE_TemperSource')},
    {'name': 'Setup reminder', 'tooltip': 'Remind at game launch while setup has not been run.', 'type': 'toggle', 'defaultValue': True, 'variable': g('MAE_SetupReminder')},
    {'name': 'Hotkey', 'tooltip': 'Aim at an NPC: set her temperament. Aim at nobody: run setup.', 'type': 'keymap', 'defaultKey': 199, 'variable': g('MAE_Hotkey')},
]
write('SKSE/Plugins/OStim/settings/Mantella Adult Expansion settings.json', json.dumps({'name': 'Adult Expansion', 'settings': S}, indent=1))

SRC = 'D:/coding/Mantella-Relationship-Bridge/SKSE/Plugins/MantellaSoftware/data/actions/'
for old, new in [('mantella_mrb_rate_positions.json', 'mantella_mae_rate_positions.json'), ('mantella_mrb_change_position.json', 'mantella_mae_change_position.json')]:
    d = json.load(open(SRC + old, encoding='utf-8'))
    d['identifier'] = d['identifier'].replace('mrb', 'mae')
    d['note'] = d['note'].replace('Mantella - Relationship Bridge', 'Mantella - Adult Expansion - OStim')
    write('SKSE/Plugins/MantellaSoftware/data/actions/' + new, json.dumps(d, indent=4))
print('records written:', len(G), 'globals,', len(Q), 'quests')
