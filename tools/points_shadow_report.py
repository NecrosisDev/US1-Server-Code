"""Read killcam points shadow-log lines and replay them under any payout settings.

The killcam points faucet (addons/us1/lua/zc_killcam/sv_points.lua) ships in shadow mode: every round end it prints
what it WOULD pay, and pays nothing. This reads those lines from server console logs and answers the balance
questions with the server's own rounds instead of guesses (docs/POINTS_BALANCE.md):

  * how much a player earns per round, per mode, at the median and the 90th percentile
  * how much of it comes from combat, from healing, from the clean-round bonus
  * how often the per-round cap bites
  * what all of that WOULD have been under different settings (--rate, --heal, --healcap, --clean, --cap)

Offline and read-only. Usage:
  python tools/points_shadow_report.py console.log [more.log ...]
  python tools/points_shadow_report.py console.log --heal 10 --cap 60
"""
import argparse
import pathlib
import re
import statistics
import sys
from collections import defaultdict

# "[Killcam] points would pay (shadow) mode=hmcd humans=12: 3 players, 20 ZP | a 5 ZP (combat 200/40, 0 heals); ..."
# Lines from before mode=/humans= existed are read too; their mode is "?".
HEADER = re.compile(r'\[Killcam\] points (?:PAID|would pay \(shadow\))(?: mode=(?P<mode>\S+) humans=(?P<humans>\d+))?: [^|]*\| (?P<body>.*)$')
ENTRY = re.compile(r'^(?P<name>.*) (?P<zp>\d+) ZP \(combat (?P<combat>\d+)/(?P<rate>\d+), (?P<heals>\d+) heals?(?P<clean>, clean)?\)'
                   r'(?P<capped> \[capped\])?(?: \[refused: .*\])?$')
DEFAULTS = {'rate': 40, 'heal': 6, 'healcap': 4, 'clean': 3, 'cap': 40}


def parse(lines):
    """Yield one dict per round: {'mode', 'humans', 'players': [{name, combat, heals, clean, zp}]}."""
    for line in lines:
        m = HEADER.search(line)
        if not m:
            continue
        players, pending = [], ''
        # Entries are joined with "; ", which a player name may also contain: a piece that does not parse on its own
        # is carried into the next one until it does.
        for part in m.group('body').split('; '):
            candidate = pending + '; ' + part if pending else part
            e = ENTRY.match(candidate.strip())
            if not e:
                pending = candidate
                continue
            pending = ''
            players.append({'name': e.group('name'), 'combat': int(e.group('combat')), 'heals': int(e.group('heals')),
                            'clean': e.group('clean') is not None, 'zp': int(e.group('zp'))})
        yield {'mode': m.group('mode') or '?', 'humans': int(m.group('humans') or 0), 'players': players}


def payout(p, s):
    """What one player's round pays under settings `s` - the same formula as P.Owed in sv_points.lua."""
    combat = p['combat'] // max(s['rate'], 1)
    heal = min(p['heals'], s['healcap']) * s['heal']
    clean = s['clean'] if p['clean'] else 0
    total = combat + heal + clean
    capped = s['cap'] > 0 and total > s['cap']
    return (min(total, s['cap']) if capped else total), combat, heal, clean, capped


def pct(values, q):
    if not values:
        return 0
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, max(0, round(q * (len(ordered) - 1))))]


def report(rounds, s):
    by_mode = defaultdict(lambda: {'rounds': 0, 'seats': 0, 'pay': [], 'combat': 0, 'heal': 0, 'clean': 0, 'capped': 0})
    for r in rounds:
        m = by_mode[r['mode']]
        m['rounds'] += 1
        earners = 0
        for p in r['players']:
            total, combat, heal, clean, capped = payout(p, s)
            m['pay'].append(total)
            m['combat'] += combat
            m['heal'] += heal
            m['clean'] += clean
            m['capped'] += 1 if capped else 0
            earners += 1
        # Players who earned nothing are not printed by the server, but they sat in the round: count them as zeros.
        missing = max(r['humans'] - earners, 0)
        m['pay'].extend([0] * missing)
        m['seats'] += max(r['humans'], earners)
    out = []
    out.append('settings: ' + ', '.join(f'{k}={v}' for k, v in s.items()))
    out.append(f"{'mode':<14}{'rounds':>7}{'seats':>7}{'mean':>7}{'median':>7}{'p90':>6}{'max':>6}  share combat/heal/clean   capped")
    for mode, m in sorted(by_mode.items(), key=lambda kv: -kv[1]['rounds']):
        total = m['combat'] + m['heal'] + m['clean']
        share = (f"{100 * m['combat'] / total:4.0f}%/{100 * m['heal'] / total:3.0f}%/{100 * m['clean'] / total:3.0f}%" if total else '     -')
        mean = statistics.fmean(m['pay']) if m['pay'] else 0
        out.append(f"{mode:<14}{m['rounds']:>7}{m['seats']:>7}{mean:>7.1f}{statistics.median(m['pay']) if m['pay'] else 0:>7g}{pct(m['pay'], 0.9):>6}"
                   f"{max(m['pay'], default=0):>6}  {share:<24}{m['capped']:>6}")
    return '\n'.join(out)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('logs', nargs='+', type=pathlib.Path)
    for key, value in DEFAULTS.items():
        ap.add_argument('--' + key, type=int, default=value)
    args = ap.parse_args(argv)
    lines = []
    for path in args.logs:
        lines.extend(path.read_text(encoding='utf-8', errors='replace').splitlines())
    rounds = list(parse(lines))
    if not rounds:
        print('no "[Killcam] points" lines found - is zc_killcam_points at 1 (shadow) or 2?', file=sys.stderr)
        return 1
    print(report(rounds, {k: getattr(args, k) for k in DEFAULTS}))
    return 0


if __name__ == '__main__':
    sys.exit(main())
