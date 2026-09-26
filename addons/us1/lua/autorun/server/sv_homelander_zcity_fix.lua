-- Homelander SWEP + ZCity Compatibility Fix
-- - Dismemberment via hg.organism.AmputateLimb
-- - Head explode via hg.ExplodeHead
-- - Invulnerability + keep-alive
-- - Disables SWEP's broken grab; adds crusher-style ZCity-native grab
if not SERVER then return end

local HOMELANDER_CLASS = "weapon_homelander"

local function IsHomelander(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return false end
    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) then return false end
    return wep:GetClass() == HOMELANDER_CLASS
end

-- =========================================================================
-- DISMEMBERMENT VIA AMPUTATE
-- =========================================================================

local BONE_TO_AMPUTATE = {
    ["ValveBiped.Bip01_R_UpperArm"] = "rarm",
    ["ValveBiped.Bip01_R_Forearm"]  = "rarm",
    ["ValveBiped.Bip01_R_Hand"]     = "rarm",
    ["ValveBiped.Bip01_L_UpperArm"] = "larm",
    ["ValveBiped.Bip01_L_Forearm"]  = "larm",
    ["ValveBiped.Bip01_L_Hand"]     = "larm",
    ["ValveBiped.Bip01_R_Thigh"]    = "rleg",
    ["ValveBiped.Bip01_R_Calf"]     = "rleg",
    ["ValveBiped.Bip01_R_Foot"]     = "rleg",
    ["ValveBiped.Bip01_L_Thigh"]    = "lleg",
    ["ValveBiped.Bip01_L_Calf"]     = "lleg",
    ["ValveBiped.Bip01_L_Foot"]     = "lleg",
}

local HEAD_BONES = {
    ["ValveBiped.Bip01_Head1"] = true,
    ["ValveBiped.Bip01_Neck1"] = true,
}

local function GetClosestLimb(ent, hitPos)
    if not IsValid(ent) then return nil, nil end
    local closestLimb, closestBone, isHead, closestDist = nil, nil, false, math.huge

    for boneName, limb in pairs(BONE_TO_AMPUTATE) do
        local boneIdx = ent:LookupBone(boneName)
        if boneIdx then
            local bonePos = ent:GetBonePosition(boneIdx)
            if bonePos then
                local d = bonePos:Distance(hitPos)
                if d < closestDist then
                    closestDist = d
                    closestLimb = limb
                    closestBone = boneIdx
                    isHead = false
                end
            end
        end
    end

    for boneName, _ in pairs(HEAD_BONES) do
        local boneIdx = ent:LookupBone(boneName)
        if boneIdx then
            local bonePos = ent:GetBonePosition(boneIdx)
            if bonePos then
                local d = bonePos:Distance(hitPos)
                if d < closestDist then
                    closestDist = d
                    closestLimb = nil
                    closestBone = boneIdx
                    isHead = true
                end
            end
        end
    end

    return closestLimb, closestBone, isHead
end

local function HomelanderLaserHit(target, hitPos, attacker)
    if not IsValid(target) then return end

    local org = target.organism
    local ragdoll = nil  -- track the ragdoll for chest cut
    if not org and target:GetClass() == "prop_ragdoll" then
        ragdoll = target
        local owner = target.ply or target:GetNWEntity("OwningPlayer")
        if not IsValid(owner) and hg and hg.RagdollOwner then
            owner = hg.RagdollOwner(target)
        end
        if not IsValid(owner) then
            for _, p in player.Iterator() do
                if p:GetRagdollEntity() == target then owner = p break end
                if hg and hg.GetCurrentCharacter and hg.GetCurrentCharacter(p) == target then owner = p break end
            end
        end
        if IsValid(owner) and owner.organism then
            org = owner.organism
            target = owner  -- damage the owner for kill
        end
    end

    local limb, bone, isHead = GetClosestLimb(target, hitPos)
    local hitChest = (limb == nil and not isHead and bone) -- closest was a chest bone but our function only returned isHead for head
    
    -- Manually re-detect chest hits
    local chestBones = {
        ["ValveBiped.Bip01_Spine"]   = true,
        ["ValveBiped.Bip01_Spine1"]  = true,
        ["ValveBiped.Bip01_Spine2"]  = true,
        ["ValveBiped.Bip01_Spine4"]  = true,
        ["ValveBiped.Bip01_Pelvis"]  = true,
    }
    local isChest = false
    if not limb and not isHead then
        -- Check if it was a chest bone
        local minDist = math.huge
        local closestChestBone = nil
        for boneName, _ in pairs(chestBones) do
            local boneIdx = (ragdoll or target):LookupBone(boneName)
            if boneIdx then
                local bonePos = (ragdoll or target):GetBonePosition(boneIdx)
                if bonePos then
                    local d = bonePos:Distance(hitPos)
                    if d < minDist then
                        minDist = d
                        closestChestBone = boneIdx
                    end
                end
            end
        end
        if closestChestBone and minDist < 30 then
            isChest = true
            bone = closestChestBone
        end
    end

    if limb and org and hg and hg.organism and hg.organism.AmputateLimb then
        if not org[limb .. "amputated"] then
            hg.organism.AmputateLimb(org, limb)
        end
    end

    if org then
        if isHead then
            if hg and hg.ExplodeHead then
                hg.ExplodeHead(target)
            else
                org.skull = 1
                org.brain = 1
                org.consciousness = 0
                org.otrub = true
                org.pulse = 0
            end
        elseif isChest then
            -- TORSO CUT: kill them then cut their death ragdoll at the waist
            if target.organism then
                target.organism.chest = 1
                target.organism.heart = 1
                target.organism.skull = 1
                target.organism.brain = 1
                target.organism.consciousness = 0
                target.organism.otrub = true
            end
            if target:IsPlayer() and target:Alive() then
                target:Kill()
            end

            -- Cut the ragdoll at the spine after death ragdoll is created
            timer.Simple(0.1, function()
                local rd = ragdoll
                if not IsValid(rd) and IsValid(target) then
                    rd = target:GetNWEntity("RagdollDeath")
                    if not IsValid(rd) and target.IsRagdoll and target:IsRagdoll() then
                        rd = target
                    end
                end
                if not IsValid(rd) then return end

                -- Break constraints at spine to cut ragdoll in half
                local cutBones = {
                    "ValveBiped.Bip01_Spine1",
                    "ValveBiped.Bip01_Spine2",
                }
                for _, boneName in ipairs(cutBones) do
                    local b = rd:LookupBone(boneName)
                    if b then
                        local pbIdx = rd:TranslateBoneToPhysBone(b)
                        if pbIdx >= 0 then
                            pcall(function() rd:RemoveInternalConstraint(pbIdx) end)
                        end
                    end
                end

                -- Mark as cut to prevent re-processing
                rd.HomelanderTorsoCut = true
            end)
        end

        if hg and hg.organism and hg.organism.AddWoundManual and bone then
            local woundCount = isChest and 8 or 3
            local bleed = isChest and 400 or 150
            for i = 1, woundCount do
                hg.organism.AddWoundManual(target, bleed, vector_origin, angle_zero, bone, CurTime() + math.Rand(0, 2))
            end
        end
    end
end

-- =========================================================================
-- INVULNERABILITY + KEEP ALIVE
-- =========================================================================

hook.Add("EntityTakeDamage", "Homelander_Invulnerable", function(ent, dmgInfo)
    if not IsValid(ent) or not ent:IsPlayer() then return end
    if IsHomelander(ent) then
        dmgInfo:SetDamage(0)
        return true
    end
end)

hook.Add("PreHomigradDamageBulletBleedAdd", "Homelander_BlockBleed", function(info)
    if info and info.ent and IsHomelander(info.ent) then
        info.restricted = true
    end
end)

timer.Create("Homelander_KeepAlive", 0.25, 0, function()
    for _, ply in player.Iterator() do
        if IsHomelander(ply) and ply:Alive() then
            if ply:Health() < 100 then ply:SetHealth(100) end
            if ply.organism then
                local org = ply.organism
                org.blood = 5000
                org.bleed = 0
                org.pain = 0
                org.skull = 0
                org.brain = 0
                org.shock = 0
                org.consciousness = 1
                org.otrub = false
                org.heart = 0
                org.pulse = 70
                org.burns = 0
                org.bulletwounds = 0
                org.explosionwounds = 0
                if org.wounds then table.Empty(org.wounds) end
            end
        end
    end
end)

-- =========================================================================
-- LASER TRACE
-- =========================================================================

local TRACE_RANGE = 8192
local lastHitOnVictim = {}

timer.Create("Homelander_LaserTrace", 0.1, 0, function()
    for _, ply in player.Iterator() do
        if not IsHomelander(ply) then continue end
        if not ply:Alive() then continue end
        if not ply:KeyDown(IN_ATTACK2) then continue end

        local trace = util.TraceLine({
            start = ply:EyePos(),
            endpos = ply:EyePos() + ply:GetAimVector() * TRACE_RANGE,
            filter = ply,
            mask = MASK_SHOT
        })

        if not IsValid(trace.Entity) then continue end
        local target = trace.Entity

        if (lastHitOnVictim[target:EntIndex()] or 0) + 0.3 > CurTime() then continue end
        lastHitOnVictim[target:EntIndex()] = CurTime()

        if target:IsPlayer() and target ~= ply and not IsHomelander(target) then
            HomelanderLaserHit(target, trace.HitPos, ply)
        elseif target:GetClass() == "prop_ragdoll" then
            HomelanderLaserHit(target, trace.HitPos, ply)
            local dir = (trace.HitPos - ply:EyePos()):GetNormalized()
            for i = 0, target:GetPhysicsObjectCount() - 1 do
                local phys = target:GetPhysicsObjectNum(i)
                if IsValid(phys) then
                    phys:ApplyForceCenter(dir * 2500)
                end
            end
        end
    end
end)

-- =========================================================================
-- DISABLE SWEP GRAB MODE - patch IsHomelanderGrabMode/SetHomelanderMode
-- =========================================================================

-- Run after the SWEP definition has loaded
hook.Add("InitPostEntity", "Homelander_DisableSwepGrab", function()
    local wepBase = weapons.GetStored(HOMELANDER_CLASS)
    if not wepBase then return end

    -- Make grab mode check always return false
    wepBase.IsHomelanderGrabMode = function(self) return false end

    -- Disable strong punch check too
    wepBase.IsHomelanderStrongPunchMode = function(self) return false end

    -- Lock mode cycle to mode 0 only (normal punch)
    local oldSetMode = wepBase.SetHomelanderMode
    wepBase.SetHomelanderMode = function(self, mode)
        if not SERVER then return end
        self:SetNW2Int("HomelanderMode", 0)
        self:SetHomelanderNW2Bool("HomelanderStrongPunch", false)
    end

    -- Disable flight lunge (causes physics crashes)
    wepBase.DoHomelanderFlightLunge = function(self) end

    print("[Homelander ZCity Fix] Disabled SWEP grab + strong punch + flight lunge")
end)

-- =========================================================================
-- PUNCH DAMAGE - intercept and translate to ZCity organism damage
-- =========================================================================
hook.Add("EntityTakeDamage", "Homelander_PunchToZCity", function(ent, dmgInfo)
    if not IsValid(ent) or not ent:IsPlayer() then return end
    if not ent.organism then return end

    local attacker = dmgInfo:GetAttacker()
    if not IsValid(attacker) or not attacker:IsPlayer() then return end
    if attacker == ent then return end
    if not IsHomelander(attacker) then return end
    if IsHomelander(ent) then return end -- can't damage other Homelanders

    -- Check if this is a club/crush type damage (punch)
    if not (dmgInfo:IsDamageType(DMG_CLUB) or dmgInfo:IsDamageType(DMG_CRUSH)) then return end

    local hitPos = dmgInfo:GetDamagePosition()
    if not hitPos or hitPos == vector_origin then hitPos = ent:GetPos() + ent:OBBCenter() end

    local limb, bone, isHead = GetClosestLimb(ent, hitPos)
    local org = ent.organism

    -- Strong punch: dismember the hit limb instantly via blunt force
    if limb and org and hg and hg.organism and hg.organism.AmputateLimb then
        if not org[limb .. "amputated"] then
            hg.organism.AmputateLimb(org, limb)
        end
    end

    if org then
        if isHead then
            if hg and hg.ExplodeHead then
                hg.ExplodeHead(ent)
            else
                org.skull = 1
                org.brain = 1
                org.consciousness = 0
                org.otrub = true
            end
        end

        if hg and hg.organism and hg.organism.AddWoundManual and bone then
            for i = 1, 3 do
                hg.organism.AddWoundManual(ent, 200, vector_origin, angle_zero, bone, CurTime() + math.Rand(0, 2))
            end
        end
    end

    -- Apply knockback force
    local dir = (ent:GetPos() - attacker:GetPos()):GetNormalized()
    ent:SetVelocity(dir * 1500 + Vector(0, 0, 400))
end)

-- =========================================================================
-- CUSTOM ZCITY-NATIVE GRAB SYSTEM
-- Modeled on crusher_standalone.lua but tied to Homelander SWEP
-- =========================================================================

util.AddNetworkString("HomelanderGrab_Victim")

-- Get bone position helper (works with player or ragdoll)
local function GetBonePos(ent, boneName)
    if not IsValid(ent) then return nil end
    local boneIdx = ent:LookupBone(boneName)
    if not boneIdx then return nil end
    return ent:GetBonePosition(boneIdx)
end

-- The grab state per Homelander player
-- ply.HomelanderGrab = { Victim = entity, Progress = 0..1, StartTime = number }

local GRAB_RANGE = 80
local GRAB_TIME = 1.5  -- seconds to fully grab

local function StartGrab(ply, victim)
    if not IsValid(victim) or not victim:Alive() then return end
    if victim.HomelanderGrabbedBy then return end
    if ply.HomelanderGrab then return end

    -- Use ZCity's native Fake function to ragdoll the player
    if hg and hg.Fake then
        hg.Fake(victim)
    end

    ply.HomelanderGrab = {
        Victim = victim,
        StartTime = CurTime(),
    }
    victim.HomelanderGrabbedBy = ply

    ply:EmitSound("physics/body/body_medium_impact_hard1.wav", 80, 100)

    -- Try to attach carry to the ragdoll once it exists (retry several times)
    local attempts = 0
    local function TryCarry()
        if not IsValid(ply) or not IsValid(victim) or not ply.HomelanderGrab then return end
        local rag = victim.FakeRagdoll
        local bone = IsValid(rag) and rag:LookupBone("ValveBiped.Bip01_Head1")
        local phys = bone and rag:GetPhysicsObjectNum(rag:TranslateBoneToPhysBone(bone))

        if IsValid(rag) and bone and IsValid(phys) then
            local dist = 25
            hg.SetCarryEnt2(
                ply, rag, bone, phys:GetMass(),
                Vector(-2, 0, 0),
                ply:GetAimVector() * dist
                + ply:EyeAngles():Up() * 5
                + ply:EyeAngles():Right() * -5
                + ply:GetShootPos(),
                ply:EyeAngles() + Angle(-90, 90, 0)
            )
            return
        end

        attempts = attempts + 1
        if attempts < 20 then
            timer.Simple(0, TryCarry)
        end
    end
    timer.Simple(0, TryCarry)
end

local function ReleaseGrab(ply, killed)
    if not ply.HomelanderGrab then return end

    local victim = ply.HomelanderGrab.Victim

    -- Stop carrying (no args - just clears it)
    if hg and hg.RemoveCarryEnt2 then
        hg.RemoveCarryEnt2(ply)
    end

    if IsValid(victim) then
        victim.HomelanderGrabbedBy = nil
        victim.BeingVictimOfNeckBreak = false

        -- Bring them back up (unless we killed them)
        if not killed and victim:Alive() and hg and hg.FakeUp then
            hg.FakeUp(victim)
        end
    end

    ply.HomelanderGrab = nil
end

-- Crush head (use input_list.brain/skull to kill via head)
local function CrushHead(ply)
    if not ply.HomelanderGrab then return end
    local victim = ply.HomelanderGrab.Victim
    if not IsValid(victim) or not victim:Alive() then ReleaseGrab(ply) return end

    -- Use hg.ExplodeHead for proper head dismemberment
    if hg and hg.ExplodeHead then
        hg.ExplodeHead(victim)
    elseif victim.organism then
        victim.organism.skull = 1
        victim.organism.brain = 1
        if victim:IsPlayer() then victim:Kill() end
    end

    victim:EmitSound("npc/zombie/zombie_pound_door.wav", 100, 80)
    ply:EmitSound("physics/flesh/flesh_impact_bullet1.wav", 100, 80)

    ReleaseGrab(ply, true)
end

-- Break neck (kill + spine fracture animation)
local function BreakNeck(ply)
    if not ply.HomelanderGrab then return end
    local victim = ply.HomelanderGrab.Victim
    if not IsValid(victim) or not victim:Alive() then ReleaseGrab(ply) return end

    -- Set organism spine damage and kill
    if victim.organism then
        victim.organism.spine3 = 1
        victim.organism.spine2 = 1
    end
    if victim:IsPlayer() then victim:Kill() end

    victim:EmitSound("neck_snap_01.wav", 80, 100, 1, CHAN_AUTO)

    -- Apply ragdoll spine break (after death ragdoll created)
    timer.Simple(0.1, function()
        if not IsValid(victim) then return end
        local rd = victim:GetNWEntity("RagdollDeath")
        if not IsValid(rd) then return end

        local headBone = rd:LookupBone("ValveBiped.Bip01_Head1")
        if not headBone then return end
        rd:RemoveInternalConstraint(rd:TranslateBoneToPhysBone(headBone))
    end)

    ReleaseGrab(ply, true)
end

-- ALT + E starts grab; if already grabbing, the SWEP just holds the victim
-- Crush key and neckbreak key handle finishers
hook.Add("KeyPress", "Homelander_GrabKey", function(ply, key)
    if not IsHomelander(ply) then return end
    if not ply:Alive() then return end

    -- ALT + E to start grab
    if key == IN_USE and ply:KeyDown(IN_WALK) then
        if ply.HomelanderGrab then
            ReleaseGrab(ply)
            return
        end

        local trace = util.TraceLine({
            start = ply:EyePos(),
            endpos = ply:EyePos() + ply:GetAimVector() * GRAB_RANGE,
            filter = ply,
            mask = MASK_SHOT,
        })

        if IsValid(trace.Entity) and trace.Entity:IsPlayer() and trace.Entity ~= ply
            and not IsHomelander(trace.Entity) then
            StartGrab(ply, trace.Entity)
        end
    end
end)

-- Console commands for crush/neckbreak (matches crusher binds: [ and ])
concommand.Add("crusher_crush", function(ply)
    if not IsHomelander(ply) then return end
    CrushHead(ply)
end)

concommand.Add("+crusher_neckbreak", function(ply)
    if not IsHomelander(ply) then return end
    BreakNeck(ply)
end)

concommand.Add("-crusher_neckbreak", function() end)

-- Additional binds specifically for Homelander
concommand.Add("homelander_crush", function(ply)
    if not IsHomelander(ply) then return end
    CrushHead(ply)
end)

concommand.Add("homelander_neckbreak", function(ply)
    if not IsHomelander(ply) then return end
    BreakNeck(ply)
end)

-- Manage grab state - only handles laser kill (positioning is handled by hg.SetCarryEnt2)
hook.Add("Think", "Homelander_GrabHold", function()
    for _, ply in player.Iterator() do
        if not IsHomelander(ply) then continue end
        local grab = ply.HomelanderGrab
        if not grab then continue end

        local victim = grab.Victim
        if not IsValid(victim) or not victim:Alive() then
            ReleaseGrab(ply)
            continue
        end

        local ragdoll = victim.FakeRagdoll
        if not IsValid(ragdoll) then
            ReleaseGrab(ply)
            continue
        end

        -- If holding RMB (laser), blast their head off
        if ply:KeyDown(IN_ATTACK2) then
            grab.LaserChargeTime = (grab.LaserChargeTime or 0) + FrameTime()
            if grab.LaserChargeTime >= 0.3 then
                if hg and hg.ExplodeHead then
                    hg.ExplodeHead(victim)
                elseif victim.organism then
                    victim.organism.skull = 1
                    victim.organism.brain = 1
                    if victim:IsPlayer() then victim:Kill() end
                end
                victim:EmitSound("ambient/energy/zap" .. math.random(1, 3) .. ".wav", 100, 90)
                ply:EmitSound("ambient/energy/whiteflash.wav", 80, 100)
                ReleaseGrab(ply, true)
            end
        else
            grab.LaserChargeTime = 0
        end
    end
end)

-- Cleanup on disconnect/death
hook.Add("PlayerDeath", "Homelander_GrabCleanup", function(ply)
    if ply.HomelanderGrab then ReleaseGrab(ply) end
    if ply.HomelanderGrabbedBy and IsValid(ply.HomelanderGrabbedBy) then
        ReleaseGrab(ply.HomelanderGrabbedBy)
    end
end)

hook.Add("PlayerDisconnected", "Homelander_GrabCleanup", function(ply)
    if ply.HomelanderGrab then ReleaseGrab(ply) end
    if ply.HomelanderGrabbedBy and IsValid(ply.HomelanderGrabbedBy) then
        ReleaseGrab(ply.HomelanderGrabbedBy)
    end
end)

hook.Add("PlayerSwitchWeapon", "Homelander_GrabCleanup", function(ply, oldWep, newWep)
    if IsValid(oldWep) and oldWep:GetClass() == HOMELANDER_CLASS and ply.HomelanderGrab then
        ReleaseGrab(ply)
    end
end)

-- =========================================================================
-- STOMP ABILITY (same as crusher) - kick downward to crush limbs
-- =========================================================================

local STOMP_BONE_TO_LIMB = {
    ["ValveBiped.Bip01_Head1"]      = function(org, ent) if not ent.noHead then hg.ExplodeHead(ent) end end,
    ["ValveBiped.Bip01_Pelvis"]     = function(org, ent) org.spine1 = 1 end,
    ["ValveBiped.Bip01_Spine2"]     = function(org, ent) org.spine2 = 1 end,
    ["ValveBiped.Bip01_R_UpperArm"] = function(org) if not org.rarmamputated then hg.organism.AmputateLimb(org, "rarm") end end,
    ["ValveBiped.Bip01_R_Forearm"]  = function(org) if not org.rarmamputated then hg.organism.AmputateLimb(org, "rarm") end end,
    ["ValveBiped.Bip01_R_Hand"]     = function(org) if not org.rarmamputated then hg.organism.AmputateLimb(org, "rarm") end end,
    ["ValveBiped.Bip01_L_UpperArm"] = function(org) if not org.larmamputated then hg.organism.AmputateLimb(org, "larm") end end,
    ["ValveBiped.Bip01_L_Forearm"]  = function(org) if not org.larmamputated then hg.organism.AmputateLimb(org, "larm") end end,
    ["ValveBiped.Bip01_L_Hand"]     = function(org) if not org.larmamputated then hg.organism.AmputateLimb(org, "larm") end end,
    ["ValveBiped.Bip01_R_Thigh"]    = function(org) if not org.rlegamputated then hg.organism.AmputateLimb(org, "rleg") end end,
    ["ValveBiped.Bip01_R_Calf"]     = function(org) if not org.rlegamputated then hg.organism.AmputateLimb(org, "rleg") end end,
    ["ValveBiped.Bip01_R_Foot"]     = function(org) if not org.rlegamputated then hg.organism.AmputateLimb(org, "rleg") end end,
    ["ValveBiped.Bip01_L_Thigh"]    = function(org) if not org.llegamputated then hg.organism.AmputateLimb(org, "lleg") end end,
    ["ValveBiped.Bip01_L_Calf"]     = function(org) if not org.llegamputated then hg.organism.AmputateLimb(org, "lleg") end end,
    ["ValveBiped.Bip01_L_Foot"]     = function(org) if not org.llegamputated then hg.organism.AmputateLimb(org, "lleg") end end,
}

local function ApplyHomelanderStompLimbDamage(ply)
    if not IsValid(ply) or not ply:Alive() then return end

    local ang        = ply:EyeAngles()
    local inDuck     = ply:KeyDown(IN_DUCK) or ply:Crouching()
    ang[1]           = inDuck and 0 or math.max(ang[1], 10)

    local reportPos  = ply:GetPos() + ply:OBBCenter() + ply:GetUp() * (-5)
    local traceStart = inDuck and reportPos or ply:EyePos()
    local rad        = Vector(5, 5, 5)

    local tr = util.TraceHull({
        start  = traceStart,
        endpos = traceStart + ang:Forward() * 90,
        filter = { ply, hg and hg.GetCurrentCharacter and hg.GetCurrentCharacter(ply) or nil },
        mins   = -rad,
        maxs   = rad,
    })

    local ragdoll, hit_bonename

    if tr.Hit and IsValid(tr.Entity) and tr.Entity:IsRagdoll() then
        ragdoll      = tr.Entity
        hit_bonename = ragdoll:GetBoneName(ragdoll:TranslatePhysBoneToBone(tr.PhysicsBone or 0))
    else
        local feet   = ply:GetPos() + Vector(0, 0, 5)
        local best_d = 120 ^ 2
        for _, ent in ipairs(ents.FindInSphere(ply:GetPos(), 120)) do
            if not ent:IsRagdoll() then continue end
            if not IsValid(ent.ply) or not ent.ply:Alive() then continue end
            for i = 0, ent:GetPhysicsObjectCount() - 1 do
                local phys = ent:GetPhysicsObjectNum(i)
                if not IsValid(phys) then continue end
                local d = phys:GetPos():DistToSqr(feet)
                if d < best_d then
                    best_d       = d
                    ragdoll      = ent
                    hit_bonename = ent:GetBoneName(ent:TranslatePhysBoneToBone(i))
                end
            end
        end
    end

    if not IsValid(ragdoll) then return end
    local victim = ragdoll.ply
    if not IsValid(victim) or not victim:Alive() or not victim.organism then return end

    local limbFunc = STOMP_BONE_TO_LIMB[hit_bonename] or STOMP_BONE_TO_LIMB["ValveBiped.Bip01_R_Calf"]
    limbFunc(victim.organism, victim)
end

local function ApplyHomelanderBlastDoor(ply)
    local tr = util.TraceHull({
        start  = ply:EyePos(),
        endpos = ply:EyePos() + ply:EyeAngles():Forward() * 90,
        filter = { ply, hg and hg.GetCurrentCharacter and hg.GetCurrentCharacter(ply) or nil },
        mins   = -Vector(5, 5, 5),
        maxs   = Vector(5, 5, 5),
    })
    if tr.Hit and IsValid(tr.Entity) and hgIsDoor and hgIsDoor(tr.Entity) then
        if hgBlastThatDoor then
            hgBlastThatDoor(tr.Entity, ply:GetAimVector() * 250)
        end
    end
end

hook.Add("PlayerPostThink", "Homelander_StompAbility", function(ply)
    if not IsHomelander(ply) then return end
    if not ply:Alive() then return end

    local kicking = (ply.InLegKick or 0) > CurTime()
    if kicking and not ply.HomelanderStompScheduled then
        ply.HomelanderStompScheduled = true
        if ply:EyeAngles()[1] >= 20 then
            -- Looking down - stomp limb
            timer.Simple(0.33, function()
                if IsValid(ply) then ApplyHomelanderStompLimbDamage(ply) end
            end)
        else
            -- Looking forward - blast door
            timer.Simple(0.33, function()
                if IsValid(ply) then ApplyHomelanderBlastDoor(ply) end
            end)
        end
    elseif not kicking then
        ply.HomelanderStompScheduled = false
    end
end)
print("[Homelander ZCity Fix] Loaded - AmputateLimb + grab + stomp")
