# Taser and killcam fixes — September 26, 2026

## Scope

These changes are based on repository commit `e7f1b5affa9dbd1772750d8fc1adf22844ef472e`. They do not merge upstream Z-City, change global load order, or deploy anything to the running server.

The taser base matched the inspected live file. The fix removes an unused, unchecked pelvis calculation, validates the required spine physics lookup, guards delayed rope creation, and cancels callbacks when their weapon, target, body, or organism references become invalid. Existing damage and stun-duration calculations and the ten shaking targets are retained. Missing spine physics skips shaking, not the remaining medical effects of an otherwise valid session.

## Two viewer baselines — do not mix them

The live server's newer viewer includes a palette refresh that assigns a color table to `P.Data`, overwriting its replay-statistics function. That theme integration is not present in the repository's older viewer.

The tracked repository viewer now names its getter `P.GetReplayData` and updates all three callers. Both tracked loader/delivery checksums were regenerated for that repository bundle:

`5d021c5f240792f3f47dd70bb1d4e4128cc9e5e7daa311d324c9e8c2779e42f0`

The exact fix prepared for the newer live viewer is retained separately in `patches/live-20260926/killcam-data-color.patch`: rename only the color to `P.DataColor`, retaining its `P.Data` getter. Its before/after hashes and unchanged fragment dependencies are recorded in `manual-upload-manifest.json`. That manifest describes the earlier manual-upload artifact; its modification flags and byte hashes are historical, not a claim about this commit. The committed taser also has a final newline absent from that artifact.

Do not copy the older tracked viewer over the newer server or mix its fragments/checksums with the manual-upload bundle. Apply the live patch only to the matching inspected baseline, verifying all fragment dependencies first. Changes to a different baseline require a new assembled checksum in both declarations. Do not disable the checksum checks.

## Validation

`python -m unittest discover -s tests -p test_taser_killcam.py -v`

The four targeted test methods passed with LuaJIT through `lupa`, with no skips. They cover actual Lua-returned fragment contents and both checksums, a getter/cache surviving 300 simulated color refreshes, and 20 taser behavior assertions. The taser full-file syntax check normalizes GLua operators before compilation; behavior tests execute extracted callbacks against mocked engine services. These are not live GMod physics, rendering, or integration tests. Without `lupa`, Lua-dependent tests explicitly skip.

The eight findings in the earlier general code-review passes are not implemented by this commit. The live server still requires a separate, version-matched deployment and staging validation.
