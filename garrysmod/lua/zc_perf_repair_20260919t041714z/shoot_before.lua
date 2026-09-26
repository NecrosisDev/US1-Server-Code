function SWEP:Shoot(override)
	self:PrimaryShootPre()

	local owner = self:GetOwner()
	if owner:IsNPC() then self.drawBullet = true end

	if !override and !self:CanPrimaryAttack() then return false end
	if !override and !self:CanUse() then return false end
	if CLIENT and owner != LocalPlayer() and !override then return false end

	local primary = self.Primary
	if override then self.drawBullet = true end
	
	if !self.drawBullet or (self:Clip1() == 0 and !override) then
		self.LastPrimaryDryFire = CurTime()
		self:PrimaryShootEmpty()
		primary.Automatic = false

		return false
	end
	
	if !override and IsValid(owner) and !owner:IsNPC() and primary.Next > CurTime() then return false end
	if !override and IsValid(owner) and !owner:IsNPC() and (primary.NextFire or 0) > CurTime() then return false end
	
	primary.Next = CurTime() + primary.Wait * 1.1
	primary.RealAutomatic = primary.RealAutomatic or weapons_Get(self:GetClass()).Primary.Automatic
	primary.Automatic = primary.RealAutomatic
	
	if CLIENT then self:SetClip1(self:GetNWInt("Clip1")) end
	
	self:PrimaryShoot()
	self:PrimaryShootPost()
end