"""Offline tests for tools/flowgen.py: the pure helpers and whole builds from small made-up OStim packs.

usage: py -3 test/test_flowgen.py
"""
import json, os, subprocess, sys, tempfile, unittest, zipfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOL = os.path.join(REPO, 'tools', 'flowgen.py')
sys.path.insert(0, os.path.join(REPO, 'tools'))
import flowgen  # noqa: E402


def stage(pose_tag, actions, *destinations, name=None):
    """One two-person OStim scene file's content."""
    scene = {'actors': [{'intendedSex': 'male'}, {'intendedSex': 'female'}], 'tags': [pose_tag],
             'actions': [{'type': a} for a in actions], 'navigations': [{'destination': d} for d in destinations]}
    if name:
        scene['name'] = name
    return scene


# Pack "Alpha": a three-stage missionary set, a two-stage cowgirl finish set and one excluded test scene.
# Pack "Beta": one missionary stage that leads on to Alpha's cowgirl (a link across packs only counts as a natural move).
ALPHA = {
    'AlphaMiss1': stage('missionary', ['vaginalsex'], 'AlphaMiss2', name='Alpha Missionary 1'),
    'AlphaMiss2': stage('missionary', ['vaginalsex'], 'AlphaMiss3'),
    'AlphaMiss3': stage('missionary', ['vaginalsex']),
    'AlphaCow1': stage('cowgirl', ['vaginalsex'], 'AlphaCow2', name='Alpha Cowgirl'),
    'AlphaCow2': stage('cowgirl', ['creampie']),
    'AlphaTest1': stage('doggystyle', ['analsex'], name='Alpha test pose'),
}
BETA = {'BetaMiss1': stage('missionary', ['vaginalsex'], 'AlphaCow1', name='Beta Missionary')}


def write_scenes(folder, scenes):
    os.makedirs(folder, exist_ok=True)
    for sid, content in scenes.items():
        with open(os.path.join(folder, sid + '.json'), 'w', encoding='utf-8') as f:
            json.dump(content, f)


def run_tool(*args):
    return subprocess.run([sys.executable, '-I', TOOL, *args], capture_output=True, text=True, timeout=120)


def read_json(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)


class Helpers(unittest.TestCase):
    def test_activity_takes_the_strongest_action(self):
        self.assertEqual(flowgen.activity_of({'kissing', 'vaginalsex', 'creampie'}), 'finish')
        self.assertEqual(flowgen.activity_of({'kissing', 'analsex'}), 'sex')
        self.assertEqual(flowgen.activity_of({'blowjob', 'handjob'}), 'oral')
        self.assertEqual(flowgen.activity_of({'handjob'}), 'manual')
        self.assertEqual(flowgen.activity_of({'hug'}), 'foreplay')

    def test_activity_idle_when_nothing_known(self):
        self.assertEqual(flowgen.activity_of(set()), 'idle')
        self.assertEqual(flowgen.activity_of({'sitting'}), 'idle')

    def test_furniture_family(self):
        cases = {'BedRoll': 'bed', 'alchemytable': 'alchemytable', 'EnchantingTable': 'enchantingtable',
                 'diningtable': 'table', 'counter': 'table', 'wardrobe': 'wardrobe', 'chair': 'chair', '': 'none'}
        for furniture_id, family in cases.items():
            self.assertEqual(flowgen.furniture_family(furniture_id), family, furniture_id)

    def test_nice_label(self):
        self.assertEqual(flowgen.nice_label('Leito Missionary 2'), 'Leito Missionary')
        self.assertEqual(flowgen.nice_label('$OStim2PCowgirlMF'), 'OStim: Cowgirl (MF)')
        self.assertEqual(flowgen.nice_label('$OStim3PLyingMFF'), 'OStim: Lying (MFF)')
        self.assertEqual(flowgen.nice_label(''), '')

    def test_pack_names(self):
        self.assertEqual(flowgen.folder_pack('BillyyTable2P'), 'Billyy')
        self.assertEqual(flowgen.folder_pack('DrG_LTNWall'), 'DrG_LTN')
        self.assertEqual(flowgen.folder_pack('Chair'), 'Chair')  # nothing left: the folder name stays
        self.assertEqual(flowgen.short_pack('[NoDelete] Billyy Animations for OStim Standalone'), 'Billyy Animations')

    def test_theme_key(self):
        self.assertEqual(flowgen.theme_key(('normal', False, False, 'romantic')), 'normal|-|-|romantic')
        self.assertEqual(flowgen.theme_key(('bigguy', True, True, 'dom')), 'bigguy|femdom|futa|dom')

    def test_qt_value(self):
        self.assertEqual(flowgen.qt_value('"X:\\\\Mods\\\\Skyrim"'), 'X:\\Mods\\Skyrim')
        self.assertEqual(flowgen.qt_value('@ByteArray(Caf\\xc3\\xa9)'), 'Caf\u00e9')
        self.assertEqual(flowgen.qt_value('Caf\\xe9'), 'Caf\u00e9')

    def test_load_json_tolerates_comments_and_trailing_commas(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, 'scene.json')
            with open(path, 'w', encoding='utf-8') as f:
                f.write('{\n  "name": "x", // a note\n  "tags": ["a",],\n}\n')
            self.assertEqual(flowgen.load_json(path), {'name': 'x', 'tags': ['a']})

    def test_pick_profile(self):
        with tempfile.TemporaryDirectory() as tmp:
            for name in ('Default', 'Other'):
                os.makedirs(os.path.join(tmp, name))
                open(os.path.join(tmp, name, 'modlist.txt'), 'w').close()
            os.makedirs(os.path.join(tmp, 'Empty'))
            instance = {'profiles': tmp, 'profile': 'Other'}
            self.assertEqual(flowgen.pick_profile(instance, 'Default'), 'Default')
            self.assertEqual(flowgen.pick_profile(instance, None), 'Other')
            self.assertEqual(flowgen.pick_profile({'profiles': tmp, 'profile': ''}, None), 'Default')
            with self.assertRaises(SystemExit):
                flowgen.pick_profile(instance, 'Empty')

    def test_pick_profile_unclear(self):
        with tempfile.TemporaryDirectory() as tmp:
            for name in ('One', 'Two'):
                os.makedirs(os.path.join(tmp, name))
                open(os.path.join(tmp, name, 'modlist.txt'), 'w').close()
            with self.assertRaises(SystemExit):
                flowgen.pick_profile({'profiles': tmp, 'profile': ''}, None)
            os.remove(os.path.join(tmp, 'Two', 'modlist.txt'))
            self.assertEqual(flowgen.pick_profile({'profiles': tmp, 'profile': ''}, None), 'One')


class Builds(unittest.TestCase):
    def check_catalogue(self, cat, alpha, beta):
        self.assertEqual(cat['int']['setcount'], 3)
        self.assertEqual(cat['stringList']['packname'], [alpha, beta])
        self.assertEqual(cat['intList']['packstart'], [0, 2])
        self.assertEqual(cat['stringList']['setstages'], ['alphacow1,alphacow2', 'alphamiss1,alphamiss2,alphamiss3', 'betamiss1'])
        self.assertEqual(cat['stringList']['setlabel'], ['Alpha Cowgirl', 'Alpha Missionary', 'Beta Missionary'])
        self.assertEqual(cat['intList']['setrank'], [3, 2, 2])
        self.assertEqual(cat['intList']['finishsets'], [0])
        self.assertEqual(cat['intList']['setcango'], [0, 0, 0])
        self.assertNotIn('alphatest1', cat['stringList']['sceneid'])
        poses = cat['stringList']['poses']
        missionary, cowgirl = poses.index('missionary'), poses.index('cowgirl')
        self.assertEqual(cat['intList']['moveweight'][missionary * len(poses) + cowgirl], 1)
        self.assertTrue(all(k == k.lower() for section in cat.values() for k in section))

    def test_vortex_build_packs_a_zip(self):
        with tempfile.TemporaryDirectory() as tmp:
            data = os.path.join(tmp, 'Data')
            write_scenes(os.path.join(data, 'SKSE', 'Plugins', 'OStim', 'scenes', 'Alpha2P'), ALPHA)
            write_scenes(os.path.join(data, 'SKSE', 'Plugins', 'OStim', 'scenes', 'BetaBed'), BETA)
            out, zip_path = os.path.join(tmp, 'out'), os.path.join(tmp, 'zips', 'flows.zip')
            result = run_tool('--data', data, '--out', out, '--zip', zip_path)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(os.path.exists(out))
            with zipfile.ZipFile(zip_path) as z:
                names = set(z.namelist())
                cat = json.loads(z.read('SKSE/Plugins/StorageUtilData/MantellaAdultExpansion/flows.json'))
                first = json.loads(z.read('SKSE/Plugins/OStim/sequences/MAEF_S1.json'))
            self.assertIn('flows-report.txt', names)
            self.assertIn('SKSE/Plugins/OStim/sequences/MAEF_S3.json', names)
            self.check_catalogue(cat, 'Alpha', 'Beta')
            self.assertEqual(first, {'scenes': [{'id': s, 'duration': 25.0} for s in ('AlphaCow1', 'AlphaCow2')],
                                     'tags': ['mrbflow']})

    def test_mo2_build_reads_enabled_mods_and_replaces_old_sequences(self):
        with tempfile.TemporaryDirectory() as tmp:
            write_scenes(os.path.join(tmp, 'mods', 'Alpha Pack', 'SKSE', 'Plugins', 'OStim', 'scenes'), ALPHA)
            write_scenes(os.path.join(tmp, 'mods', 'Beta Pack', 'SKSE', 'Plugins', 'OStim', 'scenes'), BETA)
            write_scenes(os.path.join(tmp, 'mods', 'Off Pack', 'SKSE', 'Plugins', 'OStim', 'scenes'),
                         {'OffMiss1': stage('missionary', ['vaginalsex'], 'OffMiss2'), 'OffMiss2': stage('missionary', ['vaginalsex'])})
            os.makedirs(os.path.join(tmp, 'profiles', 'Default'))
            with open(os.path.join(tmp, 'profiles', 'Default', 'modlist.txt'), 'w', encoding='utf-8') as f:
                f.write('# comment\n+Beta Pack\n+Alpha Pack\n-Off Pack\n')
            out = os.path.join(tmp, 'mods', 'Flows')
            stale = os.path.join(out, 'SKSE', 'Plugins', 'OStim', 'sequences', 'MAEF_S99.json')
            os.makedirs(os.path.dirname(stale))
            open(stale, 'w').close()
            result = run_tool('--mo2', tmp, '--out', out, '--seconds', '10')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('Refresh Mod Organizer 2 and enable "Flows"', result.stdout)
            self.assertFalse(os.path.exists(stale))
            cat = read_json(os.path.join(out, 'SKSE', 'Plugins', 'StorageUtilData', 'MantellaAdultExpansion', 'flows.json'))
            self.check_catalogue(cat, 'Alpha Pack', 'Beta Pack')
            self.assertEqual(cat['int']['stageseconds'], 10)

    def test_no_usable_scenes_fails_without_writing(self):
        with tempfile.TemporaryDirectory() as tmp:
            data = os.path.join(tmp, 'Data')
            write_scenes(os.path.join(data, 'SKSE', 'Plugins', 'OStim', 'scenes'), {'Solo': {'actors': [{}], 'actions': []}})
            out = os.path.join(tmp, 'out')
            result = run_tool('--data', data, '--out', out)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('No usable two-person OStim scenes', result.stderr)
            self.assertFalse(os.path.exists(os.path.join(out, 'SKSE')))

    def test_exactly_one_source_is_required(self):
        result = run_tool('--mo2', 'x', '--data', 'y')
        self.assertEqual(result.returncode, 2)
        self.assertIn('give one of --auto, --mo2 or --data', result.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
