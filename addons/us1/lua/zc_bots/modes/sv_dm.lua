-- dm mode profile: zone-escape MODE-band behavior that pushes a bot back
-- toward the shrinking zone center once it strays past 85% of the current
-- zone radius, preempting ACQUIRE/COMBAT the same way the real "bober" Think
-- enforcement preempts normal play (it stuns/dissolves anything outside the
-- zone, so being outside is never survivable for long -- the bot should not
-- out-fight that clock). Also owns the DM endgame escalation curve (item 1),
-- third-partying (item 2) and anticipatory zone positioning (item 7) -- all
-- three are MODE-band behaviors gated by CanRun's `not IsValid(ctx:AcquireTarget())`
-- guard, so none of them ever preempts a real, currently-visible fight.
--
-- VERIFIED (US1 tree, main-design-source/lua -> us1/addons/zcity):
--   modes/dm/sh_dm.lua:7-12 -- MODE.GetZoneRadius() reads the file-local
--     `zonedistance` global and zb.ROUND_START; called as
--     zb.modes["dm"].GetZoneRadius() from outside the file (loader.lua:80
--     stores the mode table at zb.modes[MODE.name], MODE.name = "dm" per
--     sv_dm.lua:5). Formula: (zonedistance + 2048) * max(((ROUND_START +
--     ZoneTimeToShrink) - CurTime()) / ZoneTimeToShrink, 0.025) -- a straight
--     linear shrink from full radius down to a 2.5% floor at
--     MODE.ZoneTimeToShrink seconds (120, sh_dm.lua:5), then flat forever.
--     zoneRadiusAt() below re-derives this at an arbitrary future time (item
--     7) since GetZoneRadius() itself always reads *now*.
--   modes/dm/sv_dm.lua:25-55 -- MODE:Intermission sets the plain global
--     `zonepoint` (no `local`) to the players' spawn centroid, and
--     `zonedistance` to the max spawn-to-center distance; both are true
--     globals (not zb.* / MODE.*), so any server-realm file in the same Lua
--     state can read zonepoint directly. zonepoint never moves once set --
--     only the radius shrinks -- so "anticipate the shrink" (item 7) is
--     purely a radius-lookahead problem, not a moving-target one.
--   modes/dm/sv_dm.lua:222-256 -- the "bober" Think hook is the real
--     enforcement: `local pos = zonepoint; local radius = MODE.GetZoneRadius()`
--     then punishes anything with pos:DistToSqr(ent:GetPos()) > radius^2.
--     This behavior computes the exact same distance from the exact same
--     zonepoint/radius pair so "inside/outside" agrees with the enforcement.
--   modes/dm/sv_dm.lua:3 -- convar `deathmatch_nozone` disables the zone
--     enforcement entirely; checked below so bots don't self-herd toward a
--     zone that isn't punishing anyone.
--
-- VERIFIED (item 1, 2026-09-22 -- the porting brief's own line numbers for
-- this were stale/wrong, re-derived from the actual file this session):
--   modes/dm/sv_dm.lua:73-75 -- `function MODE:ShouldRoundEnd() return
--     (#zb:CheckAlive(true) <= 1) end`. There is no `rules.survivor_target`
--     anywhere in this mode (grepped the whole modes/dm/ directory) -- the
--     real threshold is the hardcoded literal 1, i.e. DM is last-one-standing.
--   shared.lua:109-117 -- `zb:CheckAlive(incapacitatedcheck)` iterates
--     `player.Iterator()` (which includes bots -- a GMod bot is a real Player
--     entity) and keeps anyone with `ply:Alive()` true and, when
--     `incapacitatedcheck` is truthy (DM always passes true), not
--     `ply.organism.incapacitated` -- no team/spectator filtering at all (DM
--     puts every combatant on team 0 via MODE:Intermission's SetupTeam(0), so
--     that never mattered here). EndgameFactor's aliveCount below is exactly
--     this same count, so "approaching the real end condition" means
--     approaching 1, not some unverified authored target.
--   libraries/sv_roundsystem.lua:109 -- `zb.ROUND_TIME = zb.ROUND_TIME or 300`
--     (a real, mutable global); DM's own MODE table never overrides
--     ROUND_TIME (grepped modes/dm/*.lua), so the round clock term below reads
--     the same 300s default every other un-overridden mode gets.
--   init.lua:430-433 -- `hg.UpdateRoundTime` is what actually assigns
--     zb.ROUND_START/zb.ROUND_TIME each round; both are plain globals, same
--     read shape sv_tdm.lua already uses for zb.ROUND_START.

hg = hg or {}
hg.botdriver = hg.botdriver or {}

local RB = hg.botdriver.RegisterBehavior

local ESCAPE_FRACTION = 0.85

local function zoneRadius()
	local mode = zb and zb.modes and zb.modes["dm"]
	local fn = mode and mode.GetZoneRadius
	if not isfunction(fn) then return nil end
	local radius = fn()
	if not isnumber(radius) or radius <= 0 then return nil end
	return radius
end

-- Item 7: MODE.GetZoneRadius() only ever reads CurTime(); this re-derives its
-- formula (see VERIFIED note above) at `now + aheadSeconds` from the mode's
-- own verified terms (MODE.ZoneTimeToShrink, the zonedistance/zb.ROUND_START
-- globals) instead of inventing a second shrink model.
local function zoneRadiusAt(aheadSeconds)
	local mode = zb and zb.modes and zb.modes["dm"]
	if not istable(mode) then return nil end
	if not isnumber(zonedistance) or not isnumber(zb.ROUND_START) then return nil end
	local zoneTime = mode.ZoneTimeToShrink or 120
	local dist = zonedistance + 2048
	local frac = math.max(((zb.ROUND_START + zoneTime) - (CurTime() + aheadSeconds)) / zoneTime, 0.025)
	return dist * frac
end

local function nozoneActive()
	return ConVarExists("deathmatch_nozone") and GetConVar("deathmatch_nozone"):GetBool()
end

local function outsideSafeZone(bot)
	if not isvector(zonepoint) or nozoneActive() then return false, nil end
	local radius = zoneRadius()
	if not radius then return false, nil end
	local dist = bot:GetPos():Distance(zonepoint)
	return dist > radius * ESCAPE_FRACTION, dist
end

RB({
	name = "dm.zone-escape",
	band = "MODE",
	-- Band ordering alone (MODE precedes ACQUIRE/COMBAT in BAND_ORDER,
	-- sv_arbiter.lua:16) already lets this preempt both; a low order here
	-- just keeps it first among any other MODE-band dm behaviors.
	order = 10,
	default = false,
	finalize = { path = true },
	CanRun = function(ctx)
		local outside = outsideSafeZone(ctx.bot)
		return outside
	end,
	Run = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		hg.botdriver.SetObjective(bot, zonepoint, 96, 4, "hard", "dm.zone-escape")
		hg.botdriver.lib.ObjectiveTravel(bot, brain, now)
		-- Decline once back inside the safe fraction so ACQUIRE/COMBAT regain
		-- control instead of the bot idling at the zone center forever.
		local outside = outsideSafeZone(bot)
		return outside
	end,
})

----------------------------------------------------------------------
-- Item 1 (2026-09-22, DEFECT FIX): DM endgame escalation curve.
--
-- THE DEFECT: the last survivors in a DM round are very often hurt (they
-- would not still be alive otherwise), and sv_survival.lua's SURVIVAL band
-- (which runs before MODE/ACQUIRE/COMBAT, sv_arbiter.lua's BAND_ORDER) keeps
-- a hurt, low-aggression bot endlessly breaking contact to cover or ducking
-- before self-treating -- exactly the cover/defensive behaviour the owner
-- already rejected these bots for once, now stalling a second mode. Nothing
-- ever drove #zb:CheckAlive(true) down to the real end condition (1, see the
-- VERIFIED note above), so the round ground on to zb.ROUND_TIME's boring-round
-- timeout instead.
--
-- THE FIX: EndgameFactor (0..1) is driven by BOTH signals the brief asked
-- for -- how close the alive count is to the real end condition, and how much
-- of the round clock is left -- and is read by three places to floor bots'
-- committal instead of building a second combat system:
--   * sv_survival.lua's ApplySurvivalPreemption floors the effective
--     aggression used by the break-contact-to-cover gate and shortens the
--     self-treat cover-duck hesitation (the actual stall).
--   * sv_brain.lua's Engage shortens the fixed-20%-ammo disengage threshold.
--   * behaviors/sv_core_combat.lua's combat.engage floors ctx.behavior's
--     aggression term (the "commit" half of the curve).
-- dm.endgame-hunt below is the "actively path to nearest known/likely enemy"
-- half: a MODE-band behavior that only claims the tick when EndgameFactor is
-- past HUNT_THRESHOLD *and* the bot has no directly acquired target (so it
-- never preempts real combat) -- see the file-level comment for how this
-- and item 2/7's behaviors below are ordered so they do not fight it.
----------------------------------------------------------------------

hg.botdriver.dmEndgame = hg.botdriver.dmEndgame or { factor = 0, aliveCount = 0, updatedAt = 0 }

-- aliveCount<=ENDGAME_ALIVE_SPAN (the "final pair", or fewer) -> full
-- alive-driven escalation; aliveCount>=ENDGAME_ALIVE_KNEE -> none yet.
local ENDGAME_ALIVE_SPAN = 2
local ENDGAME_ALIVE_KNEE = 4
-- Only the last quarter of the round clock ramps the clock-driven term, so a
-- short/misconfigured ROUND_TIME cannot fire this early with a full lobby.
local ENDGAME_CLOCK_START_FRAC = 0.75

hg.botdriver.Every("dm_endgame_scan", 1, function()
	if not hg.botdriver.Enabled() then hg.botdriver.dmEndgame.factor = 0 return end
	local roundKey = zb and (zb.CROUND_MAIN or zb.CROUND)
	if roundKey ~= "dm" then hg.botdriver.dmEndgame.factor = 0 return end
	if not (zb and zb.CheckAlive) then return end

	local aliveList = zb:CheckAlive(true)
	local aliveCount = #aliveList
	local aliveTerm = math.Clamp((ENDGAME_ALIVE_KNEE - aliveCount) / (ENDGAME_ALIVE_KNEE - ENDGAME_ALIVE_SPAN), 0, 1)

	local clockTerm = 0
	local roundStart, roundTime = zb.ROUND_START, zb.ROUND_TIME
	if isnumber(roundStart) and isnumber(roundTime) and roundTime > 0 then
		local elapsedFrac = math.Clamp((CurTime() - roundStart) / roundTime, 0, 1)
		clockTerm = math.Clamp((elapsedFrac - ENDGAME_CLOCK_START_FRAC) / (1 - ENDGAME_CLOCK_START_FRAC), 0, 1)
	end

	hg.botdriver.dmEndgame.factor = math.max(aliveTerm, clockTerm)
	hg.botdriver.dmEndgame.aliveCount = aliveCount
	hg.botdriver.dmEndgame.updatedAt = CurTime()
end)

-- Visible to zc_bots_diagnose (sv_diagnose.lua) without a second copy of this
-- state, and read defensively (`hg.botdriver.EndgameFactor and ... or 0`) by
-- every other file above -- 0 outside dm since the Every-tick above pins it.
function hg.botdriver.EndgameFactor()
	return hg.botdriver.dmEndgame.factor
end

local HUNT_THRESHOLD = 0.15
local HUNT_MEMORY = 12
local HUNT_DEATH_MEMORY = 15

-- Nearest known-or-likely enemy position: this bot's own last-seen sighting,
-- its own last-heard gunfire, or a recent death anywhere on the map (fed by
-- sv_brain.lua's small recentDeaths ring, already maintained for the
-- idle-scan corpse-glance feature) -- whichever is closest to the bot right
-- now. No new tracking, no scan beyond the bounded recentDeaths ring.
local function huntPosition(bot, brain, now)
	local best, bestDistSqr
	local myPos = bot:GetPos()

	local function consider(pos)
		if not isvector(pos) then return end
		local d = myPos:DistToSqr(pos)
		if not bestDistSqr or d < bestDistSqr then best, bestDistSqr = pos, d end
	end

	if now - (brain.lastSeenTime or -math.huge) < HUNT_MEMORY then consider(brain.lastSeenPos) end
	if now - (brain.heardAt or -math.huge) < HUNT_MEMORY then consider(brain.heardPos) end
	for _, slot in pairs(hg.botdriver.recentDeaths or {}) do
		if slot.pos and now - (slot.at or -math.huge) < HUNT_DEATH_MEMORY then consider(slot.pos) end
	end

	return best
end

RB({
	name = "dm.endgame-hunt",
	band = "MODE",
	order = 14,
	default = false,
	finalize = { path = true },
	CanRun = function(ctx)
		if hg.botdriver.RoundAllowsCombat and not hg.botdriver.RoundAllowsCombat() then return false end
		if ctx.downed then return false end
		if hg.botdriver.EndgameFactor() < HUNT_THRESHOLD then return false end
		return not IsValid(ctx:AcquireTarget())
	end,
	Run = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		local pos = huntPosition(bot, brain, now)
		if not pos then return false end
		hg.botdriver.SetObjective(bot, pos, 90, 5, "soft", "dm.endgame-hunt")
		hg.botdriver.lib.ObjectiveTravel(bot, brain, now)
		return true
	end,
})

----------------------------------------------------------------------
-- Item 2 (2026-09-22, third-partying): sv_hearing.lua's SustainedPos (a
-- rolling "repeated shots from roughly one area" tracker, not a single-shot
-- reaction) tells this behavior a real fight is happening nearby. HEALTHY
-- bots move in to clean up the winner; hurt bots peel away from it instead.
-- Health is read from ctx.survival.body -- the exact organism blood/health
-- state sv_survival.lua already computed this decision, not a second read.
--
-- ORDERING vs item 1 (stated per the brief's explicit ask): dm.endgame-hunt
-- is order 14, this is order 18 -- both bands only ever claim the tick when
-- ctx:AcquireTarget() found nothing, so they never fight over a real,
-- visible target. When they DO compete for "what to do with no visible
-- target", endgame-hunt (a specific known/likely enemy position, gated on
-- EndgameFactor) wins first; this behavior is the earlier/mid-round default
-- (EndgameFactor still near 0) and remains a fallback for whenever
-- endgame-hunt has no candidate position of its own.
----------------------------------------------------------------------

local THIRDPARTY_HEALTHY_FRAC = 0.6
local THIRDPARTY_RETREAT_DIST = 600

RB({
	name = "dm.thirdparty",
	band = "MODE",
	order = 18,
	default = false,
	finalize = { path = true },
	CanRun = function(ctx)
		if hg.botdriver.RoundAllowsCombat and not hg.botdriver.RoundAllowsCombat() then return false end
		if ctx.downed then return false end
		if IsValid(ctx:AcquireTarget()) then return false end
		local hearing = hg.botdriver.hearing
		if not hearing or not hearing.SustainedPos then return false end
		return hearing.SustainedPos(ctx.brain, ctx.now) ~= nil
	end,
	Run = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		local pos = hg.botdriver.hearing.SustainedPos(brain, now)
		if not pos then return false end

		local body = ctx.survival and ctx.survival.body
		local healthy = not body or (body.healthFrac or 1) >= THIRDPARTY_HEALTHY_FRAC

		if healthy then
			hg.botdriver.SetObjective(bot, pos, 150, 5, "soft", "dm.thirdparty_approach")
		else
			local away = bot:GetPos()
			local delta = away - pos
			if delta:LengthSqr() > 1 then
				delta:Normalize()
			else
				delta = Vector(math.Rand(-1, 1), math.Rand(-1, 1), 0)
				if delta:LengthSqr() < 0.01 then delta = Vector(1, 0, 0) end
				delta:Normalize()
			end
			away = away + delta * THIRDPARTY_RETREAT_DIST
			hg.botdriver.SetObjective(bot, away, 96, 4, "soft", "dm.thirdparty_retreat")
		end

		hg.botdriver.lib.ObjectiveTravel(bot, brain, now)
		return true
	end,
})

----------------------------------------------------------------------
-- Item 7 (2026-09-22, DM zone play): beyond dm.zone-escape's reactive
-- 85%-flee, this anticipates the shrink using zoneRadiusAt's lookahead and
-- drifts inward along the bot's own approach bearing before it is ever
-- actually in danger. As the zone's radius converges on its 2.5% floor late
-- in the round, `safeRadius` converges too, so bots naturally end up
-- contesting the middle without a separately-tuned "late game" branch.
--
-- "use the edge offensively": when the bot has a recent last-seen-enemy
-- bearing, it stands along the centre-to-threat line (at the safe radius)
-- instead of its own current bearing -- if that threat returns along roughly
-- the same line, this bot is already positioned on the centre side of it, so
-- the threat's own retreat-under-fire runs outward, into the zone's danger,
-- not deeper into the map.
--
-- Ordering: order 22, after dm.endgame-hunt(14)/dm.thirdparty(18) -- a known
-- enemy or a real nearby fight is always more valuable than anticipatory
-- positioning, and (like both of those) this only ever claims the tick when
-- ctx:AcquireTarget() found nothing, so it never preempts real combat either.
-- dm.zone-escape(10) still owns the case where the bot is ALREADY past the
-- 85% danger line right now -- this behavior explicitly declines that case
-- and only acts BEFORE it would trigger.
----------------------------------------------------------------------

local PREPOSITION_LOOKAHEAD = 18
local PREPOSITION_SAFE_MARGIN = 0.75
local EDGE_BIAS_RECENCY = 10

local function prepositionBearing(bot, brain, now)
	if isvector(brain.lastSeenPos) and now - (brain.lastSeenTime or -math.huge) < EDGE_BIAS_RECENCY then
		local toThreat = brain.lastSeenPos - zonepoint
		toThreat.z = 0
		if toThreat:LengthSqr() > 1 then return toThreat:GetNormalized() end
	end
	local own = bot:GetPos() - zonepoint
	own.z = 0
	if own:LengthSqr() > 1 then return own:GetNormalized() end
	return nil
end

RB({
	name = "dm.zone-preposition",
	band = "MODE",
	order = 22,
	default = false,
	finalize = { path = true },
	CanRun = function(ctx)
		if hg.botdriver.RoundAllowsCombat and not hg.botdriver.RoundAllowsCombat() then return false end
		if ctx.downed then return false end
		if nozoneActive() or not isvector(zonepoint) then return false end
		if IsValid(ctx:AcquireTarget()) then return false end
		if outsideSafeZone(ctx.bot) then return false end -- dm.zone-escape already owns this

		local radius = zoneRadius()
		local future = zoneRadiusAt(PREPOSITION_LOOKAHEAD)
		if not radius or not future then return false end
		local safeRadius = math.min(radius, future) * PREPOSITION_SAFE_MARGIN
		return ctx.bot:GetPos():Distance(zonepoint) > safeRadius
	end,
	Run = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		local radius = zoneRadius()
		local future = zoneRadiusAt(PREPOSITION_LOOKAHEAD)
		if not radius or not future then return false end
		local safeRadius = math.min(radius, future) * PREPOSITION_SAFE_MARGIN

		local bearing = prepositionBearing(bot, brain, now)
		if not bearing then return false end

		local dest = zonepoint + bearing * safeRadius
		hg.botdriver.SetObjective(bot, dest, 128, 6, "soft", "dm.zone-preposition")
		hg.botdriver.lib.ObjectiveTravel(bot, brain, now)
		return true
	end,
})

hg.botdriver.RegisterModeProfile("dm", {
	behaviors = { "dm.zone-escape", "dm.endgame-hunt", "dm.thirdparty", "dm.zone-preposition" },
})
