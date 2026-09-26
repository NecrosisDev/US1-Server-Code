function SWEP:PrimaryAttack()
	if SERVER then--and not self.modeValuesdef[self.mode][2] then

		self.healbuddy = self:GetOwner()
		local done = self:Heal(self.healbuddy, self.mode)
		
		if(done and self.PostHeal)then
			self:PostHeal(self.healbuddy, self.mode)
		end

		if self.net_cooldown2 < CurTime() then
			self:SetNetVar("modeValues",self.modeValues)
			--self.net_cooldown2 = CurTime() + 0.1
		end
	end
end