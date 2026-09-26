-- Cover duel (2026-09-26 owner ask): how a bot fights a HUMAN outside close
-- quarters. It plays like a good aim-trainer target: take a cover spot, hide,
-- pop out (stand up over low cover, or step/lean out beside tall cover),
-- fire a burst or two, duck back, reload in cover, and after two or three
-- peeks move to the next cover with a callout. Readable and fair to the
-- human, never a stand-in-the-open slugfest -- and never a sniper that hides
-- forever either.
--
-- Two behaviours share one per-life state (brain.duel):
--   duel.hold   SURVIVAL band, after survival.preempt (self-treatment in
--               cover still wins): owns the tick while the duel is on and
--               the human is NOT visible -- moving between covers, hiding,
--               reloading. It sits above the MODE band on purpose: a mode's
--               "push to the objective" must not drag a hiding bot out.
--   combat.duel COMBAT band, ahead of combat.engage: the human IS visible.
--               lib.Engage (sv_brain.lua) still does all aiming and fire
--               discipline; this only replaces where the bot stands.
--
-- Close quarters (under CQB_RANGE) is never a duel: the normal Engage
-- strafing/melee/kick code fights it out. Falling back hurt is the
-- SURVIVAL band's break-contact (sv_survival.lua), which this defers to.
--
-- Scope: human targets only. Bot-vs-bot fights belong to the round director
-- (sv_director.lua), which may also opt a bot-vs-bot pair into a duel for
-- a spectator-friendly scene (brain.duelAllowBot).

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}
local D = hg.botdriver
local lib = D.lib
D.duel = D.duel or {}
local duelMod = D.duel

D.DeclareBrainState("duel", { fields = { "duel", "duelAllowBot", "duelCooldownUntil" } })

local cv = ConVarExists("zc_bots_duel") and GetConVar("zc_bots_duel")
	or CreateConVar("zc_bots_duel", "1", FCVAR_ARCHIVE, "Bots fight humans outside close quarters cover-to-cover (peek, burst, duck, relocate)", 0, 1)

local CQB_RANGE = 320           -- closer than this: no duel, Engage's close-range fighting
local MAX_RANGE = 2600
local COVER_RADIUS = 650
local LOST_TIMEOUT = 9          -- human unseen this long: the duel is over (investigate takes it)
local SIDE_PEEK = 56            -- step-out distance beside tall cover
local ARRIVE = 40

D.stats = D.stats or {}
local stats = D.stats

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function isHuman(ent)
	return IsValid(ent) and ent:IsPlayer() and not ent:IsBot()
end

local function eligibleTarget(bot, brain, ent)
	if not IsValid(ent) or not ent:IsPlayer() or not ent:Alive() then return false end
	if D.IsDowned(ent) then return false end -- a downed enemy is finished by Engage
	return isHuman(ent) or brain.duelAllowBot == ent
end

local function gunReady(bot)
	local wep = bot:GetActiveWeapon()
	if not IsValid(wep) or wep.ismelee or not (D.IsGun and D.IsGun(wep)) then
		wep = D.BestGun and D.BestGun(bot)
	end
	if not IsValid(wep) then return nil end
	local prof = D.WeaponProfile and D.WeaponProfile(wep)
	if prof and (prof.role == "launcher" or prof.role == "melee") then return nil end
	return wep
end

local function clipFrac(wep)
	if not IsValid(wep) or not wep.Clip1 then return 1 end
	local clip = wep:Clip1() or 0
	local size = (wep.GetMaxClip1 and wep:GetMaxClip1()) or (wep.Primary and wep.Primary.ClipSize) or math.max(clip, 1)
	if size <= 0 then return 1 end
	return clip / size
end

local function eyeHeightTrace(from, to, bot, target)
	return util.TraceLine({ start = from, endpos = to, filter = { bot, target }, mask = MASK_SHOT }).Hit
end

-- How to peek from a cover spot: "pop" (low cover: hidden crouched, sees
-- over it standing) or "side" (tall cover: step SIDE_PEEK to one side).
local function peekPlan(bot, target, coverPos)
	local eye = target:EyePos()
	if not eyeHeightTrace(coverPos + Vector(0, 0, 64), eye, bot, target) then
		return "pop", nil, 0
	end
	local toTarget = eye - coverPos
	toTarget.z = 0
	if toTarget:LengthSqr() < 1 then return nil end
	toTarget:Normalize()
	local right = Vector(toTarget.y, -toTarget.x, 0)
	local first = math.random() < 0.5 and 1 or -1
	for _, side in ipairs({ first, -first }) do
		local spot = coverPos + right * (side * SIDE_PEEK)
		local clearStep = util.TraceHull({
			start = coverPos + Vector(0, 0, 18), endpos = spot + Vector(0, 0, 18),
			mins = Vector(-14, -14, 0), maxs = Vector(14, 14, 54), filter = bot, mask = MASK_PLAYERSOLID,
		})
		if not clearStep.Hit and not eyeHeightTrace(spot + Vector(0, 0, 64), eye, bot, target) then
			return "side", spot, side
		end
	end
	return nil
end

-- A cover spot for this duel. Relocation asks for one away from the
-- current spot; nothing inside close quarters of the human.
local function chooseCover(bot, brain, target, avoidPos)
	for _ = 1, 3 do
		local pos = lib.FindCover(bot, target, COVER_RADIUS)
		if isvector(pos) and pos:DistToSqr(target:GetPos()) > CQB_RANGE * CQB_RANGE
			and (not avoidPos or pos:DistToSqr(avoidPos) > 150 * 150) then
			local style, peekPos, side = peekPlan(bot, target, pos)
			if style then return pos, style, peekPos, side end
		end
	end
	return nil
end

local function callout(bot, brain, key, voiceKey, chance)
	if math.random() >= (chance or 1) then return end
	if D.squad and D.squad.EmitLine then D.squad.EmitLine(bot, key) end
	if voiceKey and D.radial and D.radial.OnCallout then D.radial.OnCallout(bot, brain, voiceKey, 0.5) end
end

function duelMod.End(brain, cooldown)
	brain.duel = nil
	if cooldown then brain.duelCooldownUntil = CurTime() + cooldown end
end

local function start(bot, brain, target, now)
	local pos, style, peekPos, side = chooseCover(bot, brain, target, nil)
	if not pos then
		brain.duelCooldownUntil = now + 3 -- nowhere to duel from right here; fight normally a bit
		return nil
	end
	local p = brain.personality or {}
	brain.duel = {
		target = target, cover = pos, style = style, peekPos = peekPos, side = side,
		phase = "move", phaseUntil = now + 6, peeks = 0,
		peeksBeforeMove = math.random(2, 3), startedAt = now, seenAt = now,
		aggression = p.aggression or 0.5, patience = p.patience or 1,
	}
	stats.duels = (stats.duels or 0) + 1
	return brain.duel
end

local function relocate(bot, brain, duel, now)
	local pos, style, peekPos, side = chooseCover(bot, brain, duel.target, duel.cover)
	if not pos then
		-- No better spot: stay and keep peeking from here.
		duel.peeks = 0
		duel.phase, duel.phaseUntil = "hide", now + math.Rand(0.6, 1.2)
		return
	end
	duel.cover, duel.style, duel.peekPos, duel.side = pos, style, peekPos, side
	duel.phase, duel.phaseUntil, duel.peeks = "move", now + 6, 0
	duel.peeksBeforeMove = math.random(2, 3)
	callout(bot, brain, "moving", nil, 0.5)
	stats.duelMoves = (stats.duelMoves or 0) + 1
end

-- Engage's own D2 peek cycle would fight this file for the bot's feet.
local function silenceStancePeek(brain, now)
	brain.peekStepUntil, brain.peekHiddenUntil, brain.peekOutUntil = nil, nil, nil
	brain.peekNextHideAt = now + 5
end

local function stripLean(buttons)
	return bit.band(buttons, bit.bnot(bit.bor(IN_ALT1, IN_ALT2)))
end

local function walkTo(bot, brain, pos, speed)
	local flat = pos - bot:GetPos()
	flat.z = 0
	if flat:LengthSqr() < 4 then
		brain.forward, brain.side = 0, 0
		return true
	end
	brain.path = nil
	brain.moveAngles = Angle(0, flat:Angle().y, 0)
	brain.forward, brain.side = speed, 0
	return flat:LengthSqr() <= 12 * 12
end

local function lookToward(bot, brain, duel)
	local target = duel.target
	local pos = isvector(brain.lastSeenPos) and brain.lastSeenPos or (IsValid(target) and target:GetPos())
	if isvector(pos) then lib.LookAt(bot, brain, pos + Vector(0, 0, 56), "duel", false) end
end

----------------------------------------------------------------------
-- duel.hold: human not visible
----------------------------------------------------------------------

D.RegisterBehavior({
	name = "duel.hold",
	band = "SURVIVAL",
	order = 30,
	stateLabel = "duel",
	finalize = false,
	CanRun = function(ctx)
		local brain, now = ctx.brain, ctx.now
		local duel = brain.duel
		if not duel then return false end
		if not cv:GetBool() or ctx.downed or not D.RoundAllowsCombat()
			or not eligibleTarget(ctx.bot, brain, duel.target) or not gunReady(ctx.bot) then
			duelMod.End(brain)
			return false
		end
		if now - duel.seenAt > LOST_TIMEOUT then
			duelMod.End(brain, 4)
			return false
		end
		-- Visible again: combat.duel (COMBAT band) takes the tick.
		if lib.CanSeeTarget(ctx.bot, duel.target) then return false end
		return true
	end,
	Run = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		local duel = brain.duel
		silenceStancePeek(brain, now)
		lookToward(bot, brain, duel)
		brain.buttons = stripLean(brain.buttons or 0)

		if duel.phase == "move" then
			if bot:GetPos():DistToSqr(duel.cover) <= ARRIVE * ARRIVE or now > duel.phaseUntil then
				duel.phase, duel.phaseUntil = "hide", now + math.Rand(0.5, 1.2) * duel.patience
			else
				lib.PathTo(bot, brain, duel.cover, now, 1)
				if not brain.path and brain.pathFailedAt == now then
					duelMod.End(brain, 4) -- cover unreachable after all
					return false
				end
				return true, { path = true }
			end
		end

		if duel.phase == "peek" then
			-- Out of cover, looking for the human who is not in sight: hold
			-- the peek for its full window, then duck back.
			if now < duel.phaseUntil then
				if duel.style == "side" and isvector(duel.peekPos) then
					walkTo(bot, brain, duel.peekPos, 170)
					brain.buttons = bit.bor(brain.buttons, duel.side > 0 and IN_ALT1 or IN_ALT2)
				else
					walkTo(bot, brain, duel.cover, 120)
				end
				return true
			end
			duel.peeks = duel.peeks + 1
			duel.phase, duel.phaseUntil = "hide", now + math.Rand(0.8, 1.6) * duel.patience
		end

		-- hide: in cover. Crouch behind low cover, stand at the edge of tall.
		walkTo(bot, brain, duel.cover, 140)
		if duel.style == "pop" then brain.buttons = bit.bor(brain.buttons, IN_DUCK) end

		local wep = bot:GetActiveWeapon()
		local reloading = IsValid(wep) and ((isnumber(wep.reload) and wep.reload > now)
			or (wep.GetNetVar and (tonumber(wep:GetNetVar("shootgunReload", 0)) or 0) > now))
		if IsValid(wep) and not wep.ismelee and clipFrac(wep) < 0.7 then
			local reserve = D.EffectiveReserve and D.EffectiveReserve(bot, wep) or 0
			if reserve > 0 then
				brain.buttons = bit.bor(brain.buttons, IN_RELOAD)
				if not duel.reloadCalled and clipFrac(wep) < 0.35 then
					duel.reloadCalled = true
					callout(bot, brain, "cover_me", nil, 0.6)
				end
				if D.gunhandling and D.gunhandling.IsShellLoader and D.gunhandling.IsShellLoader(wep) then
					brain.shellGoal = (wep.GetMaxClip1 and wep:GetMaxClip1()) or brain.shellGoal
				end
				reloading = true
			end
		end
		if reloading then
			duel.phaseUntil = math.max(duel.phaseUntil, now + 0.3)
			return true
		end

		if now >= duel.phaseUntil then
			duel.reloadCalled = nil
			if duel.peeks >= duel.peeksBeforeMove then
				relocate(bot, brain, duel, now)
			else
				duel.phase = "peek"
				duel.phaseUntil = now + math.Rand(1.1, 2.3) * (0.8 + duel.aggression * 0.5)
			end
		end
		return true
	end,
})

----------------------------------------------------------------------
-- combat.duel: human visible
----------------------------------------------------------------------

D.RegisterBehavior({
	name = "combat.duel",
	band = "COMBAT",
	order = 12,
	stateLabel = "duel",
	finalize = false,
	CanRun = function(ctx)
		if not cv:GetBool() or not D.RoundAllowsCombat() then return false end
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		local target, dist = ctx:AcquireTarget()
		if not IsValid(target) then return false end
		local duel = brain.duel
		if duel and duel.target ~= target then duelMod.End(brain) duel = nil end
		if not eligibleTarget(bot, brain, target) or not gunReady(bot) then
			if duel then duelMod.End(brain) end
			return false
		end
		if (dist or 0) < CQB_RANGE or (dist or 0) > MAX_RANGE then
			if duel then duelMod.End(brain, 2) end
			return false
		end
		if not duel and now < (brain.duelCooldownUntil or 0) then return false end
		return true
	end,
	Run = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		local target, dist = ctx:AcquireTarget()
		local duel = brain.duel or start(bot, brain, target, now)
		if not duel then return false end
		duel.seenAt = now

		-- Aim, fire discipline, reload triggers, weapon choice: all Engage.
		ctx.behavior.allyOf = ctx:AllyOf()
		local buttons = lib.Engage(bot, brain, now, ctx.skill, target, dist, ctx.behavior, brain.buttons or 0)
		silenceStancePeek(brain, now)
		buttons = stripLean(buttons)

		local wep = bot:GetActiveWeapon()
		local dry = IsValid(wep) and wep.Clip1 and (wep:Clip1() or 0) <= 0

		if duel.phase == "move" then
			if bot:GetPos():DistToSqr(duel.cover) <= ARRIVE * ARRIVE or now > duel.phaseUntil then
				duel.phase, duel.phaseUntil = "hide", now + math.Rand(0.4, 1.0) * duel.patience
			else
				-- Moving between covers under the human's eyes: keep the gun
				-- on them, run the route, no sprint.
				lib.PathTo(bot, brain, duel.cover, now, 1)
				if brain.path then
					brain.buttons = buttons
					return true, { path = true }
				end
				duel.phase = "hide" -- no route there: fight from here
			end
		end

		if duel.phase == "hide" then
			if dry then
				-- Empty and in their sight: stay down behind the cover while
				-- Engage's dry-clip branch reloads (it already added IN_RELOAD).
				walkTo(bot, brain, duel.cover, 140)
				if duel.style == "pop" then buttons = bit.bor(buttons, IN_DUCK) end
				brain.buttons = bit.band(buttons, bit.bnot(IN_ATTACK))
				return true
			end
			-- Spotted while hiding (they moved, or the cover is worse than it
			-- looked): pop out and answer now rather than eat free shots.
			duel.phase = "peek"
			duel.phaseUntil = now + math.Rand(0.9, 1.8)
		end

		-- peek: exposed and shooting.
		if duel.style == "side" and isvector(duel.peekPos) then
			walkTo(bot, brain, duel.peekPos, 170)
			buttons = bit.bor(buttons, duel.side > 0 and IN_ALT1 or IN_ALT2)
		else
			walkTo(bot, brain, duel.cover, 120)
			buttons = bit.band(buttons, bit.bnot(IN_DUCK)) -- stand up over the cover
		end

		local hitThisPeek = now - (brain.damageAt or -math.huge) < 0.4
		if now >= duel.phaseUntil or dry or hitThisPeek then
			duel.peeks = duel.peeks + 1
			duel.phase = "hide"
			duel.phaseUntil = now + math.Rand(0.7, 1.6) * duel.patience * (1.2 - duel.aggression * 0.4)
			if hitThisPeek then duel.phaseUntil = duel.phaseUntil + 0.6 end
			if duel.peeks == 1 and math.random() < 0.25 then callout(bot, brain, "flushed", nil, 0.5) end
			-- Ducking back reads right: stand behind the cover again.
			if duel.style == "side" then walkTo(bot, brain, duel.cover, 170) end
		end

		brain.buttons = buttons
		return true
	end,
})

-- Status for zc_bots_director_debug (sv_director.lua).
function duelMod.Describe(brain)
	local duel = brain and brain.duel
	if not duel then return nil end
	return string.format("%s/%s peeks=%d", duel.phase, duel.style or "?", duel.peeks or 0)
end
