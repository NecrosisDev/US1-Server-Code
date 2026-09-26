-- ============================================================
--  ZC TDM CLEANER - battlefield janitor for the TDM-family modes
-- ------------------------------------------------------------
--  30-player TDM rounds sink to ~30 tick because NOTHING leaves
--  the map mid-round: the stock ZBox cleaner runs every 10 MINUTES,
--  permanently exempts player corpses (org.isPly guard), and skips
--  anything within 1000u of an alive player. Meanwhile every corpse
--  is a ~14-bone VPhysics ragdoll in COLLISION_GROUP_WEAPON (they
--  collide with EACH OTHER - piles grind the solver every engine
--  tick) AND gets a FULL organism entry at death (PostPlayerDeath ->
--  hg.organism.Add(ragdoll), tier_0/sv_tier_0.lua:31) that runs the
--  whole 10-handler "Org Think" chain at 10Hz forever. The gamemode
--  dev's own comment on that loop translates to "now it's clear why
--  corpses cause lag...".
--
--  Active ONLY while zb.CROUND is in zc_clean_modes (default = the
--  mode-vote TDM category). Two jobs, swept once a second:
--   * FREEZE (zc_clean_freeze, 10s): a body that old and at rest
--     gets EnableMotion(false) on every phys bone - zero solver
--     cost, still visible/lootable/shootable, it just never flops
--     again - and (zc_clean_orgstop) its organism entry is pulled
--     from hg.organism.list, the loop's own removal idiom. The org
--     TABLE is left intact (owner and all) so damage-path code that
--     reads rag.organism can never nil-error.
--   * CAP (zc_clean_bodycap, 10): past the cap the oldest body is
--     removed first; bodies someone is spectating are picked last.
--
--  A LIVE player's knockdown ragdoll shares his organism (alive =
--  true) and is NEVER touched - dragging the wounded stays intact.
--  Map-placed ragdolls (CreatedByMap) are dressing, also skipped.
--  Organism-less runtime ragdolls (NPC corpses in the riot modes,
--  stray rag chunks) count as bodies too.
--
--  Serverside only = hotloadable. zc_clean_enabled 0 kills it live.
-- ============================================================
if not SERVER then return end

local cv_on      = CreateConVar("zc_clean_enabled", "1", FCVAR_ARCHIVE, "TDM cleaner master toggle", 0, 1)
local cv_modes   = CreateConVar("zc_clean_modes", "tdm,hl2dm,civilwar,gwars,uncontainedriot,Cops/Gangsters,juggernaut", FCVAR_ARCHIVE, "Comma-separated zb.CROUND keys the cleaner is active in")
local cv_freeze  = CreateConVar("zc_clean_freeze", "10", FCVAR_ARCHIVE, "Seconds after death before a body's physics freeze (0 = never)", 0, 300)
local cv_cap     = CreateConVar("zc_clean_bodycap", "10", FCVAR_ARCHIVE, "Max bodies on the field - oldest removed first (0 = no cap)", 0, 100)
local cv_orgstop = CreateConVar("zc_clean_orgstop", "1", FCVAR_ARCHIVE, "Also unhook a frozen body's organism from the 10Hz Org Think loop", 0, 1)

local function modeActive()
	if not zb or not zb.CROUND then return false end
	local cur = zb.CROUND
	for m in string.gmatch(cv_modes:GetString(), "[^,]+") do
		if string.Trim(m) == cur then return true end
	end
	return false
end

-- a "body": runtime-spawned corpse ragdoll - dead organism, or an
-- organism-less runtime ragdoll (NPC corpses, stray chunks)
local function isBody(rag)
	if rag:CreatedByMap() then return false end
	local org = rag.organism
	if org then return not org.alive end
	return true
end

local function untouchable(rag)
	return rag:IsPlayerHolding() or IsValid(rag:GetParent())
end

local function freezeBody(rag)
	for i = 0, rag:GetPhysicsObjectCount() - 1 do
		local ph = rag:GetPhysicsObjectNum(i)
		if IsValid(ph) then ph:EnableMotion(false) end
	end
	rag.zc_cleanFrozen = true
	if cv_orgstop:GetBool() and hg and hg.organism and hg.organism.list then
		hg.organism.list[rag] = nil -- off the 10Hz loop; org table stays intact
	end
end

local function observed(rag)
	for _, p in player.Iterator() do
		if IsValid(p) and p:GetObserverTarget() == rag then return true end
	end
	return false
end

timer.Create("zc_clean_sweep", 1, 0, function()
	if not cv_on:GetBool() or not modeActive() then return end

	local now = CurTime()
	local freezeAt = cv_freeze:GetFloat()
	local bodies = {}

	for _, rag in ipairs(ents.FindByClass("prop_ragdoll")) do
		if IsValid(rag) and isBody(rag) then
			rag.zc_cleanSeen = rag.zc_cleanSeen or now
			local age = now - rag.zc_cleanSeen
			bodies[#bodies + 1] = { rag = rag, age = age }

			if freezeAt > 0 and not rag.zc_cleanFrozen and age >= freezeAt and not untouchable(rag) then
				-- settle gate: don't flash-freeze a body still tumbling or
				-- being dragged; hard fallback at 3x so nothing dodges forever
				local ph = rag:GetPhysicsObject()
				local resting = IsValid(ph) and ph:GetVelocity():LengthSqr() < 900
				if resting or age >= freezeAt * 3 then
					freezeBody(rag)
				end
			end
		end
	end

	local cap = cv_cap:GetInt()
	if cap > 0 and #bodies > cap then
		for i = 1, #bodies do
			bodies[i].obs = observed(bodies[i].rag)
		end
		-- removal order: unspectated before spectated, then oldest first
		table.sort(bodies, function(a, b)
			if a.obs ~= b.obs then return not a.obs end
			return a.age > b.age
		end)
		local kill = #bodies - cap
		for i = 1, #bodies do
			if kill <= 0 then break end
			local rag = bodies[i].rag
			if not untouchable(rag) then
				if hg and hg.organism and hg.organism.list then hg.organism.list[rag] = nil end
				rag:Remove()
				kill = kill - 1
			end
		end
	end
end)

print("[TDM Cleaner] active in: " .. cv_modes:GetString() .. " | freeze " .. cv_freeze:GetFloat() .. "s, body cap " .. cv_cap:GetInt())
