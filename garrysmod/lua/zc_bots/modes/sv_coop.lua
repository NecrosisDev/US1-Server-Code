-- Coop mode profile for zc_bots (Half-Life 2 co-op campaign). Round key
-- "coop" (MODE.name, us1/.../modes/coop/sh_coop.lua:2).
--
-- VERIFIED this session (us1/.../modes/coop/sv_coop.lua, sh_coop.lua):
--   * No player-count-based NPC scaling exists anywhere in this mode -- coop
--     plays the map's own native HL2 NPCs (npc_combine_s, npc_metropolice,
--     npc_zombie); nothing here spawns or scales enemy count/health by
--     player.GetCount(), so there is nothing of that kind to preserve or
--     avoid touching. Reported per the brief; no code changes follow from
--     this finding.
--   * Friendly-fire/guilt: MODE.GuiltCheck (sh_coop.lua:42-46) only penalises
--     damage between entries of the same hg.FriendlyClasses group
--     (Rebel/Refugee/Gordon, Metrocop/Combine, headcrabzombie); it does not
--     define "enemy" for targeting purposes -- Disposition() does that (see
--     sv_npc.lua).
--   * Map transitions: MODE:CanLaunch() (sv_coop.lua:488-491) requires at
--     least one trigger_changelevel on the map; MODE:ShouldRoundEnd()
--     (sv_coop.lua:208-231) fires `RunConsoleCommand("changelevel", ...)`
--     once every living player is out of the fight AND `hg.MapCompleted` is
--     true. The write site that actually sets hg.MapCompleted was not found
--     in this session's grep of modes/coop/*.lua or gamemode/init.lua's
--     visible surface -- UNVERIFIED, likely set by a level-transition trigger
--     handler elsewhere in the base gamemode this checkout does not include.
--     Because that write site is unverified, this file treats every
--     trigger_changelevel on the map as something a bot must never be the
--     SOLE occupant of (see avoidChangelevelAlone below) rather than
--     assuming any particular semantics for it.
--   * No player-count-based difficulty scaling of any kind was found to
--     avoid.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}
local RB = hg.botdriver.RegisterBehavior
local lib = hg.botdriver.lib
local runEscort -- forward-declared: referenced by coop.pve_targeting's Run, defined below

----------------------------------------------------------------------
-- Changelevel-trigger avoidance (brief: "bots must not trigger map-
-- transition/changelevel triggers on their own"). ents.FindByClass is banned
-- in this package (test_port_clean.py) -- the trigger list is seeded the same
-- sanctioned way as sv_npc.lua's NPC registry: a single ents.Iterator() pass
-- at PostCleanupMap, only while coop is the live round.
--
-- PROVISIONAL(2026-09-21, Entity:OBBMins/OBBMaxs's exact local-space
-- semantics were not independently re-verified against GMod's own engine
-- binding this session (no live server to test against) -- wrapped in pcall
-- and this whole check degrades to a no-op (bot simply keeps whatever path it
-- already had) if the call errors or a trigger reports degenerate bounds,
-- ratify-by: 2026-10-15)
----------------------------------------------------------------------

local triggers = {}

local function coopActive()
	local rk = zb and (zb.CROUND_MAIN or zb.CROUND)
	return rk == "coop"
end

local function seedTriggers()
	for i = #triggers, 1, -1 do triggers[i] = nil end
	if not coopActive() then return end
	for _, ent in ents.Iterator() do
		if IsValid(ent) and ent:GetClass() == "trigger_changelevel" then
			triggers[#triggers + 1] = ent
		end
	end
end

hook.Add("PostCleanupMap", "zc_bots_coop_seed_triggers", seedTriggers)
seedTriggers() -- lua_openscript / autorefresh mid-round

local function boundsOf(trig)
	local ok, mins, maxs = pcall(function() return trig:OBBMins(), trig:OBBMaxs() end)
	if not ok or not isvector(mins) or not isvector(maxs) then return nil end
	return mins, maxs
end

local function insideTrigger(pos, trig)
	local mins, maxs = boundsOf(trig)
	if not mins then return false end
	local local_ = pos - trig:GetPos()
	return local_.x >= mins.x and local_.x <= maxs.x
		and local_.y >= mins.y and local_.y <= maxs.y
		and local_.z >= mins.z - 72 and local_.z <= maxs.z + 72
end

local function humanInside(trig)
	for _, ply in ipairs(player.GetHumans()) do
		if IsValid(ply) and ply:Alive() and insideTrigger(ply:GetPos(), trig) then return true end
	end
	return false
end

RB({
	name = "coop.avoid_changelevel_alone",
	band = "REFLEX",
	order = 5,
	default = false,
	finalize = {},
	CanRun = function(ctx)
		if ctx.roundKey ~= "coop" or #triggers == 0 then return false end
		local pos = ctx.bot:GetPos()
		for _, trig in ipairs(triggers) do
			if IsValid(trig) and insideTrigger(pos, trig) and not humanInside(trig) then
				ctx._avoidTrigger = trig
				return true
			end
		end
		return false
	end,
	Run = function(ctx)
		local bot, brain = ctx.bot, ctx.brain
		local trig = ctx._avoidTrigger
		local away = bot:GetPos() - trig:GetPos()
		away.z = 0
		if away:LengthSqr() < 1 then away = Vector(1, 0, 0) end
		away:Normalize()
		brain.path = nil
		brain.moveAngles = away:Angle()
		brain.forward = 250
		brain.side = 0
		return true
	end,
})

----------------------------------------------------------------------
-- PvE targeting: NPCs are the only enemies, every living human is an ally
-- (sv_npc.lua's shared closures -- same idiom as
-- modes/sv_masscasualty.lua's shooterEnemyOf/shooterAllyOf install).
----------------------------------------------------------------------

RB({
	name = "coop.pve_targeting",
	band = "MODE",
	order = 10,
	default = false,
	finalize = { path = true, roam = true },
	CanRun = function(ctx)
		if ctx.roundKey ~= "coop" then return false end
		local npcMod = hg.botdriver.npc
		if not npcMod then return false end
		ctx._enemyOf = npcMod.EnemyOfPve(ctx.bot)
		ctx._allyOf = npcMod.AllyOfPve(ctx.bot)
		local target = ctx:AcquireTarget()
		-- Decline (claim nothing) once a target is found so the shared
		-- ACQUIRE/COMBAT bands fight it; the ctx._enemyOf/_allyOf override
		-- installed above still applies for the rest of this decision.
		return not IsValid(target)
	end,
	Run = function(ctx)
		return runEscort(ctx)
	end,
})

----------------------------------------------------------------------
-- Escort band (brief item 4): stay 250-600u from the "leader" human
-- (approximated as the living human with the freshest forward movement --
-- BEHAVIOUR CHOICE, not dictated by the brief beyond the approximation
-- hint), never more than 400u ahead of it, sprint-regroup past 1200u, hold
-- position in cover if no human is alive.
----------------------------------------------------------------------

local ESCORT_MIN, ESCORT_MAX = 250, 600
local ESCORT_AHEAD_MAX = 400
local ESCORT_REGROUP_SPRINT = 1200

local function pickLeader(bot)
	local best, bestScore
	for _, ply in ipairs(player.GetHumans()) do
		if IsValid(ply) and ply:Alive() then
			local speed = ply:GetVelocity():Length2D()
			local score = speed - bot:GetPos():Distance(ply:GetPos()) * 0.02
			if not bestScore or score > bestScore then best, bestScore = ply, score end
		end
	end
	return best
end

runEscort = function(ctx)
	local bot, brain, now = ctx.bot, ctx.brain, ctx.now
	local leader = pickLeader(bot)
	if not IsValid(leader) then
		-- No human alive: hold position in cover.
		brain.forward, brain.side = 0, 0
		brain.path = nil
		return true
	end

	local myPos, leaderPos = bot:GetPos(), leader:GetPos()
	local dist = myPos:Distance(leaderPos)

	if dist > ESCORT_REGROUP_SPRINT then
		brain.sprint = true
		lib.PathTo(bot, brain, leaderPos, now, 1)
		return true
	end

	local leaderVel = leader:GetVelocity()
	if leaderVel:Length2DSqr() > 100 then
		local fwd = leaderVel:GetNormalized()
		local ahead = (myPos - leaderPos):Dot(fwd)
		if ahead > ESCORT_AHEAD_MAX then
			lib.PathTo(bot, brain, leaderPos, now, 1)
			return true
		end
	end

	if dist > ESCORT_MAX then
		lib.PathTo(bot, brain, leaderPos, now, 1)
		return true
	end

	if dist < ESCORT_MIN then
		local away = myPos - leaderPos
		if away:LengthSqr() > 1 then
			away:Normalize()
			hg.botdriver.SetObjective(bot, myPos + away * (ESCORT_MIN - dist), 48, 2, "soft", "coop_escort_backoff")
			lib.ObjectiveTravel(bot, brain, now)
			return true
		end
	end

	return false -- inside the band: let IDLE/roam behave normally
end

hg.botdriver.RegisterModeProfile("coop", {
	behaviors = { "coop.avoid_changelevel_alone", "coop.pve_targeting" },
})
