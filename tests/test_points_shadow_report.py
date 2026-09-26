"""Offline tests for tools/points_shadow_report.py (no server, no network)."""
import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('shadow', ROOT / 'tools/points_shadow_report.py')
shadow = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shadow)

LOG = [
    'L 09/26/2026 - 20:01:02: [Killcam] points would pay (shadow) mode=hmcd humans=4: 2 players, 14 ZP | '
    'Ann 5 ZP (combat 200/40, 0 heals); Bob; the "medic" 9 ZP (combat 0/40, 1 heal, clean)',
    'noise line',
    '[Killcam] points would pay (shadow) mode=tdm humans=2: 1 player, 40 ZP | Cat 40 ZP (combat 2400/40, 0 heals) [capped]',
    '[Killcam] points would pay (shadow): 1 player, 30 ZP | Old 30 ZP (combat 400/40, 1 heal)',
]


class ShadowReportTests(unittest.TestCase):
    def test_parses_new_and_old_lines_and_awkward_names(self):
        rounds = list(shadow.parse(LOG))
        self.assertEqual([r['mode'] for r in rounds], ['hmcd', 'tdm', '?'])
        self.assertEqual(rounds[0]['humans'], 4)
        self.assertEqual([p['name'] for p in rounds[0]['players']], ['Ann', 'Bob; the "medic"'])
        self.assertTrue(rounds[0]['players'][1]['clean'])

    def test_payout_matches_the_server_formula(self):
        s = dict(shadow.DEFAULTS)
        p = {'combat': 2400, 'heals': 6, 'clean': True}
        total, combat, heal, clean, capped = shadow.payout(p, s)
        self.assertEqual((combat, heal, clean), (60, 24, 3))   # heals capped at 4
        self.assertEqual((total, capped), (40, True))

    def test_report_counts_silent_players_as_zeros_and_replays_other_settings(self):
        rounds = list(shadow.parse(LOG))
        base = shadow.report(rounds, dict(shadow.DEFAULTS))
        hmcd = next(line for line in base.splitlines() if line.startswith('hmcd'))
        self.assertIn('      1      4', hmcd)  # 1 round, 4 seats (two players who earned nothing)
        richer = shadow.report(rounds, dict(shadow.DEFAULTS, heal=25, cap=150))
        self.assertIn('heal=25', richer)
        self.assertNotEqual(base, richer)


if __name__ == '__main__':
    unittest.main()
