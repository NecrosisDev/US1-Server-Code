# Final pre-deploy review, 2026-09-26 (f4f5a8d..HEAD)

The review ran in three parts: the killcam viewer and delivery; the GoobOS round-end, death and observer panels; and the Z-City patches plus the tempv deletion. Every finding was re-checked against the code before any fix.

## Fixed
| Sev | Where | Problem | Fix |
|---|---|---|---|
| High | `autorun/server/zc_killcam_viewer_delivery.lua` | With 4 transfers already running, a busy server dropped viewer requests. Each dropped request still used one of the client's 3 tries, so after a VERSION change most clients ended up with no killcam until they reconnected. | Busy requests wait in a queue, which a 0.5 s timer drains. Players who have already acked this VERSION are skipped. |
| Med | `viewer_parts/cl_part_09.lua` | Esc could close the round replay instead of closing chat, because hook order is undefined. | Esc is left to ZChat while chat is open. |
| Low | `cl_part_09.lua` | While the scoreboard was up, clicks could still hit the hidden controls. | `R.hitN = 0` before the scoreboard early-return. |
| Low-Med | `zc_goobos/deathpanel.lua` | A reply that was already in flight could show "That didn't go through" after a forgive or report that worked. | Replies that arrive within 0.25 s of the action are ignored. |
| Low | `deathpanel.lua` | The 3 s quiet window swallowed the popup for a new case, e.g. after a quick second death. | The window only applies while an action is pending. |
| Low | `zc_goobos/roundend.lua` | The pre-vote re-ask loop sent a request every 3 s all intermission when there was no pool. | It stops once the server has answered. |

## Open, not fixed
- **Owner decision:** keys 1–9 cast map votes for living players whenever a ballot is open and the side panel shows, including during the preparation phase (`roundend.lua` `aliveMapKeys`). Recommendation: only after the round ends.
- An upstream bug in `sv_blood.lua:168`: `GetBonePosition(LookupBone(...))` gets a nil bone after a model change. It predates this range.
- Possible one-frame flicker of the blindflash light while the replay inset is open (the `cl_screeneffects` patch). Check it in game.
- Performance nits in the killcam: per-frame `Color`/`Vector` allocations in the HUD and the cavity loop, and the `R.TW` cache growing with every clock string.
- Unbalanced `cam.IgnoreZ`/model matrix if the wound FX errors mid-draw. Low risk.
- The round-end cursor re-assert fights any other code that turns the cursor off every frame. It converges.

## Verified
- The assembled viewer compiles in LuaJIT.
- 22 tests pass.
- `build.py --check` is clean, with all patches applying.
- The viewer VERSION was re-stamped.
- The tempv deletion leaves no dangling references.
