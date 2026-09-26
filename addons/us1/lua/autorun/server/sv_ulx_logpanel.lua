-- ULX Log Panel - server query layer
-- Serves the in-game GUI (cl_ulx_logpanel.lua): filtered/grouped queries
-- against ulx_cmdlog and punish_history, paginated, admin+ only.
-- Panel opens are themselves logged (audit the auditors).
if not SERVER then return end

util.AddNetworkString("ULXLogPanel_Query")
util.AddNetworkString("ULXLogPanel_Data")
util.AddNetworkString("ULXLogPanel_Delete")

local PAGE_SIZE = 50

local function CanUse(ply)
    if not IsValid(ply) then return false end
    if ply:IsAdmin() or ply:IsSuperAdmin() then return true end
    -- operators and above: same litmus permission as the staff toolkit
    return ULib and ULib.ucl.query(ply, "ulx kick") or false
end

-- log panel activity into the cmdlog itself
local function LogPanelUse(ply, what)
    sql.Query(string.format(
        "INSERT INTO ulx_cmdlog (ts, sid, name, rank, cmd, target, target_sid, args, result, selftarget) VALUES (%d, %s, %s, %s, %s, NULL, NULL, %s, 'executed', 0)",
        os.time(), sql.SQLStr(ply:SteamID()), sql.SQLStr(ply:Nick()),
        sql.SQLStr(ply:GetUserGroup()), sql.SQLStr("panel:" .. what), sql.SQLStr("")))
end

-- ---------------------------------------------------------------------
-- rank visibility: each viewer sees only rows from ranks at or below
-- their own. Inheritance-aware, so custom groups slot in by what they
-- inherit. Console rows are superadmin-only. Enforced server-side.
-- ---------------------------------------------------------------------
local function RankLevel(group)
    local seen = {}
    while group and not seen[group] do
        if group == "superadmin" then return 4 end
        if group == "admin" then return 3 end
        if group == "operator" then return 2 end
        seen[group] = true
        group = ULib and ULib.ucl.groups[group] and ULib.ucl.groups[group].inherit_from
    end
    return 1
end

local function ViewerLevel(ply)
    if ply:IsSuperAdmin() then return 4 end
    return RankLevel(ply:GetUserGroup())
end

-- SQL fragment excluding ranks above the viewer (nil = no filter needed)
local function RankVisibilitySQL(ply, column)
    local lvl = ViewerLevel(ply)
    if lvl >= 4 then return nil end

    local hidden = { "'console'" }
    if ULib then
        for gname in pairs(ULib.ucl.groups) do
            if RankLevel(gname) > lvl then
                hidden[#hidden + 1] = sql.SQLStr(gname)
            end
        end
    end
    if lvl < 4 then hidden[#hidden + 1] = "'superadmin'" end
    if lvl < 3 then hidden[#hidden + 1] = "'admin'" end

    return "(" .. column .. " IS NULL OR " .. column .. " NOT IN (" ..
        table.concat(hidden, ",") .. "))"
end

-- ---------------------------------------------------------------------
-- query builders (every user string through SQLStr; columns whitelisted)
-- ---------------------------------------------------------------------
local GROUP_COLS = {
    rank = "rank", person = "name", cmd = "cmd",
    target = "target", result = "result",
    hour = "strftime('%H', ts, 'unixepoch', 'localtime')",
}

local function BuildWhere(f, viewer)
    local w = { "ts >= " .. (os.time() - math.Clamp(tonumber(f.days) or 7, 1, 7) * 86400) }

    local vis = IsValid(viewer) and RankVisibilitySQL(viewer, "rank")
    if vis then w[#w + 1] = vis end

    if isstring(f.rank) and f.rank ~= "" then
        w[#w + 1] = "rank = " .. sql.SQLStr(f.rank)
    end
    if isstring(f.result) and f.result ~= "" then
        w[#w + 1] = "result = " .. sql.SQLStr(f.result)
    end
    if f.selftarget then
        w[#w + 1] = "selftarget = 1"
    end
    if isstring(f.search) and f.search ~= "" then
        local s = sql.SQLStr("%" .. f.search .. "%")
        w[#w + 1] = "(name LIKE " .. s .. " OR sid LIKE " .. s ..
            " OR cmd LIKE " .. s .. " OR target LIKE " .. s ..
            " OR target_sid LIKE " .. s .. " OR args LIKE " .. s .. ")"
    end
    return table.concat(w, " AND ")
end

local function QueryLog(f, viewer)
    local where = BuildWhere(f, viewer)
    local group = GROUP_COLS[f.group or ""]

    if group then
        local rows = sql.Query(
            "SELECT " .. group .. " AS g, COUNT(*) AS c, SUM(CASE WHEN result='denied' THEN 1 ELSE 0 END) AS denied" ..
            " FROM ulx_cmdlog WHERE " .. where ..
            " GROUP BY g ORDER BY c DESC LIMIT 150")
        return { mode = "group", rows = rows or {} }
    end

    local page = math.max(tonumber(f.page) or 0, 0)
    local rows = sql.Query(
        "SELECT id, ts, sid, name, rank, cmd, target, target_sid, args, result, selftarget" ..
        " FROM ulx_cmdlog WHERE " .. where ..
        " ORDER BY id DESC LIMIT " .. (PAGE_SIZE + 1) .. " OFFSET " .. (page * PAGE_SIZE))
    rows = rows or {}

    local more = #rows > PAGE_SIZE
    if more then rows[PAGE_SIZE + 1] = nil end
    return { mode = "rows", rows = rows, page = page, more = more }
end

local function QueryPunish(f, viewer)
    local target = isstring(f.search) and string.Trim(f.search) or ""
    local vis = IsValid(viewer) and RankVisibilitySQL(viewer, "staff_rank")

    local where
    if target == "" then
        -- no search: recent punishments for players CURRENTLY ON the server
        local sids = {}
        for _, p in player.Iterator() do
            sids[#sids + 1] = sql.SQLStr(p:SteamID())
        end
        if #sids == 0 then
            return { mode = "punish", rows = {}, summary = {} }
        end
        where = "sid IN (" .. table.concat(sids, ",") .. ")"
    else
        local s = sql.SQLStr("%" .. target .. "%")
        where = "(sid LIKE " .. s .. " OR name LIKE " .. s .. ")"
    end

    local rows = sql.Query(
        "SELECT id, ts, sid, name, ptype, duration, reason, staff_name, staff_rank, source" ..
        " FROM punish_history WHERE ptype != 'slay' AND " .. where ..
        (vis and (" AND " .. vis) or "") ..
        " ORDER BY ts DESC LIMIT 100")
    rows = rows or {}

    local counts = {}
    for _, r in ipairs(rows) do
        counts[r.ptype] = (counts[r.ptype] or 0) + 1
    end
    return { mode = "punish", rows = rows, summary = counts }
end

local function QueryDamage(f)
    local days = math.Clamp(tonumber(f.days) or 3, 1, 3)
    local cutoff = os.time() - days * 86400
    local search = isstring(f.search) and string.Trim(f.search) or ""
    local dir = isstring(f.dir) and f.dir or ""

    local where, focusSid
    if search == "" then
        where = "ts >= " .. cutoff
    else
        -- resolve to a sid when an online player matches, else raw search
        local lower = string.lower(search)
        for _, p in player.Iterator() do
            if string.lower(p:SteamID()) == lower or string.lower(p:Nick()):find(lower, 1, true) then
                focusSid = p:SteamID()
                break
            end
        end
        if not focusSid and search:upper():match("^STEAM_%d:%d:%d+$") then
            focusSid = search:upper()
        end

        if focusSid then
            local s = sql.SQLStr(focusSid)
            if dir == "dealt" then
                where = "ts >= " .. cutoff .. " AND a_sid = " .. s
            elseif dir == "taken" then
                where = "ts >= " .. cutoff .. " AND v_sid = " .. s
            else
                where = "ts >= " .. cutoff .. " AND (a_sid = " .. s .. " OR v_sid = " .. s .. ")"
            end
        else
            local s = sql.SQLStr("%" .. search .. "%")
            where = "ts >= " .. cutoff .. " AND (a_name LIKE " .. s .. " OR v_name LIKE " .. s ..
                " OR a_char LIKE " .. s .. " OR v_char LIKE " .. s ..
                " OR a_sid LIKE " .. s .. " OR v_sid LIKE " .. s .. ")"
        end
    end

    if f.teamkill then where = where .. " AND teamkill = 1" end

    local page = math.max(tonumber(f.page) or 0, 0)
    local rows = sql.Query(
        "SELECT id, ts, round, mode, a_sid, a_name, a_char, v_sid, v_name, v_char, weapon, dmg, hits, teamkill, etype" ..
        " FROM damage_log WHERE " .. where ..
        " ORDER BY id DESC LIMIT " .. (PAGE_SIZE + 1) .. " OFFSET " .. (page * PAGE_SIZE))
    rows = rows or {}
    local more = #rows > PAGE_SIZE
    if more then rows[PAGE_SIZE + 1] = nil end

    -- player summary when focused on a resolved sid
    local summary
    if focusSid then
        local s = sql.SQLStr(focusSid)
        local base = " FROM damage_log WHERE ts >= " .. cutoff .. " AND "
        summary = {
            sid = focusSid,
            dealt   = tonumber(sql.QueryValue("SELECT SUM(dmg)" .. base .. "a_sid = " .. s .. " AND etype='dmg'")) or 0,
            taken   = tonumber(sql.QueryValue("SELECT SUM(dmg)" .. base .. "v_sid = " .. s .. " AND etype='dmg'")) or 0,
            kills   = tonumber(sql.QueryValue("SELECT COUNT(*)" .. base .. "a_sid = " .. s .. " AND etype='kill'")) or 0,
            deaths  = tonumber(sql.QueryValue("SELECT COUNT(*)" .. base .. "v_sid = " .. s .. " AND etype='kill'")) or 0,
            tks     = tonumber(sql.QueryValue("SELECT COUNT(*)" .. base .. "a_sid = " .. s .. " AND teamkill = 1")) or 0,
        }
    end

    return { mode = "damage", rows = rows, page = page, more = more, summary = summary }
end

local function QueryWatchdog(f)
    local days = math.Clamp(tonumber(f.days) or 7, 1, 14)
    local where = { "ts >= " .. (os.time() - days * 86400) }

    if isstring(f.search) and f.search ~= "" then
        local s = sql.SQLStr("%" .. f.search .. "%")
        where[#where + 1] = "(name LIKE " .. s .. " OR sid LIKE " .. s ..
            " OR module LIKE " .. s .. " OR summary LIKE " .. s .. ")"
    end

    local page = math.max(tonumber(f.page) or 0, 0)
    local rows = sql.Query(
        "SELECT id, ts, sid, name, rank, module, summary, detail, map" ..
        " FROM watchdog_log WHERE " .. table.concat(where, " AND ") ..
        " ORDER BY id DESC LIMIT " .. (PAGE_SIZE + 1) .. " OFFSET " .. (page * PAGE_SIZE))
    rows = rows or {}
    local more = #rows > PAGE_SIZE
    if more then rows[PAGE_SIZE + 1] = nil end

    local counts = {}
    for _, r in ipairs(rows) do counts[r.module] = (counts[r.module] or 0) + 1 end
    return { mode = "watchdog", rows = rows, page = page, more = more, summary = counts }
end

-- ---------------------------------------------------------------------
-- net
-- ---------------------------------------------------------------------
local PANEL_LABELS = { punish = "history", damage = "damage", watchdog = "watchdog", log = "log" }

net.Receive("ULXLogPanel_Query", function(len, ply)
    if not CanUse(ply) then return end

    local ok, f = pcall(util.JSONToTable, net.ReadString())
    if not ok or not istable(f) then return end

    LogPanelUse(ply, PANEL_LABELS[f.tab] or "log")

    local result
    if f.tab == "punish" then
        result = QueryPunish(f, ply)
    elseif f.tab == "damage" then
        result = QueryDamage(f)
    elseif f.tab == "watchdog" then
        result = QueryWatchdog(f)
    else
        result = QueryLog(f, ply)
    end

    local payload = util.Compress(util.TableToJSON(result))
    net.Start("ULXLogPanel_Data")
        net.WriteUInt(#payload, 32)
        net.WriteData(payload, #payload)
    net.Send(ply)
end)

local DELETE_TABLES = {
    log = "ulx_cmdlog",
    punish = "punish_history",
    damage = "damage_log",
    watchdog = "watchdog_log",
}

net.Receive("ULXLogPanel_Delete", function(len, ply)
    -- deletion is superadmin ONLY, regardless of panel access level
    if not IsValid(ply) or not ply:IsSuperAdmin() then return end

    local tab = net.ReadString()
    local tbl = DELETE_TABLES[tab]
    if not tbl then return end

    local count = math.Clamp(net.ReadUInt(8), 1, 100)
    local ids = {}
    for i = 1, count do
        local id = net.ReadUInt(32)
        if id > 0 then ids[#ids + 1] = id end
    end
    if #ids == 0 then return end

    -- audit the deletion BEFORE performing it
    sql.Query(string.format(
        "INSERT INTO ulx_cmdlog (ts, sid, name, rank, cmd, target, target_sid, args, result, selftarget) VALUES (%d, %s, %s, %s, 'panel:delete', NULL, NULL, %s, 'executed', 0)",
        os.time(), sql.SQLStr(ply:SteamID()), sql.SQLStr(ply:Nick()),
        sql.SQLStr(ply:GetUserGroup()),
        sql.SQLStr(tbl .. " ids: " .. table.concat(ids, ","))))

    sql.Query("DELETE FROM " .. tbl .. " WHERE id IN (" .. table.concat(ids, ",") .. ")")
end)

-- open commands
concommand.Add("ulx_logs", function(ply)
    if not CanUse(ply) then
        if IsValid(ply) then ply:ChatPrint("Staff only.") end
        return
    end
    ply:ConCommand("ulx_logs_open")
end)

hook.Add("HG_PlayerSay", "ULXLogPanel_Chat", function(ply, text, rawtext)
    if istable(text) then text = text[1] or rawtext end
    if not isstring(text) then return end
    local t = string.Trim(string.lower(text))
    if t ~= "!logs" and t ~= "!ulxlogs" then return end
    if not CanUse(ply) then return end
    ply:ConCommand("ulx_logs_open")
end)

print("[ULXLogPanel] Server query layer loaded - ulx_logs / !logs")
