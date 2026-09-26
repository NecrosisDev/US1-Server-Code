if not SERVER then return end

-- ============================================================================
-- ZC Crosshair (server) - hit-tick feed for cl_zc_crosshair.lua.
--
-- 2026-09-25: hit ticks go to every attacker. The aim-assist tester lock is
-- server-only: axs_zc_tester never replicates, and only the tester is
-- told (zc_aimassist_grant) that the assist is on for them.
--
-- Listens to the organism's HomigradDamage hook (sv_input.lua) and sends the
-- attacker ONE empty, unreliable net message per landed shot, rate-limited to
-- 20/s, and only when the attacker's eye has an unobstructed line to the
-- wound. Hits through walls or from behind cover give nothing; pellet counts,
-- kills and headshots are never sent. zc_crosshair_hits 0 turns it off for
-- everyone.
-- ============================================================================

ZC_CROSSHAIR_SV_VERSION = "20260925.5"

util.AddNetworkString("zc_crosshair_hit")
util.AddNetworkString("zc_aimassist_hello")
util.AddNetworkString("zc_aimassist_grant")

-- Server-only (no FCVAR_REPLICATED): clients never see who the tester is.
local cvTester = CreateConVar("axs_zc_tester", "76561198011536179", FCVAR_ARCHIVE, "SteamID64 that gets the accessibility aim assist (cl_zc_aimassist.lua); server only")
local cvHits = CreateConVar("zc_crosshair_hits", "1", FCVAR_ARCHIVE, "Send hit ticks to attackers for zc_crosshair (0 = off for everyone)", 0, 1)

local lastSent = setmetatable({}, { __mode = "k" })

-- Only static geometry, props and doors block the sight check; bodies,
-- ragdolls, vehicles and dropped weapons do not.
local function opaqueFilter(ent)
    return not (ent:IsPlayer() or ent:IsNPC() or ent:IsRagdoll() or ent:IsNextBot() or ent:IsVehicle() or ent:IsWeapon())
end

local tr = { mask = MASK_VISIBLE, filter = opaqueFilter }

hook.Add("HomigradDamage", "ZC_Crosshair.HitFeed", function(victim, dmgInfo)
    if not cvHits:GetBool() then return end
    if not IsValid(victim) or not dmgInfo then return end

    local attacker = dmgInfo:GetAttacker()
    if not IsValid(attacker) or not attacker:IsPlayer() or attacker == victim then return end

    local now = CurTime()
    if (lastSent[attacker] or 0) > now - 0.05 then return end

    local pos = dmgInfo:GetDamagePosition()
    if not pos or pos:IsZero() then pos = victim:WorldSpaceCenter() end

    tr.start = attacker:EyePos()
    tr.endpos = pos
    local t = util.TraceLine(tr)
    if t.Hit and t.Fraction < 0.97 then return end

    lastSent[attacker] = now
    net.Start("zc_crosshair_hit", true)
    net.Send(attacker)
end)

-- ------------------------------------------------------ aim-assist grant --
-- The client asks once its file has loaded (covers join, reconnect and a
-- mid-session file refresh); the answer goes to that player only.
local function sendGrant(ply)
    if not IsValid(ply) then return end
    net.Start("zc_aimassist_grant")
    net.WriteBool(ply:SteamID64() == cvTester:GetString())
    net.Send(ply)
end

local lastHello = setmetatable({}, { __mode = "k" })
net.Receive("zc_aimassist_hello", function(_, ply)
    local now = CurTime()
    if (lastHello[ply] or 0) > now - 2 then return end
    lastHello[ply] = now
    sendGrant(ply)
end)

cvars.AddChangeCallback("axs_zc_tester", function()
    for _, ply in ipairs(player.GetHumans()) do sendGrant(ply) end
end, "ZC_AimAssist.Grant")

-- ------------------------------------------------------ aim-assist nudge --
-- Authoritative half of the tester's shot correction (cl_zc_aimassist.lua has
-- the visual mirror; KEEP THE GEOMETRY IN STEP). When the tester's shot would
-- narrowly miss a body, rotate it just far enough to land inside: at most
-- axs_zc_nudge degrees / axs_zc_nudge_reach units (the tester's userinfo),
-- clamped here to axs_zc_nudge_max degrees and 16 units. Never when the shot
-- already hits someone, never toward the head, never through cover.
-- Runs at ULib HOOK_HIGH so the phys-bullet converter, the killcam recorder
-- and the watchdog all see the corrected shot. A correction of a degree or
-- two sits far below the watchdog's 20-degree silent-aim signatures.
local cvNudgeMax = CreateConVar("axs_zc_nudge_max", "3", FCVAR_ARCHIVE, "Server cap on the aim-assist shot correction, degrees (0 = off for everyone)", 0, 5)
local NUDGE_REACH_CAP = 16

local function losFilter(ent)
    return not (ent:IsPlayer() or ent:IsNPC() or ent:IsRagdoll() or ent:IsNextBot() or ent:IsVehicle() or ent:IsWeapon())
end
local losTrace = { mask = MASK_VISIBLE, filter = losFilter }

local NUDGE_BODY = {
    { "ValveBiped.Bip01_Head1", 4.5, true },
    { "ValveBiped.Bip01_Spine2", 8 },
    { "ValveBiped.Bip01_Spine", 7 },
    { "ValveBiped.Bip01_Pelvis", 7 },
    { "ValveBiped.Bip01_L_Thigh", 4.5 },
    { "ValveBiped.Bip01_R_Thigh", 4.5 },
    { "ValveBiped.Bip01_L_Calf", 3.5 },
    { "ValveBiped.Bip01_R_Calf", 3.5 },
}

local function bodyOf(ent)
    local rag = hg and hg.ragdollFake and hg.ragdollFake[ent]
    if not IsValid(rag) then rag = ent.FakeRagdoll end
    return IsValid(rag) and rag or ent
end

local function candidateAlive(ent, shooter)
    if ent == shooter or not IsValid(ent) then return false end
    if ent:IsPlayer() then return ent:Alive() end
    return ent:Health() > 0
end

local function nudgeDir(shooter, src, dir, maxRad, maxUnits, withNPC)
    local best, bestAng, bestQ = nil, maxRad, nil
    local hitting = false

    local function sphere(c, R, noNudge)
        local rel = c - src
        local t = rel:Dot(dir)
        if t < 16 then return false end
        local w = (src + dir * t) - c
        local m = w:Length()
        if m <= R then return true end
        if noNudge or m - R > maxUnits then return false end
        local q = c + w * (0.6 * R / m)
        local nd = q - src
        nd:Normalize()
        local a = math.acos(math.Clamp(nd:Dot(dir), -1, 1))
        if a < bestAng then best, bestAng, bestQ = nd, a, q end
        return false
    end

    local function consider(ent)
        if not candidateAlive(ent, shooter) then return end
        local body = bodyOf(ent)
        local found = false
        for i = 1, #NUDGE_BODY do
            local b = NUDGE_BODY[i]
            local bone = body.LookupBone and body:LookupBone(b[1])
            local c = bone and body:GetBonePosition(bone)
            if c then
                found = true
                if sphere(c, b[2], b[3]) then hitting = true return end
            end
        end
        if not found and sphere(body:WorldSpaceCenter(), 10, false) then hitting = true end
    end

    local plys = player.GetAll()
    for i = 1, #plys do
        consider(plys[i])
        if hitting then return nil end
    end
    if withNPC then
        local npcs = ents.FindByClass("npc_*")
        for i = 1, #npcs do
            consider(npcs[i])
            if hitting then return nil end
        end
    end
    if not best then return nil end

    losTrace.start = src
    losTrace.endpos = bestQ
    local t = util.TraceLine(losTrace)
    if t.Hit and t.Fraction < 0.97 then return nil end
    return best
end

local function shooterOf(ent, data)
    if IsValid(ent) and ent:IsPlayer() then return ent end
    if IsValid(data.Attacker) and data.Attacker:IsPlayer() then return data.Attacker end
    if IsValid(ent) and ent.GetOwner then return ent:GetOwner() end
end

-- No return value: under ULib a non-nil return would stop every later hook.
hook.Add("EntityFireBullets", "AXS_ZC.Nudge", function(ent, data)
    if not data or not data.Dir or not data.Src then return end
    local cap = cvNudgeMax:GetFloat()
    if cap <= 0 then return end
    local ply = shooterOf(ent, data)
    if not (IsValid(ply) and ply:IsPlayer()) or ply:SteamID64() ~= cvTester:GetString() then return end
    if ply:GetInfoNum("axs_zc", 1) == 0 then return end
    local deg = math.Clamp(ply:GetInfoNum("axs_zc_nudge", 1.5), 0, cap)
    local reach = math.Clamp(ply:GetInfoNum("axs_zc_nudge_reach", 10), 0, NUDGE_REACH_CAP)
    if deg <= 0 or reach <= 0 then return end

    local dir = Vector(data.Dir)
    dir:Normalize()
    -- judge against the positions the shooter saw, unless the pellet volley
    -- already opened lag compensation for this shot
    local volley = data.__ZCVolley
    local comp = not (volley and volley.lagCompensated)
    if comp then ply:LagCompensation(true) end
    local ok, nd = pcall(nudgeDir, ply, data.Src, dir, math.rad(deg), reach, ply:GetInfoNum("axs_zc_npc", 1) ~= 0)
    if comp then ply:LagCompensation(false) end
    if ok and nd then data.Dir = nd end
end, HOOK_HIGH)

concommand.Add("zc_crosshair_sv_version", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    print("[zc_crosshair] server " .. ZC_CROSSHAIR_SV_VERSION .. " | aim-assist tester " .. cvTester:GetString())
end, nil, "Admin: print the crosshair server version and aim-assist tester.")
