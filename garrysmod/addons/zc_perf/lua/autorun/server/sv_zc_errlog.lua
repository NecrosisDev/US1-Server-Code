-- ============================================================
--  ZC ERRLOG (part of ZC Perf) - snag serverside Lua errors
--  into a txt file so they can be worked on later.
-- ------------------------------------------------------------
--  Joey: "a function that snags lua errors and throws them into
--  a txt file so we can work on them later."
--
--  TWO CAPTURE PATHS:
--   1. hook "OnLuaError" - hard script errors (the red console
--      ones). Fires for server errors; on builds that relay them,
--      client errors arrive with a realm tag and are logged too.
--   2. Detoured ErrorNoHalt / ErrorNoHaltWithStack - the "soft"
--      errors addons print without halting; a huge share of real
--      breakage surfaces only here. Originals preserved and always
--      called; detour is convar-gated and self-healing (1s sync
--      retakes it if another addon or a gamemode reload stomps it).
--
--  WHY NOT WRITE PER ERROR: one broken Think hook errors every
--  tick - 50+/sec, thousands per minute. Writing each would turn
--  an error into a disk-IO perf problem. Instead everything is
--  DEDUPED IN MEMORY by error signature (count + first/last seen
--  + stack captured once) and flushed as compact batches:
--   * a NEW signature writes immediately-ish (next 5s tick) with
--     its full stack
--   * repeats only bump counters; every zc_errlog_flush seconds a
--     one-line "xN more (total M)" update is appended per changed
--     signature
--   * at most zc_errlog_max unique signatures are tracked per map
--     (overflow noted once) - a runaway error can't eat memory
--
--  FILES: garrysmod/data/zc_errlog/errors-YYYY-MM-DD.txt (daily).
--  file.Write/Append require .txt - which is what we want anyway.
--
--  Convars (ARCHIVE, live):
--    zc_errlog          1    master
--    zc_errlog_nohalt   1    also capture ErrorNoHalt soft errors
--    zc_errlog_flush    15   seconds between counter-update writes
--    zc_errlog_max      200  unique signatures tracked per map
--  Commands (admin/console):
--    zc_errlog_stats    top offenders by count, file name, totals
--    zc_errlog_dump     force a flush right now
--    zc_errlog_clear    reset in-memory tracking (file untouched)
--  Live test after hotload:  lua_run error("zc_errlog test")
--  Serverside only = hotloadable.
-- ============================================================
if not SERVER then return end

ZCERRLOG = ZCERRLOG or {}
local K = ZCERRLOG
K.errs = K.errs or {}       -- [signature] = rec
K.order = K.order or {}     -- insertion order for stats
K.overflow = K.overflow or 0
K.totalSeen = K.totalSeen or 0

local cv_on    = CreateConVar("zc_errlog", "1", FCVAR_ARCHIVE, "Log Lua errors to data/zc_errlog/ (deduped)", 0, 1)
local cv_soft  = CreateConVar("zc_errlog_nohalt", "1", FCVAR_ARCHIVE, "Also capture ErrorNoHalt soft errors", 0, 1)
local cv_flush = CreateConVar("zc_errlog_flush", "15", FCVAR_ARCHIVE, "Seconds between counter-update writes", 5, 300)
local cv_max   = CreateConVar("zc_errlog_max", "200", FCVAR_ARCHIVE, "Max unique error signatures tracked per map", 10, 2000)

local DIR = "zc_errlog"

local function logfile()
	return DIR .. "/errors-" .. os.date("%Y-%m-%d") .. ".txt"
end

local function ensureDir()
	if not file.IsDir(DIR, "DATA") then file.CreateDir(DIR) end
end

local function stamp()
	return os.date("%H:%M:%S")
end

-- ------------------------------------------------------------
--  RECORDING (cheap path - no string building, no IO)
-- ------------------------------------------------------------
local function record(sig, realm, stackText, n)
	if not cv_on:GetBool() then return end
	n = n or 1
	K.totalSeen = K.totalSeen + n

	local rec = K.errs[sig]
	if rec then
		rec.count = rec.count + n
		rec.last = CurTime()
		rec.dirty = true
		return
	end

	if #K.order >= cv_max:GetInt() then
		K.overflow = K.overflow + 1
		return
	end

	rec = {
		sig = sig,
		realm = realm or "server",
		stack = stackText or "",
		count = n,
		written = 0,          -- occurrences already flushed to disk
		first = CurTime(),
		last = CurTime(),
		map = game.GetMap(),
		round = tostring(zb and zb.CROUND or "?"),
		dirty = true,
		new = true,
	}
	K.errs[sig] = rec
	K.order[#K.order + 1] = sig
end

-- stack table from OnLuaError -> readable lines
local function formatStack(stack)
	if not istable(stack) then return "" end
	local out = {}
	for i, fr in ipairs(stack) do
		if istable(fr) then
			out[#out + 1] = ("    %d. %s - %s:%s"):format(i,
				tostring(fr.Function or fr["Function"] or "?"),
				tostring(fr.File or "?"), tostring(fr.Line or "?"))
		end
	end
	return table.concat(out, "\n")
end

-- ------------------------------------------------------------
--  CAPTURE 1: hard errors
-- ------------------------------------------------------------
hook.Add("OnLuaError", "zc_errlog", function(err, realm, stack, name, id)
	local tag = "server"
	if realm ~= nil and realm ~= "" then tag = tostring(realm) end
	if name and name ~= "" then tag = tag .. "/" .. tostring(name) end
	record(tostring(err), tag, formatStack(stack))
end)

-- ------------------------------------------------------------
--  CAPTURE 1b: CLIENT errors, relayed by our own client half
--  (cl_zc_errlog.lua) - the server build's OnLuaError doesn't
--  receive client errors, but the hook fires on each player's own
--  machine; clients dedupe locally and ship compact batches.
--  Everything here is PLAYER-SUPPLIED DATA: hard caps on rate,
--  batch size, string length, and per-player unique signatures,
--  and entries are tagged [client] so fabricated reports can
--  never masquerade as server errors.
-- ------------------------------------------------------------
local cv_clients = CreateConVar("zc_errlog_clients", "1", FCVAR_ARCHIVE, "Accept clientside error reports from players", 0, 1)
util.AddNetworkString("zc_errlog_c")

local CL_MIN_INTERVAL = 15   -- client sends every 20; anything faster is hostile
local CL_MAX_BATCH = 8
local CL_MAX_UNIQUE = 30     -- per player per map

net.Receive("zc_errlog_c", function(len, ply)
	if not (cv_on:GetBool() and cv_clients:GetBool()) then return end
	if not IsValid(ply) then return end
	if (ply.zc_errlog_next or 0) > CurTime() then return end
	ply.zc_errlog_next = CurTime() + CL_MIN_INTERVAL
	ply.zc_errlog_relayActive = true -- engine-relay path (1c) defers to us from now on

	local n = math.min(net.ReadUInt(4) or 0, CL_MAX_BATCH)
	for i = 1, n do
		local sig = string.sub(net.ReadString() or "", 1, 400)
		local delta = math.min(net.ReadUInt(16) or 0, 65535)
		local stack = string.sub(net.ReadString() or "", 1, 600)
		if sig ~= "" and delta > 0 then
			local key = "[client] " .. sig
			local allow = true
			if not K.errs[key] then
				-- per-player cap on NEW signatures (no GMod `continue`
				-- here on purpose - keeps the tested code identical)
				ply.zc_errlog_uniqueN = ply.zc_errlog_uniqueN or 0
				if ply.zc_errlog_uniqueN >= CL_MAX_UNIQUE then
					allow = false
				else
					ply.zc_errlog_uniqueN = ply.zc_errlog_uniqueN + 1
				end
			end
			if allow then
				record(key, "client/" .. ply:Nick(), stack, delta)
			end
		end
	end
end)

-- ------------------------------------------------------------
--  CAPTURE 1c: ENGINE-relayed client errors - GM:OnClientLuaError
--  (server realm; wiki: OnLuaError on the server "will only account
--  for server-side errors" - THIS is the hook for the client errors
--  that print in the server console). Needs no client file.
--  The engine drops anything past 5 errors/sec per client, so
--  counts here are FLOORS; the client relay (1b) carries true
--  counts for players running cl_zc_errlog. To avoid double
--  counting, a player whose client half has reported this map is
--  skipped here.
-- ------------------------------------------------------------
hook.Add("OnClientLuaError", "zc_errlog", function(err, ply, stack, name)
	if not (cv_on:GetBool() and cv_clients:GetBool()) then return end
	if IsValid(ply) and ply.zc_errlog_relayActive then return end
	local who = IsValid(ply) and ply:Nick() or "?"
	local s = formatStack(stack)
	if name and name ~= "" and name ~= "ERROR" then s = "    addon: " .. tostring(name) .. "\n" .. s end
	record("[client] " .. string.sub(tostring(err), 1, 400), "client/" .. who, s)
end)

-- ------------------------------------------------------------
--  CAPTURE 2: ErrorNoHalt detours (originals always called)
-- ------------------------------------------------------------
local function softRecord(prefix, args)
	if not (cv_on:GetBool() and cv_soft:GetBool()) then return end
	local parts = {}
	for i = 1, math.min(#args, 8) do parts[#parts + 1] = tostring(args[i]) end
	local msg = table.concat(parts, "")
	msg = string.gsub(msg, "\n+$", "")
	if msg == "" then return end
	record(msg, prefix, "    " .. string.gsub(debug.traceback("", 3), "\n", "\n    "))
end

local function installDetours()
	if not K.origENH then K.origENH = ErrorNoHalt end
	if K.myENH ~= ErrorNoHalt then
		K.myENH = function(...)
			softRecord("nohalt", { ... })
			return K.origENH(...)
		end
		ErrorNoHalt = K.myENH
	end
	if ErrorNoHaltWithStack then
		if not K.origENHS then K.origENHS = ErrorNoHaltWithStack end
		if K.myENHS ~= ErrorNoHaltWithStack then
			K.myENHS = function(...)
				softRecord("nohalt", { ... })
				return K.origENHS(...)
			end
			ErrorNoHaltWithStack = K.myENHS
		end
	end
end

local function removeDetours()
	if K.origENH and ErrorNoHalt == K.myENH then ErrorNoHalt = K.origENH end
	if K.origENHS and ErrorNoHaltWithStack == K.myENHS then ErrorNoHaltWithStack = K.origENHS end
	K.myENH, K.myENHS = nil, nil
end

-- ------------------------------------------------------------
--  FLUSH (all string building + IO lives here, every N seconds)
-- ------------------------------------------------------------
local function flush()
	if not cv_on:GetBool() then return end
	local out = {}

	for _, sig in ipairs(K.order) do
		local rec = K.errs[sig]
		if rec and rec.dirty then
			if rec.new then
				out[#out + 1] = ("[%s] NEW x%d [%s] map %s round %s\n%s\n%s")
					:format(stamp(), rec.count, rec.realm, rec.map, rec.round,
						rec.sig, rec.stack ~= "" and rec.stack or "    (no stack)")
				rec.new = false
			else
				out[#out + 1] = ("[%s] x%d more (total %d): %s")
					:format(stamp(), rec.count - rec.written, rec.count,
						string.sub(string.gsub(rec.sig, "\n.*", ""), 1, 200))
			end
			rec.written = rec.count
			rec.dirty = false
		end
	end

	if K.overflow > K.overflowWritten then
		out[#out + 1] = ("[%s] OVERFLOW: %d error(s) dropped (unique cap %d - zc_errlog_max)")
			:format(stamp(), K.overflow - (K.overflowWritten or 0), cv_max:GetInt())
		K.overflowWritten = K.overflow
	end

	if #out == 0 then return end
	ensureDir()
	local fn = logfile()
	if not file.Exists(fn, "DATA") then
		-- file.Append on a nonexistent file is unreliable across builds:
		-- create the day's file explicitly, with a header
		file.Write(fn, "=== zc_errlog " .. os.date("%Y-%m-%d") .. " - map " .. game.GetMap() .. " ===\n")
	end
	file.Append(fn, table.concat(out, "\n") .. "\n")
end
K.overflowWritten = K.overflowWritten or 0

timer.Create("zc_errlog_flush", 5, 0, function()
	-- new signatures land within 5s; counter updates respect cv_flush
	K.nextCounters = K.nextCounters or 0
	local doCounters = CurTime() >= K.nextCounters
	if doCounters then K.nextCounters = CurTime() + cv_flush:GetFloat() end

	local any = false
	for _, sig in ipairs(K.order) do
		local rec = K.errs[sig]
		if rec and rec.dirty and (rec.new or doCounters) then any = true break end
	end
	if any or (K.overflow > (K.overflowWritten or 0) and doCounters) then
		-- suppress non-new counter updates outside the counter window
		if not doCounters then
			for _, sig in ipairs(K.order) do
				local rec = K.errs[sig]
				if rec and rec.dirty and not rec.new then rec.dirty = false rec.pend = true end
			end
		end
		flush()
		if not doCounters then
			for _, sig in ipairs(K.order) do
				local rec = K.errs[sig]
				if rec and rec.pend then rec.dirty = true rec.pend = nil end
			end
		end
	end

	-- detour upkeep (gamemode reloads / other addons replacing globals)
	if cv_soft:GetBool() then installDetours() else removeDetours() end
end)

hook.Add("ShutDown", "zc_errlog", flush)

-- ------------------------------------------------------------
--  COMMANDS
-- ------------------------------------------------------------
concommand.Add("zc_errlog_stats", function(ply)
	if IsValid(ply) and not ply:IsAdmin() then return end
	local function say(s)
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, s) else print(s) end
	end
	local list = {}
	for _, sig in ipairs(K.order) do list[#list + 1] = K.errs[sig] end
	table.sort(list, function(a, b) return a.count > b.count end)
	say("=== zc_errlog (" .. (cv_on:GetBool() and "ACTIVE" or "OFF") .. ") -> data/" .. logfile() .. " ===")
	say(("unique: %d/%d  |  total seen: %d  |  dropped past cap: %d")
		:format(#K.order, cv_max:GetInt(), K.totalSeen, K.overflow))
	for i = 1, math.min(#list, 15) do
		local r = list[i]
		say(("%5dx [%s] %s"):format(r.count, r.realm,
			string.sub(string.gsub(r.sig, "\n.*", ""), 1, 160)))
	end
end)

concommand.Add("zc_errlog_dump", function(ply)
	if IsValid(ply) and not ply:IsAdmin() then return end
	for _, sig in ipairs(K.order) do
		local r = K.errs[sig]
		if r and r.count > r.written then r.dirty = true end
	end
	flush()
	print("[errlog] flushed to data/" .. logfile())
end)

concommand.Add("zc_errlog_clear", function(ply)
	if IsValid(ply) and not ply:IsAdmin() then return end
	K.errs, K.order, K.overflow, K.overflowWritten, K.totalSeen = {}, {}, 0, 0, 0
	print("[errlog] in-memory tracking cleared (log files untouched)")
end)

print("[errlog] loaded - Lua errors collect in data/" .. DIR .. "/ (test: lua_run error(\"zc_errlog test\"))")
