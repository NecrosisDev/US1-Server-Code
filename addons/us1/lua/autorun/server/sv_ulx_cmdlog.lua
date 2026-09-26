-- ULX Command Log (capture + storage layer)
-- Logs every ULX command by every rank - superadmins and CONSOLE included -
-- with rank snapshot, target resolution, self-target flag, and denied
-- attempts. Disk-backed SQLite (sv.db): flat RAM footprint regardless of
-- history size. 7-day retention + hard row cap.
--
-- Panel comes later; for now, verify data with:
--   ulxlog_recent [count]   (admin+ / console)
--   ulxlog_stats            (admin+ / console)
--
-- NOT captured (by design): lua_run, raw console cvars, Physgun panel
-- actions - only commands that route through ULX/ULib.
--
-- Folder must sort after "ulx"/"ulib" (ulx_cmdlog does) so wraps land
-- on top of their registrations.
if not SERVER then return end

local RETENTION_DAYS = 7
local MAX_ROWS       = 50000
local DEDUPE_WINDOW  = 0.2   -- seconds; console-wrap + ULib hook overlap

-- =========================================================================
-- DATABASE
-- =========================================================================
sql.Query([[CREATE TABLE IF NOT EXISTS ulx_cmdlog (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts INTEGER NOT NULL,
    sid TEXT NOT NULL,
    name TEXT NOT NULL,
    rank TEXT NOT NULL,
    cmd TEXT NOT NULL,
    target TEXT,
    target_sid TEXT,
    args TEXT,
    result TEXT NOT NULL,
    selftarget INTEGER NOT NULL DEFAULT 0
)]])
sql.Query("CREATE INDEX IF NOT EXISTS ulxlog_ts ON ulx_cmdlog (ts)")
sql.Query("CREATE INDEX IF NOT EXISTS ulxlog_sid ON ulx_cmdlog (sid)")
sql.Query("CREATE INDEX IF NOT EXISTS ulxlog_cmd ON ulx_cmdlog (cmd)")
sql.Query("CREATE INDEX IF NOT EXISTS ulxlog_rank ON ulx_cmdlog (rank)")

local function Cleanup()
    local cutoff = os.time() - RETENTION_DAYS * 86400
    sql.Query("DELETE FROM ulx_cmdlog WHERE ts < " .. cutoff)

    local n = tonumber(sql.QueryValue("SELECT COUNT(*) FROM ulx_cmdlog") or 0)
    if n > MAX_ROWS then
        sql.Query("DELETE FROM ulx_cmdlog WHERE id IN (SELECT id FROM ulx_cmdlog ORDER BY id ASC LIMIT "
            .. (n - MAX_ROWS) .. ")")
    end
end
Cleanup()
timer.Create("ULXLog_Cleanup", 21600, 0, Cleanup)  -- every 6h

-- =========================================================================
-- LOGGING CORE
-- =========================================================================
local lastLogged = {}  -- dedupe: "sid|cmd" -> CurTime

local function ResolveTarget(caller, raw)
    if not raw or raw == "" then return nil, nil, 0 end

    -- "^" is ULX self-target shorthand
    if raw == "^" and IsValid(caller) then
        return caller:Nick(), caller:SteamID(), 1
    end

    -- "$<uniqueid>" is ULib's internal targeting token
    local uid = string.match(raw, "^%$(%d+)$")
    if uid then
        for _, p in player.Iterator() do
            if tostring(p:UniqueID()) == uid then
                return p:Nick(), p:SteamID(),
                    (IsValid(caller) and p == caller) and 1 or 0
            end
        end
        return raw, nil, 0
    end

    local lower = string.lower(raw)

    -- direct SteamID
    if lower:match("^steam_%d:%d:%d+$") then
        for _, p in player.Iterator() do
            if string.lower(p:SteamID()) == lower then
                return p:Nick(), p:SteamID(),
                    (IsValid(caller) and p == caller) and 1 or 0
            end
        end
        return raw, string.upper(raw), 0
    end

    -- nick match: exact first, then unique substring
    local exact, sub, subCount = nil, nil, 0
    for _, p in player.Iterator() do
        local nick = string.lower(p:Nick())
        if nick == lower then exact = p break end
        if nick:find(lower, 1, true) then
            sub = p
            subCount = subCount + 1
        end
    end
    local found = exact or (subCount == 1 and sub or nil)
    if found then
        return found:Nick(), found:SteamID(),
            (IsValid(caller) and found == caller) and 1 or 0
    end

    return raw, nil, 0  -- unresolved (group targets, offline, multi-match)
end

local function LogCmd(ply, cmdName, args, result)
    if not cmdName or cmdName == "" then return end
    cmdName = string.lower(cmdName)

    local sid, name, rank
    if IsValid(ply) and ply:IsPlayer() then
        sid, name, rank = ply:SteamID(), ply:Nick(), ply:GetUserGroup()
    else
        sid, name, rank = "CONSOLE", "CONSOLE", "console"
    end

    -- dedupe (console wrap + ULib exec hook can both see one command)
    local dkey = sid .. "|" .. cmdName .. "|" .. result
    if (lastLogged[dkey] or 0) > CurTime() - DEDUPE_WINDOW then return end
    lastLogged[dkey] = CurTime()

    args = args or {}
    local targetRaw = args[2]  -- args[1] is the subcommand for console path
    -- for pre-split arg tables from chat/hook paths, args[1] IS the target
    if cmdName:sub(1, 4) == "ulx " and args.fromConsoleWrap then
        targetRaw = args[2]
    else
        targetRaw = args[1]
    end

    local tName, tSid, selfT = ResolveTarget(ply, targetRaw)

    local argStr = {}
    for i, a in ipairs(args) do argStr[#argStr + 1] = tostring(a) end
    argStr = table.concat(argStr, " ")

    sql.Query(string.format(
        "INSERT INTO ulx_cmdlog (ts, sid, name, rank, cmd, target, target_sid, args, result, selftarget) VALUES (%d, %s, %s, %s, %s, %s, %s, %s, %s, %d)",
        os.time(),
        sql.SQLStr(sid), sql.SQLStr(name), sql.SQLStr(rank),
        sql.SQLStr(cmdName),
        tName and sql.SQLStr(tName) or "NULL",
        tSid and sql.SQLStr(tSid) or "NULL",
        sql.SQLStr(argStr), sql.SQLStr(result), selfT
    ))
end

-- periodic dedupe-map trim so it can't grow unbounded
timer.Create("ULXLog_DedupeTrim", 300, 0, function()
    local now = CurTime()
    for k, t in pairs(lastLogged) do
        if t < now - 5 then lastLogged[k] = nil end
    end
end)

-- =========================================================================
-- CAPTURE POINT 1: executed commands (console AND chat paths)
-- ULib fires this after access is granted and the command runs
-- =========================================================================
hook.Add(ULib and ULib.HOOK_COMMAND_CALLED or "ULibCommandCalled", "ULXLog_Executed", function(ply, cmd, args)
    -- defensive: cmd may be a string or a command object depending on version
    local cmdName = isstring(cmd) and cmd or (istable(cmd) and cmd.cmd) or tostring(cmd)
    local argCopy = {}
    if istable(args) then
        for i, a in ipairs(args) do argCopy[i] = a end
    end
    -- some versions pass the bare root "ulx" with the subcommand in args
    if string.lower(cmdName) == "ulx" and isstring(argCopy[1]) then
        cmdName = "ulx " .. string.lower(argCopy[1])
        table.remove(argCopy, 1)
    end
    LogCmd(ply, cmdName, argCopy, "executed")
end)

-- =========================================================================
-- CAPTURE POINT 2: the "ulx" console command (catches DENIED console
-- attempts - verdict mirrored via the same ACL query ULX itself uses)
-- =========================================================================
local function WrapConsole()
    if ULXLog_ConsoleWrapped then return true end
    local orig = concommand.GetTable()["ulx"]
    if not orig then return false end

    ULXLog_ConsoleWrapped = true
    concommand.Add("ulx", function(ply, cmdStr, args, argFull)
        if istable(args) and args[1] then
            local full = "ulx " .. string.lower(args[1])
            local allowed = true
            if IsValid(ply) and ply:IsPlayer() then
                allowed = ULib.ucl.query(ply, full) and true or false
            end
            local copy = { fromConsoleWrap = true }
            for i, a in ipairs(args) do copy[i] = a end
            LogCmd(ply, full, copy, allowed and "executed" or "denied")
        end
        return orig(ply, cmdStr, args, argFull)
    end)
    return true
end

-- =========================================================================
-- CAPTURE POINT 3: chat commands (catches DENIED chat attempts)
-- Wraps ULib's own PlayerSay handler so suppressed/hidden chat commands
-- are still seen. Successes dedupe against capture point 1.
-- =========================================================================
local function ChatCheck(ply, text)
    if not IsValid(ply) or not istable(ULib and ULib.sayCmds) then return end

    local lowText = string.lower(text)
    for k, v in pairs(ULib.sayCmds) do
        local kl = string.lower(k)
        if lowText == string.Trim(kl) or lowText:sub(1, #kl) == kl then
            -- best-effort resolution of the underlying access string
            local cmdName
            if istable(v) then
                cmdName = (isstring(v.cmd) and v.cmd)
                    or (istable(v.__cmd) and isstring(v.__cmd.cmd) and v.__cmd.cmd)
            end
            cmdName = cmdName or ("say:" .. string.Trim(k))

            if cmdName:sub(1, 4) == "ulx " then
                local allowed = ULib.ucl.query(ply, cmdName) and true or false
                if not allowed then
                    local rest = string.Trim(text:sub(#kl + 1))
                    local args = {}
                    for w in rest:gmatch("%S+") do args[#args + 1] = w end
                    LogCmd(ply, cmdName, args, "denied")
                end
                -- allowed chat commands log via ULibCommandCalled
            end
            break
        end
    end
end

local function WrapSayHook()
    if ULXLog_SayWrapped then return true end
    local t = hook.GetTable()["PlayerSay"]
    if not t then return false end

    for name, fn in pairs(t) do
        if not tostring(name):find("ULXLog") then
            local info = debug.getinfo(fn, "S")
            if info and info.short_src and info.short_src:lower():find("ulib", 1, true) then
                ULXLog_SayWrapped = true
                hook.Add("PlayerSay", name, function(p, txt, teamChat)
                    local ok, err = pcall(ChatCheck, p, txt)
                    if not ok then print("[ULXLog] chat check error: " .. tostring(err)) end
                    return fn(p, txt, teamChat)
                end)
                return true
            end
        end
    end
    return false
end

hook.Add("InitPostEntity", "ULXLog_Wrap", function()
    timer.Simple(5, function()
        local c = WrapConsole()
        local s = WrapSayHook()
        print(string.format("[ULXLog] Active | console wrap: %s | say wrap: %s",
            c and "OK" or "MISSING (ulx concommand not found)",
            s and "OK" or "MISSING (ULib say hook not found)"))
    end)
end)

-- immediate wrap on hotload
if ULib then
    WrapConsole()
    WrapSayHook()
end

-- =========================================================================
-- VERIFICATION COMMANDS (panel comes later)
-- =========================================================================
local function CanView(ply)
    return not IsValid(ply) or ply:IsAdmin() or ply:IsSuperAdmin()
end

concommand.Add("ulxlog_recent", function(ply, _, args)
    if not CanView(ply) then return end
    local n = math.Clamp(tonumber(args and args[1]) or 20, 1, 100)

    local rows = sql.Query("SELECT ts, name, rank, cmd, target, args, result, selftarget FROM ulx_cmdlog ORDER BY id DESC LIMIT " .. n)
    if not rows then print("[ULXLog] No entries.") return end

    print(string.format("[ULXLog] Last %d entries (newest first):", #rows))
    for _, r in ipairs(rows) do
        print(string.format("%s  %-20s %-11s %-18s -> %-15s %s%s [%s]",
            os.date("%m-%d %H:%M:%S", tonumber(r.ts)),
            string.sub(r.name, 1, 20), r.rank, r.cmd,
            r.target or "-",
            r.args ~= "" and ("(" .. string.sub(r.args, 1, 30) .. ") ") or "",
            tonumber(r.selftarget) == 1 and "[SELF] " or "",
            r.result))
    end
end)

concommand.Add("ulxlog_stats", function(ply)
    if not CanView(ply) then return end
    local total  = sql.QueryValue("SELECT COUNT(*) FROM ulx_cmdlog") or 0
    local denied = sql.QueryValue("SELECT COUNT(*) FROM ulx_cmdlog WHERE result = 'denied'") or 0
    local oldest = tonumber(sql.QueryValue("SELECT MIN(ts) FROM ulx_cmdlog"))

    print(string.format("[ULXLog] %s rows | %s denied | oldest: %s",
        total, denied, oldest and os.date("%m-%d %H:%M", oldest) or "n/a"))

    local byCmd = sql.Query("SELECT cmd, COUNT(*) c FROM ulx_cmdlog GROUP BY cmd ORDER BY c DESC LIMIT 10")
    if byCmd then
        print("Top commands:")
        for _, r in ipairs(byCmd) do
            print(string.format("  %-20s %s", r.cmd, r.c))
        end
    end
end)

concommand.Add("ulxlog_export", function(ply, _, args)
    if not CanView(ply) then return end
    -- optional day filter: ulxlog_export 3 = last 3 days (default: all 7)
    local days = math.Clamp(tonumber(args and args[1]) or RETENTION_DAYS, 1, RETENTION_DAYS)
    local cutoff = os.time() - days * 86400

    local rows = sql.Query("SELECT ts, sid, name, rank, cmd, target, target_sid, args, result, selftarget FROM ulx_cmdlog WHERE ts >= " .. cutoff .. " ORDER BY id ASC")
    if not rows then print("[ULXLog] Nothing to export.") return end

    local out = {}
    out[#out + 1] = "ULX Command Log export - " .. os.date("%Y-%m-%d %H:%M:%S")
        .. " - last " .. days .. " day(s) - " .. #rows .. " entries"
    out[#out + 1] = string.rep("=", 100)

    for _, r in ipairs(rows) do
        out[#out + 1] = string.format("%s | %-11s | %s (%s) | %s -> %s%s | args: %s | %s%s",
            os.date("%Y-%m-%d %H:%M:%S", tonumber(r.ts)),
            r.rank, r.name, r.sid, r.cmd,
            r.target or "-",
            r.target_sid and (" (" .. r.target_sid .. ")") or "",
            r.args ~= "" and r.args or "-",
            r.result,
            tonumber(r.selftarget) == 1 and " [SELF]" or "")
    end

    file.Write("ulxlog_export.txt", table.concat(out, "\n"))
    print("[ULXLog] Exported " .. #rows .. " entries to data/ulxlog_export.txt")
end)

print("[ULXLog] Loaded - capture layer (panel pending). ulxlog_recent / ulxlog_stats / ulxlog_export")
