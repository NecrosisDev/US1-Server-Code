if SERVER then AddCSLuaFile() end

SWEP.Base = "weapon_bandage_sh"
SWEP.PrintName = "Hemostatic Syringe"
SWEP.Instructions = "Injects a clotting agent to stop minor bleeding or reduce major bleeding. LMB to use on yourself; RMB to use on someone else."
SWEP.Category = "ZCity Medicine"
SWEP.Spawnable = true
SWEP.AdminOnly = false
SWEP.DrawWeaponInfoBox = true

SWEP.Primary.Wait = 1
SWEP.Primary.Next = 0
SWEP.HoldType = "normal"
SWEP.ViewModel = ""
SWEP.WorldModel = "models/bloocobalt/l4d/items/w_eq_adrenaline.mdl"

SWEP.AutoSwitchTo = false
SWEP.AutoSwitchFrom = false
SWEP.Slot = 3
SWEP.SlotPos = 1
SWEP.WorkWithFake = true

SWEP.offsetVec = Vector(3, -2.5, -1)
SWEP.offsetAng = Angle(-30, 20, -90)
SWEP.ModelScale = 0.7

SWEP.mode = 1
SWEP.modes = 1
SWEP.modeNames = {
    [1] = "hemostatic injection"
}

SWEP.modeValuesdef = {
    [1] = 1
}

SWEP.showstats = false

SWEP.modeValues = SWEP.modeValues or {}
SWEP.modeValuesdef = SWEP.modeValuesdef or {}
SWEP.DeploySnd = ""
SWEP.HolsterSnd = ""
SWEP.FallSnd = "physics/body/body_medium_impact_soft5.wav"

local hg_healanims = GetConVar("hg_healanims")

if not hg_healanims then
    hg_healanims = CreateConVar("hg_healanims", "0", FCVAR_ARCHIVE)
end

if CLIENT then
    SWEP.IconOverride = "vgui/hemostaticinjector.png"
    SWEP.BounceWeaponIcon = false
    SWEP.DrawWeaponInfoBox = true

    local IconMat = Material("vgui/hemostaticinjector.png", "smooth noclamp")

    function SWEP:DrawWeaponSelection(x, y, wide, tall, alpha)
        self:PrintWeaponInfo(x + wide + 20, y + tall * 0.15, alpha)

        if not IconMat or IconMat:IsError() then return end

        surface.SetDrawColor(255, 255, 255, alpha or 255)
        surface.SetMaterial(IconMat)

        local size = math.min(wide, tall) * 0.75
        local ix = x + (wide - size) * 0.5
        local iy = y + (tall - size) * 0.5 - 16

        surface.DrawTexturedRect(ix, iy, size, size)
    end
end

function SWEP:SetInfo(info)
    info = istable(info) and info or {}
    self:SetNetVar("modeValues", info)
    self.modeValues = info
end


function SWEP:InitializeAdd()
    self:SetHold(self.HoldType)
    self.modeValues = {
        [1] = 1
    }
    self.Used = false
    self.InfoMarkup = nil
end

function SWEP:Think()
    self:SetBodyGroups("11")

    local owner = self:GetOwner()
    if IsValid(owner) and not owner:KeyDown(IN_ATTACK) and hg_healanims and hg_healanims:GetBool() then
        self:SetHolding(math.max(self:GetHolding() - 4, 0))
    end
end

function SWEP:Animation()
    local hold = self:GetHolding()
    self:BoneSet("r_upperarm", vector_origin, Angle(0, -hold + (100 * (hold / 100)), 0))
    self:BoneSet("r_forearm", vector_origin, Angle(-hold / 6, -hold * 2, -15))
end

function SWEP:OwnerChanged()
    local owner = self:GetOwner()
    if IsValid(owner) and owner:IsNPC() then
        self:SpawnGarbage(nil, nil, nil, nil, "2211")
        self:NPCHeal(owner, 0.1, "snd_jack_hmcd_needleprick.wav")
    end
end

if SERVER then
    local blockedBones = {
        ["ValveBiped.Bip01_Head1"] = true,
        ["ValveBiped.Bip01_Neck1"] = true,
        ["ValveBiped.Bip01_Spine"] = true,
        ["ValveBiped.Bip01_Spine1"] = true,
        ["ValveBiped.Bip01_Spine2"] = true,
        ["ValveBiped.Bip01_Pelvis"] = true
    }

    local function IsValidClotWound(ent, wound)
        if not wound or not wound[4] then return false end

        local boneId = ent:LookupBone(wound[4])
        if not boneId then return false end

        local boneName = ent:GetBoneName(boneId)
        if not boneName or blockedBones[boneName] then return false end

        return true
    end

    function SWEP:ConsumeUsed()
        if self.Used then return end
        self.Used = true
        self.modeValues[1] = 0

        self:SetNextPrimaryFire(CurTime() + 999)
        self:SetNextSecondaryFire(CurTime() + 999)

        local owner = self:GetOwner()
        local class = self:GetClass()

        self:SpawnGarbage(nil, nil, nil, nil, "2211")

        if IsValid(owner) and owner:IsPlayer() then
            owner:SelectWeapon("weapon_hands_sh")

            timer.Simple(0, function()
                if IsValid(owner) then
                    owner:StripWeapon(class)
                end
            end)
        end

        timer.Simple(0, function()
            if IsValid(self) then
                self:Remove()
            end
        end)
    end

    function SWEP:ApplyClot(ent)
        local org = ent.organism
        if not org then return false end
        if self.Used then return false end
        if not self.modeValues or self.modeValues[1] <= 0 then return false end

        local changed = false
        local bestIndex = nil
        local bestValue = 0

        if istable(org.wounds) then
            for i, wound in ipairs(org.wounds) do
                if wound and wound[1] and wound[1] > bestValue and IsValidClotWound(ent, wound) then
                    bestValue = wound[1]
                    bestIndex = i
                end
            end
        end

        if bestIndex then
            local wound = org.wounds[bestIndex]
            local old = wound[1] or 0
            local new = old <= 12 and 0 or math.max(old - 22, 0)
            local reduced = old - new

            wound[1] = new
            org.bleed = math.max((org.bleed or 0) - reduced * 1.35, 0)
            org.pain = math.max((org.pain or 0) - reduced * 0.2, 0)

            ent.bandaged_limbs = ent.bandaged_limbs or {}
            if wound[4] then
                ent.bandaged_limbs[wound[4]] = true
            end

            if wound[1] <= 0 then
                table.remove(org.wounds, bestIndex)
            end

            changed = reduced > 0
        end

        if istable(org.wounds) then
            for i = #org.wounds, 1, -1 do
                local wound = org.wounds[i]
                if wound and (wound[1] or 0) <= 3 then
                    table.remove(org.wounds, i)
                    changed = true
                end
            end
        end

        if (org.bleed or 0) <= 6 and (not istable(org.arterialwounds) or #org.arterialwounds == 0) then
            org.bleed = 0

            if istable(org.wounds) then
                for i = #org.wounds, 1, -1 do
                    local wound = org.wounds[i]
                    if wound and (wound[1] or 0) <= 14 then
                        table.remove(org.wounds, i)
                    end
                end
            end

            changed = true
        else
            org.bleed = math.max((org.bleed or 0) - 4, 0)
        end

        if changed then
            if IsValid(org.owner) then
                org.owner:SetNetVar("wounds", org.wounds or {})
                org.owner:SetNetVar("arterialwounds", org.arterialwounds or {})
            end

            timer.Simple(0.1, function()
                if not IsValid(ent) then return end
                ent:SetNetVar("bandaged_limbs", ent.bandaged_limbs or {})

                if ent:IsRagdoll() and hg.RagdollOwner(ent) and hg.RagdollOwner(ent):Alive() then
                    hg.RagdollOwner(ent):SetNetVar("bandaged_limbs", ent.bandaged_limbs or {})
                end
            end)
        end

        return changed
    end

    function SWEP:Heal(ent, mode)
        if self.Used then return end
        if not IsValid(ent) then return end

        if ent:IsNPC() then
            self:NPCHeal(ent, 0.1, "snd_jack_hmcd_needleprick.wav")
            self:ConsumeUsed()
            return
        end

        local org = ent.organism
        if not org then return end

        local owner = self:GetOwner()
        if not IsValid(owner) then return end

        if ent == hg.GetCurrentCharacter(owner) and hg_healanims:GetBool() then
            self:SetHolding(math.min(self:GetHolding() + 4, 100))
            if self:GetHolding() < 100 then return end
        end

        local hasBleeding = (org.bleed or 0) > 0
            or (istable(org.wounds) and #org.wounds > 0)
            or (istable(org.arterialwounds) and #org.arterialwounds > 0)

        if not hasBleeding then return end

        local entOwner = IsValid(owner.FakeRagdoll) and owner.FakeRagdoll or owner
        entOwner:EmitSound("snd_jack_hmcd_needleprick.wav", 60, math.random(95, 105))

        local done = self:ApplyClot(ent)
        if not done then return end

        org.bloodclotter = CurTime() + 90

        if self.poisoned2 then
            org.poison4 = CurTime()
            self.poisoned2 = nil
        end

        self:ConsumeUsed()
    end
end