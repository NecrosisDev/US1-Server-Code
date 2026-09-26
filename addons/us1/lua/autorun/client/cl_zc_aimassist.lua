if not CLIENT then return end

-- ============================================================================
-- ZC Aim Assist (client) - accessibility aim help on PRIMARY FIRE.
--
-- Purpose: let players who struggle with fine mouse control take part in
-- firefights. Nothing happens until the player is already firing at someone
-- they can see, and every strength is a convar.
--
-- Two parts, both measured from the MUZZLE (where the bullet really goes,
-- the centre of the crosshair ring), not from the eyes:
--   friction : while firing (plus axs_zc_hold seconds after release), the
--              mouse turn is damped by axs_zc_friction when a body is inside
--              axs_zc_radius degrees of the barrel, fading to nothing at the edge.
--   nudge    : when a shot would narrowly miss a body, the shot is rotated just
--              far enough to land inside it: at most axs_zc_nudge degrees and
--              axs_zc_nudge_reach units of miss. Never when the shot already
--              hits someone, never toward the head, never through cover.
--              The server applies the same nudge authoritatively
--              (sv_zc_crosshair.lua); this copy keeps tracers and impacts on
--              the tester's screen matching the hits.
-- The view is never rotated toward a target.
--
-- SINGLE-CLIENT TEST LOCK: runs only for the SteamID64 in the server-only
-- axs_zc_tester convar; the server answers this client's zc_aimassist_hello
-- with zc_aimassist_grant (true only for the tester).
-- ============================================================================

ZC_AIMASSIST_VERSION = "20260925.6-test"

-- Convars exist only for the tester: they are created when the server's
-- grant arrives, so nobody else sees axs_zc_* in their console or Settings.
-- axs_zc, axs_zc_npc and the nudge pair are userinfo: the server reads them
-- (clamped to its own caps) for the authoritative nudge.
local cvOn, cvRadius, cvFriction, cvHold, cvNPC, cvNudge, cvReach
local function createConvars()
    if cvOn then return end
    cvOn       = CreateClientConVar("axs_zc", "1", true, true, "Helps land shots while you hold fire; your view is never moved for you", 0, 1)
    cvRadius   = CreateClientConVar("axs_zc_radius", "5", true, false, "How close to the barrel a target must be for friction, in degrees", 1, 15)
    cvFriction = CreateClientConVar("axs_zc_friction", "0.5", true, false, "How much your mouse slows while the barrel is on someone", 0, 0.9)
    cvHold     = CreateClientConVar("axs_zc_hold", "0.3", true, false, "Keeps the assist on briefly after you let go of fire", 0, 2)
    cvNPC      = CreateClientConVar("axs_zc_npc", "1", true, true, "Include NPCs as well as players", 0, 1)
    cvNudge    = CreateClientConVar("axs_zc_nudge", "1.5", true, true, "Largest turn given to a shot that would narrowly miss; 0 turns it off", 0, 3)
    cvReach    = CreateClientConVar("axs_zc_nudge_reach", "10", true, true, "Largest miss it will fix, measured at the target", 0, 16)
    concommand.Add("axs_zc_version", function()
        print("[axs_zc] client " .. ZC_AIMASSIST_VERSION .. " | active for tester")
    end)
end

local IsValid    = IsValid
local LocalPlayer = LocalPlayer
local CurTime    = CurTime
local math_clamp = math.Clamp
local math_sqrt  = math.sqrt
local math_abs   = math.abs
local math_acos  = math.acos
local math_rad   = math.rad
local angdiff    = math.AngleDifference
local player_GetAll = player.GetAll
local ents_FindByClass = ents.FindByClass
local util_TraceLine = util.TraceLine

-- ------------------------------------------------------------- test lock --
local granted = false
local function isTester()
    return granted
end

local registerSettings -- defined below; runs once the grant arrives

net.Receive("zc_aimassist_grant", function()
    granted = net.ReadBool()
    if granted then
        createConvars()
        if registerSettings then registerSettings() end
    end
end)

local function hello()
    -- the server file registers this name; until it has, stay silent (no error spam)
    if util.NetworkStringToID("zc_aimassist_hello") == 0 then return end
    net.Start("zc_aimassist_hello")
    net.SendToServer()
end
hook.Add("InitPostEntity", "ZC_AimAssist.Hello", hello)
if IsValid(LocalPlayer()) then hello() end -- file refreshed mid-session

-- --------------------------------------------------------------- helpers --
local function weaponIsGun(wep)
    if not IsValid(wep) or not wep.GetTrace or not wep.LocalMuzzlePos then return false end
    local ammo = wep.Primary and wep.Primary.Ammo
    return isstring(ammo) and ammo ~= "" and ammo ~= "none"
end

-- Only static geometry, props and doors block sight; bodies do not.
local function losFilter(ent)
    return not (ent:IsPlayer() or ent:IsNPC() or ent:IsRagdoll() or ent:IsNextBot() or ent:IsVehicle() or ent:IsWeapon())
end
local losTrace = { mask = MASK_VISIBLE, filter = losFilter }

-- Downed homigrad players live in their fake ragdoll.
local function bodyOf(ent)
    local rag = ent.FakeRagdoll
    return IsValid(rag) and rag or ent
end

local function candidateAlive(ent, me)
    if ent == me or not IsValid(ent) then return false end
    if ent:IsPlayer() then
        return ent:Alive()
    end
    return ent:Health() > 0
end

-- Friction aim point: upper spine when the model has it, else centre.
local function targetPoint(ent)
    local body = bodyOf(ent)
    local bone = body.LookupBone and body:LookupBone("ValveBiped.Bip01_Spine2")
    if bone then
        local pos = body:GetBonePosition(bone)
        if pos then return pos end
    end
    return body:WorldSpaceCenter()
end

-- Nearest visible target inside the cone around the barrel; returns the
-- target and its angular distance (deg), or nil.
local function findTarget(me, src, ang, radius, withNPC)
    local best, bestOff
    local function consider(ent)
        if not candidateAlive(ent, me) then return end
        local pos = targetPoint(ent)
        local dir = pos - src
        if dir:LengthSqr() < 1 then return end
        local tAng = dir:Angle()
        local dp = angdiff(tAng.p, ang.p)
        local dy = angdiff(tAng.y, ang.y)
        local off = math_sqrt(dp * dp + dy * dy)
        if off > radius or (bestOff and off >= bestOff) then return end
        losTrace.start = src
        losTrace.endpos = pos
        local t = util_TraceLine(losTrace)
        if t.Hit and t.Fraction < 0.97 then return end
        best, bestOff = ent, off
    end
    local plys = player_GetAll()
    for i = 1, #plys do consider(plys[i]) end
    if withNPC then
        local npcs = ents_FindByClass("npc_*")
        for i = 1, #npcs do consider(npcs[i]) end
    end
    return best, bestOff
end

-- ------------------------------------------------------------ shot nudge --
-- KEEP IN STEP with the copy in sv_zc_crosshair.lua (same geometry, same
-- limits); the server's copy is the one that decides hits.
-- { bone, radius, never nudge toward }. The head counts as "already hitting"
-- so a head-bound shot is left alone, but a miss is never pulled onto it.
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

-- Returns a corrected unit direction, or nil to leave the shot alone.
local function nudgeDir(shooter, src, dir, maxRad, maxUnits, withNPC)
    local best, bestAng, bestQ = nil, maxRad, nil
    local hitting = false

    -- sphere at c with radius R: true when the shot already passes through it
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
        local a = math_acos(math_clamp(nd:Dot(dir), -1, 1))
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

    local plys = player_GetAll()
    for i = 1, #plys do
        consider(plys[i])
        if hitting then return nil end
    end
    if withNPC then
        local npcs = ents_FindByClass("npc_*")
        for i = 1, #npcs do
            consider(npcs[i])
            if hitting then return nil end
        end
    end
    if not best then return nil end

    losTrace.start = src
    losTrace.endpos = bestQ
    local t = util_TraceLine(losTrace)
    if t.Hit and t.Fraction < 0.97 then return nil end
    return best
end

local function shooterOf(ent, data)
    if IsValid(ent) and ent:IsPlayer() then return ent end
    if IsValid(data.Attacker) and data.Attacker:IsPlayer() then return data.Attacker end
    if IsValid(ent) and ent.GetOwner then return ent:GetOwner() end
end

-- Mirror of the server nudge so this client's own tracers and impacts match.
-- No return value: returning anything would stop later hooks under ULib.
hook.Add("EntityFireBullets", "AXS_ZC.Nudge", function(ent, data)
    if not isTester() or not cvOn:GetBool() then return end
    if not data or not data.Dir or not data.Src then return end
    local me = LocalPlayer()
    if shooterOf(ent, data) ~= me then return end
    local deg, reach = cvNudge:GetFloat(), cvReach:GetFloat()
    if deg <= 0 or reach <= 0 then return end
    local dir = Vector(data.Dir)
    dir:Normalize()
    local ok, nd = pcall(nudgeDir, me, data.Src, dir, math_rad(deg), reach, cvNPC:GetBool())
    if ok and nd then data.Dir = nd end
end, HOOK_HIGH)

-- ---------------------------------------------------------------- state --
local lastP, lastY = nil, nil
local fireUntil = 0
ZC_AIMASSIST_WEIGHT = 0 -- 0..1, read by the crosshair for a visual cue

local function idle(ang)
    lastP, lastY = ang.p, ang.y
    ZC_AIMASSIST_WEIGHT = 0
end

hook.Add("CreateMove", "ZC_AimAssist.CreateMove", function(cmd)
    local ang = cmd:GetViewAngles()
    if not isTester() or not cvOn:GetBool() then idle(ang) return end

    local me = LocalPlayer()
    if not IsValid(me) or not me:Alive() then idle(ang) return end
    local wep = me:GetActiveWeapon()
    if not weaponIsGun(wep) then idle(ang) return end

    local now = CurTime()
    if cmd:KeyDown(IN_ATTACK) then fireUntil = now + cvHold:GetFloat() end
    if now > fireUntil then idle(ang) return end

    if lastP == nil then idle(ang) return end

    -- measure from the barrel: the muzzle trace is where the shot goes
    local src, aim = me:EyePos(), ang
    local okT, _, mpos, mang = pcall(wep.GetTrace, wep, nil, nil, nil, true)
    if okT and mpos and mang then src, aim = mpos, mang end

    local radius = cvRadius:GetFloat()
    local target, off = findTarget(me, src, aim, radius, cvNPC:GetBool())
    if not target then idle(ang) return end

    -- fade: 1 at the cone centre, 0 at the edge
    local w = math_clamp(1 - (off / radius) * (off / radius), 0, 1)
    ZC_AIMASSIST_WEIGHT = w

    -- friction: damp this command's mouse delta
    local fric = cvFriction:GetFloat() * w
    local p = math_clamp(lastP + angdiff(ang.p, lastP) * (1 - fric), -89, 89)
    local y = lastY + angdiff(ang.y, lastY) * (1 - fric)

    if math_abs(p - ang.p) > 0.0001 or math_abs(angdiff(y, ang.y)) > 0.0001 then
        ang.p, ang.y = p, y
        cmd:SetViewAngles(ang)
    end
    lastP, lastY = p, y
end)

-- ------------------------------------------------------------ settings UI --
registerSettings = function()
    if not isTester() then return end
    if not (hg and istable(hg.settings) and hg.settings.AddOpt) then return end
    local S = hg.settings
    -- { convar, title, two decimals? }; meta[8] is the position (GoobOS A.OrderedRows)
    local rows = {
        { "axs_zc", "Aim assist while firing" },
        { "axs_zc_nudge", "Shot correction", true },
        { "axs_zc_nudge_reach", "Shot correction reach" },
        { "axs_zc_friction", "Friction strength", true },
        { "axs_zc_radius", "Friction cone" },
        { "axs_zc_hold", "Hold after release", true },
        { "axs_zc_npc", "Also assist on NPCs" },
    }
    for i, row in ipairs(rows) do
        S:AddOpt("Accessibility", row[1], row[2], row[3] or false)
        S.tbl.Accessibility[row[1]][8] = i
    end
end
