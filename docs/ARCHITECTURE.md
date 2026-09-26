# US1 architecture

## What ships

`python3 tools/build.py` writes `dist/garrysmod/addons/`:

| Addon | Built from | Edit it by |
| --- | --- | --- |
| `zcity` | `uzelezz123/Z-City` pinned commit + `patches/zcity/**.patch` | adding/changing a patch (prefer a US1 override instead) |
| `ulx` | `TeamUlysses/ulx` pinned commit + `patches/ulx/**.patch` | same |
| `ulib` | `TeamUlysses/ulib` pinned commit, unmodified | bump the commit |
| `us1` | `addons/us1/` in this repo | editing files directly |

Everything else (Workshop items, eProtect, compat GMAs) is listed in `manifests/dependencies.json` and mounted separately.
Pins live in `manifests/dependencies.json`. `dist/BUILD_INFO.json` records the commits, patch counts and a tree hash per addon.

Z-City must be output as the folder `zcity`: some code checks `addons/zcity/...` paths.

## Repository layout

```
addons/us1/            the one US1 code addon (all custom code)
  lua/autorun/us1_boot.lua   core entry point
  lua/us1/core/              US1 core library (see below)
  lua/us1/modules/<name>/    new-style modules (target home for everything in lua/zc_*)
  lua/zc_*/, lua/autorun/…   legacy US1 systems, moved here unchanged; migrating one at a time
  gamemodes/zcity/gamemode/modes/<mode>/   custom round modes (merged into Z-City's mode loader by GMod)
patches/<upstream>/    our edits to upstream code, one unified diff per file
manifests/             dependencies.json, source-map.json (old path -> new home), check-baseline.json
tools/                 build.py, check.py, check_dev_database.py
tests/                 offline unit tests (python -m unittest discover -s tests)
docs/                  this file, MIGRATION.md, operational docs
```

GMod merges every addon's `lua/` into one virtual filesystem. That is why the ~50 former addons could be merged into
`addons/us1` with **identical virtual paths** and no behavior change.

## Rules

1. **No new code in upstream trees.** Change Z-City/ULX behavior from `addons/us1` (hooks, `US1.Wrap`). Use a patch
   only when an override is impossible, and keep patches small.
2. **One namespace.** New code lives in `US1.<Module>`. Don't add new globals. Legacy tables (`ZCKillcam`,
   `ZCityGuiltJustice`, …) remain until their module migrates.
3. **Explicit load order.** Never use `zz_`/`zzz_` filename prefixes or retry timers.
   - Module files load in `_order.lua` order.
   - Code that needs `hg`/`zb` goes in `US1.OnReady(id, fn)`. It runs once, after `HomigradRun` + `InitPostEntity`.
4. **Overriding functions** (`hg.*`, `zb.*`, engine) goes through `US1.Wrap(tbl, key, id, make)`. It chains the
   original, is safe on lua refresh, and every wrapper is visible in `US1.Wrapped`.
5. **Hook IDs** are `"US1.<module>.<purpose>"`. Two files registering the same event+ID fail `tools/check.py`.
6. **Net receivers** use `US1.Net.Receive(name, {maxBits, rate, admin}, fn)`: valid player, size cap, per-player
   rate limit, pcall. Never `net.ReadTable()` from a client.
7. **No ops scripts in the shipped addon.** One-off `lua_openscript` probes/activations don't belong in `addons/us1`
   (the check fails on `*_activate/_probe/_rollback/...` names). Run them from a scratch location.
8. **Realm by prefix** (Z-City convention): `sv_` server, `cl_` client, `sh_`/none shared.
9. **Never hard-code physical paths** like `addons/<name>/` or `short_src` equality. Match the virtual `lua/...` suffix.

## Core API (`addons/us1/lua/us1/core`)

| Function | Purpose |
| --- | --- |
| `US1.Include(path[, realm])` | realm-aware, pcall-guarded include |
| `US1.LoadModules(root)` | loads every `us1/modules/<name>/` |
| `US1.OnReady(id, fn)` | run once Z-City + world are ready |
| `US1.Wrap(tbl, key, id, make)` | chained, refresh-safe override |
| `US1.Net.Receive(name, opts, fn)` | validated net receiver (server) |
| `US1.Log / US1.Error` | tagged logging; errors are collected in `US1.Errors` |
| `us1_status` (console, superadmin) | ready state, module list, errors |

## Checks

Run `python3 tools/build.py --check`. Set `GLUALINT` to the glualint binary.
- `tools/check.py` compares findings with `manifests/check-baseline.json`, so only **new** problems fail.
- When a migration removes debt, shrink the baseline with `--update-baseline` in its own commit.
- CI (`.github/workflows/ci.yml`) runs the unit tests, the build and the strict check on every push.
