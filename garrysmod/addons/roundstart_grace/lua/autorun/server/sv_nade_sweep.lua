-- ============================================================
-- Grenade Sweep: ANY grenade entity existing during the round
-- start grace period is neutered and deleted. Standalone - only
-- reads the RS_GraceUntil global the item block stamps (which is
-- proven working - guns are blocked). Two detectors:
--   1. OnEntityCreated - same-frame catch
--   2. 0.2s sweep of all entities while grace is active - catches
--      anything that dodged the event, however it spawned
-- Hotload: lua_run include("autorun/server/sv_nade_sweep.lua")
-- ============================================================
if not SERVER then return end

local function IsGrenadeEnt(ent)
	if ent.ishggrenade then return true end
	local cls = ent:GetClass()
	return cls:sub(1, 14) == "ent_hg_grenade"
		or cls == "ent_hg_molotov"
		or cls == "ent_hg_smokenade"
		or cls == "ent_throwable"
end

local function GraceActive()
	local untilT = GetGlobalFloat("RS_GraceUntil", 0)
	return untilT > 0 and CurTime() < untilT
end

local function Unmake(ent, how)
	-- neuter first so nothing can detonate in a race, then delete
	ent.Explode = function() end
	ent.Arm = function() end
	ent.AddThink = function() end
	ent.timer = nil
	print("[NadeSweep] deleted grace-period " .. ent:GetClass() .. " (" .. how .. ")")
	SafeRemoveEntity(ent)
end

hook.Add("OnEntityCreated", "NadeSweep_Created", function(ent)
	timer.Simple(0, function()
		if not GraceActive() then return end
		if IsValid(ent) and IsGrenadeEnt(ent) then Unmake(ent, "on create") end
	end)
end)

timer.Create("NadeSweep_Sweep", 0.2, 0, function()
	if not GraceActive() then return end
	for _, ent in ipairs(ents.GetAll()) do
		if IsValid(ent) and IsGrenadeEnt(ent) then Unmake(ent, "sweep") end
	end
end)

print("[NadeSweep] loaded - grenades cannot exist during grace")
