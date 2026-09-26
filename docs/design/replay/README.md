# Round replay mockups (owner-approved canvas, 2026-09-26)

Copies of the boards on the owner's private canvas "Round Replay Redesign". Each file is a self-contained Design
Component page (`<x-dc>` markup + a small logic class); the markup and inline styles are the spec. They reference the
canvas runtime `./support.js`, so read them as source, do not expect them to render.

| File | Status | Built? |
| --- | --- | --- |
| `Current.dc.html` | The screen before the rebuild (reference only) | - |
| `Main.dc.html` | **Approved**: Watch mode (top bar, subject chip, map, players, kill feed, transport, shortcuts) | Yes, `e097941` (`cl_part_09.lua` R.Paint*) |
| `Loading.dc.html` | **Approved**: loading, buffering, failure and "paused because you spawned" states | Yes, `e097941` |
| `Director.dc.html` | Approved in principle: Direct a clip for CityLeak (in/out, shot list, caption, post) | No: Phase 6 |
| `Damage.dc.html` | Approved in principle: Inspect damage (hit list, facts, body diagram, organ path, vitals) | No: Phase 4 |

Layout unit: boards are 1440x810; the game scales by `ScrH()/810` (`R.Fonts` / `R.u`). Palette: `R.UI` in
`cl_part_09.lua`. Sample names and numbers in the boards are placeholders, not data.
