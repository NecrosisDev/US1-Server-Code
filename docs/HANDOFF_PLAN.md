# US1 implementation plan: orchestrator handoff

**Audience:** an orchestrating agent (Fable) and the subagents it dispatches. **Owner:** the server owner (a designer;
answers in plain language, tests on the live server). **State:** written 2026-09-26 at `e097941` + the commit that adds
this file, branch `claude/hopeful-dirac-nsfltg`. Everything below is self-contained: you do not need the conversation
that produced it.

Owner-facing summary of the same plan (read-only for you if you cannot open it):
https://claude.ai/code/artifact/7af0b709-9398-4308-acb4-1bac60b33b92. Approved UI mockups: `docs/design/replay/`.

**This file is authoritative for execution.** If it disagrees with the code, the code wins: stop, verify, and fix
this file in the same commit.

---

## 1. How to run this plan

1. Read, in order: `CLAUDE.md`, `docs/ARCHITECTURE.md`, this file, `docs/MIGRATION.md`.
2. Set up the tools (section 4.1). Run the standard verification (section 4.2) once on a clean checkout: it must pass
   before you change anything.
3. Work through the phases in order (section 5). Inside a phase, dispatch work packages (WPs) to implementer
   subagents following the dependency and file-ownership rules (section 5.1).
4. Every WP ends with: the standard verification, an adversarial review subagent (Appendix A) for WPs marked
   **review**, and one commit per WP (or per coherent step) pushed to the branch.
5. **Owner gates** (`GATE n`) end each phase: produce the live drop, hand the owner the checklist and report
   template (section 6), and **stop until the owner reports back**. Never assume a gate passed. A failed gate
   returns to the WP that caused it.
6. Keep the status table (Appendix E) current in the same commits as the work.
7. **Stop and ask the owner** (one short, plain-language message, all questions in one block) when:
   - a decision is listed as owner-reserved (section 7) and not yet answered;
   - anything would change gameplay damage, accuracy, or who can see what (yaw physics, fairness defaults,
     clip visibility, removing the aim-assist tester lock);
   - the live drift audit (WP-1.0) finds changed live files;
   - a gate fails twice, or a fix would widen a WP beyond its files.

Branch and git: work on `claude/hopeful-dirac-nsfltg` unless the owner names another. Push with
`git push -u origin <branch>`. **Do not open a pull request unless the owner asks.** Use your session's commit
attribution rules. Never force-push.

---

## 2. Facts the code depends on

These were established by reading the code; each has bitten this project once.

### 2.1 Repository and build
- Custom code: `addons/us1/` (one addon, virtual paths preserved). Upstream Z-City / ULX / ULib are pinned commits
  plus unified-diff patches in `patches/<upstream>/`, assembled by `tools/build.py` into
  `dist/garrysmod/addons/{zcity,ulx,ulib,us1}`. Pins: `manifests/dependencies.json` (Z-City
  `81aee519709836114bd10f1a23210b0c2db59f5e`).
- `manifests/source-map.json` maps every old live path to its repo path with a disposition. Counts:
  834 `removed-identical-to-upstream`, 595 `removed-stock-gmod`, 417 `removed-ops-oneshot`, 333 `moved`,
  223 `moved-from-addon`, 130 `upstream-local-edit-as-patch`, 27 `vendor-external`, 19 `moved-zcity-addition`,
  18 `vendor-workshop`, 2 `removed-merged-addon-manifest`, 2 `deleted`, 1 `moved-license`.
- The repo is **source only**: `.gitignore` is an allowlist of source file types. Models, materials, sounds and other
  assets that live on the server were never in the repo.
- `addons/us1/lua/homigrad/organism/tier_0/sh_ballistics_v2.lua` is **our own file** at a Z-City virtual path (not a
  Z-City file): edit it directly, no patch.
- CI (`.github/workflows/ci.yml`): unit tests (with LuaJIT installed), build, strict check. It has passed on every
  push through `e097941`. Check it after each push (GitHub Actions for the branch).

### 2.2 Live server
- **Live still runs the old, pre-restructure tree** (~50 addon folders plus loose `garrysmod/lua/` files). Until the
  Phase 1 cutover, drops put every file back at its old path (`tools/drop.py`). The `US1.*` core
  (`addons/us1/lua/us1/core`, booted by `addons/us1/lua/autorun/us1_boot.lua`) is **not on live yet**: nothing
  shipped before the cutover may use `US1.*`.
- `manifests/live.json` records `layout` (`legacy` now) and `deployed_commit` (`f4f5a8d`, byte-identical to the live
  snapshot `e7f1b5a` apart from 3 deliberate path fixes). v5 (`f4f5a8d..e097941`) is built but **not uploaded yet**.
- The server is quiet (2 regular players on 2026-09-26), so Phases 0 and 1 can run back to back. Bots (`zc_bots`) can
  fill rounds for testing.
- Physics bullets (`PhysBullets_ReplaceDefault`) are **off** and stay off. Only the bow, crossbow and AGS-30 use
  physics bullets, per weapon. Physics-bullet flight is never recorded (the plugin's `PostEntityFireBullets` call is
  commented out).
- `zc_killcam_tape` (round recording) is **on** on live.
- Custom playermodels may lack ValveBiped organ bones; `e5f5bdc` made Z-City skip them instead of crashing.

### 2.3 The killcam viewer (the most fragile code here)
- `addons/us1/lua/zc_killcam/viewer_parts/cl_part_01..09.lua` are each `return string.sub([========[x ...]========], 2)`.
  `zc_killcam/cl_viewer.lua` concatenates parts 01..09 and compiles them as **one chunk**.
- That chunk sits at **198 of LuaJIT's 200 local variables** (the `do -- cl_life.lua` block peaks there). Any new
  file-scope `local` breaks the killcam for every player. New code goes inside `do ... end` blocks or as fields on
  `R` (round viewer), `V` (`ZCKillcamView`), `V.Wound`, and so on. `tests/test_tools.py` compiles the assembled chunk
  with LuaJIT and fails on a breach.
- `VERSION` (SHA-256 of the assembled source) is pinned in `zc_killcam/cl_viewer.lua` and
  `autorun/server/zc_killcam_viewer_delivery.lua`. After any viewer_parts edit run
  `python3 tools/viewer_version.py --write`; the tests and `drop.py` refuse a stale value.
- Line numbers in runtime errors refer to the assembled chunk (`python3 tools/viewer_version.py --source /tmp/v.lua`).
- Round-replay HUD: `cl_part_09.lua` `R.Paint*`, palette `R.UI`, unit `R.u = ScrH()/810`, hit areas via
  `R.Hit(x, y, w, h, act, arg)` handled in `R.Press`. Esc closes through Z-City's `OnShowZCityPause` hook (Z-City
  replaces the game menu, so `gui.IsGameUIVisible()` never turns true on Esc).
- Bullet camera: `cl_part_02.lua` (`V.ShotVisual`, `V.Penetration` with `D.Hits` organ crossings, `V.Wound` wound FX:
  wisps, temporary cavity, fragment gibs, soft organs). Cavity size follows wound ballistics: `r ~ K * d * v * sqrt(dE/dx)`,
  calibrated to gelatin figures (5.56 about 8 cm, 9 mm about 5 cm).

### 2.4 Hooks under ULib
- ULib's `hook.Call` runs priorities -2..2 in order (within one priority, in `pairs` order). A non-nil return from a
  hook at -1, 0 or +1 **stops the whole chain**, including the `HOOK_MONITOR_LOW` (+2) hooks after it. Only
  `HOOK_MONITOR_HIGH` (-2) hooks are guaranteed to run (they run first); monitor returns are ignored.
- Z-City's Lua bullets call `hook.Run("EntityFireBullets")` themselves (`homigrad/sh_luabullets.lua:943, 1028`) and
  run `PostEntityFireBullets` once per traced segment (`:835`). The phys-bullet hook (priority 0) returns `false`
  when phys bullets are on, which would skip every other priority-0 hook.
- Current `EntityFireBullets` hooks: `AXS_ZC.Nudge` (server `HOOK_HIGH`, modifies `data.Dir`; client mirror),
  `WD_SilentAim`, `WD_Aim_FireFollow`, `WD_Core_Fire` (watchdogs), `ZCKillcam.Shot` (recorder), `zc_bots_stats_shots`,
  `zc_bots_hearing` (all priority 0), Z-City `NPC_Boolets` and `あPhysBullets`. The codebase already uses
  `HOOK_MONITOR_HIGH or -2` in `sv_ulx_zchat_bridge.lua` and `zc_bots/sv_chat_listen.lua`.

### 2.5 Aim assist
- `autorun/server/sv_zc_crosshair.lua` (authoritative nudge), `autorun/client/cl_zc_aimassist.lua` (mirror + friction).
  Locked to one tester (`axs_zc_tester`, server-only). Caps: `axs_zc_nudge_max` 3 deg (0 = off for everyone), reach
  16 units. Never the head, never through cover, never moves the view. It currently judges misses with spheres on
  5-6 bones (`NUDGE_BODY`). The silent-aim watchdog needs 20 deg of view offset, so 3 deg nudges do not trip it.

### 2.6 Recording
- Life killcam clips: `zc_killcam/sv_recorder.lua` (30 Hz player rings, events, objects/gibs), `sv_clips.lua`
  (clip build), `sv_life.lua` (death sequences, saves), `sv_net.lua` (`K.CanUse`, `K.MayView`).
- Round tape: `zc_killcam/sv_tape.lua`, served by `sv_tapeserve.lua` (`K.TapeClass`, `K.TapeMayView`). Tracks and
  strides are in each chunk header: `p` poses (38 cols), `r` ragdolls, `e` events (10 cols), `s` bullet segments (10),
  `o` vitals (10: blood, bleed, pain, shock, consciousness, otrub, brain, adrenaline), `x` entity poses (8),
  `w` organ crossings (16). The client decoder (`cl_part_08.lua`) reads strides from the header, so new columns and
  tracks stay backward compatible. The round viewer (`cl_part_09.lua` `R.ConvStep`) currently **keeps only `e` and `s`**;
  `R.KINDS` filters index marks to `head end chunk who wep death model me`.
- `zc_killcam_tape_stats` reports recorder cost. Tapes are kept by disk budget (`zc_killcam_tape_mb`, 2000);
  `tapes/pinned.json` is honoured but nothing writes it yet.
- Pose flags (`sv_recorder.lua:25-29`) are full: bits up to 2048, then posture (x4096) and lean above it. Do not add
  flag bits.
- Bleed-out attribution data exists at death in `zb.HarmDoneDetailed[victim][attacker]` (Z-City guilt).
- Z-City damage internals (`dist/.../homigrad/organism/tier_1/sv_input.lua`): `PreTraceOrganBulletDamage` hook at
  `:52` (bullets, buckshot, slash, club, generic); `Trace_Blast` at `:63` has **no hook**; `velocityDamage` is a local at
  `:1606`, exported as `hg.velocityDamage` (`:1841`) but called directly at `:1848`.

### 2.7 CityLeak (GoobOS feed)
- `zc_goobos/feed_rules.lua` (limits), `sv_feed.lua` (requests, uploads), `sv_feed_store.lua` (SQLite tables
  `zc_feed_*`), `feed.lua` / `feed_ui.lua` (client). Posts have `kind` `post` / `clip` / `event` and a `clip` TEXT
  column (validated `^%d+_%d+$`, 24 chars); nothing creates clip posts yet. Watch opens the killcam save path
  (`zckc_clip`), which only works for clips the viewer may already see.
- Round ids are `%d_%02d` (`os.time()` + serial); `V.OpenRound(rid, cs, resume)` already opens a round at a time.

### 2.8 Editing conventions
- Many files use **CRLF**. Edit byte-preserving (read bytes, remember `\r\n`, normalise, edit, restore). Check with
  `git diff --numstat`: a whole-file count means you broke the line endings.
- GLua syntax (`!=`, `&&`, `||`, `!`, `//`, `continue`) is valid in GMod but not in plain LuaJIT: for such files
  glualint is authoritative; for plain-Lua files also compile with LuaJIT.
- Z-City patch regeneration (never hand-edit a `.patch`):
  ```
  F=lua/homigrad/<file>.lua                                          # path inside the zcity addon
  python3 tools/build.py                                             # dist = upstream + current patches
  git -C .cache/upstream/zcity show 81aee519709836114bd10f1a23210b0c2db59f5e:$F > /tmp/orig.lua
  cp dist/garrysmod/addons/zcity/$F /tmp/new.lua && <edit /tmp/new.lua>
  diff -u --label a/$F --label b/$F /tmp/orig.lua /tmp/new.lua > patches/zcity/$F.patch
  python3 tools/build.py --check
  ```

---

## 3. Hard rules

**Must**
- Keep the killcam viewer at or under 200 locals; re-stamp `VERSION` after any viewer_parts edit.
- Observers (recorders, watchdogs, stats) hook shared events at `HOOK_MONITOR_HIGH` and never return a value. Only
  hooks that change data run at `HOOK_HIGH`.
- Every new server net receiver: valid player, size cap, per-player rate limit, pcall; never trust a client-sent id,
  window or count. After the cutover use `US1.Net.Receive`.
- Every feature a phase adds has an off switch (a convar named in the WP). Rollback is re-uploading the previous drop.
- Pure logic (geometry, validation, statistics, encoders) goes in small functions with LuaJIT unit tests.
- Per-frame paint code reuses colours and tables.
- Keep the shipped compatibility surface: virtual paths, net message names, convars, ULX commands, entity and weapon
  classes, `data/` paths.
- Preserve line endings.

**Must not**
- Commit credentials, player data or live `.cfg` files. The GIPHY and VPN API keys are supplied on the server only.
- Add ops, probe or activate scripts under `addons/us1` (`tools/check.py` rejects them). One-off live scripts go in
  `tools/live/` and are uploaded by the owner.
- Edit upstream trees in place (use patches, or better an override in `addons/us1`).
- Change gameplay damage, turn physics bullets on, or remove the aim-assist tester lock without the owner.
- Create SSH keys or credentials, or try to reach the live server. The owner deploys.
- Push to another branch, force-push, or open a pull request unasked.

---

## 4. Tools and verification

### 4.1 Setup
```
curl -sSL -o /tmp/gl.zip https://github.com/FPtje/GLuaFixer/releases/download/1.29.0/glualint-1.29.0-x86_64-linux.zip
unzip -o /tmp/gl.zip -d ~/bin && export GLUALINT=~/bin/glualint
sudo apt-get install -y luajit      # or apt-get without sudo in a container
```

### 4.2 Standard verification (every WP, before its commit)
```
python3 -m unittest discover -s tests            # includes the assembled-viewer LuaJIT compile + VERSION check
python3 tools/viewer_version.py --check          # after any viewer_parts edit: --write first
GLUALINT=~/bin/glualint python3 tools/build.py --check
luajit -e "assert(loadfile('<changed plain-Lua file>'))"   # files without GLua-only syntax
git diff --numstat                               # line counts match the intended change
```
From WP-0.3 on, also `python3 -m unittest tests.test_lua_harness` (the stub harness).

### 4.3 Helpers already in the repo
- `tools/viewer_version.py`: print / `--write` / `--check` the viewer `VERSION`; `--source` writes the assembled chunk.
- `tools/drop.py`: builds `drops/live-drop-<base>-<head>.zip` from `deployed_commit..HEAD` at live paths, with
  `MANIFEST.txt` and `DELETE.txt`; `--mark-deployed` after the owner confirms. Verified: it reproduces the v5 drop byte
  for byte.
- `tools/build.py`, `tools/check.py` (see `docs/ARCHITECTURE.md`).

---

## 5. Work packages

### 5.1 Scheduling
- Phases run in order; each ends with an owner gate.
- **Single-writer files** (one WP at a time may edit them): `zc_killcam/viewer_parts/*` (and therefore `VERSION`),
  `zc_killcam/sv_recorder.lua`, `zc_killcam/sv_tape.lua`, `zc_goobos/roundend.lua`. WPs that share one run in
  sequence; the others may run in parallel.
- Review: WPs marked **review** get an adversarial review subagent (Appendix A) after implementation; confirmed
  findings are fixed before the WP commit.

| Phase | WPs | Parallel? | Gate |
| --- | --- | --- | --- |
| 0 Ship v5 | 0.1 review fixes, 0.2 missing-bone log, 0.3 stub harness, 0.4 drop | 0.2 and 0.3 in parallel after 0.1 | GATE 0 |
| 1 Cutover | 1.0 drift audit, 1.1 cutover tool, 1.2 rehearsal, 1.3 cutover, 1.4 restructured drops | 1.1 while waiting on 1.0 | GATE 1 |
| 2 Aim assist | 2.1 monitor hooks, 2.2 hitbox nudge, 2.3 assist record | 2.2 parallel with 2.1; 2.3 after both | GATE 2 |
| 3 Vehicles | 3.1 server detection + life track, 3.2 tape, 3.3 life replay draw, 3.4 round replay draw | 3.1/3.2 sequential (recorder, tape); 3.3/3.4 sequential (viewer) | GATE 3 |
| 4 Inspector v1 | 4.1 keep tracks, 4.2 inspector UI, 4.3 gap counter | sequential (viewer) | GATE 4 |
| 5 Recording | 5a.1-5a.4, then 5b.1-5b.6 | 5b.5 (armor research) in parallel with anything | GATE 5a, GATE 5b |
| 6 Director + CityLeak | 6.1 clip schema, 6.2 feed server, 6.3 tapeserve gate, 6.4 editor, 6.5 feed card | 6.1 first; 6.2/6.3 parallel; 6.4/6.5 after | GATE 6 |
| 7 Aim fairness | 7.1 live stats, 7.2 cap, 7.3 tuning/audit, 7.4 opt-in | 7.1 then 7.2; 7.3 parallel with 7.2 | GATE 7 |

### Phase 0: ship v5

**WP-0.1 Final review fixes** (review; files: whatever the findings touch)
- If `docs/reviews/2026-09-26-final-review.md` exists, start from its findings; otherwise run Appendix A on
  commits `81ad4cd`, `ab0f85c` (bullet camera, cavity: `cl_part_02.lua`, `cl_part_07.lua`) and `e097941`
  (round-replay HUD: `cl_part_09.lua`).
- Verify each finding against the code before fixing; record each as fixed / not a bug (why) in the review file.
- Accept: every confirmed finding fixed; standard verification green.

**WP-0.2 Missing-bone log** (files: `patches/zcity/lua/homigrad/organism/tier_0/sh_hitboxorgans.lua.patch`)
- In `ShootMatrix`, where `e5f5bdc` added `if not bone then continue end`, log once per model and bone before
  continuing:
  ```lua
  if not bone then
      hg.organism.MissingBones = hg.organism.MissingBones or {}
      local key = tostring(ent:GetModel()) .. "|" .. nameBone
      if not hg.organism.MissingBones[key] then
          hg.organism.MissingBones[key] = true
          MsgN("[US1] playermodel " .. tostring(ent:GetModel()) .. " has no bone " .. nameBone .. "; its organs are skipped")
      end
      continue
  end
  ```
- Regenerate the patch (section 2.8). Accept: build applies all patches; glualint clean.

**WP-0.3 Stub harness** (review; files: new `tests/lua/*.lua`, `tests/test_lua_harness.py`)
- Spec in Appendix B. Accept: scenarios pass on the current code; deliberately inserting a nil access into
  `R.PaintBar` makes the test fail; CI runs it.

**WP-0.4 Drop v5 and GATE 0**
- `python3 tools/drop.py` gives `drops/live-drop-f4f5a8d-<head>.zip`. Hand it to the owner with the GATE 0 checklist
  (section 6.2). After a pass: `python3 tools/drop.py --mark-deployed`, commit `manifests/live.json`.

### Phase 1: move live onto the repo's build

**WP-1.0 Live drift audit** (owner-assisted; files: new `tools/live/us1_live_hashes.lua`, `tools/drift.py`)
- Live may have been edited by hand since the snapshot (the owner applied at least one fix by hand). Anything
  changed on live and not ported would be lost by the cutover.
- `tools/live/us1_live_hashes.lua`: a one-off server script (not shipped) the owner uploads to `garrysmod/lua/`,
  runs with `lua_openscript us1_live_hashes.lua`, then deletes. It walks `lua/`, `addons/*/lua/`, `gamemodes/`
  with `file.Find` on the **`"MOD"`** path (the physical `garrysmod/` folder; `"GAME"` merges every addon into one
  virtual tree and would hide which folder a file is in), and writes `data/us1_live_hashes.txt` with
  `sha256<TAB>path` for every `.lua` file (`util.SHA256(file.Read(path, "MOD"))`, spread across ticks for 3000+ files).
- `tools/drift.py live_hashes.txt`: compares each live file with the snapshot (`git show e7f1b5a:<old path>`) and
  with the current repo mapping; prints drifted files (changed on live), files only on live (unknown), and files
  missing on live.
- **Stop and ask** if anything drifted: port each drift into the repo (or confirm it can be dropped) before WP-1.3.

**WP-1.1 Cutover tool** (review; files: new `tools/cutover.py`, tests)
- Spec in Appendix C. Core rule: **overlay** the built addons onto live and delete only listed stale source files.
  Never delete a folder that still holds files, never a `removed-stock-gmod`, `vendor-external` or `data/` / `cfg/`
  path, and `vendor-workshop` items only once the owner confirms the Workshop copies load.

**WP-1.2 Offline rehearsal** (files: `tools/cutover.py --rehearse`, tests)
- Rebuild the pre-restructure tree from `git show e7f1b5a` (plus any drift from WP-1.0), apply the cutover plan to it,
  then compute the resulting set of Lua virtual paths across `garrysmod/lua` and every `garrysmod/addons/*/lua`.
- Accept: the virtual Lua file set equals dist's (`dist/garrysmod/addons/*/lua` plus stock files); **zero** virtual
  paths provided by two different places; zero stock or vendor-external files deleted.

**WP-1.3 GATE 1: the cutover** (owner, quiet window). Checklist in section 6.3.

**WP-1.4 Restructured drops** (files: `tools/drop.py`, `manifests/live.json`, tests)
- After GATE 1: set `layout` to `restructured`, `deployed_commit` to the cutover commit. Add the restructured mode
  to `drop.py`: zip whole `dist/garrysmod/addons/<name>/` folders for each addon with changes since
  `deployed_commit` (us1 for `addons/us1`; an upstream addon when its patches or pin changed) plus `DELETE.txt` for
  files removed from those folders.
- From here on new code may use the `US1.*` core, and new modules go in `addons/us1/lua/us1/modules/<name>/` per
  `docs/ARCHITECTURE.md`.

### Phase 2: aim assist accuracy and transparency

**WP-2.1 Reliable observers** (files: `autorun/server/sv_watchdog_{aim,silentaim,core}.lua`,
`zc_bots/sv_diagnose.lua`, `zc_bots/sv_hearing.lua`; the `ZCKillcam.Shot` line in `zc_killcam/sv_recorder.lua`)
- Register each listed `EntityFireBullets` observer with `HOOK_MONITOR_HIGH or -2`. Audit each handler: it must
  return nothing on every path.
- Effect: they always run, before the nudge, so the watchdog judges the player's own aim and never scores an assisted
  shot. Accept: no handler returns a value; standard verification.

**WP-2.2 Engine-hitbox nudge** (review; files: `sv_zc_crosshair.lua`, `cl_zc_aimassist.lua`, new
`us1/modules/aimassist/sh_geom.lua` + `_order.lua`, LuaJIT tests)
- Pure geometry in `US1.AimGeom` (loaded on both realms): ray vs oriented box (`RayOBB`), closest point on an OBB to a
  ray, angle between directions. Unit-test with LuaJIT (hits, near misses, parallel rays, degenerate boxes).
- Algorithm (same on server and client):
  1. Candidates: alive players other than the shooter (NPCs if `axs_zc_npc`), using the ragdoll when present
     (`bodyOf`), whose bounding sphere passes within `reach` of the ray.
  2. For each hitbox `i` of set 0: `bone = GetHitBoxBone(i, 0)`, `m = GetBoneMatrix(bone)`,
     `mins, maxs = GetHitBoxBounds(i, 0)`, `group = GetHitBoxHitGroup(i, 0)`. Skip a hitbox without a matrix.
  3. If the unmodified ray hits any hitbox of any candidate: no nudge.
  4. Else, over chest and stomach hitboxes (`HITGROUP_CHEST` 2, `HITGROUP_STOMACH` 3): the closest point inside the
     box (inset 20%) to the ray. Miss distance at the target no more than `reach`, and angle no more than the degree cap.
     Pick the smallest angle; never head or neck.
  5. Line-of-sight trace to the point (existing). Keep the existing lag compensation block.
  6. A model with no usable hitboxes falls back to the old `NUDGE_BODY` spheres.
- Accept: unit tests; owner test at `net_fakelag 150` on a bot (GATE 2).

**WP-2.3 Assisted-shot record and tag** (files: `sv_zc_crosshair.lua`, `zc_killcam/sv_recorder.lua`,
`zc_killcam/sv_tape.lua`, `zc_killcam/sv_life.lua`, `zc_goobos/deathpanel.lua`, viewer part for the life overlay)
- `ZCKillcam.AmendShot(ply, deg, newDir)` in the recorder: updates the shot event the monitor-priority recorder
  just logged for `ply` (direction columns) and marks it assisted. The nudge calls it after changing `data.Dir`.
- Tape mark `assist {t, uid, v, deg}`; life clip hit events and death instances carry `assist` (max degrees, 1 decimal).
- Death panel and killcam life overlay show a grey tag: `assisted shot (+0.8°)`.
- Off switch: `axs_zc_nudge_max 0`. Accept: a nudged shot on a bot shows the tag in the victim's death panel; the
  watchdog logs nothing for it.

### Phase 3: vehicles in replays (single-writer: recorder, tape, viewer)

**WP-3.1 Detection + life-clip vehicle track** (review; files: `sv_recorder.lua`, `sv_clips.lua`)
- A vehicle is `ent.IsGlideVehicle` or an unparented `ent:IsVehicle()`. Track on `OnEntityCreated` (deferred a
  tick) and `PlayerEnteredVehicle`.
- Track: 10 Hz frames `{cs, x, y, z, p, y, r, scale}` like objects (`K.TrackObject` / `K.ObjectRows`), `k = "veh"`,
  not ended after 1 s at rest, at most 211 frames (the client's `G.GibAt` cap). Once per track: `m`, `sk`, bodygroups
  string, colour, and `wh = {{model, lx, ly, lz, lp, lyaw, lr, scale}}` read from `ent.wheels`.
- Seat events: `enter {cs, actor, vehicleTrack}` and `exit` in the clip events (not a pose flag).
- Off switch: `zc_killcam_vehicles 0`.

**WP-3.2 Round tape** (files: `sv_tape.lua`)
- `classify()` accepts Glide bodies. The `ent` mark gains `sk`, `bg`, `col`, `wh`. The existing `veh` enter/exit marks
  then start appearing.

**WP-3.3 Life replay drawing** (review; files: `cl_part_01.lua` `G.DrawGibs` area)
- `k == "veh"` rows: apply skin, bodygroups and colour; draw each wheel at its local offset (parented transform).
  Seated actors are placed in the vehicle between their enter and exit events.
- In a `do ... end` block or `G.*` fields; `VERSION` re-stamped.

**WP-3.4 Round replay drawing** (review; files: `cl_part_09.lua`, and `cl_part_08.lua` only if the decoder needs it)
- Add `ent`, `entgone`, `veh` to `R.KINDS`; adapt the `x` track in `R.ConvStep` the way `s` is adapted; draw owned
  ClientsideModels (`V.OwnReplayEntity`); seat actors from `veh` marks. Verify on live whether a seated player's
  recorded eye yaw is relative to the vehicle; if so add the vehicle yaw.
- Accept (GATE 3): a roadkill and a drive-by replay with car, wheels and seated driver in place in both replay types.

### Phase 4: damage inspector v1 (single-writer: viewer)

**WP-4.1 Keep the tracks** (files: `cl_part_09.lua`)
- `R.ConvStep` keeps `o` (vitals per actor, time series), `w` (organ crossings, resolved through `name` marks) and
  links `w` rows to their hit events; `R.KINDS` adds `dmg`, `boom`, `name`, `amputate`, `armor`, `otrub`.
  Old tapes keep working (strides from the header).

**WP-4.2 Inspector UI** (review; files: `cl_part_09.lua`; spec `docs/design/replay/Damage.dc.html`)
- Mode switch in the top bar: Watch / Direct a clip (disabled until Phase 6) / Inspect damage.
- Left: every hit, filter chips by kind (Bullet, Buckshot, Melee, Blast, Fire, Fall, Vehicle, Bleed); clicking a hit
  seeks to it and pauses. Right: attacker to victim, weapon, time; six fact cells per kind; the Phase 2 assist tag;
  body diagram with hit points; organ path with damage per organ; victim vitals for 20 s after the hit (blood,
  consciousness, pain) with "passes out" marked. A missing field reads "not recorded".
- Accept (GATE 4): bullet and knife hits show real numbers and organs; the vitals curve matches the replay.

**WP-4.3 Gap counter** (files: `cl_part_09.lua`, new `us1/modules/inspect/sv_gaps.lua`)
- When a "not recorded" field is shown, the client counts it and sends the counts at most once a minute
  (`US1.Net.Receive`, tiny payload, rate-limited). Staff command `us1_inspect_gaps` prints the ranking. It orders
  Phase 5b's work.

### Phase 5: recording upgrade

**5a (no Z-City patches; single-writer: recorder, tape, then viewer)**
- **WP-5a.1** Every recorder and tape listener on damage and bullet hooks (`EntityTakeDamage`, `HomigradDamage`,
  `EntityFireBullets`, `PostEntityFireBullets`, `PreTraceOrganBulletDamage`, `PlayerDeath`) moves to
  `HOOK_MONITOR_HIGH`; audit returns.
- **WP-5a.2** Widen the `o` row with `o2`, `pulse`, `heartstop`, `internalBleed`, `lungsfunction`, `poison1`-`poison4`
  (stride 10 to 18; still only on change, 2 Hz). Inspector shows drowning, cardiac arrest, poison onset and
  internal bleeding. Old tapes still decode.
- **WP-5a.3** At death, write `credit {uid, share, dmgtype}` on the `death` mark from `zb.HarmDoneDetailed[victim]`
  (largest harm share), replacing the 8 s last-attacker window for attribution in the inspector.
- **WP-5a.4** Buckshot: skip the 50 ms same-pair hit merge for `DMG_BUCKSHOT`; record the pellet count per shot.
- Off switch for 5a+5b recording additions: `zc_killcam_tape_detail 0`. GATE 5a: `zc_killcam_tape_stats` shows the
  recorder under 1 ms per tick with bots filling the server; inspector rows fill.

**5b (per-hit detail track)**
- **WP-5b.1** New tape track `h`, one row per real hit: `cs, victimSlot, attackerSlot, dmgBits, amount×10, hitgroup,
  pos xyz, normal xyz ×100, force, weapon id, flags` (stride declared in the header). Copy the life-clip ballistics
  (range, angle, calibre, diameter) and v2 penetration marks for bullets.
- **WP-5b.2** Blasts (patch): add `hook.Run("US1_BlastOrgan", org, box, amt, dmgInfo)` inside Z-City's `Trace_Blast`
  (`sv_input.lua:63`); record distance to the `boom` position, fragments that hit, organs.
- **WP-5b.3** Falls and ragdoll impacts (patch): route the direct call at `sv_input.lua:1848` through
  `hg.velocityDamage` and add `hook.Run("US1_VelocityDamage", ent, data)` at its top; record height, speed and
  broken bone.
- **WP-5b.4** Crush and vehicles: the monitor-priority `EntityTakeDamage` listener records `DMG_CRUSH` / vehicle
  damage (attacker = driver, inflictor = vehicle, speed from the vehicle velocity). No patch.
- **WP-5b.5** Armor (research first): find where Z-City subtracts armor (search `armors`, `sh_armorstuff.lua` and the
  armor patch); report the hook point, then record piece and absorbed amount.
- **WP-5b.6** Yaw, **shadow only**: add a yaw model to `sh_ballistics_v2.lua` behind a shadow flag that computes and logs
  yaw per leg (published yaw-onset depths per construction and calibre as a table, cited in comments) without
  changing damage; the viewer shows it as "estimated yaw". **Stop and ask** before any live damage change.
- GATE 5b: a test round with bullet, buckshot, knife, grenade, fall, car, poison and bleed-out fills every inspector
  row; recorder cost still under budget; a week of tapes fits `zc_killcam_tape_mb`.

### Phase 6: Director mode and CityLeak clips

**WP-6.1 Clip schema** (files: new `us1/modules/tapeclip/sh_clip.lua`, LuaJIT tests)
- `{v = 1, rid, ["in"] = cs, out = cs, shots = {{at, mode, follow, speed, move, cut}}, caption}`; 3 to 30 s,
  at most 8 shots; modes `free` / `follow` / `fp`; speeds 0.25 / 0.5 / 1 / 2 / 4; move `static` / `push` / `orbit`;
  cut `hard` / `ease`; caption up to 280 bytes. `US1.TapeClip.Validate(t)` returns a clean copy or nil + reason,
  used by server and client.

**WP-6.2 Feed server** (review; files: `zc_goobos/sv_feed.lua`, `sv_feed_store.lua`, `feed_rules.lua`)
- New post kind `tapeclip`, the clip JSON stored with the post. Server validates: round closed, window inside the
  round (from the tape index), schema valid; existing rate limits and reports apply.
- Pins: posting adds the round to `tapes/pinned.json`; pinned rounds capped at 25% of `zc_killcam_tape_mb` and 50
  rounds (oldest pin released first, with a log line); deleting a round's last clip post unpins it; staff can unpin.

**WP-6.3 Clip-scoped serving** (review; files: `zc_killcam/sv_tapeserve.lua`)
- New ids `tape:<rid>:clip:<postid>:index` and `tape:<rid>:clip:<postid>:<seq>`. The window comes from the stored
  post, never from the request. The clip index is filtered to the window (actors present, marks and deaths inside
  it); only chunks overlapping the window are served. Open to every player (no `TapeClass` gate), same throttle,
  same length cap.
- Accept: a request for a chunk outside the window is refused; the filtered index holds nothing from outside it.

**WP-6.4 Editor** (review; files: `cl_part_09.lua`; spec `docs/design/replay/Director.dc.html`)
- Direct mode: in/out handles (keys I / O), snap to previous/next kill, shot list (add at playhead; camera, speed,
  move, cut), 16:9 frame guide with thirds, Preview, caption, Post to CityLeak. Only while dead or spectating and only
  on finished rounds.

**WP-6.5 Feed card and playback** (files: `zc_goobos/feed_ui.lua`, `feed.lua`, `cl_part_09.lua`)
- `tapeclip` cards open `V.OpenRound` in clip mode: start at `in`, stop at `out`, play the shot list, then offer
  Replay / Close. Off switch: `zc_goobos_feed_clips 0`.
- GATE 6: a clip posted by one player plays for another who was not in the round, stops at `out`, cannot load
  outside its window, and survives a tape clean-up.

### Phase 7: aim assist tuning and fairness

**WP-7.1 Live shot stats** (review; files: new `us1/modules/aimassist/sv_stats.lua`, LuaJIT tests for the maths)
- In a monitor-priority shot observer: per human player (skip `IsBot()`), per weapon class (pistol, rifle, shotgun,
  sniper; from the weapon's ammo type), a ring of the last 100 shots: hit, nearest miss distance to a visible player,
  nudged or not.

**WP-7.2 Fairness cap** (files: `sv_zc_crosshair.lua`, `sv_stats.lua`)
- Human median per weapon class over players active in the last 30 minutes. The cap reads the player's
  **unassisted** hit rate (nudged hits count as misses): above the median the nudge and friction switch off for that
  player; they return below 90% of it.

**WP-7.3 Tuning and audit** (files: `sv_stats.lua`, optional `tools/tape_audit.py`)
- Default `axs_zc_nudge_reach` = the assisted players' 80th-percentile near miss (no more than 16). A staff command prints
  the stats; the optional tape audit compares with recorded bullets and poses.

**WP-7.4 Opt-in for everyone** (**stop and ask first**; files: `sv_zc_crosshair.lua`, `cl_zc_aimassist.lua`,
`zc_goobos/settings.lua`)
- Replace the tester lock with a GoobOS Settings toggle, off by default. Accept (GATE 7): over one week no assisted
  player's unassisted-equivalent hit rate sits above the human median for their class; no watchdog dossier cites an
  assisted shot.

---

## 6. Owner gates and live procedures

### 6.1 Giving the owner a drop
1. `python3 tools/drop.py` gives a zip in `drops/`. Send the zip, plus a short plain-language note: what changed,
   upload all files together, restart the map, the checklist, the report template.
2. After a pass: `python3 tools/drop.py --mark-deployed` and commit `manifests/live.json`.
3. Rollback: the owner re-uploads the previous drop (keep every drop zip until the next gate passes).

### 6.2 GATE 0 checklist (v5)
- [ ] Replays > Full rounds: a round opens; the Close button and Esc both close it; loading shows Cancel.
- [ ] Die to a bullet: the bullet camera shows soft wisps, a pulsing red cavity behind the bullet, fragment chips,
      no wireframes.
- [ ] A highlight in the round-end panel: the title stays crisp (no blur).
- [ ] Alive through a map-change round: numbered map choices appear; number keys vote.
- [ ] Consoles: no new Lua errors; the `[US1] playermodel ... has no bone` line names the bad model if it appears.
- [ ] One hour of bot rounds without new errors (quiet-server rule).

### 6.3 GATE 1 checklist (cutover)
1. Quiet window; full copy of `garrysmod/addons`, `garrysmod/lua`, `garrysmod/gamemodes` (not `data/`, `cfg/`).
2. Workshop dependencies from `manifests/dependencies.json` added to the server collection and loading.
3. Delete the files in the cutover `DELETE.txt`; overlay `install/garrysmod/...` onto the server; restart.
4. `us1_status` (server console): every module loaded, no errors. Boot console: no Lua errors.
5. One homicide round and one team round (bots are fine); open a replay; die once.
6. Rollback if anything fails: stop, restore the copy from step 1, restart (about 5 minutes).

### 6.4 Report template (ask the owner to paste this back)
```
Gate: <n>     Drop: <zip name>     Uploaded: <time>
Checklist: [x] ...  [ ] ...
Server console errors: <paste, or "none">
Client console errors: <paste, or "none">
Anything that looked or felt wrong:
```

---

## 7. Decisions

| Decision | Status |
| --- | --- |
| Physics bullets | Off, stays off (owner) |
| Cutover timing | Now: the server is quiet (owner) |
| Order of phases | As in this file (owner asked for this plan) |
| Aim assist: show "assisted" to victims, human-median cap, opt-in later, tester lock until the tuning numbers look right | Proposed and accepted in conversation; confirm at GATE 2 |
| Clips: anyone watches the clipped window only; posting pins the round; 30 s max; everyone can direct; directing only dead/spectating on finished rounds | Proposed and accepted in conversation; confirm at GATE 6 |
| Torn zone stays until the shot ends | Proposed; confirm at GATE 0 |
| Yaw changes damage | **Owner only**; shadow mode until then |
| Living players vote on the map with number keys | Open (built on; ask at GATE 0) |
| "You" halo hidden in the small replay box | Open (ask at GATE 0) |
| Tape disk budget (2000 MB) | Open (ask before GATE 5) |
| Spectator ESP obeys `zc_observer_mode 0` | Open |
| Map search box typeable in game | Open (owner tests at GATE 0) |

---

## Appendix A: adversarial review prompt (fill in the brackets)

> Adversarially review these changes to a Garry's Mod (GLua) server repo for bugs they INTRODUCED. Repo:
> [path]. Do not edit files; report only. Run `git show [commits] -- [paths]` and read the full surrounding code of
> every hunk (files may be CRLF). Built Z-City reference: `dist/garrysmod/addons/zcity/`. Structural facts:
> `docs/HANDOFF_PLAN.md` section 2 (viewer is one chunk at 198/200 locals; VERSION; ULib hook semantics).
> Hunt, with concrete evidence: (1) runtime errors: nil access, wrong GMod API signatures (DrawPoly clockwise winding,
> StartBeam/AddBeam counts, Push/Pop balance, IgnoreZ balance on early returns, RoundedBox radius as a number),
> NaN/inf; (2) logic bugs in the changed flows; (3) net security: unvalidated client input, missing rate limits,
> amplification; (4) per-frame allocations and O(n²) work in paint or tick code; (5) mismatch with the approved
> design or this plan. For each finding: file:line (the file's own line), defect, concrete failure scenario,
> confidence, minimal fix. List what you verified as fine. Under 1200 words.

## Appendix B: stub harness (WP-0.3)
- `tests/lua/gmod_stubs.lua`: real implementations where code does maths or compares: `Color`, `Vector` (+ - * /
  unary minus, `Dot`, `Cross`, `Length`, `LengthSqr`, `Distance`, `DistToSqr`, `Normalize`, `GetNormalized`,
  `Angle`, `IsZero`), `Angle` (`Forward`, `Right`, `Up`), `Matrix` (`Identity`, `Translate`, `Rotate`, `Scale`),
  `math.Clamp`, `Lerp`, `LerpVector`, `LerpAngle`, `ScrW`/`ScrH` (settable), `RealTime`/`CurTime`/`SysTime`
  (settable), `input.GetCursorPos`, `surface.GetTextSize` (returns `#text * 7, 12`), `IsValid`, `istable`/`isfunction`/
  `isstring`/`isnumber`/`isvector`, `string.*` GMod extras used (`Trim`, `Explode`), `table.*` extras (`Count`,
  `HasValue`). Everything else: a universal stub whose index and call return itself, with arithmetic metamethods
  returning 0. Record call counts for `render.*`, `surface.*`, `draw.*`.
- `tests/lua/harness_replay.lua`: load the assembled viewer (`tools/viewer_version.py --source`) under the stubs
  (`setfenv` / `_G` metatable), then override `V.StateAt`, `V.HasFlag` with fixture-backed versions and run:
  `R.Paint` in loading, failed and playing states at 1280x720, 1920x1080 and 3840x2160; `R.Press` on every hit area
  registered by the last paint; `V.Wound.Wake/Channel/Cavity/Fragments/Spray` on a synthetic bullet and body
  (with and without organs and v2 marks). Each scenario runs under `pcall`; any error fails with the scenario name.
- `tests/test_lua_harness.py`: runs the harness with LuaJIT; skips when LuaJIT is missing locally (CI installs it).

## Appendix C: cutover tool (WP-1.1)
- `tools/cutover.py [--live-hashes FILE] [--workshop-mounted] [--rehearse]` writes `drops/cutover-<head>/`:
  - `DELETE.txt`: old live paths whose disposition is `moved`, `moved-from-addon`, `moved-zcity-addition`,
    `removed-ops-oneshot`, `removed-merged-addon-manifest`, `moved-license`, `deleted`; plus `vendor-workshop` paths
    only with `--workshop-mounted`.
  - `install/garrysmod/addons/{zcity,ulx,ulib,us1}/`: a copy of dist, to overlay (copy over) the live folders.
  - `KEEP.txt`: `removed-stock-gmod`, `vendor-external`, and without `--workshop-mounted` `vendor-workshop`.
  - `CUTOVER.md`: the GATE 1 steps with the counts filled in, and the rollback.
- Asserts (fail the tool): no DELETE path has disposition `removed-stock-gmod` or `vendor-external`; no DELETE
  path under `garrysmod/data/` or `garrysmod/cfg/`; every moved file's new path exists in dist; with
  `--live-hashes`, every DELETE path's live hash equals the snapshot hash (a drifted file is never deleted silently).
- Never emits a folder deletion: empty folders are harmless, and old addon folders may still hold assets the repo
  never had.
- `--rehearse`: WP-1.2 (build the snapshot tree from `e7f1b5a`, apply, compare virtual paths).
- Tests: synthetic source-map rows, classification per disposition, the stock-never-deleted assert.

## Appendix D: data formats
- Current tape tracks and marks: section 2.6. Planned: `o` stride 18 (WP-5a.2), `death.credit` (WP-5a.3),
  `assist` mark (WP-2.3), `ent` mark `sk`/`bg`/`col`/`wh` (WP-3.2), track `h` (WP-5b.1).
- Life clip additions: `k = "veh"` object tracks with `wh` (WP-3.1), `enter`/`exit` events, `assist` on hit events.
- Clip post: WP-6.1 schema, stored as JSON in the post's `clip` column with `kind = "tapeclip"`.

## Appendix E: status

| WP | Status | Commit | Notes |
| --- | --- | --- | --- |
| 0.1 | Review running in the originating session; findings will land in `docs/reviews/2026-09-26-final-review.md` | | |
| 0.2 | Not started | | |
| 0.3 | Not started | | |
| 0.4 | Drop builds (`drops/live-drop-f4f5a8d-e097941.zip` matches the hand-built v5) | | Waiting on 0.1 |
| 1.0-7.4 | Not started | | |
