# Consolidation and release target

Goal: organize the server into a maintainable source project, consolidate everything
that can safely share a release, and upload/deploy only after validation.
The raw addon import is an intermediate input, not the final distribution layout.
Status: planning plus an initial loose-source audit; no consolidation performed yet.

## Target, not the current on-disk layout

```text
US1-Server-Code/
  garrysmod/                  # Existing imported baseline; never ship wholesale
  addons/us1/                 # Curated consolidated code addon, once migrated
    addon.json
    lua/autorun/              # Reviewed entry points; preserve loading behavior
    lua/us1/                  # Modules: core, gameplay, admin, UI, compatibility
    lua/entities/             # Preserve existing registered entity identities
    lua/weapons/              # Preserve existing registered weapon identities
    lua/effects/
    gamemodes/<existing-id>/  # Only when needed; preserve gamemode lifecycle
  vendor/                     # Reviewed dependency source, not automatic output
  manifests/                  # Source mappings, dependencies, decisions, audits
  tools/                      # Future build and validation tools
  docs/
```

Asset payloads belong in the separately planned `D:\US1-Content-Packs` workspace.
Content-pack families and dependency handling are defined in `CONTENT_PACK_PLAN.md`.
One Git repository does not mean one monolithic file or one compulsory upload.

## Consolidation decisions

| Kind of input | Intended treatment |
| --- | --- |
| US1 gameplay, UI, administration and fixes | Merge compatible systems into the curated addon as readable modules |
| Embedded third-party components | Record provenance; consolidate only after dependency and distribution review |
| Libraries needing isolation or independent updates | Keep as explicit, versioned dependencies; document each exception |
| Engine/default gamemode source | Keep as reference; compare to upstream and carry only deliberate custom changes |
| Exact duplicates | Review callers and entry points before retaining one canonical implementation |
| Conflicting versions or overrides | Preserve inputs; explicitly choose/merge the implementation matching intended behavior |
| Candidate, audit, backup or test scripts | Assess actual references; exclude from releases only after review |
| Models, textures, sounds and other runtime assets | Assign to content packs or original external dependencies |
| Credentials, player data and operational files | Keep outside source releases and outside content packs |

Names and directory locations alone do not establish ownership, activation or obsolescence.
Each migrated file needs an original path/hash, chosen destination, disposition,
dependencies, publication status and validation evidence in a source mapping.
Keep raw input provenance for comparison, but emit only curated files in builds.

## Work sequence

1. Complete the raw import and reconcile package versions with actual active mounts.
   The 153 pending GMAs remain an explicit gap, not implied completed work.
2. Extend the loose-source audit below across the full import. Identify same-path
   conflicts, identical content, stale candidates and dependencies before moving code.
3. Migrate one feature group per commit. First preserve behavior and paths;
   simplify internal module layout only after includes, identifiers and order are tested.
4. Fold compatible patches into canonical implementations. Remove a legacy loader
   only when the replacement is validated; do not run original and replacement together.
5. Build code and asset outputs from explicit allowlists. Fail on unresolved path
   collisions, missing dependencies, unclassified inputs or embedded credentials.
   Generated `build/` and `dist/` outputs stay outside Git history.
6. Test an isolated server and clean client using only planned release inputs.
   Check gameplay, UI, administration, entities/weapons, round transitions and assets.
7. Produce a versioned release with checksums, source mappings, required dependencies
   and a rollback procedure. Obtain approval before publishing or replacing live files.

## Initial audit: concrete cleanup candidates, not deletions

Audited the 2,590 tracked Lua files in the existing redacted local import.
Found **33 exact-content groups across 85 Lua files**. Some copies are stored in
candidate/audit paths; their names alone are not grounds to remove them.
The limited addon/root `lua/` path comparison found zero same-path or case-variant
collisions. This is NOT an all-addon or runtime-conflict clearance: archives,
gamemode aliases, dynamic includes, hook identifiers and load order were not resolved.
See `../manifests/consolidation-audit.json` for paths, hashes, scope and source-tree ID.
No addon code was executed, changed or deleted by this audit.

## Release constraints and references

GMod merges addon scripts into a virtual filesystem and sorts autorun files
alphabetically; preserving directory names is not sufficient to prove equal behavior.
Reference: https://wiki.facepunch.com/gmod/Lua_Loading_Order (checked 2026-09-26).

Returning a release to the private server, pushing GitHub source and publishing
Workshop items are separate release actions; none is authorized by this plan alone.
Do not ship the entire raw baseline, commercial/private originals or retail-game files.
Publication review applies to code as well as assets; possession is not publication approval.
For Workshop, use the official rules and packaging whitelist, not a blind server repack.
References checked 2026-09-26:
- https://wiki.facepunch.com/gmod/Steam_Workshop_Rules
- https://wiki.facepunch.com/gmod/Workshop_Addon_Creation

Success means fewer maintainable release units with the intended behavior preserved,
not merely fewer folders. Every component kept separate should have a recorded reason.
