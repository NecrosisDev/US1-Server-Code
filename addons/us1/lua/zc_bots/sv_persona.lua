-- WS-E1: a persistent per-bot-NAME identity ("persona") so a bot looks like
-- a regular who has been on the server for a while, instead of presenting a
-- brand new, freshly-rolled connection every single time it spawns.
--
-- Storage: data/zc_bots/personas.json, same file.Read/file.Write + JSON
-- convention sv_navgen.lua already uses for its own state file (verified
-- there: file.CreateDir("zc_bots"); file.Write(STATE_FILE,
-- util.TableToJSON(tbl, true))). Loaded once at file run; a missing or
-- corrupt file yields an empty table rather than erroring the whole load
-- chain (the loader runs every file under xpcall and would just count this
-- one as failed otherwise). The in-memory table is cached on
-- hg.botdriver.personaRecords (same "X = X or {}" survive-a-hot-reload
-- contract sv_personality.lua's personalityByName and sv_identity.lua's
-- appearanceByName already use) so a Lua autorefresh mid-session never
-- throws away up to a minute of not-yet-saved playtime.
--
-- Schema per name: { firstSeen, playtime, karma, steam64, sessions }, plus
-- one bookkeeping field the brief's schema list didn't include: `lastSeen`
-- (unix time, refreshed every time the name is applied to a connected bot).
-- ADDITION, logged rather than silently made: "bounded to 400 names, drop
-- least-recently-seen" needs a recency signal to evict by, and `firstSeen`
-- would evict by oldest-first-ever-seen instead -- the opposite of what
-- "least-recently-seen" means.
--
-- KARMA DRIFT (explicit assumption): this fork's real karma-award rules
-- (what a kill/heal/etc. actually does to Karma) are not known in this
-- package -- nothing here simulates drift. karma is rolled once when a
-- name's record is first created and then republished unchanged every
-- session for that name until the owner wires real rules in.
--
-- STEAM64 ARITHMETIC: steam64 = 76561197960265728 + accountID, accountID a
-- random integer in [2200000000, 2400000000] (an unassigned Steam account-ID
-- range -- 76561197960265728 is the id64 base for accountID 0, so this never
-- produces a real profile). 76561197960265728 is ~7.656e16, already past the
-- 2^53 (~9.007e15) integer-precision ceiling for a Lua double, so it is never
-- summed directly. It is split into a 7-digit high part "7656119" and a
-- 10-digit low part "7960265728" (each comfortably exact as a double);
-- accountID (< 2.4e9) is added to the low part with a manual carry into the
-- high part, then formatted back with string.format("%d%010d").
--
-- BEHAVIOR CHOICE, logged: the brief's own self-test description said to
-- assert the composed id64 "starts with 7656119" -- but every accountID in
-- the brief's own roll range (2.2e9-2.4e9) is already bigger than
-- (1e10 - 7960265728) = 2039734272, so BASE_LOW + accountID always carries
-- and the true prefix is "7656120" for the entire roll range (independently
-- verified: 76561197960265728 + 2200000000 = 76561200160265728, and
-- + 2400000000 = 76561200360265728). A self-test that asserted the literal
-- "7656119" prefix would fail on every single boot, which defeats the point
-- of a regression guard -- this file's self-test instead pins three golden
-- sums (low end, high end, and the middle of the roll range) against the
-- carry-corrected "7656120" prefix and logs via hg.botdriver.log.error
-- (never error()/assert()) so a real regression is reported without ever
-- taking the load chain down.
--
-- accountID itself is NOT drawn with a single math.random(2200000000,
-- 2400000000) call: GMod's math.random binding is a closed-source native,
-- and neither the public wiki nor Facepunch's own Lua-side extensions say
-- whether its C++ implementation carries m/n as a 32-bit int internally
-- (checked this session; unresolved either way). 2.2-2.4 billion is already
-- past 2^31-1 (~2.147e9), so this stays on the safe side of that unknown by
-- only ever passing math.random arguments under a few hundred million and
-- offsetting the result in Lua instead.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}
hg.botdriver.persona = hg.botdriver.persona or {}

local persona = hg.botdriver.persona
local log = hg.botdriver.log

local STATE_FILE = "zc_bots/personas.json"
local MAX_NAMES = 400
local PUBLISH_INTERVAL = 15
local SAVE_INTERVAL = 60

----------------------------------------------------------------------
-- Steam64 builder + self-test
----------------------------------------------------------------------

local BASE_HIGH = 7656119
local BASE_LOW = 7960265728 -- low 10 digits of 76561197960265728
local LOW_WIDTH = 10000000000 -- 1e10, the width of the 10-digit low field

local function rollAccountID()
	-- Kept well under 2^31-1 for the native math.random call itself; see the
	-- header note on why 2200000000-2400000000 is never passed directly.
	return 2200000000 + math.random(0, 200000000)
end

local function buildSteamID64(accountID)
	accountID = math.floor(accountID)
	local low = BASE_LOW + accountID
	local carry = 0
	if low >= LOW_WIDTH then
		low = low - LOW_WIDTH
		carry = 1
	end
	return string.format("%d%010d", BASE_HIGH + carry, low)
end

local function steamIDSelfTest()
	-- Golden values independently re-derived (not read back from
	-- buildSteamID64 itself) for the low end, high end and middle of the
	-- accountID roll range. See the header for why "7656120", not the
	-- brief's literal "7656119", is the correct prefix here.
	local cases = {
		{ accountID = 2200000000, expect = "76561200160265728" },
		{ accountID = 2300000000, expect = "76561200260265728" },
		{ accountID = 2400000000, expect = "76561200360265728" },
	}
	local ok = true
	for _, case in ipairs(cases) do
		local got = buildSteamID64(case.accountID)
		if got ~= case.expect or #got ~= 17 or string.sub(got, 1, 7) ~= "7656120" then
			ok = false
			local msg = string.format(
				"steam64 self-test FAILED for accountID=%d: got %s expected %s (want 17 digits, prefix 7656120)",
				case.accountID, tostring(got), case.expect)
			if log and log.error then log.error("persona", msg) else ErrorNoHalt("[zc_bots:persona] " .. msg .. "\n") end
		end
	end
	return ok
end

steamIDSelfTest()

----------------------------------------------------------------------
-- Persisted store
----------------------------------------------------------------------

local function loadState()
	local raw = file.Read(STATE_FILE, "DATA")
	local tbl = raw and util.JSONToTable(raw, false, true) -- names stay string keys
	if not istable(tbl) then return {} end
	for name, record in pairs(tbl) do
		if not istable(record) then tbl[name] = nil end
	end
	return tbl
end

-- Survives a Lua autorefresh re-run of this file (same contract as
-- personalityByName/appearanceByName): only the very first run this map
-- reads from disk, every later re-run keeps whatever is already in memory.
hg.botdriver.personaRecords = hg.botdriver.personaRecords or loadState()
local records = hg.botdriver.personaRecords
local dirty = false

local function rollKarma()
	local roll = math.random()
	if roll < 0.55 then
		return math.random(110, 120)
	elseif roll < 0.85 then
		return math.random(90, 110)
	end
	return math.random(60, 90)
end

local function touch(record)
	record.lastSeen = os.time()
end

local function pruneOldest()
	local count = 0
	for _ in pairs(records) do count = count + 1 end
	if count <= MAX_NAMES then return end
	local names = {}
	for name in pairs(records) do names[#names + 1] = name end
	table.sort(names, function(a, b)
		return (records[a].lastSeen or 0) < (records[b].lastSeen or 0)
	end)
	for i = 1, count - MAX_NAMES do
		records[names[i]] = nil
	end
end

local function getOrCreate(name)
	local record = records[name]
	if not record then
		record = {
			firstSeen = os.time(),
			playtime = 0,
			karma = rollKarma(),
			steam64 = buildSteamID64(rollAccountID()),
			sessions = 0,
		}
		records[name] = record
		dirty = true
	end
	return record
end

local function saveState()
	file.CreateDir("zc_bots")
	file.Write(STATE_FILE, util.TableToJSON(records, true))
	dirty = false
end

local function resolveName(nameOrBot)
	if isstring(nameOrBot) then return nameOrBot end
	if IsValid(nameOrBot) and nameOrBot.Nick then return nameOrBot:Nick() end
	return nil
end

function persona.Get(nameOrBot)
	local name = resolveName(nameOrBot)
	if not name then return nil end
	return getOrCreate(name)
end

function persona.SteamID64(bot)
	if not IsValid(bot) then return nil end
	local name = bot.zcPersonaName or resolveName(bot)
	if not name then return nil end
	return getOrCreate(name).steam64
end

----------------------------------------------------------------------
-- Publish (immediate on apply + every 15s while connected)
----------------------------------------------------------------------

-- 2026-09-25: this used bot:TimeConnected(), which is always 0 for bots
-- (GMod wiki), so no persona ever accumulated playtime (live personas.json:
-- "playtime": 0 for every name). The session clock is now this file's own
-- CurTime mark, set when the persona is applied and advanced on each flush.
local function liveSessionSeconds(bot)
	local mark = bot.zcPersonaSessionMark
	if not mark then return 0 end
	return math.max(0, CurTime() - mark)
end

local function publishPersona(bot, record)
	if not IsValid(bot) then return end
	bot:SetNWInt("ZCStore_TotalPlaytime", math.floor((record.playtime or 0) + liveSessionSeconds(bot)))
	bot:SetNWInt("ZCStore_PlaytimeSyncUnix", os.time())
	if isfunction(bot.SetNetVar) then
		bot:SetNetVar("Karma", record.karma)
	end
	bot:SetNWString("zcSteamID64", record.steam64)
end

-- Folds the live session's bot:TimeConnected() delta into the persisted
-- record and advances the baseline, so the next liveSessionSeconds() call
-- starts small again (this is what keeps the periodic publish's
-- "record.playtime + sessionSeconds" from ever double-counting the same
-- span of connected time).
local function flushSession(bot, record)
	local delta = liveSessionSeconds(bot)
	if delta > 0 then
		record.playtime = (record.playtime or 0) + delta
		bot.zcPersonaSessionMark = CurTime()
		dirty = true
	end
end

local function applyPersona(bot)
	if not IsValid(bot) or bot.zcPersonaApplied then return end
	local name = bot.Nick and bot:Nick() or nil
	if not name then return end
	local record = getOrCreate(name)
	bot.zcPersonaApplied = true
	bot.zcPersonaName = name
	bot.zcPersonaSessionMark = CurTime()
	record.sessions = (record.sessions or 0) + 1
	touch(record)
	pruneOldest()
	dirty = true
	publishPersona(bot, record)
end

hook.Add("PlayerSpawn", "zc_bots_persona_apply", function(bot)
	if not hg.botdriver.Enabled() then return end
	if not IsValid(bot) or not bot:IsBot() or not bot.zcBot then return end
	applyPersona(bot)
end)

hook.Add("PlayerDisconnected", "zc_bots_persona_disconnect", function(bot)
	if not IsValid(bot) or not bot:IsBot() or not bot.zcBot then return end
	if not bot.zcPersonaApplied or not bot.zcPersonaName then return end
	local record = records[bot.zcPersonaName]
	if not record then return end
	flushSession(bot, record)
	touch(record)
	saveState()
end)

hg.botdriver.Every("persona_publish", PUBLISH_INTERVAL, function()
	if not hg.botdriver.Enabled() then return end
	for bot in pairs(hg.botdriver.brains) do
		if IsValid(bot) and bot:IsBot() and bot.zcBot and bot.zcPersonaApplied and bot.zcPersonaName then
			local record = records[bot.zcPersonaName]
			if record then publishPersona(bot, record) end
		end
	end
end)

hg.botdriver.Every("persona_save", SAVE_INTERVAL, function()
	for bot in pairs(hg.botdriver.brains) do
		if IsValid(bot) and bot:IsBot() and bot.zcBot and bot.zcPersonaApplied and bot.zcPersonaName then
			local record = records[bot.zcPersonaName]
			if record then flushSession(bot, record) end
		end
	end
	if dirty then saveState() end
end)

----------------------------------------------------------------------
-- Admin: zc_bots_persona_dump (superadmin/console only, same permission
-- check as sv_fill.lua's zc_bots_list/zc_bots_add).
----------------------------------------------------------------------

local function personaAllowed(ply)
	return not IsValid(ply) or ply:IsSuperAdmin()
end

local function personaReply(ply, msg)
	if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end
end

concommand.Add("zc_bots_persona_dump", function(ply)
	if not personaAllowed(ply) then return end
	local names = {}
	for name in pairs(records) do names[#names + 1] = name end
	table.sort(names)
	for _, name in ipairs(names) do
		local record = records[name]
		personaReply(ply, string.format(
			"[zc_bots persona] %-24s karma=%-3d steam64=%s playtime=%ds sessions=%d firstSeen=%s",
			name, record.karma or 0, record.steam64 or "?", math.floor(record.playtime or 0),
			record.sessions or 0, os.date("%Y-%m-%d %H:%M:%S", record.firstSeen or os.time())))
	end
	personaReply(ply, string.format("[zc_bots persona] %d record(s) total", #names))
end, nil, "Superadmin: print every bot persona record.")
