-- Path traversal competence, restoring what Trauma's original 645-line
-- lua/homigrad/botdriver/sv_traverse.lua did and this package's Phase 1 port
-- cut to a single low-obstruction hop (see the old header this replaces).
-- Ported and re-verified against THIS package's own primitives; Trauma-only
-- deps are dropped, not stubbed:
--   * Trauma's actor/scheduler/objective-director/logging abstractions and
--     its custom-gamemode-profile and NPC-targeting paths (banned tokens per
--     TestBannedTokens) -- never referenced below.
--   * brain.blockedAreas (a per-bot TTL blacklist consulted by Trauma's own
--     FindPath) -- this package's hg.botdriver.FindPath (sv_nav.lua) takes no
--     brain argument and has no such blacklist. It DOES have a shared,
--     decayed PenalizeArea/PenalizeEdge learning map that A* already
--     consults, so blockAreaAt below bumps that instead of adding a second
--     mechanism nothing else reads (BEHAVIOUR CHOICE, see report).
--   * Slugcat class abilities (lib.SlugcatJumpButtons) -- a Trauma
--     playermodel feature; US1 has no Slugcat class (grepped this session).
--   * lib.ClearWalk/lib.MoveVector did not exist anywhere in this package
--     (grepped this session) even though Trauma's sv_traverse/sv_squadmove
--     both call them -- defined once here since this file loads right after
--     sv_nav.lua, ahead of every other file (sv_doors.lua, sv_squad.lua) that
--     will need them for door/formation work.
--
--   * hop ONLY when the obstacle is knee-high with clear headroom
--   * breakable clutter (reports health) gets smashed if the bot can fight
--   * gaps: reach = min(runSpeed, sprintSpeed) * (2*jumpPower/gravity) with a
--     safety margin; no landing inside reach -> penalize the connection and
--     sidestep instead of stalling into the wall forever
--   * windows: chest blocked but a chest-height opening with a verified
--     landing beyond it -> sprint, jump at the sill, tuck mid-air
--   * ladders: verified this session that NOTHING in Trauma's own botdriver
--     or either US1 truth tree ever handled a physical ladder for a bot
--     (grepped "ladder" case-insensitively across all three; Trauma's own
--     botdriver hits are a comment metaphor, not movement code). US1 ladders
--     work through the stock engine: touching a ladder brush switches ANY
--     player (bot included) to MOVETYPE_LADDER, and every player already has
--     SetLadderClimbSpeed configured (homigrad/movement/sh_inertia.lua:437,
--     436-441 setup block). This driver does not need to do anything to
--     CLIMB -- what was actually missing is that every obstacle probe below
--     reads a ladder rail as a flat wall and blocks/reroutes around it
--     forever, so lib.TraverseStep's first check skips diagnosis entirely
--     while MOVETYPE_LADDER is active. (US1 also has a second, custom ladder
--     point-entity, func_useableladder2 -- main-design-source/lua/entities/
--     func_useableladder2.lua -- whose Think() sets ent:SetNWEntity("Ladder",
--     self) on the touching player; grepped BOTH US1 trees for any reader of
--     GetNWEntity("Ladder") and found none. UNVERIFIED/likely inert even for
--     humans; not built against.)

hg = hg or {}
hg.botdriver = hg.botdriver or {}
hg.botdriver.lib = hg.botdriver.lib or {}
local lib = hg.botdriver.lib

local HOP_TRACE_DIST = 40
-- 2026-09-23 fix: the old probe pair (z+4 hit, z+20 clear) fired for exactly
-- the obstacles the engine already steps over (sv_stepsize 18) -- every stair
-- riser and every slope made the bot jump. A hop is only justified when
-- something taller than a step (probe at HOP_STEP_CLEAR) but lower than a
-- crate (probe at HOP_MAX_HEIGHT is clear) is ahead.
local HOP_STEP_CLEAR = 22
local HOP_MAX_HEIGHT = 46
local HOP_COOLDOWN = 0.6

local PROBE_HULL = Vector(13, 13, 1)
local PROBE_DIST = 55
local VAULT_SPEED = 330       -- sprint-ish horizontal speed for reach math
local VAULT_MARGIN = 0.9
local UNSTICK_TIME = 0.55
local UNSTICK_SPEED = 180

-- Fires before sv_doors.lua's staged escalation (1.2s) and sv_brain.lua's
-- blunt universal fallback (bumped there to 1.6s -- see that file: it used to
-- be 0.9s, which fired BEFORE this or sv_doors' escalation ever got a turn
-- and wiped brain.path out from under both every single time, verified by
-- reading the call order this session). Real diagnosis gets first crack at a
-- stall now; the staged/blunt layers stay as backstops for whatever this
-- doesn't resolve.
local FAST_STUCK_TIME = 0.5
local STUCK_EPS = 12

local PROP_CLASSES = {
	prop_physics = true,
	prop_physics_multiplayer = true,
	prop_dynamic = true,
	func_breakable = true,
	func_breakable_surf = true,
}

local function probe(bot, pos, fwd, height, dist)
	return util.TraceHull({
		start = pos + vector_up * height,
		endpos = pos + vector_up * height + fwd * (dist or PROBE_DIST),
		filter = bot,
		mins = -PROBE_HULL,
		maxs = PROBE_HULL,
		mask = MASK_PLAYERSOLID,
	})
end

local function groundAt(bot, pos, depth)
	return util.TraceLine({
		start = pos,
		endpos = pos - vector_up * (depth or 160),
		filter = bot,
		mask = MASK_PLAYERSOLID,
	})
end

-- lib.ClearWalk: "is a straight line to `dest` actually walkable". Needed by
-- this file's own sidestep safety check and by sv_doors.lua/sv_squad.lua's
-- door/formation work later in the load order.
function lib.ClearWalk(bot, dest)
	local pos = bot:GetPos()
	local tr = util.TraceHull({
		start = pos + vector_up * 18,
		endpos = dest + vector_up * 18,
		filter = bot,
		mins = Vector(-14, -14, 0),
		maxs = Vector(14, 14, 56),
		mask = MASK_PLAYERSOLID,
	})
	return not tr.Hit and not tr.StartSolid
end

-- lib.MoveVector: the world-space direction brain.moveAngles/brain.forward
-- actually drive (sv_control.lua projects onto moveAngles:Forward()/Right()).
-- Falls back to the look direction when no path heading is set yet (matches
-- how DiagnoseStuck/EdgeProbe used this in Trauma).
local function moveVector(brain)
	if brain.moveAngles then return brain.moveAngles:Forward() end
	if brain.viewAngles then return Angle(0, brain.viewAngles.y, 0):Forward() end
	return Vector(1, 0, 0)
end
lib.MoveVector = moveVector

local function startSidestep(bot, brain, fwd, now)
	local moveAng = Angle(0, fwd:Angle().yaw, 0)
	local right = moveAng:Right()
	-- attempts count EXECUTED maneuvers only; the increment happens once a
	-- safe side is actually committed below, not for merely looking for one
	local preferRight = ((brain.unstickAttempts or 0) + 1 + bot:EntIndex()) % 2 == 0
	local first = preferRight and right or -right
	local second = -first
	local pos = bot:GetPos()
	local side

	local function sideIsSafe(dir)
		local dest = pos + dir * 60
		if not lib.ClearWalk(bot, dest) then return false end
		return groundAt(bot, dest + vector_up * 18, 120).Hit
	end

	if sideIsSafe(first) then
		side = first
	elseif sideIsSafe(second) then
		side = second
	elseif sideIsSafe(-fwd) then
		side = -fwd
	else
		-- no safe sidestep: back straight out the way we came instead of
		-- standing in place repeating the same diagnosis (walked ground is
		-- known-safe). Not counted as an attempt -- nothing new was tried.
		brain.unstick = { dir = -fwd, until_ = now + UNSTICK_TIME }
		brain.nextRepath = 0
		return false
	end

	brain.unstickAttempts = (brain.unstickAttempts or 0) + 1
	local dir = side + fwd * 0.2
	dir.z = 0
	dir:Normalize()
	brain.unstick = { dir = dir, until_ = now + UNSTICK_TIME }
	brain.nextRepath = 0
	return true
end

-- See the file header's BEHAVIOUR CHOICE: this package has no per-bot
-- blockedAreas blacklist, so a static-cause block bumps the shared
-- PenalizeArea/PenalizeEdge learning map (sv_nav.lua) instead, hard enough on
-- an escalated (repeatedly stuck) call to actually clear PENALTY_THRESHOLD
-- and reroute, rather than only ever nudging it by one.
local function blockAreaAt(bot, brain, pos, escalate)
	if navmesh.IsLoaded() then
		local area = navmesh.GetNearestNavArea(pos, false, 220, true, true)
		local hereArea = navmesh.GetNearestNavArea(bot:GetPos(), false, 220, true, true)
		local amount = escalate and 12 or 1
		if IsValid(area) and hg.botdriver.PenalizeArea then
			hg.botdriver.PenalizeArea(area:GetID(), amount)
		end
		if IsValid(area) and IsValid(hereArea) and hereArea ~= area and hg.botdriver.PenalizeEdge then
			hg.botdriver.PenalizeEdge(hereArea:GetID(), area:GetID(), amount)
		end
	end
	-- A failed patrol leg did not arrive, so it must not receive Roam's
	-- arrival pause when the path is discarded for recovery.
	if brain.roamPath == brain.path then
		brain.roamPath = nil
		brain.roamGoal = nil
	end
	brain.path = nil
	brain.nextRepath = 0
end
lib.BlockAreaAt = blockAreaAt

local function startVault(brain, takeoff, land, window, now)
	brain.vault = { takeoff = takeoff, land = land, window = window, until_ = now + 3 }
end

-- A landing is only safe when it's near-flat and a standing player fits
-- there -- "any trace hit" would count railings/steep banks/prop tops as
-- ground and commit the bot to an impossible vault.
local function landingSafe(bot, tr)
	if not tr.Hit or tr.HitNormal.z < 0.7 then return false end
	local room = util.TraceHull({
		start = tr.HitPos + vector_up * 4,
		endpos = tr.HitPos + vector_up * 4,
		filter = bot,
		mins = Vector(-14, -14, 0),
		maxs = Vector(14, 14, 66),
		mask = MASK_PLAYERSOLID,
	})
	return not room.Hit and not room.StartSolid
end

-- Probe for a landing spot within jump reach; commit to a vault if found.
local function tryGapVault(bot, brain, now, fwd)
	local jumpPower = bot:GetJumpPower()
	local gravity = GetConVar("sv_gravity"):GetFloat()
	if jumpPower <= 0 or gravity <= 0 then return false end

	-- this bot's actual run speed (class/injury/scale modifiers), not one
	-- hardcoded sprint figure for every bot -- verified bot:GetRunSpeed()
	-- exists and applies to every player (main-design-source/lua/homigrad/
	-- movement/sh_inertia.lua uses it unconditionally, not gated to a class).
	local runSpeed = bot.GetRunSpeed and bot:GetRunSpeed() or 0
	if not isnumber(runSpeed) or runSpeed <= 0 then runSpeed = VAULT_SPEED end
	local reach = math.min(runSpeed, VAULT_SPEED) * (2 * jumpPower / gravity) * VAULT_MARGIN
	local pos = bot:GetPos()

	local dist = 60
	while dist <= reach do
		local start = pos + fwd * dist + vector_up * 20
		local tr = groundAt(bot, start, 180)
		if landingSafe(bot, tr) then
			startVault(brain, pos + fwd * 25, tr.HitPos, false, now)
			return true
		end
		dist = dist + 25
	end
	return false
end

-- A window: chest-height probe blocked, but a person-sized opening slightly
-- higher is clear and there's ground on the far side.
local function windowLanding(bot, pos, fwd)
	local slot = probe(bot, pos, fwd, 52, 70)
	if slot.Hit then return nil end
	local far = groundAt(bot, pos + fwd * 120 + vector_up * 52, 220)
	if not landingSafe(bot, far) then return nil end
	return far.HitPos
end

-- Diagnose WHY the bot stopped making progress and pick a justified recovery
-- instead of a blind jump. Returns an immediate button mask (a justified hop)
-- or 0; longer actions (unstick/vault/break) land in brain state for
-- lib.TraverseStep's active-state handling below to drive.
local function diagnoseStuck(bot, brain, now, escalate)
	local fwd = moveVector(brain)
	local pos = bot:GetPos()

	local knee = probe(bot, pos, fwd, 18)

	-- nothing solid at knee height: catching on a ledge lip or a gap
	if not knee.Hit then
		if tryGapVault(bot, brain, now, fwd) then return 0 end
		blockAreaAt(bot, brain, pos + fwd * 50, escalate)
		startSidestep(bot, brain, fwd, now)
		return 0
	end

	local ent = knee.Entity
	local isProp = IsValid(ent) and PROP_CLASSES[ent:GetClass()]

	-- Players/NPCs are transient traffic, not broken geometry -- sidestep,
	-- never blacklist their nav area.
	if IsValid(ent) and ((ent.IsPlayer and ent:IsPlayer())
		or (ent.IsNPC and ent:IsNPC()) or (ent.IsNextBot and ent:IsNextBot())) then
		startSidestep(bot, brain, fwd, now)
		return 0
	end

	local canFight = hg.botdriver.CanFight and hg.botdriver.CanFight(bot)
	if isProp and ent:Health() > 0 and canFight then
		brain.breakAttempts = brain.breakAttempts or {}
		local attempts = brain.breakAttempts[ent] or 0
		if attempts < 3 then
			brain.breakAttempts[ent] = attempts + 1
			brain.breakTarget = { ent = ent, until_ = now + 1.2 }
			return 0
		end
	elseif isProp and ent:Health() <= 0 then
		local phys = ent:GetPhysicsObject()
		if IsValid(phys) and phys:IsMotionEnabled() and phys:GetMass() <= 60 then
			-- light loose clutter: a committed forward shove moves it
			brain.unstick = { dir = fwd, until_ = now + UNSTICK_TIME }
			brain.nextRepath = 0
			return 0
		end
		-- heavy/frozen prop: fall through -- it's a wall, hop or route around
	end

	local chest = probe(bot, pos, fwd, 48)
	local head = probe(bot, pos, fwd, 68)

	-- knee-high with headroom: the one case a hop is actually justified --
	-- unless this is a staircase, where the knee probe simply read the next
	-- riser and the engine steps up on its own.
	local onStairs = lib.OnStairs and lib.OnStairs(bot, brain, now)
	if not chest.Hit and not head.Hit then
		if onStairs then
			blockAreaAt(bot, brain, knee.HitPos, escalate)
			startSidestep(bot, brain, fwd, now)
			return 0
		end
		return bit.bor(IN_JUMP, IN_DUCK)
	end

	-- chest blocked but a window opening above it, with a verified landing
	local windowLand = chest.Hit and windowLanding(bot, pos, fwd) or nil
	if windowLand then
		startVault(brain, pos, windowLand, true, now)
		return 0
	end

	-- short loose prop (jumpable even though it clipped the chest probe)
	if isProp and not onStairs then
		local _, obbTop = ent:WorldSpaceAABB()
		if (obbTop.z - pos.z) < 34 then
			return bit.bor(IN_JUMP, IN_DUCK)
		end
	end

	-- a wall, a tall prop, a locked grate: this way is not a way
	blockAreaAt(bot, brain, knee.HitPos, escalate)
	startSidestep(bot, brain, fwd, now)
	return 0
end

-- Active traversal states + fast stuck diagnosis + the Phase 1 low-obstacle
-- hop, all in one seam sv_doors.lua wraps. Returns true when it owns the
-- tick (skip FollowPath's normal steering this decision).
function lib.TraverseStep(bot, brain)
	if not IsValid(bot) then return false end
	local now = CurTime()

	-- Ladders: see file header. The engine already owns vertical movement
	-- once the bot's hull touches the ladder brush; every probe below would
	-- read the rail as a flat wall, so skip diagnosis entirely while climbing
	-- and clear the stuck tracker so leaving the ladder doesn't replay a
	-- stale stuck timer accumulated while legitimately climbing in place.
	if bot:GetMoveType() == MOVETYPE_LADDER then
		brain.traverseStuckPos = nil
		brain.traverseStuckAt = nil
		return false
	end

	local unstick = brain.unstick
	if unstick then
		if now > unstick.until_ then
			brain.unstick = nil
		else
			local moveAng = Angle(0, unstick.dir:Angle().yaw, 0)
			brain.moveAngles = moveAng
			if not brain.aimLocked then lib.SetLookAngles(brain, moveAng, "traverse:unstick", true) end
			brain.forward = UNSTICK_SPEED
			-- an active recovery IS progress; keep sv_brain.lua's blunt
			-- StuckCheck from also firing mid-maneuver.
			brain.progressAt = now
			brain.progressPos = bot:GetPos()
			return true
		end
	end

	local bt = brain.breakTarget
	if bt then
		if not IsValid(bt.ent) or bt.ent:Health() <= 0 or now > bt.until_ then
			brain.breakTarget = nil
		else
			lib.LookAt(bot, brain, bt.ent:WorldSpaceCenter(), "traverse:break", true)
			brain.forward = 0
			brain.traverseButtons = bit.bor(brain.traverseButtons or 0, IN_ATTACK)
			brain.progressAt = now
			brain.progressPos = bot:GetPos()
			return true
		end
	end

	local v = brain.vault
	if v then
		if now > v.until_ then
			brain.vault = nil
		else
			local pos = bot:GetPos()
			local flat = v.land - pos
			flat.z = 0
			local moveAng = flat:Angle()
			brain.moveAngles = moveAng
			lib.SetLookAngles(brain, moveAng, "traverse:vault", true)
			brain.forward = 400
			brain.sprint = true -- run-up must actually sprint (sv_control adds IN_FORWARD)
			brain.traverseButtons = bit.bor(brain.traverseButtons or 0, IN_SPEED)
			brain.progressAt = now
			brain.progressPos = pos

			if not v.jumpedAt then
				local toTakeoff = v.takeoff - pos
				toTakeoff.z = 0
				local course = v.land - v.takeoff
				course.z = 0
				local courseLenSqr = course:LengthSqr()
				local progress = (-toTakeoff):Dot(course)
				local crossedTakeoff = courseLenSqr > 1 and progress >= 0 and progress <= courseLenSqr
				if toTakeoff:Length() < 25 or crossedTakeoff then
					brain.traverseButtons = bit.bor(brain.traverseButtons, IN_JUMP)
					v.jumpedAt = now
				end
				return true
			end

			if not bot:IsOnGround() and now - v.jumpedAt > 0.1 then
				brain.traverseButtons = bit.bor(brain.traverseButtons, IN_DUCK)
			end
			if bot:IsOnGround() and now - v.jumpedAt > 0.25 then
				brain.vault = nil -- landed
			end
			return true
		end
	end

	-- Fast stuck diagnosis: see FAST_STUCK_TIME's comment for why this must
	-- run (and fire) before sv_doors.lua's staged escalation and sv_brain's
	-- blunt fallback.
	if brain.path and not IsValid(brain.doorTarget) then
		local pos = bot:GetPos()
		local moving = not (brain.actionPolicy and brain.actionPolicy.lockMove)
			and not (brain.survival and brain.survival.body and brain.survival.body.movementSuppressed)
		if not moving or not brain.traverseStuckPos then
			brain.traverseStuckPos = pos
			brain.traverseStuckAt = now
		elseif pos:DistToSqr(brain.traverseStuckPos) > STUCK_EPS * STUCK_EPS then
			brain.traverseStuckPos = pos
			brain.traverseStuckAt = now
		elseif now - brain.traverseStuckAt > FAST_STUCK_TIME then
			brain.traverseStuckPos = pos
			brain.traverseStuckAt = now
			local escalate = (brain.unstickAttempts or 0) > 3
			local buttons = diagnoseStuck(bot, brain, now, escalate)
			if buttons ~= 0 then
				brain.traverseButtons = bit.bor(brain.traverseButtons or 0, buttons)
			end
			brain.progressAt = now
			brain.progressPos = pos
			return true
		end
	else
		brain.traverseStuckPos = nil
	end

	-- Phase 1 behaviour, kept as a cheaper continuous pass ahead of the fuse
	-- above: hop a short obstruction with clear headroom before it ever
	-- becomes a full stall (curbs/small ledges -- "not stopping on small
	-- ledges").
	if now >= (brain.nextHopCheck or 0) then
		brain.nextHopCheck = now + 0.2
		local wp = brain.path and brain.path[brain.pathIdx]
		if isvector(wp) then
			local pos = bot:GetPos()
			local dir = wp - pos
			dir.z = 0
			if dir:LengthSqr() >= 1 then
				dir:Normalize()
				local lowTrace = util.TraceLine({
					start = pos + Vector(0, 0, HOP_STEP_CLEAR),
					endpos = pos + Vector(0, 0, HOP_STEP_CLEAR) + dir * HOP_TRACE_DIST,
					filter = bot,
					mask = MASK_PLAYERSOLID,
				})
				local lowEnt = lowTrace.Entity
				local lowIsActor = IsValid(lowEnt) and (lowEnt:IsPlayer() or (lowEnt.IsNPC and lowEnt:IsNPC()))
				local onStairs = lib.OnStairs and lib.OnStairs(bot, brain, now)
				if lowTrace.Hit and not lowIsActor and bot:IsOnGround() and not onStairs then
					local highTrace = util.TraceLine({
						start = pos + Vector(0, 0, HOP_MAX_HEIGHT),
						endpos = pos + Vector(0, 0, HOP_MAX_HEIGHT) + dir * HOP_TRACE_DIST,
						filter = bot,
						mask = MASK_PLAYERSOLID,
					})
					if not highTrace.Hit and now >= (brain.nextHop or 0) then
						brain.nextHop = now + HOP_COOLDOWN
						brain.traverseButtons = bit.bor(brain.traverseButtons or 0, IN_JUMP)
						hg.botdriver.stats = hg.botdriver.stats or {}
						hg.botdriver.stats.hops = (hg.botdriver.stats.hops or 0) + 1
					end
				end
			end
		end
	end

	return false
end

----------------------------------------------------------------------
-- Nav posture: duck ONLY for a real measured low ceiling, never a navmesh
-- CROUCH-attribute proxy (auto-generated meshes over-flag whole open areas as
-- crouch; measuring the actual overhead means an over-flagged mesh can never
-- force a crouch, and a genuinely low ceiling always does).
----------------------------------------------------------------------

local HEAD_HULL = Vector(14, 14, 1) -- half-extents at model scale 1
local DUCK_TOP = 40   -- just above the crouched hull, below standing shoulders
local STAND_TOP = 72  -- top of the standing hull

-- True when there is headroom to STAND at pos; false means the bot must duck.
-- Scales with GetModelScale so a resized body (!setscale, Giant/Tiny) measures
-- its own clearance.
function lib.HeadClear(bot, pos)
	local scale = (bot.GetModelScale and bot:GetModelScale()) or 1
	if not isnumber(scale) or scale <= 0 then scale = 1 end
	local rad = HEAD_HULL.x * scale
	local hullMaxs = Vector(rad, rad, HEAD_HULL.z)
	local hullMins = -hullMaxs
	-- Only world geometry and props should force a crouch; a teammate or a
	-- corpse standing/lying in the overhead column must never duck-walk the
	-- bot for no reason (a body is never a ceiling).
	local tr = util.TraceHull({
		start = pos + vector_up * (DUCK_TOP * scale),
		endpos = pos + vector_up * (STAND_TOP * scale),
		filter = function(e) return e ~= bot and IsValid(e) and not e:IsPlayer() and not e:IsNPC() and not (e.IsRagdoll and e:IsRagdoll()) end,
		mins = hullMins,
		maxs = hullMaxs,
		mask = MASK_PLAYERSOLID,
	})
	return not (tr.Hit or tr.StartSolid)
end

-- Called from FollowPath with the current waypoint: duck for the low ceiling
-- the bot is under OR the one it's about to enter, so the tuck happens a beat
-- before the opening rather than wedging at it. Skips entirely on a ladder --
-- a ladder shaft reads as tight overhead by this same probe and would
-- otherwise duck-walk a climbing bot for no reason.
function lib.NavPosture(bot, brain, waypoint)
	if bot:GetMoveType() == MOVETYPE_LADDER then return end
	local now = CurTime()
	if now >= (brain.nextNavPosture or 0) then
		brain.nextNavPosture = now + 0.15
		local hereLow = not lib.HeadClear(bot, bot:GetPos())
		local aheadLow = isvector(waypoint) and not lib.HeadClear(bot, waypoint) or false
		brain.navMustCrouch = hereLow or aheadLow
	end
	if brain.navMustCrouch then
		brain.traverseButtons = bit.bor(brain.traverseButtons or 0, IN_DUCK)
	end
end

----------------------------------------------------------------------
-- Gait moved to sv_movement.lua (lib.Gait) on 2026-09-23: sprint by default,
-- run in tight geometry / near the goal / around combat, slow-walk (IN_WALK)
-- to listen. lib.GaitSelect is kept there as an alias.
----------------------------------------------------------------------

----------------------------------------------------------------------
-- Proactive edge watch while walking a path: spot a dropoff BEFORE stumbling
-- over it, and either commit to a jump or route around. Called from the tail
-- of FollowPath (forward speed already decided by then).
----------------------------------------------------------------------

function lib.EdgeProbe(bot, brain)
	if brain.vault or not brain.path or (brain.forward or 0) <= 0 then return end
	if bot:GetMoveType() == MOVETYPE_LADDER then return end

	local now = CurTime()
	if now < (brain.nextEdgeProbe or 0) then return end
	brain.nextEdgeProbe = now + 0.3

	if not bot:IsOnGround() then return end

	local fwd = moveVector(brain)
	local ahead = bot:GetPos() + fwd * 45 + vector_up * 18
	local tr = groundAt(bot, ahead, 120)
	if tr.Hit then return end

	if not tryGapVault(bot, brain, now, fwd) then
		blockAreaAt(bot, brain, bot:GetPos() + fwd * 60, false)
	end
end

hg.botdriver.DeclareBrainState("traverse", {
	fields = {
		"unstick", "unstickAttempts", "vault", "breakTarget", "breakAttempts",
		"winded", "nextEdgeProbe", "nextNavPosture", "navMustCrouch",
		"traverseStuckPos", "traverseStuckAt", "pathGoal",
	},
})
