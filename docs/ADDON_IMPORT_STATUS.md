# Addon import status - 2026-09-26

## Completed

- Existing loose-source baseline: commit `610b0f14cc957b2910c279012d2b899a188f03da`.
- Broader server package-location inventory completed without reported scan errors.
- Inventoried 153 GMA files: 2 local addons, 133 modern Workshop cache packages,
  and 18 legacy UGC cache packages. Their stored size totals 23,626,874,175 bytes
  (22.004 GiB); this is package size, not the size of code to import.
- Inventoried 53 loose addon directories. The baseline includes source/metadata
  from 52 of them; a content-only directory need not have files in a code repo.
- Saved package paths, sizes, modification times, proposed code locations and
  explicit pending statuses in `../manifests/addon-packages.json`.
- Recorded the content separation and migration gates in `CONTENT_PACK_PLAN.md`.

## Blocked / incomplete

The tool blocked the read-only archive-header inspection request because it
could not determine the request's safety status. No package inspection or
extraction followed that block. **Zero of the 153 GMA packages were unpacked**
in this pass. No archive-entry lists or package checksums have been verified.
The code from the two local compatibility GMAs and cached Workshop packages
is therefore still absent unless separately present in the loose-source baseline.
Do not describe this repository as a complete addon-source import yet.

## Scope and safety

The inventory is of files present on disk, not a verified active-addon list.
Reconcile startup configuration, collections and mounted addons before deployment.
Historical backups, release-staging archives, runtime-data ZIPs and base-game VPKs
remain excluded; their paths are recorded separately in the inventory manifest.

Existing Lua files and the earlier API-key redactions were not changed by this
planning pass. No content assets were downloaded, moved, published or committed.
No live server files or server configuration were modified. No server restart,
GitHub upload, Workshop upload or content-pack deployment was performed.

Next required gate: approved archive inspection/extraction, followed by per-file
classification, credential review, provenance and collision checks. Content-pack
assignment cannot be finalized from archive filenames and sizes alone.
