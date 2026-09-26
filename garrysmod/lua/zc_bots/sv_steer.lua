-- Local steering: proactive obstacle avoidance while following a path.
--
-- Before this file existed the driver walked the raw waypoint line and only
-- reacted to a prop, wall edge or another player AFTER a 0.5 s stall
-- (sv_traverse.lua's fast diagnosis) -- so every piece of clutter on the route
-- produced a visible bump-stop-sidestep. A person steers around things they
-- can see coming. This is classic context steering: a small fan of short hull
-- "whiskers" ahead of the bot in its movement direction, a danger value per
-- whisker from how soon it hits, and a blended heading toward the clearest
-- whisker, weighted to prefer small deviations. It runs at 10 Hz per bot and
-- caches its answer between samples, so the per-tick cost is a table read.
--
-- What it deliberately does NOT do:
--   * It never overrides an active traversal manoeuvre (vault / unstick /
--     break / door phases own the tick before FollowPath even calls us).
--   * Doors are not obstacles -- sv_doors.lua wants the bot walking straight
--     at them. Weapons/items/ragdolls are not obstacles -- players walk
--     through those on this server.
--   * A hit that is FURTHER than the current waypoint is ignored: the path
--     turns before it, so it is not in the way.
--   * Other players/NPCs are SOFT obstacles: slow down and slide past instead
--     of swerving wide -- people shoulder past each other in corridors.
--   * Inside a narrow nav area (doorway/tight corridor, flagged by
--     sv_nav.lua's path meta) the whiskers are shortened so wall proximity on
--     both sides does not produce oscillation; the bot just goes through.
--
-- Consumers: sv_brain.lua's lib.FollowPath calls lib.LocalSteer right after it
-- computes the raw heading, and uses the returned heading + speed multiplier.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}
hg.botdriver.lib = hg.botdriver.lib or {}
local lib = hg.botdriver.lib

local STEER_INTERVAL = 0.1
local WHISKER_ANGLES = { 0, 32, -32, 64, -64 }
local WHISKER_BASE_LEN = 44   -- units at standstill
local WHISKER_SPEED_LEN = 0.2 -- extra units per unit of commanded speed (250 -> +50)
local WHISKER_HULL = Vector(12, 12, 1)
local WHISKER_Z = 20          -- probe height: above step size, below a table top
local SOFT_SPEED_MUL = 0.55   -- speed while sliding past a person
local HARD_SPEED_MIN = 0.45   -- never slower than this for geometry (stuck layers need motion)
local NARROW_LEN_MUL = 0.6

local DOOR_CLASSES = { func_door = true, func_door_rotating = true, prop_door_rotating = true, prop_door = true }

hg.botdriver.DeclareBrainState("steer", { fields = {
	"steerAt", "steerYawOffset", "steerSpeedMul", "steerSoftUntil", "steerBlockedAt",
} })

hg.botdriver.stats = hg.botdriver.stats or {}
local stats = hg.botdriver.stats

-- Entities the whiskers pass through. Everything a human player's hull also
-- passes through (items, corpses) plus doors (handled by sv_doors.lua).
local function passable(ent, bot)
	if ent == bot then return true end
	if not IsValid(ent) then return false end
	if ent:IsWeapon() then return true end
	if ent.IsRagdoll and ent:IsRagdoll() then return true end
	local class = ent:GetClass()
	if DOOR_CLASSES[class] then return true end
	if string.sub(class, 1, 4) == "ent_" then return true end -- ent_ammo_/ent_armor_/ent_att_ loot
	return false
end

local traceData = { mins = -WHISKER_HULL, maxs = WHISKER_HULL, mask = MASK_PLAYERSOLID }

local function whisker(bot, origin, dir, len)
	traceData.start = origin
	traceData.endpos = origin + dir * len
	traceData.filter = function(ent) return not passable(ent, bot) end
	return util.TraceHull(traceData)
end

local function isSoft(ent)
	return IsValid(ent) and (ent:IsPlayer() or (ent.IsNPC and ent:IsNPC()) or (ent.IsNextBot and ent:IsNextBot()))
end

-- lib.LocalSteer(bot, brain, dirAng, speed, now) -> steeredAng, speedMul
-- dirAng: the raw heading FollowPath wants (Angle). speed: commanded forward.
function lib.LocalSteer(bot, brain, dirAng, speed, now)
	if not IsValid(bot) or not dirAng then return dirAng, 1 end
	if bot:GetMoveType() == MOVETYPE_LADDER then return dirAng, 1 end
	if not bot:IsOnGround() then return dirAng, 1 end

	if now < (brain.steerAt or 0) then
		local off = brain.steerYawOffset or 0
		if off ~= 0 or (brain.steerSpeedMul or 1) ~= 1 then
			return Angle(0, dirAng.y + off, 0), brain.steerSpeedMul or 1
		end
		return dirAng, 1
	end
	brain.steerAt = now + STEER_INTERVAL

	local pos = bot:GetPos()
	local origin = pos + vector_up * WHISKER_Z
	local len = WHISKER_BASE_LEN + math.abs(speed or 250) * WHISKER_SPEED_LEN
	local meta = brain.pathMeta
	local narrow = meta and meta.narrow and meta.narrow[brain.pathIdx or 1] == true
	if narrow then len = len * NARROW_LEN_MUL end

	local wp = brain.path and brain.path[brain.pathIdx]
	local wpDist = math.huge
	if isvector(wp) then
		local d = wp - pos
		d.z = 0
		wpDist = d:Length()
	end

	local centerDanger, centerSoft = 0, false
	local bestAngle, bestScore = 0, math.huge
	local allBlocked = true
	local rightDanger = 1 -- the -32 (right-hand) whisker, for keep-right passing
	-- centre-first: in open ground the centre whisker is clear and the four
	-- side whiskers are never traced (one hull trace per 0.1 s per bot).
	local centerTr = whisker(bot, origin, dirAng:Forward(), len)
	if not centerTr.Hit and not centerTr.StartSolid then
		brain.steerBlockedAt = nil
		brain.steerYawOffset = 0
		brain.steerSpeedMul = (now < (brain.steerSoftUntil or 0)) and 0.8 or 1
		return dirAng, brain.steerSpeedMul
	end
	for i = 1, #WHISKER_ANGLES do
		local a = WHISKER_ANGLES[i]
		local dir = Angle(0, dirAng.y + a, 0):Forward()
		local tr = (a == 0) and centerTr or whisker(bot, origin, dir, len)
		local danger = 0
		local soft = false
		if tr.Hit or tr.StartSolid then
			local hitDist = tr.StartSolid and 0 or tr.Fraction * len
			-- The path turns before this obstacle: not in the way.
			if a == 0 and hitDist >= wpDist - 8 then
				danger = 0
			else
				danger = 1 - math.Clamp(hitDist / len, 0, 1)
				soft = isSoft(tr.Entity)
			end
		end
		if danger < 0.999 then allBlocked = false end
		if a == 0 then centerDanger, centerSoft = danger, soft end
		if a == -32 then rightDanger = danger end
		-- Prefer the clearest whisker; among equals prefer the smallest turn.
		local score = danger * 2 + (math.abs(a) / 64) * 0.5
		if score < bestScore then bestScore, bestAngle = score, a end
	end

	local yawOffset, speedMul = 0, 1
	if centerDanger > 0 then
		if allBlocked then
			-- Boxed in: keep heading, slow down and let the stuck machinery
			-- (sv_traverse fast diagnosis) take over -- it is the right tool.
			yawOffset = 0
			speedMul = HARD_SPEED_MIN
			if not brain.steerBlockedAt then brain.steerBlockedAt = now end
		else
			brain.steerBlockedAt = nil
			-- Blend: the closer the obstacle, the more of the turn we commit to.
			local commit = 0.55 + 0.45 * centerDanger
			yawOffset = bestAngle * commit
			if centerSoft then
				-- A person: shoulder past, do not swerve wide. 2026-09-26: keep
				-- RIGHT whenever the right side is open. The old per-bot side
				-- (EntIndex parity) was relative to each bot's own heading, so
				-- two bots of opposite parity meeting head-on both chose the
				-- same world side and mirrored into each other -- the hallway
				-- dance. A shared rule means both always step apart.
				if rightDanger < 0.9 then
					yawOffset = -24
				elseif bestAngle == 0 then
					yawOffset = 24
				end
				speedMul = SOFT_SPEED_MUL
				brain.steerSoftUntil = now + 0.4
			else
				speedMul = math.max(HARD_SPEED_MIN, 1 - 0.35 * centerDanger)
			end
			stats.steerAvoids = (stats.steerAvoids or 0) + 1
		end
	else
		brain.steerBlockedAt = nil
		-- Keep sliding for a beat after a person was ahead so we don't clip
		-- them the tick after the whisker clears.
		if now < (brain.steerSoftUntil or 0) then speedMul = 0.8 end
	end

	brain.steerYawOffset = yawOffset
	brain.steerSpeedMul = speedMul
	if yawOffset ~= 0 then
		return Angle(0, dirAng.y + yawOffset, 0), speedMul
	end
	return dirAng, speedMul
end
