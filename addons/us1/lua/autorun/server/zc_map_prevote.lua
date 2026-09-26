-- Map PRE-VOTE panel data (Goob's ZCity US1). Server-only. Standing per-round pre-votes,
-- broadcast to the panel, wired into SolidMapVote's real ballot via an identity-checked wrap of
-- SolidMapVote.selectMaps (addons/zc_solidmapvote, never edited here) using the same
-- rec={original=,wrapper=}/ensureInstalled idiom as zc_round_guard.lua's wrapModeMethod.
if not SERVER then return end

ZCMapPrevote = ZCMapPrevote or {}
local M = ZCMapPrevote
M.Version = "20260924.prevote1"

local cv = CreateConVar("zc_map_prevote", "0", FCVAR_ARCHIVE, "Enable the SolidMapVote pre-vote panel wrap (0/1).")

util.AddNetworkString("zc_map_prevote_cast")
util.AddNetworkString("zc_map_prevote_ask")
util.AddNetworkString("zc_map_prevote_state")

-- State ----------------------------------------------------------------------------------------
M.votes = M.votes or {}     -- sid64 -> map name (their standing pre-vote)
M.changed = M.changed or {} -- sid64 -> true once they've used this round's set/change allowance
M.stats = M.stats or { errors = 0, applications = 0, identityChanges = 0, firstError = nil }
M.lastApplication = M.lastApplication or nil -- {ranked = {...}, time = CurTime()}
M.pool = M.pool or nil                       -- cached installed/allowed map list, built per map load

local rec = { original = nil, wrapper = nil } -- the SolidMapVote.selectMaps wrap record
M.Rec = rec

local function countError(err)
    M.stats.errors = M.stats.errors + 1
    if not M.stats.firstError then
        M.stats.firstError = tostring(err)
        print("[Killcam] zc_map_prevote error: " .. tostring(err))
    end
end

-- Connected humans only: bots have no SteamID64 and never count. ------------------------------
local function humans()
    local list = {}
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and not ply:IsBot() then list[#list + 1] = ply end
    end
    return list
end

-- Pool: installed maps/*.bsp filtered by SolidMapVote.isAllowed, minus the current map. Cached
-- once per map load (this file's whole lifetime), rebuilt lazily on first need. ------------------
local function buildPool()
    local list = {}
    if not SolidMapVote or not SolidMapVote.isAllowed then return list end
    local current = string.lower(game.GetMap())
    for _, filename in ipairs(file.Find("maps/*.bsp", "GAME") or {}) do
        local name = filename:sub(1, -5)
        if SolidMapVote.isAllowed(name) and string.lower(name) ~= current then
            list[#list + 1] = name
        end
    end
    table.sort(list)
    return list
end
M.BuildPool = buildPool

local function pool()
    if not M.pool then M.pool = buildPool() end
    return M.pool
end
M.Pool = pool

-- Standing tally: count of connected humans' current pre-votes per map, ranked count desc then
-- name. Disconnected players never appear in humans(), so their vote never counts. ---------------
local function tally()
    local counts = {}
    for _, ply in ipairs(humans()) do
        local sid = ply:SteamID64()
        local map = sid and M.votes[sid]
        if map and map ~= "" then counts[map] = (counts[map] or 0) + 1 end
    end
    local order = {}
    for map, count in pairs(counts) do order[#order + 1] = { map = map, count = count } end
    table.sort(order, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.map < b.map
    end)
    return order
end
M.Tally = tally

local function limitFor()
    if not SolidMapVote or not SolidMapVote.number then return 6 end
    return math.floor(SolidMapVote.number("Map Limit", 6, 1, 6))
end

-- Pre-voted maps with count > 0 that are in the real pool and not excluded, capped at `cap`. ------
local function rankedForWrap(exclude, cap)
    local ranked, out = tally(), {}
    for _, row in ipairs(ranked) do
        if #out >= cap then break end
        local name = row.map
        if SolidMapVote.poolSet and SolidMapVote.poolSet[name] and not exclude[name] then
            out[#out + 1] = name
        end
    end
    return out
end

-- THE WRAP ---------------------------------------------------------------------------------------
-- off, a reroll (ignoreNominations), or no counted pre-votes -> the original, unchanged. Otherwise
-- ranked pre-votes go first, the original fills the rest (never duplicating, never excluded), and
-- M.maps/M.ballotSet are rebuilt keeping extend/random exactly as the original call left them. The
-- ranking part is pcall'd; any error falls back to the plain original call (and is counted).
local function wrapperFn(exclude, ignoreNominations)
    exclude = exclude or {}
    if not rec.original then return {} end
    if not cv:GetBool() or ignoreNominations then
        return rec.original(exclude, ignoreNominations)
    end
    local cap = limitFor()
    local ranked = rankedForWrap(exclude, cap)
    if #ranked == 0 then
        return rec.original(exclude, ignoreNominations)
    end
    local ok, result = pcall(function()
        local excludePlus = {}
        for name in pairs(exclude) do excludePlus[name] = true end
        for _, name in ipairs(ranked) do excludePlus[name] = true end
        local originalPicks = rec.original(excludePlus, ignoreNominations)
        local extendFlag = SolidMapVote.ballotSet and SolidMapVote.ballotSet.extend
        local randomFlag = SolidMapVote.ballotSet and SolidMapVote.ballotSet.random
        local out, seen = {}, {}
        for _, name in ipairs(ranked) do
            if not seen[name] then out[#out + 1] = name; seen[name] = true end
        end
        for _, name in ipairs(originalPicks or {}) do
            if #out >= cap then break end
            if not seen[name] then out[#out + 1] = name; seen[name] = true end
        end
        local ballotSet = {}
        for _, name in ipairs(out) do ballotSet[name] = true end
        if extendFlag then ballotSet.extend = true end
        if randomFlag then ballotSet.random = true end
        SolidMapVote.maps = out
        SolidMapVote.ballotSet = ballotSet
        return out
    end)
    if ok then
        M.lastApplication = { ranked = ranked, time = CurTime() }
        M.stats.applications = M.stats.applications + 1
        M.votes = {} -- the real ballot just opened/consumed the standing pre-votes; clear them
        return result
    end
    countError(result)
    return rec.original(exclude, ignoreNominations)
end
rec.wrapper = wrapperFn
M.Wrapper = wrapperFn

-- Idempotent: safe at InitPostEntity, on the 2s timer, and on the convar change callback. On +
-- SolidMapVote.selectMaps not already our wrapper -> take it as the new original and install.
-- Off + currently wrapped -> restore the current original. -------------------------------------
local function ensureInstalled()
    if not SolidMapVote then return end
    if cv:GetBool() then
        local current = SolidMapVote.selectMaps
        if type(current) == "function" and current ~= rec.wrapper then
            if rec.original then M.stats.identityChanges = M.stats.identityChanges + 1 end
            rec.original = current
            SolidMapVote.selectMaps = rec.wrapper
        end
    else
        if rec.original and SolidMapVote.selectMaps == rec.wrapper then
            SolidMapVote.selectMaps = rec.original
        end
    end
end
M.EnsureInstalled = ensureInstalled

-- Throttle: 1 cast/ask per second per player. ----------------------------------------------------
local lastCast, lastAsk = {}, {}
local function allowCast(sid)
    local now = CurTime()
    if lastCast[sid] and now - lastCast[sid] < 1 then return false end
    lastCast[sid] = now
    return true
end
local function allowAsk(sid)
    local now = CurTime()
    if lastAsk[sid] and now - lastAsk[sid] < 1 then return false end
    lastAsk[sid] = now
    return true
end

local dirty = false
local function markDirty() dirty = true end

-- Wire (S->C zc_map_prevote_state): WriteUInt(1,8) WriteUInt(n<=16,5) then n x {WriteString(map)
-- WriteUInt(count,8)} (ranked) WriteString(yourVote or "") WriteBool(canChangeThisRound)
-- WriteUInt(nPool<=400,9) then nPool x WriteString(map) (pool only on "ask" replies; nPool=0 on
-- broadcasts, which also carry an empty yourVote/false canChange since net.Broadcast cannot
-- personalize a single buffered message per recipient).
local function replyState(ply, includePool)
    local ranked = tally()
    local sid = ply:SteamID64()
    net.Start("zc_map_prevote_state")
    net.WriteUInt(1, 8)
    local n = math.min(#ranked, 16)
    net.WriteUInt(n, 5)
    for i = 1, n do
        net.WriteString(ranked[i].map)
        net.WriteUInt(math.min(ranked[i].count, 255), 8)
    end
    net.WriteString((sid and M.votes[sid]) or "")
    net.WriteBool(sid ~= nil and not M.changed[sid])
    if includePool then
        local list = pool()
        local nPool = math.min(#list, 400)
        net.WriteUInt(nPool, 9)
        for i = 1, nPool do net.WriteString(list[i]) end
    else
        net.WriteUInt(0, 9)
    end
    net.Send(ply)
end

local function doBroadcast()
    if not cv:GetBool() then return end
    local ranked = tally()
    net.Start("zc_map_prevote_state")
    net.WriteUInt(1, 8)
    local n = math.min(#ranked, 16)
    net.WriteUInt(n, 5)
    for i = 1, n do
        net.WriteString(ranked[i].map)
        net.WriteUInt(math.min(ranked[i].count, 255), 8)
    end
    net.WriteString("")
    net.WriteBool(false)
    net.WriteUInt(0, 9)
    net.Broadcast()
end

net.Receive("zc_map_prevote_cast", function(len, ply)
    local map = net.ReadString() or ""
    if not cv:GetBool() then return end
    local ok, err = pcall(function()
        if not IsValid(ply) or ply:IsBot() then return end
        local sid = ply:SteamID64()
        if not sid then return end
        if not allowCast(sid) then return end
        if #map > 64 then return end
        if map ~= "" then
            if not map:match("^[%w_%.%-]+$") then return end
            if not (SolidMapVote and SolidMapVote.isAllowed and SolidMapVote.isAllowed(map)) then return end
            if not file.Exists("maps/" .. map .. ".bsp", "GAME") then return end
            if string.lower(map) == string.lower(game.GetMap()) then return end
        end
        if M.changed[sid] then return end
        M.votes[sid] = (map ~= "") and map or nil
        M.changed[sid] = true
        markDirty()
        replyState(ply, false)
    end)
    if not ok then countError(err) end
end)

net.Receive("zc_map_prevote_ask", function(len, ply)
    if not cv:GetBool() then return end
    local ok, err = pcall(function()
        if not IsValid(ply) or ply:IsBot() then return end
        local sid = ply:SteamID64()
        if not sid then return end
        if not allowAsk(sid) then return end
        replyState(ply, true)
    end)
    if not ok then countError(err) end
end)

concommand.Add("zc_map_prevote_print", function(p, _, _)
    if IsValid(p) and not p:IsAdmin() then return end
    local function out(line)
        if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, line .. "\n") else print(line) end
    end
    out(string.format("[zc_map_prevote] version=%s on=%d", M.Version, cv:GetBool() and 1 or 0))
    local ranked = tally()
    out(string.format("  standing tally: %d map(s)", #ranked))
    for i = 1, math.min(#ranked, 16) do
        out(string.format("    %d. %s x%d", i, ranked[i].map, ranked[i].count))
    end
    local installed = rec.original ~= nil and SolidMapVote and SolidMapVote.selectMaps == rec.wrapper
    out(string.format("  wrap: installed=%s identityChanges=%d applications=%d errors=%d",
        tostring(installed and true or false), M.stats.identityChanges, M.stats.applications, M.stats.errors))
    if M.lastApplication then
        out(string.format("  last application: %d ranked map(s) at t=%.1f", #M.lastApplication.ranked, M.lastApplication.time or 0))
        for i, name in ipairs(M.lastApplication.ranked) do out("    " .. i .. ". " .. name) end
    else
        out("  last application: none")
    end
end, nil, "Admin: print the map pre-vote tally.")

hook.Add("ZB_StartRound", "ZCMapPrevote_StartRound", function()
    if not cv:GetBool() then return end
    local ok, err = pcall(function() M.changed = {} end)
    if not ok then countError(err) end
end)

hook.Add("PlayerDisconnected", "ZCMapPrevote_Disconnect", function(ply)
    if not cv:GetBool() then return end
    local ok, err = pcall(function()
        if not IsValid(ply) or ply:IsBot() then return end
        local sid = ply:SteamID64()
        if not sid then return end
        M.votes[sid] = nil
        M.changed[sid] = nil
    end)
    if not ok then countError(err) end
end)

-- Boot receipt -------------------------------------------------------------------------------
local receipted = false
local function bootReceipt()
    if receipted then return end
    receipted = true
    file.CreateDir("zc_killcam")
    local line = os.date("%Y-%m-%d %H:%M:%S") .. " zc_map_prevote.lua version=" .. M.Version .. " on=" .. (cv:GetBool() and 1 or 0)
    file.Append("zc_killcam/boot.txt", line .. "\n")
    print("[Killcam] " .. line)
end

hook.Add("InitPostEntity", "ZCMapPrevote_Install", function()
    ensureInstalled()
    M.pool = buildPool()
    bootReceipt()
end)
timer.Create("ZCMapPrevote_Install", 2, 0, ensureInstalled)
timer.Create("ZCMapPrevote_Broadcast", 1, 0, function()
    if not cv:GetBool() then return end
    if not dirty then return end
    dirty = false
    local ok, err = pcall(doBroadcast)
    if not ok then countError(err) end
end)

cvars.AddChangeCallback("zc_map_prevote", function(_, _, new)
    ensureInstalled()
end, "ZCMapPrevote_Toggle")

-- Late load (a live refresh after InitPostEntity already fired this map): same idiom as
-- zc_round_guard.lua's own late-load guard, so the wrap and the boot receipt engage immediately
-- rather than waiting on the timer / never firing at all.
if hook.GetULibTable then
    ensureInstalled()
    bootReceipt()
end
