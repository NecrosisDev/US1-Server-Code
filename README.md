# US1 server source

Code for the US1 Garry's Mod server: one US1 addon plus pinned upstream Z-City, ULX and ULib with our patches.

```
python3 -m pip install -r tests/requirements.txt
python3 tools/check.py --tests      # all required offline tests; no skips
python3 tools/build.py --check      # -> dist/garrysmod/addons/{us1,zcity,ulx,ulib}
```

The required test gate needs both `lupa.luajit21` (installed above) and the native
`luajit` executable on PATH. Static checks require glualint 1.29.0; set `GLUALINT`
to its path. Missing tools, incomplete inputs and reported syntax errors cannot be
waived through the warning baseline. `--strict` remains a compatible alias.

`python3 -m unittest discover -s tests` is still available for local development,
but may skip unavailable runtimes and is not a substitute for the required gate.

- [Architecture and rules](docs/ARCHITECTURE.md). Agents: see [CLAUDE.md](CLAUDE.md).
- [Migration status and backlog](docs/MIGRATION.md). The pre-restructure raw import is tag `pre-restructure`.
- [Dependencies](manifests/dependencies.json) and the [old-path → new-path map](manifests/source-map.json).

The sections below describe the original raw import (now at tag `pre-restructure`).


Source-only working import of the server's `garrysmod/` directory.

The goal is an organized, consolidated US1 code addon with separate content packs
and explicit dependencies, followed by a tested release. The raw import is an
intermediate input, not the final layout or a folder to upload wholesale.
See the [consolidation plan](docs/CONSOLIDATION_PLAN.md).

## Contents

- `garrysmod/addons/`: loose addon source and retained addon manifests/licenses.
- `garrysmod/gamemodes/`: loose gamemode source.
- `garrysmod/lua/`: loose Lua source, including server customizations.

The baseline contains 2,590 Lua files and 11 addon manifest/license files.
Original directory layout and source bytes were preserved, except for the two
API-key values described below. Existing nested Git histories were not imported.

## Deliberate exclusions

No maps, models, materials, sounds, media, compiled modules, runtime data,
player databases, logs, caches, backups, or live `.cfg` files were imported.
GMA/VPK archives were not downloaded or unpacked. In particular, source inside
`addons/zcity_drones_compat.gma` and `addons/zcity_pillpack_compat.gma` is not
represented in this loose-source snapshot. Workshop cache contents are excluded.

## Local credentials

Two embedded API-key values were replaced with empty strings in the Git copies:

- `garrysmod/addons/zc_watchdog/lua/autorun/server/sv_watchdog_vpn.lua`
- `garrysmod/lua/zc_chat_media/giphy_config.lua`

Their original files were retained outside this repository on the importing PC.
Keep deployment-specific credentials private; do not commit the original keys.
Credential screening was pattern-based, not a guarantee of complete detection.

## Deployment caution

This is not a complete runnable server backup. Do not replace the live server
with this directory or use a synchronization command that deletes excluded files.
Before any deployment, review changes and supply the private configuration.
The import did not modify, restart, stop, or deploy to the live server.
No GitHub remote or upload was created during the local import.

Third-party source retains its existing notices; this import grants no new rights.

## Planned archive expansion and content separation

A broader inventory located 153 GMA files in addon and Workshop-cache locations,
plus 53 loose addon directories. Archive inspection/extraction was tool-blocked;
none of those GMAs has been unpacked in this repository. The baseline remains
loose-source only, not a complete addon import.

See [current import status](docs/ADDON_IMPORT_STATUS.md), the
[code/content separation plan](docs/CONTENT_PACK_PLAN.md), and the
[machine-readable package inventory](manifests/addon-packages.json).
The content-pack plan does not move assets or authorize public redistribution.

## Database readiness

The observed live configuration uses SQLite. A verified, private SQLite snapshot
was saved outside Git; no live backend change or data migration was performed.
See [database readiness](docs/DATABASE_READINESS.md) and
[storage audit](manifests/storage-audit.json). The read-only development checker
has seven passing offline tests; hosted-database creation and a real connection
remain pending. Actual player data and credentials must never enter this repo.
