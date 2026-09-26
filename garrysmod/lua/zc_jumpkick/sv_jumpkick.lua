-- Nativized 2026-09-24 from addons/pat's_jump_kick/lua/autorun/server/sv_pat_jumpkick.lua (verbatim minus its own
-- AddCSLuaFile/include lines, which the loader now does). Loaded by lua/autorun/zc_jumpkick.lua, server only.

local addon = PAT_JumpKick
local kickProbeHull = Vector(18, 18, 20)
local kickConfirmHull = Vector(12, 12, 12)
local wallSlamHull = Vector(14, 14, 28)

local function getCurrentCharacter(ply)
    if not hg or not hg.GetCurrentCharacter then
        return nil
    end

    return hg.GetCurrentCharacter(ply)
end

local function currentCharacterIsRagdoll(ply)
    local character = getCurrentCharacter(ply)
    return IsValid(character) and character.IsRagdoll and character:IsRagdoll()
end

local function getHandsWeapon(ply)
    local class, wep = addon:GetHandsWeapon(ply)

    if IsValid(wep) then
        return class, wep
    end

    return class, ply:GetActiveWeapon()
end

local function clearImpactWindow(ply)
    ply.PAT_JumpKickImpactStart = nil
    ply.PAT_JumpKickImpactEnd = nil
    ply.PAT_JumpKickDidImpact = nil
end

local function clearState(ply)
    if not IsValid(ply) then
        return
    end

    ply.PAT_JumpKickActiveUntil = nil
    ply.PAT_JumpKickCooldown = nil
    ply.PAT_JumpKickRecoverQueued = nil
    ply.PAT_JumpKickRecoverUntil = nil
    ply.PAT_JumpKickRecoverDuration = nil
    ply.PAT_JumpKickHit = nil
    ply.PAT_JumpKickStartedAt = nil
    ply.PAT_JumpKickLastJumpPress = nil
    ply.PAT_JumpKickLastButtons = nil
    ply.PAT_JumpKickDidRebound = nil
    clearImpactWindow(ply)

    if ply:GetNWString("hg_CustomAnim", "") ~= "" and ply.PlayCustomAnims then
        ply:PlayCustomAnims("")
    end
end

local function getKickForward(ply)
    local forward = ply:EyeAngles():Forward()
    local velocity = ply:GetVelocity()
    local planarVelocity = Vector(velocity.x, velocity.y, 0)

    if planarVelocity:LengthSqr() <= 1 then
        return forward
    end

    return (forward * 0.35 + planarVelocity:GetNormalized() * 0.65):GetNormalized()
end

function addon:Debug(ply, message)
    if not self:IsDebugEnabled() then
        return
    end

    print(string.format("[pat_jumpkick] %s: %s", IsValid(ply) and ply:Nick() or "server", message))
end

function addon:NormalizeState(ply)
    if not IsValid(ply) then
        return
    end

    local now = CurTime()

    if (ply.PAT_JumpKickCooldown or 0) <= now then
        ply.PAT_JumpKickCooldown = nil
    end

    if (ply.PAT_JumpKickActiveUntil or 0) <= now then
        ply.PAT_JumpKickActiveUntil = nil
    end

    if (ply.PAT_JumpKickImpactEnd or 0) <= now then
        clearImpactWindow(ply)
    end

    if (ply.PAT_JumpKickRecoverUntil or 0) <= now then
        ply.PAT_JumpKickRecoverUntil = nil
    end
end

function addon:ShouldInterceptLegAttack(ply)
    if not IsValid(ply) or not ply:Alive() then
        return false
    end

    if ply:GetMoveType() ~= MOVETYPE_WALK then
        return false
    end

    if ply:WaterLevel() >= 2 then
        return false
    end

    return not ply:IsOnGround()
end

function addon:CanJumpKick(ply)
    self:NormalizeState(ply)

    if not self:IsEnabled() then
        return false, "disabled"
    end

    if not IsValid(ply) or not ply:Alive() then
        return false, "invalid_or_dead"
    end

    if ply:GetMoveType() ~= MOVETYPE_WALK then
        return false, "wrong_movetype"
    end

    if ply:WaterLevel() >= 2 then
        return false, "underwater"
    end

    if ply:IsOnGround() then
        return false, "on_ground"
    end

    if currentCharacterIsRagdoll(ply) then
        return false, "character_ragdoll"
    end

    if (ply.PAT_JumpKickActiveUntil or 0) > CurTime() then
        return false, string.format("active_%.2f", ply.PAT_JumpKickActiveUntil - CurTime())
    end

    if (ply.PAT_JumpKickCooldown or 0) > CurTime() then
        return false, string.format("cooldown_%.2f", ply.PAT_JumpKickCooldown - CurTime())
    end

    if ply:GetNWBool("TauntStopMoving", false) then
        return false, "taunt_stop_moving"
    end

    local organism = ply.organism
    if organism and organism.canmove == false then
        return false, "cannot_move"
    end

    if hook.Run("PlayerCanLegAttack", ply) == false then
        return false, "mode_blocked"
    end

    local _, hands = getHandsWeapon(ply)
    if not IsValid(hands) then
        return false, "missing_hands"
    end

    local horizontalSpeed = ply:GetVelocity():Length2D()
    if horizontalSpeed < self:GetNumber("min_speed") then
        return false, string.format("too_slow_%.1f", horizontalSpeed)
    end

    return true, "ok"
end

function addon:SelectAnimation(ply)
    local pitch = ply:EyeAngles().p

    if pitch > 35 then
        return "kick_pistol_45_base"
    end

    if pitch > 20 then
        return "kick_pistol_25_base"
    end

    return self.Anim or "kick_pistol_base"
end

function addon:ArmImpactWindow(ply)
    local now = CurTime()
    ply.PAT_JumpKickImpactStart = now + 0.02
    ply.PAT_JumpKickImpactEnd = now + 0.58
    ply.PAT_JumpKickDidImpact = false
end

function addon:GetKickVolume(ply)
    local velocity = ply:GetVelocity()
    local forward = getKickForward(ply)
    local startPos = ply:GetPos() + Vector(0, 0, 32)
    local velocityLead = velocity * FrameTime() * 6
    local endPos = startPos + velocityLead + forward * 72 + Vector(0, 0, -14)
    local center = (startPos + endPos) * 0.5

    return startPos, endPos, center, forward
end

function addon:IsValidKickTarget(ply, ent, character)
    if not IsValid(ent) or ent == ply or ent == character then
        return false
    end

    if ent:IsPlayer() or ent:IsNPC() then
        return true
    end

    local class = ent:GetClass()
    if class == "prop_ragdoll" or class == "func_breakable_surf" then
        return true
    end

    if hgIsDoor and hgIsDoor(ent) then
        return not ent:GetNoDraw()
    end

    if ent.GetPhysicsObject and IsValid(ent:GetPhysicsObject()) then
        return true
    end

    return false
end

function addon:MakeCandidateTrace(ent, hitPos, matType)
    return {
        Hit = true,
        Entity = ent,
        HitPos = hitPos,
        PhysicsBone = 0,
        MatType = matType or MAT_FLESH
    }
end

function addon:FindCandidateHit(ply)
    local startPos, endPos, center, forward = self:GetKickVolume(ply)
    local character = getCurrentCharacter(ply)
    local filter = {ply}

    if IsValid(character) then
        filter[#filter + 1] = character
    end

    local directTrace = util.TraceHull({
        start = startPos,
        endpos = endPos,
        filter = filter,
        mins = -kickProbeHull,
        maxs = kickProbeHull
    })

    if directTrace.Hit and self:IsValidKickTarget(ply, directTrace.Entity, character) then
        return directTrace, forward
    end

    local bestTrace
    local bestScore

    for _, ent in ipairs(ents.FindInSphere(center, 80)) do
        if not self:IsValidKickTarget(ply, ent, character) then
            continue
        end

        local targetPos = ent.NearestPoint and ent:NearestPoint(center) or ent:WorldSpaceCenter()
        local toTarget = targetPos - startPos
        local distance = toTarget:Length()

        if distance > 116 then
            continue
        end

        local dir = distance > 0 and toTarget:GetNormalized() or forward
        local dot = dir:Dot(forward)
        if dot < 0.05 then
            continue
        end

        local confirmTrace = util.TraceHull({
            start = startPos,
            endpos = targetPos,
            filter = filter,
            mins = -kickConfirmHull,
            maxs = kickConfirmHull
        })

        if confirmTrace.Hit and confirmTrace.Entity ~= ent and not confirmTrace.HitWorld then
            continue
        end

        if confirmTrace.HitWorld and not (hgIsDoor and hgIsDoor(ent)) then
            continue
        end

        local score = dot * 165 - distance
        if ent:IsPlayer() then
            score = score + 28
        elseif hgIsDoor and hgIsDoor(ent) then
            score = score + 16
        end

        if not bestScore or score > bestScore then
            bestScore = score
            bestTrace = confirmTrace.Hit and confirmTrace.Entity == ent and confirmTrace or self:MakeCandidateTrace(ent, targetPos)
        end
    end

    if bestTrace then
        return bestTrace, forward
    end

    return directTrace, forward
end

function addon:HandleDoorImpact(ply, ent, tr, forward, damage)
    if not hgIsDoor or not hgIsDoor(ent) or ent:GetNoDraw() then
        return false
    end

    ent.HP = ent.HP or 200
    ent.HP = ent.HP - damage * (tr.MatType == MAT_METAL and 1 or 2)
    ent:EmitSound("physics/wood/wood_crate_impact_hard" .. math.random(1, 4) .. ".wav")

    if DoorIsOpen and DoorIsOpen(ent) then
        local oldName = ply:GetName()

        if DoorIsOpen2 and not DoorIsOpen2(ent) then
            ent:FastOpenDoor(ply, 5, true)
            ply:SetName(oldName .. ply:EntIndex())

            if ent:GetClass() == "func_door_rotating" then
                ent:Fire("open", ply:GetName(), 0, ply, ply)
            elseif ent:GetClass() == "prop_door_rotating" then
                ent:Fire("openawayfrom", ply:GetName(), 0, ply, ply)
            end

            ply:SetName(oldName)
        else
            ent:FastOpenDoor(ply, 2, true)
            ent:Fire("Close", oldName, 0, ply, ply)
        end

        ent:EmitSound("physics/wood/wood_box_impact_hard3.wav")
    end

    if ent.HP <= 0 and hgBlastThatDoor then
        hgBlastThatDoor(ent, forward * 140)
    end

    return true
end

function addon:FindWallSlamTrace(ply)
    local velocity = ply:GetVelocity()
    local forward = getKickForward(ply)
    local character = getCurrentCharacter(ply)
    local filter = {ply}

    if IsValid(character) then
        filter[#filter + 1] = character
    end

    local startPos = ply:WorldSpaceCenter() + Vector(0, 0, 4)
    local reach = math.Clamp(velocity:Length() * FrameTime() * 7 + 24, 40, 84)
    local tr = util.TraceHull({
        start = startPos,
        endpos = startPos + forward * reach,
        filter = filter,
        mins = -wallSlamHull,
        maxs = wallSlamHull,
        mask = MASK_PLAYERSOLID
    })

    if not tr.Hit then
        return nil, forward, startPos
    end

    if tr.HitWorld then
        return tr, forward, startPos
    end

    if self:IsWallSlamObstacle(tr.Entity) then
        return tr, forward, startPos
    end

    return nil, forward, startPos
end

function addon:IsDoorEntity(ent)
    return IsValid(ent) and hgIsDoor and hgIsDoor(ent) and not ent:GetNoDraw()
end

function addon:IsWallSlamObstacle(ent)
    if not IsValid(ent) then
        return false
    end

    if hgIsDoor and hgIsDoor(ent) then
        return false
    end

    if ent:IsPlayer() or ent:IsNPC() then
        return false
    end

    local class = ent:GetClass()
    if class == "prop_ragdoll" or class == "func_breakable_surf" then
        return false
    end

    if ent:GetMoveType() == MOVETYPE_PUSH then
        return true
    end

    if ent.GetPhysicsObject and IsValid(ent:GetPhysicsObject()) then
        return true
    end

    return false
end


function addon:CanWallRebound(ply, tr, forward)
    if not self:GetNumber("rebound_enable") or self:GetNumber("rebound_enable") <= 0 then
        return false, "disabled"
    end

    if not IsValid(ply) or not ply:Alive() then
        return false, "invalid"
    end

    if ply.PAT_JumpKickDidRebound then
        return false, "already_rebounded"
    end

    local speed = ply:GetVelocity():Length()
    if speed < self:GetNumber("rebound_speed") then
        return false, string.format("too_slow_%.1f", speed)
    end

    local startedAt = ply.PAT_JumpKickStartedAt or 0
    local lastPress = ply.PAT_JumpKickLastJumpPress or 0
    local now = CurTime()

    if lastPress <= 0 then
        return false, "no_input"
    end

    if lastPress <= (startedAt + self:GetNumber("rebound_grace")) then
        return false, "grace"
    end

    if (now - lastPress) > self:GetNumber("rebound_window") then
        return false, "late"
    end

    if not tr or not tr.Hit then
        return false, "no_trace"
    end

    local hitNormal = tr.HitNormal or vector_origin
    if hitNormal:LengthSqr() <= 0.001 then
        return false, "bad_normal"
    end

    local velocity = ply:GetVelocity()
    local velocityDir = velocity:GetNormalized()
    if velocityDir:Dot(hitNormal) > -0.2 then
        return false, "glancing"
    end

    return true, "ok"
end

function addon:HandleWallRebound(ply, ent, tr, forward)
    local canRebound, reason = self:CanWallRebound(ply, tr, forward)
    if not canRebound then
        self:Debug(ply, "rebound_blocked:" .. tostring(reason))
        return false
    end

    local velocity = ply:GetVelocity()
    local normal = tr.HitNormal:GetNormalized()

    -- Pure "push off the wall" direction.
    local outward = normal
    outward.z = 0
    if outward:LengthSqr() <= 0.001 then
        outward = -forward
        outward.z = 0
    end
    outward = outward:GetNormalized()

    -- Keep only a little of the sideways movement so it still feels fluid.
    local planarVelocity = Vector(velocity.x, velocity.y, 0)
    local lateral = planarVelocity - outward * planarVelocity:Dot(outward)
    if lateral:LengthSqr() > 1 then
        lateral = lateral:GetNormalized()
    else
        lateral = vector_origin
    end

    local rebound = outward * self:GetNumber("rebound_push")
    rebound = rebound + lateral * (self:GetNumber("rebound_push") * 0.08)
    rebound.z = self:GetNumber("rebound_up")

    -- Kill most of the old wall-carry speed first.
    local cancel = Vector(-velocity.x * 1.0, -velocity.y * 1.0, 0)
    if velocity.z < 0 then
        cancel.z = -velocity.z * 0.25
    end

    ply.PAT_JumpKickHit = false
    ply.PAT_JumpKickDidRebound = true
    ply.PAT_JumpKickRecoverQueued = nil
    ply.PAT_JumpKickRecoverUntil = nil
    ply.PAT_JumpKickActiveUntil = nil
    clearImpactWindow(ply)

    local extraCooldown = self:GetNumber("rebound_cooldown")
    ply.PAT_JumpKickCooldown = math.max(ply.PAT_JumpKickCooldown or 0, CurTime() + extraCooldown)

    ply:SetVelocity(cancel)
    ply:SetVelocity(rebound)

    ply:ViewPunch(Angle(-6, math.Rand(-1.5, 1.5), math.Rand(-2, 2)))
    ply:EmitSound("physics/body/body_medium_impact_soft" .. math.random(1, 7) .. ".wav", 60, math.random(105, 115), 0.65)
    ply:EmitSound("player/clothes_generic_foley_0" .. math.random(1, 5) .. ".wav", 60, 110, 0.8)

    self:Debug(ply, string.format("wall_rebound_%s", IsValid(ent) and ent:GetClass() or "world"))

    return true
end

function addon:HandleWallResponse(ply, ent, tr, forward)
    if self:HandleWallRebound(ply, ent, tr, forward) then
        return true
    end

    return self:HandleWallSlam(ply, ent, tr, forward)
end

function addon:HandleWallSlam(ply, ent, tr, forward)
    if not IsValid(ply) or not ply:Alive() then
        return false
    end

    local velocity = ply:GetVelocity()
    local speed = velocity:Length()
    if speed < self:GetNumber("wall_stun_speed") then
        return false
    end

    local velocityDir = speed > 0 and velocity:GetNormalized() or forward
    if velocityDir:Dot(forward) < 0.55 then
        return false
    end

    ply.PAT_JumpKickHit = false
    ply.PAT_JumpKickRecoverQueued = true
    ply.PAT_JumpKickActiveUntil = nil

    local bounce = -forward * math.Clamp(speed * 0.55, 160, 320)
    bounce.z = math.max(bounce.z, 24)
    ply:SetVelocity(bounce)
    ply:ViewPunch(Angle(10, math.Rand(-2, 2), math.Rand(-3, 3)))
    ply:EmitSound("physics/body/body_medium_impact_hard" .. math.random(1, 6) .. ".wav", 68, math.random(90, 100), 0.9)

    local stunDelay = self:GetNumber("wall_stun_delay")
    if hg and hg.LightStunPlayer then
        timer.Simple(stunDelay, function()
            if IsValid(ply) and ply:Alive() then
                hg.LightStunPlayer(ply, self:GetNumber("wall_stun_time"))
            end
        end)
    elseif hg and hg.Fake then
        timer.Simple(stunDelay, function()
            if IsValid(ply) and ply:Alive() then
                hg.Fake(ply)
            end
        end)
    end

    self:Debug(ply, string.format("wall_slam_%s_%.1f", IsValid(ent) and ent:GetClass() or "world", speed))

    return true
end

function addon:TryActiveWallSlam(ply)
    if not IsValid(ply) or not ply:Alive() then
        return false
    end

    if (ply.PAT_JumpKickActiveUntil or 0) <= CurTime() then
        return false
    end

    if ply:IsOnGround() or ply.PAT_JumpKickDidImpact then
        return false
    end

    ply:LagCompensation(true)
    local wallTrace, wallForward = self:FindWallSlamTrace(ply)
    ply:LagCompensation(false)

    local kickTrace = self:FindCandidateHit(ply)
    local kickEnt = kickTrace and kickTrace.Entity or nil
    if self:IsDoorEntity(kickEnt) then
        return false
    end
    if not wallTrace then
        return false
    end

    ply.PAT_JumpKickDidImpact = true
    clearImpactWindow(ply)

    return self:HandleWallResponse(ply, wallTrace.Entity, wallTrace, wallForward)
end

function addon:DoImpact(ply)
    if not IsValid(ply) or not ply:Alive() then
        clearImpactWindow(ply)
        return false
    end

    ply:LagCompensation(true)
    local tr, forward = self:FindCandidateHit(ply)
    local wallTrace, wallForward, wallStart = self:FindWallSlamTrace(ply)
    ply:LagCompensation(false)

    local ent = tr and tr.Entity or nil
    local hasKickTrace = tr and tr.Hit and (tr.HitWorld or IsValid(ent))
    local slamWins = false

    if wallTrace then
        local wallDistance = wallTrace.HitPos and wallStart and wallTrace.HitPos:DistToSqr(wallStart) or math.huge
        local kickDistance = hasKickTrace and tr.HitPos and wallStart and tr.HitPos:DistToSqr(wallStart) or math.huge
        local kickIsPreferred = hasKickTrace and IsValid(ent) and not self:IsWallSlamObstacle(ent)

        slamWins = (not kickIsPreferred) and wallDistance <= kickDistance + 48
    end

    if slamWins then
        ply.PAT_JumpKickDidImpact = true
        ply.PAT_JumpKickHit = false
        clearImpactWindow(ply)

        ply:EmitSound("player/shove_0" .. math.random(1, 5) .. ".wav", 65, 100, 1)
        ply:EmitSound("weapons/melee/blunt_light" .. math.random(1, 8) .. ".wav", 70, 100, 1)

        if self:HandleWallResponse(ply, wallTrace.Entity, wallTrace, wallForward) then
            return true
        end

        ply:SetVelocity(-wallForward * 120)
        return true
    end

    if not hasKickTrace then
        return false
    end

    ply.PAT_JumpKickDidImpact = true
    ply.PAT_JumpKickHit = IsValid(ent)
    clearImpactWindow(ply)

    ply:EmitSound("player/shove_0" .. math.random(1, 5) .. ".wav", 65, 100, 1)
    ply:EmitSound("weapons/melee/blunt_light" .. math.random(1, 8) .. ".wav", 70, 100, 1)

    if tr.HitWorld and not IsValid(ent) then
        if self:HandleWallResponse(ply, nil, tr, forward) then
            return true
        end

        ply:SetVelocity(-forward * 120)
        return true
    end

    local _, inflictor = getHandsWeapon(ply)
    local organism = ply.organism
    local horizontalSpeed = ply:GetVelocity():Length2D()
    local speedMul = math.Clamp(horizontalSpeed / 260, 0.75, 1.8)
    local fallMul = math.Clamp(math.abs(math.min(ply:GetVelocity().z, 0)) / 500, 0, 0.45)
    local damage = self:GetNumber("damage") * speedMul * (1 + fallMul)

    if organism and organism.superfighter then
        damage = damage * 1.2
    end

    local baseForce = forward * self:GetNumber("force")
    baseForce.z = math.max(baseForce.z, self:GetNumber("lift"))

    local force = baseForce
    local isWallObstacle = self:IsWallSlamObstacle(ent)
    local wallStunSpeed = self:GetNumber("wall_stun_speed")
    local minSpeed = self:GetNumber("min_speed")

    if self:HandleDoorImpact(ply, ent, tr, forward, damage) then
        ply:SetVelocity(-forward * 40)
        return true
    end

    if isWallObstacle then
        if horizontalSpeed >= wallStunSpeed and self:HandleWallSlam(ply, ent, tr, forward) then
            return true
        end

        local propFrac = math.Clamp(
            (horizontalSpeed - minSpeed) / math.max(wallStunSpeed - minSpeed, 1),
            0,
            1
        )

        local propForceMul = Lerp(propFrac, 0.04, 0.22)
        local propDamageMul = Lerp(propFrac, 0.08, 0.30)

        force = baseForce * propForceMul
        force.z = self:GetNumber("lift") * propForceMul
        damage = damage * propDamageMul
    end

    local phys = ent.GetPhysicsObjectNum and ent:GetPhysicsObjectNum(tr.PhysicsBone or 0) or nil
    if not IsValid(phys) and ent.GetPhysicsObject then
        phys = ent:GetPhysicsObject()
    end

    local dmginfo = DamageInfo()
    dmginfo:SetAttacker(ply)
    dmginfo:SetInflictor(IsValid(inflictor) and inflictor or ply)
    dmginfo:SetDamage(damage)
    dmginfo:SetDamageForce(force * damage)
    dmginfo:SetDamageType(ent:GetClass() == "func_breakable_surf" and DMG_SLASH or DMG_CLUB)
    dmginfo:SetDamagePosition(tr.HitPos)

    PenetrationGlobal = 1
    MaxPenLenGlobal = 1

    if hg and hg.AddForceRag and (ent:IsPlayer() or ent:IsNPC() or ent:GetClass() == "prop_ragdoll") then
        hg.AddForceRag(ent, tr.PhysicsBone or 0, force * damage * 7, 0.2)
    end

    ent:TakeDamageInfo(dmginfo)

    if IsValid(phys) then
        local physMul = isWallObstacle and 2 or 8
        phys:ApplyForceOffset(force * math.max(phys:GetMass(), 1) * physMul, tr.HitPos)
    end

    if ent:IsPlayer() or ent:IsNPC() then
        ent:SetVelocity(force)
    end

    if ent:IsPlayer() then
        ent:ViewPunch(Angle(-8, 0, 0))
    end

    if ent:IsPlayer() or ent:GetClass() == "prop_ragdoll" then
        ent:EmitSound("physics/body/body_medium_impact_hard" .. math.random(1, 6) .. ".wav", 60, math.random(90, 105), 0.7)
    end

    ply:SetVelocity(-forward * 40)

    return true
end

function addon:StartJumpKick(ply)
    local canJumpKick, reason = self:CanJumpKick(ply)
    if not canJumpKick then
        self:Debug(ply, "blocked: " .. tostring(reason))
        return false
    end

    local now = CurTime()
    local organism = ply.organism

    if organism and organism.stamina then
        organism.stamina.subadd = (organism.stamina.subadd or 0) + (organism.superfighter and 5 or 10)
    end

    ply.PAT_JumpKickHit = false
    ply.PAT_JumpKickDidRebound = false
    ply.PAT_JumpKickStartedAt = now
    ply.PAT_JumpKickLastJumpPress = nil
    ply.PAT_JumpKickCooldown = now + self:GetNumber("cooldown")
    ply.PAT_JumpKickActiveUntil = now + 0.6
    ply.PAT_JumpKickRecoverQueued = true
    clearImpactWindow(ply)
    self:ArmImpactWindow(ply)

    local anim = self:SelectAnimation(ply)
    if ply.PlayCustomAnims then
        ply:PlayCustomAnims(anim, true, 0.65, false, 0.18)
    end

    local forward = getKickForward(ply)
    ply:SetVelocity(forward * 95 + Vector(0, 0, 22))
    ply:EmitSound("player/clothes_generic_foley_0" .. math.random(1, 5) .. ".wav", 65, 100, 1)

    self:Debug(ply, "jumpkick_started")

    return true
end

function addon:HandleAirborneLegAttack(ply)
    local canJumpKick = self:StartJumpKick(ply)
    return canJumpKick
end

function addon:InstallWrapper()
    local PLAYER = FindMetaTable("Player")
    if not PLAYER then
        return false
    end

    local current = PLAYER.LegAttack
    if not isfunction(current) then
        return false
    end

    if current ~= self.LegAttackWrapper and current ~= PLAYER.PAT_JumpKickOriginalLegAttack then
        PLAYER.PAT_JumpKickOriginalLegAttack = current
    end

    if PLAYER.LegAttack ~= self.LegAttackWrapper then
        PLAYER.LegAttack = self.LegAttackWrapper
        self:Debug(nil, "installed_legattack_wrapper")
    end

    return PLAYER.LegAttack == self.LegAttackWrapper and isfunction(PLAYER.PAT_JumpKickOriginalLegAttack)
end

addon.LegAttackWrapper = function(ply, ...)
    local PLAYER = FindMetaTable("Player")
    local original = PLAYER and PLAYER.PAT_JumpKickOriginalLegAttack

    if addon:ShouldInterceptLegAttack(ply) then
        return addon:HandleAirborneLegAttack(ply)
    end

    if isfunction(original) then
        return original(ply, ...)
    end
end

addon:InstallWrapper()

hook.Add("Think", "PAT_JumpKick_EnsureWrapper", function()
    addon.NextInstallAttempt = addon.NextInstallAttempt or 0

    if addon.NextInstallAttempt > CurTime() then
        return
    end

    addon.NextInstallAttempt = CurTime() + 1
    addon:InstallWrapper()
end)

hook.Add("Think", "PAT_JumpKick_ImpactThink", function()
    local now = CurTime()

    for _, ply in ipairs(player.GetAll()) do
        addon:NormalizeState(ply)

        if addon:TryActiveWallSlam(ply) then
            continue
        end

        local impactStart = ply.PAT_JumpKickImpactStart
        local impactEnd = ply.PAT_JumpKickImpactEnd

        if not impactStart or not impactEnd then
            continue
        end

        if impactStart > now then
            continue
        end

        if impactEnd <= now or not ply:Alive() then
            clearImpactWindow(ply)
            continue
        end

        if ply.PAT_JumpKickDidImpact then
            clearImpactWindow(ply)
            continue
        end

        addon:DoImpact(ply)
    end
end)

hook.Add("SetupMove", "PAT_JumpKick_LandingRecovery", function(ply, mv)
    local buttons = mv:GetButtons()
    local lastButtons = ply.PAT_JumpKickLastButtons or 0

    if bit.band(buttons, IN_JUMP) ~= 0 and bit.band(lastButtons, IN_JUMP) == 0 then
        ply.PAT_JumpKickLastJumpPress = CurTime()
    end

    ply.PAT_JumpKickLastButtons = buttons

    local activeUntil = ply.PAT_JumpKickActiveUntil
    if activeUntil and activeUntil > CurTime() then
        mv:SetSideSpeed(mv:GetSideSpeed() * 0.35)
        mv:SetForwardSpeed(math.max(mv:GetForwardSpeed(), 0))
    end

    local recoverQueued = ply.PAT_JumpKickRecoverQueued
    if recoverQueued and ply:IsOnGround() then
        ply.PAT_JumpKickRecoverUntil = CurTime() + ((ply.PAT_JumpKickHit and addon:GetNumber("recovery_hit")) or addon:GetNumber("recovery_miss"))
        ply.PAT_JumpKickRecoverQueued = nil
    end

    local recoverUntil = ply.PAT_JumpKickRecoverUntil
    if not recoverUntil or recoverUntil <= CurTime() then
        return
    end

    local scale = 0.55
    mv:SetForwardSpeed(mv:GetForwardSpeed() * scale)
    mv:SetSideSpeed(mv:GetSideSpeed() * scale)
    mv:SetMaxClientSpeed(mv:GetMaxClientSpeed() * scale)
end)

hook.Add("Player Spawn", "PAT_JumpKick_Reset", clearState)
hook.Add("Player Getup", "PAT_JumpKick_ResetGetup", clearState)
hook.Add("PlayerDeath", "PAT_JumpKick_Reset", clearState)
hook.Add("PlayerDisconnected", "PAT_JumpKick_Reset", clearState)




