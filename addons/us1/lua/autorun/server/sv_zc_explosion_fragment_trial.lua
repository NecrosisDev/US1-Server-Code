-- Server-only integration for the approved fragmentation trial.
if not SERVER then return end
local ID, SCHEDULER = 'ZCExplosionFragmentTrial20260920', 'ZCExplosionFragments20260920'
if _G[ID] then return _G[ID] end
local specs, sources = {{class="ent_hg_grenade",key="Explode",source="@addons/zcity/lua/entities/ent_hg_grenade/init.lua",first=142,last=429,hash="762524930e246ba00be7ea874a87185f188594e86f5e385a1e9bc9f0e24fd143"},{class="projectile_base",key="Detonate",source="@addons/zcity/lua/entities/projectile_base.lua",first=146,last=295,hash="9b58370e4f09d98ad0e965f58f178ef3f88150159b3d9d85527032176bfcc4e8"},{class="ent_claymore",key="ActivateExplosive",source="@addons/zcity/lua/entities/ent_claymore/init.lua",first=49,last=148,hash="57995b13f98fd68dfc4ef19d8724c8fcd0b0f4aa9b23f9c1a1d60f9d10a91fae"},{class="prop",key="PropExplosion",source="@addons/zcity/lua/homigrad/explosives/sv_explosives.lua",first=324,last=329,hash="b897fd4ff0594169cc9b02519201b70c571f1d584b6001170de18df90b205d30"}}, {["entities/ent_hg_grenade/init.lua"]="4c184f71c6facc41d79093f77d78ff35e1b6074c06096f5238fa220de0a33e40",["entities/ent_claymore/init.lua"]="fc626ebe9c1592541f99a4e4b85d3db5539a747c8b5b3585841608f3d57b58ea",["homigrad/explosives/sv_explosives.lua"]="591dd5b33b6df58f31ded0e0125e29d1ca5d841ea0e70ad35354dd274cd94b4c",["entities/projectile_base.lua"]="9d9cbed34900c381ebcde39d9afb838be66cf8cb79de12b7c33ee48da7464994"}
local function BuildCandidates(FragmentJobs)
local result={}
do
local ENT={}
local vecCone=Vector(0,0,0)
function ENT:Explode()
	if self:PoopBomb() or (!self.shouldBoom and !IsValid(self.owner)) then
		self:EmitSound("weapons/p99/slideback.wav", 75)
		self.Exploded = true
		return
	end
	hg.EmitAISound(self:GetPos(), 512, 16, 1)
	
	self.owner = self.owner or Entity(0)

	local selfPos = self:GetPos() + self:OBBCenter()

	self.Exploded = true

	local indoors = false
	

	local hits = 0
	local total = 4 
	
	local traceUp = util.TraceLine({
		start = selfPos,
		endpos = selfPos + Vector(0, 0, 1000),
		mask = MASK_SOLID,
		filter = self
	})
	
	if traceUp.Hit and not traceUp.HitSky then
		hits = hits + 1
	end
	

	for i = 1, 3 do
		local dir = VectorRand()
		dir.z = math.abs(dir.z) * 1.5 
		dir:Normalize()
		
		local traceAngled = util.TraceLine({
			start = selfPos,
			endpos = selfPos + dir * 700,
			mask = MASK_SOLID_BRUSHONLY,
			filter = self
		})
		
		if traceAngled.Hit and not traceAngled.HitSky then
			hits = hits + 1
		end
	end
	
	indoors = hits / total >= 0.5 

	if self:WaterLevel() == 0 then
		local line = util.TraceLine(
			{
				start = self:GetPos(),
				endpos = self:GetPos() - vector_up * 25,
				mask = MASK_SHOT,
				filter = self
			})
		--if line.Hit then
		--	ParticleEffect("pcf_jack_groundsplode_small3",selfPos,-vector_up:Angle())
		--else
			ParticleEffect("pcf_jack_airsplode_small3",selfPos,-vector_up:Angle())
		--end
	else
		local effectdata = EffectData()
		effectdata:SetOrigin(selfPos)
		effectdata:SetScale(self.BlastDis/2.5)
		effectdata:SetNormal(-self:GetAngles():Forward())
		util.Effect("eff_jack_genericboom", effectdata)
	end

	net.Start("projectileFarSound")
		net.WriteString(self.Sound[math.random(#self.Sound)])
		net.WriteString(self.SoundFar[math.random(#self.SoundFar)])
		net.WriteVector(self:GetPos())
		net.WriteEntity(self)
		net.WriteBool(self:WaterLevel() > 0)
		net.WriteString(self.SoundWater[math.random(#self.SoundWater)])
	net.Broadcast()

	if self:WaterLevel() > 0 then
		self:EmitSound(self.SoundWater, 140, 85, 1, CHAN_WEAPON)
		self:EmitSound(self.SoundBass[math.random(#self.SoundBass)], 150, 70, 0.8, CHAN_AUTO)
	else
		self:EmitSound(self.Sound[math.random(#self.Sound)], 145, 85, 1, CHAN_WEAPON)
		self:EmitSound(self.SoundFar[math.random(#self.SoundFar)], 140, 85, 0.9, CHAN_WEAPON)
		
		timer.Simple(0.05, function() 
			if IsValid(self) then
				self:EmitSound(self.SoundBass[math.random(#self.SoundBass)], 150, 70, 0.95, CHAN_AUTO) 
			end
		end)

		timer.Simple(0.1, function() 
			if IsValid(self) then
				self:EmitSound(self.SoundBass[math.random(#self.SoundBass)], 155, 60, 0.9, CHAN_BODY) 
			end
		end)
	end

	EmitSound(self.Sound[math.random(#self.Sound)], self:GetPos(), self:EntIndex() + 100, CHAN_STATIC, 1, 140, nil, math.random(75, 85))

	if self:WaterLevel() > 0 then
		self:EmitSound(self.SoundWater, 100, 100, 1, CHAN_WEAPON)
	else
		self:EmitSound(self.Sound[math.random(#self.Sound)], 100, 100, 1, CHAN_WEAPON)
		self:EmitSound(self.SoundFar[math.random(#self.SoundFar)], 95, 100, 0.8, CHAN_WEAPON)
	end


	if indoors and self.LegacyInDoorSound then

		if not util.TraceLine({start = self:GetPos(), endpos = self:GetPos() + Vector(0,0,500), filter = self,mask = MASK_SOLID_BRUSHONLY}).HitSky then
			for i = 1, 3 do
				local debris_sound = self.DebrisSounds[math.random(#self.DebrisSounds)]
				timer.Simple(i * 0.15, function()
					if IsValid(self) then
						self:EmitSound(debris_sound, 90, math.random(95, 105), 1, CHAN_AUTO)
					end
				end)
			end
		end
		
		EmitSound(self.DebrisSounds[math.random(#self.DebrisSounds)], self:GetPos(), self:EntIndex(), CHAN_AUTO, 1, 80)
	end

	util.BlastDamage(self, IsValid(self.owner) and self.owner or self, selfPos, self.BlastDis / 0.01905, 35)

	--;; Расскажу вам тайну но у нас трассировка делалась просто ужасно
	local dis = self.BlastDis / 0.01905
	local disorientation_dis = 6 / 0.01905  
	local entsCount = 0
	for i, enta in ipairs(ents.FindInSphere(selfPos, disorientation_dis)) do
		local tracePos = enta:IsPlayer() and (enta:GetPos() + enta:OBBCenter()) or enta:GetPos()
		local tr = hg.ExplosionTrace(selfPos, tracePos, {self})
		local phys = enta:GetPhysicsObject()
		if IsValid(phys) then
			entsCount = entsCount + 1
		end
		
		local phys = enta:GetPhysicsObject()
		local force = (enta:GetPos() - selfPos)
		local len = force:Length()
		force:Div(len)
		local frac = math.Clamp((disorientation_dis - len) / disorientation_dis, 0.1, 1)  
		local physics_frac = math.Clamp((dis - len) / dis, 0.5, 1)  
		local forceadd = force * physics_frac * 50000  

		if enta.organism then
			local behindwall = tr.Entity != enta and tr.MatType != MAT_GLASS
			if IsValid(enta.organism.owner) and enta.organism.owner:IsPlayer() and not behindwall then
				hg.ExplosionDisorientation(enta, 5 * frac, 6 * frac)
				hg.RunZManipAnim(enta.organism.owner, "shieldexplosion")
			end
		end

		if len > dis then continue end
		if tr.Entity != enta then continue end


		if enta:IsPlayer() then
			hg.AddForceRag(enta, 0, forceadd * 0.5, 0.5)
			hg.AddForceRag(enta, 1, forceadd * 0.5, 0.5)

			hg.LightStunPlayer(enta)
		end

		if not IsValid(phys) then continue end
		phys:ApplyForceCenter(forceadd)
	end

	if entsCount > 10 and not self.LegacyInDoorSound then
		for i = 1, 3 do
			local debris_sound = self.DebrisSounds[math.random(#self.DebrisSounds)]
			timer.Simple(i * 0.15, function()
				if IsValid(self) then
					self:EmitSound(debris_sound, 90, math.random(95, 105), 1, CHAN_AUTO)
				end
			end)
		end

		EmitSound(self.DebrisSounds[math.random(#self.DebrisSounds)], self:GetPos(), self:EntIndex(), CHAN_AUTO, 1, 80)
	end
	
	local Poof=EffectData()
	Poof:SetOrigin(selfPos)
	Poof:SetScale(1.2)
	util.Effect("eff_jack_hmcd_shrapnel",Poof,true,true)

	timer.Simple(0, function()
		if not IsValid(self) then return end
		util.ScreenShake( selfPos, 35, 200, 1, 1000 )

		local ammo = "Metal Debris"
		local ammotype = hg.ammotypeshuy[ammo].BulletSettings

		local co = coroutine.create(function()


			for i = 1, self.Fragmentation do
					if not IsValid(self) then return end
					-- Each resume handles one candidate; the shared scheduler owns the budget.

					local dir = VectorRand(-1,1):GetNormalized()--vector_up
					dir[3] = dir[3] > 0 and math.abs(dir[3] - 0.5) or -math.abs(dir[3] + 0.5)
					dir:Normalize()

					local Tr = util.QuickTrace(selfPos, dir * 10000, self)

					if Tr.Hit and !Tr.HitSky and !Tr.HitWorld then
						local bullet = {}

						bullet.Speed = ammotype.Speed
						bullet.Distance = ammotype.Distance or 56756
						bullet.penetrated = 0
						bullet.MaxPenLen = 100
						bullet.Penetration = (ammotype.Penetration or (-(-self.Penetration))) * (self.PenetrationMultiplier or 1)
						bullet.Diameter = ammotype.Diameter or 1

						bullet.Src = selfPos
						bullet.Spread = vecCone
						bullet.Force = 20
						bullet.Damage = 40
						bullet.AmmoType = ammo
						bullet.Attacker = self.owner
						bullet.Inflictor = self
						bullet.Distance = 56756
						bullet.DisableLagComp = true
						bullet.Filter = {self}
						bullet.Dir = dir
						bullet.Callback = hg.bulletHit

						self:FireLuaBullets(bullet, true)
					end

					coroutine.yield()
			end

			self.ShrapnelDone = true
		end)

		FragmentJobs.Add(self, co, function()
			SafeRemoveEntity(self)
		end)
		if self.ExplodeAdd then
			self:ExplodeAdd()
		end
	end)
	util.ScreenShake( selfPos, 35, 1, 1, 1000, true )
	hg.EmitAISound(self:GetPos(), 300, 3, bit.bor(1, 33554432)) -- надеюсь буде работать
end

result.ent_hg_grenade=ENT.Explode
end
do
local ENT={}

	function ENT:Detonate()
		if self.Exploded then return end
		if self.Removed then return end
		self.Exploded = true
		local SelfPos, Owner = self:LocalToWorld(self:OBBCenter()), self
		self:SetMoveType(MOVETYPE_NONE)

		--; говна поел
		local offset = VectorRand() * 10
		SelfPos = SelfPos + offset

		net.Start("projectileFarSound")
			net.WriteString(self.Sound)
			net.WriteString(self.SoundFar)
			net.WriteVector(SelfPos)
			net.WriteEntity(self)
			net.WriteBool(self:WaterLevel() > 0)
			net.WriteString(self.SoundWater)
		net.Broadcast()


		local dis = self.BlastDis / 0.01905
		local disorientation_dis = (self.BlastDis * 1.5) / 0.01905  

		for i, enta in ipairs(ents.FindInSphere(SelfPos, disorientation_dis)) do
			local tracePos = enta:IsPlayer() and (enta:GetPos() + enta:OBBCenter()) or enta:GetPos()
			local tr = hg.ExplosionTrace(SelfPos, tracePos, {self})
			local phys = enta:GetPhysicsObject()
			
			local phys = enta:GetPhysicsObject()
			local force = (enta:GetPos() - SelfPos)
			local len = force:Length()
			force:Div(len)
			local frac = math.Clamp((disorientation_dis - len) / disorientation_dis, 0.1, 1) 
			local physics_frac = math.Clamp((dis - len) / dis, 0.5, 1)  
			local forceadd = force * physics_frac * 50000  

			if enta.organism then
				local behindwall = tr.Entity != enta and tr.MatType != MAT_GLASS
				if IsValid(enta.organism.owner) and enta.organism.owner:IsPlayer() and not behindwall then
					hg.ExplosionDisorientation(enta, 5 * frac, 6 * frac)
					hg.RunZManipAnim(enta.organism.owner, "shieldexplosion")
				end
			end

			if len > dis then continue end
			if tr.Entity != enta then continue end
		end

		--[[local boom = DamageInfo()
		boom:SetDamage(self.BlastDamage)
		boom:SetDamageType(DMG_BLAST)
		boom:SetDamageForce(vector_up * 0)
		boom:SetInflictor(self)

		util.BlastDamageInfo( boom, SelfPos, self.BlastDis / 0.01905 )]]--
		util.BlastDamage(self, IsValid(self.owner) and self.owner or Owner, SelfPos, self.BlastDis / 0.01905, self.BlastDamage * 1)
		hgWreckBuildings(self, SelfPos, self.BlastDamage / 100, self.BlastDis/6, false)
		hgBlastDoors(self, SelfPos, self.BlastDamage / 100, self.BlastDis/6, false)
		
		hg.ExplosionEffect(SelfPos, self.BlastDis / 0.2, 80)

		timer.Simple(.01, function()
			if not IsValid(self) then return end
			for i = 0, 10 do
				local Tr = util.QuickTrace(SelfPos, -vector_up, {self})
				if Tr.Hit then
					util.Decal("Scorch", Tr.HitPos + Tr.HitNormal, Tr.HitPos - Tr.HitNormal)
				end
			end
			if self:WaterLevel() == 0 then
				ParticleEffect(self.ExplosionEffect,SelfPos+vector_up*1,-vector_up:Angle())
			else
				local effectdata = EffectData()
				effectdata:SetOrigin(SelfPos)
				effectdata:SetScale(self.BlastDis/2.5)
				effectdata:SetNormal(-self:GetAngles():Forward())
				util.Effect(self.WaterExplosionEffect, effectdata)
			end
		end)

		
		local co 

		if not IsValid(self) then return end
		if self.Oskole then 
			local Poof=EffectData()
			Poof:SetOrigin(SelfPos)
			Poof:SetScale(1.5)
			util.Effect(self.ShrapnelEffect,Poof,true,true)
			co = coroutine.create(function()

				local vecCone = Vector(5, 5, 0)
				local forward = self:GetAngles():Forward()
				local selfowner = self.owner
				local selfFragmentation = self.Fragmentation
				for i = 1, self.Fragmentation do
						if not IsValid(self) then return end


						local dir = VectorRand(-1,1):GetNormalized()--vector_up
						dir[3] = dir[3] > 0 and math.abs(dir[3] - 0.5) or -math.abs(dir[3] + 0.5)
						dir:Normalize()

						local Tr = util.QuickTrace(SelfPos, dir * 10000, self)
						if Tr.Hit and !Tr.HitSky and !Tr.HitWorld then
							local bullet = {}
							bullet.Src = SelfPos
							bullet.Spread = vecCone
							bullet.Force = 20
							bullet.Damage = 40
							bullet.AmmoType = "Metal Debris"
							bullet.Attacker = self.owner
							bullet.Inflictor = self
							bullet.Distance = 16756
							bullet.DisableLagComp = true
							bullet.Filter = {self}
							bullet.Dir = dir
							--bullet.Spread = vecCone * i / self.Fragmentation
							self:FireLuaBullets(bullet, true)
						end

						coroutine.yield()
				end
				self.ShrapnelDone = true
			end)
		end

        util.ScreenShake(SelfPos,100,200,1,3000)

		if co then
			FragmentJobs.Add(self, co, function()
				self:StopSound("weapons/ins2rpg7/rpg_rocket_loop.wav")
				SafeRemoveEntity(self)
			end)
		else
			-- Allow the existing .01-second effect callback to run first.
			timer.Simple(0.05, function()
				if not IsValid(self) then return end
				self:StopSound("weapons/ins2rpg7/rpg_rocket_loop.wav")
				SafeRemoveEntity(self)
			end)
		end
	end
result.projectile_base=ENT.Detonate
end
do
local ENT={}

function ENT:ActivateExplosive()
	if self.Exploded then return end
	self.Exploded = true
	local selfPos = self:GetPos()
	local pos, ang = LocalToWorld(self.offsetPos, self.offsetAng, self:GetPos(), self:GetAngles())
	local num = 700

	local bullet = {}
	bullet.Force = 2
	bullet.Damage = 10
	bullet.AmmoType = "Metal Debris"
	bullet.Attacker = self.owner
	bullet.Distance = 56756
	bullet.Callback = hg.bulletHit
	bullet.IgnoreEntity = self
	bullet.Tracer = 10000
	bullet.DisableLagComp = true
	bullet.Filter = {self}

	local co = coroutine.create(function()


		for i = 1, num do
			if not IsValid(self) then return end


			local dir = (ang + Angle(math.Rand(-12, 2), math.Rand(-30, 30), 0)):Forward()
			dir:Normalize()

			local tr = util.TraceLine({
				start = pos,
				endpos = pos + dir * bullet.Distance,
				filter = bullet.Filter,
				mask = MASK_SHOT
			})
			if i > 100 and tr.Entity == game.GetWorld() then
				util.Decal("ExplosiveGunshot",tr.HitPos+tr.HitNormal,tr.HitPos-tr.HitNormal)
			else

			bullet.Src = pos
			bullet.Dir = dir
			bullet.Penetration = math.Clamp(num / i, 5, 10) * 10
			if not IsValid(self) then return end
			self:FireLuaBullets(bullet,true)
			end

			coroutine.yield()
		end

		self.ShrapnelDone = true
	end)

	FragmentJobs.Add(self, co, function()
		util.ScreenShake(selfPos, 20, 20, 1, self.ConcussionDis)
		SafeRemoveEntity(self)
	end)

	net.Start("projectileFarSound")
		net.WriteString(table.Random(self.Sound))
		net.WriteString(table.Random(self.SoundFar))
		net.WriteVector(selfPos)
		net.WriteEntity(self)
		net.WriteBool(self:WaterLevel() > 0)
		net.WriteString(self.SoundWater)
	net.Broadcast()
	local normal = self:GetAngles():Right()
	local blastdist = self.BlastDis
	timer.Simple(0.3,function()
		ParticleEffect("pcf_jack_groundsplode_medium",selfPos+vector_up*1,-normal:Angle())
		--hg.ExplosionEffect(selfPos, blastdist, 80)
	end)

	local attacker = IsValid(self.owner) and self.owner or Entity(0)
	
	for _, ply in ipairs(ents.FindInSphere(selfPos,self.ConcussionDis)) do
		if not ply:IsPlayer() then continue end
		local tr = hg.ExplosionTrace(selfPos,ply:GetPos(),{self})
		if tr.Entity != ply then continue end
		local dist = ply:GetPos():Distance(selfPos)
		local tinnitusDuration = math.Clamp(10 * (1 - dist/self.ConcussionDis), 2, 10)
		ply:AddTinnitus(math.max(tinnitusDuration,1.5), true)
	end
	   
	--util.BlastDamage(self, attacker, selfPos, self.ShrapnelDis, self.BlastDamage)
	util.BlastDamage(self, attacker, selfPos, self.BlastDis, self.ShrapnelDamage)
	--util.BlastDamage(self, attacker, selfPos, self.ConcussionDis, self.ConcussionDamage)
end

result.ent_claymore=ENT.ActivateExplosive
end
do
local DebrisSounds = {
    "explosion_debris/interior/explosion_debris_sprinkle_interior_wave01.wav",
    "explosion_debris/interior/explosion_debris_sprinkle_interior_wave010.wav",
    "explosion_debris/interior/explosion_debris_sprinkle_interior_wave02.wav",
    "explosion_debris/interior/explosion_debris_sprinkle_interior_wave03.wav",
    "explosion_debris/interior/explosion_debris_sprinkle_interior_wave04.wav",
    "explosion_debris/interior/explosion_debris_sprinkle_interior_wave05.wav",
    "explosion_debris/interior/explosion_debris_sprinkle_interior_wave06.wav",
    "explosion_debris/interior/explosion_debris_sprinkle_interior_wave07.wav",
    "explosion_debris/interior/explosion_debris_sprinkle_interior_wave09.wav"
}

local hg, util, ParticleEffect, IsValid, timer, coroutine, Vector = hg, util, ParticleEffect, IsValid, timer, coroutine, Vector

local vecCone = Vector(5, 5, 0)
local ExpTypes = {
    Fire = function(Ent, Force, Mass)
		local multi = math.min(Mass / 10,20)
		Force = Force * multi
        local SelfPos, Owner = Ent:LocalToWorld(Ent:OBBCenter()), (Ent.owner or Ent)
		local rad = (Force / 8)
        util.BlastDamage(Ent, Owner, SelfPos, rad / 0.01905, Force * 2)
		--hgWreckBuildings(Ent, SelfPos, Force / 50)
		hgBlastDoors(Ent, SelfPos, Force / 50, Force / 15)
		--ParticleEffect("pcf_jack_incendiary_ground_sm2",SelfPos + vector_up * 1,vector_up:Angle())
		hg.ExplosionEffect(SelfPos, Force / 0.2, 80)

        net.Start("hg_booom")
            net.WriteVector(SelfPos)
            net.WriteString("Fire")
        net.Broadcast()

		if not IsValid(Ent) then return end
		local multi = math.min(Mass / 5, 20)
		
		local Tr = util.QuickTrace(SelfPos, -vector_up*500, {Ent})
		local fire = CreateVFire(game.GetWorld(), Tr.HitPos, Tr.HitNormal, 150 / 7 * multi, Ent)
		if IsValid(fire) then
			fire:ChangeLife(150)
		end
		for i = 1, multi / 2 do
			local randvec = VectorRand(-1000,1000)--VectorRand(-1,1) * math.random(1000)
			randvec[3] = math.random(100,1000)
			CreateVFireBall(20, 50, SelfPos + vector_up * 10, randvec)
		end

		local dis = rad / 0.01900
		local entsCount = 0
		for i, enta in ipairs(ents.FindInSphere(SelfPos, dis)) do
			local tracePos = enta:IsPlayer() and (enta:GetPos() + enta:OBBCenter()) or enta:GetPos()
			local tr = hg.ExplosionTrace(SelfPos, tracePos, {Ent})
			local phys = enta:GetPhysicsObject()
			if IsValid(phys) then
				entsCount = entsCount + 1
			end
			
			local phys = enta:GetPhysicsObject()
			local force = (enta:GetPos() - SelfPos)
			local len = force:Length()
			force:Div(len)
			local frac = math.Clamp((dis - len) / dis, 0.5, 1)
			local forceadd = force * frac * 50000

			if enta.organism then
				local behindwall = tr.Entity != enta and tr.MatType != MAT_GLASS
				if IsValid(enta.organism.owner) and enta.organism.owner:IsPlayer() then
					hg.ExplosionDisorientation(enta, 5 * frac / (behindwall and 3 or 1), 6 * frac / (behindwall and 3 or 1))
					hg.RunZManipAnim(enta.organism.owner, "shieldexplosion")
				end
			end

			if tr.Entity != enta then forceadd = forceadd / 5 continue end

			if enta:IsPlayer() then
				hg.AddForceRag(enta, 0, forceadd * 0.5, 0.5)
				hg.AddForceRag(enta, 1, forceadd * 0.5, 0.5)

				timer.Simple(0, function() hg.LightStunPlayer(enta) end)
			end

			if not IsValid(phys) then continue end
			phys:ApplyForceCenter(forceadd)
		end

		if entsCount > 10 then
			EmitSound(DebrisSounds[math.random(#DebrisSounds)], Ent:GetPos(), Ent:EntIndex(), CHAN_AUTO, 1, 80)
			EmitSound(DebrisSounds[math.random(#DebrisSounds)], Ent:GetPos(), Ent:EntIndex(), CHAN_AUTO, 1, 80)
			EmitSound(DebrisSounds[math.random(#DebrisSounds)], Ent:GetPos(), Ent:EntIndex(), CHAN_AUTO, 1, 80)
		end

		local bullet = {}
		bullet.Src = SelfPos
		bullet.Spread = vecCone
		bullet.Force = 0.01
		bullet.Damage = Force
		bullet.AmmoType = "Metal Debris"
		bullet.Attacker = Owner
		bullet.Distance = 15000
		bullet.DisableLagComp = true
		bullet.Filter = {Ent}
		table.Add(bullet.Filter, hg.drums2)
		local multi = math.min(Mass/5,20)

		local co = coroutine.create(function()

			for i = 1, multi*3 do

				if not IsValid(Ent) then return end
				bullet.Dir = Ent:GetAngles():Forward() * math.random(-1,1)
				bullet.Spread = vecCone * (i / Mass/5)
				Ent:FireLuaBullets(bullet, true)
				coroutine.yield()
			end
			Ent.ShrapnelDone = true
		end)

        util.ScreenShake(SelfPos,100,900,1,5000)

		FragmentJobs.Add(Ent, co, function()
			SafeRemoveEntity(Ent)
		end)
    end,

    Sharpnel = function(Ent,Force,Mass)
		local rad = (Force / 8)
        local SelfPos, Owner = Ent:LocalToWorld(Ent:OBBCenter()), (Ent.owner or Ent)
        util.BlastDamage(Ent, Owner, SelfPos, (Force/7.5) / 0.01905, Force * 1)
		--hgWreckBuildings(Ent, SelfPos, Force / 50)
		hgBlastDoors(Ent, SelfPos, Force / 50)

        --ParticleEffect("pcf_jack_groundsplode_medium",SelfPos + vector_up * 1,vector_up:Angle())
		hg.ExplosionEffect(SelfPos, Force / 0.2, 80)

        net.Start("hg_booom")
            net.WriteVector(SelfPos)
            net.WriteString("Sharpnel")
        net.Broadcast()

		local dis = rad / 0.01900
		local entsCount = 0
		for i, enta in ipairs(ents.FindInSphere(SelfPos, dis)) do
			local tracePos = enta:IsPlayer() and (enta:GetPos() + enta:OBBCenter()) or enta:GetPos()
			local tr = hg.ExplosionTrace(SelfPos, tracePos, {Ent})
			local phys = enta:GetPhysicsObject()
			if IsValid(phys) then
				entsCount = entsCount + 1
			end
			
			local phys = enta:GetPhysicsObject()
			local force = (enta:GetPos() - SelfPos)
			local len = force:Length()
			force:Div(len)
			local frac = math.Clamp((dis - len) / dis, 0.5, 1)
			local forceadd = force * frac * 50000

			if enta.organism then
				local behindwall = tr.Entity != enta and tr.MatType != MAT_GLASS
				if IsValid(enta.organism.owner) and enta.organism.owner:IsPlayer() and not behindwall then
					hg.ExplosionDisorientation(enta, 5 * frac, 6 * frac)
					hg.RunZManipAnim(enta.organism.owner, "shieldexplosion")
				end
			end

			if tr.Entity != enta then forceadd = forceadd / 5 continue end


			if enta:IsPlayer() then
				hg.AddForceRag(enta, 0, forceadd * 0.5, 0.5)
				hg.AddForceRag(enta, 1, forceadd * 0.5, 0.5)

				timer.Simple(0, function() hg.LightStunPlayer(enta) end)
			end

			if not IsValid(phys) then continue end
			phys:ApplyForceCenter(forceadd)
		end

		if entsCount > 10 then
			EmitSound(DebrisSounds[math.random(#DebrisSounds)], Ent:GetPos(), Ent:EntIndex(), CHAN_AUTO, 1, 80)
			EmitSound(DebrisSounds[math.random(#DebrisSounds)], Ent:GetPos(), Ent:EntIndex(), CHAN_AUTO, 1, 80)
			EmitSound(DebrisSounds[math.random(#DebrisSounds)], Ent:GetPos(), Ent:EntIndex(), CHAN_AUTO, 1, 80)
		end

		local bullet = {}
		bullet.Src = SelfPos
		bullet.Spread = vecCone
		bullet.Force = 0.01
		bullet.Damage = Force
		bullet.AmmoType = "Metal Debris"
		bullet.Attacker = Owner
		bullet.Distance = 15000
		bullet.DisableLagComp = true
		bullet.Filter = {Ent}
		table.Add(bullet.Filter, hg.drums2)
		local multi = math.min(Mass/5,20)

		local co = coroutine.create(function()

			for i = 1, multi*5 do

				if not IsValid(Ent) then return end
				bullet.Dir = Ent:GetAngles():Forward() * math.random(-1,1)
				bullet.Spread = vecCone * (i / Mass/5)
				Ent:FireLuaBullets(bullet, true)
				coroutine.yield()
			end
			Ent.ShrapnelDone = true
		end)

         util.ScreenShake(SelfPos,100,900,1,5000)

		FragmentJobs.Add(Ent, co, function()
			SafeRemoveEntity(Ent)
		end)
    end,
    Normal = function(Ent,Force)
		local rad = (Force / 8)
        local SelfPos, Owner = Ent:LocalToWorld(Ent:OBBCenter()), (Ent.owner or Ent)
        util.BlastDamage(Ent, Owner, SelfPos, (Force / 7.5) / 0.01905, Force * 1)
		--hgWreckBuildings(Ent, SelfPos, Force / 50)
		hgBlastDoors(Ent, SelfPos, Force / 50)

        --ParticleEffect("pcf_jack_groundsplode_small",SelfPos + vector_up * 1,vector_up:Angle())
		hg.ExplosionEffect(SelfPos, Force / 0.2, 80)

        net.Start("hg_booom")
            net.WriteVector(SelfPos)
            net.WriteString("Normal")
        net.Broadcast()

		local dis = rad / 0.01900
		local entsCount = 0
		for i, enta in ipairs(ents.FindInSphere(SelfPos, dis)) do
			local tracePos = enta:IsPlayer() and (enta:GetPos() + enta:OBBCenter()) or enta:GetPos()
			local tr = hg.ExplosionTrace(SelfPos, tracePos, {Ent})
			local phys = enta:GetPhysicsObject()
			if IsValid(phys) then
				entsCount = entsCount + 1
			end
			
			local phys = enta:GetPhysicsObject()
			local force = (enta:GetPos() - SelfPos)
			local len = force:Length()
			force:Div(len)
			local frac = math.Clamp((dis - len) / dis, 0.5, 1)
			local forceadd = force * frac * 50000

			if enta.organism then
				local behindwall = tr.Entity != enta and tr.MatType != MAT_GLASS
				if IsValid(enta.organism.owner) and enta.organism.owner:IsPlayer() and not behindwall then
					hg.ExplosionDisorientation(enta, 5 * frac, 6 * frac)
					hg.RunZManipAnim(enta.organism.owner, "shieldexplosion")
				end
			end

			if tr.Entity != enta then forceadd = forceadd / 5 continue end


			if enta:IsPlayer() then
				hg.AddForceRag(enta, 0, forceadd * 0.5, 0.5)
				hg.AddForceRag(enta, 1, forceadd * 0.5, 0.5)

				timer.Simple(0, function() hg.LightStunPlayer(enta) end)
			end

			if not IsValid(phys) then continue end
			phys:ApplyForceCenter(forceadd)
		end

		if entsCount > 10 then
			EmitSound(DebrisSounds[math.random(#DebrisSounds)], Ent:GetPos(), Ent:EntIndex(), CHAN_AUTO, 1, 80)
			EmitSound(DebrisSounds[math.random(#DebrisSounds)], Ent:GetPos(), Ent:EntIndex(), CHAN_AUTO, 1, 80)
			EmitSound(DebrisSounds[math.random(#DebrisSounds)], Ent:GetPos(), Ent:EntIndex(), CHAN_AUTO, 1, 80)
		end

		if not IsValid(Ent) then return end
		 util.ScreenShake(SelfPos,100,900,1,2000)
		SafeRemoveEntity(Ent)
    end,
}

local function PropExplosion(Ent, ExpType, Force, Mass)
	if Ent.HasExploded then return end
	Ent.HasExploded = true
	
    ExpTypes[ExpType](Ent,Force, Mass)
end

result.prop=PropExplosion
end
return result
end
local state={version='20260920.1',active=false,reason='not installed',slots={}}
_G[ID]=state
local hookNames={'Tick','EntityRemoved','PreCleanupMap','ShutDown'}
local function root(spec)
    if spec.class=='prop' then return hg end
    local stored=scripted_ents.GetStored(spec.class)
    return stored and stored.t
end
local function matches(fn,spec)
    if not isfunction(fn) then return false end
    local info=debug.getinfo(fn,'S')
    return info and info.source==spec.source and info.linedefined==spec.first
        and info.lastlinedefined==spec.last and util.SHA256(string.dump(fn,true))==spec.hash
end
function state.IsActive()
    if not state.active then return false end
    for _,s in ipairs(specs)do local t=root(s);if not t or t[s.key]~=state.candidates[s.class]then return false end end
    return _G[SCHEDULER]==state.scheduler and (hook.GetTable().Tick or {})[SCHEDULER]==state.scheduler.Step
end
function state.Install()
    if state.IsActive()then return true end
    if state.active then state.reason='owner changed; refusing to overwrite';return false end
    for path,expected in pairs(sources)do
        local source=file.Read(path,'LUA')
        if not source or util.SHA256(source)~=expected then state.reason='source mismatch: '..path;return false end
    end
    local originals={}
    for _,s in ipairs(specs)do
        local t=root(s)
        if not t or not matches(t[s.key],s)then state.reason='waiting for reviewed owner: '..s.class;return false end
        originals[s.class]=t[s.key]
    end
    local currentEntities=ents.GetAll()
    for _,ent in ipairs(currentEntities)do
        if IsValid(ent)then
            local name='GrenadeCheck_'..ent:EntIndex()
            if timer.Exists(name)or timer.Exists(name..'_'..ent:GetCreationID())then
                state.reason='waiting for legacy fragmentation';return false
            end
        end
    end
    if _G[SCHEDULER]then state.reason='scheduler already exists';return false end
    for _,event in ipairs(hookNames)do
        if (hook.GetTable()[event] or {})[SCHEDULER]then state.reason='scheduler hook already exists';return false end
    end
    local slots,seen={},{}
    local function collect(t)
        if not istable(t)or seen[t]then return end
        seen[t]=true
        for _,s in ipairs(specs)do
            if rawget(t,s.key)==originals[s.class]then slots[#slots+1]={target=t,key=s.key,old=rawget(t,s.key),class=s.class}end
        end
        collect(rawget(t,'BaseClass'))
    end
    collect(hg)
    for class in pairs(scripted_ents.GetList())do
        local stored=scripted_ents.GetStored(class)
        if stored then collect(stored.t)end
        collect(baseclass.Get(class))
    end
    -- Existing entities may contain inherited copies rather than class-table lookups.
    for _,ent in ipairs(currentEntities)do
        if IsValid(ent)then
            local t=ent:GetTable()
            for _,s in ipairs(specs)do
                if ent[s.key]==originals[s.class] and not (seen[t] and rawget(t,s.key)==originals[s.class])then
                    slots[#slots+1]={target=t,entity=ent,key=s.key,old=rawget(t,s.key),class=s.class}
                end
            end
            seen[t]=true
        end
    end
    local scheduler=include('zc_explosion/fragment_scheduler.lua')
    local candidates=BuildCandidates(scheduler)
    state.scheduler,state.candidates,state.originals,state.slots=scheduler,candidates,originals,slots
    state.schedulerHooks={}
    for _,event in ipairs(hookNames)do state.schedulerHooks[event]=hook.GetTable()[event][SCHEDULER]end
    for _,slot in ipairs(slots)do slot.target[slot.key]=candidates[slot.class]end
    state.active,state.reason=true,'active'
    timer.Remove(ID)
    print('[ZCity explosion fragments] approved trial active; '..#slots..' method slots')
    return true
end
function state.Rollback()
    if not state.active then return true,0 end
    if state.scheduler.stats.pending>0 then return false,'waiting for queued fragments to finish' end
    local drift=0
    for _,slot in ipairs(state.slots)do
        if not slot.entity or IsValid(slot.entity)then
            if slot.target[slot.key]==state.candidates[slot.class]then slot.target[slot.key]=slot.old else drift=drift+1 end
        end
    end
    -- New entities/classes can copy candidate methods after activation.
    -- Restore only exact owned copies; preserve any later foreign override.
    local seen={}
    local function restoreNew(t)
        if not istable(t)or seen[t]then return end
        seen[t]=true
        for _,spec in ipairs(specs)do
            if rawget(t,spec.key)==state.candidates[spec.class]then t[spec.key]=state.originals[spec.class]end
        end
        restoreNew(rawget(t,'BaseClass'))
    end
    for class in pairs(scripted_ents.GetList())do
        local stored=scripted_ents.GetStored(class)
        if stored then restoreNew(stored.t)end
        restoreNew(baseclass.Get(class))
    end
    for _,ent in ipairs(ents.GetAll())do if IsValid(ent)then restoreNew(ent:GetTable())end end
    state.scheduler.Clear()
    for _,event in ipairs(hookNames)do
        if (hook.GetTable()[event] or {})[SCHEDULER]==state.schedulerHooks[event]then hook.Remove(event,SCHEDULER)else drift=drift+1 end
    end
    if _G[SCHEDULER]==state.scheduler then _G[SCHEDULER]=nil else drift=drift+1 end
    timer.Remove(ID)
    for _,event in ipairs({'OnGamemodeLoaded','InitPostEntity'})do
        if (hook.GetTable()[event] or {})[ID]==state.Attempt then hook.Remove(event,ID)end
    end
    state.active,state.reason=false,'rolled back'
    return true,drift
end
state.Attempt=function()state.Install()end -- Never return a value into hook dispatch.
hook.Add('OnGamemodeLoaded',ID,state.Attempt)
hook.Add('InitPostEntity',ID,state.Attempt)
timer.Create(ID,1,30,state.Attempt)
state.Attempt()
return state
