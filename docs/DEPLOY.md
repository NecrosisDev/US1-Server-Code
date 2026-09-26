# Deploying US1: auto-update at every restart

Owner decision 2026-09-26: the live server updates itself from git on every restart, from `main`, in the
restructured layout (the four built addons). This page is the whole procedure.

## How it works
1. **Merge to `main`.** `.github/workflows/release.yml` runs the full check (unit tests, glualint, build, strict
   check). If anything fails, nothing is published and the server keeps what it has.
2. **CI publishes the `release` branch**: `addons/{zcity,ulx,ulib,us1}` exactly as `tools/build.py` built them, plus
   `us1_update.sh`, `RELEASE.json` (the main commit) and `MANIFEST.txt` (a sha256 for every file). Laid out by
   `tools/release.py`. One commit per release, so history is the list of every release.
3. **At each restart** the panel runs `us1_update.sh` before srcds. It fetches `release`, checks every file against
   `MANIFEST.txt`, then swaps the four folders in `garrysmod/addons/` (the previous copy stays as `<name>.prev`).
   It writes `garrysmod/data/us1_version.txt`; the console prints `[US1] running release <sha>` at boot.
4. **Any failure** (GitHub down, bad token, checksum mismatch, missing git) prints one `[US1 update] ...` line and
   the server starts on the files already installed. An update can never stop the server from starting.

It touches only `garrysmod/addons/{zcity,ulx,ulib,us1}` (and `.us1/`, its cache). Never `data/`, `cfg/`,
`garrysmod/lua`, other addons, Workshop content or `server.cfg`.

## One-time setup (owner; test server first)
1. **Token.** GitHub → Settings → Developer settings → Fine-grained tokens → Generate. Repository access: only
   `necrosisdev/us1-server-code`. Permissions: **Contents: Read-only**, nothing else. Pick an expiry and put a reminder
   in the calendar. Never paste it into chat, the repo or a cfg file.
2. **Panel variables** (Startup tab, or the panel's environment variables):
   - `US1_GIT_URL` = `https://x-access-token:<TOKEN>@github.com/necrosisdev/us1-server-code.git`
   - `US1_BRANCH` = `release` (optional), `US1_PIN` = empty, `US1_UPDATE` = `1`
3. **The script.** Download `us1_update.sh` from the `release` branch once and upload it to the server root (the folder
   that holds `garrysmod/`). After that it keeps itself up to date.
4. **The hook.** Physgun's startup box can't be edited, so the updater hooks into `srcds_run` instead (the startup
   command runs it; it is a plain text script in the server root). Open it in the panel's file manager and add this
   line directly under the first line (`#!/bin/bash`):
   `[ -f "$(dirname "$0")/us1_update.sh" ] && sh "$(dirname "$0")/us1_update.sh"`
   A Garry's Mod update can replace `srcds_run` and drop the line. Then the console says
   `[US1] WARNING: the auto-updater did not run at this start` at boot: add the line again. (If Physgun support will
   add `sh ./us1_update.sh;` to the front of the startup command for you, that survives game updates; prefer it.)
5. **The cutover (GATE 1).** The live server still has the old layout (~50 folders + loose `lua/`). Once only:
   - Take a panel backup. Stop the server.
   - `python3 tools/cutover.py --plan out/` on a checkout gives `CUTOVER.sh`, `UNDO.sh`, `CUTOVER.txt` (the list).
   - Upload `CUTOVER.sh` + `UNDO.sh` to the server root and run `sh CUTOVER.sh` (panel console or SFTP shell). It
     MOVES old US1 files into `garrysmod/_legacy_us1/`, which Garry's Mod never loads. Nothing is deleted.
   - Start the server: the updater installs the four addons. Run the HANDOFF_PLAN §6.3 checklist.
   - Something wrong: stop, `sh UNDO.sh`, delete the four `garrysmod/addons/<name>` folders the updater made and
     rename `<name>.prev` back if present, start. That is the old server again.
   - `tools/cutover.py --rehearse` proves the plan on the git snapshot: after it, 0 Lua paths are missing and 0 are
     provided twice.
6. After the cutover works: set `manifests/live.json` `layout` to `restructured`. `tools/drop.py` then refuses to
   build legacy drops (auto-update replaces them).

## Everyday use
- **Ship a change:** merge to `main`; wait for the green `release` run; restart the server (or wait for the next).
- **What is running:** the console line at boot, or `garrysmod/data/us1_version.txt`.
- **Roll back:** set `US1_PIN` to an older release commit from the `release` branch history, restart. Clear it to
  follow `main` again. Quicker, for one restart: stop, rename `<name>.prev` back over `<name>`, set `US1_UPDATE=0`.
- **Stop updating:** `US1_UPDATE=0`.

## Notes
- Every merge to `main` goes live at the next restart. Test on the test server (point it at the same branch) first.
- `server.cfg` is never shipped: settings stay on the server.
