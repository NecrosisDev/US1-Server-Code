-- ============================================================
--  ZC PERF v1.7 - hook + timer + net profiler with auto-capture
-- ------------------------------------------------------------
--  Answers "where do the frame's milliseconds go" with real data:
--   * frame time from Think-to-Think deltas: avg, buckets, worst,
--     effective tickrate over the window
--   * per-named-hook cost across the hot events (ULib-priority-safe
--     wrapping, fully reversible)
--   * v1.1 TIMER COST: timer.Create/timer.Simple callbacks are
--     wrapped too - closes the blind spot that hid ZCity's
--     timer-driven work (send_info_org, WoundsSend, dmgstack, every
--     addon's think timer). Dynamic names are normalised
--     ("send_info_org1234" -> "send_info_org#") so they group.
--   * v1.1 NET COST: net.Start + every sender wrapped - per-message
--     count, payload bytes, recipients and TOTAL WIRE BYTES. This is
--     what convicts (or clears) snapshot/netvar flooding.
--   * spike log: frames over zc_perf_spike ms record their top hooks
--   * v1.6 WORST-FRAMES LOG - see below
--   * entity census at report time
--
--  v1.6 WHY THIS VERSION EXISTS. The v1.1-1.5 spike log was a
--  RECENCY ring: it kept the LAST 8 frames over the threshold. On a
--  60s window with 100+ long frames, the single WORST frame had
--  almost always been overwritten by the time the report was
--  written. Swept across 13 light captures on 8/27 this cost us
--  attribution on 5 of the 13 worst frames - INCLUDING the biggest
--  freeze ever recorded on the server (832.3ms, 27-player
--  juggernaut on riverside_snow), which we simply cannot explain.
--  So v1.6 keeps a SECOND ring sorted by SIZE (zc_perf_worst, default
--  8) that a frame can only fall out of by being beaten. The recency
--  ring stays - it shows what a bad patch looked like moment to
--  moment - but the worst ring is the one that answers "what was
--  that huge freeze". Every entry now also carries:
--    * seconds into the window (do the monsters cluster? -> round start)
--    * round state at that instant (PRE / LIVE / ENDING) and mode -
--      a freeze during a state change IS the round transition
--    * alive-player count
--    * ATTRIBUTED LUA vs FRAME MS as a percentage, with an explicit
--      "ENGINE-SIDE" tag under 10% - which separates "we know what
--      this was" from "no Lua ran, this was the engine or the host"
--      without any further guesswork
--  Also fixed in v1.6: the auto-capture header no longer hardcodes
--  "tick sagged below N" - it prints the trigger that actually fired
--  (tick average vs long-frame count), which had been misreporting
--  every spike-triggered capture.
--  Measured-vs-unmeasured split: while the server is BELOW its
--  tickrate there is no idle sleep, so unmeasured time = engine
--  (snapshot packing, physics, network send).
--
--  v1.1 AUTO-CAPTURE (per Joey - "only happens on certain maps"):
--  an always-on featherweight watcher (one Think, no wrapping)
--  tracks effective tick. If it stays under zc_perf_auto_tick for
--  zc_perf_auto_sustain seconds it ARMS ITSELF, records for
--  zc_perf_auto_time, then disarms, prints the report and SAVES it
--  to data/zc_perf/<map>-<timestamp>.txt. Unattended capture on the
--  maps that actually misbehave.
--
--  USAGE (admin or server console):
--    zc_perf 1          arm manually (fresh window)
--    zc_perf_report     print + save the report
--    zc_perf_reset      zero the window, stay armed
--    zc_perf 0          disarm - originals restored, zero overhead
--    zc_perf_auto 1     enable the auto-capture watcher (default on)
--    zc_perf_reports    list saved report files
--    zc_perf_worst 8    how many worst frames to keep attributed (v1.6)
--    zc_perf_auto_grace 30       no auto-capture for 30s after a map
--                                load - a map change is a guaranteed
--                                sag and was burning a capture on
--                                EVERY map change (v1.7)
--    zc_perf_auto_minplayers 2   no auto-capture below 2 players - two
--                                of the 13 captures on 8/27 fired at
--                                ZERO players (v1.7)
--  Serverside only = hotloadable.
-- ============================================================
if not SERVER then return end

ZCPERF = ZCPERF or {}

-- v1.7: when this map came up. Set at file load (autorun runs during map
-- load, so this is the load itself) and refreshed at InitPostEntity, which
-- is the honest "map is now up" moment - the heavy part (clients
-- reconnecting, spawning, first round) all happens AFTER it. A hotload
-- also resets this, which is correct: don't capture the hotload either.
ZCPERF.mapAt = SysTime()
hook.Add("InitPostEntity", "zc_perf_maptime", function()
	ZCPERF.mapAt = SysTime()
end)

local cv_on      = CreateConVar("zc_perf", "0", 0, "Arm the profiler (0 = restore originals, zero overhead)", 0, 1)
local cv_spike   = CreateConVar("zc_perf_spike", "25", 0, "Frame ms threshold for the spike log", 5, 200)
-- v1.6: the worst-frames ring. A frame only leaves this list by being
-- beaten, so the biggest freeze of the window is ALWAYS attributed.
local cv_worst   = CreateConVar("zc_perf_worst", "8", FCVAR_ARCHIVE, "How many worst frames to keep attributed (0 = worst-frame log off)", 0, 20)
local cv_auto    = CreateConVar("zc_perf_auto", "1", FCVAR_ARCHIVE, "Auto-arm and save a report when the tickrate sags", 0, 1)
local cv_autotick = CreateConVar("zc_perf_auto_tick", "45", FCVAR_ARCHIVE, "Effective tick below this counts as sagging", 5, 200)
-- v1.3: average tick alone MISSES hitching - a round can sit at 50.1
-- effective tick while a fifth of its frames blow past 25ms (measured
-- live on hmcd). So a second trigger counts long frames per second.
local cv_autospikes = CreateConVar("zc_perf_auto_spikes", "10", FCVAR_ARCHIVE, "Frames over zc_perf_spike ms within one second that also count as sagging (0 = tick-average trigger only)", 0, 200)
local cv_autosus = CreateConVar("zc_perf_auto_sustain", "5", FCVAR_ARCHIVE, "Seconds of sag before auto-capture starts", 1, 120)
local cv_autotime = CreateConVar("zc_perf_auto_time", "60", FCVAR_ARCHIVE, "Seconds to record once auto-capture fires", 10, 600)
local cv_autocd  = CreateConVar("zc_perf_auto_cd", "600", FCVAR_ARCHIVE, "Cooldown between auto-captures (seconds)", 0, 3600)
-- v1.7 JUNK-CAPTURE FILTERS. A map change is a guaranteed sag - the map
-- loads, entities spawn, every client reconnects and downloads - and the
-- watcher was reading that as "the server is struggling" and burning a
-- capture on it EVERY SINGLE MAP CHANGE. Worse, by the time the 5-second
-- sustain elapses and the 60s window records, the load is over, so the
-- report is 60 seconds of a nearly EMPTY server: two of the 13 captures
-- on 8/27 fired at ZERO players and told us nothing.
--   * grace: no auto-capture for N seconds after the map comes up
--   * minplayers: no auto-capture below N connected players at all -
--     nobody is affected by lag on an empty server, and it also covers
--     the tail of a map change while players are still reconnecting.
--     Kept LOW (2) on purpose: the 2-3 player captures are what produced
--     the Think/zb-think round-transition finding, so this must not
--     become a "only capture busy servers" filter.
-- Neither applies to MANUAL arming (zc_perf 1) - that always works.
local cv_autograce = CreateConVar("zc_perf_auto_grace", "30", FCVAR_ARCHIVE, "Seconds after a map load before auto-capture may arm", 0, 600)
local cv_autominply = CreateConVar("zc_perf_auto_minplayers", "2", FCVAR_ARCHIVE, "Minimum connected players for auto-capture to arm", 0, 128)
local cv_save    = CreateConVar("zc_perf_save", "1", FCVAR_ARCHIVE, "Save reports to data/zc_perf/", 0, 1)
-- v1.5 LIGHT MODE (default ON). The per-usercmd events (SetupMove /
-- StartCommand / PlayerTick / Move / FinishMove) fire ~1,550 times a
-- SECOND at 30 players, and util.TraceLine ~1,400/s. Wrapping those
-- adds two clock reads to every one of them - that is the profiler's
-- own weight, and it inflates the very frame times it is reporting.
-- Their cost is already well established (~4ms/frame, stable across
-- six captures), so light mode stops re-measuring the known and keeps
-- the instruments that are still answering questions: Think/Tick/
-- EntityTakeDamage hooks, timers, net, GC, churn, frame buckets.
local cv_light   = CreateConVar("zc_perf_light", "1", FCVAR_ARCHIVE, "Low-impact capture: skip wrapping per-usercmd hooks and traces (0 = full detail, heavier)", 0, 1)

util.AddNetworkString("ZCPERF_Alert")
util.AddNetworkString("ZCPERF_Hello")

-- Clients running our client file announce themselves; anyone else
-- gets the no-client-file fallback below. This makes the upgrade
-- automatic: ZCity notifications before the restart, proper
-- Watchdog-style toasts after it, never both.
net.Receive("ZCPERF_Hello", function(_, ply)
	if IsValid(ply) then ply.zc_perfUI = true end
end)

-- ---- staff alerts (Watchdog-style bottom-right toast + sound + chat) ----
-- 1 = auto-armed, 2 = manual arm, 3 = stopped, 4 = report saved
local ALERT_COL = Color(255, 190, 70)

local function alertStaff(kind, text)
	print("[zc_perf] " .. text)
	local toastTo = {}
	for _, p in ipairs(player.GetAll()) do
		if IsValid(p) and (p:IsAdmin() or p:IsSuperAdmin()) then
			if p.zc_perfUI then
				toastTo[#toastTo + 1] = p -- client file draws toast + chat itself
			else
				-- FALLBACK (no client file yet): ZCity's own notification
				-- system, server-side only. CAVEAT found in sv_notification
				-- .lua:46 - the gamemode DROPS a Notify while the player is
				-- dead or unconscious, and that is exactly when staff tend
				-- to be spectating - so the chat line below is the belt that
				-- guarantees the alert always lands.
				pcall(function()
					p:Notify("[PERF] " .. text, 0, "zc_perf_alert" .. kind, 0, nil, ALERT_COL)
				end)
				p:PrintMessage(HUD_PRINTTALK, "[zc_perf] " .. text)
			end
		end
	end
	if #toastTo > 0 then
		net.Start("ZCPERF_Alert")
		net.WriteUInt(kind, 3)
		net.WriteString(text)
		net.Send(toastTo)
	end
end

local SysTime = SysTime
local EVENTS_FULL  = { "Think", "Tick", "SetupMove", "Move", "FinishMove", "StartCommand", "PlayerTick", "EntityTakeDamage", "Player Think" }
local EVENTS_LIGHT = { "Think", "Tick", "EntityTakeDamage" }
local EVENTS = EVENTS_FULL -- swapped per-arm below
local BUCKETS = { 10, 15, 20, 25, 33, 50 } -- ms upper bounds; overflow bucket after
local SAVEDIR = "zc_perf"

-- ---- shared stat accounting ----
local function statRow(key)
	local st = ZCPERF.stats[key]
	if not st then
		st = { calls = 0, total = 0, kb = 0 }
		ZCPERF.stats[key] = st
	end
	return st
end

local gcCount = collectgarbage
local function record(key, dt, kb)
	local st = statRow(key)
	st.calls = st.calls + 1
	st.total = st.total + dt
	-- kb < 0: a collection ran inside the call, the sample says nothing about what it allocated
	if kb and kb > 0 then st.kb = st.kb + kb end
	local fr = ZCPERF.frame
	fr[key] = (fr[key] or 0) + dt
end

-- ---- hook wrapping ----
local function makeWrap(key, fn)
	statRow(key)
	return function(...)
		local k0, t0 = gcCount("count"), SysTime()
		local a, b, c, d = fn(...)
		record(key, SysTime() - t0, gcCount("count") - k0)
		return a, b, c, d
	end
end

local function wantEvent(ev)
	for _, e in ipairs(EVENTS) do
		if e == ev then return true end
	end
	return false
end

local function collectHooks()
	local out = {}
	local ulibT = hook.GetULibTable and hook.GetULibTable()
	if istable(ulibT) then
		for event, prios in pairs(ulibT) do
			if wantEvent(event) and istable(prios) then
				for prio, hooks in pairs(prios) do
					if istable(hooks) then
						for name, data in pairs(hooks) do
							local fn = istable(data) and data.fn or data
							if isstring(name) and isfunction(fn) and not string.find(name, "^zc_perf") then
								out[#out + 1] = { event = event, name = name, fn = fn, prio = prio }
							end
						end
					end
				end
			end
		end
	else
		local all = hook.GetTable()
		for _, event in ipairs(EVENTS) do
			local t = all[event]
			if istable(t) then
				for name, fn in pairs(t) do
					if isstring(name) and isfunction(fn) and not string.find(name, "^zc_perf") then
						out[#out + 1] = { event = event, name = name, fn = fn }
					end
				end
			end
		end
	end
	return out
end

local function readd(event, name, fn, prio)
	if prio ~= nil then
		hook.Add(event, name, fn, prio) -- ULib 4-arg keeps the priority
	else
		hook.Add(event, name, fn)
	end
end

-- ---- v1.1 TIMER instrumentation ----
-- Only timers CREATED while armed can be wrapped (there is no way to
-- read back an existing timer's callback). That still catches every
-- on-demand timer - which is exactly where ZCity's per-event work
-- lives (send_info_org, WoundsSend, Blood_burst, dmgstack...).
-- Timers created at file load are only captured if the profiler was
-- already armed then (auto-capture on a fresh map start sees them).
local function normTimerName(name)
	name = tostring(name)
	name = string.gsub(name, "%d+", "#")       -- entindex/id suffixes group together
	if #name > 60 then name = string.sub(name, 1, 60) end
	return name
end

local function installTimerWrap()
	if ZCPERF.origTimerCreate then return end
	ZCPERF.origTimerCreate = timer.Create
	ZCPERF.origTimerSimple = timer.Simple

	timer.Create = function(name, delay, reps, fn, ...)
		if isfunction(fn) then
			local key = "timer/" .. normTimerName(name)
			local inner = fn
			fn = function(...)
				local k0, t0 = gcCount("count"), SysTime()
				local a, b, c, d = inner(...)
				record(key, SysTime() - t0, gcCount("count") - k0)
				return a, b, c, d
			end
		end
		return ZCPERF.origTimerCreate(name, delay, reps, fn, ...)
	end

	timer.Simple = function(delay, fn, ...)
		if isfunction(fn) then
			local info = debug.getinfo(2, "Sl")
			local src = info and ((info.short_src or "?") .. ":" .. (info.currentline or 0)) or "?"
			local key = "timer.Simple/" .. src
			local inner = fn
			fn = function(...)
				local k0, t0 = gcCount("count"), SysTime()
				local a, b, c, d = inner(...)
				record(key, SysTime() - t0, gcCount("count") - k0)
				return a, b, c, d
			end
		end
		return ZCPERF.origTimerSimple(delay, fn, ...)
	end
end

local function removeTimerWrap()
	if not ZCPERF.origTimerCreate then return end
	timer.Create = ZCPERF.origTimerCreate
	timer.Simple = ZCPERF.origTimerSimple
	ZCPERF.origTimerCreate, ZCPERF.origTimerSimple = nil, nil
end

-- ---- v1.1 NET instrumentation ----
-- Counts every outgoing net message: sends, payload bytes, recipients
-- and total wire bytes (payload x recipients). Netvar/organism floods
-- show up here in black and white.
local NET_SENDERS = { "Send", "SendOmit", "Broadcast", "SendPVS", "SendPAS" }

local function netRow(name)
	local r = ZCPERF.netstats[name]
	if not r then
		r = { sends = 0, bytes = 0, recips = 0 }
		ZCPERF.netstats[name] = r
	end
	return r
end

local function countRecipients(target)
	if target == nil then return #player.GetAll() end
	if istable(target) then return #target end
	return 1
end

local function installNetWrap()
	if ZCPERF.origNetStart then return end
	ZCPERF.origNetStart = net.Start
	ZCPERF.origNetSenders = {}

	net.Start = function(name, unreliable)
		ZCPERF.curNet = name
		return ZCPERF.origNetStart(name, unreliable)
	end

	for _, sender in ipairs(NET_SENDERS) do
		local orig = net[sender]
		if isfunction(orig) then
			ZCPERF.origNetSenders[sender] = orig
			net[sender] = function(target, ...)
				local name = ZCPERF.curNet
				if name then
					local ok, bytes = pcall(net.BytesWritten)
					if ok and isnumber(bytes) then
						local n = (sender == "Broadcast") and #player.GetAll() or countRecipients(target)
						local r = netRow(name)
						r.sends = r.sends + 1
						r.bytes = r.bytes + bytes
						r.recips = r.recips + n
					end
				end
				ZCPERF.curNet = nil
				return orig(target, ...)
			end
		end
	end
end

local function removeNetWrap()
	if not ZCPERF.origNetStart then return end
	net.Start = ZCPERF.origNetStart
	for sender, orig in pairs(ZCPERF.origNetSenders or {}) do
		net[sender] = orig
	end
	ZCPERF.origNetStart, ZCPERF.origNetSenders = nil, nil
end

-- ---- v1.1 TRACE instrumentation ----
-- Traces are the classic invisible cost: every bullet, melee hull,
-- AI check and spawn-point probe is one. Count + time only (naming
-- the caller would need debug.getinfo per trace = too expensive).
local TRACE_FNS = { "TraceLine", "TraceHull", "TraceEntity" }

local function installTraceWrap()
	if ZCPERF.origTraces then return end
	ZCPERF.origTraces = {}
	for _, fname in ipairs(TRACE_FNS) do
		local orig = util[fname]
		if isfunction(orig) then
			ZCPERF.origTraces[fname] = orig
			local key = "trace/util." .. fname
			util[fname] = function(...)
				local t0 = SysTime()
				local a, b = orig(...)
				local st = ZCPERF.tracestats
				if st then
					local r = st[key]
					if not r then r = { calls = 0, total = 0 } st[key] = r end
					r.calls = r.calls + 1
					r.total = r.total + (SysTime() - t0)
				end
				return a, b
			end
		end
	end
end

local function removeTraceWrap()
	if not ZCPERF.origTraces then return end
	for fname, orig in pairs(ZCPERF.origTraces) do util[fname] = orig end
	ZCPERF.origTraces = nil
end

-- ---- v1.1 ENTITY CHURN ----
-- Creation/removal rate by class. Catches loot spam, gib storms and
-- anything quietly recycling entities every round.
local function installChurn()
	hook.Add("OnEntityCreated", "zc_perf_churn_c", function(e)
		local c = ZCPERF.churn
		if not c or not IsValid(e) then return end
		local k = e:GetClass()
		local r = c[k]
		if not r then r = { made = 0, gone = 0 } c[k] = r end
		r.made = r.made + 1
	end)
	hook.Add("EntityRemoved", "zc_perf_churn_r", function(e)
		local c = ZCPERF.churn
		if not c or not IsValid(e) then return end
		local k = e:GetClass()
		local r = c[k]
		if not r then r = { made = 0, gone = 0 } c[k] = r end
		r.gone = r.gone + 1
	end)
end

local function removeChurn()
	hook.Remove("OnEntityCreated", "zc_perf_churn_c")
	hook.Remove("EntityRemoved", "zc_perf_churn_r")
end

-- ---- window ----
local function resetWindow()
	ZCPERF.stats = {}
	ZCPERF.netstats = {}
	ZCPERF.tracestats = {}
	ZCPERF.churn = {}
	-- v1.1 samplers: Lua memory (GC pressure - a collection pass is a
	-- classic invisible frame spike) and alive-player count (directly
	-- tests the "only early round while everyone's alive" pattern)
	ZCPERF.mem = { min = math.huge, max = 0, sum = 0, n = 0, start = collectgarbage("count") }
	ZCPERF.alive = { min = math.huge, max = 0, sum = 0, n = 0 }
	-- v1.4 GC-PAUSE DETECTION: Lua memory is sampled EVERY frame. A frame
	-- where memory DROPS is a frame in which the collector ran. Correlating
	-- that against the long frames answers the question the hook/timer
	-- numbers cannot: are the spikes garbage collection, or something else?
	ZCPERF.gc = {
		lastKb = collectgarbage("count"),
		anyDrop = 0, bigDrop = 0, freed = 0,
		spikeGC = 0, spikeNoGC = 0, spikeGCms = 0, spikeNoGCms = 0,
		worstDrop = 0, worstDropMs = 0,
	}
	ZCPERF.frame = {}
	ZCPERF.fcount, ZCPERF.fsum, ZCPERF.fmax = 0, 0, 0
	ZCPERF.bcounts = { 0, 0, 0, 0, 0, 0, 0 }
	ZCPERF.spikes, ZCPERF.spikeIdx = {}, 0
	ZCPERF.worst = {} -- v1.6: sorted descending by frame ms, never evicted by age
	ZCPERF.lastT = nil
	ZCPERF.armedAt = SysTime()
	if ZCPERF.wrapped then
		for _, w in ipairs(ZCPERF.wrapped) do
			readd(w.event, w.name, makeWrap(w.event .. "/" .. w.name, w.fn), w.prio)
		end
	end
end

local function arm(reason)
	if ZCPERF.wrapped then return end
	ZCPERF.stats, ZCPERF.netstats, ZCPERF.frame = {}, {}, {}
	-- pick the event set for this capture before collecting anything
	EVENTS = cv_light:GetBool() and EVENTS_LIGHT or EVENTS_FULL
	ZCPERF.light = cv_light:GetBool()

	ZCPERF.wrapped = collectHooks()
	installTimerWrap()
	installNetWrap()
	if not ZCPERF.light then installTraceWrap() end -- traces are ~1400/s
	installChurn()
	resetWindow()

	hook.Add("Think", "zc_perf_frame", function()
		local now = SysTime()
		local last = ZCPERF.lastT
		ZCPERF.lastT = now
		local fr = ZCPERF.frame
		if last then
			local dt = (now - last) * 1000
			ZCPERF.fcount = ZCPERF.fcount + 1
			ZCPERF.fsum = ZCPERF.fsum + dt
			if dt > ZCPERF.fmax then ZCPERF.fmax = dt end
			local b = 7
			for i = 1, 6 do
				if dt <= BUCKETS[i] then b = i break end
			end
			ZCPERF.bcounts[b] = ZCPERF.bcounts[b] + 1

			-- v1.4: per-frame Lua memory delta. Negative = the collector
			-- ran during this frame and freed that much.
			local g = ZCPERF.gc
			local kb = collectgarbage("count")
			local dKb = kb - (g.lastKb or kb)
			g.lastKb = kb
			local collected = dKb < -8 -- ignore float noise
			if collected then
				g.anyDrop = g.anyDrop + 1
				g.freed = g.freed - dKb
				if -dKb > 256 then g.bigDrop = g.bigDrop + 1 end
				if -dKb > g.worstDrop then g.worstDrop, g.worstDropMs = -dKb, dt end
			end

			if dt >= cv_spike:GetFloat() then
				if collected then
					g.spikeGC = g.spikeGC + 1
					g.spikeGCms = g.spikeGCms + dt
				else
					g.spikeNoGC = g.spikeNoGC + 1
					g.spikeNoGCms = g.spikeNoGCms + dt
				end
				-- v1.6: sum ALL attributed Lua before truncating, so the
				-- "Lua x of y ms" figure is the real total and not just
				-- the top few entries.
				local top, luaMs = {}, 0
				for k, v in pairs(fr) do
					local ms = v * 1000
					luaMs = luaMs + ms
					top[#top + 1] = { k = k, ms = ms }
				end
				table.sort(top, function(x, y) return x.ms > y.ms end)
				for i = #top, 9, -1 do top[i] = nil end -- keep 8; recency prints 5

				local rec = {
					ms = dt,
					ents = ents.GetCount(),
					top = top,
					lua = luaMs,
					gc = collected and -dKb or nil,
					-- v1.6 context: when in the window, what the round was
					-- doing, and how many players were alive. A monster frame
					-- during a state change IS the round transition.
					t = now - (ZCPERF.armedAt or now),
					rs = zb and zb.ROUND_STATE or nil,
					mode = zb and zb.CROUND or nil,
					alive = ZCPERF.aliveNow,
				}

				ZCPERF.spikeIdx = (ZCPERF.spikeIdx % 8) + 1
				ZCPERF.spikes[ZCPERF.spikeIdx] = rec

				-- v1.6 WORST RING: insertion-sorted, capped. A frame can only
				-- leave this list by being beaten, never by being old.
				local wcap = cv_worst:GetInt()
				if wcap > 0 then
					-- guard: a hotload over a live capture leaves .worst nil
					local W = ZCPERF.worst
					if not W then W = {} ZCPERF.worst = W end
					if #W < wcap or dt > W[#W].ms then
						local i = #W + 1
						W[i] = rec
						while i > 1 and W[i - 1].ms < W[i].ms do
							W[i - 1], W[i] = W[i], W[i - 1]
							i = i - 1
						end
						for j = #W, wcap + 1, -1 do W[j] = nil end
					end
				end
			end
		end
		for k in pairs(fr) do fr[k] = nil end
	end)

	print("[zc_perf] ARMED (" .. (reason or "manual") .. ") - " .. #ZCPERF.wrapped .. " hooks + timers + net"
		.. (ZCPERF.light and " [LIGHT: per-usercmd hooks and traces not wrapped]" or " + traces [FULL]") .. ".")
end

local function disarm(quiet)
	removeTimerWrap()
	removeNetWrap()
	removeTraceWrap()
	removeChurn()
	if not ZCPERF.wrapped then return end
	for _, w in ipairs(ZCPERF.wrapped) do
		readd(w.event, w.name, w.fn, w.prio)
	end
	ZCPERF.wrapped = nil
	hook.Remove("Think", "zc_perf_frame")
	if quiet then
		print("[zc_perf] disarmed - originals restored.")
	else
		alertStaff(3, "recording stopped - profiler off, originals restored")
	end
end

timer.Create("zc_perf_sync", 1, 0, function()
	local want = cv_on:GetBool()
	if want and not ZCPERF.wrapped then
		arm("convar")
		alertStaff(2, "profiler armed manually - recording until zc_perf 0")
	end
	if not want and ZCPERF.wrapped and not ZCPERF.autoUntil then disarm() end
end)

-- ---- reporting ----
local function fmt(n, d) return string.format("%." .. (d or 1) .. "f", n) end

local function census()
	local counts, rags, frozen, awake = {}, 0, 0, 0
	for _, e in ipairs(ents.GetAll()) do
		local c = e:GetClass()
		counts[c] = (counts[c] or 0) + 1
		if c == "prop_ragdoll" then
			rags = rags + 1
			if e.zc_cleanFrozen then frozen = frozen + 1 end
		elseif c == "prop_physics" then
			local ph = e:GetPhysicsObject()
			if IsValid(ph) and not ph:IsAsleep() then awake = awake + 1 end
		end
	end
	local top = {}
	for c, n in pairs(counts) do top[#top + 1] = { c = c, n = n } end
	table.sort(top, function(a, b) return a.n > b.n end)
	return top, rags, frozen, awake
end

local function buildReport()
	local L = {}
	local function out(s) L[#L + 1] = s end

	local elapsed = SysTime() - ZCPERF.armedAt
	out("================ ZC_PERF REPORT ================")
	out("map: " .. game.GetMap() .. " | players: " .. #player.GetAll() .. " | " .. os.date("%Y-%m-%d %H:%M:%S"))
	if ZCPERF.light then
		out("mode: LIGHT (per-usercmd hooks + traces NOT wrapped - low observer effect;")
		out("      those cost ~4ms/frame combined, measured repeatedly in earlier full captures)")
	else
		out("mode: FULL (everything wrapped - NOTE the profiler's own overhead inflates")
		out("      frame times and hook totals in this capture; compare like with like)")
	end
	out("window: " .. fmt(elapsed) .. "s | frames: " .. ZCPERF.fcount .. " | effective tick: " .. fmt(ZCPERF.fcount / math.max(elapsed, 0.001)))
	out("frame ms: avg " .. fmt(ZCPERF.fsum / math.max(ZCPERF.fcount, 1), 2) .. " | worst " .. fmt(ZCPERF.fmax, 1))
	out("buckets(ms) <10:" .. ZCPERF.bcounts[1] .. " 10-15:" .. ZCPERF.bcounts[2] .. " 15-20:" .. ZCPERF.bcounts[3]
		.. " 20-25:" .. ZCPERF.bcounts[4] .. " 25-33:" .. ZCPERF.bcounts[5] .. " 33-50:" .. ZCPERF.bcounts[6] .. " >50:" .. ZCPERF.bcounts[7])

	local rows, luaTotal, timerTotal = {}, 0, 0
	for k, st in pairs(ZCPERF.stats) do
		if st.calls > 0 and st.total > 0 then
			rows[#rows + 1] = { k = k, st = st }
			luaTotal = luaTotal + st.total
			if string.sub(k, 1, 5) == "timer" then timerTotal = timerTotal + st.total end
		end
	end
	table.sort(rows, function(a, b) return a.st.total > b.st.total end)

	out("measured Lua: " .. fmt(luaTotal * 1000) .. "ms (" .. fmt(luaTotal / elapsed * 100) .. "% of wall)"
		.. "  [hooks " .. fmt((luaTotal - timerTotal) / elapsed * 100) .. "% + timers " .. fmt(timerTotal / elapsed * 100) .. "%]")
	out("unmeasured (engine snapshot/physics/net-send + idle): " .. fmt((elapsed - luaTotal) * 1000) .. "ms")
	out("  (below server tickrate there is no idle - unmeasured IS the engine)")

	out("---- top Lua by total ms (hooks + timers) ----")
	for i = 1, math.min(22, #rows) do
		local r = rows[i]
		local ms = r.st.total * 1000
		out(fmt(ms, 1) .. "ms  " .. r.k .. "  (" .. r.st.calls .. " calls, " .. fmt(ms / r.st.calls, 3) .. "ms/call, " .. fmt(r.st.total / elapsed * 100) .. "%)")
	end

	-- allocation section
	local arows, kbTotal = {}, 0
	for k, st in pairs(ZCPERF.stats) do
		if (st.kb or 0) > 0 then arows[#arows + 1] = { k = k, st = st } kbTotal = kbTotal + st.kb end
	end
	table.sort(arows, function(a, b) return a.st.kb > b.st.kb end)
	out("---- top Lua by ALLOCATION (inclusive, lower bound: samples with a GC step inside are dropped) ----")
	out("measured: " .. fmt(kbTotal / 1024, 1) .. " MB, " .. fmt(kbTotal / elapsed, 1) .. " KB/s  (nested hooks are counted in their caller too)")
	for i = 1, math.min(15, #arows) do
		local r = arows[i]
		out(fmt(r.st.kb / elapsed, 1) .. "KB/s  " .. r.k .. "  (" .. fmt(r.st.kb / 1024, 2) .. " MB, " .. fmt(r.st.kb * 1024 / r.st.calls, 0) .. " B/call)")
	end

	-- net section
	local nrows, totalWire, totalSends = {}, 0, 0
	for name, r in pairs(ZCPERF.netstats) do
		local wire = r.bytes * (r.recips / math.max(r.sends, 1))
		nrows[#nrows + 1] = { name = name, r = r, wire = wire }
		totalWire = totalWire + wire
		totalSends = totalSends + r.sends
	end
	table.sort(nrows, function(a, b) return a.wire > b.wire end)
	out("---- net messages (payload x recipients) ----")
	out("total: " .. totalSends .. " sends, " .. fmt(totalWire / 1024) .. " KB wire, " .. fmt(totalWire / 1024 / math.max(elapsed, 0.001)) .. " KB/s")
	for i = 1, math.min(14, #nrows) do
		local n = nrows[i]
		out(fmt(n.wire / 1024) .. "KB  " .. n.name .. "  (" .. n.r.sends .. " sends, "
			.. fmt(n.r.bytes / math.max(n.r.sends, 1), 0) .. "B each, "
			.. fmt(n.r.recips / math.max(n.r.sends, 1), 1) .. " recips avg, "
			.. fmt(n.r.sends / math.max(elapsed, 0.001), 1) .. "/s)")
	end
	if #nrows == 0 then out("(none captured)") end

	-- traces
	local ttot, tcalls = 0, 0
	for _, r in pairs(ZCPERF.tracestats or {}) do ttot = ttot + r.total tcalls = tcalls + r.calls end
	if tcalls > 0 then
		out("---- traces ----")
		out("total: " .. tcalls .. " (" .. fmt(tcalls / math.max(elapsed, 0.001), 0) .. "/s, "
			.. fmt(ttot * 1000) .. "ms, " .. fmt(ttot / elapsed * 100) .. "% of wall)")
		for k, r in pairs(ZCPERF.tracestats) do
			out("  " .. k .. ": " .. r.calls .. " (" .. fmt(r.total * 1000) .. "ms)")
		end
	end

	-- entity churn
	local crows, madeTot, goneTot = {}, 0, 0
	for k, r in pairs(ZCPERF.churn or {}) do
		crows[#crows + 1] = { k = k, r = r }
		madeTot = madeTot + r.made; goneTot = goneTot + r.gone
	end
	table.sort(crows, function(a, b) return a.r.made > b.r.made end)
	if madeTot > 0 or goneTot > 0 then
		out("---- entity churn ----")
		out("created " .. madeTot .. " (" .. fmt(madeTot / math.max(elapsed, 0.001), 1) .. "/s), removed " .. goneTot
			.. " -> net " .. (madeTot - goneTot))
		for i = 1, math.min(8, #crows) do
			out("  " .. crows[i].k .. ": +" .. crows[i].r.made .. " / -" .. crows[i].r.gone)
		end
	end

	-- GC pressure + alive-player span
	local m, al = ZCPERF.mem, ZCPERF.alive
	if m and m.n > 0 then
		out("---- lua memory / players over the window ----")
		out("lua mem: " .. fmt(m.min / 1024) .. "-" .. fmt(m.max / 1024) .. " MB (avg " .. fmt(m.sum / m.n / 1024)
			.. ", swing " .. fmt((m.max - m.min) / 1024) .. " MB = GC churn)")
		if al and al.n > 0 then
			out("alive players: " .. al.min .. "-" .. al.max .. " (avg " .. fmt(al.sum / al.n, 1) .. ")")
		end
	end

	-- v1.4 THE GC VERDICT: did the collector run inside the long frames?
	local g = ZCPERF.gc
	if g then
		local spikes = g.spikeGC + g.spikeNoGC
		out("---- GC pause correlation ----")
		out("collections: " .. g.anyDrop .. " frames freed memory (" .. g.bigDrop .. " freed >256KB), "
			.. fmt(g.freed / 1024) .. " MB reclaimed total, " .. fmt(g.freed / 1024 / math.max(elapsed, 0.001), 2) .. " MB/s allocation churn")
		out("worst single collection: " .. fmt(g.worstDrop / 1024, 2) .. " MB freed in a " .. fmt(g.worstDropMs) .. "ms frame")
		if spikes > 0 then
			local pct = g.spikeGC / spikes * 100
			out("long frames WITH a collection: " .. g.spikeGC .. "/" .. spikes .. " (" .. fmt(pct) .. "%), avg "
				.. fmt(g.spikeGCms / math.max(g.spikeGC, 1)) .. "ms")
			out("long frames WITHOUT one:       " .. g.spikeNoGC .. "/" .. spikes .. ", avg "
				.. fmt(g.spikeNoGCms / math.max(g.spikeNoGC, 1)) .. "ms")
			-- baseline: what share of ALL frames had a collection? If the
			-- spike share is much higher, GC is implicated; if it matches,
			-- collections are just as common in fast frames = NOT the cause.
			local base = g.anyDrop / math.max(ZCPERF.fcount, 1) * 100
			out("baseline (all frames with a collection): " .. fmt(base) .. "%")
			if pct > base * 1.8 and g.spikeGC >= 5 then
				out("VERDICT: GC IS IMPLICATED - collections are " .. fmt(pct / math.max(base, 0.01), 1)
					.. "x over-represented in long frames. Attack allocation churn (traces, net messages, per-tick tables).")
			elseif spikes >= 10 then
				out("VERDICT: GC is NOT the spike cause - collections are no more common in long frames than normal ones. Look at engine-side work (snapshot packing, entity spawns, physics events).")
			else
				out("VERDICT: too few long frames in this window to call it.")
			end
		end
	end

	-- v1.6: a spike line, shared by both rings.
	local RSTATE = { [0] = "PRE", [1] = "LIVE", [3] = "ENDING" }
	local function spikeLine(s, topn)
		local line = fmt(s.ms, 1) .. "ms"
		if s.t then line = line .. " @" .. fmt(s.t, 1) .. "s" end
		line = line .. " | " .. s.ents .. " ents"
		if s.alive then line = line .. ", " .. s.alive .. " alive" end
		if s.rs ~= nil then
			line = line .. ", round " .. (RSTATE[s.rs] or tostring(s.rs))
				.. (s.mode and ("/" .. tostring(s.mode)) or "")
		end
		if s.gc then line = line .. " [GC freed " .. fmt(s.gc / 1024, 2) .. "MB]" end

		-- the decisive figure: how much of this frame we can actually name
		local lua = s.lua or 0
		local pct = s.ms > 0 and (lua / s.ms * 100) or 0
		line = line .. " | Lua " .. fmt(lua, 2) .. "/" .. fmt(s.ms, 1) .. "ms = " .. fmt(pct, 0) .. "%"
		if pct < 10 then line = line .. " <- ENGINE-SIDE (no Lua to blame)" end
		line = line .. ":"

		for i = 1, math.min(topn, #s.top) do
			line = line .. " " .. s.top[i].k .. "=" .. fmt(s.top[i].ms, 2)
		end
		return line
	end

	if cv_worst:GetInt() > 0 then
		out("---- WORST frames of the window (kept by size, never evicted by age) ----")
		local W = ZCPERF.worst or {}
		if #W == 0 then
			out("(none over " .. cv_spike:GetFloat() .. "ms)")
		else
			for i = 1, #W do out(spikeLine(W[i], 8)) end
		end
	end

	out("---- spikes (frames >= " .. cv_spike:GetFloat() .. "ms, last 8 by RECENCY - may repeat the list above) ----")
	local any = false
	for _, s in pairs(ZCPERF.spikes) do
		any = true
		out(spikeLine(s, 5))
	end
	if not any then out("(none)") end

	out("---- census now ----")
	local top, rags, frozen, awake = census()
	local orgs = (hg and hg.organism and hg.organism.list) and table.Count(hg.organism.list) or -1
	local weps = (hg and hg.weapons) and #hg.weapons or -1
	local alive = 0
	for _, p in ipairs(player.GetAll()) do if p:Alive() and p:Team() ~= TEAM_SPECTATOR then alive = alive + 1 end end
	out("edicts: " .. ents.GetCount() .. " | alive players: " .. alive .. " | ragdolls: " .. rags .. " (" .. frozen .. " frozen)"
		.. " | props awake: " .. awake .. " | organism list: " .. orgs .. " | hg.weapons: " .. weps)
	local line = "classes:"
	for i = 1, math.min(12, #top) do line = line .. " " .. top[i].c .. "=" .. top[i].n end
	out(line)
	out("round: " .. tostring(zb and zb.CROUND) .. " | type: " .. tostring(zb and zb.modes and zb.modes["hmcd"] and zb.modes["hmcd"].Type))
	out("================================================")
	return table.concat(L, "\n")
end

local function saveReport(text)
	if not cv_save:GetBool() then return nil end
	if not file.IsDir(SAVEDIR, "DATA") then file.CreateDir(SAVEDIR) end
	local fn = SAVEDIR .. "/" .. game.GetMap() .. "-" .. os.date("%Y%m%d-%H%M%S") .. ".txt"
	file.Write(fn, text)
	return fn
end

local function report(ply, autoTag, noAlert)
	if not ZCPERF.wrapped then
		local m = "[zc_perf] not armed - run: zc_perf 1"
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, m) else print(m) end
		return
	end
	local elapsed = SysTime() - ZCPERF.armedAt
	if elapsed < 1 or ZCPERF.fcount < 10 then
		local m = "[zc_perf] window too short - let it run a bit"
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, m) else print(m) end
		return
	end

	local text = buildReport()
	-- v1.6: print the trigger that ACTUALLY fired. v1.1-1.5 hardcoded the
	-- tick-average reason here, so every spike-triggered capture lied about
	-- why it existed.
	if autoTag then
		text = "[AUTO-CAPTURE: " .. (ZCPERF.autoWhy or ("tick sagged below " .. cv_autotick:GetInt())) .. "]\n" .. text
	end
	local saved = saveReport(text)

	if IsValid(ply) then
		for line in string.gmatch(text, "[^\n]+") do ply:PrintMessage(HUD_PRINTCONSOLE, line) end
		if saved then ply:PrintMessage(HUD_PRINTCONSOLE, "[zc_perf] saved: data/" .. saved) end
	else
		print(text)
		if saved then print("[zc_perf] saved: data/" .. saved) end
	end
	if saved and not noAlert then alertStaff(4, "report saved -> data/" .. saved) end
	return saved
end

-- ---- v1.1 AUTO-CAPTURE WATCHER (always on, featherweight) ----
-- One Think, two SysTime reads, no wrapping: safe to leave running.
local wLast, wFrames, wStart, sagFor, wSpikes = nil, 0, SysTime(), 0, 0
hook.Add("Think", "zc_perf_watch", function()
	local now = SysTime()
	if wLast then
		wFrames = wFrames + 1
		if (now - wLast) * 1000 >= cv_spike:GetFloat() then wSpikes = wSpikes + 1 end
	end
	wLast = now

	local span = now - wStart
	if span < 1 then return end
	local tick = wFrames / span
	local spikes = wSpikes
	wFrames, wSpikes, wStart = 0, 0, now

	-- 1Hz samplers (armed only): GC pressure + alive-player count
	if ZCPERF.wrapped and ZCPERF.mem then
		local kb = collectgarbage("count")
		local m = ZCPERF.mem
		m.min = math.min(m.min, kb); m.max = math.max(m.max, kb)
		m.sum = m.sum + kb; m.n = m.n + 1
		local a = 0
		for _, p in ipairs(player.GetAll()) do
			if p:Alive() and p:Team() ~= TEAM_SPECTATOR then a = a + 1 end
		end
		local al = ZCPERF.alive
		al.min = math.min(al.min, a); al.max = math.max(al.max, a)
		al.sum = al.sum + a; al.n = al.n + 1
		-- v1.6: last sampled value, so a spike record can stamp the alive
		-- count for free instead of looping players inside a hitching frame
		ZCPERF.aliveNow = a
	end

	-- auto-stop a running capture (alert order: stopped -> report saved)
	if ZCPERF.autoUntil and now >= ZCPERF.autoUntil then
		ZCPERF.autoUntil = nil
		local secs = cv_autotime:GetInt()
		local saved = report(nil, true, true)
		disarm(true)
		ZCPERF.autoCD = now + cv_autocd:GetFloat()
		local cd = cv_autocd:GetInt()
		alertStaff(3, "auto-capture finished (" .. secs .. "s recorded) - profiler off"
			.. (cd > 0 and (", next possible in " .. math.max(1, math.Round(cd / 60)) .. "m") or ""))
		if saved then
			alertStaff(4, "report saved -> data/" .. saved .. "  (zc_perf_reports to list)")
		end
		return
	end
	if ZCPERF.autoUntil then return end

	if not cv_auto:GetBool() or ZCPERF.wrapped then sagFor = 0 return end
	if (ZCPERF.autoCD or 0) > now then sagFor = 0 return end

	-- v1.7: don't burn a capture on the map change itself, and don't
	-- record 60 seconds of an empty server. sagFor is RESET (not decayed)
	-- so a load sag cannot bank credit toward a capture that fires the
	-- instant the grace expires.
	if (ZCPERF.mapAt or 0) + cv_autograce:GetFloat() > now then sagFor = 0 return end
	if player.GetCount() < cv_autominply:GetInt() then sagFor = 0 return end

	-- v1.3: sag = low average tick OR a hitchy second (long-frame count).
	-- The second test is the one that catches "50 tick but stuttering".
	local spikeTrig = cv_autospikes:GetInt() > 0 and spikes >= cv_autospikes:GetInt()
	local tickTrig = tick < cv_autotick:GetFloat()

	if tickTrig or spikeTrig then
		sagFor = sagFor + span
		if sagFor >= cv_autosus:GetFloat() then
			sagFor = 0
			local why = tickTrig
				and ("tick " .. fmt(tick) .. " < " .. cv_autotick:GetInt())
				or (spikes .. " frames over " .. cv_spike:GetInt() .. "ms in a second")
			arm("auto: " .. why)
			ZCPERF.autoWhy = why -- v1.6: threaded into the report header
			ZCPERF.autoUntil = now + cv_autotime:GetFloat()
			alertStaff(1, why .. " on " .. game.GetMap() .. " - RECORDING for " .. cv_autotime:GetInt() .. "s")
		end
	else
		-- decay, not a hard reset: a server flapping either side of the
		-- threshold still accumulates toward a capture instead of being
		-- wiped clean by one good second
		sagFor = math.max(0, sagFor - span)
	end
end)

concommand.Add("zc_perf_report", function(ply)
	if IsValid(ply) and not ply:IsAdmin() then return end
	report(ply)
end)

concommand.Add("zc_perf_reset", function(ply)
	if IsValid(ply) and not ply:IsAdmin() then return end
	if not ZCPERF.wrapped then
		local m = "[zc_perf] not armed"
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, m) else print(m) end
		return
	end
	resetWindow()
	print("[zc_perf] window reset")
end)

concommand.Add("zc_perf_reports", function(ply)
	if IsValid(ply) and not ply:IsAdmin() then return end
	local files = select(1, file.Find(SAVEDIR .. "/*.txt", "DATA")) or {}
	local function say(s)
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, s) else print(s) end
	end
	say("[zc_perf] " .. #files .. " saved report(s) in garrysmod/data/" .. SAVEDIR .. "/")
	for _, f in ipairs(files) do
		say("  " .. f .. "  (" .. math.Round(file.Size(SAVEDIR .. "/" .. f, "DATA") / 1024, 1) .. " KB)")
	end
end)

print("[zc_perf] v1.7 loaded - auto-capture " .. (cv_auto:GetBool() and "ON" or "off")
	.. " (arms below " .. cv_autotick:GetInt() .. " tick for " .. cv_autosus:GetInt() .. "s, records "
	.. cv_autotime:GetInt() .. "s, saves to data/" .. SAVEDIR .. "/)")
print("[zc_perf] auto-capture blocked for " .. cv_autograce:GetInt() .. "s after map load"
	.. " and below " .. cv_autominply:GetInt() .. " players (zc_perf_auto_grace / zc_perf_auto_minplayers)")
