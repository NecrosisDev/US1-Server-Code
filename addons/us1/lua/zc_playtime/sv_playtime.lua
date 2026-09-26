-- Z-City: playtime, and an hourly ZPoint reward.
--
-- Owner, 2026-09-22: track playtime and pay pointshop points for every hour played.
--
-- No owner found. UTime used to do this and is GONE: nothing on the box defines GetUTimeTotalTime or writes
-- utime_updated, and that table's newest row is 2026-07-02. It left 2312 rows of real history and a scoreboard
-- column (cl_pat_scoreboard.lua:358) that silently renders nothing behind `if ply.GetUTimeTotalTime then`,
-- which is why the absence was invisible. So this is new -- but it reuses what is here rather than inventing:
-- the mysql wrapper and the DatabaseConnected pattern from sv_experience.lua, ply.afkTime from
-- sv_antiafk.lua, and PS_AddPoints for the payout.
--
-- IT PAYS NOBODY UNTIL SWITCHED ON. Default is 1: track and log, pay nothing. Same reason as sv_points.lua --
-- an hourly faucet is the easiest of all to get wrong, because every idle player earns from it.
if not SERVER then return end

ZCPlaytime = ZCPlaytime or {}
local P = ZCPlaytime
P.Version = "20260922.pt1"

-- 0 = off. 1 = track and log, pay nothing. 2 = track and pay.
local mode = CreateConVar("zc_playtime", "1", FCVAR_ARCHIVE, "Playtime: 0 off, 1 track only, 2 track and pay")
-- PROVISIONAL(2026-09-22, no rate was given; 100 ZP/hour puts the 1350 median accessory about 13 hours away,
-- which is a slower earner than combat and meant to be, ratify-by: 2026-10-22)
local REWARD = CreateConVar("zc_playtime_reward", "100", FCVAR_ARCHIVE, "ZPoints paid per full hour played")
-- sv_antiafk.lua moves a player to spectators at 300s idle and kicks at 600s, so 300 is its own idea of "gone".
local AFK = CreateConVar("zc_playtime_afk", "300", FCVAR_ARCHIVE, "Idle seconds after which time stops counting (0 = always count)")
local TICK = 60 -- how often time is credited; also the granularity of everything below

local stats = P.stats or {credited = 0, skippedAfk = 0, hours = 0, paid = 0, refused = 0, saves = 0, imported = 0, last = "nothing yet"}
P.stats = stats

-- [steamid64] = {n = name, s = seconds, h = hours already PAID for, dirty = bool}
local rows = P.rows or {}
P.rows = rows

P.Active = P.Active or false

local function row(sid, name)
    local e = rows[sid]
    if not e then e = {s = 0, h = 0} rows[sid] = e end
    if name then e.n = name end
    return e
end

-- ------------------------------------------------------------------------------- persistence
local function save(sid)
    local e = rows[sid]
    if not e or not P.Active then return end
    e.dirty = false
    local q = mysql:Update("zc_playtime")
        q:Update("steam_name", e.n or "")
        q:Update("seconds", math.floor(e.s))
        q:Update("paidhours", math.floor(e.h))
        q:Update("lastseen", os.time())
        q:Where("steamid", sid)
    q:Execute()
    stats.saves = stats.saves + 1
end
P.Save = save

local function load(ply)
    if not P.Active or not IsValid(ply) or ply:IsBot() then return end
    local sid, name = ply:SteamID64(), ply:Name()
    if not sid then return end

    local q = mysql:Select("zc_playtime")
        q:Select("seconds")
        q:Select("paidhours")
        q:Where("steamid", sid)
        q:Callback(function(result)
            if not IsValid(ply) then return end
            local e = row(sid, name)
            -- Already loaded this map. A reconnect (or two PlayerInitialSpawns racing) must NOT reapply the
            -- stored row over what is in memory: the table only gets written on the hour and on disconnect,
            -- so the stored value is up to an hour staler than the counter, and reloading it would quietly
            -- refund that hour to the house every time somebody rejoined.
            if e.loaded then return end
            if istable(result) and #result > 0 and result[1].seconds then
                e.s = tonumber(result[1].seconds) or 0
                e.h = tonumber(result[1].paidhours) or 0
                e.loaded = true
            else
                -- No row of our own. UTime may still hold this player's history: take the SECONDS so their
                -- total stays honest, but mark every one of those hours ALREADY PAID. Importing as unpaid
                -- would hand the 110-hour player 11000 ZP the instant this loads, and the owner's answer on
                -- back-pay was "start all at zero".
                local carried = 0
                local uq = mysql:Select("utime_updated")
                    uq:Select("totaltime")
                    uq:Where("SteamID64", sid)
                    uq:Callback(function(old)
                        if istable(old) and #old > 0 and old[1].totaltime then
                            carried = tonumber(old[1].totaltime) or 0
                            if carried > 0 then stats.imported = stats.imported + 1 end
                        end

                        local ee = row(sid, name)
                        ee.s = carried
                        ee.h = math.floor(carried / 3600)
                        ee.loaded = true

                        local iq = mysql:Insert("zc_playtime")
                            iq:Insert("steamid", sid)
                            iq:Insert("steam_name", name)
                            iq:Insert("seconds", math.floor(ee.s))
                            iq:Insert("paidhours", math.floor(ee.h))
                            iq:Insert("lastseen", os.time())
                        iq:Execute()
                    end)
                uq:Execute()
            end
        end)
    q:Execute()
end
P.Load = load

hook.Add("DatabaseConnected", "ZCPlaytimeCreate", function()
    local q = mysql:Create("zc_playtime")
        q:Create("steamid", "VARCHAR(20) NOT NULL")
        q:Create("steam_name", "VARCHAR(32) NOT NULL")
        q:Create("seconds", "INT NOT NULL")
        q:Create("paidhours", "INT NOT NULL")
        q:Create("lastseen", "INT NOT NULL")
        q:PrimaryKey("steamid")
    q:Execute()

    P.Active = true
    for _, ply in ipairs(player.GetHumans()) do load(ply) end
end)

hook.Add("PlayerInitialSpawn", "ZCPlaytime", function(ply)
    -- A reconnect inside one map reuses the row, so the session counter has to start over or the
    -- scoreboard would show a "this session" figure covering two of them.
    local sid = IsValid(ply) and ply:SteamID64() or nil
    if sid and rows[sid] then rows[sid].session = 0 end
    load(ply)
end)

hook.Add("PlayerDisconnected", "ZCPlaytime", function(ply)
    if not IsValid(ply) then return end
    local sid = ply:SteamID64()
    if sid and rows[sid] then save(sid) end
end)

-- A map change would otherwise drop up to an hour of everyone's time on the floor.
hook.Add("ShutDown", "ZCPlaytime", function()
    for sid, e in pairs(rows) do if e.dirty then save(sid) end end
end)

-- ------------------------------------------------------------------------------- earning
-- Counted as PLAYING: connected, not a bot, and not idle by the server's own definition. ply.afkTime is
-- sv_antiafk.lua's counter -- reset on KeyPress and on chat, and the same number it uses to decide somebody
-- has gone away. Borrowing it means there is one idea of "AFK" here, not two that disagree.
function P.IsEarning(ply)
    if not IsValid(ply) or not ply:IsPlayer() or ply:IsBot() then return false end
    local limit = AFK:GetInt()
    if limit <= 0 then return true end
    return (tonumber(ply.afkTime) or 0) < limit
end

local function payHours(ply, sid, e, live)
    local due = math.floor(e.s / 3600) - e.h
    if due < 1 then return end

    e.h = e.h + due
    stats.hours = stats.hours + due
    local owed = due * REWARD:GetInt()

    if not live then
        print(string.format("[Playtime] %s reached %d hour%s: would pay %d ZP (shadow)",
            tostring(e.n or sid), math.floor(e.s / 3600), due == 1 and "" or "s", owed))
        save(sid)
        return
    end

    if owed > 0 and IsValid(ply) and ply.PS_AddPoints then
        local ok, why = ply:PS_AddPoints(owed)
        if ok then
            stats.paid = stats.paid + owed
            ply:ChatPrint(string.format("+%d ZPoints for %d hour%s played.", owed, math.floor(e.s / 3600), math.floor(e.s / 3600) == 1 and "" or "s"))
            print(string.format("[Playtime] %s paid %d ZP for hour %d", tostring(e.n or sid), owed, math.floor(e.s / 3600)))
        else
            -- The shop refuses a profile that has not loaded. The hour is still BANKED (e.h moved), because
            -- re-trying against an absolute write is how a balance gets clobbered; it is logged instead.
            stats.refused = stats.refused + 1
            print(string.format("[Playtime] %s earned %d ZP but the shop refused: %s", tostring(e.n or sid), owed, tostring(why)))
        end
    end
    save(sid)
end

timer.Create("ZCPlaytimeThink", TICK, 0, function()
    if mode:GetInt() <= 0 then return end
    local live = mode:GetInt() >= 2

    for _, ply in ipairs(player.GetHumans()) do
        local sid = IsValid(ply) and ply:SteamID64() or nil
        if sid then
            if P.IsEarning(ply) then
                local e = row(sid, ply:Name())
                e.s = e.s + TICK
                e.session = (e.session or 0) + TICK
                e.dirty = true
                stats.credited = stats.credited + TICK
                P.Publish(ply, e)
                payHours(ply, sid, e, live)
            else
                stats.skippedAfk = stats.skippedAfk + TICK
            end
        end
    end
end)

-- ------------------------------------------------------------------------------- reading it back
function P.Get(ply)
    if not IsValid(ply) then return 0 end
    local sid = ply:SteamID64()
    local e = sid and rows[sid]
    return e and e.s or 0
end

function P.Session(ply)
    if not IsValid(ply) then return 0 end
    local sid = ply:SteamID64()
    local e = sid and rows[sid]
    return e and e.session or 0
end

-- The scoreboard's playtime column lights up from here, with no client file and no map change.
--
-- It tries `ply:GetUTimeTotalTime()` first (cl_pat_scoreboard.lua:358) -- a CLIENT name, absent since UTime
-- was removed, which is why the column has been blank. Aliasing it server-side would have changed nothing a
-- player can see. But the same function then falls back to a list of plain networked keys (:366-378):
-- PlayTime, TimePlayed, TotalPlayTime, first one >= 0 wins. Setting one of those is all it takes.
--
-- PlayTime carries the WHOLE total, session included, because that fallback returns the value as-is. The
-- UTime branch above it does `total + session`, so feeding both names would have counted this session twice.
local function publish(ply, e)
    if not IsValid(ply) or not e then return end
    local total = math.floor(e.s)
    ply:SetNWInt("PlayTime", total)
    -- Our own names, for anything that wants the two figures apart.
    ply:SetNWInt("ZCPlaytimeTotal", total)
    ply:SetNWInt("ZCPlaytimeSession", math.floor(e.session or 0))
end
P.Publish = publish

-- ------------------------------------------------------------------------------- telling the player
-- "12h 34m". Hours are what the reward is denominated in, so they lead.
function P.Pretty(seconds)
    seconds = math.max(math.floor(tonumber(seconds) or 0), 0)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if h < 1 then return m .. "m" end
    return h .. "h " .. m .. "m"
end

-- What a player is told about themselves. Returns the lines rather than printing them, so the chat command
-- and anything added later (a panel, a scoreboard tooltip) cannot drift apart on the wording.
function P.Report(ply)
    if not IsValid(ply) then return {} end

    local sid = ply:SteamID64()
    local e = sid and rows[sid]
    if not e then
        return {"[Playtime] Nothing recorded yet - give it a minute."}
    end

    local out = {string.format("[Playtime] You have played %s (%s this session).",
        P.Pretty(e.s), P.Pretty(e.session or 0))}

    if mode:GetInt() >= 2 then
        local reward = REWARD:GetInt()
        local left = 3600 - (e.s % 3600)
        out[#out + 1] = string.format("Paid for %d hour%s. %s until your next %d ZPoints.",
            e.h, e.h == 1 and "" or "s", P.Pretty(left), reward)
        if not P.IsEarning(ply) then
            out[#out + 1] = "You are counted as idle right now, so this is not going up. Move or say something."
        end
    elseif mode:GetInt() == 1 then
        out[#out + 1] = "Playtime rewards are not switched on yet - your time is being counted."
    end

    return out
end

-- The only other !command on this server is !pointshop, so this follows it exactly: trimmed and
-- case-folded, still an EXACT match (so "how do I check !playtime" stays a message), and swallowed from
-- chat afterwards, because a command is not a thing you said. ZChat drops a message whose first slot is
-- empty (zchat/sh_chat.lua:227-232).
hook.Add("HG_PlayerSay", "ZCPlaytimeSay", function(ply, txtTbl, txt)
    if not isstring(txt) then return end
    if string.lower(string.Trim(txt)) ~= "!playtime" then return end

    for _, line in ipairs(P.Report(ply)) do ply:ChatPrint(line) end

    if istable(txtTbl) then txtTbl[1] = "" end
end)

-- Same thing from the console, for anyone who prefers it. Not admin-gated: it only ever reports on the
-- caller, which is the whole point -- the two commands below are the staff ones.
-- NOT named zc_playtime: that is already the convar above, and a concommand sharing a convar's name is a
-- collision the engine resolves in nobody's favour.
concommand.Add("zc_playtime_me", function(p)
    if not IsValid(p) then return end
    for _, line in ipairs(P.Report(p)) do p:PrintMessage(HUD_PRINTTALK, line) end
end, nil, "Show your playtime and hourly ZPoint rewards in chat.")

concommand.Add("zc_playtime_stats", function(p)
    if IsValid(p) and not p:IsAdmin() then return end
    local n = 0
    for _ in pairs(rows) do n = n + 1 end
    local line = string.format("[Playtime] %s mode=%d reward=%d/h afk=%ds | tracked=%d credited=%.1fh skippedAfk=%.1fh hours=%d paid=%d ZP refused=%d imported=%d saves=%d",
        P.Version, mode:GetInt(), REWARD:GetInt(), AFK:GetInt(), n, stats.credited / 3600, stats.skippedAfk / 3600,
        stats.hours, stats.paid, stats.refused, stats.imported, stats.saves)
    if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
end, nil, "Admin: print playtime tracking totals.")

concommand.Add("zc_playtime_check", function(p, _, args)
    if IsValid(p) and not p:IsAdmin() then return end
    local want = string.lower(args[1] or "")
    local out = {}
    for _, ply in ipairs(player.GetHumans()) do
        if want == "" or string.find(string.lower(ply:Name()), want, 1, true) then
            local e = rows[ply:SteamID64()]
            out[#out + 1] = string.format("%s %.2fh (paid %d, %s)", ply:Name(), (e and e.s or 0) / 3600,
                e and e.h or 0, P.IsEarning(ply) and "earning" or "idle")
        end
    end
    local line = "[Playtime] " .. (#out > 0 and table.concat(out, " | ") or "nobody matched")
    if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
end, nil, "Admin: print online players' playtime: zc_playtime_check [name].")
