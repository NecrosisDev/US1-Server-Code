-- ZC TEMP V - the syringe. Fire once to inject: super strength +
-- speed, 30% roll of HEAT VISION (weapon_tempv_laser), and a crash
-- when it wears off. One dose, no going back. (zc_tempv addon)
AddCSLuaFile()

SWEP.PrintName        = "Temp V"
SWEP.Author           = "ZCity"
SWEP.Instructions     = "FIRE to inject. Your damage will hurt Homelander. 30% chance of heat vision. It WILL wear off."
SWEP.Category         = "ZCity"

SWEP.Spawnable        = true
SWEP.AdminOnly        = true

SWEP.ViewModel        = "models/weapons/c_medkit.mdl"
SWEP.WorldModel       = "models/healthvial.mdl"
SWEP.UseHands         = true
SWEP.HoldType         = "slam"

SWEP.Primary.ClipSize     = -1
SWEP.Primary.DefaultClip  = -1
SWEP.Primary.Automatic    = false
SWEP.Primary.Ammo         = "none"
SWEP.Secondary.ClipSize   = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic  = false
SWEP.Secondary.Ammo       = "none"

SWEP.DrawAmmo = false

function SWEP:Initialize()
	self:SetHoldType(self.HoldType)
end

function SWEP:PrimaryAttack()
	self:SetNextPrimaryFire(CurTime() + 2)
	if not SERVER then return end
	local ply = self:GetOwner()
	if not IsValid(ply) then return end
	if ZCTEMPV and ZCTEMPV.Inject then
		ZCTEMPV.Inject(ply)
	end
	self:Remove()
end

function SWEP:SecondaryAttack()
	self:SetNextSecondaryFire(CurTime() + 1)
end

if CLIENT then
	function SWEP:DrawHUD()
		draw.SimpleText("TEMP V - fire to inject (no going back)", "Default",
			ScrW() / 2, ScrH() * 0.62, Color(90, 150, 255, 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end
