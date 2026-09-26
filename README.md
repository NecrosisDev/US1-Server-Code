# US1 server source

Source-only import of the server's `garrysmod/` directory.

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
