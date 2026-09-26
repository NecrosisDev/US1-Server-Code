function SWEP:PrimaryAttack()
	if SERVER then--and not self.modeValuesdef[self.mode][2] then

		self.healbuddy = self:GetOwner()
		local done = self:Heal(self.healbuddy, self.mode)
		
		if(done and self.PostHeal)then
			self:PostHeal(self.healbuddy, self.mode)
		end

		PublishModeValues(self)
	end
end