if SERVER then
    AddCSLuaFile()
    AddCSLuaFile("zc_hmcd_mutators/cl_phone.lua")
    AddCSLuaFile("zc_hmcd_mutators/sh_phone_pose.lua")
end
SWEP.Base = "weapon_base"
SWEP.PrintName = "Unknown Caller"
SWEP.Instructions = "Primary attack: answer. Secondary attack: hang up."
SWEP.Spawnable = false
SWEP.AdminOnly = true
SWEP.Slot = 4
SWEP.SlotPos = 8
SWEP.Weight = 0
SWEP.AutoSwitchTo = false
SWEP.AutoSwitchFrom = false
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = false
SWEP.ViewModel = ""
SWEP.WorldModel = "models/saraphines/insurgency explosives/ied/insurgency_ied_phone.mdl"
SWEP.HoldType = "normal"
SWEP.RingSound = "homigrad/vgui/beep22.wav" -- Existing ZCity Content 2 sound; no custom FastDL file required.
SWEP.NoDrop = true
SWEP.DontEquipInstantly = true
SWEP.WorkWithFake = false
-- Intentionally no weaponInvCategory: this utility must never displace a pistol.
SWEP.Primary = {ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none"}
SWEP.Secondary = {ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none"}
function SWEP:SetupDataTables()
    self:NetworkVar("Int", 0, "CallPhase")
    self:NetworkVar("Float", 0, "PhaseStart")
end
function SWEP:Initialize() self:SetHoldType("normal") end
function SWEP:PlayRing() self:EmitSound(self.RingSound, 70, 100, 0.8, CHAN_ITEM) end
function SWEP:StopRing() self:StopSound(self.RingSound) end
function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.3)
    if SERVER and ZC_HMCD_MUTATORS then ZC_HMCD_MUTATORS:InformantAnswer(self, self:GetOwner()) end
end
function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.3)
    if SERVER and ZC_HMCD_MUTATORS then ZC_HMCD_MUTATORS:InformantAbort(self, "hung up") end
end
function SWEP:Reload() end
function SWEP:Holster()
    if SERVER and self:GetCallPhase() > 0 and ZC_HMCD_MUTATORS then
        ZC_HMCD_MUTATORS:InformantAbort(self, "phone put away")
    end
    return true
end
function SWEP:OnDrop()
    if SERVER then
        if ZC_HMCD_MUTATORS then ZC_HMCD_MUTATORS:InformantAbort(self, "phone dropped") end
    end
end
function SWEP:OnRemove()
    if SERVER then self:StopRing() end
    if CLIENT and IsValid(self.PhoneModel) then self.PhoneModel:Remove() end
end
if CLIENT then include("zc_hmcd_mutators/cl_phone.lua") end
