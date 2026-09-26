-- ULX Log Panel - ZC Watchdog capture layer
-- Adopts ZC Watchdog anticheat detections into the Staff Logs panel. Watchdog
-- itself is untouched: it already fires hook.Run("WD_Dossier", ply, module,
-- evidence) whenever a dossier is filed (after its anti-flood cooldown, and
-- never for exempt staff). We mirror each into a disk-backed SQLite table that
-- the panel's "Watchdog" tab reads. Flat RAM footprint; own retention.
if not SERVER then return end

local RETENTION_DAYS = 14
local MAX_ROWS       = 20000

-- =========================================================================
-- DATABASE
-- =========================================================================
sql.Query([[CREATE TABLE IF NOT EXISTS watchdog_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts INTEGER NOT NULL,
    sid TEXT NOT NULL,
    name TEXT NOT NULL,
    rank TEXT,
    module TEXT NOT NULL,
    summary TEXT,
    detail TEXT,
    map TEXT
)]])
sql.Query("CREATE INDEX IF NOT EXISTS wdlog_ts ON watchdog_log (ts)")
sql.Query("CREATE INDEX IF NOT EXISTS wdlog_sid ON watchdog_log (sid)")
sql.Query("CREATE INDEX IF NOT EXISTS wdlog_module ON watchdog_log (module)")

local function Cleanup()
    sql.Query("DELETE FROM watchdog_log WHERE ts < " .. (os.time() - RETENTION_DAYS * 86400))
    local n = tonumber(sql.QueryValue("SELECT COUNT(*) FROM watchdog_log") or 0)
    if n > MAX_ROWS then
        sql.Query("DELETE FROM watchdog_log WHERE id IN (SELECT id FROM watchdog_log ORDER BY id ASC LIMIT "
            .. (n - MAX_ROWS) .. ")")
    end
end
Cleanup()
timer.Create("ULXLog_WatchdogCleanup", 21600, 0, Cleanup)

-- =========================================================================
-- CAPTURE: mirror each Watchdog dossier into the table
-- =========================================================================
-- pull the most human-useful fields out of the module's evidence table
local SUMMARY_KEYS = {
    "note", "target", "dist", "viewOffDeg", "jump", "yawRate", "ticks",
    "sweep", "speed", "allowed", "runspeed", "type", "pitch", "roll",
    "cappedCommands", "perWindow", "weapon",
}
local function Summarize(ev)
    if not istable(ev) then return tostring(ev) end
    local parts = {}
    for _, k in ipairs(SUMMARY_KEYS) do
        if ev[k] ~= nil then parts[#parts + 1] = k .. "=" .. tostring(ev[k]) end
    end
    return table.concat(parts, "  ")
end

hook.Add("WD_Dossier", "ULXLog_WatchdogCapture", function(ply, module, evidence, action)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local detail = ""
    local ok, json = pcall(util.TableToJSON, istable(evidence) and evidence or { value = tostring(evidence) })
    if ok and json then detail = json end

    -- action tag ("kicked"/"banned") rides the summary column so it shows in the
    -- Watchdog tab and wdlog_recent with no schema or panel changes; plain
    -- watch-mode detections stay untagged (= only logged).
    local summary = Summarize(evidence)
    if action and action ~= "logged" then
        summary = "[" .. string.upper(tostring(action)) .. "]  " .. summary
    end

    sql.Query(string.format(
        "INSERT INTO watchdog_log (ts, sid, name, rank, module, summary, detail, map) VALUES (%d, %s, %s, %s, %s, %s, %s, %s)",
        os.time(),
        sql.SQLStr(ply:SteamID()), sql.SQLStr(ply:Nick()), sql.SQLStr(ply:GetUserGroup()),
        sql.SQLStr(module), sql.SQLStr(summary),
        sql.SQLStr(detail), sql.SQLStr(game.GetMap())
    ))
end)

-- =========================================================================
-- verification command (panel tab does the rest)
-- =========================================================================
concommand.Add("wdlog_recent", function(ply, _, args)
    if IsValid(ply) and not (ply:IsAdmin() or ply:IsSuperAdmin()) then return end
    local n = math.Clamp(tonumber(args and args[1]) or 20, 1, 100)
    local rows = sql.Query("SELECT ts, name, rank, module, summary FROM watchdog_log ORDER BY id DESC LIMIT " .. n)
    if not rows then print("[ULXLog/WD] No detections logged.") return end
    print(string.format("[ULXLog/WD] Last %d detections:", #rows))
    for _, r in ipairs(rows) do
        print(string.format("%s  %-18s %-10s %-10s %s",
            os.date("%m-%d %H:%M:%S", tonumber(r.ts)), string.sub(r.name, 1, 18),
            r.rank or "?", r.module, string.sub(r.summary or "", 1, 60)))
    end
end)

print("[ULXLog] ZC Watchdog capture layer loaded - detections -> Staff Logs 'Watchdog' tab")
