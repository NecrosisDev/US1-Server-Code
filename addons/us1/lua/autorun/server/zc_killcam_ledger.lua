-- Per-life killcam ledger: kills/hits/damage/points since each human's last real spawn, frozen at death so LifeH2H answers from a snapshot, never the live row (sv_life.lua's pack job runs 0.1-1.5 s+ after death).
if not SERVER then return end

local L = ZCKillcamLedger or {}
ZCKillcamLedger = L
L.Version = "20260924.ledger1"

-- PROVISIONAL(2026-09-24, FCVAR_ARCHIVE was not specified by the spec; matches the sibling killcam convars
-- (zc_killcam_points and friends) so a staff toggle survives a restart. ratify-by: 2026-10-24)
local ON = CreateConVar("zc_killcam_ledger", "0", FCVAR_ARCHIVE, "Killcam per-life ledger: 0 off, 1 on")
local function on() return ON:GetBool() end

L.rows = L.rows or {}         -- [sid64] = live per-life row
L.lastLife = L.lastLife or {} -- [victimSid64] = frozen snapshot from their last ZCKillcam_Death
L.stats = L.stats or {errors = 0, firstError = nil, hits = 0, deaths = 0}

local rows, lastLife, stats = L.rows, L.lastLife, L.stats

local function r1(n) return math.floor((tonumber(n) or 0) * 10 + 0.5) / 10 end

local function bumpErr(where, err)
    stats.errors = stats.errors + 1
    if not stats.firstError then
        stats.firstError = where .. ": " .. tostring(err)
        print("[Killcam] ledger error (" .. where .. "): " .. tostring(err))
    end
end

local function displayName(p)
    local K = rawget(_G, "ZCKillcam")
    if K and K.DisplayName then
        local ok, name = pcall(K.DisplayName, p)
        if ok and name then return name end
    end
    return (p.Nick and p:Nick()) or "?"
end

local function validHuman(p)
    return IsValid(p) and p.IsPlayer and p:IsPlayer() and not p:IsBot()
end

-- Lazily creates a fresh per-life row. Called at a real spawn, or (best-effort fallback) on a player's
-- first hit under tracking if the convar came on mid-life -- one allocation per player per life either way.
local function freshRow(sid, name)
    local combat, heal, heals, ref = 0, 0, 0, nil
    local K = rawget(_G, "ZCKillcam")
    local P = K and K.Points
    if P and P.round then
        ref = P.round
        local e = P.round[sid]
        if e then combat, heal, heals = e.combat or 0, e.heal or 0, e.heals or 0 end
    end
    return {
        sid = sid, name = name or "?", spawnAt = CurTime(),
        kills = 0, hits = 0, hitsTaken = 0, dealt = 0, taken = 0,
        vs = {}, lastHitTaken = nil,
        pointsAtSpawn = {combat = combat, heal = heal, heals = heals},
        pointsRoundRef = ref,
    }
end

local function ensureRow(sid, name)
    local row = rows[sid]
    if not row then
        row = freshRow(sid, name)
        rows[sid] = row
    elseif name then
        row.name = name
    end
    return row
end

local function vsEntry(row, oppSid)
    local e = row.vs[oppSid]
    if not e then
        e = {dealt = 0, hits = 0, taken = 0, hitsTaken = 0}
        row.vs[oppSid] = e
    end
    return e
end

-- Delta of the Points row between a row's spawn snapshot and now, clamped >= 0 per field, zeroed whole if
-- ZCKillcam.Points.round has been replaced (a new round) since the snapshot was taken.
local function pointsSnapshot(row)
    local K = rawget(_G, "ZCKillcam")
    local P = K and K.Points
    local combat, heal, heals = 0, 0, 0
    if P and P.round and row.pointsRoundRef == P.round then
        local e = P.round[row.sid] or {}
        combat = math.max(0, (e.combat or 0) - row.pointsAtSpawn.combat)
        heal = math.max(0, (e.heal or 0) - row.pointsAtSpawn.heal)
        heals = math.max(0, (e.heals or 0) - row.pointsAtSpawn.heals)
    end
    local zp = 0
    if P and P.Owed then
        local ok, v = pcall(P.Owed, {combat = combat, heal = heal})
        if ok and isnumber(v) then zp = v end
    end
    return {combat = combat, heal = heal, heals = heals, zp = zp}
end

local function lifeSnapshot(row)
    return {
        name = row.name,
        life = {
            kills = row.kills, hits = row.hits, hitsTaken = row.hitsTaken,
            dealt = r1(row.dealt), taken = r1(row.taken),
            alive = r1(CurTime() - row.spawnAt),
            points = pointsSnapshot(row),
        },
    }
end

-- ------------------------------------------------------------------- HomigradDamage: O(1) after the first
-- hit against a given opponent in a life; no allocation beyond that first touch.
-- Orchestrator review 2026-09-24: the body is a named function handed to pcall with its arguments (no closure built
-- per hit), and a display name is only resolved when a row is created (rowFor), not on every hit.
local function rowFor(p, sid)
    return rows[sid] or ensureRow(sid, displayName(p))
end
local function onHit(ply, dmgInfo, hitgroup, _, harm)
    local victim = ply
    if IsValid(victim) and not victim:IsPlayer() and hg and hg.RagdollOwner then victim = hg.RagdollOwner(victim) end
    local attacker = dmgInfo:GetAttacker()
    if not validHuman(victim) or not validHuman(attacker) or attacker == victim then return end
    local vsid, asid = victim:SteamID64(), attacker:SteamID64()
    if not vsid or not asid then return end
    local amount = tonumber(harm) or 0
    local vrow = rowFor(victim, vsid)
    local arow = rowFor(attacker, asid)
    vrow.hitsTaken = vrow.hitsTaken + 1
    vrow.taken = vrow.taken + amount
    arow.hits = arow.hits + 1
    arow.dealt = arow.dealt + amount
    local vvs = vsEntry(vrow, asid)
    vvs.taken = vvs.taken + amount
    vvs.hitsTaken = vvs.hitsTaken + 1
    local avs = vsEntry(arow, vsid)
    avs.dealt = avs.dealt + amount
    avs.hits = avs.hits + 1
    local wep = ""
    local w = attacker.GetActiveWeapon and attacker:GetActiveWeapon()
    if IsValid(w) then wep = w:GetClass() or "" end
    local lh = vrow.lastHitTaken
    if not lh then
        lh = {}
        vrow.lastHitTaken = lh
    end
    lh.attackerSid, lh.attackerName = asid, arow.name
    lh.weapon, lh.hitgroup, lh.at = wep, tonumber(hitgroup) or 0, CurTime()
    stats.hits = stats.hits + 1
end
hook.Add("HomigradDamage", "ZCKillcamLedger.Hit", function(ply, dmgInfo, hitgroup, ent, harm)
    if not on() then return end
    local ok, err = pcall(onHit, ply, dmgInfo, hitgroup, ent, harm)
    if not ok then bumpErr("HomigradDamage", err) end
end)

-- ------------------------------------------------------------------- real spawn: starts a new life. A
-- ragdoll get-up sets the global OverrideSpawn and fires PlayerSpawn mid-life -- ignore those.
hook.Add("PlayerSpawn", "ZCKillcamLedger.Spawn", function(ply)
    if not on() then return end
    local ok, err = pcall(function()
        if rawget(_G, "OverrideSpawn") then return end
        if not validHuman(ply) then return end
        local sid = ply:SteamID64()
        if not sid then return end
        rows[sid] = freshRow(sid, displayName(ply))
    end)
    if not ok then bumpErr("PlayerSpawn", err) end
end)

hook.Add("PlayerDisconnected", "ZCKillcamLedger.Disconnect", function(ply)
    if not on() then return end
    local ok, err = pcall(function()
        if not validHuman(ply) then return end
        local sid = ply:SteamID64()
        if not sid then return end
        rows[sid] = nil
        lastLife[sid] = nil
    end)
    if not ok then bumpErr("PlayerDisconnected", err) end
end)

-- ------------------------------------------------------------------- ZCKillcam_Death: freeze the life.
hook.Add("ZCKillcam_Death", "ZCKillcamLedger.Death", function(victim, killer, tag)
    if not on() then return end
    local ok, err = pcall(function()
        if not validHuman(victim) then return end
        local vsid = victim:SteamID64()
        if not vsid then return end
        local vrow = rows[vsid]
        if not vrow then return end -- never tracked this life; nothing to freeze

        local killerSid, killerName
        if killer and killer.id then
            killerSid, killerName = killer.id, killer.name or "?"
        elseif vrow.lastHitTaken then
            killerSid, killerName = vrow.lastHitTaken.attackerSid, vrow.lastHitTaken.attackerName
        end

        if killerSid then
            local krow = rows[killerSid]
            if krow then krow.kills = krow.kills + 1 end
        end

        local snap = {
            victimSid = vsid, killerSid = killerSid,
            victim = lifeSnapshot(vrow),
            killer = (killerSid and rows[killerSid]) and lifeSnapshot(rows[killerSid]) or nil,
        }

        if killerSid then
            local vs = vrow.vs[killerSid]
            snap.traded = {
                victimToKiller = {dmg = r1(vs and vs.dealt or 0), hits = vs and vs.hits or 0},
                killerToVictim = {dmg = r1(vs and vs.taken or 0), hits = vs and vs.hitsTaken or 0},
            }
        end

        local lh = vrow.lastHitTaken
        snap.how = {
            weapon = lh and lh.weapon or "", hitgroup = lh and lh.hitgroup or 0,
            by = killerName or "", ago = lh and r1(CurTime() - lh.at) or 0,
        }

        -- Orchestrator review 2026-09-24 (adversarial review): the pack job asking for this may run after the same
        -- player has died AGAIN (respawn modes, a busy queue), so the previous snapshot stays reachable one step
        -- back and each carries the CurTime() of its death - the same value sv_life.lua passes as `death` (both
        -- hooks run in the one ZCKillcam_Death dispatch).
        snap.at = CurTime()
        local before = lastLife[vsid]
        if before then before.prev = nil snap.prev = before end
        lastLife[vsid] = snap
        stats.deaths = stats.deaths + 1
    end)
    if not ok then bumpErr("ZCKillcam_Death", err) end
end)

-- ------------------------------------------------------------------- LifeH2H: read-only, answers from the
-- frozen snapshot alone -- the caller may run long after the death, possibly after a respawn, and `death`
-- (accepted for the caller's own convenience/future use) is never consulted: everything needed was already
-- frozen at ZCKillcam_Death.
local function lifeH2H(victimSid, death)
    if not on() then return nil end
    local snap = victimSid and lastLife[victimSid]
    if isnumber(death) then
        while snap and math.abs((snap.at or 0) - death) > 0.5 do snap = snap.prev end
    end
    if not snap then return nil end
    local lifetime = nil
    local LT = rawget(_G, "ZCKillcamLifetime")
    if LT and LT.Get then
        local ok1, vRow = pcall(LT.Get, snap.victimSid)
        local ok2, kRow = pcall(LT.Get, snap.killerSid)
        vRow = ok1 and vRow or nil
        kRow = (snap.killerSid and ok2) and kRow or nil
        if vRow or kRow then lifetime = {victim = vRow, killer = kRow} end
    end
    return {v = 1, victim = snap.victim, killer = snap.killer, traded = snap.traded, how = snap.how, lifetime = lifetime}
end

L.H2H = lifeH2H

local function installH2H()
    if rawget(_G, "ZCKillcam") then ZCKillcam.LifeH2H = lifeH2H end
end
installH2H()
hook.Add("InitPostEntity", "ZCKillcamLedger.InstallH2H", installH2H)

-- ------------------------------------------------------------------- boot receipt
local receipted = false
local function bootReceipt()
    if receipted then return end
    receipted = true
    file.CreateDir("zc_killcam")
    local line = os.date("%Y-%m-%d %H:%M:%S") .. " zc_killcam_ledger.lua version=" .. L.Version .. " on=" .. ON:GetInt() .. "\n"
    file.Append("zc_killcam/boot.txt", line)
    print("[Killcam] " .. line)
end
hook.Add("InitPostEntity", "ZCKillcamLedger.Boot", bootReceipt)
-- House idiom (zc_round_guard.lua): ULib loads after InitPostEntity on this host, so its presence signals a
-- late load (an autorefresh-style reload), not a fresh boot -- fire the receipt once immediately in that case.
if hook.GetULibTable then bootReceipt() end

-- ------------------------------------------------------------------- staff print concommand
local function reply(p, line)
    if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
end

local function looksLikeSid(s) return type(s) == "string" and s:match("^%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d?$") ~= nil end

local function findSid(needle)
    if looksLikeSid(needle) and (rows[needle] or lastLife[needle]) then return needle end
    local lower = string.lower(needle)
    for _, p in ipairs(player.GetHumans()) do
        if validHuman(p) then
            local nick = string.lower(p:Nick())
            if nick:find(lower, 1, true) then
                local sid = p:SteamID64()
                if sid then return sid end
            end
        end
    end
    for sid, row in pairs(rows) do
        if row.name and string.lower(row.name):find(lower, 1, true) then return sid end
    end
    return nil
end

local function fmtLife(life)
    return string.format("kills=%d hits=%d hitsTaken=%d dealt=%.1f taken=%.1f alive=%.1fs combat=%.1f heal=%.1f heals=%d zp=%d",
        life.kills, life.hits, life.hitsTaken, life.dealt, life.taken, life.alive,
        life.points.combat, life.points.heal, life.points.heals, life.points.zp)
end

concommand.Add("zc_killcam_ledger_print", function(p, _, args)
    if IsValid(p) and not p:IsAdmin() then return end
    local needle = args and args[1]
    if not needle or needle == "" then
        local n, m = 0, 0
        for _ in pairs(rows) do n = n + 1 end
        for _ in pairs(lastLife) do m = m + 1 end
        reply(p, string.format("[Killcam] ledger v=%s on=%d rows=%d lastLife=%d errors=%d", L.Version, ON:GetInt(), n, m, stats.errors))
        return
    end
    local sid = findSid(needle)
    if not sid then
        reply(p, "[Killcam] ledger: no match for '" .. needle .. "'")
        return
    end
    local row = rows[sid]
    if row then
        reply(p, string.format("[Killcam] ledger live %s (%s) spawned %.1fs ago: kills=%d hits=%d hitsTaken=%d dealt=%.1f taken=%.1f",
            row.name, sid, CurTime() - row.spawnAt, row.kills, row.hits, row.hitsTaken, r1(row.dealt), r1(row.taken)))
    else
        reply(p, "[Killcam] ledger: no live row for " .. sid)
    end
    local snap = lastLife[sid]
    if snap then
        reply(p, "[Killcam] lastLife victim " .. snap.victim.name .. ": " .. fmtLife(snap.victim.life))
        if snap.killer then reply(p, "[Killcam] lastLife killer " .. snap.killer.name .. ": " .. fmtLife(snap.killer.life)) end
        reply(p, string.format("[Killcam] lastLife how weapon=%s hitgroup=%d by=%s ago=%.1fs", snap.how.weapon, snap.how.hitgroup, snap.how.by, snap.how.ago))
        if snap.traded then
            reply(p, string.format("[Killcam] lastLife traded v->k dmg=%.1f hits=%d | k->v dmg=%.1f hits=%d",
                snap.traded.victimToKiller.dmg, snap.traded.victimToKiller.hits, snap.traded.killerToVictim.dmg, snap.traded.killerToVictim.hits))
        end
    else
        reply(p, "[Killcam] ledger: no lastLife for " .. sid)
    end
end)
