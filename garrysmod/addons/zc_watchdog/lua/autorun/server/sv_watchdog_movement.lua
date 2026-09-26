-- ============================================================
--  Watchdog module: SPEED  (movement / speedhack detection)
-- ------------------------------------------------------------
--  ZCity's max speed is INERTIA-driven and set live every move
--  (mv:SetMaxSpeed(inertia_len); ply:SetMaxSpeed(max(100,inertia_len))),
--  and RunSpeed changes with berserk (->500), noradrenaline (+200*n),
--  class, superfighter. So the ground truth is READ LIVE from the
--  player, never a constant, with generous headroom for inertia
--  overshoot. External forces (knockback, vehicle, teleport, falls)
--  are excused upstream. Only sustained on-ground overspeed scores.
--
--  Note: usercmd-flooding speedhacks also read high here (position
--  advances faster per server tick). The prevention module actually
--  CAPS them; this module is the watch-mode witness.
--  WATCH MODE: dossiers only.
-- ============================================================
if not SERVER then return end
if not WD then include("autorun/server/sv_watchdog_core.lua") end

local MARGIN     = 1.6    -- allowed multiple of live RunSpeed
local FLOOR      = 260    -- never flag below this (walk/inertia noise)
local SUSTAIN    = 8      -- consecutive over-speed ground ticks
local HIT_SCORE  = 40
local THRESHOLD  = 100

local function sample(ply, cmd, t)
	if not t.onground then t.spdRun = 0 return end
	if not t.latStable then return end
	if WD.Excused(ply, "move") then t.spdRun = 0 return end

	local legit = math.max(ply:GetRunSpeed() * MARGIN, ply:GetMaxSpeed() * 1.3, FLOOR)
	if t.speed2d > legit then
		t.spdRun = (t.spdRun or 0) + 1
		if t.spdRun >= SUSTAIN then
			WD.AddSuspicion(ply, "speed", HIT_SCORE, {
				speed = math.Round(t.speed2d),
				allowed = math.Round(legit),
				runspeed = math.Round(ply:GetRunSpeed()),
				maxspeed = math.Round(ply:GetMaxSpeed()),
				ticks = t.spdRun,
			})
			t.spdRun = 0
		end
	else
		t.spdRun = 0
	end
end

WD.RegisterModule("speed", {
	threshold = THRESHOLD,
	decay = 0.5,
	desc = "on-ground overspeed vs live inertia truth",
	Sample = sample,
})
