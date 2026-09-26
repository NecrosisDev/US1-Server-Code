-- ZCity Damage Log
-- Player-vs-player damage + kills, aggregated per attacker->victim->weapon
-- burst (a shotgun blast or mag dump = ONE row, not 8-30), batch-flushed to
-- SQLite once a second. Player-indexed both directions for the panel's
-- "damage BY player / damage TO player" view.
--
-- Retention: 3 days / 100k rows (this answers "who RDMed me tonight",
-- not archaeology). Kills also recorded as their own event rows.
if not SERVER then return end

local RETENTION_DAYS = 3
local MAX_ROWS       = 100000
local IDLE_FLUSH     = 0.6   -- pair quiet this long -> row flushes

-- =========================================================================
-- DATABASE
-- =========================================================================
sql.Query([[CREATE TABLE IF NOT EXISTS damage_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts INTEGER NOT NULL,
    round INTEGER,
    mode TEXT,
    a_sid TEXT NOT NULL,
    a_name TEXT,
    a_char TEXT,
    v_sid TEXT NOT NULL,
    v_name TEXT,
    v_char TEXT,
    weapon TEXT,
    dmg INTEGER NOT NULL DEFAULT 0,
    hits INTEGER NOT NULL DEFAULT 1,
    teamkill INTEGER NOT NULL DEFAULT 0,
    etype TEXT NOT NULL DEFAULT 'dmg'
)]])
sql.Query("CREATE INDEX IF NOT EXISTS dl_ts ON damage_log (ts)")
sql.Query("CREATE INDEX IF NOT EXISTS dl_a ON damage_log (a_sid, ts)")
sql.Query("CREATE INDEX IF NOT EXISTS dl_v ON damage_log (v_sid, ts)")

local function Cleanup()
    if zb and zb.ROUND_STATE == 1 then return end  -- never during a live round
    sql.Query("DELETE FROM damage_log WHERE ts < " .. (os.time() - RETENTION_DAYS * 86400))
    local n = tonumber(sql.QueryValue("SELECT COUNT(*) FROM damage_log") or 0)
    if n > MAX_ROWS then
        sql.Query("DELETE FROM damage_log WHERE id IN (SELECT id FROM damage_log ORDER BY id ASC LIMIT " .. (n - MAX_ROWS) .. ")")
    end
end
timer.Create("DamageLog_Cleanup", 21600, 0, Cleanup)
timer.Simple(30, Cleanup)

-- =========================================================================
-- IDENTITY / CONTEXT HELPERS
-- =========================================================================
-- role-aware teamkill: homicide-family rounds put everyone on team 0,
-- so raw team comparison calls everything a TK. There, the real
-- "teams" are the traitor line: innocent-vs-innocent (or
-- traitor-vs-traitor) is a TK; across the line is gameplay.
-- zb.CROUND holds the round TYPE (e.g. "standard"), not the mode key
local HMCD_FAMILY = {
    ["standard"] = true, ["soe"] = true,
    ["wildwest"] = true, ["masscasualty"] = true,
    ["fear"] = true, ["fear_soe"] = true,
    ["hmcd"] = true, ["hmcd_soe"] = true, -- belt and suspenders
}

local function IsTeamkill(atk, vic)
    local round = zb and zb.CROUND
    if round and HMCD_FAMILY[round] then
        return (atk.isTraitor == true) == (vic.isTraitor == true)
    end
    return atk:Team() == vic:Team()
end

local function Ident(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return nil end
    local char = ply.GetNWString and ply:GetNWString("PlayerName", "") or ""
    return ply:SteamID(), ply:Nick(), (char ~= "" and char or nil)
end

local function Context()
    return (zb and zb.Roundscount) or 0, (zb and tostring(zb.CROUND or "")) or ""
end

-- =========================================================================
-- AGGREGATION BUFFER + BATCH FLUSH
-- =========================================================================
local buffer = {}   -- key "asid|vsid|weapon" -> pending row
local pending = 0

local function FlushRows(rows)
    if #rows == 0 then return end
    local values = {}
    for _, r in ipairs(rows) do
        values[#values + 1] = string.format("(%d, %d, %s, %s, %s, %s, %s, %s, %s, %s, %d, %d, %d, %s)",
            r.ts, r.round, sql.SQLStr(r.mode),
            sql.SQLStr(r.a_sid), sql.SQLStr(r.a_name or ""), r.a_char and sql.SQLStr(r.a_char) or "NULL",
            sql.SQLStr(r.v_sid), sql.SQLStr(r.v_name or ""), r.v_char and sql.SQLStr(r.v_char) or "NULL",
            sql.SQLStr(r.weapon or "?"),
            math.Round(r.dmg), r.hits, r.teamkill, sql.SQLStr(r.etype))
    end
    sql.Query("INSERT INTO damage_log (ts, round, mode, a_sid, a_name, a_char, v_sid, v_name, v_char, weapon, dmg, hits, teamkill, etype) VALUES "
        .. table.concat(values, ","))
end

local function FlushIdle(force)
    if pending == 0 then return end
    local now = CurTime()
    local out = {}
    for key, r in pairs(buffer) do
        if force or (now - r.lastHit) > IDLE_FLUSH then
            out[#out + 1] = r
            buffer[key] = nil
            pending = pending - 1
        end
    end
    FlushRows(out)
end

timer.Create("DamageLog_Flush", 1, 0, function() FlushIdle(false) end)
hook.Add("ZB_EndRound", "DamageLog_RoundFlush", function() FlushIdle(true) end)
hook.Add("ShutDown", "DamageLog_Shutdown", function() FlushIdle(true) end)

-- flush everything involving one player immediately (called before kills
-- so the row order in the log reads naturally)
local function FlushPlayer(sid)
    local out = {}
    for key, r in pairs(buffer) do
        if r.a_sid == sid or r.v_sid == sid then
            out[#out + 1] = r
            buffer[key] = nil
            pending = pending - 1
        end
    end
    FlushRows(out)
end

-- =========================================================================
-- CAPTURE: damage
-- =========================================================================
local sigWarned = false

local function ExtractDamage(...)
    -- defensive: find the victim entity and the CTakeDamageInfo among the
    -- args regardless of exact HomigradDamage signature on this build
    local vic, dmg
    for _, a in ipairs({...}) do
        local t = TypeID(a)
        if t == TYPE_DAMAGEINFO then
            dmg = a
        elseif t == TYPE_ENTITY and not vic and IsValid(a) then
            vic = a
        end
    end
    return vic, dmg
end

-- grenades and thrown items arrive with the projectile (or world) as
-- attacker - walk the entity's ownership fields back to the thrower
local function ResolveThrower(atk, inf)
    if IsValid(atk) and atk:IsPlayer() then return atk end
    local src = (IsValid(atk) and atk) or (IsValid(inf) and inf) or nil
    if not src then return nil end
    for _, cand in ipairs({ src:GetOwner(), src.Owner, src.thrower, src.ply, src.owner }) do
        if IsValid(cand) and cand:IsPlayer() then return cand end
    end
    return nil
end

hook.Add("HomigradDamage", "DamageLog_Capture", function(...)
    local ok, err = pcall(function(...)
        local vic, dmg = ExtractDamage(...)
        if not vic or not dmg then
            if not sigWarned then
                sigWarned = true
                print("[DamageLog] WARNING: could not extract victim/dmginfo from HomigradDamage args")
            end
            return
        end

        -- victim may be the ragdoll - map back to the player
        if not vic:IsPlayer() and IsValid(vic.ply) then vic = vic.ply end
        if not vic:IsPlayer() then return end

        local atk = ResolveThrower(dmg:GetAttacker(), dmg:GetInflictor())
        if not IsValid(atk) or not atk:IsPlayer() then return end
        if atk == vic then return end

        local amount = dmg:GetDamage()
        if amount <= 0 then return end

        local a_sid, a_name, a_char = Ident(atk)
        local v_sid, v_name, v_char = Ident(vic)
        if not a_sid or not v_sid then return end

        local inf = dmg:GetInflictor()
        local weapon = "?"
        if IsValid(inf) and inf ~= atk then
            weapon = inf:GetClass()
        else
            local w = atk:GetActiveWeapon()
            weapon = IsValid(w) and w:GetClass() or "?"
        end

        local key = a_sid .. "|" .. v_sid .. "|" .. weapon
        local r = buffer[key]
        if not r then
            local round, mode = Context()
            r = {
                ts = os.time(), round = round, mode = mode,
                a_sid = a_sid, a_name = a_name, a_char = a_char,
                v_sid = v_sid, v_name = v_name, v_char = v_char,
                weapon = weapon, dmg = 0, hits = 0,
                teamkill = IsTeamkill(atk, vic) and 1 or 0,
                etype = "dmg",
            }
            buffer[key] = r
            pending = pending + 1
        end
        r.dmg = r.dmg + amount
        r.hits = r.hits + 1
        r.lastHit = CurTime()
    end, ...)

    if not ok and not sigWarned then
        sigWarned = true
        print("[DamageLog] capture error (logging disabled for safety this session): " .. tostring(err))
        hook.Remove("HomigradDamage", "DamageLog_Capture")
    end
end)

-- =========================================================================
-- CAPTURE: kills
-- =========================================================================
hook.Add("PlayerDeath", "DamageLog_Kill", function(vic, inf, atk)
    if not IsValid(vic) or not vic:IsPlayer() then return end
    atk = ResolveThrower(atk, inf) or atk
    if not IsValid(atk) or not atk:IsPlayer() or atk == vic then return end

    local v_sid, v_name, v_char = Ident(vic)
    local a_sid, a_name, a_char = Ident(atk)
    if not a_sid or not v_sid then return end

    FlushPlayer(v_sid)  -- damage rows land before the kill row

    local round, mode = Context()
    FlushRows({{
        ts = os.time(), round = round, mode = mode,
        a_sid = a_sid, a_name = a_name, a_char = a_char,
        v_sid = v_sid, v_name = v_name, v_char = v_char,
        weapon = IsValid(inf) and inf:GetClass() or "?",
        dmg = 0, hits = 1,
        teamkill = (atk:Team() == vic:Team()) and 1 or 0,
        etype = "kill",
    }})
end)

print("[DamageLog] Loaded - aggregated PvP damage + kills, 3-day retention")
