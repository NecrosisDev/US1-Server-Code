-- Homelander: Hide & Seek mode wiring (2026-09-21, Part B). Civilian hiders
-- only -- bots are never allowed to become the Homelander.
--
-- Facts verified this session (work/bots/us1/addons/zc_homelander_complete/
-- gamemodes/zcity/gamemode/modes/zz_homelanderhns/{sv,sh,cl}_homelanderhns.lua):
--   * Registered round key is "homelanderhns" (MODE.name, sv_homelanderhns.lua:1)
--     -- the folder is zz_homelanderhns, but zb.modes is keyed by MODE.name
--     (same "folder != round key" pattern already documented in
--     sv_lowpop.lua's header for masscasualty/cstrike/superfighters).
--   * MODE.Chance = 0 (line 7, admin/vote-only), MODE.ROUND_TIME = 330 (line
--     5, "30s freeze + 5min hunt"). FREEZE_TIME = 30 is a mode-local const
--     (line 10, not exported) -- reproduced verbatim below.
--   * Selection: MODE:AssignTeams() (lines 24-60) -- an admin-forced pick via
--     TraitorAdmin.ForcedHomelander (SteamID match) if set, else a shuffled
--     players[1] gets team 0. Bots are eligible under the stock function; no
--     bot-exclusion exists on US1.
--   * Role representation: numeric team is authoritative (0 = Homelander,
--     1 = Civilian/hider) -- zb.GiveRole's "Homelander"/Color(190,0,0) and
--     "Civilian"/Color(0,120,190) (GiveEquipment, lines 172, 200) are cosmetic
--     labels layered on top, the same team-is-authoritative/role-is-cosmetic
--     split modes/sv_criresp.lua's header already documents for that mode.
--   * Freeze vs hunt: MODE:Intermission kills the Homelander's ply
--     immediately (line 73) and GiveEquipment's own
--     timer.Create("HomelanderHNS_Spawn_"..EntIndex, FREEZE_TIME, 1, ...)
--     (line 148) is what actually spawns them; a global EntityTakeDamage hook
--     zeroes ALL player damage while `zb.ROUND_START + FREEZE_TIME >
--     CurTime()` (lines 248-255). So "freeze" == before ROUND_START+30,
--     reproduced below as `inFreeze()`.
--   * End conditions: ShouldRoundEnd (lines 103-122) refuses to end before
--     ROUND_START+FREEZE_TIME+3 (line 105); then ends when team 0 (Homelander)
--     has zero alive (hiders win) or team 1 (hiders) has zero alive
--     (Homelander wins), or once ROUND_TIME (330s) elapses (hiders win by
--     default -- EndRound's winner is 0 only when aliveTeams[2]==0, lines
--     271-279).
--
-- BEHAVIOUR CHOICE (not dictated by the brief): AssignTeams is wrapped to run
-- the ORIGINAL selection unchanged (preserving TraitorAdmin.ForcedHomelander
-- and the random-shuffle path exactly) and then, only if a bot ended up on
-- team 0, swap it with a human civilian if one exists -- rather than trying
-- to intercept/reimplement the shuffle itself. This is the same
-- "run original, then swap the picked bot for a human" shape
-- modes/sv_defense.lua's installCommanderGuard already uses in this exact
-- codebase for an identical "a solo special role must not land on a bot"
-- problem.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}
local RB = hg.botdriver.RegisterBehavior
local lib = hg.botdriver.lib

hg.botdriver.DeclareBrainState("homelanderhns", { fields = {
	"hnsSpot", "hnsRoamer", "hnsNextReposition",
	"hnsLosCheckAt", "hnsLastThreat", "hnsLastThreatDist", "hnsRelocateUntil",
} })

local FREEZE_TIME = 30 -- verified local const, sv_homelanderhns.lua:10
local HIDE_MIN_SPACING = 450
local HIDE_SEARCH_RADIUS = 2500
local RELOCATE_LOS_GRACE = 0.5   -- rate-limit the LOS trace to ~2 Hz
local RELOCATE_BASE_DIST = 450
local RELOCATE_MOVE_DIST = 500
local ROAMER_INTERVAL_MIN, ROAMER_INTERVAL_MAX = 20, 40

----------------------------------------------------------------------
-- Idempotent wrap of zb.modes.homelanderhns.AssignTeams -- see file header.
----------------------------------------------------------------------

local function swapBotHomelanderForHuman()
	local homelander
	for _, ply in ipairs(player.GetAll()) do
		if IsValid(ply) and ply:Team() == 0 then homelander = ply break end
	end
	if not IsValid(homelander) or not homelander.zcBot then return end

	local human
	for _, ply in ipairs(player.GetAll()) do
		if IsValid(ply) and ply:Team() == 1 and not ply.zcBot then human = ply break end
	end
	-- No eligible human: never break the round to exclude a bot -- let the
	-- original selection stand.
	if not IsValid(human) then return end

	homelander:SetTeam(1)
	human:SetTeam(0)
end

-- Guard state lives on the persistent hg.botdriver table, NOT a file-local
-- (a file-local would be a fresh empty table every autorefresh re-run,
-- losing track of "wrapped" and re-capturing our OWN previous wrapper as if
-- it were the original -- the exact growing-call-chain pitfall sv_doors.lua's
-- own TraverseStep wrap already documents guarding against).
local function installAssignTeamsGuard()
	if not (zb and zb.modes and zb.modes.homelanderhns) then return false end
	local mode = zb.modes.homelanderhns
	if mode.AssignTeams == hg.botdriver._homelanderhnsAssignWrapped then return true end

	-- Re-capture (2026-09-25): the live function is not our wrapper, so it is
	-- the current original. The old `X = X or` kept the first capture forever,
	-- so after a hot reload of this mode the ZB_PreRoundStart re-install
	-- routed AssignTeams back to the pre-reload function.
	hg.botdriver._homelanderhnsAssignOriginal = mode.AssignTeams
	local original = hg.botdriver._homelanderhnsAssignOriginal
	if not isfunction(original) then return false end

	local function wrapped(self, ...)
		local results = { original(self, ...) }
		if hg.botdriver.cv_enable and hg.botdriver.cv_enable:GetBool() then
			swapBotHomelanderForHuman()
		end
		return unpack(results)
	end

	hg.botdriver._homelanderhnsAssignWrapped = wrapped
	mode.AssignTeams = wrapped
	return true
end

hook.Add("InitPostEntity", "zc_bots_homelanderhns_assign_guard", installAssignTeamsGuard)
hook.Add("ZB_PreRoundStart", "zc_bots_homelanderhns_assign_guard_reinstall", installAssignTeamsGuard)
installAssignTeamsGuard() -- lua_openscript / autorefresh mid-session
timer.Simple(0, installAssignTeamsGuard) -- zb may not exist yet at include time

----------------------------------------------------------------------
-- Civilian hider behaviour.
----------------------------------------------------------------------

local function findHomelander()
	for _, ply in ipairs(player.GetAll()) do
		if IsValid(ply) and ply:Team() == 0 then return ply end
	end
	return nil
end

local function inFreeze(now)
	return now < ((zb and zb.ROUND_START) or 0) + FREEZE_TIME
end

local claimedSpots = {} -- bot -> Vector, reset at ZB_StartRound / disconnect

hook.Add("ZB_StartRound", "zc_bots_homelanderhns_round_reset", function()
	local roundKey = zb and (zb.CROUND_MAIN or zb.CROUND)
	if roundKey ~= "homelanderhns" then return end
	claimedSpots = {}
end)

hook.Add("PlayerDisconnected", "zc_bots_homelanderhns_release_claim", function(ply)
	claimedSpots[ply] = nil
end)

local function spotFarEnough(bot, pos)
	for otherBot, otherPos in pairs(claimedSpots) do
		if otherBot ~= bot and IsValid(otherBot) and pos:DistToSqr(otherPos) < HIDE_MIN_SPACING * HIDE_MIN_SPACING then
			return false
		end
	end
	return true
end

-- Budgeted: at most 8 RandomRoamPos rolls + 8 visibility traces, only called
-- once per freeze/relocation (never per-decision).
local function pickHidingSpot(bot, homelander)
	if not navmesh.IsLoaded() then return nil end
	local myPos = bot:GetPos()
	local best, bestScore
	for _ = 1, 8 do
		local candidate = hg.botdriver.RandomRoamPos(myPos, HIDE_SEARCH_RADIUS)
		if isvector(candidate) and spotFarEnough(bot, candidate) then
			local score
			if IsValid(homelander) then
				score = candidate:DistToSqr(homelander:GetPos())
				local blocked = util.TraceLine({
					start = homelander:EyePos(), endpos = candidate + Vector(0, 0, 40), mask = MASK_SHOT,
				}).Hit
				if blocked then score = score + HIDE_SEARCH_RADIUS * HIDE_SEARCH_RADIUS end
			else
				score = math.random(100000) -- Homelander not spawned yet (freeze): distance-only fallback
			end
			if not bestScore or score > bestScore then best, bestScore = candidate, score end
		end
	end
	return best
end

-- Rate-limited (~2Hz) LOS/distance check. Trait-scaled trigger distance:
-- patient bots (up to 1.4x) tolerate the Homelander closer before bolting,
-- impatient ones (down to 0.7x) relocate sooner.
local function homelanderThreat(bot, brain, now, homelander)
	if not IsValid(homelander) or not homelander:Alive() then return false end
	if now < (brain.hnsLosCheckAt or 0) then return brain.hnsLastThreat or false end
	brain.hnsLosCheckAt = now + RELOCATE_LOS_GRACE

	local dist = bot:GetPos():Distance(homelander:GetPos())
	local patience = (brain.personality and brain.personality.patience) or 1
	local triggerDist = RELOCATE_BASE_DIST / math.max(patience, 0.5)
	local seen = dist <= HIDE_SEARCH_RADIUS and lib.VisibleAimPos(homelander, bot) ~= nil
	local threat = seen or dist <= triggerDist
	brain.hnsLastThreat = threat
	return threat
end

-- Perpendicular-biased flight direction (never straight back toward/away in
-- a predictable line), snapped to a reachable nav point.
local function relocateDestination(bot, homelander)
	local away = bot:GetPos() - (IsValid(homelander) and homelander:GetPos() or bot:GetPos())
	away.z = 0
	if away:LengthSqr() < 1 then away = Vector(1, 0, 0) else away:Normalize() end
	local perp = Vector(-away.y, away.x, 0)
	if math.random() < 0.5 then perp = perp * -1 end
	local dir = perp * 0.75 + away * 0.35
	if dir:LengthSqr() < 1 then dir = perp end
	dir:Normalize()

	local dest = bot:GetPos() + dir * RELOCATE_MOVE_DIST
	if navmesh.IsLoaded() then
		local area = navmesh.GetNearestNavArea(dest)
		if IsValid(area) then return area:GetCenter() end
	end
	return dest
end

local function noTargets() return false end

RB({
	name = "homelanderhns.hider",
	band = "MODE",
	order = 10,
	default = false,
	finalize = {},
	CanRun = function(ctx)
		if ctx.roundKey ~= "homelanderhns" then return false end
		if ctx.downed then return false end
		if hg.botdriver.TeamOf(ctx.bot) ~= 1 then return false end
		-- Never a combat target, never a shooter: installed here (MODE band,
		-- before ACQUIRE/COMBAT) so this decision's later bands see no
		-- enemies at all -- same technique modes/sv_masscasualty.lua uses for
		-- its own per-mode relationship override. This behavior ALWAYS then
		-- claims the tick below, so ACQUIRE/COMBAT/SUPPORT/IDLE structurally
		-- never run for a live hider -- verified: nothing here can fall
		-- through to idle roaming in the open, because nothing after MODE
		-- band ever gets a turn while this CanRun holds.
		ctx._enemyOf = noTargets
		ctx._allyOf = noTargets
		return true
	end,
	Run = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		local homelander = findHomelander()

		if inFreeze(now) then
			if not isvector(brain.hnsSpot) then
				local spot = pickHidingSpot(bot, homelander)
				if spot then
					brain.hnsSpot = spot
					claimedSpots[bot] = spot
					local personality = brain.personality
					local curiosity = (personality and personality.curiosity) or 0.5
					local patience = (personality and personality.patience) or 1
					-- PERSONALITY: curious/impatient bots keep repositioning
					-- through the hunt; patient/incurious ones freeze in place.
					brain.hnsRoamer = curiosity > 0.55 or patience < 0.9
					brain.hnsNextReposition = now + math.Rand(ROAMER_INTERVAL_MIN, ROAMER_INTERVAL_MAX) * patience
				end
			end
			local spot = brain.hnsSpot
			if isvector(spot) and bot:GetPos():Distance(spot) > 48 then
				lib.PathTo(bot, brain, spot, now, 1)
				return true, { path = true }
			end
			brain.path = nil
			brain.forward, brain.side = 0, 0
			return true
		end

		-- Hunt phase: stay still and quiet; relocate (perpendicular/away, then
		-- re-hide) when the hunter closes within trait-scaled range or gains
		-- LOS; otherwise a roamer-trait bot still repositions on its own timer.
		local threat = homelanderThreat(bot, brain, now, homelander)
		local roamerDue = brain.hnsRoamer and now >= (brain.hnsNextReposition or 0)
		if (threat or roamerDue or not isvector(brain.hnsSpot)) and now >= (brain.hnsRelocateUntil or 0) then
			local dest = relocateDestination(bot, homelander)
			claimedSpots[bot] = dest
			brain.hnsSpot = dest
			brain.hnsRelocateUntil = now + 2
			local patience = (brain.personality and brain.personality.patience) or 1
			brain.hnsNextReposition = now + math.Rand(ROAMER_INTERVAL_MIN, ROAMER_INTERVAL_MAX) * patience
		end

		local spot = brain.hnsSpot
		if isvector(spot) and bot:GetPos():Distance(spot) > 64 then
			brain.sprint = false -- never sprint in the open while relocating
			lib.PathTo(bot, brain, spot, now, 1)
			return true, { path = true }
		end

		brain.path = nil
		brain.forward, brain.side = 0, 0
		brain.sprint = false
		return true
	end,
})

hg.botdriver.RegisterModeProfile("homelanderhns", {
	behaviors = { "homelanderhns.hider" },
})
