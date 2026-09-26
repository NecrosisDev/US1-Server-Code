-- ============================================================
--  Watchdog module: SPIN  (spinbot + impossible-angle / anti-aim)
-- ------------------------------------------------------------
--  Two signatures off the shared per-tick view data:
--   * SPIN: |yaw rate| stays high for many CONSECUTIVE ticks and
--     never settles (a legit flick settles within 1-3 ticks).
--   * FAKE ANGLES: pitch beyond the ~89 deg look limit, or non-zero
--     roll while upright (Source never networks roll from a standing
--     player; homigrad's rolled views come from fake/KO states, which
--     the excuse system removes upstream).
--  Angle-sanity is absolute (choke can't inflate it) so it does not
--  need the latency gate; the spin run does.
--  WATCH MODE: dossiers only.
-- ============================================================
if not SERVER then return end
if not WD then include("autorun/server/sv_watchdog_core.lua") end

local SPIN_YAW    = 22     -- deg/tick sustained (~1100 deg/s at tick 50)
local SETTLE      = 6      -- deg/tick that counts as "settled", resets the run
local RUN_NEEDED  = 12     -- consecutive spin ticks before it scores
local SPIN_SCORE  = 55

local PITCH_MAX   = 89.7   -- cannot look past vertical
local ROLL_MAX    = 25     -- upright players network ~0 roll
local ANGLE_SCORE = 34     -- impossible-angle sample

local THRESHOLD   = 100

local function sample(ply, cmd, t)
	local ex = WD.Excused(ply, "view")

	-- ---- fake-angle sanity (absolute, choke-proof) ----
	if not ex then
		local a = t.ang
		if math.abs(a.p) > PITCH_MAX then
			WD.AddSuspicion(ply, "spin", ANGLE_SCORE, { type = "pitch", pitch = math.Round(a.p, 1) })
		end
		if math.abs(a.r) > ROLL_MAX then
			WD.AddSuspicion(ply, "spin", ANGLE_SCORE, { type = "roll", roll = math.Round(a.r, 1) })
		end
	end

	-- ---- spinbot (needs stable latency + no excuse) ----
	if ex or not t.latStable then
		t.spinRun = 0
		return
	end
	local yr = math.abs(t.dYaw)
	if yr > SPIN_YAW then
		t.spinRun = (t.spinRun or 0) + 1
		if t.spinRun >= RUN_NEEDED then
			WD.AddSuspicion(ply, "spin", SPIN_SCORE, {
				type = "spin",
				yawRate = math.Round(yr, 1),
				ticks = t.spinRun,
			})
			t.spinRun = 0
		end
	elseif yr < SETTLE then
		t.spinRun = 0
	end
end

WD.RegisterModule("spin", {
	threshold = THRESHOLD,
	decay = 0.6,
	desc = "spinbot + impossible angles",
	Sample = sample,
})
