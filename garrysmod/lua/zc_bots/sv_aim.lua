-- Human aim model (2026-09-21 humanization pass, section A of the brief).
--
-- sv_control.lua's StartCommand hook used to LerpAngle straight at
-- brain.viewAngles every tick. This file replaces that with a two-regime
-- motor model (ballistic saccade / critically-damped pursuit), a perceptual-
-- latency ring so the model chases where the target WAS instead of where it
-- IS, signal-dependent motor noise, and the fire-discipline gate the brief
-- asks to derive from the same model. sv_brain.lua's lib.Engage still decides
-- WHAT to look at (a target position/velocity sample, or a plain viewAngles
-- for path/idle gaze) -- this file decides HOW the view gets there.
--
-- HARD RULE (server is CPU-bound, verified against sv_control.lua's existing
-- per-tick StartCommand hook): aim.Tick runs once per bot per tick and must
-- be pure arithmetic on numbers plus mutation of a handful of Angle/Vector
-- objects allocated exactly once per bot life (in aim.ResetState, called from
-- PlayerSpawn -- never from Tick itself). No table/Vector/Angle construction,
-- no traces, no player loops inside TICK-BEGIN/TICK-END below.
--
-- Verified engine symbols (rule: no invented APIs, grepped against
-- work/main-design-source): math.NormalizeAngle and math.AngleDifference
-- (work/main-design-source/lua/entities/gtav_insurgent.lua:146 and
-- lua/entities/glide_gtav_skylift.lua:218), org.stamina[1]/org.stamina.max
-- (work/main-design-source/lua/homigrad/organism/tier_1/modules/sv_stamina.lua:12),
-- Player:Crouching() (same stamina file, sv_stamina.lua:56). org.pain/org.rarm
-- were already used by sv_gunhandling.lua before this file existed (kept
-- PROVISIONAL there, unchanged here).

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}
hg.botdriver.aim = hg.botdriver.aim or {}
local aim = hg.botdriver.aim

hg.botdriver.DeclareBrainState("aim", { fields = {
	"aimAngle", "aimYawVel", "aimPitchVel", "aimMotorYaw", "aimMotorPitch", "aimConfirmDelay",
	"aimFlickActive", "aimFlickPhase", "aimFlickStartAt", "aimFlickDuration",
	"aimFlickStartYaw", "aimFlickStartPitch", "aimFlickDeltaYaw", "aimFlickDeltaPitch",
	"aimFlickPauseUntil", "aimFlickCorrectionsLeft", "aimFlickLandedAt", "aimFlickBoost",
	"aimRingYaw", "aimRingPitch", "aimRingAt", "aimRingVelYaw", "aimRingVelPitch", "aimRingIdx", "aimRingCount",
	"aimTargetDist", "aimOnTarget", "aimCanFire", "aimPanic",
	-- zc_bots_diagnose snapshot (sv_diagnose.lua): plain string-literal enum
	-- ("flick"/"offtarget"/"confirm"/"ready") plus the two numbers it was
	-- computed from -- assigning an existing literal is a constant-table
	-- reference in Lua, not a runtime allocation, so this stays legal inside
	-- the TICK-BEGIN/TICK-END span below.
	"aimGateCode", "aimErrMagLast", "aimConeLast",
	"aimOcclusionUntil", "aimOcclusionYaw", "aimOcclusionPitch", "aimOcclusionVelYaw", "aimOcclusionVelPitch",
	"aimFlinchAt", "aimFlinchMagYaw", "aimFlinchMagPitch",
	"aimStartleUntil",
	"aimLastTickAt",
},
	-- Re-created by sv_brain.lua's ResetBrain right after it wipes these
	-- fields, so the result no longer depends on PlayerSpawn hook order (see
	-- ResetBrain). aim.ResetState is looked up at call time (defined below).
	reset = function(bot, brain) aim.ResetState(bot, brain) end,
})

----------------------------------------------------------------------
-- Constants (section A). Every duration/overshoot/latency range below is
-- lifted verbatim from the brief; the exact interpolation used inside each
-- range is a BEHAVIOR CHOICE where the brief gave a band, not a formula.
----------------------------------------------------------------------

local SACCADE_DEG = 12          -- A1: error above this triggers a flick, not a pursuit
local FLICK_MIN_DUR, FLICK_MAX_DUR = 0.05, 0.6
local FLICK_SPEED_CAP = 900     -- deg/s peak, trait-scaled (A4)
local PURSUIT_SPEED_CAP_YAW = 260
local PURSUIT_SPEED_CAP_PITCH = 170 -- A4: pitch worse than yaw
local PURSUIT_K_YAW, PURSUIT_K_PITCH = 55, 40   -- spring constant, deg/s^2 per deg of error
local ASSUMED_TARGET_ANGULAR_SIZE = 3 -- deg; BEHAVIOR CHOICE (A1's Fitts term needs a
	-- target angular size and the package has no per-weapon/per-target hitbox
	-- angular-size source verified this session; a human head at typical
	-- engagement range subtends roughly this, used as a flat approximation)
-- No invented API: GMod's math.log is Lua 5.1-shaped (one argument only --
-- the two-argument math.log(x, base) form is Lua 5.2+ and unverified against
-- this engine's Lua build; passing a second argument to a one-arg function
-- would silently be ignored rather than error, producing a natural log where
-- a base-2 log was intended). log2(x) = ln(x) / ln(2) instead.
local LN2 = math.log(2)

local RING_SIZE = 8 -- A2: perceptual-latency ring, numbers only
local MAX_EXTRAPOLATE_AGE = 0.5 -- seconds; caps velocity*age lead in sampleLatent

local DRIFT_FREQ_A, DRIFT_FREQ_B = 0.37, 0.53 -- Hz, incommensurate (A3)
local DRIFT_AMPLITUDE_DEG = 0.35
local NOISE_SPEED_COEFF = 0.006 -- signal-dependent noise: fraction of current angular speed

local FLINCH_DURATION = 0.3
local OCCLUSION_MIN, OCCLUSION_MAX = 0.3, 0.6
local STARTLE_MIN, STARTLE_MAX = 0.12, 0.25
local CONFIRM_MIN, CONFIRM_MAX = 0.04, 0.12
local PANIC_RANGE = 250
-- 2026-09-23: a ballistic saccade (flick + overshoot + corrections) is what a
-- person does when something DEMANDS their eyes -- a hit, a noise, a glimpse.
-- Turning to follow a corridor, sweeping a room or glancing at a flank is a
-- smooth head turn. The old model flicked for ANY error > 12 deg, so every
-- waypoint change snapped the head: "twitchy aim welded to the feet". Only
-- these sources (plus combat) may saccade; everything else pursues.
local SNAP_SOURCES = {
	damage = true, ["sound:damage"] = true, doubletake = true, corpse = true,
	suppression = true, downed = true, sound = true,
}
local TURN_SPEED_CAP_YAW = 320   -- deg/s for a deliberate non-combat head turn
local TURN_K_YAW = 40

----------------------------------------------------------------------
-- Per-life allocation (once, at spawn -- never inside Tick).
----------------------------------------------------------------------

function aim.ResetState(bot, brain)
	brain.aimAngle = Angle(0, 0, 0)
	brain.aimYawVel, brain.aimPitchVel = 0, 0
	brain.aimFlickActive = false
	brain.aimFlickPhase = nil
	brain.aimFlickCorrectionsLeft = 0
	brain.aimFlickLandedAt = 0
	brain.aimRingYaw = { 0, 0, 0, 0, 0, 0, 0, 0 }
	brain.aimRingPitch = { 0, 0, 0, 0, 0, 0, 0, 0 }
	brain.aimRingAt = { -1, -1, -1, -1, -1, -1, -1, -1 }
	brain.aimRingVelYaw = { 0, 0, 0, 0, 0, 0, 0, 0 }
	brain.aimRingVelPitch = { 0, 0, 0, 0, 0, 0, 0, 0 }
	brain.aimRingIdx = 0
	brain.aimRingCount = 0
	brain.aimOcclusionUntil = 0
	brain.aimFlinchAt = -1
	brain.aimStartleUntil = 0
	brain.aimOnTarget = false
	brain.aimCanFire = false
	brain.aimPanic = false
	brain.aimGateCode = "no target"
	brain.aimErrMagLast = 0
	brain.aimConeLast = 0
	brain.aimLastTickAt = CurTime()
	if IsValid(bot) then
		local eye = bot:EyeAngles()
		brain.aimAngle.p, brain.aimAngle.y = eye.p, eye.y
	end
	brain.aimMotorYaw, brain.aimMotorPitch = brain.aimAngle.y, brain.aimAngle.p
	brain.aimConfirmDelay = math.Rand(CONFIRM_MIN, CONFIRM_MAX)
end

-- Lazy allocation for any path that reaches the aim model without a reset
-- this life (a brain created mid-life by GetBrain, a hot reload): never let
-- a missing ring crash a decision again.
function aim.EnsureState(bot, brain)
	if brain.aimAngle and brain.aimRingAt then return end
	aim.ResetState(bot, brain)
end

-- Forget the latency ring's samples (a new target): sampleLatent must never
-- extrapolate another target's old angle forward.
function aim.ClearRing(brain)
	local at = brain.aimRingAt
	if not at then return end
	for i = 1, RING_SIZE do at[i] = -1 end
	brain.aimRingIdx = 0
	brain.aimRingCount = 0
end

hook.Add("PlayerSpawn", "zc_bots_aim_reset", function(ply)
	if not hg.botdriver.Enabled() then return end
	if not ply:IsBot() or not ply.zcBot then return end
	local brain = hg.botdriver.GetBrain(ply)
	aim.ResetState(ply, brain)
end)

----------------------------------------------------------------------
-- Decision-rate input: sv_brain.lua's Engage calls this once per decision
-- (~6Hz) with the raw look angle toward the visible aim point -- NOT
-- per-tick, so the table/number writes here are outside the StartCommand
-- budget. This is "the decision layer records target position+velocity
-- samples" from A2: the ring stores angles (not world positions) because the
-- consumer (Tick) only ever needs an angle to steer toward, and angles avoid
-- a second per-sample vector subtraction.
----------------------------------------------------------------------

function aim.RecordCombatSample(brain, yawDeg, pitchDeg, now, dist)
	if not brain.aimRingAt then aim.ResetState(brain.bot, brain) end
	local idx = (brain.aimRingIdx % RING_SIZE) + 1
	brain.aimRingIdx = idx

	local prevIdx = brain.aimRingCount > 0 and (((idx - 2) % RING_SIZE) + 1) or nil
	local vy, vp = 0, 0
	if prevIdx then
		local prevAt = brain.aimRingAt[prevIdx]
		local dt = prevAt >= 0 and (now - prevAt) or 0
		if dt > 0.01 then
			vy = math.AngleDifference(yawDeg, brain.aimRingYaw[prevIdx]) / dt
			vp = math.AngleDifference(pitchDeg, brain.aimRingPitch[prevIdx]) / dt
		end
	end

	brain.aimRingYaw[idx] = yawDeg
	brain.aimRingPitch[idx] = pitchDeg
	brain.aimRingAt[idx] = now
	brain.aimRingVelYaw[idx] = vy
	brain.aimRingVelPitch[idx] = vp
	brain.aimRingCount = math.min(brain.aimRingCount + 1, RING_SIZE)
	brain.aimTargetDist = dist or brain.aimTargetDist
end

-- A2: sample the ring `latency` seconds behind now, extrapolated by the
-- velocity recorded AT that old sample (so a target that just reversed
-- direction is briefly led the wrong way -- this is the point, not a bug).
-- Pure number scan over a fixed 8-slot ring; no allocation.
local function sampleLatent(brain, now, latency)
	if brain.aimRingCount < 1 then return nil end
	local wantAt = now - latency
	local bestIdx, bestAge
	for i = 1, brain.aimRingCount do
		local at = brain.aimRingAt[i]
		if at >= 0 then
			local age = wantAt - at
			if age >= 0 and (not bestAge or age < bestAge) then
				bestAge = age
				bestIdx = i
			end
		end
	end
	if not bestIdx then
		-- Every sample is younger than the requested latency (target just
		-- appeared): use the oldest one we have, unextrapolated.
		local oldest, oldestAt
		for i = 1, brain.aimRingCount do
			local at = brain.aimRingAt[i]
			if at >= 0 and (not oldestAt or at < oldestAt) then
				oldestAt, oldest = at, i
			end
		end
		bestIdx, bestAge = oldest, 0
	end
	if not bestIdx then return nil end
	-- Never lead a sample further than one decision gap past the latency
	-- window: an older sample is stale history, not a trajectory.
	if bestAge > MAX_EXTRAPOLATE_AGE then bestAge = MAX_EXTRAPOLATE_AGE end
	local yaw = brain.aimRingYaw[bestIdx] + brain.aimRingVelYaw[bestIdx] * bestAge
	local pitch = brain.aimRingPitch[bestIdx] + brain.aimRingVelPitch[bestIdx] * bestAge
	return yaw, pitch, brain.aimRingVelYaw[bestIdx], brain.aimRingVelPitch[bestIdx]
end

----------------------------------------------------------------------
-- Occlusion pre-aim hold (A5 last clause): called from sv_brain.lua's Engage
-- the instant LOS is lost. Freezes an extrapolated pursuit target for
-- 0.3-0.6s instead of letting Tick snap to whatever the next behavior wants
-- looked at.
----------------------------------------------------------------------

function aim.BeginOcclusion(brain, now)
	if (brain.aimRingCount or 0) < 1 then return end
	local latency = (brain.personality and brain.personality.latency) or 0.2
	local yaw, pitch, vy, vp = sampleLatent(brain, now, latency)
	if not yaw then return end
	brain.aimOcclusionUntil = now + math.Rand(OCCLUSION_MIN, OCCLUSION_MAX)
	brain.aimOcclusionYaw = yaw
	brain.aimOcclusionPitch = pitch
	brain.aimOcclusionVelYaw = vy
	brain.aimOcclusionVelPitch = vp
end

----------------------------------------------------------------------
-- Damage reactions: flinch (A3) always; startle (C4) only when the attacker
-- was outside the bot's current field of view. Event-driven (one hook call
-- per hit, not per tick), so the single GetAimVector/vector-subtract here is
-- outside the StartCommand budget.
----------------------------------------------------------------------

local STARTLE_FOV_DOT = math.cos(math.rad(80))

hook.Add("HomigradDamage", "zc_bots_aim_flinch", function(ply, dmg, hitgroup, ent, harm)
	if not IsValid(ply) or not ply:IsPlayer() or not ply:IsBot() or not ply.zcBot then return end
	local brain = hg.botdriver.brains[ply]
	if not brain or not brain.aimAngle then return end
	local now = CurTime()
	local humanize = hg.botdriver.cv_humanize and hg.botdriver.cv_humanize:GetFloat() or 1

	local sign = (math.random(2) == 1) and 1 or -1
	brain.aimFlinchAt = now
	brain.aimFlinchMagYaw = math.Rand(2, 6) * sign * humanize
	brain.aimFlinchMagPitch = math.Rand(1, 3) * ((math.random(2) == 1) and 1 or -1) * humanize

	local attacker = dmg and dmg.GetAttacker and dmg:GetAttacker()
	if IsValid(attacker) and attacker ~= ply and attacker:IsPlayer() then
		local toAttacker = attacker:EyePos() - ply:EyePos()
		if toAttacker:LengthSqr() > 1 then
			toAttacker:Normalize()
			local dot = ply:GetAimVector():Dot(toAttacker)
			if dot < STARTLE_FOV_DOT then
				-- C4: shot from outside the FOV -- freeze, then a larger-overshoot
				-- flick toward the attacker once the freeze ends. The flick itself
				-- is authored by Tick reading aimStartleUntil/aimFlickBoost below.
				brain.aimStartleUntil = now + math.Rand(STARTLE_MIN, STARTLE_MAX) * humanize
				brain.aimFlickBoost = true
				local ang = toAttacker:Angle()
				brain.aimStartleYaw, brain.aimStartlePitch = ang.y, ang.p
			end
		end
	end
end)

----------------------------------------------------------------------
-- Minimum-jerk position/velocity fraction for a bell-shaped saccade (A1).
----------------------------------------------------------------------

local function minJerkPos(t)
	return 10 * t * t * t - 15 * t * t * t * t + 6 * t * t * t * t * t
end

local function minJerkVel(t)
	return 30 * t * t - 60 * t * t * t + 30 * t * t * t * t
end

local function startFlick(brain, now, curYaw, curPitch, targetYaw, targetPitch, skill, boosted, correction)
	local personality = brain.personality
	local flickSpeed = (personality and personality.flickSpeed) or 1
	local errYaw = math.AngleDifference(targetYaw, curYaw)
	local errPitch = math.AngleDifference(targetPitch, curPitch)
	local angleDeg = math.max(math.sqrt(errYaw * errYaw + errPitch * errPitch), 0.01)

	local duration = (0.12 + 0.11 * (math.log(angleDeg / ASSUMED_TARGET_ANGULAR_SIZE + 1) / LN2))
		* flickSpeed * (1.35 - 0.5 * (skill or 0.5))
	duration = math.Clamp(duration, FLICK_MIN_DUR, FLICK_MAX_DUR)

	-- A1: signed 4-12% over/undershoot, smaller with skill; a startle-driven
	-- flick (C4) overshoots harder, matching a genuine flinch-flick.
	local overshootFrac = math.Rand(0.04, 0.12) * (1.4 - 0.6 * (skill or 0.5))
	if boosted then overshootFrac = overshootFrac * 1.8 end
	if math.random(2) == 1 then overshootFrac = -overshootFrac end

	brain.aimFlickActive = true
	brain.aimFlickPhase = "flick"
	brain.aimFlickStartAt = now
	brain.aimFlickDuration = duration
	brain.aimConfirmDelay = math.Rand(CONFIRM_MIN, CONFIRM_MAX)
	brain.aimFlickStartYaw = curYaw
	brain.aimFlickStartPitch = curPitch
	brain.aimFlickDeltaYaw = errYaw * (1 + overshootFrac)
	brain.aimFlickDeltaPitch = errPitch * (1 + overshootFrac * 0.6)
	if not correction then
		brain.aimFlickCorrectionsLeft = math.random(1, 2)
	end
	-- Minimum-jerk peak derivative is 1.875. Bound the actual rotation,
	-- not just a velocity diagnostic after an already-too-fast turn.
	local travel = math.sqrt(brain.aimFlickDeltaYaw ^ 2 + brain.aimFlickDeltaPitch ^ 2)
	brain.aimFlickDuration = math.max(duration, 1.875 * travel / (FLICK_SPEED_CAP / flickSpeed))
	brain.aimFlickBoost = false
end

----------------------------------------------------------------------
-- Per-tick core (A). Marked with TICK-BEGIN/TICK-END for the static check in
-- tests/test_port_clean.py -- this body must never allocate a table, Vector
-- or Angle, trace, or loop players.
----------------------------------------------------------------------

local cv_aimerr = ConVarExists("zc_bots_aim_error") and GetConVar("zc_bots_aim_error") or nil -- declared by sv_brain.lua

function aim.Tick(bot, brain, now)
	-- TICK-BEGIN
	if not brain.aimAngle then return end
	local dt = math.Clamp(now - (brain.aimLastTickAt or now), 0, 0.1)
	brain.aimLastTickAt = now

	local personality = brain.personality
	local skill = brain.aimSkill or 0.5
	local steadiness = (personality and personality.steadiness) or 0.6
	local latency = (personality and personality.latency) or 0.2
	local humanize = hg.botdriver.cv_humanize and hg.botdriver.cv_humanize:GetFloat() or 1
	-- A4: ONE source of aim error -- the global zc_bots_aim_error convar times
	-- sv_gunhandling.lua's contextual widening (burst/pain/range), both folded
	-- into this model's cone width and saccade threshold instead of the old
	-- per-decision tremor sv_brain.lua's Engage used to add on top.
	local aimErrMult = ((cv_aimerr and (cv_aimerr:GetFloat() / 5)) or 1) * (brain.aimGunErrMult or 1)

	-- Noise is an output perturbation, never the next motor-state input.
	local curYaw = brain.aimMotorYaw or brain.aimAngle.y
	local curPitch = brain.aimMotorPitch or brain.aimAngle.p
	local startled = now < (brain.aimStartleUntil or 0)

	if startled then
		-- C4: startle freeze -- inputs frozen, view held, no motion this tick.
		brain.aimOnTarget, brain.aimCanFire, brain.aimPanic = false, false, false
		brain.aimGateCode = "startled"
		bot:SetEyeAngles(brain.aimAngle)
	else
		if brain.aimFlickBoost and brain.aimStartleYaw then
			startFlick(brain, now, curYaw, curPitch, brain.aimStartleYaw, brain.aimStartlePitch, skill, true)
			brain.aimStartleYaw = nil
		end

		-- Resolve the desired target angle this tick, cheapest branch first.
		-- (Sample velocity is baked into targetYaw/targetPitch by sampleLatent's
		-- extrapolation and by the occlusion carry-forward below, so it is not
		-- needed again once the target angle itself is known.)
		local targetYaw, targetPitch
		local dist = brain.aimTargetDist or 800
		local panicking = false

		if now < (brain.aimOcclusionUntil or 0) then
			targetYaw = brain.aimOcclusionYaw + (brain.aimOcclusionVelYaw or 0) * dt
			targetPitch = brain.aimOcclusionPitch + (brain.aimOcclusionVelPitch or 0) * dt
			brain.aimOcclusionYaw, brain.aimOcclusionPitch = targetYaw, targetPitch
		elseif brain.lookSource == "combat" and brain.aimRingCount > 0 then
			targetYaw, targetPitch = sampleLatent(brain, now, latency)
			panicking = dist < PANIC_RANGE
		elseif brain.viewAngles then
			targetYaw, targetPitch = brain.viewAngles.y, brain.viewAngles.p
		else
			targetYaw, targetPitch = curYaw, curPitch
		end
		brain.aimPanic = panicking

		local errYaw = math.AngleDifference(targetYaw, curYaw)
		local errPitch = math.AngleDifference(targetPitch, curPitch)
		local errMag = math.sqrt(errYaw * errYaw + errPitch * errPitch)

	-- Regime selection + motion (A1).
	if brain.aimFlickActive then
		if brain.aimFlickPhase == "flick" then
			local frac = math.Clamp((now - brain.aimFlickStartAt) / brain.aimFlickDuration, 0, 1)
			local pos = minJerkPos(frac)
			curYaw = math.NormalizeAngle(brain.aimFlickStartYaw + brain.aimFlickDeltaYaw * pos)
			curPitch = math.NormalizeAngle(brain.aimFlickStartPitch + brain.aimFlickDeltaPitch * pos)
			local velScale = minJerkVel(frac) / math.max(brain.aimFlickDuration, 0.001)
			brain.aimYawVel = brain.aimFlickDeltaYaw * velScale
			brain.aimPitchVel = brain.aimFlickDeltaPitch * velScale
			local speed = math.sqrt(brain.aimYawVel ^ 2 + brain.aimPitchVel ^ 2)
			local cap = FLICK_SPEED_CAP * ((personality and personality.flickSpeed) and (1 / personality.flickSpeed) or 1)
			if speed > cap then
				local scale = cap / speed
				brain.aimYawVel = brain.aimYawVel * scale
				brain.aimPitchVel = brain.aimPitchVel * scale
			end
			if frac >= 1 then
				brain.aimFlickPhase = "pause"
				brain.aimFlickPauseUntil = now + math.Rand(0.06, 0.14)
				brain.aimFlickLandedAt = nil
			end
		elseif brain.aimFlickPhase == "pause" then
			brain.aimYawVel, brain.aimPitchVel = 0, 0
			if now >= brain.aimFlickPauseUntil then
				if errMag > 1.5 and brain.aimFlickCorrectionsLeft > 0 then
					brain.aimFlickCorrectionsLeft = brain.aimFlickCorrectionsLeft - 1
					startFlick(brain, now, curYaw, curPitch, targetYaw, targetPitch, skill, false, true)
				else
					brain.aimFlickActive = false
					brain.aimFlickPhase = nil
					brain.aimFlickLandedAt = now
				end
			end
		end
	elseif errMag > SACCADE_DEG * math.Clamp(aimErrMult, 0.4, 2)
		and (brain.lookSource == "combat" or SNAP_SOURCES[brain.lookSource] == true) then
		startFlick(brain, now, curYaw, curPitch, targetYaw, targetPitch, skill, false)
	else
		-- A1: smooth pursuit -- critically damped spring, gain < 1 (lags a
		-- moving target, catches up when it stops), pitch weaker than yaw.
		-- Non-combat turns (path/scan/travel) use the deliberate head-turn
		-- constants: a little slower spring, a higher speed cap, no overshoot.
		local combatLook = brain.lookSource == "combat"
		local kYaw, kPitch = PURSUIT_K_YAW, PURSUIT_K_PITCH
		local capYaw = PURSUIT_SPEED_CAP_YAW
		if not combatLook then
			kYaw = TURN_K_YAW
			capYaw = TURN_SPEED_CAP_YAW
		end
		local cYaw, cPitch = 2 * math.sqrt(kYaw), 2 * math.sqrt(kPitch)
		local gain = combatLook and 0.85 or 1 -- < 1: deliberate lag behind a moving target

		local accelYaw = kYaw * errYaw * gain - cYaw * brain.aimYawVel
		local accelPitch = kPitch * errPitch * gain - cPitch * brain.aimPitchVel
		brain.aimYawVel = brain.aimYawVel + accelYaw * dt
		brain.aimPitchVel = brain.aimPitchVel + accelPitch * dt
		brain.aimYawVel = math.Clamp(brain.aimYawVel, -capYaw, capYaw)
		brain.aimPitchVel = math.Clamp(brain.aimPitchVel, -PURSUIT_SPEED_CAP_PITCH, PURSUIT_SPEED_CAP_PITCH)
		curYaw = math.NormalizeAngle(curYaw + brain.aimYawVel * dt)
		curPitch = math.NormalizeAngle(curPitch + brain.aimPitchVel * dt)
	end

	-- Motor noise (A3): signal-dependent tremor + slow incommensurate drift.
	-- Rises with pain/low stamina/recent damage/sustained fire/post-flick;
	-- falls when crouched/still/ADS. Additive to the OUTPUT only -- it never
	-- feeds back into aimYawVel/aimPitchVel, so it cannot accumulate.
	local org = bot.organism
	local pain = math.Clamp((org and tonumber(org.pain) or 0) / 100, 0, 1)
	local staminaFrac = (org and org.stamina and org.stamina[1] and org.stamina.max)
		and math.Clamp(org.stamina[1] / org.stamina.max, 0, 1) or 1
	local recentDamage = (now - (brain.aimFlinchAt or -math.huge)) < 1.5
	local sustainedFire = now < (brain.fireUntil or 0)
	local postFlick = (now - (brain.aimFlickLandedAt or -math.huge)) < 0.25
	local settled = bot:Crouching() or (math.abs(brain.actualForward or 0) < 1 and math.abs(brain.actualSide or 0) < 1)
	local ads = bit.band(brain.buttons or 0, IN_ATTACK2) ~= 0

	local riseTerm = 1 + 1.2 * pain + 0.8 * (1 - staminaFrac) + (recentDamage and 0.6 or 0)
		+ (sustainedFire and 0.4 or 0) + (postFlick and 0.5 or 0)
	local fallTerm = (settled and 0.5 or 1) * (ads and 0.5 or 1)
	local noiseScale = (1 - steadiness) * riseTerm * fallTerm * humanize

	local speed = math.sqrt(brain.aimYawVel ^ 2 + brain.aimPitchVel ^ 2)
	local signalYaw = NOISE_SPEED_COEFF * speed * noiseScale * math.sin(now * 17 + ((personality and personality.noisePhaseA) or 0))
	local phaseA = (personality and personality.noisePhaseA) or 0
	local phaseB = (personality and personality.noisePhaseB) or 0
	local drift = DRIFT_AMPLITUDE_DEG * noiseScale
		* (math.sin(now * (2 * math.pi) * DRIFT_FREQ_A + phaseA) + math.sin(now * (2 * math.pi) * DRIFT_FREQ_B + phaseB)) * 0.5

	local flinchDecay = math.max(0, 1 - (now - (brain.aimFlinchAt or -math.huge)) / FLINCH_DURATION)
	local flinchYaw = (brain.aimFlinchMagYaw or 0) * flinchDecay
	local flinchPitch = (brain.aimFlinchMagPitch or 0) * flinchDecay

	local outYaw = math.NormalizeAngle(curYaw + signalYaw + drift + flinchYaw)
	local outPitch = math.Clamp(curPitch + signalYaw * 1.3 + drift * 1.3 + flinchPitch, -89, 89)

	brain.aimMotorYaw, brain.aimMotorPitch = curYaw, curPitch
	brain.aimAngle.p, brain.aimAngle.y, brain.aimAngle.r = outPitch, outYaw, 0

	-- A5: fire discipline gate. Acceptance cone widens at close range/panic
	-- (spray) and tightens with range; first shot after a flick waits for
	-- landing + a short confirmation unless panicking.
	local coneBase = 6 - 4 * skill -- degrees, 2..6
	local cone
	if panicking then
		cone = 14
	else
		cone = coneBase * math.Clamp(1 - (dist - PANIC_RANGE) / 3000 * 0.5, 0.4, 1)
	end
	cone = cone * math.Clamp(aimErrMult, 0.4, 2.5)

	local outputYawError = math.AngleDifference(targetYaw, outYaw)
	local outputPitchError = math.AngleDifference(targetPitch, outPitch)
	errMag = math.sqrt(outputYawError ^ 2 + outputPitchError ^ 2)
	local onTarget = errMag <= cone
	local confirmed = panicking or not brain.aimFlickLandedAt
		or (now - brain.aimFlickLandedAt) >= (brain.aimConfirmDelay or CONFIRM_MAX)
	brain.aimOnTarget = onTarget
	brain.aimCanFire = onTarget and confirmed and not brain.aimFlickActive
	brain.aimErrMagLast = errMag
	brain.aimConeLast = cone
	-- zc_bots_diagnose gate-code: plain literal assignment (see field
	-- declaration comment above for why this is allocation-free), checked in
	-- the same priority aimCanFire itself uses.
	if brain.aimFlickActive then
		brain.aimGateCode = "flick"
	elseif not onTarget then
		brain.aimGateCode = "offtarget"
	elseif not confirmed then
		brain.aimGateCode = "confirm"
	else
		brain.aimGateCode = "ready"
	end

		bot:SetEyeAngles(brain.aimAngle)
	end
	-- TICK-END
end
