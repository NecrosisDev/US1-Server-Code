return function(self, ent, bone, pos, dist)
	local owner = self:GetOwner()
	if not IsValid(owner) then return end

	if IsValid(ent) or game.GetWorld() == ent then
		self.CarryEnt = ent
		if SERVER then hook.Run("ZCityHandsPickedUp", owner, ent) end
		self.CarryBone = bone
		self.CarryDist = dist

		local phys = self.CarryEnt:GetPhysicsObjectNum(self.CarryBone)

		if ent:GetClass() ~= "prop_ragdoll" then
			self.CarryPos = ent:WorldToLocal(pos)
		else
			self.CarryPos = WorldToLocal(pos, angle_zero, phys:GetPos(), phys:GetAngles())
		end

		if not IsValid(owner:GetNetVar("carryent")) then
			owner:SetNetVar("carryent", self.CarryEnt)
			owner:SetNetVar("carrybone", self.CarryBone)
			owner:SetNetVar("carrymass", phys:GetMass())
			owner:SetNetVar("carrypos", self.CarryPos)
		end

		if not self.CarryEnt:GetCustomCollisionCheck() then
			self.CarryEnt:SetCustomCollisionCheck(true)
			self.CarryEnt:CollisionRulesChanged()
			owner:CollisionRulesChanged()

			self.CarryEnt:CallOnRemove("removenarsla",function()
				if not IsValid(owner) then return end
				owner:CollisionRulesChanged()
				owner:SetNetVar("carryent",nil)
				owner:SetNetVar("carrybone",nil)
				owner:SetNetVar("carrymass",nil)
				owner:SetNetVar("carrypos",nil)
			end)

			owner:SetNetVar("carrymass",self.CarryEnt:GetPhysicsObjectNum(self.CarryBone):GetMass())
		end
	else
		if IsValid(self.CarryEnt) and self.CarryEnt:GetCustomCollisionCheck() then
			self.CarryEnt:CollisionRulesChanged()
			owner:CollisionRulesChanged()
			//self.CarryEnt:SetCustomCollisionCheck(false)
		end

		if IsValid(owner:GetNetVar("carryent")) then
			owner:SetNetVar("carryent",nil)
			owner:SetNetVar("carrybone",nil)
			owner:SetNetVar("carrypos",nil)
			owner:SetNetVar("carrymass",0)
		end

		self.CarryEnt = nil
		self.CarryBone = nil
		self.CarryPos = nil
		self.CarryDist = nil
	end
end