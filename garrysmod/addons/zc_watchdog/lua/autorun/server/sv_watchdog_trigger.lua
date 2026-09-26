-- ============================================================
--  Watchdog module: TRIGGER  (triggerbot)
-- ------------------------------------------------------------
--  A triggerbot fires the instant the crosshair sweeps onto an
--  enemy - and then STAYS locked, because it fired *because* it was
--  on target. Signature: the rising edge of IN_ATTACK lands the exact
--  tick the (moving) view first sits on an enemy, AND the very next
--  tick the crosshair is still on that same enemy. A human flick or a
--  spray-transfer sweeps THROUGH the target instead of locking.
--  The player-loop runs only on an attack rising edge, so it's cheap.
--  Ranged weapons only. WATCH MODE: dossiers only.
-- ============================================================
if not SERVER then return end
if not WD then include("autorun/server/sv_watchdog_core.lua") end

local ONTARGET   = 0.9989   -- ~2.7 deg lock onto an enemy
local SWEEP_MIN  = 8        -- view must be moving at least this (deg/tick): crosshair swept on
local NEAR       = 150
local FAR        = 4000
local HIT_SCORE  = 24       -- ~4-5 confirmed zero-reaction locks => dossier
local THRESHOLD  = 100

-- exclude melee / utility so held-attack actions don't qualify
local NOT_RANGED = { "hands", "knife", "bat", "hammer", "fist", "melee", "bandage",
                     "medkit", "syringe", "tool", "physgun", "camera", "arrest" }
local function isRanged(ply)
	local w = ply:GetActiveWeapon()
	if not IsValid(w) then return false end
	local c = w:GetClass()
	for _, p in ipairs(NOT_RANGED) do
		if string.find(c, p, 1, true) then return false end
	end
	return true
end

local function onEnemyPrecise(ply, dir, eye)
	for _, other in player.Iterator() do
		if other ~= ply and IsValid(other) and other:Alive() and other:Team() ~= TEAM_SPECTATOR then
			local to = other:WorldSpaceCenter() - eye
			local dist = to:Length()
			if dist > NEAR and dist < FAR then
				to:Normalize()
				if dir:Dot(to) > ONTARGET then return other, math.Round(dist) end
			end
		end
	end
	return nil
end

local function sample(ply, cmd, t)
	local attackNow = bit.band(t.buttons, IN_ATTACK) ~= 0

	-- confirm a candidate raised last tick: is the crosshair STILL locked on it?
	local pend = t.trigPend
	t.trigPend = nil
	if pend and attackNow and IsValid(pend) and pend:Alive() then
		local eye = ply:EyePos()
		local to = pend:WorldSpaceCenter() - eye
		to:Normalize()
		if t.ang:Forward():Dot(to) > ONTARGET then
			WD.AddSuspicion(ply, "trigger", HIT_SCORE, {
				target = pend:Nick(),
				sweep = math.Round(t.jump, 1),
				weapon = IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass() or "?",
			})
		end
	end

	local was = t.trigWas
	t.trigWas = attackNow
	if not attackNow or was then return end     -- only the rising edge of fire
	if not t.latStable then return end
	if WD.Excused(ply, "view") then return end
	if t.jump < SWEEP_MIN then return end        -- stationary pre-aim click = legit
	if not isRanged(ply) then return end

	local eye = ply:EyePos()
	local tgt = onEnemyPrecise(ply, t.ang:Forward(), eye)
	if not tgt then return end
	-- ...and the crosshair was NOT on that enemy the tick before (swept on, not tracked)
	local toPrev = tgt:WorldSpaceCenter() - eye
	toPrev:Normalize()
	if t.prev:Forward():Dot(toPrev) > ONTARGET then return end

	t.trigPend = tgt   -- confirm the lock next tick
end

WD.RegisterModule("trigger", {
	threshold = THRESHOLD,
	decay = 0.4,
	desc = "triggerbot: zero-reaction lock on target",
	Sample = sample,
})
