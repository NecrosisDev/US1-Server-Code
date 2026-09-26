# US1 server code: agent guide

This repo holds a Garry's Mod (Z-City gamemode) server's code. Read `docs/ARCHITECTURE.md` before changing anything.
The migration backlog is in `docs/MIGRATION.md`.
**Active work plan (orchestrator handoff): `docs/HANDOFF_PLAN.md`** — phases, work packages, owner gates, hard rules.

- Custom code: `addons/us1/`. Upstream edits: `patches/<upstream>/` (avoid adding more). Pins: `manifests/dependencies.json`.
- Where did an old file go? `manifests/source-map.json` (old `garrysmod/...` path -> new path + disposition).
- Deploy: `docs/DEPLOY.md` (main -> `release` branch -> the server pulls it at each restart).
- Build: `python3 tools/build.py --check` (set `GLUALINT=/path/to/glualint`). Tests: `python3 -m unittest discover -s tests`.
- The shipped virtual paths, net strings, convars, ULX commands, entity/weapon classes and `data/` paths are a compatibility
  surface: don't rename them in passing.
- Don't add ops/probe/activate scripts to `addons/us1`; `tools/check.py` rejects them.
- Never commit credentials, player data or live `.cfg` files. The GIPHY and VPN API keys are supplied on the server.
