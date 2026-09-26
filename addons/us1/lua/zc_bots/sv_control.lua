-- Bot control: applies the brain's intent through StartCommand each tick.
-- Ported from Trauma's sv_control.lua; the muzzle-steer measurement and
-- finish-downed pulse machinery are cut (rule 1 -- finishing/execution is not
-- part of this Phase 1 slice; Engage never targets a downed enemy specially).
--
-- 2026-09-21 humanization pass (section A/D): the old plain LerpAngle toward
-- brain.viewAngles is replaced by sv_aim.lua's two-regime motor model
-- (aim.Tick), and forward/side are quantised to a discrete WASD-style
-- {-mag,0,+mag} signal with a key-switch dwell before a direction reversal
-- (section D) instead of the smoothed analog value the old code Lerp'd every
-- tick -- GMod's own player movement code already supplies the physical
-- acceleration curve a digital key input would produce; lerping the
-- forward/side values on top of that was the tell.
--
-- Both additions are pure per-tick arithmetic on brain-cached numbers --
-- aim.Tick owns the one persistent Angle object (brain.aimAngle, allocated
-- once per life in sv_aim.lua's PlayerSpawn hook), and the quantiser below
-- only ever reads/writes plain numbers on the brain.

hg.botdriver.DeclareBrainState("control_quantize", { fields = {
	"qForwardSign", "qForwardAt", "qForwardDwell", "qSideSign", "qSideAt", "qSideDwell", "jumpStartedAt",
	"cmdLOSTarget", "cmdLOSNextCheck", "cmdLOSLastVisible",
	"lagHitchAt", "lagHitchUntil",
} })

local KEY_SWITCH_MIN, KEY_SWITCH_MAX = 0.08, 0.16
local AXIS_DEADZONE = 5

-- D: never reverse a movement axis (full forward<->back or left<->right)
-- faster than a human key-switch; releasing to/from neutral is not gated
-- (letting go of a key is not itself a "switch"). Pure number compare/writes.
local function quantizeAxis(brain, signField, atField, dwellField, sign, now)
	local prevSign = brain[signField] or 0
	if sign ~= prevSign then
		local reversal = sign ~= 0 and prevSign ~= 0
		local dwellOk = not reversal or (now - (brain[atField] or 0)) >= (brain[dwellField] or KEY_SWITCH_MIN)
		if dwellOk then
			brain[signField] = sign
			brain[atField] = now
			brain[dwellField] = math.Rand(KEY_SWITCH_MIN, KEY_SWITCH_MAX)
		end
	end
	return brain[signField] or 0
end

hook.Add("StartCommand", "zc_bots_control", function(ply, cmd)
	if not hg.botdriver.Enabled() then return end
	if not ply:IsBot() or not ply.zcBot then return end
	if not ply:Alive() then return end

	local brain = hg.botdriver.brains and hg.botdriver.brains[ply]
	if not brain then return end

	local now = CurTime()

	-- At most once per life (a brain that reached StartCommand without aim
	-- state): allocate it rather than running the whole life on the plain
	-- look-at fallback below, which also left aimCanFire unset.
	local aimMod = hg.botdriver.aim
	if aimMod and aimMod.EnsureState and not brain.aimAngle then aimMod.EnsureState(ply, brain) end

	-- TICK-BEGIN
	if hg.botdriver.aim and brain.aimAngle then
		hg.botdriver.aim.Tick(ply, brain, now)
	else
		-- Fallback (aim state not yet allocated this life, e.g. mid-autorefresh
		-- before the next PlayerSpawn): behave like a plain look-at so a bot is
		-- never left staring at a stale angle.
		local cur = ply:EyeAngles()
		local want = brain.viewAngles or cur
		local fraction = math.Clamp(10 * FrameTime(), 0, 1)
		local newAng = LerpAngle(fraction, cur, want)
		newAng.r = 0
		ply:SetEyeAngles(newAng)
	end
	if brain.aimAngle then
		cmd:SetViewAngles(brain.aimAngle)
	else
		cmd:SetViewAngles(ply:EyeAngles())
	end
	-- TICK-END

	local eyeYaw = brain.aimAngle and brain.aimAngle.y or ply:EyeAngles().y

	-- E: humans load in and orient before their first input -- hold movement
	-- (but not the aim model above, so the bot still looks around) until the
	-- per-life spawn delay elapses.
	local spawnHeld = now < (brain.spawnHoldUntil or 0)

	-- F3 laggy archetype (sv_personality.lua): every hitchInterval seconds the
	-- inputs freeze for hitchLength, then resume -- the engine's own
	-- acceleration produces the rubber-band catch-up. Inputs only: hitboxes,
	-- position and damage are untouched, so the bot is never harder to hit.
	local personality = brain.personality
	if personality and personality.hitchInterval then
		if now >= (brain.lagHitchAt or 0) then
			brain.lagHitchAt = now + personality.hitchInterval * math.Rand(0.7, 1.3)
			brain.lagHitchUntil = now + personality.hitchLength
		end
		if now < (brain.lagHitchUntil or 0) then spawnHeld = true end
	end

	local rawForward = spawnHeld and 0 or (brain.forward or 0)
	local rawSide = spawnHeld and 0 or (brain.side or 0)

	if brain.actionPolicy and brain.actionPolicy.lockMove then
		rawForward, rawSide = 0, 0
	end

	local moveAng = brain.moveAngles
	if moveAng and (rawForward ~= 0 or rawSide ~= 0) then
		local worldMove = moveAng:Forward() * rawForward + moveAng:Right() * rawSide
		local viewMove = Angle(0, eyeYaw, 0)
		rawForward = worldMove:Dot(viewMove:Forward())
		rawSide = worldMove:Dot(viewMove:Right())
	end

	local suppressed, moveCap = false, nil
	if hg.botdriver.MovementSuppression then
		suppressed, moveCap = hg.botdriver.MovementSuppression(ply)
	end
	if suppressed then
		if (moveCap or 0) <= 0 then
			rawForward, rawSide = 0, 0
		else
			rawForward = math.Clamp(rawForward, -moveCap, moveCap)
			rawSide = math.Clamp(rawSide, -moveCap, moveCap)
		end
	end

	-- D: quantise to a discrete WASD-style signal -- sign gated by the
	-- key-switch dwell on a reversal, magnitude passed straight through (the
	-- decision layer already authors distinct walk/jog/sprint magnitudes).
	local signForward = rawForward > AXIS_DEADZONE and 1 or (rawForward < -AXIS_DEADZONE and -1 or 0)
	local signSide = rawSide > AXIS_DEADZONE and 1 or (rawSide < -AXIS_DEADZONE and -1 or 0)
	local qForward = quantizeAxis(brain, "qForwardSign", "qForwardAt", "qForwardDwell", signForward, now)
	local qSide = quantizeAxis(brain, "qSideSign", "qSideAt", "qSideDwell", signSide, now)
	brain.actualForward = qForward * math.abs(rawForward)
	brain.actualSide = qSide * math.abs(rawSide)

	local buttons = brain.buttons or 0

	-- A5: the per-tick aim model is the final authority on whether the
	-- crosshair is settled enough to fire (acceptance cone + post-flick
	-- confirmation); false only once sv_aim.lua has actually evaluated a tick.
	-- Ranged gunfire only: bandaging, fist raising, melee swings and gun bashes
	-- are IN_ATTACK too and must never wait on a settled crosshair.
	if brain.aimCanFire == false and CurTime() < (brain.fireGatedUntil or 0) then
		buttons = bit.band(buttons, bit.bnot(IN_ATTACK))
	end

	-- Command-rate LOS gate: strip fire if the target broke line of sight
	-- since the last (~6Hz) decision. Only combat aim sets aimLocked +
	-- lookSource "combat".
	if brain.aimLocked and brain.lookSource == "combat" then
		local lib = hg.botdriver.lib
		local visible
		if brain.cmdLOSTarget == brain.target and now < (brain.cmdLOSNextCheck or 0) then
			visible = brain.cmdLOSLastVisible
		else
			visible = lib and lib.CanSeeTarget and IsValid(brain.target) and lib.CanSeeTarget(ply, brain.target) or false
			brain.cmdLOSTarget = brain.target
			brain.cmdLOSLastVisible = visible
			brain.cmdLOSNextCheck = now + 0.06
		end
		if not visible then
			buttons = bit.band(buttons, bit.bnot(IN_ATTACK))
			brain.target = nil
			brain.aimLocked = nil
			brain.fireUntil = 0
		end
	end

	local roundAllowsCombat = hg.botdriver.RoundAllowsCombat == nil or hg.botdriver.RoundAllowsCombat()

	if brain.sprint and rawForward > 0 and not suppressed then
		buttons = bit.bor(buttons, IN_FORWARD)
	end
	local finalButtons = bit.bor(cmd:GetButtons(), buttons)

	if suppressed then
		finalButtons = bit.band(finalButtons, bit.bnot(IN_JUMP))
	end

	if bit.band(finalButtons, IN_JUMP) ~= 0 and ply:IsOnGround() then
		brain.jumpStartedAt = now
	end
	if brain.jumpStartedAt then
		if not ply:IsOnGround() and now - brain.jumpStartedAt > 0.08 then
			finalButtons = bit.bor(finalButtons, IN_DUCK)
		end
		if ply:IsOnGround() and now - brain.jumpStartedAt > 0.25 then
			brain.jumpStartedAt = nil
		end
	end

	if not roundAllowsCombat then
		finalButtons = bit.band(finalButtons, bit.bnot(bit.bor(IN_ATTACK, IN_ATTACK2)))
	end

	-- Rule 3, enforced again at command rate: IN_SPEED/IN_USE never ride
	-- along with IN_ATTACK, and IN_WALK never rides with IN_RELOAD or
	-- IN_SPEED (sv_movement.lua authors IN_WALK for the slow-walk gait since
	-- 2026-09-23; IN_SPEED+IN_WALK is the ragdoll-grab chord on this fork).
	if bit.band(finalButtons, IN_ATTACK) ~= 0 then
		local strip = now < (brain.bashUntil or 0) and IN_SPEED or bit.bor(IN_SPEED, IN_USE)
		finalButtons = bit.band(finalButtons, bit.bnot(strip))
	end
	if bit.band(finalButtons, IN_WALK) ~= 0 and bit.band(finalButtons, bit.bor(IN_RELOAD, IN_SPEED)) ~= 0 then
		finalButtons = bit.band(finalButtons, bit.bnot(IN_WALK))
	end

	cmd:SetButtons(finalButtons)
	cmd:SetForwardMove(brain.actualForward)
	cmd:SetSideMove(brain.actualSide)
end)
