-- ZC TEMP V - HEAT VISION: the "neutered homelander swep" (per Joey:
-- laser eyes ONLY - no grab, no flight, no punches, no invulnerability).
-- The beam itself is fired by zc_tempv's serverside 0.1s eye-trace
-- while this weapon is out and RMB is held; this file is just the
-- selectable shell so the player SEES they rolled heat vision.
AddCSLuaFile()

SWEP.PrintName        = "Heat Vision (Temp V)"
SWEP.Author           = "ZCity"
SWEP.Instructions     = "HOLD RMB: laser eyes. Drains Homelander's vitality hard. Burns anyone else it touches."
SWEP.Category         = "ZCity"

SWEP.Spawnable        = true
SWEP.AdminOnly        = true

SWEP.ViewModel        = "models/weapons/c_medkit.mdl" -- hidden below
SWEP.WorldModel       = ""
SWEP.UseHands         = false
SWEP.HoldType         = "normal"

SWEP.Primary.ClipSize     = -1
SWEP.Primary.DefaultClip  = -1
SWEP.Primary.Automatic    = false
SWEP.Primary.Ammo         = "none"
SWEP.Secondary.ClipSize   = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic  = true
SWEP.Secondary.Ammo       = "none"

SWEP.DrawAmmo = false

function SWEP:Initialize()
	self:SetHoldType(self.HoldType)
end

function SWEP:PrimaryAttack()
	self:SetNextPrimaryFire(CurTime() + 1)
end

-- RMB is read by the server trace timer via KeyDown - nothing here
function SWEP:SecondaryAttack()
	self:SetNextSecondaryFire(CurTime() + 0.1)
end

if CLIENT then
	function SWEP:PreDrawViewModel()
		return true -- eyes are the weapon: hide the viewmodel entirely
	end

	function SWEP:DrawHUD()
		draw.SimpleText("HEAT VISION - hold RMB", "Default",
			ScrW() / 2, ScrH() * 0.62, Color(255, 90, 60, 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end
