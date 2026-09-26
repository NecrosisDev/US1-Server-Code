# US1 modules

One folder per feature: `us1/modules/<name>/`, exposed as `US1.<Name>`.
Files use Z-City realm prefixes (`sv_`, `sh_`, `cl_`). Optional `_order.lua` returns the file list in load order.
Code needing `hg`/`zb` runs inside `US1.OnReady("<name>.<purpose>", fn)`.
Legacy `lua/zc_*` systems migrate here one at a time; see docs/MIGRATION.md.
