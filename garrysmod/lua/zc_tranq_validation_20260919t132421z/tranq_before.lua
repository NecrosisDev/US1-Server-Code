function SWEP:Shoot(override)
	--self:GetWeaponEntity():ResetSequenceInfo()
	--self:GetWeaponEntity():SetSequence(1)
	if self:GetOwner():IsNPC() then self.drawBullet = true end
	if not self:CanPrimaryAttack() then return false end
	if not self:CanUse() then return false end
	if CLIENT and self:GetOwner() != LocalPlayer() and not override then return false end
	local primary = self.Primary
	if override then self.drawBullet = override end

	if not self.drawBullet or (self:Clip1() == 0 and not override) then
		self.LastPrimaryDryFire = CurTime()
		self:PrimaryShootEmpty()
		primary.Automatic = false
		return false
	end

	if not self:GetOwner():IsNPC() and primary.Next > CurTime() then return false end
	if not self:GetOwner():IsNPC() and (primary.NextFire or 0) > CurTime() then return false end

	primary.Next = CurTime() + primary.Wait
	primary.RealAutomatic = primary.RealAutomatic or weapons_Get(self:GetClass()).Primary.Automatic
	primary.Automatic = primary.RealAutomatic
	self:PrimaryShoot()
	self:PrimaryShootPost()
end
