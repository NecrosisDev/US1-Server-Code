-- Cover finding: navmesh-area scan for a spot that breaks line of sight to a
-- given threat entity. Extracted from sv_melee.lua's local hiddenSpot() (same
-- 10-trace cap; callers keep their own re-run cadence) so sv_gunhandling.lua
-- (reload) and sv_survival.lua (self-treat / break-contact) can share it
-- instead of duplicating the scan.

hg = hg or {}
hg.botdriver = hg.botdriver or {}
hg.botdriver.lib = hg.botdriver.lib or {}
local lib = hg.botdriver.lib

hg.botdriver.DeclareBrainState("combat_step", { fields = {
	"combatStepAt", "combatStepPos", "combatStepWant", "combatStepResult",
} })

-- Validate local combat footwork at decision rate. Nav travel has its own
-- traversal owner; these probes protect direct strafes and backsteps only.
function lib.SafeCombatMove(bot, brain, now)
	if brain.path or not bot:IsOnGround() then return end
	local forward, side = brain.forward or 0, brain.side or 0
	if math.abs(forward) + math.abs(side) < 1 then return end
	local frame = brain.moveAngles or Angle(0, bot:EyeAngles().y, 0)
	local want = frame:Forward() * forward + frame:Right() * side
	want.z = 0
	local pos = bot:GetPos()
	local cached = brain.combatStepWant
	if now < (brain.combatStepAt or 0) and cached and cached:DistToSqr(want) < 1
		and brain.combatStepPos:DistToSqr(pos) < 16 * 16 then
		brain.forward, brain.side = brain.combatStepResult[1], brain.combatStepResult[2]
		return
	end
	local function clear(f, s)
		local delta = frame:Forward() * f + frame:Right() * s
		delta.z = 0
		if delta:LengthSqr() < 1 then return false end
		local dest = pos + delta:GetNormalized() * math.Clamp(delta:Length() * 0.25, 40, 90)
		local wall = util.TraceHull({ start = pos + Vector(0, 0, 18), endpos = dest + Vector(0, 0, 18),
			mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 54), filter = bot, mask = MASK_PLAYERSOLID })
		if wall.Hit or wall.StartSolid then return false end
		local floor = util.TraceHull({ start = dest + Vector(0, 0, 18), endpos = dest - Vector(0, 0, 36),
			mins = Vector(-12, -12, 0), maxs = Vector(12, 12, 2), filter = bot, mask = MASK_PLAYERSOLID })
		return floor.Hit and not floor.StartSolid and floor.HitNormal.z >= 0.7
	end
	local f, s = forward, side
	if not clear(f, s) then
		-- Slide along the safe component of a diagonal. Never turn an unsafe
		-- retreat into an unsolicited charge toward the threat.
		if side ~= 0 and forward ~= 0 and clear(0, side) then f = 0
		elseif side ~= 0 and forward ~= 0 and clear(forward, 0) then s = 0
		else f, s = 0, 0 end
	end
	brain.combatStepAt, brain.combatStepPos = now + 0.15, pos
	brain.combatStepWant, brain.combatStepResult = want, { f, s }
	brain.forward, brain.side = f, s
end

-- Nearby firing positions with low cover and a clear standing firing line.
-- Six candidates, at most three traces each; caller throttles scans.
function lib.FindCombatPosition(bot, threat, preferred)
	if not IsValid(bot) or not IsValid(threat) then return nil end
	local pos, eye = bot:GetPos(), threat:EyePos()
	local filter = { bot, threat }
	local here = util.TraceLine({start = eye, endpos = pos + Vector(0, 0, 24), filter = filter, mask = MASK_SHOT})
	if here.Hit then return nil end -- already using low cover; keep the angle
	local areas = navmesh.Find(pos, 500, 72, 72) or {}
	local n = #areas
	if n == 0 then return nil end
	local best, bestScore
	local offset = math.random(n) - 1
	for i = 0, math.min(n, 6) - 1 do
		local area = areas[(offset + math.floor(i * n / math.min(n, 6))) % n + 1]
		local spot = area:GetCenter()
		local travel = spot:Distance(pos)
		local range = spot:Distance(threat:GetPos())
		if travel > 64 and range > math.min(160, preferred * 0.4) and range < preferred * 1.6 then
			local low = util.TraceLine({start = eye, endpos = spot + Vector(0, 0, 24), filter = filter, mask = MASK_SHOT})
			if low.Hit then
				local sight = util.TraceLine({start = spot + Vector(0, 0, 64), endpos = eye, filter = filter, mask = MASK_SHOT})
				local room = util.TraceHull({start = spot + Vector(0, 0, 2), endpos = spot + Vector(0, 0, 2),
					mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 70), filter = bot, mask = MASK_PLAYERSOLID})
				if not sight.Hit and not room.Hit and not room.StartSolid then
					local score = travel + math.abs(range - preferred) * 0.35
					if not bestScore or score < bestScore then best, bestScore = spot, score end
				end
			end
		end
	end
	return best
end

-- A spot near `bot` that `threatEnt` cannot see, preferring ones that also
-- close the distance to it. Budgeted: at most 10 traces per call. Callers are
-- responsible for their own cadence (do not call this every decision).
function lib.FindCover(bot, threatEnt, radius, purpose)
	if not IsValid(bot) or not IsValid(threatEnt) then return nil end
	local areas = navmesh.Find(bot:GetPos(), radius or 700, 120, 120)
	if not areas then return nil end
	local eye = threatEnt:EyePos()
	local tpos = threatEnt:GetPos()
	local myDist = bot:GetPos():DistToSqr(tpos)
	local best, bestScore
	local traces = 0
	-- Random start + fixed stride: spread over the candidates, never the same area twice.
	local n = #areas
	if n == 0 then return nil end
	local offset, stride = math.random(n) - 1, math.max(1, math.floor(n / 10))
	for i = 0, n - 1, stride do
		if traces >= 10 then break end
		local area = areas[(offset + i) % n + 1]
		local center = area:GetCenter()
		traces = traces + 1
		local tr = util.TraceLine({
			start = eye,
			endpos = center + Vector(0, 0, 40),
			filter = { bot, threatEnt },
			mask = MASK_SHOT,
		})
		if tr.Hit and (purpose ~= "retreat" or center:DistToSqr(tpos) >= myDist * 0.8) then
			local score = center:DistToSqr(bot:GetPos())
			if purpose ~= "retreat" and center:DistToSqr(tpos) < myDist then score = score * 0.4 end
			if not bestScore or score < bestScore then best, bestScore = center, score end
		end
	end
	return best
end

-- 2026-09-26: cover hysteresis. FindCover samples ~10 random nav areas per
-- call and every caller re-runs it on a 1.5 s cadence, so each call could
-- return a DIFFERENT "best" spot -- a bot running for cover turned around
-- every 1.5 s to run for another one. KeepCover holds the spot it already
-- chose while that spot still hides it from the same threat and is still
-- within reach; only then is a fresh spot searched for. `slot` separates
-- independent uses (reload / break-contact / self-treat) on one brain.
hg.botdriver.DeclareBrainState("cover_hold", { fields = { "coverHeld" } })

function lib.KeepCover(bot, brain, slot, threatEnt, radius, purpose)
	radius = radius or 700
	local held = brain.coverHeld and brain.coverHeld[slot]
	if held and IsValid(threatEnt) and held.threat == threatEnt and isvector(held.pos) then
		local hidden = util.TraceLine({
			start = threatEnt:EyePos(),
			endpos = held.pos + Vector(0, 0, 40),
			filter = { bot, threatEnt },
			mask = MASK_SHOT,
		}).Hit
		if hidden and bot:GetPos():DistToSqr(held.pos) <= (radius * 1.4) ^ 2 then
			return held.pos
		end
	end
	local pos = lib.FindCover(bot, threatEnt, radius, purpose)
	brain.coverHeld = brain.coverHeld or {}
	brain.coverHeld[slot] = pos and { pos = pos, threat = threatEnt } or nil
	return pos
end

-- Item 4 (2026-09-22, weapon-appropriate positioning): the inverse of
-- FindCover -- a spot near `bot` with a CLEAR line of sight to `threatEnt`,
-- preferring greater distance from the threat without crossing past it, so
-- a sniper retreats instead of walking a long way toward the enemy. Same scan shape
-- and 10-trace budget as FindCover; callers own their own cadence.
function lib.FindSightline(bot, threatEnt, radius)
	if not IsValid(bot) or not IsValid(threatEnt) then return nil end
	local areas = navmesh.Find(bot:GetPos(), radius or 1500, 120, 120)
	if not areas then return nil end
	local eye = threatEnt:EyePos()
	local best, bestDistSqr
	local currentRange = bot:GetPos():Distance(threatEnt:GetPos())
	local traces = 0
	local n = #areas
	if n == 0 then return nil end
	local offset, stride = math.random(n) - 1, math.max(1, math.floor(n / 10))
	for i = 0, n - 1, stride do
		if traces >= 10 then break end
		local area = areas[(offset + i) % n + 1]
		local center = area:GetCenter()
		traces = traces + 1
		local tr = util.TraceLine({
			start = eye,
			endpos = center + Vector(0, 0, 40),
			filter = { bot, threatEnt },
			mask = MASK_SHOT,
		})
		if not tr.Hit and (center - threatEnt:GetPos()):Dot(bot:GetPos() - threatEnt:GetPos()) > 0 then
			-- A long walk sideways (or toward the enemy) is not a retreat.
			local distSqr = center:DistToSqr(threatEnt:GetPos())
			if distSqr <= (currentRange + 96) ^ 2 then distSqr = 0 end
			if distSqr > 0 and (not bestDistSqr or distSqr > bestDistSqr) then best, bestDistSqr = center, distSqr end
		end
	end
	return best
end
