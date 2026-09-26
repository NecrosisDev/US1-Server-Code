return function(self)
	local ply = self:GetOwner()
	local target = self:GetOwner():GetAimVector() * self.CarryDist + select(1, hg.eye(ply))
	if not IsValid(self.CarryEnt) then return end
	local phys = self.CarryEnt:GetPhysicsObjectNum(self.CarryBone)

	if ply.organism and ply.organism.rarmamputated and ply:IsTyping() then
		self:SetCarrying()

		return
	end
	
	if IsValid(phys) then
		local TargetPos = phys:GetPos()

		if self.CarryEnt.poisoned then
			if ply.organism then
				ply.organism.poison2 = CurTime()
				self.CarryEnt.poisoned = nil
			end
		end

		if self.CarryEnt.organism and ((ply.sendTimeOrg or 0) < CurTime()) then
			ply.sendTimeOrg = CurTime() + 0.5

			//hg.send_organism(self.CarryEnt.organism, ply)
		end

		if self.CarryPos then
			if self.CarryEnt:IsRagdoll() then
				TargetPos = LocalToWorld(self.CarryPos, angle_zero, phys:GetPos(), phys:GetAngles())
			else
				TargetPos = self.CarryEnt:LocalToWorld(self.CarryPos)
			end
		end

		local vec = target - TargetPos
		local len, mul = vec:Length(), phys:GetMass()

		vec:Normalize()

		if (ply.organism and ply.organism.superfighter) then
			mul = mul * 5
		end

		local isCrusher = ply.SubRole == "traitor_strangler" or ply.SubRole == "traitor_strangler_soe"

		if (ply.organism and ply:IsBerserk()) then
			mul = mul * (1 + ply.organism.berserk / 5)
		end

		local avec = vec * len * 8 - phys:GetVelocity()

		local Force = avec * mul
		local ForceMagnitude = math.min(Force:Length(), 3000) * (1 / math.max(phys:GetVelocity():Dot(vec) / 25, 1))

		Force = Force:GetNormalized() * ForceMagnitude

		if len > (isCrusher and 300 or 100) then
			self:SetCarrying()
			return
		end

		phys:Wake()
		self.CarryEnt:SetPhysicsAttacker(ply, 15)

		if SERVER then
			if self.CarryEnt.welds then
				for i, weld in pairs(self.CarryEnt.welds) do
					if IsValid(weld) then weld:Remove() end
				end
				self.CarryEnt.welds = nil
			end
			if (ply:GetGroundEntity() == self.CarryEnt) or (ply:GetEntityInUse() == self.CarryEnt) or IsValid(ply.FakeRagdoll) or self.CarryEnt:IsPlayerHolding() then
				self:SetCarrying()
				return
			end
		end

		if self.CarryEnt:GetClass() == "ent_hg_cyanide_canister" then
			ply.Guilt = math.max(ply.Guilt, 5)
		end

		if self.CarryEnt:GetClass() == "prop_ragdoll" then
			local ply2 = RagdollOwner(self.CarryEnt) or self.CarryEnt
			local bone = self.CarryEnt:GetBoneName(self.CarryEnt:TranslatePhysBoneToBone(self.CarryBone))

			if ply:KeyPressed(IN_RELOAD) then
				if not ply2.noHead and ply2.organism then

					if ply2.organism.CantCheckPulse then
						--ply:ChatPrint("The armor is too thick to feel the pulse.")
					elseif ((bone == "ValveBiped.Bip01_L_Hand") or (bone == "ValveBiped.Bip01_R_Hand") or (bone == "ValveBiped.Bip01_Head1")) then
						local org = ply2.organism

						if org.heartstop then
							--ply:ChatPrint("No pulse.")
						else
							--ply:ChatPrint(org.pulse < 20 and "Barely can feel the pulse." or (org.pulse <= 50 and "Low pulse.") or (org.pulse <= 90 and "Normal pulse.") or "High pulse.")
						end

						if (org.last_heartbeat + 60) > CurTime() then
							ply:ChatPrint("The body is still warm.")
						else
							ply:ChatPrint((org.last_heartbeat + 180) < CurTime() and "The body has been here for awhile." or "The body is slightly warm")
						end

						if org.blood < 3500 then
							//if org.blood < 1000 then
								//ply:ChatPrint("The skin looks almost white.")
							//else
								ply:ChatPrint("The skin is pale.")
							//end
						end

						if org.bleed > 0 then
							ply:ChatPrint("The body is bleeding "..((org.bleed > 10 and "profusely.") or (org.bleed > 5 and "moderately.") or "slightly."))
						end

						//org.bulletwounds = 0
						//org.stabwounds = 0
						//org.slashwounds = 0
						//org.bruises = 0
						//org.burns = 0
						//org.explosionwounds = 0

						if org.bulletwounds > 0 then
							ply:ChatPrint("You notice "..org.bulletwounds.." bullet wounds on this body.")
						end

						if org.stabwounds > 0 then
							ply:ChatPrint("You notice "..org.stabwounds.." stab wounds on this body.")//28 STAB WOUNDS. YOU WOULDNT LEAVE HIM A CHANCE, HUH?
						end

						if org.slashwounds > 0 then
							ply:ChatPrint("You notice "..org.slashwounds.." slashes on this body.")
						end

						if org.bruises > 0 then
							ply:ChatPrint("You notice "..org.bruises.." bruises on this body.")
						end

						if org.burns > 0 then
							ply:ChatPrint("The body was burned.")
						end

						if org.explosionwounds > 0 then
							ply:ChatPrint("The body appears to have blast trauma.")
						end

						if (bone == "ValveBiped.Bip01_Head1") then
							if (org.o2.curregen == 0 or not org.alive or org.holdingbreath) then
								--ply:ChatPrint("Not breathing.")
							else
								--ply:ChatPrint("Breathing.")
							end

							--ply:ChatPrint(org.otrub and "No reaction." or "Reaction present.")

							if org.isPly and not org.otrub then
								org.owner:ChatPrint("You were checked for reaction.")
							end
						end
					end

					self.Checking = math.min(self.Checking + FrameTime() * 2, 10)
				else
					ply:Notify("I dont think I need to check their vitals.", 10)
				end
			end
		end

		if SERVER then
			local ply2 = self.CarryEnt
			local org = ply2.organism
			if ply:KeyDown(IN_ATTACK) and !ply.organism.superfighter and !isCrusher and !(org and ply.PlayerClassName == "furry" and org.owner.PlayerClassName != "furry") and !ply:IsBerserk() then
				local bone = self.CarryEnt:GetBoneName(self.CarryEnt:TranslatePhysBoneToBone(self.CarryBone))

				local tr = {}
				tr.start = TargetPos
				tr.endpos = TargetPos - vector_up * 32
				tr.mask = MASK_SOLID
				tr.filter = {self.CarryEnt, self, ply}
				local trace = util.TraceLine(tr)
				
				if bone != "ValveBiped.Bip01_Spine2" or !trace.Hit then
					phys:ApplyForceCenter(ply:GetAimVector() * math.min(5000, phys:GetMass() * 800))
					hook.Run("ZCityHandsThrown", ply, self.CarryEnt) -- Cosmetic throw notification.
					self:SetCarrying()
				end

				if org and bone == "ValveBiped.Bip01_Spine2" and trace.Hit then
					if self.firstTimePrint then
						if not ply2.noHead then
							ply:ChatPrint("You are beginning to perform CPR.")
						else
							ply:Notify("I dont think CPR would help here...", 10)
						end
					end

					self.firstTimePrint = false
					if (self.CPRThink or 0) < CurTime() then
						self.CPRThink = CurTime() + (1 / 120) * 60
						if org.alive then
							//org.o2[1] = math.min(org.o2[1] + hg.organism.OxygenateBlood(org) * 2 * (ply.Profession == "doctor" and 2 or 1), org.o2.range)
							org.pulse = math.min(org.pulse + 5 * (ply.Profession == "doctor" and 2 or 1),70)
							org.CO = math.Approach(org.CO, 0, (ply.Profession == "doctor" and 2 or 1))
							org.COregen = math.Approach(org.COregen, 0, (ply.Profession == "doctor" and 2 or 1))

							if math.random(3) == 1 then
								org.lungsfunction = true
							end

							if math.random(50) == 1 and (ply.Profession != "doctor") then
								local dmginfo = DamageInfo()
								dmginfo:SetDamageType(DMG_CRUSH)
								dmginfo:SetInflictor(self)
								hg.organism.input_list.chest(org, 1, 5, dmginfo)
							end

							if org.pulse > 15 then org.heartstop = false end
						end

						phys:ApplyForceCenter(-vector_up * 6000)

						--self.CarryEnt:EmitSound("physics/body/body_medium_impact_soft" .. tostring(math.random(7)) .. ".wav")
					end
				end
			else
				self.firstTimePrint = true
				self.firstTimePrint2 = true
			end

			if ply:KeyDown(IN_ATTACK) and ply.PlayerClassName == "furry" and org ~= nil and org.alive and org.owner.PlayerClassName != "furry" and !(org.owner.IsBerserk and org.owner:IsBerserk()) then
				org.assimilated = math.Approach(org.assimilated, 1, FrameTime() / 6)
				ply:SetLocalVar("assimilation", org.assimilated)

				hg.LightStunPlayer(org.owner, 1)

				//phys:ApplyForceCenter(ply:GetAimVector() * 40000 * self.Penetration)
				//self:SetCarrying()
			end

			if ply:KeyDown(IN_ATTACK) and (ply.organism.superfighter or ply:IsBerserk() or isCrusher) then
				local crusherScale = (isCrusher and not ply:IsBerserk() and not ply.organism.superfighter) and 0.4 or 1
				phys:ApplyForceCenter(ply:GetAimVector() * 40000 * self.Penetration * crusherScale * (1 + ply.organism.berserk / 10))
				hook.Run("ZCityHandsThrown", ply, self.CarryEnt) -- Cosmetic throw notification.
				self:SetCarrying()
			end
		end

		if self.CarryPos then
			phys:ApplyForceOffset(Force, TargetPos)
		else
			phys:ApplyForceCenter(Force)
		end

		--[[if IsValid(self.CarryEnt) and self.CarryBone then
			hg.ShadowControl(self.CarryEnt, self.CarryBone, 0.1, angle_zero, 0, 0, target, 60, 40)
		end]]

		if ply:KeyDown(IN_USE) then
			SetAng = SetAng or ply:EyeAngles()
			local commands = ply:GetCurrentCommand()
			local x, y = commands:GetMouseX(), commands:GetMouseY()
			if IsValid(self.CarryEnt) and self.CarryEnt:IsRagdoll() then
				rotate = Vector(0, -x, -y) / 6
			else
				rotate = Vector(0, -x, -y) / 4
			end

			//phys:AddAngleVelocity(rotate * phys:GetMass() / 10)
		end

		phys:ApplyForceCenter(Vector(0, 0, mul))
		phys:AddAngleVelocity(-phys:GetAngleVelocity() / 10)
	end
end