# Code and content separation plan

Status: planned, not deployed or published. Archive extraction is still pending.

## Repository contract

Keep editable source in this repository, preserving each addon's internal paths.
Keep each addon in its own folder; do not flatten unrelated addons into one Lua tree.
The two local GMA addons should become `garrysmod/addons/zcity_drones_compat/`
and `garrysmod/addons/zcity_pillpack_compat/`. Workshop code should initially live
under `vendor/workshop/<workshop-id>/`; legacy UGC packages without a verified
Workshop ID should live under `vendor/ugc/<ugc-id>/<package>/`.
These vendor directories are review inputs, not automatically deployed addons.
Do not mistake a legacy UGC content handle for a Workshop item ID.
Retain licenses, attribution, addon metadata, and a source-to-repository manifest.
Record original filenames, archive checksums, per-file hashes, and import status.
The current package inventory has paths and sizes only; checksums are still pending.

## Proposed content packs

Create these only for US1-owned assets or assets approved for this distribution.
Names are planning labels, not existing Workshop items or completed packages.

| Pack family | Intended contents | Boundary |
| --- | --- | --- |
| `us1-content-core` | Shared UI imagery, fonts, common particles and effects | No executable Lua or credentials |
| `us1-content-characters` | Character models, skins, animation companions, textures and character audio | Keep each model's full dependency set together |
| `us1-content-equipment` | Weapons, props, vehicles and their models, textures, sounds and static definitions | Keep equipment dependency sets together |
| `us1-map-<name>` | An independently distributable US1 map with required map-specific assets | One coherent map package, not arbitrary numbered chunks |

## Not everything excluded from Git belongs in a content pack

- Runtime assets: models and their `.vvd/.vtx/.phy/.ani` companions, materials,
  textures, audio, particles, fonts, scenes, maps, and required navigation data
  are candidates for content packs after dependency and ownership review.
- Text is not necessarily code: material definitions, localization, vehicle
  definitions and static resource files need explicit classification. Required
  runtime definitions must be retained somewhere; never discard them by extension.
- Lua and other executable source remain in the code repository. Required HTML,
  JavaScript or CSS need a separate delivery decision, not a silent omission.
- Databases, player records, runtime `data/`, logs, caches and backups remain
  operational/private storage. They are not content-pack candidates.
- Passwords, API keys and live server configuration remain private deployment
  inputs. Compiled server modules are separately provisioned dependencies.
- Source-art/build inputs can have separate asset-source storage. Do not ship
  Photoshop projects or other authoring intermediates merely because they exist.
- Base-game and mounted retail-game VPKs remain game dependencies, not US1 packs.

## Third-party content

Default to the original Workshop item as the external content dependency.
Do not assume local possession gives permission to relicense or republish it.
Do not automatically merge downloaded Workshop addons into server content packs.
Keep provenance and existing notices, including for commercial addons. Review
publication eligibility separately before any GitHub or Workshop upload.

## Extraction and migration gates

1. Unpack every inventoried GMA through an approved extraction action into a
   staging location outside Git. Include modern Workshop caches and legacy UGC,
   not just `garrysmod/addons/`. Inspect other package formats explicitly.
2. Reject traversal paths, symlinks, duplicate archive paths and unsupported
   encodings. Detect Windows-invalid paths and case collisions before writing.
   Check archive CRCs, SHA-256 hashes and source stability; do not execute addons.
3. Classify every entry as source, content, dependency, operational/private,
   build input or manual review. Do not treat an unclassified file as disposable.
4. Preserve all differing versions. Identify duplicate archives and virtual-path
   collisions across loose addons, Workshop packages, gamemodes and root Lua.
   Determine active mounts separately: a cached package is not proof of activation.
5. Screen code and metadata for credentials before staging any Git commit.
   Retain any private originals outside Git. Keep the prior key redactions intact.
6. Build per-file content manifests with exact destination paths, sizes, hashes,
   source addon/Workshop IDs, dependencies and ownership/publication review status.
   Keep models with their sidecars and referenced textures; deduplicate only after
   hashes match. Resolve same-path/different-bytes collisions explicitly.
7. Copy approved assets to a separate sibling workspace, `D:\US1-Content-Packs`,
   preserving game-relative paths. Never delete or move the live server originals.
   This workspace has not been created or populated by this planning pass.
8. Test code plus content on an isolated server and a clean client. Check includes,
   autorun load order, entities, missing models/textures/audio and map navigation.

9. Deploy only after review and explicit approval. Replace each packaged code
   source with its raw counterpart without leaving both versions active. A mixed
   third-party Workshop dependency may also contain Lua: resolve duplicate code
   on both server and client before treating it as an assets-only dependency.
10. Publish eligible content separately, record the resulting item IDs, then
    configure server mounting and client downloads separately. `resource.AddWorkshop`
    marks a single Workshop item for client download; it does not install it on
    the server. Do not pass collection IDs or use it for Lua-only addons.

Before any full extraction, check available disk space and impose archive size
and entry-count limits. Packaging must validate allowed paths and formats.
No existing code is deployment-ready merely because its files were copied.
No arbitrary multi-part Workshop split is planned to work around upload limits.

## References checked 2026-09-26

- Archive tool and format: https://github.com/Facepunch/gmad
- Addon layout and packaging: https://wiki.facepunch.com/gmod/Workshop_Addon_Creation
- Content distribution: https://wiki.facepunch.com/gmod/resource.AddWorkshop
- Server installation: https://wiki.facepunch.com/gmod/Workshop_for_Dedicated_Servers
- Publication rules: https://wiki.facepunch.com/gmod/Steam_Workshop_Rules

The official rules restrict reuploads and retail-game content. Use original
Workshop dependencies for third-party content; do not presume a repack is allowed.
