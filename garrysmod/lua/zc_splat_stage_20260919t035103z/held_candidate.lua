return function()
		heldents = heldents or {}
		for i, tbl in pairs(heldents) do
			if not tbl or not IsValid(tbl[1]) then
				if IsValid(tbl[2]) then
					hg.SetCarryEnt2(tbl[2])
				end
				heldents[i] = nil

				continue
			end

			local ent, ply, dist, target, bone, pos, lang = tbl[1], tbl[2], tbl[3], tbl[4], tbl[5], tbl[6], tbl[7]
			local phys = ent:GetPhysicsObjectNum(bone)

			if not IsValid(phys) or not IsValid(ply) or not IsValid(ent) or not ply:Alive() or (ply:GetGroundEntity() == ent) or (ply:GetEntityInUse() == ent) or IsValid(ply.FakeRagdoll) or ply:KeyPressed(IN_RELOAD) then
				hg.SetCarryEnt2(ply)
				heldents[i] = nil

				continue
			end

			local wep = ply:GetActiveWeapon()
			if wep.GetCarrying and wep:GetCarrying() == ent then continue end

			if ply:KeyDown(IN_USE) then
				if not ent.rememberedang or not ent.oldaddang then
					ent.oldaddang = ent.addang or Angle(0,0,0)
					ent.rememberedang = ply:EyeAngles()
				end

				local _,ang = WorldToLocal(vector_origin, ply:EyeAngles(), vector_origin, ent.rememberedang)
				ent.addang = ang + ent.oldaddang
				ent.addang[1] = math.Clamp(ent.addang[1],-80,80)
				ent.addang[2] = math.Clamp(ent.addang[2],-80,80)
				ent.addang[3] = math.Clamp(ent.addang[3],-80,80)
				ent.rememberedang[1] = math.Clamp(ent.rememberedang[1],ply:EyeAngles()[1] - 40,ply:EyeAngles()[1] + 40)
				ent.rememberedang[2] = math.Clamp(ent.rememberedang[2],ply:EyeAngles()[2] - 40,ply:EyeAngles()[2] + 40)
				ent.rememberedang[3] = math.Clamp(ent.rememberedang[3],ply:EyeAngles()[3] - 40,ply:EyeAngles()[3] + 40)
			else
				ent.oldaddang = ent.addang or Angle(0,0,0)
				ent.rememberedang = ply:EyeAngles()
			end

			local TargetPos = phys:GetPos()

			if ent:IsRagdoll() then
				TargetPos = LocalToWorld(pos, angle_zero, phys:GetPos(), phys:GetAngles())
			else
				TargetPos = ent:LocalToWorld(pos)
			end

			local target,_ = LocalToWorld(target,angle_zero,ply:EyePos(),(ent.rememberedang or ply:EyeAngles()) - (not ply:KeyDown(IN_USE) and ent.addang or ent.oldaddang or angle_zero))
			local vec = target - TargetPos
			local len, mul = vec:Length(), phys:GetMass()
	
			vec:Normalize()
	
			if (ply.organism and ply.organism.superfighter) then
				mul = mul * 5
			end
	
			if (ply.organism and ply:IsBerserk()) then
				mul = mul * (1 + ply.organism.berserk / 5)
			end
	
			local avec = vec * len * 8 - phys:GetVelocity()
	
			local Force = avec * mul
			local ForceMagnitude = math.min(Force:Length(), 3000) * (1 / math.max(phys:GetVelocity():Dot(vec) / 25, 1))
	
			Force = Force:GetNormalized() * ForceMagnitude

			phys:Wake()

			if len > 100 then
				hg.SetCarryEnt2(ply)
				heldents[i] = nil
				
				continue
			end
	
			ent:SetPhysicsAttacker(ply, 15)

			Force = Force:GetNormalized() * ForceMagnitude

			--ply:SetLocalVelocity(ply:GetVelocity() - (avec - velo / 2))

			local ang = (ent.rememberedang or ply:EyeAngles()) - (ent.oldaddang or angle_zero)
			ang[3] = 0
			local _,huy = WorldToLocal(vector_origin,phys:GetAngles(),vector_origin,ang)
			local _,needed_ang = WorldToLocal(vector_origin,lang,vector_origin,huy)

			local vec = Vector(0,0,0)
			vec[3] = needed_ang[2]
			vec[1] = needed_ang[3]
			vec[2] = needed_ang[1]

			if tbl[6] then
				phys:ApplyForceOffset(Force, TargetPos)
			else
				phys:ApplyForceCenter(Force)
			end

			phys:ApplyForceCenter(Vector(0, 0, mul))
			local m2 = 1 / phys:GetMass() * math.min(phys:GetMass(), 5)
			phys:AddAngleVelocity(-phys:GetAngleVelocity() * m2 + vec / 1 * (ent:IsRagdoll() and 1 or 1) * m2)

			if wep.GetCarrying and ply:KeyDown(IN_ATTACK) then
				phys:ApplyForceCenter(ply:GetAimVector() * math.min(5000, phys:GetMass() * 800))
				hook.Run("ZCityHandsThrown", ply, ent) -- Cosmetic throw notification.
				
				hg.SetCarryEnt2(ply)
				heldents[i] = nil
			end
		end
end
