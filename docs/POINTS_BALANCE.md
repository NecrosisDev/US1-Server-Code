# Killcam points: balance evaluation

Evaluation of the killcam ZPoints faucet (`garrysmod/lua/zc_killcam/sv_points.lua`), written 2026-09-26.
The faucet is in **shadow mode** (`zc_killcam_points 1`): it logs what it would pay and pays nothing.

## TLDR

- **Right now ZPoints buy nothing.** Every shop item is free, and "unlimited" spending is on for everyone. Payout
  numbers can't be felt until that changes, so **deciding what ZP buys comes first**.
- **Heals were worth 5 kills. Now a heal is worth about 1 kill.** Six bandages used to out-earn a traitor's whole
  round. Heal went from 25 to 6 ZP, and paid heals per round from 6 to 4.
- **The per-round cap was worth more than an hour of play.** It went from 150 to 40 ZP (about one great traitor
  round), so one lucky round can't matter more than a whole session.
- **New: a 3 ZP clean-round bonus.** You get it for playing a traitor round with nothing counted against you. It is
  the "encouraged to be good" payment, and it rewards the ordinary good round that has no kill or heal.
- **Nobody is ever fined ZP.** Bad acts earn nothing (an unprovoked teamkill or an ambush pays 0). The karma system
  handles punishment. Losing currency is what makes people leave.
- **These are starting values, not final ones.** `tools/points_shadow_report.py` replays the server's own shadow log
  under any settings, so the final numbers come from real rounds. The rollout plan is below.

## What the economy looks like today

Numbers are from the source, with file references.

| | Value | Where |
|---|---|---|
| Shop | **every item free** (`ForSale` is never set) | `addons/zcity/lua/homigrad/libraries/pointshop/sh_pointshop.lua:17-20` |
| Unlimited spending | on for everyone while `hg_appearance_access_for_all` = 1 (the default) | `pointshop/sv_pointshop.lua:202`, `new_appearance/sh_shared.lua:42-52` |
| Catalog | 84 items. Cheapest 750, **median 1350**, most 7331. About 150k ZP for all of it | `new_appearance/sh_accessories.lua` |
| Only other sink | Arcade games (roughly zero-sum; blackjack edge about 2%) | `zc_goobos/arcade_rules.lua` |

**Faucets:**

| Faucet | Pays | Status |
|---|---|---|
| Round XP converted to ZP | about 1.9 ZP per round per player (4-15 XP / 5, at 10+ players) | **live** |
| Team-mode win XP | 3-6 ZP | live |
| Traitor-win XP | 6-10 ZP, **probably never pays** (it reads an undeclared global `traitor`, `sv_homicide.lua:1871`) | bug |
| Arcade Minesweeper | 5 ZP per board, 50 ZP/day at most | live |
| Playtime | 100 ZP per active hour | **shadow** (`zc_playtime 1`) |
| Killcam points | this document | **shadow** |

**Round structure:**
- Homicide rounds last up to 10 minutes and are about 38% of rounds on small maps. They have 1 traitor below 16
  players and 2 at 16 or more.
- Team and deathmatch modes run 3-5 minutes. There, kills are the whole game.
- A bandage turns up in about 7% of loot-box rolls, and any medicine in about 25%.

## Principles the numbers follow

1. **Reward what you want more of. Withhold rewards for what you want less of. Never fine.** An unprovoked teamkill
   or an ambush pays 0, and self-defence pays in full (`sv_intent.lua`). ZP is never taken away.
2. **One helpful act is worth about one kill.** Anyone can heal in any round, but kills mostly go to traitors and
   combat modes. Equal value makes helping a real choice without making it the easiest farm.
3. **Playtime is the backbone; killcam points are the flavour.** A steady per-hour faucet is fair to everyone.
   Killcam points should shape behaviour, not decide income, so they are sized at roughly a third of hourly
   earnings.
4. **No single round should be worth more than a session.** The cap should sit around one excellent round.
5. **Pay for the good round nobody sees.** Most good rounds contain no kill and no heal. The clean-round bonus is the
   only thing that rewards them.

## The numbers

| Setting | Was | Now (shadow) | Why |
|---|---|---|---|
| `zc_killcam_points_rate` | 40 | 40 | A clean kill (score about 200) is about 5 ZP, the same size as the win-XP faucet. Kept. |
| `zc_killcam_points_heal` | 25 | **6** | About one clean kill (principle 2). At 25, six bandages hit the old 150 cap. |
| `zc_killcam_points_healcap` | 6 | **4** | Four paid heals a round is a very good medic. Bandage-trading is capped at 24 ZP a round. |
| `zc_killcam_points_cap` | 150 | **40** | About one great traitor round (6 kills plus bonuses is about 32 ZP). 150 was more than an hour of playtime pay. |
| `zc_killcam_points_clean` | - | **3** | New. A traitor round you took part in, with nothing counted against you. |
| `zc_killcam_points_healcd` | 60 s | 60 s | Kept: one pay per healer/patient pair per minute. |
| `zc_killcam_points_healhurt` | - | 120 s | From the earlier pass: no pay for patching up someone you hurt. |

These settings are archived (`FCVAR_ARCHIVE`). If the server has already saved the old values, the new defaults
**do not apply by themselves**. Check with `zc_killcam_points_stats`.

### What a player would earn (model, before real data)

Assumptions:
- 8 rounds per hour, 3 of them homicide.
- 12 players and 1 traitor, so each player is the traitor in about 1 homicide round in 12.

| Source | Typical player | Helpful player | Notes |
|---|---|---|---|
| Round XP (live) | 15 | 15 | 1.9 × 8 |
| Clean-round bonus | 9 | 9 | 3 × 3 homicide rounds |
| Heals | 2 | 36 | about 0.1 vs 2 heals per homicide round × 6 ZP |
| Homicide combat | 9 | 9 | innocent kills are rare; one traitor round in four hours pays about 25 |
| Team/DM combat | **15-40?** | same | **The biggest unknown.** Kills are normal play there. The shadow log settles it. |
| **Killcam + XP** | **about 50-75 per hour** | **about 85-110 per hour** | |
| Playtime, if turned on | +100 per hour | +100 per hour | |

With playtime on, a regular earns about 150-175 ZP an hour. That is **a median item every 8-9 hours** and the whole
catalog in about 900 hours. Without playtime, it is about 20-25 hours per median item.

## Rollout plan

1. **Decide what ZP buys.** Put catalog items back on sale (`ForSale`), and decide whether
   `hg_appearance_access_for_all` stays on. Until then, any payout rate feels the same (worthless).
2. **Run shadow mode for two weeks** with the values above. Mode and player-count fields are now on every log line.
3. **Read it weekly:** `python tools/points_shadow_report.py <console logs>`. Try alternatives with flags such as
   `--heal 10 --cap 60`.

   | If the report shows | Then |
   |---|---|
   | Heals are over 40% of homicide pay | lower `heal` or `healcap` |
   | Team/DM mean per seat is over 2× homicide | combat in team modes is outweighing good conduct; consider a per-mode multiplier |
   | More than 5% of seats are capped | the cap is too low for normal good rounds; raise it |
   | Clean bonus is under 15% of homicide pay | raise `clean` (it is the "be good" signal, and it should be visible) |
   | Median homicide seat earns 0 | innocents feel ignored; raise `clean` |

4. **Flip `zc_killcam_points 2`**, and keep reading the report.

## Also found

- **Traitor-win XP most likely never pays.** It reads an undeclared global `traitor` (`sv_homicide.lua:1871`).
  Worth checking on the live server.
- **Blood bags and big consumables never fire `ZCity_MedicineUsed`** (they override `SecondaryAttack`), so those
  heals are never paid or logged.
- **Karma forgiveness never reaches a "round stars" system.** `ZC_RoundStars_*` hooks are fired, but nothing in the
  repo defines that system. The only listener is the killcam's staff ledger.
