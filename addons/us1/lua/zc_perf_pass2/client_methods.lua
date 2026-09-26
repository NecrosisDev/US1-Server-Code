if SERVER then return end
local SWEP={}
local vecZero=Vector(0,0,0)
local angZero=Angle(0,0,0)
local addAngle=Angle(0,0,0)
function SWEP:WorldModel_Transform(bNoApply, bNoAdditional, model)
    local model, owner = model or self.worldModel, self:GetOwner()
    local controlled = IsValid(owner) and (owner:IsNPC() or owner:IsPlayer())
    local ent, inuse, should
    if controlled then
        ent = IsValid(owner.FakeRagdoll) and owner.FakeRagdoll or owner
        inuse = self:InUse()
        should = hg.ShouldTPIK(owner) and not (ent ~= owner and not inuse)
        if not should and not IsValid(owner.FakeRagdoll) then
            self.last_transform = SysTime()
            if IsValid(model) then
                model:SetModel(self.WorldModel)
                model:AddEffects(EF_BONEMERGE)
                model:SetParent(owner)
                model:Remove()
            end
            return
        end
    end
    if not IsValid(model) then self.worldModel = self:CreateWorldModel(); model = self.worldModel end
    if not IsValid(model) then return end
    if controlled then
        local dtime = SysTime() - (self.last_transform or SysTime())
        self.last_transform = SysTime()
        -- Visible weapon and live-ragdoll transforms retain the original cadence.

		
		local RHand = ent:LookupBone("ValveBiped.Bip01_R_Hand")
		
		if not RHand then return end

		local matrixR = ent:GetBoneMatrix(RHand)
        if not matrixR then
            local forearm = ent:LookupBone("ValveBiped.Bip01_R_Forearm")
            if forearm ~= nil then matrixR = ent:GetBoneMatrix(forearm) end
        end
		
		if not matrixR then 
			//matrixR = Matrix()
			//local att = ent:GetAttachment(ent:LookupAttachment("anim_attachment_RH"))
			//matrixR:SetTranslation(att.Pos)
			//matrixR:SetAngles(att.Ang)
			return
		end
		
		local aimvec = ent:IsNPC() and matrixR:GetAngles() or owner:GetAimVector():Angle()

		//self:ChangeGunPos()
		
		local matrixRAngRot = matrixR:GetAngles()
		matrixRAngRot:RotateAroundAxis(matrixRAngRot:Forward(),180)
		local lerp = self:KeyDown(IN_ATTACK2) and 1 or 1
		local _, ang = WorldToLocal(vecZero,matrixRAngRot,vecZero,aimvec)
		ang = ang * lerp
		local _,ang = LocalToWorld(vecZero,ang,vecZero,aimvec)
		ang[3] = matrixRAngRot[3]
		local desiredAng = ((ent~=owner)) and ang or aimvec
		desiredAng[3] = desiredAng[3] + (owner:EyeAngles()[3])
		desiredAng:RotateAroundAxis(desiredAng:Forward(), ent:IsNPC() and 0 or 180)
		local desiredPos = matrixR:GetTranslation()
		
		--local oldPos = -(-desiredPos)
		--local oldAng = -(-desiredAng)
				
		if !owner:IsNPC() then//should then
			local desiredPos1, desiredAng1 = self:PosAngChanges(owner, desiredPos, desiredAng, bNoAdditional, nil, dtime)
			
			desiredPos = LerpVector(self.lerped_positioning or 0, desiredPos, desiredPos1)
			desiredAng = LerpAngle(self.lerped_angle or 0, desiredAng, desiredAng1)
			--self.lastTpikPos = desiredPos
			--self.lastTpikAng = desiredAng
		end
		
		--self.fuckhands = LerpFT(0.1, self.fuckhands, self.setrhik and 1 or 0)

		--desiredPos = LerpVector(self.fuckhands, oldPos, self.lastTpikPos or desiredPos)
		--desiredAng = LerpAngle(self.fuckhands, oldAng, self.lastTpikAng or desiredAng)

		local newPos, newAng = LocalToWorld(self.WorldPos, self.WorldAng + (self.WorldAng2 or angle_zero), desiredPos, desiredAng)
		newAng:RotateAroundAxis(newAng:Forward(), 180)
		
		if self:ShouldUseFakeModel() then
			newPos, newAng = LocalToWorld(self.FakePos, self.FakeAng, newPos, newAng)
		end
		
		if bNoApply then
			return newPos, newAng, desiredPos, desiredAng
		end

		self.desiredPos, self.desiredAng = newPos, newAng
		self.handPos, self.handAng = desiredPos, desiredAng
		
		model:SetRenderOrigin(newPos)
		model:SetRenderAngles(newAng)
		model:SetPos(newPos)
		model:SetAngles(newAng)
		self:DrawShadow(true)
	else
		local pos, ang = self:GetPos(), self:GetAngles()

		if self:ShouldUseFakeModel() then
			pos, ang = LocalToWorld(self.FakePos, self.FakeAng, pos, ang)
		end
		
		model:SetRenderOrigin(pos)
		model:SetRenderAngles(ang)
		model:SetPos(pos)
		model:SetAngles(ang)
		self:DrawShadow(false)
	end
end

function SWEP:WorldModel_Transform_Holstered()
	local model, owner = self.worldModel, self:GetOwner()
	if not IsValid(model) then model = self:CreateWorldModel() end
	
	local ent = IsValid(owner.FakeRagdoll) and owner.FakeRagdoll or owner
	
	if not IsValid(ent) then
		model:SetNoDraw(true)
		return
	end

	local inv = owner:IsPlayer() and owner:GetNetVar("Inventory")
	
	if IsValid(ent) then
		local noSling = inv and (not inv["Weapons"] or not inv["Weapons"]["hg_sling"]) and not self.shouldntDrawHolstered
		--if noSling then self:WorldModel_Transform() return end
		--потом...
		--local bone = noSling and noSlingBone or self.holsteredBone
		--local pos = noSling and noSlingPos or self.holsteredPos
		--local ang = noSling and noSlingAng or self.holsteredAng
		local bone = self.holsteredBone
		local pos = self.holsteredPos
		local ang = self.holsteredAng

		local boneIndex = ent:LookupBone(bone)
        if boneIndex == nil then return end
        local matrix = ent:GetBoneMatrix(boneIndex)
		if not matrix then return end
		local localPos, localAng = pos, ang
		
		local ang = owner:GetAngles()
		
		if owner:IsPlayer() then
			ang = owner:EyeAngles()
			ang[1] = 0
			local vel = ent:GetVelocity()
			local dotforward = vel:Dot(ang:Forward())
			local dotright = vel:Dot(ang:Right())
			
			addAngle[2] = math.Clamp(-dotforward / 3, -1, 10) + math.abs(math.Clamp(dotright / 1, -3, 3))
			addAngle[1] = math.Clamp(dotright / 3, -10, 10)
			
			self.addAngle = LerpAngleFT(0.05, self.addAngle, addAngle)
		else
			addAngle:Zero()
		end

		local desiredPos, desiredAng = LocalToWorld(localPos, localAng, matrix:GetTranslation(), matrix:GetAngles())
		
		desiredAng:RotateAroundAxis(ang:Right(), self.addAngle[2])
		desiredAng:RotateAroundAxis(ang:Forward(), self.addAngle[1])

		local newPos, newAng = LocalToWorld(self.WorldPos, self.WorldAng, desiredPos, desiredAng)
		if self:ShouldUseFakeModel() then
			newPos, newAng = LocalToWorld(self.FakePos, self.FakeAng, newPos, newAng)
		end
		local booba = self.deploy
		local booba2 = self.deploy and (self.CooldownDeploy / self.Ergonomics)
		
		local lerp = (not booba) and 0 or math.Clamp(1 - ((booba - CurTime()) / booba2) * 1.2, 0, 1)
		lerp = math.ease.InOutExpo(lerp)
		
		local newPos = LerpVector(lerp, newPos, model:GetPos())
		local newAng = LerpAngle(lerp, newAng, model:GetAngles())
		
		local matrix = Matrix()
		matrix:SetTranslation(self.WorldPos)
		matrix:SetAngles(self.WorldAng)
		local newmat = matrix:GetInverse()
		local ang = -(-newAng)
		ang:RotateAroundAxis(ang:Forward(),180)
		
		local desiredPos, desiredAng = LocalToWorld(newmat:GetTranslation(), newmat:GetAngles(), newPos, ang)

		self.handPos, self.handAng = desiredPos, desiredAng

		self.holstercheckwait = CurTime()--FUCKING FUCK

		model:SetRenderOrigin(newPos)
		model:SetRenderAngles(newAng)
		model:SetPos(newPos)
		model:SetAngles(newAng)
		self.desiredPos = newPos
		self.desiredAng = newAng
	else
		local pos, ang = self:GetPos(), self:GetAngles()

		if self:ShouldUseFakeModel() then
			pos, ang = LocalToWorld(self.FakePos, self.FakeAng, pos, ang)
		end

		model:SetRenderOrigin(pos)
		model:SetRenderAngles(ang)
		model:SetPos(pos)
		model:SetAngles(ang)
		model:SetRenderOrigin()
		model:SetRenderAngles()
	end
end

local base=assert(weapons.GetStored("homigrad_base"),"Weapon base not ready")
local names={"WorldModel_Transform","WorldModel_Transform_Holstered"}
local old={};for _,key in ipairs(names)do assert(isfunction(base[key]),key);old[key]=base[key]end
local count=0
local function patch(t)
    for _,key in ipairs(names)do
        if t[key]==old[key] then t[key]=SWEP[key];count=count+1 end
    end
end
for _,entry in ipairs(weapons.GetList())do
    local t=weapons.GetStored(entry.ClassName);if t then patch(t)end
end
for _,e in ipairs(ents.GetAll())do if IsValid(e) and e:IsWeapon() then patch(e)end end
patch(base)
ZCPerf2Client={Version="20260916.1",changed=count,methods=SWEP}
