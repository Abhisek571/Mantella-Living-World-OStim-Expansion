"""Offline tests for test/validate.py's checks, on hand-written log lines.

usage: py -3 test/test_validate.py
"""
import os, sys, unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import validate  # noqa: E402

POSES = ['standing face to face', 'missionary', 'cowgirl']


def flow_set(why, idx, pose, rank, pack='a', furn='none', theme='normal|-|-|neutral', chain=1):
    return f'FLOW|SET|{why}|{idx}|pack={pack}|pose={pose}|rank={rank}|furn={furn}|theme={theme}|chain={chain}'


class SplitScenarios(unittest.TestCase):
    def test_lines_go_to_the_scenario_they_follow(self):
        rows = ['before anything', 'test|setup|finish=90', 'test|begin|Flow', 'one', 'test|begin|summary', 'two', 'three']
        finish_at, scenarios = validate.split_scenarios(rows)
        self.assertEqual(finish_at, 90.0)
        self.assertEqual(scenarios, [['flow', ['one']], ['summary', ['two', 'three']]])

    def test_no_scenarios(self):
        self.assertEqual(validate.split_scenarios(['a', 'b']), (None, []))


class FlowSets(unittest.TestCase):
    def test_a_clean_chain_passes(self):
        lines = [flow_set('opener', 0, 1, 1), flow_set('next', 1, 2, 2, chain=2), 'test|excite|A|95',
                 flow_set('finish', 5, 2, 3, pack='b')]
        self.assertEqual(validate.check_flow_sets('flow', lines, POSES, 90.0), ([], 3))

    def test_broken_rules_are_reported(self):
        lines = [flow_set('opener', 0, 1, 1), flow_set('next', 0, 1, 0, pack='b', theme='bigguy|-|-|dom'),
                 flow_set('finish', 5, 2, 2)]
        bad, sets = validate.check_flow_sets('flow', lines, POSES, 90.0)
        self.assertEqual(sets, 3)
        for problem in ('theme bigguy|-|-|dom not allowed', 'set reused', 'pack changed a -> b', 'theme changed',
                        'intensity dropped 1 -> 0', 'finish set has rank 2', 'finish before anyone reached excitement 90.0'):
            self.assertTrue(any(problem in b for b in bad), problem)

    def test_new_chain_needs_a_climax_and_requests_must_match(self):
        lines = [flow_set('opener', 0, 1, 1), flow_set('new chain', 1, 1, 1), 'FLOW|REQUEST|cowgirl', flow_set('request', 2, 1, 2)]
        bad, _ = validate.check_flow_sets('s', lines, POSES, None)
        self.assertIn('s: set 1 (new chain): new chain without her climax', bad)
        self.assertIn('s: set 2 (request): request for cowgirl played missionary', bad)

    def test_pose_cap_per_chain(self):
        lines = [flow_set('opener', 0, 1, 1), flow_set('next', 1, 1, 1), flow_set('next', 2, 1, 1)]
        bad, _ = validate.check_flow_sets('s', lines, POSES, None)
        self.assertEqual(bad, ['s: set 2 (next): pose missionary 3 times in a chain'])


class AffectionAndExpectations(unittest.TestCase):
    def test_restart_gap_and_missing_score(self):
        lines = ['AFFECT|CALL|x|sinceEnd=2.5', 'AFFECT|TIMING|start|x', 'AFFECT|TIMING|end|x']
        self.assertEqual(validate.check_affection_timing('a', lines),
                         ['a: AFFECT|CALL 2.5 s after the last end', 'a: affection scene ended without a score event'])

    def test_scored_or_stopped_early_is_fine(self):
        played = ['AFFECT|CALL|x|sinceEnd=7', 'AFFECT|TIMING|start|x', 'AFFECT|TIMING|end|x', 'AFFECT|SCORE|x|physical']
        stopped = ['AFFECT|TIMING|start|x', 'AFFECT|STOP|ended before the start', 'AFFECT|TIMING|end|x']
        self.assertEqual(validate.check_affection_timing('a', played), [])
        self.assertEqual(validate.check_affection_timing('a', stopped), [])

    def test_expected_lines(self):
        self.assertEqual(validate.check_expected('takeover', ['FLOW|TAKEOVER|x']), [])
        self.assertEqual(validate.check_expected('takeover', []), ['takeover: expected "TAKEOVER\\|" never logged'])
        self.assertEqual(validate.check_expected('unrated', ['EVENT|They have not been rated yet.']),
                         ['unrated: "EVENT\\|.* have not been rated yet\\." logged but should not be'])
        self.assertEqual(validate.check_expected('unknown-name: detail', ['anything']), [])


if __name__ == '__main__':
    unittest.main(verbosity=2)
