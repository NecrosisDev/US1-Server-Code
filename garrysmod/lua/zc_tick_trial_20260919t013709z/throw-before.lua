function SWEP:Throw(mul, time, nosound, throwPosAdjust, throwAngAdjust)
	if not self.ENT then return end

	local owner = self.Thrower or self:GetOwner()
	local ent = ents.Create(self.ENT)
	local entOwner = IsValid(owner.FakeRagdoll) and owner.FakeRagdoll or IsValid(owner) and owner
	throwPosAdjust = throwPosAdjust or Vector(0,0,5)
	throwAngAdjust = throwAngAdjust or Angle(0,0,0)
	--throwPosAdjust[2] = throwPosAdjust[2] + 2
	local _,_,headm = self:GetEyeTrace()
	local eyepos = headm:GetTranslation() or false
	local ang = IsValid(entOwner) and owner:EyeAngles() or self:GetAngles()
	local hand = eyepos and eyepos + ang:Forward() * throwPosAdjust[1] + ang:Right() * (throwPosAdjust[2] + 2) + ang:Up() * throwPosAdjust[3] or self:GetPos()

	if IsValid(entOwner) then
		ent:SetOwner(entOwner or game.GetWorld())
	end
	
	ent.team = owner:Team()
	ent.steamid = owner:SteamID()

	if not nosound and IsValid(entOwner) then
		entOwner:EmitSound(self.throwsound or "weapons/m67/m67_throw_01.wav", 90, math.random(95, 105))
	end

	if SERVER and IsValid(owner) and owner:IsPlayer() then
		local playerClass = owner.PlayerClassName
		if playerClass == "terrorist" or playerClass == "nationalguard" or
		   playerClass == "commanderforces" or playerClass == "swat" then
			timer.Simple(0.1, function()
				if IsValid(owner) and hg and hg.GetPlayerClassPhrases then
					local classPhrases = hg.GetPlayerClassPhrases(owner, "grenade_throw")
					if classPhrases and #classPhrases > 0 then
						local randomPhrase = classPhrases[math.random(#classPhrases)]
						local ent_char = hg.GetCurrentCharacter(owner)
						local muffed = owner.armors and owner.armors["face"] == "mask2"
						
						if IsValid(ent_char) then
							ent_char:EmitSound(randomPhrase, muffed and 75 or 85, owner.VoicePitch or 100, 1, CHAN_AUTO, 0, muffed and 14 or 0)
						else
							owner:EmitSound(randomPhrase, muffed and 75 or 85, owner.VoicePitch or 100, 1, CHAN_AUTO, 0, muffed and 14 or 0)
						end
						
						owner.lastPhr = randomPhrase
					end
				end
			end)
		end
	end

	if IsValid(owner) then
		owner:ViewPunch(Angle(3,0,0))
		owner:AnimRestartGesture(GESTURE_SLOT_GRENADE, ACT_HL2MP_GESTURE_RANGE_ATTACK_GRENADE, true)
	end
	ent:SetCollisionGroup( COLLISION_GROUP_WEAPON )
	timer.Simple(0.15,function()
		if IsValid(ent) then
			ent:SetCollisionGroup( COLLISION_GROUP_INTERACTIVE )
		end
	end)
	ent:Spawn()
	ent:SetPos(hand + (IsValid(owner) and self:GetAngles():Forward() * 5 or vector_origin))
	local angThrow = IsValid(owner) and owner:EyeAngles() or self:GetAngles()
	angThrow:RotateAroundAxis(angThrow:Forward(),throwAngAdjust[1])
	angThrow:RotateAroundAxis(angThrow:Right(),throwAngAdjust[2])
	angThrow:RotateAroundAxis(angThrow:Up(),throwAngAdjust[3])
	ent:SetAngles(angThrow)
	local phys = ent:GetPhysicsObject()
	if phys then 
		real_ent = hg.GetCurrentCharacter(owner)
		phys:SetVelocity(IsValid(real_ent) and (owner:GetAimVector() * mul/1.5) + real_ent:GetVelocity() or Vector(0,0,0)) 
	end
	if owner:IsOnGround() then
		owner:SetVelocity(owner:GetVelocity() - owner:GetVelocity()/2)
	end
	ent.timer = time
	ent.owner = self.lastOwner
	ent.owner2 = self.lastOwner

	--self.removed = true
	if IsValid(owner) then
		self:ThrowAdd()
	end

	self.Thrower = nil
end
