-- ============================================================
--  Watchdog: PREVENTION  (silent, low-risk - neutralize, not punish)
-- ------------------------------------------------------------
--  These do not accuse anyone; they make the cheat not work.
--
--  1) SPEED CAP (anti usercmd-flooding speedhack)
--     Token bucket in real time (SMAC pattern). A speedhack sends
--     more move-commands than wall-clock allows; when the bucket is
--     empty we ClearMovement() on the extra commands - they produce
--     no locomotion, so no speed is gained. Commands are NOT dropped
--     (no desync). A 2s bucket + no-count on forced/choke commands
--     means legit play never empties it.
--
--  2) NOCLIP DENY (additive to ZCity's own Hook.PlayerNoClip)
--     Denies the noclip command to non-admins and LOGS the attempt.
--     Safe because it only ever returns false (never grants), and it
--     stacks with the gamemode's existing guard.
--     A watch-only detector notes a non-admin sitting in MOVETYPE_NOCLIP
--     while NONE of homigrad's legit noclip states apply (otrub /
--     fake-ragdoll / vehicle). Homigrad noclips KO'd bodies on purpose
--     (sv_tier_0), so we NEVER force a movetype change unless the
--     admin explicitly enables revertNoclip (default off).
-- ============================================================
if not SERVER then return end
if not WD then include("autorun/server/sv_watchdog_core.lua") end

-- prevention config (set if absent; tune with wd_config)
local C = WD.Config
if C.capSpeed     == nil then C.capSpeed     = true  end
if C.denyNoclip   == nil then C.denyNoclip   = true  end
if C.revertNoclip == nil then C.revertNoclip = false end  -- risky: leave OFF until proven
if C.noclipTicks  == nil then C.noclipTicks  = 10    end  -- consecutive bad-noclip ticks before a dossier

-- ---------------- 1) SPEED CAP (token bucket) ----------------
local bucket = {}   -- sid -> tokens
local lastRT = {}   -- sid -> last SysTime we refilled
local capHit = {}   -- sid -> consecutive capped commands (for logging)

hook.Add("StartCommand", "WD_Prevent_SpeedCap", function(ply, cmd)
	if not C.enabled or not C.capSpeed then return end
	if not IsValid(ply) or not ply:Alive() then return end
	if cmd:IsForced() then return end          -- engine backup command under choke
	if ply:InVehicle() then return end         -- vehicle physics, not player locomotion
	if WD.IsExempt(ply) then return end        -- never cap elevated roles

	local sid = ply:SteamID()
	local rate = 1 / engine.TickInterval()     -- commands per second the server expects
	local cap  = rate * 3                       -- 3 second buffer (lag-recovery headroom)
	local now  = SysTime()
	local prev = lastRT[sid]
	local tok  = bucket[sid]

	-- a client recovering from a stall drains buffered commands in a burst;
	-- refill the bucket and skip the cap while/just after it's timing out.
	if ply:IsTimingOut() then
		bucket[sid] = cap
		lastRT[sid] = now
		capHit[sid] = 0
		return
	end

	if not prev or not tok then
		bucket[sid] = cap
		lastRT[sid] = now
		return
	end

	tok = math.min(cap, tok + (now - prev) * rate)  -- refill by REAL elapsed time
	lastRT[sid] = now

	if tok >= 1 then
		bucket[sid] = tok - 1
		if capHit[sid] and capHit[sid] > 0 then capHit[sid] = 0 end
	else
		-- flooding: this command has no real-time budget. Neutralize its movement.
		bucket[sid] = 0
		cmd:ClearMovement()
		capHit[sid] = (capHit[sid] or 0) + 1
		-- log a witness dossier if it's sustained and latency is stable (not just a lag burst)
		if capHit[sid] == math.floor(rate) and WD.LatencyStable(ply) then
			WD.AddSuspicion(ply, "speedcap", 100, {
				note = "usercmd flooding capped",
				cappedCommands = capHit[sid],
			})
		end
	end
end)

WD.RegisterModule("speedcap", {
	threshold = 100, decay = 0,
	desc = "PREVENT: caps usercmd-flooding speedhacks",
})

-- ---------------- 2) NOCLIP DENY + watch ----------------
local function noclipAuthorized(ply)
	-- admins, plus any elevated role Watchdog is told to ignore. We only ever
	-- ADD a denial; ZCity's own Hook.PlayerNoClip still governs everyone else.
	return ply:IsAdmin() or WD.IsExempt(ply)
end

-- additive deny (stacks with ZCity's Hook.PlayerNoClip). Only ever denies.
local ncNotify = {}   -- sid -> next time we may chat-ping about this player (anti-spam)
hook.Add("PlayerNoClip", "WD_Prevent_NoClip", function(ply, want)
	if not C.enabled or not C.denyNoclip then return end
	if want and not noclipAuthorized(ply) then
		local sid = ply:SteamID()
		local now = CurTime()
		if not ncNotify[sid] or ncNotify[sid] < now then
			ncNotify[sid] = now + 15   -- one notice per 15s per player (bind-spam guard)
			WD.Notify("blocked noclip: " .. ply:Nick())
			if C.logConsole then print("[Watchdog] blocked noclip attempt: " .. ply:Nick() .. " (" .. sid .. ")") end
		end
		return false
	end
end)

-- watch-only: a non-admin stuck in MOVETYPE_NOCLIP with no legit reason
local function noclipSample(ply, cmd, t)
	if noclipAuthorized(ply) then t.ncRun = 0 return end
	if ply:GetMoveType() ~= MOVETYPE_NOCLIP then t.ncRun = 0 return end
	-- homigrad legit noclip states:
	local o = ply.organism
	if (o and o.otrub) or IsValid(ply.FakeRagdoll) or ply:InVehicle() then t.ncRun = 0 return end

	t.ncRun = (t.ncRun or 0) + 1
	if t.ncRun == C.noclipTicks then
		WD.AddSuspicion(ply, "noclip", 100, { note = "unauthorized MOVETYPE_NOCLIP", ticks = t.ncRun })
		if C.revertNoclip then
			ply:SetMoveType(MOVETYPE_WALK)   -- opt-in only; can strand if a legit state was missed
		end
	end
end

WD.RegisterModule("noclip", {
	threshold = 100, decay = 0,
	desc = "PREVENT/WATCH: unauthorized noclip",
	Sample = noclipSample,
})

-- bucket cleanup
hook.Add("PlayerDisconnected", "WD_Prevent_Cleanup", function(ply)
	if not IsValid(ply) then return end
	local sid = ply:SteamID()
	bucket[sid] = nil lastRT[sid] = nil capHit[sid] = nil
end)

print("[Watchdog] prevention loaded (speedcap/noclip)")
