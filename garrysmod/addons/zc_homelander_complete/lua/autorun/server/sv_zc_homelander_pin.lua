-- ============================================================
--  ZC HOMELANDER PIN - restrain him to defeat him
-- ------------------------------------------------------------
--  Homelander: Hide & Seek defeat condition (Joey's design):
--  if Homelander is NAILED (weapon_hammer -> rag.Nails) or
--  DUCT-TAPED (weapon_ducttape -> rag.DuctTape) down for
--  zc_hlpin_time continuous seconds, the round ends as a
--  HOMELANDER LOSS.
--
--  How the loss works: both restraint systems already keep him
--  from standing while any entry exists ("Should Fake Up" hooks).
--  After the hold time we Kill() him - the mode's own stock logic
--  does the rest: ShouldRoundEnd fires on no-homelander, and
--  EndRound awards the HIDERS whenever any hider is alive.
--  Struggling can still tear nails/tape off in time - keeping him
--  down is an active fight, exactly the counterplay loop.
--
--  Convars (FCVAR_ARCHIVE, live):
--    zc_hlpin_enabled  1   master toggle (pin defeat only - the HUD
--                          broadcast below runs regardless)
--    zc_hlpin_time     5   continuous seconds pinned to win
--
--  v2.0 STATUS HUD (jugg-panel style, per Joey): the same 0.25s
--  tick now broadcasts "zc_hl_status" to everyone during
--  homelanderhns rounds - arrival countdown, hunt clock
--  (mode.ROUND_TIME read live), hiders-alive count, and the PIN
--  METER (pinned progress toward the execution) - and the new
--  client file draws a persistent bottom-center panel gated purely
--  on packet freshness (the jugg stale-round lesson). CLIENT FILE =
--  RESTART CARGO; the sv half stays hotloadable. DRIFT CAVEAT:
--  FREEZE_TIME 30 mirrors the mode file's local.
-- ============================================================
if not SERVER then return end

local cv_on   = CreateConVar("zc_hlpin_enabled", "1", FCVAR_ARCHIVE, "Homelander HnS: tape/nail pin defeat condition", 0, 1)
local cv_time = CreateConVar("zc_hlpin_time", "5", FCVAR_ARCHIVE, "Continuous seconds Homelander must stay pinned to defeat him", 1, 60)

util.AddNetworkString("zc_hl_status")
local FREEZE_TIME = 30 -- mirrors sv_homelanderhns.lua's local FREEZE_TIME

local pinned = 0
local announced = false

local function anyRestraint(rag)
	if istable(rag.Nails) then
		for _, tbl in pairs(rag.Nails) do
			if tbl then return true end
		end
	end
	if istable(rag.DuctTape) then
		for _, tbl in pairs(rag.DuctTape) do
			if tbl then return true end
		end
	end
	return false
end

local function reset()
	pinned = 0
	announced = false
end

timer.Create("zc_hlpin_think", 0.25, 0, function()
	if not zb or zb.CROUND ~= "homelanderhns" then reset() return end

	local mode = zb.modes and zb.modes["homelanderhns"]
	local hl = mode and mode.HomelanderPlayer

	-- ---- pin defeat (v1.x logic, gated on the convar) ----
	local pinFrac, restrained = 0, false
	if cv_on:GetBool() and IsValid(hl) and hl:Alive() then
		-- v2.3: an active CHOKE counts as restraint (per Joey). The hands
		-- choke sets organism.choking every frame; sv_lungs clears it at
		-- 10Hz - a 0.5s grace smooths that flicker so the counter can't
		-- stutter-reset mid-choke.
		if hl.organism and hl.organism.choking then hl.zc_lastChoke = CurTime() end
		local choked = (hl.zc_lastChoke or 0) > CurTime() - 0.5
		local rag = hl.FakeRagdoll
		if IsValid(rag) and (anyRestraint(rag) or choked) then
			restrained = true
			pinned = pinned + 0.25
			pinFrac = math.Clamp(pinned / math.max(cv_time:GetFloat(), 0.25), 0, 1)
			if not announced then
				announced = true
				PrintMessage(HUD_PRINTTALK, "[HnS] HOMELANDER IS PINNED DOWN - hold him for " .. cv_time:GetInt() .. " seconds!")
			end
			if pinned >= cv_time:GetFloat() then
				reset()
				PrintMessage(HUD_PRINTTALK, "[HnS] Homelander has been restrained. The hiders win!")
				-- head-explosion finish: hg.ExplodeHead kills the player AND
				-- gibs the head bone on the ragdoll (stamps headexploded).
				-- Stock mode logic then ends the round as a Homelander loss.
				local target = IsValid(hl.FakeRagdoll) and hl.FakeRagdoll or hl
				local ok = hg and hg.ExplodeHead and pcall(hg.ExplodeHead, target)
				if not ok and IsValid(hl) and hl:Alive() then hl:Kill() end
			end
		else
			pinned = 0
			announced = false
		end
	else
		pinned = 0
		announced = false
	end

	-- ---- v2.0 status broadcast (every tick; freshness = the HUD gate) ----
	local now = CurTime()
	local roundTime = (mode and mode.ROUND_TIME) or 330
	local freezeLeft = math.max(0, math.ceil((zb.ROUND_START or 0) + FREEZE_TIME - now))
	local timeLeft = math.max(0, math.floor((zb.ROUND_START or 0) + roundTime - now))
	local hiders = 0
	for _, p in ipairs(team.GetPlayers(1)) do
		if IsValid(p) and p:Alive() then hiders = hiders + 1 end
	end
	net.Start("zc_hl_status", true)
	net.WriteUInt(freezeLeft, 6)
	net.WriteUInt(math.min(timeLeft, 1023), 10)
	net.WriteUInt(math.min(roundTime, 1023), 10)
	net.WriteUInt(math.min(hiders, 63), 6)
	net.WriteFloat(pinFrac)
	net.WriteBool(restrained)
	-- v2.1: Temp V attrition fields (zc_tempv addon; sentinel 2.0 =
	-- no vitality system installed -> the panel hides the row)
	local vitFrac = 2
	if ZCTEMPV and ZCTEMPV.vit and ZCTEMPV.vitmax and ZCTEMPV.vitmax > 0 then
		vitFrac = math.Clamp(ZCTEMPV.vit / ZCTEMPV.vitmax, 0, 1)
	end
	net.WriteFloat(vitFrac)
	net.WriteBool((ZCTEMPV and ZCTEMPV.burned) and true or false)
	net.WriteUInt(math.min((ZCTEMPV and ZCTEMPV.vials) or 0, 15), 4)
	net.Broadcast()
end)

print("[HnS Pin] loaded - nail or tape Homelander down for " .. cv_time:GetInt() .. "s to defeat him")
