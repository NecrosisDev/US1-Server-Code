if SERVER then
    AddCSLuaFile()
elseif CLIENT then
    SWEP.DrawAmmo = false
    SWEP.DrawCrosshair = true
    SWEP.Slot = 4
    SWEP.SlotPos = 3
    SWEP.IconOverride = "vgui/weapon_beartrap_homigrad.png"
    SWEP.Category = "ZCity Other"
    SWEP.BounceWeaponIcon = false
    SWEP.DrawWeaponInfoBox = true

    local IconMat = Material("vgui/weapon_beartrap_homigrad.png", "smooth noclamp")

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

SWEP.ViewModel = PAT_BEARTRAP and PAT_BEARTRAP.ViewModel or "models/stiffy360/c_beartrap.mdl"
SWEP.WorldModel = PAT_BEARTRAP and PAT_BEARTRAP.Model or "models/stiffy360/beartrap.mdl"
SWEP.UseHands = true
SWEP.HoldType = "slam"
SWEP.PrintName = "Bear Trap"
SWEP.Instructions = "LMB to place the bear trap on the ground. Use on the placed trap to pick it back up."
SWEP.Category = "Weapons - Trap"
SWEP.Spawnable = true
SWEP.AdminOnly = false
SWEP.AutoSwitchTo = false
SWEP.AutoSwitchFrom = false

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

SWEP.ViewModelFOV = 58
SWEP.Offset = {
    Pos = Vector(3, 8, -1),
    Ang = Angle(60, -50, 90),
    Size = 0.8
}

local placementRadius = 90

local function inPlacementRadius(ply, tr)
    return tr.HitPos:DistToSqr(ply:GetPos()) <= placementRadius * placementRadius
end

local function canPlace(ply, tr)
    if not tr.Hit or tr.HitSky or not tr.HitPos then return false end
    if not inPlacementRadius(ply, tr) then return false end
    if vector_up:Dot(tr.HitNormal) < 0.65 then return false end
    if IsValid(tr.Entity) and (tr.Entity:IsPlayer() or tr.Entity:IsNPC() or tr.Entity:IsRagdoll()) then return false end

    return true
end

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
end

function SWEP:PrimaryAttack()
    local owner = self:GetOwner()
    if not IsValid(owner) then return end

    local tr = util.TraceLine({
        start = owner:GetShootPos(),
        endpos = owner:GetShootPos() + owner:GetAimVector() * placementRadius,
        filter = owner,
        mask = MASK_SOLID
    })

    if not canPlace(owner, tr) then return end
    if CLIENT then return end

    local trap = ents.Create("ent_pat_beartrap")
    if not IsValid(trap) then return end

    local ang = tr.HitNormal:Angle()
    ang:RotateAroundAxis(ang:Right(), -90)

    trap:SetPos(tr.HitPos + tr.HitNormal * 1.2)
    trap:SetAngles(ang)
    trap:SetTrapOwner(owner)
    trap:Spawn()
    trap:Activate()

    self:EmitSound("physics/metal/chain_impact_hard2.wav", 60, 110)

    timer.Simple(0, function()
        if IsValid(owner) then
            owner:SelectWeapon("weapon_hands_sh")
            owner:StripWeapon("weapon_beartrap_homigrad")
        end
    end)
end

function SWEP:SecondaryAttack()
    return false
end

function SWEP:Reload()
    return false
end

function SWEP:Deploy()
    self:SetNextPrimaryFire(CurTime() + 0.3)
    self:SetNextSecondaryFire(CurTime() + 0.3)
    return true
end

function SWEP:OnRemove()
    local owner = self:GetOwner()
    if IsValid(owner) and owner:IsPlayer() then
        owner:ConCommand("lastinv")
    end
end

function SWEP:DrawWorldModel()
    local owner = self:GetOwner()
    if IsValid(owner) then
        local boneIndex = owner:LookupBone("ValveBiped.Bip01_R_Hand")
        if boneIndex then
            local pos, ang = owner:GetBonePosition(boneIndex)
            if pos and ang then
                pos = pos + self.Offset.Pos.x * ang:Right() + self.Offset.Pos.y * ang:Forward() + self.Offset.Pos.z * ang:Up()
                ang:RotateAroundAxis(ang:Right(), self.Offset.Ang.p)
                ang:RotateAroundAxis(ang:Up(), self.Offset.Ang.y)
                ang:RotateAroundAxis(ang:Forward(), self.Offset.Ang.r)

                self:SetPos(pos)
                self:SetAngles(ang)
                self:SetupBones()
                self:SetModelScale(self.Offset.Size, 0)
                self:DrawModel()
                return
            end
        end
    end

    self:DrawModel()
end

if CLIENT then
    local preview

    local function getPreviewModel(model)
        if not IsValid(preview) then
            preview = ClientsideModel(model)
            preview:SetNoDraw(true)
        end

        return preview
    end

    function SWEP:DrawHUD()
        local owner = self:GetOwner()
        if not IsValid(owner) then return end

        local tr = owner:GetEyeTrace()
        if not canPlace(owner, tr) then return end

        local mdl = getPreviewModel(self.WorldModel)
        if not IsValid(mdl) then return end

        local ang = tr.HitNormal:Angle()
        ang:RotateAroundAxis(ang:Right(), -90)

        cam.Start3D()
            mdl:SetPos(tr.HitPos + tr.HitNormal * 1.2)
            mdl:SetAngles(ang)
            mdl:SetMaterial("models/wireframe")
            mdl:SetColor(Color(255, 255, 255, 180))
            mdl:DrawModel()
            mdl:SetMaterial("")
            mdl:SetColor(color_white)
        cam.End3D()
    end
end

