-- ============================================================
--  Watchdog module: PINGKICK  (sustained high-ping kicker)
-- ------------------------------------------------------------
--  Removes players whose ping stays disruptively high, so gunfights
--  aren't wrecked by their rubberbanding. This is the ONE module that
--  ENFORCES (kicks) by default - a connection-quality tool, not a cheat
--  flag, and independent of the cheat watch-mode.
--
--  Guardrails so legit players aren't kicked for a blip / a server hitch:
--   * only above pingThreshold (350ms) sustained pingSustain (20s)
--   * hysteresis: only counts as "recovered" once ping drops under
--     pingClear (300ms), so jitter right at the line resolves toward keeping
--   * sampled every 2s; tolerates a single momentary dip
--   * SERVER-HEALTH GATE: if a big share of players are over at once, that's
--     the SERVER lagging (Ping() inflates for everyone on a hitch), not them -
--     the whole kicker pauses so a ragdoll-storm can't mass-kick innocents
--   * pingGrace (45s) after joining; staff exempt; timing-out skipped
--   * chat warning at pingWarnAt (15s) before the kick at 20s
--   * pingKickEnforce=false => DRY RUN (logs who WOULD be kicked, no kick)
--   * respects the panel's module on/off toggle (emergency kill-switch)
-- ============================================================
if not SERVER then return end
if not WD then include("autorun/server/sv_watchdog_core.lua") end

local C = WD.Config
if C.pingKick        == nil then C.pingKick        = true end   -- module on
if C.pingKickEnforce == nil then C.pingKickEnforce = true end   -- true = actually kick
if C.pingThreshold   == nil then C.pingThreshold   = 350  end   -- ms: "over"
if C.pingClear       == nil then C.pingClear       = 300  end   -- ms: below this = "recovered" (hysteresis)
if C.pingSustain     == nil then C.pingSustain     = 20   end   -- s over before kick
if C.pingWarnAt      == nil then C.pingWarnAt      = 15   end   -- s over before the chat warning
if C.pingGrace       == nil then C.pingGrace       = 45   end   -- s after join before measuring
if C.pingServerGuard == nil then C.pingServerGuard = true end   -- pause when the server itself is lagging

local SAMPLE = 2   -- timer interval (s)
local state = {}   -- sid -> { joined, over (consecutive over-cycles), under, warned }

-- Is the whole server lagging right now? If a large share of players are all
-- over the threshold at once, that's server-side latency inflating everyone's
-- Ping(), not a per-player problem - don't kick anyone this cycle.
local function serverLagging(plys)
	if not C.pingServerGuard then return false end
	local total, over = 0, 0
	for _, p in ipairs(plys) do
		if IsValid(p) and not p:IsBot() then
			total = total + 1
			if p:Ping() > C.pingThreshold then over = over + 1 end
		end
	end
	return total >= 4 and (over / total) >= 0.4
end

local function act(ply, ping, dur)
	if C.pingKickEnforce then
		WD.Notify(string.format("high-ping kick: %s (%dms for %ds)", ply:Nick(), ping, dur))
		if C.logConsole then print(string.format("[Watchdog] ping kick: %s (%s) %dms/%ds", ply:Nick(), ply:SteamID(), ping, dur)) end
		ply:Kick(string.format("High ping (%dms) for over %ds - rejoin when your connection improves.", ping, C.pingSustain))
	else
		WD.Notify(string.format("[dry-run] WOULD ping-kick: %s (%dms for %ds)", ply:Nick(), ping, dur))
		if C.logConsole then print(string.format("[Watchdog] ping DRY-RUN: %s %dms/%ds (not kicked)", ply:Nick(), ping, dur)) end
	end
end

local function tick(ply, now)
	if not IsValid(ply) or ply:IsBot() then return end
	local sid = ply:SteamID()
	local s = state[sid]
	if not s then s = { joined = now } state[sid] = s end

	local function reset() s.over = 0 s.under = 0 s.warned = false end

	if now - s.joined < C.pingGrace then return reset() end   -- join grace
	if WD.IsExempt(ply) then return reset() end               -- staff
	if ply:IsTimingOut() then return reset() end              -- disconnecting anyway

	local ping = ply:Ping()

	-- Count CONSECUTIVE over-cycles (not wall-clock), so a paused server-lag
	-- cycle simply doesn't increment - no inflated duration after a hitch.
	if ping > C.pingThreshold then
		s.under = 0
		s.over = (s.over or 0) + 1
	elseif ping < C.pingClear then
		s.under = (s.under or 0) + 1
		if s.under >= 2 then return reset() end   -- recovered (2 straight samples under clear)
		return                                    -- one dip: hold the count
	else
		s.under = 0                               -- hysteresis band [clear, threshold]
		if not s.over or s.over == 0 then return end
		s.over = s.over + 1                        -- still elevated: keep counting
	end

	local secs = s.over * SAMPLE
	if not s.warned and secs >= C.pingWarnAt then
		s.warned = true
		ply:ChatPrint(string.format("[Server] Your ping (%dms) is very high - please fix your connection or you'll be removed shortly.", ping))
	end
	if secs >= C.pingSustain then
		act(ply, ping, secs)
		reset()
	end
end

timer.Create("WD_PingKick", 2, 0, function()
	if not C.enabled or not C.pingKick or not WD.ModuleEnabled("pingkick") then return end
	local plys = player.GetAll()
	if serverLagging(plys) then return end   -- server-wide lag: don't kick anyone
	local now = CurTime()
	for _, ply in ipairs(plys) do tick(ply, now) end
end)

hook.Add("PlayerDisconnected", "WD_PingKick_Clean", function(ply)
	if IsValid(ply) then state[ply:SteamID()] = nil end
end)

WD.RegisterModule("pingkick", {
	threshold = 100, decay = 0,
	desc = "ENFORCES: kicks sustained high ping (350ms/20s)",
})

print("[Watchdog] ping kicker loaded - " .. (C.pingKickEnforce and "ENFORCING" or "DRY-RUN") ..
	" | " .. C.pingThreshold .. "ms / " .. C.pingSustain .. "s")
