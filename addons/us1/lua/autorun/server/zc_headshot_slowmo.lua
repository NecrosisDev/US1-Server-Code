if not SERVER then return end
local M = ZCHeadshotSlowmo or {}
-- Hot reload must release only the timescale this module still owns.
if M.Release then M.Release("reload") end
ZCHeadshotSlowmo = M
M.Version = "20260920.2"
M.pending = setmetatable({}, {__mode = "k"})
M.dead = setmetatable({}, {__mode = "k"})
M.stats = M.stats or {kills = 0, pulses = 0, coalesced = 0, external = 0, restored = 0}
M.stats.extended = M.stats.extended or 0
M.stats.extensionSeconds = M.stats.extensionSeconds or 0
local enabled = CreateConVar("zc_headshot_slowmo", "1", FCVAR_ARCHIVE, "Brief slow motion on fatal player headshots", 0, 1)
local scale = CreateConVar("zc_headshot_slowmo_scale", "0.35", FCVAR_ARCHIVE, "Fatal headshot game speed", 0.1, 0.95)
local duration = CreateConVar("zc_headshot_slowmo_duration", "0.35", FCVAR_ARCHIVE, "Fatal headshot pulse in real seconds", 0.1, 0.75)
local function isplayer(p) return IsValid(p) and p:IsPlayer() end
local function bullet(info)
    return info and info:IsDamageType(DMG_BULLET + DMG_BUCKSHOT + DMG_SNIPER)
end
local function same(a, b) return type(a) == "number" and math.abs(a - b) < 0.0001 end
local function running() return zb and zb.ROUND_STATE == 1 end

function M.Release(reason)
    local active = M.active
    if not active then return end
    M.active = nil
    if same(game.GetTimeScale(), active.applied) then
        game.SetTimeScale(active.before)
        M.stats.restored = M.stats.restored + 1
    end
    M.lastRelease = reason
end

function M.Start()
    if not enabled:GetBool() or not running() then return false end
    local now = SysTime()
    -- A kill after the deadline starts a fresh pulse even before Think runs.
    if M.active and now >= M.active.deadline then M.Release("finished") end
    if M.active then
        if same(game.GetTimeScale(), M.active.applied) then
            local active = M.active
            local deadline = math.min(active.deadline + active.nextExtension, active.limit)
            local added = deadline - active.deadline
            active.deadline = deadline
            active.nextExtension = active.nextExtension * 0.5
            M.stats.coalesced = M.stats.coalesced + 1
            if added > 0 then
                M.stats.extended = M.stats.extended + 1
                M.stats.extensionSeconds = M.stats.extensionSeconds + added
            end
            return true
        end
        M.Release("external_change")
        M.stats.external = M.stats.external + 1
        return false
    end
    local before = game.GetTimeScale()
    local host = GetConVar("host_timescale")
    if not same(before, 1) or (host and not same(host:GetFloat(), 1)) then
        M.stats.external = M.stats.external + 1
        return false
    end
    local applied = math.Clamp(scale:GetFloat(), 0.1, 0.95)
    local length = math.Clamp(duration:GetFloat(), 0.1, 0.75)
    -- Add half the base duration, then a quarter, then an eighth, etc.
    -- Snapshot the budget: even a large burst cannot exceed twice the base pulse.
    M.active = {before = before, applied = applied, deadline = now + length,
        nextExtension = length * 0.5, limit = now + length * 2}
    game.SetTimeScale(applied)
    M.stats.pulses = M.stats.pulses + 1
    return true
end

function M.Tick()
    local active = M.active
    if not active then return end
    if not same(game.GetTimeScale(), active.applied) then M.Release("external_change"); return end
    if not enabled:GetBool() or not running() or SysTime() >= active.deadline then M.Release("finished") end
end

function M.ClearHit(p)
    if isplayer(p) then M.pending[p] = nil end
end

function M.Record(p, info, hitgroup, source)
    if not isplayer(p) then return end
    M.pending[p] = nil -- A later body hit must invalidate an earlier head hit.
    if not enabled:GetBool() or not running() or not p:Alive() or M.dead[p]
        or hitgroup ~= HITGROUP_HEAD or not bullet(info) or info:GetDamage() <= 0 then return end
    local attacker = info:GetAttacker()
    if not isplayer(attacker) or attacker == p then return end
    M.pending[p] = {org = p.organism, attacker = attacker, source = source, at = SysTime(), tick = engine.TickCount()}
end

function M.OnDeath(p, attacker, info)
    if not isplayer(p) or M.dead[p] then return end
    M.dead[p] = true
    local hit = M.pending[p]
    M.pending[p] = nil
    if not hit or hit.org ~= p.organism or SysTime() - hit.at > 0.25
        or engine.TickCount() - hit.tick > 1 or not IsValid(hit.attacker) then return end
    -- Native medical kills use Player:Kill(), whose death DamageInfo is generic.
    -- Accept that path only when the current organism has actually become terminal;
    -- a recent nonfatal head hit followed by suicide/admin Kill is not enough.
    local medical = hit.source == "native" and type(hit.org) == "table" and hit.org.alive == false
    local direct = bullet(info) and info:GetAttacker() == hit.attacker
    if not medical and not direct then return end
    M.stats.kills = M.stats.kills + 1
    M.Start()
end

function M.Reset()
    M.Release("round_or_map_cleanup")
    M.pending = setmetatable({}, {__mode = "k"})
    M.dead = setmetatable({}, {__mode = "k"})
end

hook.Add("PreHomigradDamage", "ZCHeadshotSlowmo_Clear", function(p) M.ClearHit(p) end)
hook.Add("HomigradDamage", "ZCHeadshotSlowmo_Record", function(p, info, hitgroup)
    M.Record(p, info, hitgroup, "native")
end)
hook.Add("ScalePlayerDamage", "ZCHeadshotSlowmo_Engine", function(p, hitgroup, info)
    M.Record(p, info, hitgroup, "engine")
end)
hook.Add("DoPlayerDeath", "ZCHeadshotSlowmo_Death", M.OnDeath)
hook.Add("PlayerSpawn", "ZCHeadshotSlowmo_Life", function(p)
    if OverrideSpawn then return end
    M.pending[p] = nil; M.dead[p] = nil
end)
hook.Add("Org Clear", "ZCHeadshotSlowmo_Organism", function(org)
    if type(org) == "table" then M.ClearHit(org.owner) end
end)
hook.Add("PlayerDisconnected", "ZCHeadshotSlowmo_Disconnect", function(p) M.pending[p] = nil; M.dead[p] = nil end)
hook.Add("Think", "ZCHeadshotSlowmo_Clock", M.Tick)
hook.Add("ZB_EndRound", "ZCHeadshotSlowmo_End", M.Reset)
hook.Add("ZB_PreRoundStart", "ZCHeadshotSlowmo_Round", M.Reset)
hook.Add("PreCleanupMap", "ZCHeadshotSlowmo_Map", M.Reset)
hook.Add("ShutDown", "ZCHeadshotSlowmo_Stop", M.Reset)

concommand.Add("zc_headshot_slowmo_status", function(p)
    if IsValid(p) and not p:IsAdmin() then return end
    print("[HeadshotSlowmo]", M.Version, "enabled", enabled:GetBool(), "scale", game.GetTimeScale(),
        "active", M.active ~= nil, "kills", M.stats.kills, "pulses", M.stats.pulses, "coalesced", M.stats.coalesced,
        "extended", M.stats.extended, "added seconds", M.stats.extensionSeconds)
end, nil, "Admin: print headshot slow-motion status.")
