function SWEP:SecondaryAttack()
	--self:SetHolding(math.min(self:GetHolding() + 9, 100))
	if SERVER then
		if IsValid(self:GetNWEntity("fakeGun")) then return end
		local ent = hg.eyeTrace(self:GetOwner()).Entity
		self.healbuddy = ent
		if !IsValid(self.healbuddy) then return end
		if hg.GetCurrentCharacter(self.healbuddy) == hg.GetCurrentCharacter(self:GetOwner()) then return end
		local done = self:Heal(self.healbuddy, self.mode)
		if(done and self.PostHeal)then
			self:PostHeal(self.healbuddy, self.mode)
		end		

		if self.net_cooldown2 < CurTime() then
			self:SetNetVar("modeValues",self.modeValues)
			--self.net_cooldown2 = CurTime() + 0.1 * game.GetTimeScale()
		end
	end
end