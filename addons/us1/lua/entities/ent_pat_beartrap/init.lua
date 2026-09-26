AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")

include("shared.lua")

local function setSequenceSafe(ent, sequenceName)
    local sequence = ent:LookupSequence(sequenceName)
    if sequence and sequence >= 0 then
        ent:SetSequence(sequence)
        ent:SetCycle(0)
        ent:SetPlaybackRate(1)
        ent:ResetSequenceInfo()
    end
end

local function paintBlood(pos, source)
    for _ = 1, 5 do
        local jitter = VectorRand() * 16
        jitter.z = math.abs(jitter.z) + 4

        if util.PaintDown then
            util.PaintDown(pos + jitter, "Blood", source)
        else
            local startPos = pos + jitter
            local tr = util.TraceLine({
                start = startPos,
                endpos = startPos - Vector(0, 0, 96),
                filter = source
            })

            if tr.Hit then
                util.Decal("Blood", tr.HitPos + tr.HitNormal, tr.HitPos - tr.HitNormal, source)
            end
        end
    end
end

local function getBonePos(ent, boneName)
    if not IsValid(ent) or not boneName then return end

    local bone = ent:LookupBone(boneName)
    if not bone then return end

    local pos = select(1, ent:GetBonePosition(bone))
    if isvector(pos) and not pos:IsZero() then
        return pos
    end

    local matrix = ent:GetBoneMatrix(bone)
    if matrix then
        return matrix:GetTranslation()
    end
end

local function chooseLimb(ply, trapPos)
    local org = ply.organism
    if not org then return end

    local char = PAT_BEARTRAP.GetCharacterEntity(ply)
    local leftPos = getBonePos(char, "ValveBiped.Bip01_L_Foot") or getBonePos(char, "ValveBiped.Bip01_L_Calf")
    local rightPos = getBonePos(char, "ValveBiped.Bip01_R_Foot") or getBonePos(char, "ValveBiped.Bip01_R_Calf")

    local chosen
    if isvector(leftPos) and isvector(rightPos) then
        chosen = leftPos:DistToSqr(trapPos) <= rightPos:DistToSqr(trapPos) and "lleg" or "rleg"
    else
        local localPos = char:WorldToLocal(trapPos)
        chosen = localPos.y >= 0 and "lleg" or "rleg"
    end

    local other = chosen == "lleg" and "rleg" or "lleg"
    if org[chosen .. "amputated"] and not org[other .. "amputated"] then
        chosen = other
    end

    return chosen
end

local function getClosestLegDistanceSqr(ply, trapPos)
    local char = PAT_BEARTRAP.GetCharacterEntity(ply)
    if not IsValid(char) then
        return math.huge
    end

    local leftPos = getBonePos(char, "ValveBiped.Bip01_L_Foot") or getBonePos(char, "ValveBiped.Bip01_L_Calf")
    local rightPos = getBonePos(char, "ValveBiped.Bip01_R_Foot") or getBonePos(char, "ValveBiped.Bip01_R_Calf")
    local best = math.huge

    if isvector(leftPos) then
        best = math.min(best, leftPos:DistToSqr(trapPos))
    end

    if isvector(rightPos) then
        best = math.min(best, rightPos:DistToSqr(trapPos))
    end

    if best < math.huge then
        return best
    end

    local nearest = char:NearestPoint(trapPos)
    return isvector(nearest) and nearest:DistToSqr(trapPos) or math.huge
end

local function resolveVictim(ent)
    if not IsValid(ent) then return end
    if ent:IsPlayer() then return ent end
    if ent:IsRagdoll() and hg and hg.RagdollOwner then
        return hg.RagdollOwner(ent)
    end
end

function ENT:Initialize()
    self:SetModel(PAT_BEARTRAP.Model)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    self:DrawShadow(true)
    self:SetTrigger(true)
    self:SetArmed(false)
    self:SetNextRearm(0)
    self.NextTrigger = 0
    self.LastVictim = nil
    self.LastVictimUntil = 0
    self.ScanRadius = 24
    self.LegRadiusSqr = 22 * 22

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
        phys:Sleep()
    end

    setSequenceSafe(self, "ClosedIdle")

    timer.Simple(0.6, function()
        if IsValid(self) then
            self:ArmTrap()
        end
    end)
end

function ENT:CanTriggerVictim(victim)
    if not IsValid(victim) then return false end
    if not victim:IsPlayer() then return false end
    if not victim:Alive() then return false end
    if victim:GetMoveType() == MOVETYPE_NOCLIP then return false end
    if victim:GetObserverMode() ~= OBS_MODE_NONE then return false end
    if getClosestLegDistanceSqr(victim, self:GetPos()) > self.LegRadiusSqr then return false end

    return true
end

function ENT:ArmTrap()
    self:SetArmed(true)
    self:SetNextRearm(0)
    setSequenceSafe(self, "OpenIdle")
end

function ENT:CloseTrap()
    self:SetArmed(false)
    self:SetNextRearm(0)
    setSequenceSafe(self, "ClosedIdle")
end

function ENT:TriggerVictim(victimEnt)
    local victim = resolveVictim(victimEnt)
    local owner = self:GetTrapOwner()

    self.NextTrigger = CurTime() + 0.75
    self.LastVictim = victim
    self.LastVictimUntil = CurTime() + 2.5
    self:CloseTrap()

    setSequenceSafe(self, "Snap")
    self:EmitSound(PAT_BEARTRAP.Sound, 75, 100)

    timer.Simple(0.18, function()
        if IsValid(self) then
            self:CloseTrap()
        end
    end)

    if not IsValid(victim) or not victim:IsPlayer() or not victim:Alive() or not victim.organism then
        if IsValid(victimEnt) then
            local dmg = DamageInfo()
            dmg:SetDamage(PAT_BEARTRAP.NPCDamage:GetFloat())
            dmg:SetDamageType(DMG_SLASH)
            dmg:SetAttacker(IsValid(owner) and owner or self)
            dmg:SetInflictor(self)
            victimEnt:TakeDamageInfo(dmg)
            paintBlood(self:GetPos(), victimEnt)
        end

        return
    end

    local limb = chooseLimb(victim, self:GetPos())
    if limb and not victim.organism[limb .. "amputated"] and hg and hg.organism and hg.organism.AmputateLimb then
        hg.organism.AmputateLimb(victim.organism, limb)
        if victim.Notify then
            victim:Notify("The bear trap shredded your leg!", 1, "pat_beartrap", 1, nil, Color(255, 70, 70))
        end
    else
        local dmg = DamageInfo()
        dmg:SetDamage(45)
        dmg:SetDamageType(DMG_SLASH)
        dmg:SetAttacker(IsValid(owner) and owner or self)
        dmg:SetInflictor(self)
        victim:TakeDamageInfo(dmg)
    end

    timer.Simple(0, function()
        if IsValid(victim) and hg and hg.LightStunPlayer then
            hg.LightStunPlayer(victim, PAT_BEARTRAP.StunTime:GetFloat())
        end
    end)

    paintBlood(self:GetPos(), PAT_BEARTRAP.GetCharacterEntity(victim))
end

function ENT:Touch(toucher)
    if not IsValid(self) or not self:GetArmed() then return end
    if self.NextTrigger > CurTime() then return end
    if not IsValid(toucher) then return end

    local victim = resolveVictim(toucher)
    if IsValid(victim) and victim == self.LastVictim and self.LastVictimUntil > CurTime() then return end

    if IsValid(victim) then
        if not self:CanTriggerVictim(victim) then return end
        self:TriggerVictim(victim)
        return
    end

    if toucher:IsNPC() then
        self:TriggerVictim(toucher)
    end
end

function ENT:Think()
    if self:GetArmed() and self.NextTrigger <= CurTime() then
        for _, ent in ipairs(ents.FindInSphere(self:GetPos(), self.ScanRadius)) do
            if ent == self then continue end

            local victim = resolveVictim(ent)
            if IsValid(victim) then
                if victim ~= self.LastVictim or self.LastVictimUntil <= CurTime() then
                    if self:CanTriggerVictim(victim) then
                        self:TriggerVictim(victim)
                        break
                    end
                end
            elseif ent:IsNPC() then
                self:TriggerVictim(ent)
                break
            end
        end
    end

    self:NextThink(CurTime())
    return true
end

function ENT:Use(act)
    if not IsValid(act) or not act:IsPlayer() then return end
    if act:HasWeapon("weapon_beartrap_homigrad") then return end

    act:Give("weapon_beartrap_homigrad")
    self:Remove()
end
