-- Public current mutation only; never sends next-round picks or special-role identities.

if not SERVER then return end

local function PublishMutation()

    local title = "None"

    local framework = ZC_HMCD_MUTATORS

    local ctx = framework and framework.current

    if ctx and ctx.definition and type(ctx.Valid) == "function" and ctx:Valid() then

        local name = ctx.definition.Title

        if type(name) == "string" and name ~= "" then title = name end

    end

    if GetGlobalString("PATSB_MutationTitle", "") ~= title then

        SetGlobalString("PATSB_MutationTitle", title)

    end

end

PublishMutation()

timer.Create("PATSB_MutationBridge", 0.5, 0, PublishMutation)


-- ============================================================
-- Police Timer Bridge: networks homicide's police arrival clock
-- to clients so the scoreboard can show it. Wildwest excluded
-- (no police come), and any type with PoliceAllowed = false
-- naturally never broadcasts.
-- Hotload: lua_run include("autorun/server/sv_police_timer_bridge.lua")
-- ============================================================
if not SERVER then return end

timer.Create("PoliceTimerBridge", 1, 0, function()
	local eta, here = 0, false

	-- only rounds that actually run the hmcd police machinery -
	-- hmcd.saved goes STALE after homicide rounds end, so without
	-- this gate TDM/fear/civilwar would broadcast leftovers
	-- each round type's police clock lives on its OWN mode table
	-- (masscasualty/activeshooter stamp self.saved, not hmcd's)
	local MODE_FOR = {
		["standard"] = "hmcd", ["soe"] = "hmcd",
		["gunfreezone"] = "hmcd",
		["masscasualty"] = "masscasualty",
		["activeshooter"] = "activeshooter",
	}
	local round = zb and zb.CROUND
	local mkey = round and MODE_FOR[round]
	if mkey then
		local m = zb.modes and zb.modes[mkey]
		if m and m.saved and m.saved.PoliceTime and m.PoliceAllowed then
			eta = m.saved.PoliceTime
			here = m.PoliceSpawned == true
		end
	end

	SetGlobalFloat("HMCD_PoliceETA", eta)
	SetGlobalBool("HMCD_PoliceHere", here)
end)

print("[PoliceTimerBridge] loaded")
