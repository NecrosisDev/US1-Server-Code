-- Z-City killcam: end-of-round summary broadcast.
--
-- At ZB_EndRound, 2.5 s later (a named, cancellable timer -- lets the round's last combat burst be
-- booked by sv_points before totals are read), builds and broadcasts ONE summary to everyone on NEW
-- net string "zc_round_summary". Survivors and the winner text are captured immediately at
-- ZB_EndRound (before the 2.5 s wait), because who was alive at the horn is a fact about that instant;
-- everything else (mode name, duration, the ZP leaderboard, round totals) is read 2.5 s later, when the
-- points ledger has settled. The 2.5 s timer is named and removed at ZB_StartRound and
-- ZB_PreRoundStart so a summary can never land after the next round has begun, and a second
-- ZB_EndRound in the same intermission never produces a second broadcast.
--
-- Wire order (server -> client; P4's client reader must decode in EXACTLY this order):
--   WriteUInt(1, 8)             -- payload version
--   WriteString(mode)
--   WriteUInt(duration, 16)     -- seconds, clamped 0-65535 (0 if the round start time is unknown)
--   WriteString(winner)
--   WriteUInt(nSurvivors, 4)    -- <= 8
--   nSurvivors x WriteString(name)
--   WriteUInt(nTop, 3)          -- <= 5
--   nTop x {
--       WriteString(name)
--       WriteUInt(zp, 16)
--       WriteUInt(combat, 24)
--       WriteUInt(heals, 8)
--       WriteUInt(kills, 8)
--   }
--   WriteUInt(totalKills, 12)
--   WriteUInt(totalHeals, 12)
-- Every WriteUInt value is clamped (floored, then min/max) to its bit width before it is written.
-- Strings: player/team names truncated to 32 chars; mode and winner text truncated to 48 chars.
if not SERVER then return end

ZCRoundSummary = ZCRoundSummary or {}
local M = ZCRoundSummary
M.Version = "20260924.rs2"

-- 0 = off: no hooks do work, nothing is ever sent. 1 = on.
local cvOn = CreateConVar("zc_round_summary", "0", FCVAR_ARCHIVE, "Round summary broadcast: 0 off, 1 on")

util.AddNetworkString("zc_round_summary")
util.AddNetworkString("zc_map_summary") -- owner 2026-09-24: the whole map's numbers, sent with the last round's summary

local PENDING = "ZCRoundSummary.Send"

local stats = { errors = 0, firstErr = nil }
local function guarded(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            stats.errors = stats.errors + 1
            if not stats.firstErr then
                stats.firstErr = tostring(err)
                print("[Killcam] zc_round_summary error: " .. stats.firstErr)
            end
        end
    end
end

local function truncate(s, n)
    s = tostring(s or "")
    if #s > n then return string.sub(s, 1, n) end
    return s
end

local function clampU(n, bits)
    n = math.floor(tonumber(n) or 0)
    local hi = (2 ^ bits) - 1
    if n < 0 then n = 0 elseif n > hi then n = hi end
    return n
end

local function displayName(p)
    local K = rawget(_G, "ZCKillcam")
    if K and K.DisplayName then
        local name = K.DisplayName(p)
        if name then return name end
    end
    return p:Nick()
end

-- [SteamID64] = kills this round, from ZCKillcam_Death. Reset at ZB_StartRound.
local tally = {}

-- true from the first accepted ZB_EndRound until its timer fires (sent or skipped) or is cancelled.
local awaiting = false
-- true once a summary has actually been broadcast for the round that is currently in intermission;
-- reset only at ZB_StartRound (the intermission is over once the next round begins).
local sentThisIntermission = false

-- Captured AT ZB_EndRound, not 2.5 s later.
local capturedSurvivors, capturedWinner, capturedDuration

-- Map summary (owner, 2026-09-24): everything this map has seen since it loaded, folded from every round's rows
-- and broadcast on "zc_map_summary" right after the LAST round summary before a map vote (SolidMapVote.mapVoteDue()),
-- for the final intermission's stats card. Lives exactly as long as the map (this file reloads with it).
-- Wire order (server -> client, "zc_map_summary"):
--   WriteUInt(1, 8)             -- payload version
--   WriteString(map)            -- <= 48 chars
--   WriteUInt(rounds, 8)
--   WriteUInt(elapsed, 16)      -- seconds since this file loaded with the map
--   WriteUInt(nTop, 3)          -- <= 5
--   nTop x { WriteString(name), WriteUInt(points, 24), WriteUInt(kills, 12), WriteUInt(heals, 12), WriteUInt(rounds, 8), WriteUInt(wins, 8) }
--   WriteUInt(totalKills, 16)
--   WriteUInt(totalHeals, 16)
local mapAgg = { rounds = 0, kills = 0, heals = 0, rows = {}, since = CurTime() }
M.Map = mapAgg
local function foldIntoMap(rows, survivors, totalKills, totalHeals)
    mapAgg.rounds = mapAgg.rounds + 1
    mapAgg.kills = mapAgg.kills + (tonumber(totalKills) or 0)
    mapAgg.heals = mapAgg.heals + (tonumber(totalHeals) or 0)
    local survived = {}
    for _, name in ipairs(survivors or {}) do survived[name] = true end
    for _, row in ipairs(rows or {}) do
        local key = row.sid or row.name
        local e = mapAgg.rows[key]
        if not e then
            e = { name = row.name, points = 0, kills = 0, heals = 0, rounds = 0, wins = 0 }
            mapAgg.rows[key] = e
        end
        e.name = row.name
        e.points = e.points + (row.zp or 0) + (row.combat or 0)
        e.kills = e.kills + (row.kills or 0)
        e.heals = e.heals + (row.heals or 0)
        e.rounds = e.rounds + 1
        if survived[row.name] then e.wins = e.wins + 1 end
    end
end
local function mapTop()
    local list = {}
    for _, e in pairs(mapAgg.rows) do list[#list + 1] = e end
    table.sort(list, function(a, b)
        if a.points ~= b.points then return a.points > b.points end
        if a.kills ~= b.kills then return a.kills > b.kills end
        return a.name < b.name
    end)
    return list
end
local function broadcastMap()
    local list = mapTop()
    net.Start("zc_map_summary")
    net.WriteUInt(1, 8)
    net.WriteString(truncate(game.GetMap(), 48))
    net.WriteUInt(clampU(mapAgg.rounds, 8), 8)
    net.WriteUInt(clampU(CurTime() - mapAgg.since, 16), 16)
    local n = math.min(#list, 5)
    net.WriteUInt(n, 3)
    for i = 1, n do
        local e = list[i]
        net.WriteString(truncate(e.name, 32))
        net.WriteUInt(clampU(e.points, 24), 24)
        net.WriteUInt(clampU(e.kills, 12), 12)
        net.WriteUInt(clampU(e.heals, 12), 12)
        net.WriteUInt(clampU(e.rounds, 8), 8)
        net.WriteUInt(clampU(e.wins, 8), 8)
    end
    net.WriteUInt(clampU(mapAgg.kills, 16), 16)
    net.WriteUInt(clampU(mapAgg.heals, 16), 16)
    net.Broadcast()
    M.LastMap = { map = game.GetMap(), rounds = mapAgg.rounds, top = list, kills = mapAgg.kills, heals = mapAgg.heals }
end
local function mapVoteDue()
    local S = rawget(_G, "SolidMapVote")
    return type(S) == "table" and type(S.mapVoteDue) == "function" and S.mapVoteDue() == true
end

local function captureEndState()
    local alive = {}
    local teamRef, sameTeam = nil, true
    for _, p in ipairs(player.GetHumans() or {}) do
        if IsValid(p) and p:Alive() then
            alive[#alive + 1] = p
            local t = p:Team()
            if teamRef == nil then teamRef = t elseif t ~= teamRef then sameTeam = false end
        end
    end

    -- Orchestrator review 2026-09-24 (adversarial review): a shared team only means a team WON when the round was
    -- played between teams: humans present must span two or more teams (spectator / unassigned not counted).
    -- In a free-for-all everyone shares one team, and naming it ("Unassigned") would be wrong - that stays "".
    local teams, spread = {}, 0
    for _, p in ipairs(player.GetHumans() or {}) do
        local t = IsValid(p) and p:Team()
        if t and t ~= TEAM_SPECTATOR and t ~= TEAM_UNASSIGNED and not teams[t] then teams[t] = true spread = spread + 1 end
    end
    if spread < 2 then sameTeam = false end

    -- the round's length at the horn, not 2.5 s later when it is sent
    local zbT = rawget(_G, "zb")
    capturedDuration = (zbT and type(zbT.ROUND_BEGIN) == "number") and clampU(CurTime() - zbT.ROUND_BEGIN, 16) or 0

    capturedSurvivors = {}
    for i, p in ipairs(alive) do capturedSurvivors[i] = truncate(displayName(p), 32) end

    if #alive == 0 then
        capturedWinner = "nobody"
    elseif #alive == 1 then
        capturedWinner = truncate(displayName(alive[1]), 48)
    elseif sameTeam and teamRef ~= nil and team.GetName then
        capturedWinner = truncate(team.GetName(teamRef) or "", 48)
    else
        capturedWinner = ""
    end
end

-- Top 5 by Owed ZP (ties: more kills, then name). When the points table is unavailable every zp is 0,
-- so the same sort degenerates to "rank by kills, then name" -- exactly the fallback the spec asks for,
-- with no separate branch needed. Candidates are humans connected right now ("present"); kills already
-- landed are still counted whether or not their scorer is still connected (see totals below).
local function computeTop()
    local K = rawget(_G, "ZCKillcam")
    local pointsRound = K and K.Points and K.Points.round
    local owed = K and K.Points and K.Points.Owed

    local rows = {}
    for _, p in ipairs(player.GetHumans() or {}) do
        if IsValid(p) and not p:IsBot() then
            local sid = p:SteamID64()
            if sid then
                local prow = pointsRound and pointsRound[sid]
                local zp, combat, heals = 0, 0, 0
                if prow then
                    if owed then zp = clampU(owed(prow), 16) end
                    combat = clampU(prow.combat, 24)
                    heals = clampU(prow.heals, 8)
                end
                rows[#rows + 1] = {
                    sid = sid,
                    name = truncate(displayName(p), 32),
                    zp = zp, combat = combat, heals = heals,
                    kills = clampU(tally[sid] or 0, 8),
                }
            end
        end
    end

    table.sort(rows, function(a, b)
        if a.zp ~= b.zp then return a.zp > b.zp end
        if a.kills ~= b.kills then return a.kills > b.kills end
        return a.name < b.name
    end)

    local top = {}
    for i = 1, math.min(5, #rows) do top[i] = rows[i] end

    -- Round totals: everyone who scored, present or not -- these count what happened this round, not
    -- just who is still connected to read it back.
    local totalKills = 0
    for _, n in pairs(tally) do totalKills = totalKills + (tonumber(n) or 0) end
    local totalHeals = 0
    if pointsRound then
        for _, e in pairs(pointsRound) do totalHeals = totalHeals + (tonumber(e.heals) or 0) end
    end

    return top, totalKills, totalHeals, rows
end

local function broadcast(summary)
    net.Start("zc_round_summary")
    net.WriteUInt(1, 8)
    net.WriteString(summary.mode)
    net.WriteUInt(summary.duration, 16)
    net.WriteString(summary.winner)

    local nSurv = math.min(#summary.survivors, 8)
    net.WriteUInt(nSurv, 4)
    for i = 1, nSurv do net.WriteString(summary.survivors[i]) end

    local nTop = math.min(#summary.top, 5)
    net.WriteUInt(nTop, 3)
    for i = 1, nTop do
        local row = summary.top[i]
        net.WriteString(row.name)
        net.WriteUInt(row.zp, 16)
        net.WriteUInt(row.combat, 24)
        net.WriteUInt(row.heals, 8)
        net.WriteUInt(row.kills, 8)
    end

    net.WriteUInt(summary.totalKills, 12)
    net.WriteUInt(summary.totalHeals, 12)
    net.Broadcast()
end

local function sendSummary()
    awaiting = false
    if not cvOn:GetBool() or sentThisIntermission then return end

    local modeName = ""
    local cr = rawget(_G, "CurrentRound")
    cr = cr and cr()
    if cr and cr.name then modeName = cr.name end

    local duration = capturedDuration or 0

    local top, totalKills, totalHeals, rows = computeTop()

    local summary = {
        mode = truncate(modeName, 48),
        duration = duration,
        winner = capturedWinner or "",
        survivors = capturedSurvivors or {},
        top = top,
        totalKills = clampU(totalKills, 12),
        totalHeals = clampU(totalHeals, 12),
    }

    sentThisIntermission = true
    M.Last = summary
    broadcast(summary)
    -- Owner 2026-09-24: fold this round into the map's totals; before a map vote, the whole map's numbers follow.
    foldIntoMap(rows, summary.survivors, totalKills, totalHeals)
    if mapVoteDue() then broadcastMap() end
end

local function onEndRound()
    if not cvOn:GetBool() then return end
    if awaiting or sentThisIntermission then return end
    awaiting = true
    captureEndState()
    timer.Create(PENDING, 2.5, 1, guarded(sendSummary))
end

hook.Add("ZB_EndRound", "ZCRoundSummary.End", guarded(onEndRound))

hook.Add("ZB_StartRound", "ZCRoundSummary.Start", guarded(function()
    timer.Remove(PENDING)
    awaiting = false
    sentThisIntermission = false
    tally = {}
end))

-- Between rounds, still inside the same intermission: only strip any surviving timer so it cannot fire
-- into the next round. Does not reset sentThisIntermission -- that guard lives until ZB_StartRound.
hook.Add("ZB_PreRoundStart", "ZCRoundSummary.Pre", guarded(function()
    timer.Remove(PENDING)
    awaiting = false
end))

hook.Add("ZCKillcam_Death", "ZCRoundSummary.Death", guarded(function(victim, killer, tag)
    if not cvOn:GetBool() then return end
    if killer and killer.id then
        tally[killer.id] = (tally[killer.id] or 0) + 1
    end
end))

-- Boot receipt: fires at InitPostEntity, and once immediately (guarded so it can still only ever fire
-- once) if this file loaded after InitPostEntity already happened -- the same "hook.GetULibTable"
-- late-load signal zc_round_guard.lua and zc_vote_manager.lua already use for this on this server.
local receipted = false
local function receipt()
    if receipted then return end
    receipted = true
    file.CreateDir("zc_killcam")
    local line = os.date("%Y-%m-%d %H:%M:%S") .. " zc_round_summary.lua version=" .. M.Version
        .. " on=" .. cvOn:GetInt() .. "\n"
    file.Append("zc_killcam/boot.txt", line)
    print("[Killcam] " .. line)
end
hook.Add("InitPostEntity", "ZCRoundSummary.Boot", receipt)
if hook.GetULibTable then receipt() end

-- Staff: zc_round_summary_print prints the last summary; "send" (admins/console only, same gate)
-- re-broadcasts it without waiting for another round to end.
concommand.Add("zc_round_summary_print", function(p, _, args)
    if IsValid(p) and not p:IsAdmin() then return end
    local function out(line)
        if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
    end

    if args and args[1] and string.lower(args[1]) == "send" then
        if not cvOn:GetBool() then out("[Killcam] round summary is off (zc_round_summary 0)") return end
        if not M.Last then out("[Killcam] no round summary to resend yet") return end
        broadcast(M.Last)
        out("[Killcam] resent the last round summary")
        return
    end

    if not M.Last then
        out(string.format("[Killcam] round summary %s: no summary yet (on=%d, errors=%d)",
            M.Version, cvOn:GetInt(), stats.errors))
        return
    end

    local s = M.Last
    out(string.format("[Killcam] round summary %s: mode=%s duration=%ds winner=%s survivors=%d top=%d totalKills=%d totalHeals=%d errors=%d",
        M.Version, s.mode, s.duration, s.winner, #s.survivors, #s.top, s.totalKills, s.totalHeals, stats.errors))
    for i, row in ipairs(s.top) do
        out(string.format("  #%d %s zp=%d combat=%d heals=%d kills=%d", i, row.name, row.zp, row.combat, row.heals, row.kills))
    end
    out(string.format("[Killcam] map summary: %s rounds=%d kills=%d heals=%d players=%d sent=%s", game.GetMap(), mapAgg.rounds, mapAgg.kills, mapAgg.heals,
        table.Count(mapAgg.rows), tostring(M.LastMap ~= nil)))
    for i, e in ipairs(mapTop()) do
        if i > 5 then break end
        out(string.format("  #%d %s points=%d kills=%d heals=%d rounds=%d wins=%d", i, e.name, e.points, e.kills, e.heals, e.rounds, e.wins))
    end
end)
