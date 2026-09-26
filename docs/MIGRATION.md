# Migration status and backlog

Baseline before the restructure is tag **`pre-restructure`**. Every old path is recorded in `manifests/source-map.json`.

## Done (M0/M1)

| Step | Result |
| --- | --- |
| Stock GMod files (base/sandbox/terrortown gamemodes, lua/includes, vgui, menu, …) | **595 removed.** Each one matched Facepunch/garrysmod (45 differed only in CRLF, 4 had Facepunch-side engine-version edits, none were ours) |
| Ops one-shots and staging dirs in `lua/` | **417 files removed.** None was referenced by live code (checked transitively from autorun, addons and gamemodes) |
| Z-City | **765 files removed**, byte-identical to upstream `81aee51`. **127 local edits → `patches/zcity`**. **19 local additions → `addons/us1`** |
| ULX / ULib | ULib is upstream `147657e`, unmodified. ULX is upstream `987806a` plus 3 edits (`patches/ulx`) |
| AdvDupe2 | Pure upstream, now a Workshop dependency |
| eProtect | Vendor. External dependency (its loader carries a local compat wrapper, see dependencies.json) |
| ~48 custom addons and custom root `lua/` | Merged into `addons/us1` at identical virtual paths (no path collisions) |
| SolidMapVote | Kept inside `addons/us1` for now. The US1 round-end ballot (`zc_goobos/roundend.lua`) is our UI, but its data (pool, votes, nominations, RTV) still comes from SolidMapVote's server side. See M4 |
| Proof | `tools/build.py` output is **byte-identical** to the pre-restructure server for all 1,538 shipped files, except the 3 deliberate fixes below |

Deliberate code changes in M0/M1 (physical-path checks that broke when the addons merged):
- `zc_guilt_justice/roles.lua`: the `short_src` check now matches the virtual path suffix.
- `zc_scoreboard/cl_boot.lua` and `cl_controller.lua`: allow the scoreboard hook owner at `addons/us1/...`.

## M2 — karma unification (next; the owner's priority)

**Current state.** Four systems are loaded:
- Upstream `sv_guilt` (patched): the per-hit writer.
- `zc_guilt_justice` + `zc_karma_bounties`: the real ledger, through `J.Change`.
- `zc_justice_v3`: observe-only shadow, with per-bullet wrappers.
- Pat legacy (`sv_pat_guilt_overhaul.lua` is byte-identical to `zc_guilt_justice/legacy_server.lua` and loads twice), plus `zc_guilt_legacy` (UI only).

⚠ `zc_karma_loss_enabled` defaults to **0**, so karma never goes down unless the server cfg sets it.

**Target** (`addons/us1/lua/us1/modules/karma/`):
1. **Evidence:** killcam `ZCKillcam_Death` (`K.Classify`) is the only source of charges. First confirm it covers bullets, melee, explosives, fall/push, vehicles and fire.
2. **Pricing:**
   - Bounties' target-karma curve.
   - A single team-mode table (currently duplicated in bounties, ff_brain and v3 `modes.lua`).
   - Pat's self-defense window.
   - Extension points: wildwest multiplier, postmortem exclusion, seizure guard, admin max karma.
3. **Ledger:** `J.Change` is the only writer. Keep MetaSafety's hidden-round deferral, regen and join checks, and the MySQL `zb_guilt` store.
4. **UI:** the Justice `zc_guilt_action_v3` menu.
5. **Switches:**
   - `us1_karma_shadow 1`: log only, compared side by side with the old pipeline.
   - `us1_karma_autoban 0` until the owner approves the shadow numbers.
   - Loss becomes real when shadow is 0.
6. **Upstream per-hit pricing:** turn it off with a `US1.Wrap` override. Fix the upstream `hg_setkarma` bug (no target check; sends the admin's own karma).
7. **Then delete:**
   - `zc_guilt_legacy`, `sv_pat_guilt_overhaul.lua`, `legacy_server.lua`.
   - The v3 bridge, `zz_zcj_medical_verify.lua`, `zzz_zcj_ownership_repair.lua`.
   - `zc_combat_incident.lua`.
   - The duplicate client review code in `zc_karma_bounties.lua`.

## M3 — module migration (one feature group per PR)

Order: killcam → chat → admin → rounds → gameplay → ui → perf. For each group:
- Move it into `us1/modules/<name>` and add `_order.lua`.
- Replace retry timers and `zz_` names with `US1.OnReady`.
- Use `US1.Wrap` for overrides and `US1.Net.Receive` for receivers.
- Namespace hook IDs.
- Keep net strings, convars, ULX command names, entity/weapon classes and `data/` paths unchanged.

Known collisions to fix on the way (all listed in `manifests/check-baseline.json` → `hooks`):
- Duplicate Temp V code: `lua/sv_zc_tempv.lua` and `lua/autorun/server/sv_zc_tempv.lua`. Keep one.
- `ZB_InventoryChecked/"LootSpawn"`: `zc_hmcd_mutators` vs upstream `sv_lootspawn`.
- `GlassShards`.
- `ZCityGuiltReview_Prompt` is registered in 3 files.
- `hg.organism.AmputateLimb` is wrapped by both super_crusher and juggernaut.
- `hook.Call` (ulx_zchat_bridge) and `net.Incoming` (watchdog) are replaced globally.
- Perf: merge `zc_tick_budget`, `zc_perf_pass2`, `sv_tick_governor`, `zc_perf`, `zc_gcsmooth` and `zc_spikewatch` into one governor.
- Live trial/preview files still in autorun: `zcity_stealth_trial.lua`, `zc_scoreboard_successor_preview.lua`, `zc_chat_settings_preview_restore.lua`, `sv_zc_explosion_fragment_trial.lua`. Promote each one or remove it.
- 15 stale `addons/<old-name>/` path references (baseline → `paths`).

## M4 — map vote

Port SolidMapVote's server side (map pool, ballot, nominations, RTV and reroll; `sv_mapvote.lua`, `sv_net.lua`, `sv_hooks.lua`, `sv_reroll.lua`) into `us1/modules/mapvote`.
- Keep the net messages that `zc_goobos/roundend.lua` reads.
- Then delete `lua/solidmapvote` and its unused VGUI.
- Callers to repoint: `zc_goobos/roundend.lua`, `zc_killcam/sv_highlight.lua`, `zc_round_guard.lua`, `zc_round_summary.lua`, `sv_rtv_countdown.lua`, `zc_map_prevote.lua`, `zc_vote_manager.lua`, `zc_bots/sv_lowpop.lua`, `zc_scoreboard/cl_view.lua`.

## M5 — Glide and upstream bumps

- **Glide:** once Workshop Glide (3389728250 / 3389795738) is confirmed mounted, add the Glide globs to `exclude_from_build` for zcity.
- **Z-City upstream bumps:** bump the commit (upstream is ~3 months ahead at `5e17a76`) and rebuild. Any patch that fails to apply gets fixed by hand, or replaced with a US1 override.
