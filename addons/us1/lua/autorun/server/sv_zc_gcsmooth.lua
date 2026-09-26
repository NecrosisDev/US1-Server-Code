-- ============================================================
--  ZC GC SMOOTH  (anti-hitch Lua garbage-collection smoothing)
-- ------------------------------------------------------------
--  ZCity allocates enough Lua garbage that the collector was building up to
--  big stop-the-world sweeps - each one a ~40-50ms tick hitch, roughly once a
--  second, with the heap sawtoothing ~53<->113 MB. Proven live with SpikeWatch:
--  running one incremental GC step per tick keeps the collector caught up so it
--  never does a big sweep - the heap flattened to a tight ~52-68 MB band and
--  GC-caused spikes fell from the dominant cause to ~3%.
--
--  This is that fix, made permanent. Near-zero cost (one small GC step/tick).
--  Toggle/tune live if ever needed:
--    zc_gcsmooth       1/0   (default 1)   on/off
--    zc_gcsmooth_step  KB    (default 0)   step size hint; 0 = engine default.
--                                          raise a little if heap still climbs.
-- ============================================================
if not SERVER then return end

local cv_on   = CreateConVar("zc_gcsmooth", "1", FCVAR_ARCHIVE, "Incremental Lua GC smoothing (anti tick-hitch)", 0, 1)
local cv_step = CreateConVar("zc_gcsmooth_step", "0", FCVAR_ARCHIVE, "GC step size hint in KB (0 = engine default)", 0, 4096)

hook.Add("Tick", "ZC_GCSmooth", function()
	if not cv_on:GetBool() then return end
	collectgarbage("step", cv_step:GetInt())   -- one incremental step; prevents the big atomic sweep
end)

print("[zc_gcsmooth] loaded - incremental GC smoothing " .. (cv_on:GetBool() and "ON" or "OFF"))
