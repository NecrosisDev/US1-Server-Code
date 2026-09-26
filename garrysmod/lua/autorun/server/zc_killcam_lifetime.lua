-- Z-City killcam, phase 2 (killcam_revitalize): lifetime per-player stats, persisted to disk.
-- Server-only. Off by default: convar zc_killcam_lifetime, 0 = inert (no hooks do work, no disk I/O).
if not SERVER then return end

local M = ZCKillcamLifetime or {}
ZCKillcamLifetime = M
M.Version = "20260924.lifetime1"

local cvar = CreateConVar("zc_killcam_lifetime", "0", FCVAR_ARCHIVE,
    "Killcam lifetime stats: persist per-player kills/deaths/damage across sessions (0 off)")

local ROOT = "zc_killcam/stats"

-- sid64 -> row, while the player is online and the row is loaded.
local rows = M.Rows or {}
M.Rows = rows
-- sid64 -> true for rows with unwritten changes.
local dirty = M.Dirty or {}
M.Dirty = dirty
-- sid64 -> delta accumulator for a player whose row is not loaded yet. In the ordinary path this
-- never happens (PlayerInitialSpawn/PlayerSpawn load the row before any hit can land), but a hit
-- or kill must never be dropped if that timing is ever off, and must never trigger a disk read of
-- its own from inside HomigradDamage/ZCKillcam_Death.
local pending = M.Pending or {}
M.Pending = pending
-- sid64 -> true for humans who have taken a real spawn (OverrideSpawn falsy) this round.
local spawnedThisRound = M.SpawnedThisRound or {}
M.SpawnedThisRound = spawnedThisRound

local stats = M.Stats or {errors = 0, lastFlushN = 0, lastFlushCost = 0}
M.Stats = stats

local receipted = false

local function safeHook(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            stats.errors = stats.errors + 1
            if stats.errors == 1 then print("[Killcam] ZCKillcamLifetime error: " .. tostring(err)) end
        end
    end
end

local function receipt()
    if receipted then return end
    receipted = true
    file.CreateDir("zc_killcam")
    local line = os.date("%Y-%m-%d %H:%M:%S") .. " zc_killcam_lifetime.lua version=" .. M.Version
        .. " on=" .. (cvar:GetBool() and 1 or 0) .. "\n"
    file.Append("zc_killcam/boot.txt", line)
    print("[Killcam] " .. line)
end
hook.Add("InitPostEntity", "ZCKillcamLifetime.Boot", receipt)
-- Catches a hot-reload after InitPostEntity already fired (that hook will then never run again):
-- Think fires every tick regardless of load order, so the very next tick prints the receipt
-- instead. `receipted` makes either order idempotent and this handler removes itself once done.
hook.Add("Think", "ZCKillcamLifetime.BootCatch", function()
    receipt()
    hook.Remove("Think", "ZCKillcamLifetime.BootCatch")
end)

local function freshRow()
    local now = os.time()
    return {v = 1, name = "", kills = 0, deaths = 0, damage = 0, damageTaken = 0,
        rounds = 0, first = now, last = now}
end

-- Folds an unmerged pending delta into a freshly loaded row. Only ever called right after the row
-- is created/loaded, never from a hot path.
local function applyPending(sid, row)
    local p = pending[sid]
    if not p then return end
    row.kills = row.kills + p.kills
    row.deaths = row.deaths + p.deaths
    row.damage = row.damage + p.damage
    row.damageTaken = row.damageTaken + p.damageTaken
    row.rounds = row.rounds + p.rounds
    pending[sid] = nil
    dirty[sid] = true
end

local function nameOf(ply)
    local K = ZCKillcam
    if K and K.DisplayName then return K.DisplayName(ply) end
    return ply:Nick()
end

-- Loads (or creates) sid's row into memory. Synchronous file.Read, but only ever called off the
-- per-hit hot path (PlayerInitialSpawn / PlayerSpawn) - never from HomigradDamage/ZCKillcam_Death.
-- Idempotent: a second call for an already-loaded sid is a no-op.
local function loadRow(sid, ply)
    if rows[sid] then return end
    local path = ROOT .. "/" .. sid .. ".json"
    local row
    if file.Exists(path, "DATA") then
        local raw = file.Read(path, "DATA")
        local ok, decoded = pcall(util.JSONToTable, raw or "")
        if ok and istable(decoded) and decoded.v == 1 then row = decoded end
    end
    if not row then row = freshRow() end
    if ply then row.name = nameOf(ply) end
    row.last = os.time()
    rows[sid] = row
    applyPending(sid, row)
end

-- O(1) table increment; creates sid's pending delta the first time a not-yet-loaded sid is
-- touched. No allocation beyond the one pending/row table made on first use per player.
local function bump(sid, field, amount)
    local row = rows[sid]
    if row then
        row[field] = row[field] + amount
        dirty[sid] = true
        return
    end
    local p = pending[sid]
    if not p then
        p = {kills = 0, deaths = 0, damage = 0, damageTaken = 0, rounds = 0}
        pending[sid] = p
    end
    p[field] = p[field] + amount
end

local function round1(n) return math.Round(n * 10) / 10 end

local function writeRow(sid)
    local row = rows[sid]
    if not row then return end
    local out = {v = 1, name = row.name, kills = row.kills, deaths = row.deaths,
        damage = round1(row.damage), damageTaken = round1(row.damageTaken),
        rounds = row.rounds, first = row.first, last = row.last}
    file.CreateDir(ROOT)
    file.Write(ROOT .. "/" .. sid .. ".json", util.TableToJSON(out))
    dirty[sid] = nil
end

-- sids: array of SteamID64 strings. sync = true writes them all now (ShutDown: the job queue will
-- not run again). Otherwise routed through the killcam job queue when available, low-priority and
-- noExpire, so a lifetime flush never delays a clip cut and is never dropped by the low-tier age
-- sweep (P2_SPEC.md hard rule).
local function flushDirty(sids, sync)
    if #sids == 0 then return end
    local K = ZCKillcam
    if sync or not (K and K.Work) then
        local began = SysTime()
        for _, sid in ipairs(sids) do writeRow(sid) end
        stats.lastFlushN, stats.lastFlushCost = #sids, SysTime() - began
        return
    end
    local began = SysTime()
    K.Work("killcam_lifetime_flush", function(breathe)
        for _, sid in ipairs(sids) do
            writeRow(sid)
            breathe("write")
        end
        stats.lastFlushN, stats.lastFlushCost = #sids, SysTime() - began
    end, function()
        stats.errors = stats.errors + 1
    end, true, nil, true)
end

-- Orchestrator review 2026-09-24 (adversarial review): a delta that landed while its row was not loaded (the
-- convar switched on mid-life, before that player's next real spawn) lives only in `pending`, which no flush reads.
-- Every flush point first loads such a row (a file.Read, never on the hit path) and folds the delta in (dirty).
local function promotePending(onlySid)
    for sid in pairs(pending) do
        if (not onlySid or sid == onlySid) and not rows[sid] then
            local ply = player.GetBySteamID64 and player.GetBySteamID64(sid) or nil
            loadRow(sid, IsValid(ply) and ply or nil)
        end
    end
end

local function dirtyList()
    local sids = {}
    for sid in pairs(dirty) do sids[#sids + 1] = sid end
    return sids
end

-- PlayerDisconnected: write sid's row (if dirty) and only THEN drop it from memory. A plain
-- flushDirty({sid}, false) would queue an async K.Work job and clear rows[sid] before that job
-- runs, so the deferred write would find nothing left to write; this keeps the row resident until
-- the write that reads it has actually happened.
local function flushAndForget(sid)
    if not dirty[sid] then
        rows[sid] = nil
        return
    end
    local K = ZCKillcam
    if not (K and K.Work) then
        writeRow(sid)
        rows[sid] = nil
        return
    end
    K.Work("killcam_lifetime_flush", function(breathe)
        writeRow(sid)
        breathe("write")
        rows[sid] = nil
        stats.lastFlushN, stats.lastFlushCost = 1, 0
    end, function()
        stats.errors = stats.errors + 1
        rows[sid] = nil
    end, true, nil, true)
end

----------------------------------------------------------------- hooks

hook.Add("HomigradDamage", "ZCKillcamLifetime.Hit", safeHook(function(ply, dmgInfo, hitgroup, ent, harm)
    if not cvar:GetBool() then return end
    local victim = ply
    if IsValid(victim) and not victim:IsPlayer() and hg and hg.RagdollOwner then victim = hg.RagdollOwner(victim) end
    local attacker = dmgInfo:GetAttacker()
    if not IsValid(victim) or not victim:IsPlayer() or not IsValid(attacker) or not attacker:IsPlayer()
        or attacker == victim then return end
    local amount = tonumber(harm) or 0
    if amount <= 0 then return end
    if not victim:IsBot() then bump(victim:SteamID64(), "damageTaken", amount) end
    if not attacker:IsBot() then bump(attacker:SteamID64(), "damage", amount) end
end))

hook.Add("ZCKillcam_Death", "ZCKillcamLifetime.Death", safeHook(function(victim, killer)
    if not cvar:GetBool() then return end
    if IsValid(victim) and victim:IsPlayer() and not victim:IsBot() then
        bump(victim:SteamID64(), "deaths", 1)
    end
    if killer and killer.id then
        bump(killer.id, "kills", 1)
    end
end))

hook.Add("PlayerInitialSpawn", "ZCKillcamLifetime.Join", safeHook(function(ply)
    if not cvar:GetBool() then return end
    if not IsValid(ply) or not ply:IsPlayer() or ply:IsBot() then return end
    loadRow(ply:SteamID64(), ply)
end))

hook.Add("PlayerSpawn", "ZCKillcamLifetime.Spawn", safeHook(function(ply)
    if not cvar:GetBool() then return end
    if not IsValid(ply) or not ply:IsPlayer() or ply:IsBot() then return end
    if rawget(_G, "OverrideSpawn") then return end -- a mid-life get-up, not a new life
    local sid = ply:SteamID64()
    loadRow(sid, ply) -- catches a player who connected before the convar was switched on
    spawnedThisRound[sid] = true
end))

-- Orchestrator review 2026-09-24: NOT cleared at ZB_StartRound. Players are spawned for a round before
-- zb:RoundStart runs hook "ZB_StartRound", so clearing there wiped every one-life spawn and `rounds` would almost
-- never count. The set is emptied only where it is counted (ZB_EndRound), so "spawned since the last round ended"
-- is what a round means here.

hook.Add("ZB_EndRound", "ZCKillcamLifetime.EndRound", safeHook(function()
    if not cvar:GetBool() then return end
    for sid in pairs(spawnedThisRound) do
        bump(sid, "rounds", 1)
        spawnedThisRound[sid] = nil
    end
    promotePending()
    flushDirty(dirtyList(), false)
end))

hook.Add("PlayerDisconnected", "ZCKillcamLifetime.Leave", safeHook(function(ply)
    if not cvar:GetBool() then return end
    if not IsValid(ply) or not ply:IsPlayer() or ply:IsBot() then return end
    local sid = ply:SteamID64()
    promotePending(sid)
    flushAndForget(sid)
    pending[sid] = nil
end))

hook.Add("ShutDown", "ZCKillcamLifetime.Shutdown", safeHook(function()
    if not cvar:GetBool() then return end
    promotePending()
    flushDirty(dirtyList(), true) -- synchronous: the job queue will not run again
end))

----------------------------------------------------------------- read API

-- Returns a COPY of sid's row, or nil (off, or not loaded - never reads disk here).
function M.Get(sid)
    if not cvar:GetBool() then return nil end
    local row = rows[sid]
    if not row then return nil end
    local copy = {}
    for k, v in pairs(row) do copy[k] = v end
    return copy
end

----------------------------------------------------------------- staff command

local function findSid(arg)
    if arg:match("^%d+$") and #arg >= 15 then return arg end
    local needle = arg:lower()
    for _, ply in ipairs(player.GetHumans and player.GetHumans() or player.GetAll()) do
        if IsValid(ply) and not ply:IsBot() and ply:Nick():lower():find(needle, 1, true) then
            return ply:SteamID64()
        end
    end
end

concommand.Add("zc_killcam_lifetime_print", function(p, _, args)
    if IsValid(p) and not p:IsAdmin() then return end
    local function out(line)
        if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
    end
    local arg = args and args[1]
    if not arg or arg == "" then
        local nLoaded, nDirty = 0, 0
        for _ in pairs(rows) do nLoaded = nLoaded + 1 end
        for _ in pairs(dirty) do nDirty = nDirty + 1 end
        out(string.format("[Killcam] lifetime: on=%d loaded=%d dirty=%d lastFlush=%d row(s)/%.1fms errors=%d",
            cvar:GetBool() and 1 or 0, nLoaded, nDirty, stats.lastFlushN, stats.lastFlushCost * 1000, stats.errors))
        return
    end
    local sid = findSid(arg)
    local row = sid and rows[sid]
    if not row then
        out("[Killcam] lifetime: no loaded row for '" .. arg .. "'")
        return
    end
    out(string.format("[Killcam] lifetime %s: %s kills=%d deaths=%d dmg=%.1f taken=%.1f rounds=%d first=%s last=%s",
        sid, row.name, row.kills, row.deaths, row.damage, row.damageTaken, row.rounds,
        os.date("%Y-%m-%d %H:%M:%S", row.first), os.date("%Y-%m-%d %H:%M:%S", row.last)))
end, nil, "Print a player's lifetime killcam stats, or a loaded/dirty count with no argument.")
