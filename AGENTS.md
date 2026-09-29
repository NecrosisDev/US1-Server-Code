# US1 agent development rules

These instructions apply repository-wide to coding agents and delegated workers.
Read this file, `README.md`, and relevant subsystem guidance before changing code.
For consolidation, also read `docs/CONSOLIDATION_PLAN.md` and the applicable source
and dependency manifests. Pass these requirements to any delegated agent.

## Core rule: fix the owner, not another layer around it

Prefer direct, reviewed changes to the canonical implementation over additional
monkey-patches, override files, wrapper chains, or timers that repeatedly reinstall
changes. For behavior owned by US1 or its controlled Z-City fork, fix the source
that owns the behavior. A helper module may support that owner; it should not need
to replace the owner after initialization.

Consolidation means clear ownership, not giant files. Preserve useful feature
modules, documented extension hooks, independent dependencies, and bounded
diagnostic tooling. A `zc_` prefix alone is not a defect or grounds for deletion.

## Establish the actual implementation before editing

- Identify the owning function/module, its callers, realm, loading path, and
  dependencies. Search for existing fixes, competing definitions, hook IDs,
  timers, net receivers, includes, and feature flags before adding anything.
- Record the source revision being reviewed. For live-server work, read the
  deployed sources and reconcile relevant differences with the repository;
  never assume `main`, an old local copy, or a previous chat matches live.
- Account for virtual paths and mounted addon/Workshop providers. A file's
  presence in Git does not establish that it runs, and an absent loose file does
  not establish that a mounted dependency is absent.
- Missing authoritative source is a reason to retrieve and verify it, not invent
  another override. When it cannot be obtained, document the precise gap and do
  not claim the dependent change is verified or safe to deploy.

## Implement and retire together

- Integrate accepted fixes into their owners and retire superseded runtime
  implementations in the same reviewed change. Update their loaders, includes,
  client-file delivery, callers, and release/source mappings as applicable.
  Do not leave the original and replacement active together.
- Do not add permanent `fix2`, `pass3`, `final`, `restore`, or date-stamped runtime
  variants as a substitute for modifying the established implementation.
- Production code must not compete for ownership by repeatedly re-registering
  hooks, receivers, or methods. Prefer explicit initialization, documented
  readiness events, and one authoritative registration per responsibility.
- Preserve intended behavior, public interfaces, hook/net identifiers, commands,
  configuration, defaults, persistence, and security/permission boundaries unless
  their change is explicitly in scope. Activating an inactive feature or changing
  gameplay/punishment policy is not merely consolidation; review it separately.
- Keep changes narrow and reviewable, preferably one subsystem per commit. Do not
  combine semantic repairs, broad renaming, physical relocation, and a new loader
  into one opaque cleanup. Preserve virtual paths during relocation where possible.

## Compatibility patches are exceptions

Use an adapter or runtime patch only when changing the authoritative source is
 genuinely impractical, such as an independently maintained external dependency.
Document its source owner, why native integration is impractical, supported
version/API, installation path, safeguards, validation, and removal condition.
Use supported extension points first. Any necessary installation retry must be
bounded and report failure; do not maintain an indefinite ownership contest.

An emergency hotfix must have a documented path back into the canonical source
and a retirement condition. Do not call native integration complete while the
old patch remains necessary. Do not delete an existing safety patch until its
replacement and dependency handling are verified.

## Keep development history out of production

- Keep historical implementations in Git. Put reusable probes, tests, candidates,
  and operational scripts under appropriate non-runtime `tools/` or `tests/`
  locations; exclude them from production release inputs.
- Determine disposition from references and behavior, not filename, age, size,
  or matching hashes alone. An identical copy may still be a required entrypoint.
  Review include chains, dynamic loading, and external callers before removal.
- Follow the curated addon layout in the consolidation plan. Do not proliferate
  loose custom runtime files under `garrysmod/lua/` or alter engine/vendor files
  merely to avoid understanding ownership. Controlled fork changes must retain
  provenance and a deliberate upstream-update strategy.

## Validate the replacement and the cutover

For each implementation change, record the owner, evidence, files changed/added/
retired, preserved contracts, tests performed, remaining gaps, and rollback path.
Validate cold startup using only planned release inputs, without historical
activation scripts. Check relevant realms, load order, hook return semantics,
round/map lifecycle, reconnect behavior, and persistence. Include an appropriate
regression check for the behavior being consolidated.

A deployment must identify both files to install and old runtime files to retire.
Deleting a file does not establish that its existing callbacks/state are gone:
use a controlled restart/reconnect or explicitly tested teardown for the cutover.
Never deploy the raw import wholesale or run destructive synchronization against
live; preserve excluded content, private configuration, and player data.

Repository commits, live deployment, restarts, and external publication are
separate actions; perform only what the user authorized. Do not claim runtime
validation from static inspection, and do not claim a deployment or memory update
that was not actually performed.
