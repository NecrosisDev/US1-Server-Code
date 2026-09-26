-- Movement policy: the one place that decides HOW a bot moves along a path
-- and WHERE it looks while doing so, plus the two safety nets around it.
-- Loads after sv_steer.lua (heading) and before sv_doors.lua. Called from
-- sv_brain.lua's lib.FollowPath / finalize; consumed by sv_traverse.lua,
-- sv_doors.lua and lib.StuckCheck for the stairs guard.
--
--   lib.Gait(bot, brain, now)            sprint / run / walk tier -> brain.sprint,
--                                        brain.forward scale, IN_SPEED / IN_WALK
--   lib.TravelGaze(bot, brain, wp, ...)  where the eyes go while travelling
--   lib.OnStairs(bot, brain, now)        true on a navmesh STAIRS area (never jump)
--   lib.StallWatch(bot, brain, now)      "hung in one spot" watchdog
--
-- GAIT (owner ask, 2026-09-23): people sprint to get places. They drop to a
-- run around fights, at a door they must open, on the last stretch to a
-- goal (2026-09-26: no longer in every narrow doorway), and only
-- slow-walk (IN_WALK: quieter footsteps on this fork, sh_footsteps.lua) when
-- they have HEARD something nearby and want information, or when creeping up
-- on a last-known position. Combat never sprints (IN_SPEED blocks fire).
--
-- GAZE: the old follower pointed the head at each waypoint, so the aim was
-- welded to the feet and snapped at every node. Now the eyes lead 2-3 nodes
-- down the corridor with a slow personality-scaled sweep and occasional side
-- glances; sv_aim.lua turns the head with smooth pursuit for these (only
-- reactive glances -- damage, sounds, double-takes -- are saccades).
--
-- Cost: no traces. OnStairs does two navmesh lookups per 0.3 s per bot.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}
hg.botdriver.lib = hg.botdriver.lib or {}
local lib = hg.botdriver.lib

hg.botdriver.DeclareBrainState("movement", { fields = {
	"gait", "gaitWalkUntil", "winded", "gaitPrev", "gaitHoldUntil",
	"gazeSweepPhase", "gazeGlanceAt", "gazeGlanceUntil", "gazeGlanceYaw", "gazeSweepAmp",
	"stairsAt", "stairsNow",
	"stallPos", "stallAt", "stallCount",
} })

hg.botdriver.stats = hg.botdriver.stats or {}
local stats = hg.botdriver.stats

----------------------------------------------------------------------
-- Stairs guard
----------------------------------------------------------------------

local STAIRS_ATTR = NAV_MESH_STAIRS or 4096
local STAIRS_CACHE = 0.3
local STAIRS_LOOKAHEAD = 48

function lib.OnStairs(bot, brain, now)
	now = now or CurTime()
	if now < (brain.stairsAt or 0) then return brain.stairsNow == true end
	brain.stairsAt = now + STAIRS_CACHE
	brain.stairsNow = false
	if not navmesh.IsLoaded() then return false end
	local pos = bot:GetPos()
	local area = navmesh.GetNearestNavArea(pos, false, 64, false, true)
	if IsValid(area) and area.HasAttributes and area:HasAttributes(STAIRS_ATTR) then
		brain.stairsNow = true
		return true
	end
	local fwd = lib.MoveVector and lib.MoveVector(brain) or bot:GetAimVector()
	local ahead = navmesh.GetNearestNavArea(pos + fwd * STAIRS_LOOKAHEAD, false, 64, false, true)
	if IsValid(ahead) and ahead.HasAttributes and ahead:HasAttributes(STAIRS_ATTR) then
		brain.stairsNow = true
		return true
	end
	return false
end

----------------------------------------------------------------------
-- Gait
----------------------------------------------------------------------

local SPRINT_MIN_REMAINING = 260   -- units of path left below which we ease to a run
local HEARD_WALK_WINDOW = 10       -- seconds after a nearby sound worth creeping for
local HEARD_WALK_RANGE = 900
local SEEN_NO_SPRINT_WINDOW = 5    -- seconds after last sight of an enemy: no sprinting
local WALK_SPEED = 120             -- forward magnitude while slow-walking (engine caps at slow-walk speed)
local RUN_SPEED = 250
local SPRINT_SPEED = 400           -- engine caps at run speed

local COMBAT_STATES = { engage = true, melee = true, ["melee-evade"] = true, disengage = true }
local URGENT_STATES = { disengage = true, homicide_rush = true }

local function remainingPathLength(bot, brain)
	local path, idx = brain.path, brain.pathIdx or 1
	if not path then return 0 end
	local total = 0
	local prev = bot:GetPos()
	local n = #path
	-- Bounded: only sum the next few legs; beyond that it is "far" anyway.
	for i = idx, math.min(n, idx + 4) do
		local p = path[i]
		if isvector(p) then
			total = total + prev:Distance(p)
			prev = p
		end
	end
	if n > idx + 4 then total = total + 1000 end
	return total
end

local function setRun(brain)
	brain.gait = "run"
	brain.forward = math.min(brain.forward, RUN_SPEED)
end

-- Sets brain.gait and the movement magnitude/buttons for this decision.
-- Assumes brain.forward was set by the follower (positive = travelling).
function lib.Gait(bot, brain, now)
	brain.sprint = false
	if (brain.forward or 0) <= 0 then brain.gait = "hold" return end
	if brain.vault then brain.gait = "sprint" brain.sprint = true return end -- run-up owns it

	-- Carrying a body: never sprint (the carry link snaps).
	local wep = bot:GetActiveWeapon()
	if IsValid(wep) and IsValid(wep.CarryEnt) then brain.gait = "run" return end

	local state = brain.state
	local urgent = URGENT_STATES[state] == true
	local personality = brain.personality
	local aggression = personality and personality.aggression or 0.5
	local patience = personality and personality.patience or 1

	-- Threat picture.
	local sawEnemyRecently = now - (brain.lastSeenTime or -math.huge) < SEEN_NO_SPRINT_WINDOW
	local heardRecently = isvector(brain.heardPos) and now - (brain.heardAt or -math.huge) < HEARD_WALK_WINDOW * patience
		and bot:GetPos():DistToSqr(brain.heardPos) <= HEARD_WALK_RANGE * HEARD_WALK_RANGE
	local hurtRecently = now - (brain.damageAt or -math.huge) < 3
	-- 2026-09-26: an investigation used to creep the WHOLE way (even from
	-- across the map), overriding its own approach sprint. Creep only for
	-- the last stretch to the spot being checked.
	local investigatingNear = state == "investigate" and isvector(brain.investigatePos)
		and bot:GetPos():DistToSqr(brain.investigatePos) < 650 * 650
	local creeping = investigatingNear or (heardRecently and not IsValid(brain.target))

	-- Slow walk: information gathering. Not while urgent, not while a target
	-- is live (Engage owns combat movement), and hotheads creep less.
	if creeping and not urgent and not brain.aimLocked and not hurtRecently and aggression < 0.85 then
		brain.gait = "walk"
		brain.forward = math.min(brain.forward, WALK_SPEED)
		brain.traverseButtons = bit.bor(brain.traverseButtons or 0, IN_WALK)
		return
	end

	-- Run (no sprint) when: fighting or just fought, tight geometry, a door
	-- is being handled, nearly there, or winded.
	local org = bot.organism
	local stam = org and istable(org.stamina) and org.stamina or nil
	if stam then
		local max = stam.max or 100
		local cur = stam[1] or max
		if brain.winded then
			if cur > max * 0.5 then brain.winded = nil end
		elseif cur < max * 0.2 then
			brain.winded = true
		end
	end
	-- 2026-09-26: hard reasons always force a run. Soft reasons (nearly
	-- there, still turning onto the route) used to flip sprint<->run on any
	-- decision, and narrow nav areas were a reason too -- on a fragmented
	-- mesh that toggled IN_SPEED every few metres: speed surging and the gun
	-- bobbing between sprint pose and ready. Narrow areas no longer stop a
	-- sprint (people sprint through doorways), turning uses a 45/70 degree
	-- band, and a soft change of gait holds for about a second.
	local hardNoSprint = brain.winded or brain.aimLocked or COMBAT_STATES[state] == true
		or (sawEnemyRecently and not urgent) or IsValid(brain.doorTarget)
		or bot:Crouching() or brain.navMustCrouch
	if hardNoSprint then
		brain.gaitPrev = "run"
		return setRun(brain)
	end

	local softNoSprint = remainingPathLength(bot, brain) < SPRINT_MIN_REMAINING
	-- Do not launch into a sprint while the body is still rotating onto the
	-- route (reads as moonwalking); the gaze may look elsewhere, so compare
	-- the MOVE heading, not the eyes.
	if not softNoSprint and brain.moveAngles and not urgent then
		local turnError = math.abs(math.AngleDifference(brain.moveAngles.y, bot:EyeAngles().y))
		softNoSprint = turnError > (brain.gaitPrev == "sprint" and 70 or 45)
	end
	local want = softNoSprint and "run" or "sprint"
	local prev = brain.gaitPrev
	if prev and prev ~= want and (prev == "run" or prev == "sprint") and now < (brain.gaitHoldUntil or 0) then
		want = prev
	elseif prev ~= want then
		brain.gaitHoldUntil = now + math.Rand(0.8, 1.4)
	end
	brain.gaitPrev = want
	if want == "run" then return setRun(brain) end
	brain.gait = "sprint"
	brain.sprint = true
	brain.forward = SPRINT_SPEED
	brain.traverseButtons = bit.bor(brain.traverseButtons or 0, IN_SPEED)
end

-- Kept for any caller still using the old name.
lib.GaitSelect = lib.Gait

----------------------------------------------------------------------
-- Travel gaze
----------------------------------------------------------------------

local GAZE_EYE_Z = 64
local GAZE_LEAD_NODES = 2
local GAZE_SWEEP_HZ = 0.32
local GAZE_GLANCE_MIN, GAZE_GLANCE_MAX = 2.5, 6.5
local GAZE_GLANCE_HOLD_MIN, GAZE_GLANCE_HOLD_MAX = 0.5, 1.1

function lib.TravelGaze(bot, brain, wp, steerWp, distToWp, now)
	local path, idx = brain.path, brain.pathIdx or 1
	local personality = brain.personality
	local curiosity = personality and personality.curiosity or 0.5
	if not brain.gazeSweepPhase then
		brain.gazeSweepPhase = math.Rand(0, 6.283)
		brain.gazeSweepAmp = 10 + 22 * curiosity
	end

	-- Base: lead down the corridor. Near a sharp corner the lead node is
	-- around the bend, which is exactly where a person looks.
	local lookNode = steerWp
	if path then
		local leadIdx = math.min(idx + GAZE_LEAD_NODES, #path)
		if isvector(path[leadIdx]) then lookNode = path[leadIdx] end
	end
	local eye = bot:EyePos()
	local flat = lookNode - bot:GetPos()
	flat.z = 0
	local baseYaw = flat:LengthSqr() > 1 and flat:Angle().y or bot:EyeAngles().y
	local basePitch = math.Clamp((lookNode.z + GAZE_EYE_Z - eye.z) / math.max(flat:Length(), 64), -0.6, 0.6) * -45

	-- Side glances: brief looks toward a flank, more often for curious bots;
	-- a heard sound, if recent, is what gets glanced at instead of a random side.
	local yawOffset
	if now < (brain.gazeGlanceUntil or 0) then
		yawOffset = brain.gazeGlanceYaw
	else
		if now >= (brain.gazeGlanceAt or 0) then
			local period = math.Rand(GAZE_GLANCE_MIN, GAZE_GLANCE_MAX) * (1.4 - 0.8 * curiosity)
			brain.gazeGlanceAt = now + period
			brain.gazeGlanceUntil = now + math.Rand(GAZE_GLANCE_HOLD_MIN, GAZE_GLANCE_HOLD_MAX)
			if isvector(brain.heardPos) and now - (brain.heardAt or -math.huge) < 8 then
				local toHeard = brain.heardPos - bot:GetPos()
				toHeard.z = 0
				brain.gazeGlanceYaw = toHeard:LengthSqr() > 1 and math.AngleDifference(toHeard:Angle().y, baseYaw) or 0
			else
				brain.gazeGlanceYaw = ((bot:EntIndex() + math.floor(now)) % 2 == 0 and 1 or -1) * math.Rand(45, 95)
			end
			yawOffset = brain.gazeGlanceYaw
		else
			yawOffset = math.sin(now * 6.283 * GAZE_SWEEP_HZ + brain.gazeSweepPhase) * brain.gazeSweepAmp
		end
	end

	-- Never glance further than the body can comfortably keep walking with.
	local gait = brain.gait
	if gait == "sprint" then yawOffset = math.Clamp(yawOffset, -40, 40) end

	lib.SetLookAngles(brain, Angle(basePitch, baseYaw + yawOffset, 0), "travel", false)
	return true
end

----------------------------------------------------------------------
-- Stall watchdog: a bot that has not moved for STALL_TIME seconds while it
-- had no reason to stand still gets its movement intent wiped and a fresh,
-- distant goal. The staged stuck layers (sv_traverse fast diagnosis,
-- sv_doors escalation, sv_brain blunt fallback) handle a bot pushing against
-- something; this handles a bot that is not pushing at all -- a search job
-- waiting on budget, a stale objective, an arrival pause that never ended.
----------------------------------------------------------------------

local STALL_TIME = 7
local STALL_EPS = 24

local function intentionallyStill(bot, brain, now)
	if hg.botdriver.IsDowned(bot) then return true end
	if brain.actionPolicy and brain.actionPolicy.lockMove then return true end
	if now < (brain.spawnHoldUntil or 0) then return true end
	if now < (brain.peekHiddenUntil or 0) then return true end
	if brain.doorPhase or brain.vault or brain.breakTarget or brain.unstick then return true end
	if bot:GetMoveType() == MOVETYPE_LADDER then return true end
	if brain.aimLocked and IsValid(brain.target) then return true end
	if now < (brain.medicStartAt or 0) + 10 and brain.medicStartAt then return true end
	if brain.lootHoldStart or now < (brain.lootRummageUntil or 0) then return true end
	if isvector(brain.objectivePos) and brain.objectivePhase == "arrived" and now <= (brain.objectiveExpire or 0) then return true end
	return false
end

function lib.StallWatch(bot, brain, now)
	local pos = bot:GetPos()
	if not brain.stallPos or pos:DistToSqr(brain.stallPos) > STALL_EPS * STALL_EPS or intentionallyStill(bot, brain, now) then
		brain.stallPos = pos
		brain.stallAt = now
		return false
	end
	if now - (brain.stallAt or now) < STALL_TIME then return false end

	-- Hung. Wipe every movement intent that could be stale and start over.
	brain.stallAt = now
	brain.stallCount = (brain.stallCount or 0) + 1
	stats.stalls = (stats.stalls or 0) + 1
	brain.path, brain.pathMeta, brain.pathGoal = nil, nil, nil
	brain.roamPath, brain.roamGoal = nil, nil
	brain.roamPauseUntil, brain.nextRoam, brain.nextRepath = nil, 0, 0
	brain.combatPosition, brain.combatRoute = nil, nil
	brain.doorTarget, brain.doorPhase = nil, nil
	if brain.objectivePriority ~= "hard" then brain.objectivePos = nil end
	if navmesh.IsLoaded() and hg.botdriver.PenalizeArea then
		local area = navmesh.GetNearestNavArea(pos, false, 120, false, true)
		if IsValid(area) then hg.botdriver.PenalizeArea(area:GetID(), 4) end
	end
	-- A fresh distant goal so the next decision walks somewhere new.
	if hg.botdriver.RandomRoamPos then
		local goal = hg.botdriver.RandomRoamPos(pos, 2500)
		if goal and lib.PathTo then
			lib.PathTo(bot, brain, goal, now, 0)
			brain.roamPath, brain.roamGoal = brain.path, brain.path and goal or nil
		end
	end
	-- Third stall in one life without moving: last resort, a small hop out.
	if brain.stallCount >= 3 and not lib.OnStairs(bot, brain, now) then
		brain.traverseButtons = bit.bor(brain.traverseButtons or 0, IN_JUMP)
		brain.stallCount = 0
	end
	return true
end
