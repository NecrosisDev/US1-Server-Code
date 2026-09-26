-- Punishment History (permanent record)
-- Answers "has this player been punished before?" - permanent per-SteamID
-- log of bans, kicks, gags, mutes, slays with staff attribution.
--
-- Sources:
--   1. ULibPlayerBanned hook  -> ALL bans regardless of origin: ulx ban/banid,
--      the disconnects menu, XGUI, and automatic guilt/karma bans
--   2. ULibCommandCalled hook -> kicks, gags, mutes, tgag/tmute, slays, unbans
--   3. One-time backfill from ULib's existing ban storage (history predating
--      this addon)
--
-- Storage: SQLite (sv.db), table punish_history, NO expiry (permanent,
-- rows are tiny). Flat RAM footprint.
--
-- Lookup (operator and above):
--   punish_history <steamid or name>   (console)
--   !history <steamid or name>         (chat)
--
-- Lives alongside ulx_cmdlog (same addon folder) but fully independent.
if not SERVER then return end

-- =========================================================================
-- DATABASE
-- =========================================================================
sql.Query([[CREATE TABLE IF NOT EXISTS punish_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts INTEGER NOT NULL,
    sid TEXT NOT NULL,
    name TEXT,
    ptype TEXT NOT NULL,
    duration INTEGER NOT NULL DEFAULT 0,
    reason TEXT,
    staff_sid TEXT,
    staff_name TEXT,
    staff_rank TEXT,
    source TEXT NOT NULL
)]])
sql.Query("CREATE INDEX IF NOT EXISTS ph_sid ON punish_history (sid)")
sql.Query("CREATE INDEX IF NOT EXISTS ph_ts ON punish_history (ts)")

local function Insert(row)
    sql.Query(string.format(
        "INSERT INTO punish_history (ts, sid, name, ptype, duration, reason, staff_sid, staff_name, staff_rank, source) VALUES (%d, %s, %s, %s, %d, %s, %s, %s, %s, %s)",
        row.ts or os.time(),
        sql.SQLStr(row.sid or "?"),
        row.name and sql.SQLStr(row.name) or "NULL",
        sql.SQLStr(row.ptype),
        tonumber(row.duration) or 0,
        row.reason and sql.SQLStr(row.reason) or "NULL",
        row.staff_sid and sql.SQLStr(row.staff_sid) or "NULL",
        row.staff_name and sql.SQLStr(row.staff_name) or "NULL",
        row.staff_rank and sql.SQLStr(row.staff_rank) or "NULL",
        sql.SQLStr(row.source)
    ))
end

-- =========================================================================
-- ZC WATCHDOG LINK: if a punished player was flagged by the anticheat in the
-- last WD_WINDOW seconds, tag the source "<origin>|wd:<module>" so the
-- Punishments tab (and console lookup) show which punishments line up with an
-- anticheat detection. No-op if the watchdog_log table isn't present.
-- =========================================================================
local WD_WINDOW = 1800  -- 30 min
local function recentWatchdog(sid)
    if not isstring(sid) or not sql.TableExists("watchdog_log") then return nil end
    local m = sql.QueryValue(
        "SELECT module FROM watchdog_log WHERE sid = " .. sql.SQLStr(sid) ..
        " AND ts >= " .. (os.time() - WD_WINDOW) .. " ORDER BY id DESC LIMIT 1")
    return (m and m ~= "" and m) or nil
end

local function tagSource(origin, sid)
    local wd = recentWatchdog(sid)
    return wd and (origin .. "|wd:" .. wd) or origin
end

-- =========================================================================
-- SOURCE 1: every ban through ULib (commands, menus, guilt auto-bans)
-- =========================================================================
local recentBans = {}  -- sid -> CurTime, dedupe vs command capture

local function OnBanned(steamid, banData)
    if not isstring(steamid) then return end
    banData = istable(banData) and banData or {}

    recentBans[steamid] = CurTime()

    -- admin field is usually "Nick(STEAM_0:...)" or "(Console)"
    local staffName, staffSid
    local adminStr = tostring(banData.admin or "")
    staffName, staffSid = string.match(adminStr, "^(.-)%((STEAM_%d:%d:%d+)%)$")
    staffName = staffName or (adminStr ~= "" and adminStr) or "SYSTEM"

    local duration = 0
    local unban = tonumber(banData.unban)
    local btime = tonumber(banData.time)
    if unban and unban > 0 and btime then
        duration = math.Round((unban - btime) / 60)
    end

    Insert({
        ts = btime or os.time(),
        sid = steamid,
        name = banData.name,
        ptype = "ban",
        duration = duration,   -- 0 = permanent
        reason = banData.reason,
        staff_sid = staffSid,
        staff_name = staffName,
        staff_rank = staffSid and (ULib.ucl.users[staffSid] and ULib.ucl.users[staffSid].group) or nil,
        source = tagSource("banhook", steamid),
    })
end

hook.Add("ULibPlayerBanned", "PunishHist_Ban", OnBanned)
-- some ULib versions use this name instead; duplicate registration is harmless
-- (dedupe below), missing hook is silently ignored
hook.Add("ULibBanned", "PunishHist_Ban2", OnBanned)

-- =========================================================================
-- SOURCE 2: punishment-class ULX commands
-- =========================================================================
local CAPTURE = {
    ["ulx kick"]   = { ptype = "kick" },
    ["ulx gag"]    = { ptype = "gag" },
    ["ulx mute"]   = { ptype = "mute" },
    ["ulx tgag"]   = { ptype = "tgag",  durArg = 2 },
    ["ulx tmute"]  = { ptype = "tmute", durArg = 2 },
    ["ulx slay"]   = { ptype = "slay" },
    ["ulx sslay"]  = { ptype = "slay" },
    ["ulx unban"]  = { ptype = "unban" },
}

local function ResolveOffender(raw)
    if not isstring(raw) or raw == "" then return "?", nil end

    local uid = string.match(raw, "^%$(%d+)$")
    if uid then
        for _, p in player.Iterator() do
            if tostring(p:UniqueID()) == uid then return p:SteamID(), p:Nick() end
        end
        return raw, nil
    end

    local lower = string.lower(raw)

    if lower:match("^steam_%d:%d:%d+$") then
        for _, p in player.Iterator() do
            if string.lower(p:SteamID()) == lower then return p:SteamID(), p:Nick() end
        end
        return string.upper(raw), nil
    end

    local exact, sub, subCount = nil, nil, 0
    for _, p in player.Iterator() do
        local nick = string.lower(p:Nick())
        if nick == lower then exact = p break end
        if nick:find(lower, 1, true) then sub = p subCount = subCount + 1 end
    end
    local found = exact or (subCount == 1 and sub or nil)
    if found then return found:SteamID(), found:Nick() end
    return raw, nil  -- unresolved: store the raw target string
end

hook.Add(ULib and ULib.HOOK_COMMAND_CALLED or "ULibCommandCalled", "PunishHist_Cmd", function(ply, cmd, args)
    local cmdName = string.lower(isstring(cmd) and cmd or (istable(cmd) and cmd.cmd) or tostring(cmd))
    local cap = CAPTURE[cmdName]
    if not cap then return end

    args = istable(args) and args or {}
    local sid, name = ResolveOffender(args[1])

    -- bans are recorded by the ban hook with better data; skip if one just fired
    if (recentBans[sid] or 0) > CurTime() - 2 then return end

    local staffSid, staffName, staffRank
    if IsValid(ply) and ply:IsPlayer() then
        staffSid, staffName, staffRank = ply:SteamID(), ply:Nick(), ply:GetUserGroup()
    else
        staffSid, staffName, staffRank = "CONSOLE", "CONSOLE", "console"
    end

    local duration = 0
    if cap.durArg then duration = tonumber(args[cap.durArg]) or 0 end

    -- reason = everything after the known args
    local reasonStart = (cap.durArg or 1) + 1
    local reasonParts = {}
    for i = reasonStart, #args do reasonParts[#reasonParts + 1] = tostring(args[i]) end

    Insert({
        sid = sid,
        name = name,
        ptype = cap.ptype,
        duration = duration,
        reason = #reasonParts > 0 and table.concat(reasonParts, " ") or nil,
        staff_sid = staffSid,
        staff_name = staffName,
        staff_rank = staffRank,
        source = tagSource("command", sid),
    })
end)

timer.Create("PunishHist_DedupeTrim", 300, 0, function()
    local now = CurTime()
    for k, t in pairs(recentBans) do
        if t < now - 10 then recentBans[k] = nil end
    end
end)

-- =========================================================================
-- SOURCE 3: one-time backfill from ULib's existing ban table
-- =========================================================================
local function Backfill()
    local done = sql.QueryValue("SELECT COUNT(*) FROM punish_history WHERE source = 'backfill'")
    if tonumber(done or 0) > 0 then return end
    if not (ULib and istable(ULib.bans)) then return end

    local n = 0
    for steamid, ban in pairs(ULib.bans) do
        if isstring(steamid) and istable(ban) then
            local staffName, staffSid
            local adminStr = tostring(ban.admin or "")
            staffName, staffSid = string.match(adminStr, "^(.-)%((STEAM_%d:%d:%d+)%)$")
            staffName = staffName or (adminStr ~= "" and adminStr) or "SYSTEM"

            local duration = 0
            local unban, btime = tonumber(ban.unban), tonumber(ban.time)
            if unban and unban > 0 and btime then
                duration = math.Round((unban - btime) / 60)
            end

            Insert({
                ts = btime or os.time(),
                sid = steamid,
                name = ban.name,
                ptype = "ban",
                duration = duration,
                reason = ban.reason,
                staff_sid = staffSid,
                staff_name = staffName,
                source = "backfill",
            })
            n = n + 1
        end
    end
    if n > 0 then print("[PunishHist] Backfilled " .. n .. " existing bans from ULib") end
end

hook.Add("InitPostEntity", "PunishHist_Backfill", function()
    timer.Simple(10, Backfill)
end)

-- =========================================================================
-- LOOKUP
-- =========================================================================
local function CanView(ply)
    if not IsValid(ply) then return true end
    return ply:IsAdmin() or ply:IsSuperAdmin() or (ULib and ULib.ucl.query(ply, "ulx kick")) or false
end

local function FormatDuration(mins)
    mins = tonumber(mins) or 0
    if mins <= 0 then return "perma/na" end
    if mins < 60 then return mins .. "m" end
    if mins < 1440 then return math.Round(mins / 60, 1) .. "h" end
    return math.Round(mins / 1440, 1) .. "d"
end

local function RunLookup(target, printFn)
    target = string.Trim(target or "")
    if target == "" then printFn("Usage: punish_history <steamid or name>") return end

    -- resolve to a sid if possible, else search raw
    local sid = ResolveOffender(target)
    local key = sql.SQLStr(sid)
    local rawKey = sql.SQLStr("%" .. target .. "%")

    local rows = sql.Query(
        "SELECT * FROM punish_history WHERE sid = " .. key ..
        " OR sid LIKE " .. rawKey .. " OR name LIKE " .. rawKey ..
        " ORDER BY ts DESC LIMIT 200")

    if not rows then
        printFn("No punishment history found for: " .. target)
        return
    end

    -- summary counts
    local counts, total = {}, 0
    local newest, oldest = 0, math.huge
    for _, r in ipairs(rows) do
        counts[r.ptype] = (counts[r.ptype] or 0) + 1
        total = total + 1
        local t = tonumber(r.ts) or 0
        if t > newest then newest = t end
        if t < oldest then oldest = t end
    end

    local parts = {}
    for ptype, n in SortedPairs(counts) do parts[#parts + 1] = n .. " " .. ptype end

    printFn("===== Punishment history: " .. target .. " (" .. (rows[1].sid or "?") .. ") =====")
    printFn(total .. " total: " .. table.concat(parts, ", "))
    printFn("First: " .. os.date("%Y-%m-%d", oldest) .. " | Most recent: " .. os.date("%Y-%m-%d %H:%M", newest))

    printFn("Last " .. math.min(10, #rows) .. " entries:")
    for i = 1, math.min(10, #rows) do
        local r = rows[i]
        local ac = r.source and string.match(r.source, "|wd:(%w+)")
        printFn(string.format("  %s  %-6s %-9s by %s%s%s%s",
            os.date("%m-%d %H:%M", tonumber(r.ts)),
            r.ptype,
            FormatDuration(r.duration),
            r.staff_name or "?",
            (r.staff_rank and r.staff_rank ~= "" and r.staff_rank ~= "NULL") and (" [" .. r.staff_rank .. "]") or "",
            ac and (" [AC:" .. ac .. "]") or "",
            (r.reason and r.reason ~= "" and r.reason ~= "NULL") and (" - " .. string.sub(r.reason, 1, 50)) or ""))
    end
end

concommand.Add("punish_history", function(ply, _, args)
    if not CanView(ply) then return end
    local target = table.concat(args or {}, " ")
    RunLookup(target, function(line)
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
    end)
end, nil, "Staff: print a player's permanent punishment history: punish_history <name|SteamID>.")

-- chat command: !history <target>
hook.Add("HG_PlayerSay", "PunishHist_Chat", function(ply, text, rawtext)
    if istable(text) then text = text[1] or rawtext end
    if not IsValid(ply) or not isstring(text) then return end
    local target = string.match(text, "^!history%s+(.+)$")
    if not target then return end
    if not CanView(ply) then return end

    RunLookup(target, function(line) ply:ChatPrint(line) end)
end)

print("[PunishHist] Loaded - permanent punishment record. punish_history / !history")
