AddCSLuaFile()
local math_random, math_Rand = math.random, math.Rand -- 2026-09-24: FireBullet used these as undefined globals; nil on the client since 20260918.1
if SERVER then ZCBulletPhase1Version="20260918.1" end
--
local surface_hardness = {
	[MAT_METAL] = 1,
	[MAT_COMPUTER] = 0.9,
	[MAT_VENT] = 0.9,
	[MAT_GRATE] = 0.9,
	[MAT_FLESH] = 0.5,
	[MAT_ALIENFLESH] = 0.3,
	[MAT_SAND] = 0.1,
	[MAT_DIRT] = 0.9,
	[74] = 0.1,
	[85] = 0.2,
	[MAT_WOOD] = 0.5,
	[MAT_FOLIAGE] = 0.5,
	[MAT_CONCRETE] = 0.9,
	[MAT_TILE] = 0.8,
	[MAT_SLOSH] = 0.05,
	[MAT_PLASTIC] = 0.3,
	[MAT_GLASS] = 0.6,
}

local effect = {
	[MAT_METAL] = {"metal",1},
	[MAT_COMPUTER] = {"metal",1},
	[MAT_VENT] = {"metal",1},
	[MAT_FLESH] = {"flesh",0.75},
	[MAT_ALIENFLESH] = {"alienflesh",1},
	[MAT_SAND] = {"sand",1},
	[MAT_DIRT] = {"dirt",1},
	[MAT_WOOD] = {"wood",1},
	[MAT_FOLIAGE] = {"grass",1},
	[MAT_CONCRETE] = {"concrete",1},
	[MAT_TILE] = {"concrete",1},
	[MAT_SLOSH] = {"concrete",1},
	[MAT_PLASTIC] = {"concrete",1},
	[MAT_GLASS] = {"glass",1},
}

if SERVER then
	hg.bulletholes = hg.bulletholes or {}

	hook.Add("PostCleanupMap", "cleanupholes", function()
		hg.bulletholes = {}

		SetNetVar("BulletHoles", hg.bulletholes)
	end)
end

local bulletHit
local util, math, IsValid, WorldToLocal, Vector, sound, EffectData, game = util, math, IsValid, WorldToLocal, Vector, sound, EffectData, game
local hg_bulletholes = GetConVar("hg_bulletholes") or CreateConVar("hg_bulletholes", "0",
	FCVAR_ARCHIVE + FCVAR_NOTIFY + FCVAR_REPLICATED, "Enable R6S bulletholes feature", 0, 1)

local function BulletHolesEnabled()
	return hg_bulletholes and hg_bulletholes:GetBool() or false
end

-- Ballistic presentation is delayed in a few places to separate the entry and
-- exit effects. A shared scheduler avoids allocating a timer closure for every
-- pellet while retaining the authored 0/0.1/0.15 second delays.
local ballisticEffects, ballisticEffectPool = {}, {}
local function copyVector(v)
	return Vector(v.x, v.y, v.z)
end

local function queueBallisticEffect(kind, delay, origin, start, normal, magnitude, weapon, material)
	local job = ballisticEffectPool[#ballisticEffectPool]
	if job then
		ballisticEffectPool[#ballisticEffectPool] = nil
	else
		job = {}
	end

	job.kind = kind
	job.due = CurTime() + delay
	job.minTick = engine.TickCount() + 1
	job.origin = origin and copyVector(origin)
	job.start = start and copyVector(start)
	job.normal = normal and copyVector(normal)
	job.magnitude = magnitude
	job.weapon = weapon
	job.material = material
	ballisticEffects[#ballisticEffects + 1] = job
end

local function recycleBallisticEffect(job)
	job.kind, job.due, job.minTick = nil, nil, nil
	job.origin, job.start, job.normal = nil, nil, nil
	job.magnitude, job.weapon, job.material = nil, nil, nil
	ballisticEffectPool[#ballisticEffectPool + 1] = job
end

local function openDoorAreaPortal(ent)
	if not hgIsDoor(ent) then return end
	for _, portal in ipairs(ents.FindByClass("func_areaportal")) do
		if portal:GetInternalVariable("target") == ent:GetName() then
			portal:SetKeyValue("target", "")
			portal:Fire("Open")
			return
		end
	end
end

local function callbackBullet(self, tr, dmg, force, bullet, penetration)
	if CLIENT then return end
	if not IsValid(self) then return end
	if not bullet then return end
	bullet.limit_ricochet = bullet.limit_ricochet or 0
	bullet.penetrated = bullet.penetrated or 0
	if bullet.penetrated > 6 then return end
	if bullet.limit_ricochet > 6 then return end
	if tr.Entity.organism then return end
	local dir, hitNormal, hitPos = tr.Normal, tr.HitNormal, tr.HitPos
	local hardness = surface_hardness[tr.MatType] or 0.5
	local ApproachAngle = -math.deg(math.asin(math.Clamp(hitNormal:Dot(dir), -1, 1)))
	local MaxRicAngle = 60 * hardness * (bullet.noricochet and 0 or 1)
	-- all the way through
	--print(ApproachAngle > MaxRicAngle * 0.7  )
	if ApproachAngle > MaxRicAngle * 1 or tr.Entity:IsVehicle() then
		local Pen = (bullet.Penetration or 5) * 3
		local MaxDist, SearchPos, SearchDist, Penetrated = math.min(Pen / hardness * 0.4, 100), hitPos, 5, false
		local hit
		local penetrationTraceOutput = {}
		local penetrationTraceInput = {
			mask = MASK_SOLID,
			output = penetrationTraceOutput
		}
		while SearchDist < MaxDist do
			SearchPos = hitPos + dir * SearchDist
			penetrationTraceInput.start = SearchPos
			penetrationTraceInput.endpos = SearchPos - dir * SearchDist
			util.TraceLine(penetrationTraceInput)
			local PeneTrace = penetrationTraceOutput
			if not PeneTrace.StartSolid then
				Penetrated = true
				hit = PeneTrace
				bullet.Penetration = bullet.Penetration - Pen * SearchDist / MaxDist / 3
				break
			else
				SearchDist = SearchDist + 5
			end
		end

		if tr.Entity:IsVehicle() then Penetrated = penetration end
		if Penetrated then
			util.Decal("Impact.Concrete", SearchPos + dir * 5, SearchPos - dir * 15)
			local materialEffect = effect[tr.MatType]
			if materialEffect then queueBallisticEffect("material", 0.15, nil, hitPos + dir * 15, dir, materialEffect[2], nil, materialEffect[1]) end

			local filter = {}
			if tr.Entity:IsVehicle() then
				filter = {tr.Entity}
				if tr.Entity.seats then
					for i, seat in pairs(tr.Entity.seats) do
						table.insert(filter, seat)
					end
				end
			end

			local tBullet = {
				Attacker = IsValid(self) and IsValid(self:GetOwner()) and self:GetOwner() or self,
				Damage = dmg * 0.65,
				Force = force / 3,
				Num = 1,
				Tracer = 0,
				TracerName = "nil",
				Dir = dir,
				Spread = vector_origin,
				Src = tr.Entity:IsVehicle() and hitPos or (SearchPos + dir),
				Callback = bulletHit,
				DisableLagComp = true,
				Filter = filter,
				Penetration = bullet.Penetration,
				Diameter = bullet.Diameter,
				penetrated = bullet.penetrated + 1,
				dmgtype = bullet.dmgtype or DMG_BULLET,
				NpcShoot = bullet.NpcShoot,
				limit_ricochet = bullet.limit_ricochet + 1,
				noricochet = bullet.noricochet,
				AmmoType = bullet.AmmoType
			}

			self.bullet = tBullet
			self:FireLuaBullets(tBullet)
			if BulletHolesEnabled() then
				local ent = IsValid(tr.Entity) and tr.Entity or Entity(0)
				local hitPos2, dir2 = WorldToLocal(hitPos, dir:Angle(), ent:GetPos(), ent:GetAngles())
				local _, hitNormal2 = WorldToLocal(hitPos, hitNormal:Angle(), ent:GetPos(), ent:GetAngles())
				local size = (bullet.Diameter or 9) / 25.4 * math.Rand(2, 4) * math.Rand(1, self.NumBullet or 1)
				local dontadd = false
				for i = 1, #hg.bulletholes do
					if hitPos2:IsEqualTol(hg.bulletholes[i][1], size * 1.414) then --sqrt of 2, cuz it's a square
						dontadd = true
						break
					end
				end

				if not dontadd and hit then
					local dist = hitPos:Distance(hit.HitPos)
					table.insert(hg.bulletholes, {hitPos2, dir2, dist, hitNormal2, size, ent})
					local exitPos, exitDir = WorldToLocal(hit.HitPos, (-dir):Angle(), ent:GetPos(), ent:GetAngles())
					local _, exitNormal = WorldToLocal(hit.HitPos, hit.HitNormal:Angle(), ent:GetPos(), ent:GetAngles())
					table.insert(hg.bulletholes, {exitPos, exitDir, dist, exitNormal, size, ent})
					openDoorAreaPortal(ent)

					if #hg.bulletholes > 160 then
						table.remove(hg.bulletholes, 1)
						table.remove(hg.bulletholes, 1)
					end
				end

				SetNetVar("BulletHoles", hg.bulletholes, nil, true)
			end

			local tracerTrace = util.TraceLine({
				start = SearchPos + dir,
				endpos = SearchPos + dir * 10000,
				mask = MASK_SHOT
			})

			queueBallisticEffect("tracer", 0.1, tracerTrace.HitPos, hitPos + hitNormal, nil, 2, self)
		end
	elseif ApproachAngle < MaxRicAngle * 0.7 then
		--previosly 0.2, made 1 for fun
		--if CLIENT then return end
		-- ping whiiiizzzz
		local rnd = math.random(12)
		if rnd == 8 then rnd = 9 end
		sound.Play("arc9_eft_shared/ricochet/ricochet" .. rnd .. ".ogg", hitPos, 75, math.random(90, 110))
		--sound.Play("snd_jack_hmcd_ricochet_" .. math.random(1, 2) .. ".wav", hitPos, 75, math.random(90, 110))
		--sound.Play("weapons/arccw/ricochet0" .. math.random(1, 5) .. "_quiet.wav", hitPos, 75, math.random(90, 110))
		util.Decal("ManhackCut", tr.HitPos + tr.HitNormal, tr.HitPos - tr.HitNormal)
		local NewVec = dir:Angle()
		NewVec:RotateAroundAxis(hitNormal, 180)
		NewVec = NewVec:Forward()
		local tBullet = {
			Attacker = IsValid(self) and IsValid(self:GetOwner()) and self:GetOwner() or self,
			Damage = (dmg or 1) * .85,
			Force = force / 3,
			Num = 1,
			Tracer = 0,
			TracerName = "nil",
			Dir = -NewVec,
			Spread = vector_origin,
			Src = hitPos + hitNormal,
			Callback = bulletHit,
			DisableLagComp = true,
			Filter = {},
			Penetration = bullet.Penetration,
			Diameter = bullet.Diameter,
			penetrated = bullet.penetrated + 1,
			dmgtype = bullet.dmgtype or DMG_BULLET,
			limit_ricochet = bullet.limit_ricochet + 1,
			noricochet = bullet.noricochet,
			AmmoType = bullet.AmmoType
		}

		self.bullet = tBullet
		self:FireLuaBullets(tBullet)
		local tracerTrace = util.TraceLine({
			start = hitPos + hitNormal,
			endpos = hitPos + hitNormal + -NewVec * 10000,
			mask = MASK_SHOT
		})

		queueBallisticEffect("tracer", 0, tracerTrace.HitPos, hitPos + hitNormal, nil, 2, self)
	elseif math.random(2) == 1 then
		if CLIENT then return end
		local effectdata1 = EffectData()
		effectdata1:SetOrigin(hitPos)
		effectdata1:SetNormal(tr.Normal)
		effectdata1:SetStart(tr.HitNormal)
		effectdata1:SetEntity(self)
		effectdata1:SetFlags(2)
		effectdata1:SetMagnitude(4)
		util.Effect("eff_bulletdrop", effectdata1)
	end
end

function SWEP:CallbackBullet(self, tr)
	return callbackBullet(self, tr)
end

local shootDecalCount = 5
for i = 1, shootDecalCount do
	game.AddDecal("Impact.ShootAdd" .. i, "decals/zcity/powder_impact_" .. i)
end

game.AddDecal("Impact.ShootPowderAdd", "decals/burn01a")
local allowedMats = {
	[MAT_CONCRETE] = true,
	[MAT_METAL] = true
}

-- Double-buffered impact queue: callbacks produced while a batch drains are
-- retained for the next Think. Entry tables are pooled and scrubbed so bursts
-- do not produce a second wave of garbage or retain entities afterward.
local hitQueueWrite, hitQueueDrain, hitEntryPool = {}, {}, {}
bulletHit = function(ply, tr, dmgInfo, bullet, Weapon)
	if CLIENT then return end
	local inflictor = IsValid(ply) and not ply:IsNPC() and ply.GetActiveWeapon and ply:GetActiveWeapon() or dmgInfo:GetInflictor()
	local dmg, force = dmgInfo:GetDamage(), dmgInfo:GetDamage() --dmgInfo:GetDamageForce():Length()
	local trPos, trNormal, trStart = tr.HitPos, tr.HitNormal, tr.StartPos
	if tr.MatType == MAT_FLESH then
		util.Decal("Impact.Flesh", trPos + trNormal, trPos - trNormal)
	end
	local dist = trStart:DistToSqr(trPos)
	if dist <= 160000 and (math.random(3) == 2 or force >= 35) and tr.Entity:IsWorld() and allowedMats[tr.MatType] then
		util.Decal("Impact.ShootAdd" .. math.random(shootDecalCount), trPos + trNormal, trPos - trNormal)
		util.ScreenShake(trPos, 3, 1, 1, 128)
	end

	-- if force >= 35 and dist <= 1400000 and (math.random(3) == 2 or force >= 45) and !tr.Entity:IsRagdoll() then
	-- 	util.Decal("Impact.ShootPowderAdd", trPos + trNormal, trPos - trNormal)
	-- 	util.ScreenShake(trPos, 3, 10, 1, 150)
	-- end
	local penetration, dmgmul
	if tr.Entity:IsVehicle() then
		penetration, dmgmul = hg.VehiclePenetration(tr.Entity, tr, bullet)
		dmgInfo:SetDamage(dmgInfo:GetDamage() * dmgmul)
	end

	-- Queued for the shared next-Think drain below; a timer.Simple(0) per
	-- impact was a heap insert + closure for every hit in a penetration chain.
	if bullet then
		local entry = hitEntryPool[#hitEntryPool]
		if entry then
			hitEntryPool[#hitEntryPool] = nil
		else
			entry = {}
		end
		entry[1], entry[2], entry[3] = Weapon or inflictor, tr, dmg
		entry[4], entry[5], entry[6] = force, bullet, penetration
		entry[7] = engine.TickCount() + 1
		hitQueueWrite[#hitQueueWrite + 1] = entry
	end
end

hg.bulletHit = bulletHit
hg.callbackBullet = callbackBullet
-- Deferred impact callbacks: one shared queue drained per Think instead of a
-- timer per impact. Entries queued while draining (penetration follow-up
-- hits) run on the next Think, matching the old timer.Simple(0) cadence.
hook.Add("Think", "ZCity.WeaponBase.BallisticQueues", function()
	if hitQueueWrite[1] ~= nil then
		hitQueueWrite, hitQueueDrain = hitQueueDrain, hitQueueWrite
		local drained = #hitQueueDrain
		local tick = engine.TickCount()
		for i = 1, drained do
			local entry = hitQueueDrain[i]
			if tick >= (entry[7] or 0) then
				-- An error in a callback used to abort this whole listener, so :360 never
				-- cleared entries i..drained. That array becomes hitQueueWrite on the next
				-- swap, and `#` on a table with holes returns an arbitrary border, so the
				-- re-queue in the else branch could overwrite live entries. Catch and carry on.
				local ok, err = pcall(callbackBullet, entry[1], entry[2], entry[3], entry[4], entry[5], entry[6])
				if not ok then
					ErrorNoHalt("[ZCity.WeaponBase.BallisticQueues] impact callback failed: " .. tostring(err) .. "\n")
				end
				for field = 1, 7 do entry[field] = nil end
				hitEntryPool[#hitEntryPool + 1] = entry
			else
				hitQueueWrite[#hitQueueWrite + 1] = entry
			end
			hitQueueDrain[i] = nil
		end
	end

	if ballisticEffects[1] == nil then return end
	local now, tick = CurTime(), engine.TickCount()
	for i = #ballisticEffects, 1, -1 do
		local job = ballisticEffects[i]
		if tick >= job.minTick and now >= job.due then
			local effectdata = EffectData()
			if job.kind == "material" then
				effectdata:SetNormal(job.normal)
				effectdata:SetStart(job.start)
				effectdata:SetMagnitude(job.magnitude)
				util.Effect("zippy_impact_" .. job.material, effectdata)
			else
				effectdata:SetOrigin(job.origin)
				effectdata:SetStart(job.start)
				if IsValid(job.weapon) then effectdata:SetEntity(job.weapon) end
				effectdata:SetMagnitude(job.magnitude)
				util.Effect("eff_tracer", effectdata)
			end
			local last = #ballisticEffects
			ballisticEffects[i] = ballisticEffects[last]
			ballisticEffects[last] = nil
			recycleBallisticEffect(job)
		end
	end
end)

-- Per-pellet bullet copy: shallow top-level plus a fresh Filter array.
-- table.Copy recursed into every nested table for every pellet (8 deep
-- copies per shotgun blast). Vectors were reference-copied by table.Copy
-- too, so sharing them here is unchanged behavior; each pellet keeps an
-- independent Filter, exactly as before.
local function CopyPelletBullet(src)
	local dst = {}
	for k, v in pairs(src) do
		dst[k] = v
	end

	if istable(src.Filter) then
		local filter = {}
		for j = 1, #src.Filter do
			filter[j] = src.Filter[j]
		end

		dst.Filter = filter
	end
	return setmetatable(dst, getmetatable(src))
end

local function ballisticTraceback(err)
	return debug.traceback(tostring(err), 2)
end

local function firePelletVolley(weapon, bullet, numbullet, penetration, diameter, usesLuaBullets, volleyContext, owner, suicideShot, headpos, ent, dir)
	for i = 1, numbullet do
		local pellet = CopyPelletBullet(bullet)
		pellet.penetrated = 0
		pellet.MaxPenLen = 100
		pellet.Penetration = penetration
		pellet.Diameter = diameter
		pellet.__ZCVolley = volleyContext
		pellet.__ZCPelletIndex = i
		if SERVER and suicideShot then
			local dmginfo = DamageInfo()
			dmginfo:SetDamage(pellet.Damage)
			dmginfo:SetInflictor(weapon)
			dmginfo:SetAttacker(owner)
			dmginfo:SetDamageType(DMG_BULLET)
			dmginfo:SetDamageForce(dir * pellet.Force)
			dmginfo:SetDamagePosition(headpos)
			ent:TakeDamageInfo(dmginfo)
		end

		if usesLuaBullets then
			weapon:FireLuaBullets(pellet)
		elseif SERVER then
			hg.PhysBullet.CreateBullet(pellet)
		end
	end
end

function SWEP:GetWeaponEntity()
	return IsValid(self.worldModel) and IsValid(self:GetOwner()) and self.worldModel or self
end

SWEP.attPos = Vector(0, 0, 0)
SWEP.attAng = Angle(0, 0, 0)
local gun
local vecZero = Vector(0, 0, 0)
local angZero = Angle(0, 0, 0)
local attTbl = {
	Pos = vecZero,
	Ang = angZero
}

function SWEP:GetMuzzleAtt(ent, trueAtt, supressorAdd)
	gun = ent or self:GetWeaponEntity()
	if not IsValid(gun) then return attTbl end
	local owner = IsValid(self) and self:GetOwner() or nil
	if not IsValid(owner) and IsValid(ent) and ent.GetOwner then owner = ent:GetOwner() end
	--do return {Pos=Vector(0,0,0),Ang=Angle(0,0,0)} end

	if SERVER and IsValid(owner) and owner:IsNPC() then
		attTbl.Pos = owner:EyePos()
		attTbl.Ang = owner:GetAimVector():Angle()
		return attTbl
	end

	--if true then return {Pos = self.desiredPos or vector_origin,Ang = self.desiredAng or angle_zero} end

	local att = gun:GetAttachment(gun:LookupAttachment( self:ShouldUseFakeModel() and self.FakeAttachment or "muzzle"))
	local att = att ~= nil and att or gun:GetAttachment(gun:LookupAttachment("muzzle_flash"))
	--local att = gun:GetAttachment(gun:LookupAttachment("muzzle"))
	--local att = att!=nil and att or gun:GetAttachment(gun:LookupAttachment("muzzle_flash"))
	local attPos = self.attPos
	local attAng = self.attAng

	if not att then
		local angHuy = gun:GetAngles()
		local posHuy = gun:GetPos()
		
		angHuy:RotateAroundAxis(angHuy:Forward(), 90)
		local _,angHuy = LocalToWorld(vecZero,attAng,vecZero,angHuy)
		
		posHuy:Add(angHuy:Up() * attPos[1] + angHuy:Right() * attPos[2] + angHuy:Forward() * attPos[3])
		if supressorAdd and self:HasAttachment("barrel", "supressor") then posHuy:Add(angHuy:Forward() * 10) end

		if self:ShouldUseFakeModel() then posHuy, angHuy = LocalToWorld(self.AttachmentPos, self.AttachmentAng, posHuy, angHuy) end

		attTbl.Pos = posHuy
		attTbl.Ang = angHuy

		return attTbl
	end
	
	if trueAtt then
		local pos, ang = att.Pos, att.Ang
		
		local pos, ang = LocalToWorld(attPos, attAng, pos, ang)
		

		att.Pos = pos
		att.Ang = ang
		ang:RotateAroundAxis(ang:Forward(),self.rotatehuy or 0)
		
		if self:ShouldUseFakeModel() then pos, ang = LocalToWorld(self.AttachmentPos, self.AttachmentAng, pos, ang) end

		--ang:Add(attAng)
		if supressorAdd and self:HasAttachment("barrel", "supressor") then pos:Add(ang:Forward() * 10) end
		--pos:Add(ang:Up() * attPos[1] + ang:Right() * attPos[2] + ang:Forward() * attPos[3])
	end

	if self:ShouldUseFakeModel() then att.Pos, att.Ang = LocalToWorld(self.AttachmentPos, self.AttachmentAng, att.Pos, att.Ang) end

	return att
end

local tr = {}
local att
local util_TraceLine = util.TraceLine

function SWEP:GetTrace(bCacheTrace, desiredPos, desiredAng, NoTrace, closeanim)
	-- Server cache is valid for this tick only. The old cache had no
	-- invalidation and could return the first muzzle trace indefinitely.
	if SERVER and !bCacheTrace and self.cache_trace and self.cache_trace[4] == CurTime()
		and !(desiredPos or desiredAng) and (NoTrace or self.cache_trace[1] ~= nil) then
		return self.cache_trace[1], self.cache_trace[2], self.cache_trace[3]
	end
	local owner = self:GetOwner()
	
	if IsValid(owner) and owner:IsNPC() then local att = self:GetMuzzleAtt() return nil,SERVER and owner:GetShootPos() or att.Pos,SERVER and owner:GetAimVector():Angle() or att.Ang end
	
	local gun = self:GetWeaponEntity()
	if !IsValid(gun) then return end

	local gunpos, gunang

	if CLIENT and !closeanim then
		gunpos, gunang = self.desiredPos, self.desiredAng
	else
		gunpos, gunang = self:WorldModel_Transform(true)
	end
	
	gunpos = gunpos or gun:GetPos()
	gunang = gunang or gun:GetAngles()
	--debugoverlay.Line(gunpos, gunpos + gunang:Forward() * 20,0.5,color_white)

	if CLIENT and self:ShouldUseFakeModel() then
		local mat = Matrix()
		mat:SetTranslation(self.FakePos)
		mat:SetAngles(self.FakeAng)
		mat = mat:GetInverse()
		gunpos, gunang = LocalToWorld(mat:GetTranslation(), mat:GetAngles(), gunpos, gunang)
	end
	
	local pos, ang = LocalToWorld(self.LocalMuzzlePos, self.LocalMuzzleAng, gunpos, gunang)
	
	if NoTrace then
		self.cache_trace = self.cache_trace or {}
		self.cache_trace[1] = nil
		self.cache_trace[2] = pos
		self.cache_trace[3] = ang
		self.cache_trace[4] = CurTime()
		if !bCacheTrace then
			return {}, pos, ang
		else
			return pos, ang
		end
	end

	local dir = ang:Forward()

	local fake = CLIENT and IsValid(owner) and owner.FakeRagdoll or nil
	local traceFilter = {self,gun}
	if IsValid(owner) and not owner.suiciding then
		traceFilter[#traceFilter + 1] = owner
		if IsValid(fake) then traceFilter[#traceFilter + 1] = fake end
	end
	tr.start = pos
	tr.endpos = pos + dir * 8000
	tr.filter = traceFilter

	local trace = util_TraceLine(tr)
	if bCacheTrace then
		self.cache_trace = self.cache_trace or {}
		self.cache_trace[1] = trace
		self.cache_trace[2] = pos
		self.cache_trace[3] = ang
		self.cache_trace[4] = CurTime()
	end

	if IsValid(owner) and owner.IsSuperAdmin and owner:IsSuperAdmin() then
		-- debugoverlay.Line(pos, pos + ang:Forward() * 1000, 0.1, SERVER and Color(255, 0, 0) or Color(0, 0, 255))
		-- debugoverlay.Sphere(trace.HitPos, 1, SERVER and 5 or 0.1, SERVER and Color(255, 0, 0) or Color(0, 255, 0))
	end

	return trace, pos, ang
end

SWEP.ShellEject = "EjectBrass_556"
SWEP.MuzzleEffectType = 1


local images_muzzle = {
	[2] = {"effects/muzzleflash1", "effects/muzzleflash2", "effects/muzzleflash3", "effects/muzzleflash4"},
	[3] = {"effects/gunshipmuzzle","effects/combinemuzzle2"}
}
local vecZero = Vector(0, 0, 0)
local image_distort = "sprites/heatwave"

SWEP.PPSMuzzleEffect = "pcf_jack_mf_mpistol" -- shared in sh_effects.lua
SWEP.PPSMuzzleEffectSuppress = "pcf_jack_mf_suppressed"

function SWEP:GetLocalHuynyis()
	local gun = self:GetWeaponEntity()
	local owner = self:GetOwner()

	local atth = gun:GetAttachment(gun:LookupAttachment("muzzle"))
	local atth = atth ~= nil and atth or gun:GetAttachment(gun:LookupAttachment("muzzle_flash"))
	
	local att2 = self:GetMuzzleAtt(gun,false)
	local muzzle_local_pos,muzzle_local_ang = WorldToLocal(att2.Pos,att2.Ang,gun:GetPos(),gun:GetAngles())
	if atth then
		muzzle_local_pos,muzzle_local_ang = LocalToWorld(self.attPos,self.attAng,muzzle_local_pos,muzzle_local_ang)
	end
	if not IsValid(owner.FakeRagdoll) then
		muzzle_local_ang:RotateAroundAxis(muzzle_local_ang:Up(),-(self.rotatehuy or 0))
	end

	return muzzle_local_pos,muzzle_local_ang
end

function SWEP:GetRealDebilAttachment(muzzle_local_pos,muzzle_local_ang)
	if not IsValid(owner) then return end
	local gun = self:GetWeaponEntity()
	local owner = self:GetOwner()
	local eyeang = owner:GetAimVector():Angle()
	eyeang[3] = eyeang[3] + (owner:EyeAngles()[3])
	local eyeang = eyeang + (self.weaponAngLerp or angZero)
	local _,ang2 = LocalToWorld(vector_origin,muzzle_local_ang,vector_origin,eyeang)
	local pos,ang = LocalToWorld(muzzle_local_pos,muzzle_local_ang,gun:GetPos(),gun:GetAngles())
	local angh = (owner.suiciding or IsValid(owner.FakeRagdoll)) and ang or ang2

	return pos,angh
end

/*for i, ent in pairs(ents.FindByClass("weapon_akm")) do
	if !IsValid(ent) then continue end
	ent:PrimaryAttack()
end*/

function SWEP:FireBullet()
    local gun = self:GetWeaponEntity()
    local owner = self:GetOwner()
	local isply = IsValid(owner) and owner:IsPlayer()
	local isnpc = IsValid(owner) and owner:IsNPC()
	local ent = owner

	if self:ShouldUseFakeModel() and not self.NoIdleLoop and isply then
		self:PlayAnim("idle", 1)
	end

	if isply then
		local character = hg.GetCurrentCharacter(owner)
		ent = IsValid(character) and character or owner
	end

    local ammotype = hg.ammotypeshuy[self.Primary.Ammo].BulletSettings
    
	if SERVER and !timer.Exists("ShootWeaponAfterDeath"..self:EntIndex()) then
		timer.Create("ShootWeaponAfterDeath"..self:EntIndex(), 0.1, 1, function()
			if not IsValid(self) then return end
			if (!IsValid(owner) or !owner:Alive()) and self.Primary and self.Primary.Automatic then
				self:PrimaryAttack()
			end
		end)
	end

    local att = self:GetMuzzleAtt(gun, true)
    if not att then return end
    local pos, ang = att.Pos, att.Ang
    //if not isply and not owner:IsNPC() then return end
    local fakeGun = self:GetNWEntity("fakeGun")

    local primary = self.Primary

	if isply then
		owner:LagCompensation(true)
	end

	self:WorldModel_Transform()
	local tr, pos, ang = self:GetTrace(true)

	if isply then
		owner:LagCompensation(false)
	end

	local trace
	local dir = ang:Forward()
	if isply then
		//print(gun:GetAngles(), dir, owner.offsetView)
		local dist, point = util.DistanceToLine(pos, pos - dir * 50, owner:EyePos())
		local tr = {}
		tr.start = point
		tr.endpos = pos
		tr.filter = {owner, ent, SERVER and hg.ragdollFake[owner]}
		trace = util.TraceLine(tr)
	end

    local numbullet = ammotype.NumBullet or 1

	if not IsValid(owner) then
		local phys = self:GetPhysicsObject()

		if IsValid(phys) then
			phys:ApplyForceOffset(-dir * self.Primary.Force * 5, pos)
		end
	else
		local char = hg.GetCurrentCharacter(owner)
		local phys = IsValid(char) and char:GetPhysicsObjectNum(0) or nil
		
		if IsValid(phys) then
			phys:ApplyForceCenter(-dir * math.min(self.Primary.Force, 70) * 40 * (self.NumBullet or 1))
		end
	end

	--[[local enta = ents.Create("prop_physics")
	enta:SetModel("models/props_c17/lampShade001a.mdl")
	enta:SetPos(head:GetTranslation() + head:GetAngles():Forward() * 15)
	enta:Spawn()
	enta:SetSolidFlags(FSOLID_NOT_SOLID)
	enta:GetPhysicsObject():EnableMotion(false)--]]

	local headpos, headang
	-- Ordinary server shots do not consume the head transform.
	if CLIENT or (IsValid(owner) and owner.suiciding) then

	if isply then
		owner:LagCompensation(true)
	end

	if CLIENT then
		if IsValid(ent) then
			local headBone = ent:LookupBone("ValveBiped.Bip01_Head1")
			local head = headBone and ent:GetBoneMatrix(headBone)

			if head then
				headpos, headang = head:GetTranslation(), head:GetAngles()
			else
				headpos, headang = ent:GetPos(), ent:GetAngles()
			end
		end
	else
		--[[if IsValid(ent) then
			headpos, headang = ent:GetBonePosition(ent:LookupBone("ValveBiped.Bip01_Head1"))
			headpos = headpos + headang:Forward() * 3-- - dir * 10
		end]]
		if IsValid(ent) then
			local headBone = ent:LookupBone("ValveBiped.Bip01_Head1")
			local head = headBone and ent:GetBoneMatrix(headBone)

			if head then
				headpos, headang = head:GetTranslation(), head:GetAngles()
			else
				headpos, headang = ent:GetPos(), ent:GetAngles()
			end
		end
	end
	
	if isply then
		owner:LagCompensation(false)
	end

	end

	local willsuicide = CurTime() + 1
	local suiciding = false
	if IsValid(owner) then
		local networkedSuicideAt = owner:GetNWFloat("willsuicide", 0)
		willsuicide = networkedSuicideAt != 0 and networkedSuicideAt or (owner.startsuicide or CurTime()) + 1
		suiciding = owner.suiciding == true
	end
	local willsuicidereal = suiciding and (willsuicide == 0 or willsuicide < CurTime())
	if isnpc then
		suiciding, willsuicidereal = false, false
	end

	local bullet = {}
    bullet.Src = (willsuicidereal and headpos or (trace and (trace.HitPos - trace.Normal) or pos))
	bullet.Dir = dir
	bullet.Attacker = owner
	
	if IsValid(owner) and owner.IsSuperAdmin and owner:IsSuperAdmin() then
    	--debugoverlay.Line(bullet.Src, bullet.Src + bullet.Dir * 1000, 5, SERVER and Color(255, 0, 0) or Color(0, 0, 255))
    	--debugoverlay.Sphere(bullet.Src, 10, 5, SERVER and Color(255, 0, 0) or Color(0, 0, 255))
    	--debugoverlay.Sphere(headpos, 10, 5, SERVER and Color(255, 0, 0) or Color(0, 0, 255))
	end

	if isnpc and CLIENT then
		local npcYawOffset = math.Remap( owner:GetPoseParameter("aim_yaw"),0,1,-60,60 )
		local npcPitchOffset = math.Remap( owner:GetPoseParameter("aim_pitch"),0,1,-88,50 )
		bullet.Dir = (owner:GetAngles()+AngleRand(-4,4)+Angle(npcPitchOffset,npcYawOffset,0)):Forward()
	end

	bullet.Force = ammotype.Force and ammotype.Force / 1.5 or primary.Force
    bullet.Damage = ammotype.Damage or primary.Damage or 25
	bullet.Damage = bullet.Damage * (self.Supressor and 0.9 or 1) * (self.DamageMultiplier or 1)

	bullet.Spread = (ammotype.Spread or self.Primary.Spread or 0) * 3
	bullet.Num = 1
	
	bullet.AmmoType = primary.Ammo
	bullet.TracerName = self.Tracer or "nil"
    bullet.IgnoreEntity = nil
    bullet.Callback = bulletHit

	local filter = {self, self.worldModel}
	if IsValid(owner) and owner.InVehicle and owner:InVehicle() then
		local veh = owner:GetVehicle()
		
		table.insert(filter, veh)
		table.insert(filter, veh:GetParent())

		if veh.seats then
			for i, seat in pairs(veh.seats) do
				table.insert(filter, seat)
			end
		end
	end

    bullet.Speed = ammotype.Speed
	bullet.Distance = ammotype.Distance or 56756
	bullet.Filter = filter

	bullet.noricochet = ammotype.noricochet
	
	local f1 = IsValid(owner) and not suiciding and owner or nil
	local f2 = isply and owner:InVehicle() and owner:GetVehicle() or nil
	local f3 = isply and owner.GetSimfphys and IsValid(owner:GetSimfphys()) and owner:GetSimfphys() or nil
	local f4 = isply and owner:InVehicle() and owner.FakeRagdoll or nil
	local f5 = IsValid(owner) and IsValid(owner.OldRagdoll) and owner.OldRagdoll or nil
	
	if IsValid(f1) then table.insert(bullet.Filter, 1, f1) end
	if IsValid(f2) then table.insert(bullet.Filter, 1, f2) end
	if IsValid(f3) then table.insert(bullet.Filter, 1, f3) end
	if IsValid(f4) then table.insert(bullet.Filter, 1, f4) end
	if IsValid(f5) then table.insert(bullet.Filter, 1, f5) end

	bullet.Inflictor = self
	bullet.DontUsePhysBullets = self.DontUsePhysBullets
	if isnpc then
		--[[self.DontUsePhysBullets = true
		bullet.DontUsePhysBullets = true]]
		bullet.IgnoreEntity = owner
	end
	
	local usesLuaBullets = not (hg.PhysBullet and self.UsePhysBullets)
	local volleyContext = usesLuaBullets and {ammo = {}} or nil
	local penetration = math.max(0, tonumber(ammotype.Penetration) or tonumber(self.Penetration) or 0)
		* math.max(0, tonumber(self.PenetrationMultiplier) or 1)
	local diameter = ammotype.Diameter or 1
	local suicideShot = isply and suiciding and willsuicidereal

	-- FireLuaBullets normally toggles lag compensation per call. Shotguns call it
	-- once per pellet, so own one compensation window for the complete volley.
	local managesVolleyLagComp = usesLuaBullets and isply and numbullet > 1
	if managesVolleyLagComp then
		owner:LagCompensation(true)
		volleyContext.lagCompensated = true
		local ok, err = xpcall(function()
			firePelletVolley(self, bullet, numbullet, penetration, diameter,
				usesLuaBullets, volleyContext, owner, suicideShot, headpos, ent, dir)
		end, ballisticTraceback)
		owner:LagCompensation(false)
		volleyContext.lagCompensated = false
		if not ok then error(err, 0) end
	else
		firePelletVolley(self, bullet, numbullet, penetration, diameter,
			usesLuaBullets, volleyContext, owner, suicideShot, headpos, ent, dir)
	end

	-- The old loop emitted the exact same precomputed tracer once per pellet.
	-- One visual tracer per discharge is equivalent information with less work.
	if CLIENT and usesLuaBullets and !GetGlobalBool("PhysBullets_ReplaceDefault") and tr then
		local effectdata1 = EffectData()
		if tr.HitPos then effectdata1:SetOrigin(tr.HitPos) end
		if tr.StartPos then effectdata1:SetStart(pos) end
		effectdata1:SetEntity(self)
		effectdata1:SetMagnitude(1)
		util.Effect("eff_tracer", effectdata1)
	end

	if CLIENT then
		local att = self:GetMuzzleAtt(gun, true)
		if not att then return end
		local pos, ang = att.Pos, att.Ang

		local mul = self.MuzzleMul or 1
		mul = mul * (self.Supressor and 0.25 or 1)

		if mul > 0 then
			if not self.Supressor then 
				ParticleEffect(self.PPSMuzzleEffect, pos, ang, self)
			else
				ParticleEffect(self.PPSMuzzleEffectSuppress, pos, ang, self)
			end
			hg_potatopc = hg_potatopc or hg.ConVars.potatopc
			if not hg_potatopc:GetBool() then
				local dlight = DynamicLight(self:EntIndex())
				dlight.pos = pos
				dlight.r = math_random(245, 255)
				dlight.g = math_random(245, 255)
				dlight.b = math_random(150, 200)
				dlight.brightness = math_Rand(7, 8)
				dlight.Decay = 4000
				dlight.Size = math_Rand(60, 75) * mul
				dlight.DieTime = CurTime() + 1 / 60
			end
		end
	end

	self:PostFireBullet(bullet)
end

function SWEP:PostFireBullet()
end

if CLIENT then
	net.Receive("reject shell",function()
		local ent = net.ReadEntity()
		if ent and ent.RejectShell then
			ent:RejectShell(net.ReadString())
		end
	end)

	function SWEP:RejectShell(shell)
		if not shell then return end
		local gun = self:GetWM()
		if not IsValid(gun) then return end
		local attmuzle = self:GetMuzzleAtt(gun, true)
		local att = gun:GetAttachment(gun:LookupAttachment(self.FakeEjectBrassATT or "ejectbrass")) or gun:GetAttachment(gun:LookupAttachment("shell"))
		local pos, ang
		if not att then
			pos, ang = gun:GetPos(), gun:GetAngles()
		else
			pos, ang = att.Pos, att.Ang
		end

		local _
		if self.EjectPos then pos = gun:GetPos() + ang:Right() * self.EjectPos.x + ang:Up() * self.EjectPos.z + ang:Forward() * self.EjectPos.y end
		if self.EjectAng then _,ang = LocalToWorld(vecZero,self.EjectAng,vecZero,ang) end

		local ammotype = hg.ammotypeshuy[self.Primary.Ammo].BulletSettings
		local ejectAng = attmuzle.Ang
		if self.EjectAddAng then
			_,ejectAng = LocalToWorld(vecZero,self.EjectAddAng,vecZero,attmuzle.Ang) 
		end
		if self.CustomSecShell then self:MakeShell(self.CustomSecShell, pos, ejectAng, ang:Forward() * 75) end
		if ammotype.Shell or self.CustomShell then self:MakeShell(ammotype.Shell or self.CustomShell, pos, ejectAng, ang:Forward() * 105) return end
		local effectdata = EffectData()
		effectdata:SetOrigin(pos)
		effectdata:SetAngles(ang)
		effectdata:SetFlags(25)
		util.Effect(shell, effectdata)
	end
else
	util.AddNetworkString("reject shell")
	function SWEP:RejectShell(shell)
		net.Start("reject shell")
			net.WriteEntity(self)
			net.WriteString(shell)
		net.Broadcast()
	end
end