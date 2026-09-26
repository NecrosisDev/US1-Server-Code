-- Z-City killcam loader (server). Recorder, clip store, records net layer, life sequence, round highlight, round tape.
local booting = ZCKillcam == nil -- false when autorefresh re-runs this file on a live server
include("zc_killcam/sv_recorder.lua")
include("zc_killcam/sv_clips.lua")
include("zc_killcam/sv_net.lua")
include("zc_killcam/sv_life.lua")
include("zc_killcam/sv_intent.lua") -- before the highlight, karma and points: all three read who started a fight
include("zc_killcam/sv_highlight.lua")
include("zc_killcam/sv_karma.lua")
include("zc_killcam/sv_tape.lua")
include("zc_killcam/sv_tapeserve.lua")
-- LAST on purpose. This file opens with asserts, and an error inside an include aborts the rest of the
-- including file -- so anywhere earlier, a bad load here would take the round tape down with it. Nothing
-- below depends on it, so the worst case is that the points faucet is missing and everything else runs.
include("zc_killcam/sv_points.lua")
AddCSLuaFile("zc_killcam/cl_analysis.lua")
AddCSLuaFile("zc_killcam/cl_viewer.lua")
-- Client files are only ever registered at boot. Registering one on a running server left
-- connected clients with a broken copy, and US1 restarted shortly after (2026-09-21).
if booting then AddCSLuaFile("zc_killcam/cl_life.lua") end
