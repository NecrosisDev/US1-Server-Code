
local MODE = MODE

MODE.GuiltDisabled = true
MODE.PoliceTime = 9999

function MODE:AfterBaseInheritance()
	-- deep copies: as plain references these carry standard/soe's
	-- ChanceFunctions (which return STANDARD's ~0.2 rotation chance), so
	-- fear's types flooded the rotation. The types ARE fear's entry into
	-- the roll (base-derived modes don't get an independent mode-level
	-- entry), so give each half of fear's intended total - tunable via
	-- zb_setmodechance fear <x>.
	self.Types.fear = table.Copy(self.Types.standard)
	self.Types.fear_soe = table.Copy(self.Types.soe)

	-- fear only rolls on night maps (name contains "night") or maps
	-- you've approved via the fear_allowmap command (persisted)
	local function FearMapAllowed()
		local map = string.lower(game.GetMap())
		if string.find(map, "night", 1, true) then return true end
		if not MODE.FearMaps then
			MODE.FearMaps = util.JSONToTable(file.Read("fear_maps.txt", "DATA") or "") or {}
		end
		return MODE.FearMaps[map] == true
	end

	local function FearChance()
		if not FearMapAllowed() then return 0 end
		return (zb.ModesChances["fear"] or 0.03) / 2
	end

	self.Types.fear.Chance = 0.015
	self.Types.fear.ChanceFunction = FearChance
	self.Types.fear_soe.Chance = 0.015
	self.Types.fear_soe.ChanceFunction = FearChance

	self.Types.wildwest = nil
	self.Types.gunfreezone = nil
	self.Types.standard = nil
	self.Types.soe = nil
end

function MODE:CanLaunch()
	-- natural rotation: needs a real lobby for the horror to work
	return #zb:CheckPlaying() >= 2
end

function MODE:IsDoor(ent)
	return ent:GetClass() == "prop_door_rotating" or ent:GetClass() == "prop_door"
end

local crysound
local hooks = {}
function MODE:RandomStuff()
	for _, v in ents.Iterator() do
		if self:IsDoor(v) then
			if math.random(1, 100) != 1 then continue end
			v:Fire("Toggle")
		elseif v.GetPhysicsObject and IsValid(v:GetPhysicsObject()) and !self:IsDoor(v) then
			if v:GetClass() == "prop_ragdoll" then
				if math.random(1, 100) != 1 then continue end
				local bones = v:GetPhysicsObjectCount()
				for i = 0, bones - 1 do
					local phys = v:GetPhysicsObjectNum( i )
					if ( IsValid( phys ) ) then
						phys:EnableGravity(false)
						phys:Wake()

						phys:SetVelocity(Vector(math.Rand(-1000, 1000), math.Rand(-1000, 1000), math.Rand(-1000, 1000)))
					end
				end
			else
				if math.random(1, 5000) != 1 then continue end
				v:GetPhysicsObject():SetVelocity(Vector(math.Rand(-1000, 1000), math.Rand(-1000, 1000), math.Rand(-1000, 1000)))
			end
		end
	end

	if math.random(1, 25) == 1 and !IsValid(crysound) then
		local snd = math.random(2) == 1 and "cry2.wav" or "cry1.wav"
		if crysound then return end
		local tbl = ents.FindByClass("func_door_rotating")
		table.Add(ents.FindByClass("prop_door_rotating"))
		
		local door
		for i, ent in RandomPairs(tbl) do
			if DoorIsOpen(ent) then
				door = ent

				break
			end
		end

		local pos = door:GetPos() + door:GetAngles():Right() * 1
		crysound = CreateSound(door, snd)
		crysound:Play()

		hook.Add("PlayerUse", "dooruse"..door:EntIndex(), function(ply, ent)
			if ent == door then
				crysound:Stop()
				crysound = nil
			end

			hook.Remove("PlayerUse", "dooruse"..ent:EntIndex())
		end)

		hooks[#hooks + 1] = "dooruse"..door:EntIndex()

		return
	end
end

hook.Add("PostCleanupMap", "removehooksass", function()
	for i, hooka in ipairs(hooks) do
		hook.Remove("PlayerUse", hooka)
	end
end)

local modes = {
	"fear_soe",
	"fear",
}

function MODE:SubModes()
	return modes
end

function MODE:Intermission()
	game.CleanUpMap()

	-- fear inherits hmcd's equip machinery, which reads hmcd.Type -
	-- left stale from the last homicide round (wildwest, gunfreezone,
	-- etc.) it dresses fear rounds in the wrong loadout. Pin it.
	local hmcd = zb.modes["hmcd"]
	if hmcd then hmcd.Type = "standard" end

	MODE.saved.TimePlayed = 0
	MODE.saved.KillTime = CurTime() + 30

	self.NightApplied = nil
	self.NextWhisper = nil
	self.NextAmbient = nil
	self.NextSighting = nil
	self.NextBlackGuy = nil
	self.NextCharple = nil
	self.NextDoors = nil
	self.NextLightTheft = nil
	self.NextBodySwap = nil
	self.NextDoorLock = nil
	self.NextLightCheck = nil
	self.LightAttn = 0
	self.LightAngerCooldown = 0
	self.LastMarked = nil
	self.SwapHappened = nil
	self.Enraged = nil
	self.NextFavor = nil
	self.NextFling = nil

	-- hygiene: no one starts a round ghosted by a stale flag
	for _, p in player.Iterator() do
		if p:GetNetVar("disappearance") then
			p:SetNetVar("disappearance", nil)
			p:SetCustomCollisionCheck(false)
			p:CollisionRulesChanged()
		end
	end
	self.PactBroken = nil
	self.LastAloneSent = nil
	if IsValid(self.NightEnt) then SafeRemoveEntity(self.NightEnt) self.NightEnt = nil end

	local _,CROUND = CurrentRound()

	if not CROUND or CROUND == "hmcd" then
		CROUND = table.Random(self:SubModes())
	end

	self.Type = CROUND
	local player_count = 0

	for k, ply in player.Iterator() do
		if ply:Team() == TEAM_SPECTATOR then continue end
		ply:KillSilent()

		ply.isPolice = false
		ply.isTraitor = false
		ply.isGunner = false
		ply.MainTraitor = false
		ply.SubRole = nil
		ply.Profession = nil

		ply:SetupTeam(0)

		ply.organism.recoilmul = DefaultSkillIssue
		player_count = player_count + 1
	end

	MODE.TraitorFrequency = nil
	MODE.TraitorWord = MODE.TraitorWords[math.random(1, #MODE.TraitorWords)]
	MODE.TraitorWordSecond = MODE.TraitorWords[math.random(1, #MODE.TraitorWords)]
	local traitors_needed = 1 -- always exactly one traitor

	MODE.TraitorExpectedAmt = traitors_needed
	local main_traitor = nil
	local traitors = {}


	MODE.NextRoundMainTraitors = MODE.NextRoundMainTraitors or {}

	-- pull the admin panel's forced list directly - the injection hook
	-- loses the timing race against this selection; the global can't
	if TraitorAdmin and TraitorAdmin.ForcedSteamIDs then
		for _, sid in ipairs(TraitorAdmin.ForcedSteamIDs) do
			MODE.NextRoundMainTraitors[sid] = true
		end
	end

	-- forced picks first (traitor admin panel), then random fill
	for i, ply in RandomPairs(player.GetAll()) do
		if traitors_needed <= 0 then break end
		if ply.isTraitor or ply:Team() == TEAM_SPECTATOR then continue end
		if not MODE.NextRoundMainTraitors[ply:SteamID()] then continue end

		ply.isTraitor = true
		traitors_needed = traitors_needed - 1
		traitors[#traitors + 1] = ply
		main_traitor = ply
		ply.MainTraitor = true
		MODE.NextRoundMainTraitors[ply:SteamID()] = nil
	end

	for i, ply in RandomPairs(player.GetAll()) do
		if ply.isTraitor or ply:Team() == TEAM_SPECTATOR then continue end

		if traitors_needed > 0 then
			ply.isTraitor = true
			traitors_needed = traitors_needed - 1
			traitors[#traitors + 1] = ply

			main_traitor = ply
			ply.MainTraitor = true
		end
	end


	for i, ply in RandomPairs(player.GetAll()) do
		if ply.isTraitor or ply:Team() == TEAM_SPECTATOR then continue end
		if math.random(100) > (ply.Karma or 100) then continue end

		if traitors_needed > 0 then
			ply.isTraitor = true
			traitors_needed = traitors_needed - 1
			traitors[#traitors + 1] = ply

			if not main_traitor then
				main_traitor = ply
				ply.MainTraitor = true
			end
		end
	end

	if traitors_needed > 0 then
		for i, ply in RandomPairs(player.GetAll()) do
			if ply.isTraitor or ply:Team() == TEAM_SPECTATOR then continue end

			if traitors_needed > 0 then
				ply.isTraitor = true
				traitors_needed = traitors_needed - 1
				traitors[#traitors + 1] = ply

				if not main_traitor then
					main_traitor = ply
					ply.MainTraitor = true
				end
			end
		end
	end

	-- self.saved.PoliceTime = CurTime() + math.min(self.Types[self.Type].PoliceTime * (#player.GetAll() / 4),self.Types[self.Type].PoliceTime * 2.2)
	self.saved.PoliceTime = 99999
	self.PoliceSpawned = false
	self.PoliceAllowed = false

	for k, ply in player.Iterator() do
		if(MODE.ShouldStartRoleRound())then
			net.Start("HMCD_RoundStart")	--; TODO Structure description
				net.WriteBool(ply.isTraitor)	--; Is Traitor
				net.WriteBool(ply.isGunner)	--; Is Gunner
				net.WriteString(self.Type)	--; Round Type
				net.WriteBool(false)	--; Round Started
				net.WriteString("")	--; SubRole
				net.WriteBool(ply.MainTraitor == true)	--; MainTraitor

				if(ply.isTraitor)then
					net.WriteString(MODE.TraitorWord)
					net.WriteString(MODE.TraitorWordSecond)
					net.WriteUInt(MODE.TraitorExpectedAmt, MODE.TraitorExpectedAmtBits)
				else
					net.WriteString("")
					net.WriteString("")
					net.WriteUInt(0, MODE.TraitorExpectedAmtBits)
				end

				net.WriteString("")	--; Profession
			net.Send(ply)

			local role = self.Roles[self.Type][(ply.isTraitor and "traitor") or (ply.isGunner and "gunner") or "innocent"]

			zb.GiveRole(ply, role.name, role.color)
		end
	end

	self:CreateTimer("WaitForRandomStuff", math.Rand(60, 120), 1, function()
		self:CreateTimer("FearRandomStuff", 5, 0, function()
			self:RandomStuff()
		end)
	end)
end

function MODE:ShouldRoundEnd()
	return #zb:CheckAlive() == 0
end

function MODE:EndRound()
	if IsValid(self.NightEnt) then SafeRemoveEntity(self.NightEnt) self.NightEnt = nil end
	timer.Remove("HMCDSpawnSWAT")
	timer.Remove("SpawnAdditionalPolice")
	timer.Remove("SpawnAdditionalNationalGuard")

	for k, _ in pairs(self.saved.Timers or {}) do
		timer.Remove(k)
	end

	self.deadPoliceCount = 0
	self.swatDeployed = false
	self.spawnedPoliceCount = 0
	self.roundStartType = nil

	local traitors, gunners = {}, {}
	local players_alive = 0
	local endround, winner = zb:CheckWinner(self:CheckAlivePlayers())

	for i, ply in player.Iterator() do
		if ply.isTraitor and ply:Team() ~= TEAM_SPECTATOR then
			traitors[#traitors + 1] = ply
		end

		if ply.isGunner and ply:Team() ~= TEAM_SPECTATOR then
			gunners[#gunners + 1] = ply
		end

		if(ply:Alive() and ply.organism and !ply.organism.incapacitated)then
			players_alive = players_alive + 1
		end

		ply.isPolice = false
		ply.isTraitor = false
		ply.isGunner = false
		ply.MainTraitor = false
		ply.SubRole = nil
		ply.Profession = nil

		self:ResetNetworkVars(ply)
	end

	timer.Simple(2,function()
		net.Start("hmcd_roundend")
			net.WriteUInt(#traitors, MODE.TraitorExpectedAmtBits)

			for _, traitor in ipairs(traitors) do
				net.WriteEntity(traitor)
			end

			net.WriteUInt(#gunners, MODE.TraitorExpectedAmtBits)

			for _, gunner in ipairs(gunners) do
				net.WriteEntity(gunner)
			end
		net.Broadcast()
	end)
end

-- =====================================================================
-- The finale: when the last one alive would have merely disappeared,
-- it comes for them in person instead. A whisper, then the burnt thing
-- sprints out of the dark, camera locked, and takes them on contact.
-- =====================================================================
function MODE:LastRites(ply)
	if self.LastRitesActive then return end
	self.LastRitesActive = true

	if not IsValid(ply) or not ply:Alive() then self.LastRitesActive = nil return end

	if ply.Notify then ply:Notify("There is no one left to take but you.", 0) end

	-- THE SURROUND: figures appear one by one in a ring around them,
	-- facing in. Then, blink by blink, the ring tightens. When the
	-- circle is close enough to touch... it all goes dark at once.
	local COUNT = 7
	local figs = {}
	local angles = {}
	local baseAng = math.Rand(0, math.pi * 2)
	for i = 1, COUNT do
		angles[i] = baseAng + (i - 1) * (math.pi * 2 / COUNT)
	end

	local function PlaceFig(fig, ang, radius)
		if not IsValid(ply) then return false end
		local center = ply:GetPos()
		local pos = center + Vector(math.cos(ang) * radius, math.sin(ang) * radius, 40)
		local floor = util.TraceLine({
			start = pos,
			endpos = pos - vector_up * 400,
			filter = ply,
		})
		if not floor.Hit then return false end
		fig:SetPos(floor.HitPos)
		fig:SetAngles(Angle(0, (center - floor.HitPos):Angle().yaw, 0))
		return true
	end

	local function Teardown(killedThem)
		timer.Remove("FearSurround")
		for _, f in ipairs(figs) do
			if IsValid(f) then f:Remove() end
		end
		self.LastRitesActive = nil
	end

	local state = "spawning"
	local spawned = 0
	local radius = 480
	local nextStep = CurTime() + 1.5

	timer.Create("FearSurround", 0.1, 0, function()
		if not IsValid(ply) or not ply:Alive() then
			Teardown(false)
			return
		end
		if CurTime() < nextStep then return end

		if state == "spawning" then
			spawned = spawned + 1
			local fig = ents.Create("ent_zc_anim")
			if IsValid(fig) then
				fig:SetModel("models/Humans/Group01/male_06.mdl")
				fig:SetMaterial("models/debug/debugwhite")
				fig:SetColor(color_black)
				fig:Spawn()
				fig:ResetSequence(126)
				if PlaceFig(fig, angles[spawned], radius) then
					figs[#figs + 1] = fig
					sound.Play("ambient/wind/wind_hit1.wav", fig:GetPos(), 62, 70)
				else
					fig:Remove()
				end
			end

			if spawned >= COUNT then
				if #figs < 3 then
					-- nowhere to stand: it takes them plainly
					Teardown(false)
					hg.BreakNeck(ply)
					return
				end
				state = "tightening"
				nextStep = CurTime() + 1.8
			else
				nextStep = CurTime() + 1.1
			end

		elseif state == "tightening" then
			radius = radius * 0.72

			if radius < 95 then
				-- the final beat: hold... then all of them, at once, gone
				state = "finale"
				nextStep = CurTime() + 1.0
				return
			end

			-- the blink: every figure is suddenly closer, re-ringed
			-- around wherever they've run to
			for i, fig in ipairs(figs) do
				if IsValid(fig) then
					PlaceFig(fig, angles[i], radius)
				end
			end
			sound.Play("ambient/levels/citadel/strange_talk4.wav", ply:GetPos(), 68, 80)
			nextStep = CurTime() + 1.4

		elseif state == "finale" then
			for _, fig in ipairs(figs) do
				if IsValid(fig) then fig:Remove() end
			end
			ply:EmitSound("ambient/wind/wind_hit1.wav", 85, 85)

			timer.Remove("FearSurround")
			timer.Simple(0.5, function()
				if IsValid(ply) and ply:Alive() then
					ply:EmitSound("lurker_scream.wav", 100, 100)
					hg.BreakNeck(ply)
					for _, v in player.Iterator() do
						v:ScreenFade(SCREENFADE.IN, Color(0, 0, 0), 1.2, 0.6)
					end
				end
				self.LastRitesActive = nil
			end)
		end
	end)
end

-- =====================================================================
-- The Floor Take: the victim collapses and sinks halfway into the
-- floor - held there, frozen, for three seconds - then their neck
-- snaps. The body stays half-buried. Solver-safe: physics are frozen
-- BEFORE the body is moved into the world, so Source never tries to
-- resolve the penetration (corpse-sleeper technique).
-- =====================================================================
function MODE:FloorTake(ply)
	if not IsValid(ply) or not ply:Alive() then return end

	-- must be standing on world geometry with some thickness below
	local floorTr = util.TraceLine({
		start = ply:GetPos() + vector_up * 5,
		endpos = ply:GetPos() - vector_up * 40,
		filter = ply,
	})
	if not floorTr.HitWorld then
		ply:KillSilent() -- nowhere to sink; it takes them the plain way
		return
	end

	hg.StunPlayer(ply)
	ply:EmitSound("physics/body/body_medium_impact_hard1.wav", 75, 90)

	timer.Simple(0.4, function()
		if not IsValid(ply) or not ply:Alive() then return end

		local rag = hg.GetCurrentCharacter(ply)
		if not IsValid(rag) or rag == ply then
			hg.BreakNeck(ply)
			return
		end

		-- freeze every bone FIRST, then sink the frozen body
		for i = 0, rag:GetPhysicsObjectCount() - 1 do
			local phys = rag:GetPhysicsObjectNum(i)
			if IsValid(phys) then
				phys:EnableMotion(false)
			end
		end

		timer.Simple(0.1, function()
			if not IsValid(rag) then return end
			ply:EmitSound("ambient/materials/rock_impact_hard2.wav", 70, 80)
			for i = 0, rag:GetPhysicsObjectCount() - 1 do
				local phys = rag:GetPhysicsObjectNum(i)
				if IsValid(phys) then
					phys:SetPos(phys:GetPos() - vector_up * 20)
				end
			end
		end)

		-- three seconds half-buried, then the crack
		timer.Simple(3.1, function()
			if not IsValid(ply) or not ply:Alive() then return end
			hg.BreakNeck(ply)
		end)
	end)
end

-- =====================================================================
-- Traitor Rites: the cultist's own end. Frozen in place, gaze forced
-- to open ground, the burnt thing walks to them slowly - savoring -
-- then lunges. The neck snap ends the pact.
-- =====================================================================
function MODE:TraitorRites(ply)
	if self.TraitorRitesActive then return end
	self.TraitorRitesActive = true

	if not IsValid(ply) or not ply:Alive() then self.TraitorRitesActive = nil return end

	-- find ground for it: prefer a long walk, accept shorter and
	-- shorter, and if the room allows nothing - it is simply THERE,
	-- close enough to touch. The entity always comes in person.
	local spawnPos, spawnYaw
	for _, wantDist in ipairs({ 450, 320, 220, 150 }) do
		for i = 1, 10 do
			local yaw = math.random(0, 359)
			local dir = Angle(0, yaw, 0):Forward()
			local tr = util.TraceHull({
				start = ply:EyePos(),
				endpos = ply:EyePos() + dir * (wantDist + 100),
				filter = ply,
				maxs = Vector(20, 20, 40),
				mins = Vector(-20, -20, 0),
			})
			if tr.HitPos:Distance(ply:EyePos()) >= wantDist then
				local floor = util.TraceLine({
					start = tr.HitPos - dir * 60,
					endpos = (tr.HitPos - dir * 60) - vector_up * 500,
				})
				if floor.Hit then
					spawnPos = floor.HitPos
					spawnYaw = yaw
					break
				end
			end
		end
		if spawnPos then break end
	end

	if not spawnPos then
		-- nowhere to walk from: it appears within arm's reach, facing
		-- them, and takes a moment to be seen before it takes them
		local dir = ply:GetAimVector()
		dir.z = 0
		dir:Normalize()
		local floor = util.TraceLine({
			start = ply:GetPos() + dir * 90 + vector_up * 40,
			endpos = ply:GetPos() + dir * 90 - vector_up * 300,
		})
		spawnPos = floor.Hit and floor.HitPos or (ply:GetPos() + dir * 90)
		spawnYaw = (spawnPos - ply:GetPos()):Angle().yaw + 180
	end

	ply:Freeze(true)
	ply:SetEyeAngles(Angle(5, spawnYaw, 0))

	local fig = ents.Create("ent_zc_anim")
	if not IsValid(fig) then
		ply:Freeze(false)
		hg.BreakNeck(ply)
		self.TraitorRitesActive = nil
		return
	end

	fig:SetPos(spawnPos)
	fig:SetModel("models/humans/charple01.mdl")
	fig:SetAngles(Angle(0, spawnYaw + 180, 0))
	fig:Spawn()
	local seq = fig:LookupSequence("walk_all")
	if seq < 0 then seq = fig:LookupSequence("run_all") end
	if seq < 0 then seq = 126 end
	fig:ResetSequence(seq)
	fig:EmitSound("npc/fast_zombie/gurgle_loop1.wav", 88, 70)

	local figIdx = fig:EntIndex()
	local lunging = false
	hook.Add("Think", "FearTraitorRites_" .. figIdx, function()
		if not IsValid(fig) or not IsValid(ply) or not ply:Alive() then
			hook.Remove("Think", "FearTraitorRites_" .. figIdx)
			if IsValid(fig) then fig:Remove() end
			if IsValid(ply) then ply:Freeze(false) end
			self.TraitorRitesActive = nil
			return
		end

		local toPly = ply:GetPos() - fig:GetPos()
		local dist = toPly:Length()

		if dist < 45 then
			fig:StopSound("npc/fast_zombie/gurgle_loop1.wav")
			ply:Freeze(false)
			hg.BreakNeck(ply)
			for _, v in player.Iterator() do
				v:ScreenFade(SCREENFADE.IN, Color(0, 0, 0), 1.2, 0.6)
			end
			hook.Remove("Think", "FearTraitorRites_" .. figIdx)
			timer.Simple(1.5, function()
				if IsValid(fig) then fig:Remove() end
			end)
			self.TraitorRitesActive = nil
			return
		end

		-- the slow walk... until close, then the lunge
		local speed = 130
		if dist < 140 then
			if not lunging then
				lunging = true
				fig:EmitSound("lurker_scream.wav", 95, 105)
			end
			speed = 1200
		end

		local step = toPly:GetNormalized() * math.min(speed * FrameTime(), dist)
		fig:SetPos(fig:GetPos() + step)
		fig:SetAngles(Angle(0, toPly:Angle().yaw, 0))

		local look = (fig:GetPos() + vector_up * 50 - ply:EyePos()):Angle()
		ply:SetEyeAngles(Angle(look.pitch, look.yaw, 0))
	end)
end

-- enraged scheduling: after the cultist dies, everything comes twice
-- as fast
function MODE:Sched(minT, maxT)
	local t = math.random(minT, maxT)
	if self.Enraged then t = t / 2 end

	-- crowd scaling: with many players, single-target scares dilute -
	-- speed the clocks up so each person's night stays busy
	local alive = #zb:CheckAlive()
	if alive > 10 then
		t = t / math.Clamp(alive / 10, 1, 2)
	end

	return CurTime() + t
end

-- the cultist's death unleashes it
hook.Add("PlayerDeath", "Fear_CultistWrath", function(victim)
	local MODE = zb and zb.modes and zb.modes["fear"]
	if not MODE then return end
	if not (zb.CROUND == "fear" or zb.CROUND == "fear_soe") then return end
	if not IsValid(victim) or not victim.isTraitor then return end
	if MODE.Enraged then return end

	MODE.Enraged = true

	net.Start("fear_wrath")
		net.WriteUInt(0, 2)
	net.Broadcast()

	for _, p in player.Iterator() do
		if p:Alive() then
			sound.Play("ambient/atmosphere/cave_hit1.wav", p:GetPos(), 130, 55)
		end
	end
	timer.Simple(0.45, function()
		for _, p in player.Iterator() do
			if p:Alive() then
				sound.Play("ambient/atmosphere/cave_hit4.wav", p:GetPos(), 125, 45)
			end
		end
	end)

	print("[Fear] The cultist is dead. It is enraged.")
end)

-- =====================================================================
-- The Fling: something grabs them and hurls them at the nearest wall,
-- hard. Homigrad's impact physics handle the rest.
-- =====================================================================
function MODE:FlingPlayer(ply)
	if not IsValid(ply) or not ply:Alive() then return false end

	local organism, round, saved = ply.organism, zb and zb.CROUND, self.saved

	-- find the nearest wall within reach
	local eye = ply:EyePos()
	local bestDir, bestDist = nil, 700
	for i = 0, 7 do
		local dir = Angle(0, i * 45, 0):Forward()
		local tr = util.TraceLine({
			start = eye,
			endpos = eye + dir * 700,
			filter = ply,
			mask = MASK_SOLID_BRUSHONLY,
		})
		if tr.Hit then
			local d = tr.HitPos:Distance(eye)
			if d < bestDist and d > 80 then
				bestDist = d
				bestDir = dir
			end
		end
	end
	if not bestDir then return false end

	-- the grab: it takes hold and they drop limp...
	ply:EmitSound("npc/stalker/go_alert2a.wav", 85, 80)
	ply:ViewPunch(Angle(-8, math.random(-6, 6), 0))
	if hg and hg.StunPlayer then
		pcall(function() hg.StunPlayer(ply) end)
	end

	-- ...then the limp body is hurled at the wall
	timer.Simple(0.35, function()
		if not IsValid(ply) or not ply:Alive() or ply.organism ~= organism
			or (zb and zb.CROUND) ~= round or self.saved ~= saved then return end
		local vel = bestDir * 950 + Vector(0, 0, 260)

		-- throw the ragdoll if homigrad gave us one, else the player
		local body = hg and hg.GetCurrentCharacter and hg.GetCurrentCharacter(ply)
		if IsValid(body) and body:GetClass() == "prop_ragdoll" then
			for i = 0, body:GetPhysicsObjectCount() - 1 do
				local phys = body:GetPhysicsObjectNum(i)
				if IsValid(phys) then
					phys:SetVelocity(vel)
				end
			end
		else
			ply:SetVelocity(vel)
		end
		ply:EmitSound("ambient/wind/wind_hit1.wav", 90, 70)
	end)
	return true
end

function MODE:SkipVictim(ply)
	if ply:GetNetVar("disappearance") then
		return true
	end

	-- the entity leaves the traitor alone - until they're the last one
	-- left, at which point the alliance ends
	if ply.isTraitor then
		local others = 0
		for _, p in ipairs(zb:CheckAlive()) do
			if p != ply then others = others + 1 end
		end
		if others > 0 then
			return true
		end
	end
end

function MODE:CheckInAGroup(ply)
	local players = zb:CheckAlive()
	local flag = false

	for i2, ply2 in ipairs(players) do
		if IsLookingAt(ply2, ply:EyePos(), 0.8) and hg.isVisible(ply:EyePos(), ply2:EyePos(), {ply, ply2}, MASK_VISIBLE) then
			flag = true
		end
	end

	return flag
end

util.AddNetworkString("check_lightness")
util.AddNetworkString("fear_jumpscare")
util.AddNetworkString("fear_marked")
util.AddNetworkString("fear_wrath")

local checkedPlayer
local checkPlayers = {}
local maxLen = math.sqrt(3)
net.Receive("check_lightness", function(len, ply)
	local vec = net.ReadVector()
	
	if vec:Length() > maxLen then return end
	if vec[1] < 0 or vec[2] < 0 or vec[3] < 0 then return end

	if checkedPlayer and !checkPlayers[ply] then
		checkPlayers[ply] = true
		
		checkedPlayer.lightcolor = checkedPlayer.lightcolor or Vector(0.5, 0.5, 0.5)
		checkedPlayer.lightcolor = LerpVector(0.5, checkedPlayer.lightcolor, vec)
	end
end)

function MODE:CheckInDarkness(ply)
	return ply.lightcolor and ply.lightcolor:Length() < 0.1
end

function MODE:SelectTheBestVictim()
	local alive = zb:CheckAlive()
	local victims = {}
	local victims_stats = {}

	for i, ply in ipairs(alive) do
		if self:SkipVictim(ply) then continue end
		
		local index = #victims_stats + 1

		victims_stats[index] = {}
		local tbl = victims_stats[index]
		tbl.ply = ply
		tbl.harmed = math.min(zb.HarmAttacked[ply] or 0, 40) / 40
		tbl.not_in_a_group = !self:CheckInAGroup(ply) and 1 or 0
		tbl.in_darkness = self:CheckInDarkness(ply) and 25 or 0
		tbl.has_a_gun = ishgweapon(ply:GetActiveWeapon()) and 1 or 0
		tbl.doesnt_move = (ply.avgvelocity or 0) < 200 and 1 or 0
		tbl.randomness = math.random(-3, 3)

		tbl.calculated_interest = tbl.harmed + tbl.not_in_a_group
			+ tbl.in_darkness + tbl.in_darkness + tbl.has_a_gun
			+ tbl.doesnt_move + tbl.randomness
	end
	
	self.saved.KillTime = CurTime() + math.random(15, 45) * math.max(#alive / 20, 0.5) * (self.Enraged and 0.5 or 1)

	if #alive == 1 then
		self.saved.KillTime = CurTime() + 5
	end

	local victim = table.Random(alive)
	local max_interest = -5
	for i, tbl in ipairs(victims_stats) do
		if max_interest < tbl.calculated_interest then
			max_interest = tbl.calculated_interest
			vicitm = tbl.ply
		end
		-- print(tbl.calculated_interest, tbl.ply)
	end

	return vicitm
end

function MODE:ReturnToRealmOfLiving(ply)
	local entindex = ply:EntIndex()

	local players = zb:CheckAlive()

	self:CreateTimer("ReturnToLife " .. entindex, 10, 0, function()
		if !IsValid(ply) or !ply:Alive() then
			timer.Remove("ReturnToLife " .. entindex)
		else
			for i2, ply2 in ipairs(players) do
				if IsLookingAt(ply2, ply:EyePos(), 0.8) and hg.isVisible(ply:EyePos(), ply2:EyePos(), {ply, ply2}, MASK_VISIBLE) then
					return
				else
					ply:SetNetVar("disappearance", false)
					timer.Remove("ReturnToLife " .. entindex)
				end
			end
		end
	end)
end

function MODE:Disappear(ply)
	-- defense in depth: no selection bug may ever vanish the cultist
	-- while others still live
	if ply.isTraitor and #zb:CheckAlive() > 1 then return end

	ply:SetCustomCollisionCheck(true)
	ply:CollisionRulesChanged()
	ply:SetNetVar("disappearance", true)

	if self.CurrentVictim == ply then
		self.CurrentVictim = nil
	end

	self:CreateTimer("disappearance " .. ply:EntIndex(), math.Rand(60, 120), 1, function()
		if IsValid(ply) and ply:Alive() then
			if #zb:CheckAlive() > 1 and (math.random(1, 3) == 1) then
				self:CreateTimer("Afterlife " .. ply:EntIndex(), 119, 1, function()
					if IsValid(ply) and ply:Alive() then
						ply:KillSilent()
						ply:ChatPrint("You were taken into the afterlife.")
					end
				end)

				ply:SetLocalVar("afterlife", CurTime())
			else
				self:ReturnToRealmOfLiving(ply)
			end
		end
	end)
end

local counted_players = {}
function MODE:PropKill(ply)
	local index = ply:EntIndex()

	if self.CurrentVictim == ply then
		self.CurrentVictim = nil
	end

	self:CreateTimer("Fear_PropKill " .. index, 5, math.random(30, 60), function()
		if !IsValid(ply) or !ply:Alive() then
			timer.Remove("Fear_PropKill " .. index)
			return
		end

		for _, v in ipairs(ents.FindInSphere(ply:GetPos(), 256)) do
			if v.GetPhysicsObject and IsValid(v:GetPhysicsObject()) and !self:IsDoor(v) then
				if math.random(1, 50) == 1 then
					local pos
					if !IsValid(ply.FakeRagdoll) then
						pos = ply:GetBoneMatrix(ply:LookupBone("ValveBiped.Bip01_Head1")):GetTranslation()
					elseif IsValid(ply.FakeRagdoll) then
						pos = ply.FakeRagdoll:GetBoneMatrix(ply.FakeRagdoll:LookupBone("ValveBiped.Bip01_Head1")):GetTranslation()
					end

					if !pos then return end

					local dir = (pos - v:GetPos()):GetNormalized()
					v:GetPhysicsObject():SetVelocity(dir * math.Rand(500, 2000))
					timer.Adjust("Fear_PropKill " .. index, math.Rand(1, 10))
					return
				end
			end
		end
	end)
end

-- Fear event tuning 1.1.1. Only called by the existing main attack clock.
-- This roll is conditional on the attack not taking the forced-gun branch.
function MODE:RollAttackFate(watched)
    local roll = math.random(100)
    if watched then
        if roll <= 40 then return "snatch" end
        if roll <= 55 then return "disappear" end
    elseif roll <= 15 then
        return "disappear"
    end
    return "other"
end

local function FearCanStrike(ply)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then
        return false, "Target must be a living player."
    end
    if ply.isTraitor then return false, "Target is a traitor and is protected from this Fear attack." end
    if ply:GetNetVar("disappearance", false) then return false, "Target is currently disappeared." end
    return true
end

function MODE:TorsoTake(ply)
    if not FearCanStrike(ply) or type(ply.organism) ~= "table" then return false end
    if ply.organism.torsoamputated or ply:GetNWBool("ZCityTorsoSevered", false)
        or ply.__zcGoreTorsoPending then return false end
    if not hg or type(hg.ZCityGore_AmputateTorso) ~= "function" then return false end
    -- Same native operation as Amputate torso in the context menu. Do not use
    -- the friendly crawler wrapper: it heals/restores trauma after the split.
    local ok, applied = pcall(hg.ZCityGore_AmputateTorso, ply, VectorRand(-250, 250), false)
    if not ok then
        ErrorNoHalt("[Fear] TorsoTake failed: " .. tostring(applied) .. "\n")
        return false
    end
    return applied == true
end

function MODE:PropStrike(ply)
    local allowed, reason = FearCanStrike(ply)
    if not allowed then return false, reason end
    local body = IsValid(ply.FakeRagdoll) and ply.FakeRagdoll or ply
    local target = body:WorldSpaceCenter()
    local eligible = {}
    local counts = {props = 0, held = 0, attached = 0, physics = 0,
        frozen = 0, limits = 0, distance = 0, blocked = 0}
    for _, ent in ipairs(ents.FindInSphere(target, 1200)) do
        if IsValid(ent) and ent:GetClass() == "prop_physics" then
            counts.props = counts.props + 1
            local rejection
            if ent.isheld or ent:IsPlayerHolding() then
                rejection = "held"
            elseif IsValid(ent:GetParent()) or constraint.HasConstraints(ent) then
                rejection = "attached"
            elseif ent:GetCollisionGroup() ~= COLLISION_GROUP_NONE or ent:GetPhysicsObjectCount() ~= 1 then
                rejection = "physics"
            else
                local phys = ent:GetPhysicsObject()
                local model = string.lower(ent:GetModel() or "")
                if not IsValid(phys) or not phys:IsCollisionEnabled() then
                    rejection = "physics"
                elseif not phys:IsMotionEnabled() then
                    rejection = "frozen"
                elseif phys:GetMass() < 10 or phys:GetMass() > 120 or ent:BoundingRadius() > 80
                    or string.find(model, "explosive", 1, true) then
                    rejection = "limits"
                else
                    local origin = ent:WorldSpaceCenter()
                    local delta = target - origin
                    local distance = delta:Length()
                    if distance < 160 or distance > 1200 then
                        rejection = "distance"
                    else
                        -- This is a line-of-sight check, not a swept cube built
                        -- from BoundingRadius (that cube intersects the floor
                        -- for ordinary resting props). Native physics still
                        -- handles the prop's actual collision shape afterward.
                        local trace = util.TraceLine({start = origin, endpos = target,
                            filter = {ent, ply, body}, mask = MASK_SOLID})
                        if trace.Hit or trace.StartSolid or trace.AllSolid then
                            rejection = "blocked"
                        else
                            eligible[#eligible + 1] = {physics = phys, direction = delta:GetNormalized()}
                            if #eligible >= 24 then break end
                        end
                    end
                end
            end
            if rejection then counts[rejection] = counts[rejection] + 1 end
        end
    end
    if #eligible == 0 then
        return false, string.format("No usable prop: %d nearby; %d frozen, %d held, %d attached, %d physics/collision, %d size/mass/model, %d distance, %d blocked sightlines.",
            counts.props, counts.frozen, counts.held, counts.attached, counts.physics,
            counts.limits, counts.distance, counts.blocked)
    end
    local chosen = eligible[math.random(#eligible)]
    chosen.physics:Wake()
    chosen.physics:SetVelocity(chosen.direction * 2200)
    return true
end
-- End Fear event tuning.

function MODE:RoundThink()
	self.BaseClass.RoundThink(self)

	-- night from round start - gWeather night, skipped on maps already
	-- set at night
	if not self.NightApplied and zb.ROUND_START then
		self.NightApplied = true
		local night = ents.Create("gw_t1_night")
		if IsValid(night) then
			night:SetPos(vector_origin)
			night:Spawn()
			self.NightEnt = night
		end

		-- the whispers begin a little into the round
		self.NextWhisper = CurTime() + math.random(45, 90)
		self.NextAmbient = CurTime() + math.random(15, 30)
		self.NextSighting = CurTime() + math.random(20, 40)
		self.NextBlackGuy = CurTime() + math.random(40, 70)
		self.NextCharple = CurTime() + math.random(60, 110)
		self.NextDoors = CurTime() + math.random(120, 240)
		self.NextLightTheft = CurTime() + math.random(90, 180)
		self.NextFling = CurTime() + math.random(120, 200)
		self.NextBodySwap = self:Sched(150, 210)
		self.NextDoorLock = CurTime() + math.random(120, 240)
		self.NextLightCheck = CurTime() + 10

		-- everyone carries a flashlight in the dark
		for _, ply in player.Iterator() do
			if ply:Alive() and ply:Team() != TEAM_SPECTATOR then
				local inv = ply:GetNetVar("Inventory") or {}
				inv["Weapons"] = inv["Weapons"] or {}
				inv["Weapons"]["hg_flashlight"] = true
				ply:SetNetVar("Inventory", inv)
			end
		end

		-- the pact's terms: the summoner carries exactly three things -
		-- the cultist's blade, the disguise, and the idol. Nothing else.
		for _, ply in player.Iterator() do
			if ply:Alive() and ply.isTraitor then
				local hasCultist = weapons.GetStored("weapon_eft_melee_cultist") ~= nil

				local KEEP = {
					["weapon_hands_sh"] = true,
					["weapon_traitor_suit"] = true,
					["weapon_fear_pact"] = true,
					["weapon_eft_melee_cultist"] = true,
				}
				-- no cultist blade on this server: keep their own knife
				if not hasCultist then
					KEEP["weapon_buck200knife"] = true
					KEEP["weapon_sogknife"] = true
				end

				for _, wep in ipairs(ply:GetWeapons()) do
					if not KEEP[wep:GetClass()] then
						ply:StripWeapon(wep:GetClass())
					end
				end

				if hasCultist and not ply:HasWeapon("weapon_eft_melee_cultist") then
					ply:Give("weapon_eft_melee_cultist")
				end
				if not ply:HasWeapon("weapon_traitor_suit") then
					ply:Give("weapon_traitor_suit")
				end
				if weapons.GetStored("weapon_fear_pact") and not ply:HasWeapon("weapon_fear_pact") then
					ply:Give("weapon_fear_pact")
				end
				ply:SetNWInt("PactFavors", 3)

				-- the cultist gets a light like everyone else
				local tinv = ply:GetNetVar("Inventory") or {}
				tinv["Weapons"] = tinv["Weapons"] or {}
				tinv["Weapons"]["hg_flashlight"] = true
				ply:SetNetVar("Inventory", tinv)
			end
		end
	end
	local players = zb:CheckAlive()

	self.saved.TimePlayed = (self.saved.TimePlayed or 0) + 0.5
	
	self.NextLightCheck = self.NextLightCheck or self.saved.TimePlayed + 5

	if self.saved.TimePlayed > self.NextLightCheck then
		self.NextLightCheck = self.saved.TimePlayed + 5
		
		if table.Count(counted_players) >= #players then
			counted_players = {}
		end
		
		for i, ply in ipairs(players) do
			if ply.lightcolor and counted_players[ply] then continue end
			counted_players[ply] = true
			checkedPlayer = ply
			ply.lastcheckedcolor = MODE.saved.TimePlayed

			net.Start("check_lightness")
			net.WriteEntity(ply)
			net.Broadcast()
	
			timer.Simple(0.5, function()
				checkedPlayer = nil
				checkPlayers = {}
			end)

			break
		end
	end

	-- the black guy on his own clock: independent of the kill cycle,
	-- he visits someone roughly once a minute - look at him and die
	if self.NextBlackGuy and CurTime() > self.NextBlackGuy and not self.LastAloneSent then
		self.NextBlackGuy = self:Sched(45, 75)

		local pool = {}
		for _, p in player.Iterator() do
			if p:Alive() and p:Team() != TEAM_SPECTATOR and not p.isTraitor
				and not p:GetNetVar("disappearance")
				and not (MODE.StartedEvents[p:UserID()] and MODE.StartedEvents[p:UserID()].IsActive
					and MODE.StartedEvents[p:UserID()]:IsActive(p)) then
				pool[#pool + 1] = p
			end
		end
		if #pool > 0 then
			self:StartEvent("scary_black_guy", pool[math.random(#pool)])
		end
	end

	-- light anger: too many beams in one place for too long draws its
	-- gaze - the huddle gets a warning, then a surge
	if self.NextLightCheck and CurTime() > self.NextLightCheck then
		self.NextLightCheck = CurTime() + 10

		if CurTime() > (self.LightAngerCooldown or 0) then
			local lit = {}
			for _, p in player.Iterator() do
				if p:Alive() and p:Team() != TEAM_SPECTATOR and not p.isTraitor and p:GetNetVar("flashlight") then
					lit[#lit + 1] = p
				end
			end

			-- find the densest lit cluster
			local anchor, best = nil, 0
			for _, p in ipairs(lit) do
				local n = 0
				for _, p2 in ipairs(lit) do
					if p2 != p and p2:GetPos():DistToSqr(p:GetPos()) < 500 * 500 then n = n + 1 end
				end
				if n > best then best = n anchor = p end
			end

			if best >= 3 then -- 4+ beams together
				self.LightAttn = (self.LightAttn or 0) + 1
			else
				self.LightAttn = math.max((self.LightAttn or 0) - 1, 0)
			end

			if self.LightAttn >= 3 and IsValid(anchor) then
				self.LightAttn = 0
				self.LightAngerCooldown = CurTime() + 90

				local cluster = { anchor }
				for _, p2 in ipairs(lit) do
					if p2 != anchor and not p2.isTraitor and p2:GetPos():DistToSqr(anchor:GetPos()) < 500 * 500 then
						cluster[#cluster + 1] = p2
					end
				end

				for _, p in ipairs(cluster) do
					if p.Notify then p:Notify("The light has drawn its gaze.", 0) end
				end

				-- the surge: black guy on one of them, and the runner
				-- at another moments later
				local t1 = cluster[math.random(#cluster)]
				pcall(function() self:StartEvent("scary_black_guy", t1) end)
				if #cluster > 1 then
					timer.Simple(math.Rand(3, 7), function()
						if zb.CROUND != "fear" and zb.CROUND != "fear_soe" then return end
						local t2
						for _, p in ipairs(cluster) do
							if p != t1 and IsValid(p) and p:Alive() then t2 = p break end
						end
						if t2 then self.NextCharple = 0 end
					end)
				end
			end
		end
	end

	-- locked in: a room's doors seal with someone inside for 20 seconds
	if self.NextDoorLock and CurTime() > self.NextDoorLock then
		self.NextDoorLock = self:Sched(150, 270)

		local pool = {}
		for _, p in player.Iterator() do
			if p:Alive() and p:Team() != TEAM_SPECTATOR and not p.isTraitor then pool[#pool + 1] = p end
		end

		if #pool > 0 then
			local victim = pool[math.random(#pool)]
			local doors = {}
			for _, ent in ipairs(ents.FindInSphere(victim:GetPos(), 350)) do
				if hgIsDoor(ent) then doors[#doors + 1] = ent end
			end

			if #doors > 0 then
				for _, d in ipairs(doors) do
					d:Fire("Lock")
				end
				if victim.Notify then
					victim:Notify("The doors will not open for you.", 0)
				end
				timer.Simple(math.Rand(6, 14), function()
					if IsValid(victim) and victim:Alive() and victim.Notify then
						victim:Notify("It knows you cannot leave.", 0)
					end
				end)
				timer.Simple(20, function()
					for _, d in ipairs(doors) do
						if IsValid(d) then d:Fire("Unlock") end
					end
				end)
			end
		end
	end

	-- the exchange: two living people collapse - and wake up in each
	-- other's bodies. Faces, clothes, and pockets all traded.
	if self.NextBodySwap and CurTime() > self.NextBodySwap then
		self.NextBodySwap = CurTime() + math.random(150, 210)

		local pool = {}
		for _, p in player.Iterator() do
			if p:Alive() and p:Team() != TEAM_SPECTATOR and not p.isTraitor
				and not p:GetNetVar("disappearance") then
				pool[#pool + 1] = p
			end
		end

		if #pool >= 2 and hg.RespawnIntoBody then
			local a = table.remove(pool, math.random(#pool))
			local b = table.remove(pool, math.random(#pool))

			hg.StunPlayer(a)
			hg.StunPlayer(b)

			timer.Simple(0.6, function()
				if not IsValid(a) or not IsValid(b) or not a:Alive() or not b:Alive() then return end

				local ragA = hg.GetCurrentCharacter(a)
				local ragB = hg.GetCurrentCharacter(b)
				if not IsValid(ragA) or ragA == a or not IsValid(ragB) or ragB == b then return end

				local ok = pcall(function()
					hg.RespawnIntoBody(a, ragB)
					hg.RespawnIntoBody(b, ragA)
				end)

				if ok then
					self.SwapHappened = true
					print("[Fear] Body swap: " .. a:Nick() .. " <-> " .. b:Nick())
					timer.Simple(1.5, function()
						if IsValid(a) and a.Notify then a:Notify("These hands are not yours.", 0) end
						if IsValid(b) and b.Notify then b:Notify("Whose face is this?", 0) end
					end)
				end
			end)
		end
	end

	-- the fling: something picks a person up and throws them
	if self.NextFling and CurTime() > self.NextFling and not self.LastAloneSent then
		self.NextFling = self:Sched(180, 300)

		local pool = {}
		for _, p in player.Iterator() do
			if p:Alive() and p:Team() != TEAM_SPECTATOR and not p.isTraitor then
				pool[#pool + 1] = p
			end
		end
		if #pool > 0 then
			self:FlingPlayer(pool[math.random(#pool)])
		end
	end

	-- stolen light: someone's flashlight dies for a while. Paired with
	-- the whisper - "The lights won't stay on for you." becomes literal.
	if self.NextLightTheft and CurTime() > self.NextLightTheft then
		self.NextLightTheft = self:Sched(120, 220)

		local pool = {}
		for _, p in player.Iterator() do
			if p:Alive() and p:Team() != TEAM_SPECTATOR and not p.isTraitor then
				local inv = p:GetNetVar("Inventory")
				if inv and inv["Weapons"] and inv["Weapons"]["hg_flashlight"] then
					pool[#pool + 1] = p
				end
			end
		end

		if #pool > 0 then
			local victim = pool[math.random(#pool)]

			local inv = victim:GetNetVar("Inventory")
			inv["Weapons"]["hg_flashlight"] = nil
			victim:SetNetVar("Inventory", inv)
			victim:Flashlight(false)

			if victim.Notify then
				victim:Notify("The lights won't stay on for you.", 0)
			end

			timer.Simple(30, function()
				if IsValid(victim) and victim:Alive() then
					local inv2 = victim:GetNetVar("Inventory")
					if inv2 and inv2["Weapons"] then
						inv2["Weapons"]["hg_flashlight"] = true
						victim:SetNetVar("Inventory", inv2)
					end
				end
			end)
		end
	end

	-- every door on the map moves at once
	if self.NextDoors and CurTime() > self.NextDoors then
		self.NextDoors = self:Sched(150, 300)

		local activator = zb:CheckAlive()[1]
		if IsValid(activator) then
			for _, ent in ents.Iterator() do
				if hgIsDoor(ent) and not ent:GetNoDraw() then
					ent:Use(activator)
				end
			end
		end
	end

	-- the charple: something burnt sprints straight at someone at
	-- inhuman speed, forcing them to watch, and vanishes at their face
	if self.NextCharple and CurTime() > self.NextCharple then
		self.NextCharple = self:Sched(75, 135)

		local pool = {}
		for _, p in player.Iterator() do
			if p:Alive() and p:Team() != TEAM_SPECTATOR and not p.isTraitor then pool[#pool + 1] = p end
		end

		-- try up to 5 different people until one has an open lane
		for attempt = 1, math.min(5, #pool) do
			local target = table.remove(pool, math.random(#pool))

			-- find an open lane: try several directions for clear space
			local spawnPos, spawnYaw
			for i = 1, 8 do
				local yaw = math.random(0, 359)
				local dir = Angle(0, yaw, 0):Forward()
				local tr = util.TraceHull({
					start = target:EyePos(),
					endpos = target:EyePos() + dir * 800,
					filter = target,
					maxs = Vector(20, 20, 40),
					mins = Vector(-20, -20, 0),
				})
				if tr.HitPos:Distance(target:EyePos()) >= 500 then
					local floor = util.TraceLine({
						start = tr.HitPos - dir * 60,
						endpos = (tr.HitPos - dir * 60) - vector_up * 500,
					})
					if floor.Hit then
						spawnPos = floor.HitPos
						spawnYaw = yaw
						break
					end
				end
			end

			if spawnPos then
				local fig = ents.Create("ent_zc_anim")
				if IsValid(fig) then
					fig:SetPos(spawnPos)
					fig:SetModel("models/humans/charple01.mdl")
					fig:SetAngles(Angle(0, spawnYaw + 180, 0)) -- facing the target
					fig:Spawn()

					local runSeq = fig:LookupSequence("run_all")
					if runSeq < 0 then runSeq = fig:LookupSequence("run_all_panicked") end
					if runSeq < 0 then runSeq = 126 end
					fig:ResetSequence(runSeq)

					fig:EmitSound("npc/fast_zombie/gurgle_loop1.wav", 85, 110)

					-- force the target's view onto it
					target:SetEyeAngles(Angle(5, spawnYaw, 0))

					local figIdx = fig:EntIndex()
					local SPEED = 1500
					hook.Add("Think", "FearCharple_" .. figIdx, function()
						if not IsValid(fig) or not IsValid(target) or not target:Alive() then
							hook.Remove("Think", "FearCharple_" .. figIdx)
							if IsValid(fig) then fig:Remove() end
							return
						end

						local toTarget = target:GetPos() - fig:GetPos()
						local dist = toTarget:Length()

						if dist < 30 then
							-- vanishes at their face
							fig:StopSound("npc/fast_zombie/gurgle_loop1.wav")
							target:EmitSound("ambient/wind/wind_hit1.wav", 90, 95)
							hook.Remove("Think", "FearCharple_" .. figIdx)
							fig:Remove()
							return
						end

						local step = toTarget:GetNormalized() * math.min(SPEED * FrameTime(), dist)
						fig:SetPos(fig:GetPos() + step)
						fig:SetAngles(Angle(0, toTarget:Angle().yaw, 0))

						-- hold their gaze on it while it comes
						local look = (fig:GetPos() + vector_up * 50 - target:EyePos()):Angle()
						target:SetEyeAngles(Angle(look.pitch, look.yaw, 0))
					end)

					break -- someone got charpled; done this cycle
				end
			end
		end
	end

	-- sightings: brief harmless apparitions every ~30s. A black figure
	-- watching from a distance, or darting across the edge of vision.
	-- Sometimes only one person can see it - sometimes everyone can.
	if self.NextSighting and CurTime() > self.NextSighting then
		self.NextSighting = self:Sched(30, 30)

		local pool = {}
		for _, p in player.Iterator() do
			if p:Alive() and p:Team() != TEAM_SPECTATOR and not p.isTraitor then pool[#pool + 1] = p end
		end

		if #pool > 0 then
			local target = pool[math.random(#pool)]
			local eyeAng = target:EyeAngles()
			eyeAng.pitch = 0

			-- the Count: near a group, sometimes the figure stands among
			-- them in plain sight - and someone is told to count
			local nearby = 0
			for _, p2 in ipairs(pool) do
				if p2 != target and p2:GetPos():DistToSqr(target:GetPos()) < 600 * 600 then
					nearby = nearby + 1
				end
			end
			local isCount = nearby >= 2 and math.random(100) <= 15

			-- pick a spot: ahead (watcher) or off to the side (dart)
			local isDart = not isCount and math.random(2) == 1
			local yawOff = isDart and (math.random(2) == 1 and 70 or -70) or math.random(-25, 25)
			local dir = Angle(0, eyeAng.yaw + yawOff, 0):Forward()
			local dist = isDart and math.random(250, 450) or math.random(500, 900)

			local tr = util.TraceHull({
				start = target:EyePos(),
				endpos = target:EyePos() + dir * dist,
				filter = target,
				maxs = Vector(16, 16, 16),
				mins = -Vector(16, 16, 16),
			})
			local floor = util.TraceLine({
				start = tr.HitPos - dir * 40,
				endpos = (tr.HitPos - dir * 40) - vector_up * 400,
			})

			if floor.Hit and floor.HitPos:Distance(target:GetPos()) > 150 then
				local fig = ents.Create("ent_zc_anim")
				if IsValid(fig) then
					fig:SetPos(floor.HitPos)
					fig:SetModel("models/Humans/Group01/male_06.mdl")
					fig:SetMaterial("models/debug/debugwhite")
					fig:SetColor(color_black)
					fig:SetAngles(Angle(0, (target:GetPos() - floor.HitPos):Angle().yaw, 0))
					fig:Spawn()
					fig:ResetSequence(126)

					-- half the sightings are personal; half anyone can see.
					-- the Count is ALWAYS visible to everyone - that's the point
					if not isCount and math.random(2) == 1 then
						fig:SetWhiteListToSee(true)
						fig:SetNetVar("CanSeeUserID", { [target:UserID()] = true })
					end

					if isCount and target.Notify then
						target:Notify("Count the people again.", 0)
					end

					if isDart then
						-- slide across their periphery, then gone
						local startPos = floor.HitPos
						local slideDir = Angle(0, eyeAng.yaw + (yawOff > 0 and -90 or 90), 0):Forward()
						local t0 = CurTime()
						local figIdx = fig:EntIndex()
						hook.Add("Think", "FearDart_" .. figIdx, function()
							if not IsValid(fig) then hook.Remove("Think", "FearDart_" .. figIdx) return end
							local frac = (CurTime() - t0) / 0.8
							if frac >= 1 then
								hook.Remove("Think", "FearDart_" .. figIdx)
								fig:Remove()
								return
							end
							fig:SetPos(startPos + slideDir * frac * 260)
						end)
					else
						-- the watcher: stands still, then is simply gone.
						-- Count figures linger longer - they want to be seen
						timer.Simple(isCount and math.Rand(5, 8) or math.Rand(2, 4), function()
							if IsValid(fig) then fig:Remove() end
						end)
					end
				end
			end
		end
	end

	-- ambient dread: positional sounds near random people - footsteps
	-- where nobody is, breathing behind you, distant moans. Mostly
	-- subtle, occasionally a distant scream or a deep boom for everyone.
	if self.NextAmbient and CurTime() > self.NextAmbient then
		self.NextAmbient = self:Sched(30, 30)

		local subtle = {
			"ambient/creatures/town_scared_breathing1.wav",
			"ambient/creatures/town_scared_breathing2.wav",
			"ambient/creatures/town_muffled_cry1.wav",
			"ambient/creatures/town_moan1.wav",
			"ambient/levels/citadel/strange_talk1.wav",
			"ambient/levels/citadel/strange_talk3.wav",
			"ambient/levels/citadel/strange_talk8.wav",
			"ambient/materials/door_hit1.wav",
			"ambient/wind/wind_hit1.wav",
			"physics/wood/wood_box_footstep1.wav",
			"physics/wood/wood_box_footstep3.wav",
		}
		local rare = {
			"ambient/voices/f_scream1.wav",
			"ambient/creatures/town_zombie_call1.wav",
		}
		local boom = "ambient/atmosphere/cave_hit" .. math.random(1, 6) .. ".wav"

		-- rare jumpscare: one person's screen becomes a face
		if math.random(100) <= 10 then
			local jsPool = {}
			for _, p in player.Iterator() do
				if p:Alive() and p:Team() != TEAM_SPECTATOR and not p.isTraitor then jsPool[#jsPool + 1] = p end
			end
			if #jsPool > 0 then
				local victim = jsPool[math.random(#jsPool)]
				net.Start("fear_jumpscare")
					net.WriteUInt(math.random(2), 2)
				net.Send(victim)
				-- physical jolt to sell it
				victim:ViewPunch(Angle(math.Rand(-8, -14), math.Rand(-6, 6), math.Rand(-4, 4)))
			end
		end

		-- small chance: an explosive barrel somewhere just... goes off
		-- (holstered during the last-innocent toying - nothing lethal
		-- before the circle)
		if math.random(100) <= 7 and not self.LastAloneSent then
			local barrels = {}
			for _, ent in ipairs(ents.FindByClass("prop_physics")) do
				local mdl = string.lower(ent:GetModel() or "")
				if mdl:find("oildrum001_explosive") or mdl:find("explosive") then
					barrels[#barrels + 1] = ent
				end
			end
			if #barrels > 0 then
				local barrel = barrels[math.random(#barrels)]
				local dmg = DamageInfo()
				dmg:SetDamage(50)
				dmg:SetDamageType(DMG_BURN)
				dmg:SetAttacker(game.GetWorld())
				dmg:SetInflictor(game.GetWorld())
				barrel:TakeDamageInfo(dmg)
			end
		end

		local roll = math.random(100)
		if roll <= 8 then
			-- global deep boom, everyone feels it
			for _, p in player.Iterator() do
				if p:Alive() then p:EmitSound(boom, 60, math.random(85, 95)) end
			end

			-- and rarely, riding the boom: EVERYONE sees it. At once.
			-- The whole lobby screaming simultaneously, once a night.
			if math.random(100) <= 20 then
				net.Start("fear_jumpscare")
					net.WriteUInt(math.random(2), 2)
				net.Broadcast()
			end
		else
			-- positional sound near one random living person
			local pool = {}
			for _, p in player.Iterator() do
				if p:Alive() and p:Team() != TEAM_SPECTATOR and not p.isTraitor then pool[#pool + 1] = p end
			end
			if #pool > 0 then
				-- anchor on anyone alive - loners and groups alike; whoever
				-- is near the anchor hears it too
				local anchor = pool[math.random(#pool)]

				local ang = math.Rand(0, math.pi * 2)
				local dist = math.random(150, 400)
				local pos = anchor:GetPos() + Vector(math.cos(ang) * dist, math.sin(ang) * dist, math.random(0, 40))

				local snd = (roll <= 16) and rare[math.random(#rare)] or subtle[math.random(#subtle)]
				sound.Play(snd, pos, 85, math.random(90, 105))
			end
		end
	end

	-- the pact ends when there is no one left to hunt but its maker
	if not self.PactBroken then
		local alive = zb:CheckAlive()
		if #alive == 1 and IsValid(alive[1]) and alive[1].isTraitor then
			self.PactBroken = true
			local t = alive[1]
			net.Start("fear_wrath")
				net.WriteUInt(1, 2)
			net.Broadcast()
			sound.Play("ambient/atmosphere/cave_hit3.wav", t:GetPos(), 120, 50)
		end
	end

	-- while the last innocent waits for the circle: the dark does not
	-- pause. Non-lethal clocks are pinned to constant fire; anything
	-- that could kill early stays holstered (the kill cycle itself is
	-- gated behind KillTime, so the Surround stays the only death).
	if self.LastAloneSent then
		for _, clock in ipairs({ "NextWhisper", "NextSighting", "NextCharple", "NextDoors", "NextAmbient", "NextLightTheft", "NextDoorLock" }) do
			if self[clock] and self[clock] > CurTime() + 2.5 then
				self[clock] = CurTime() + math.Rand(0.5, 2.5)
			end
		end
	end

	-- and when the last one standing is innocent, they are told what
	-- that means too
	if not self.LastAloneSent then
		local alive = zb:CheckAlive()
		if #alive == 1 and IsValid(alive[1]) and not alive[1].isTraitor then
			self.LastAloneSent = true
			net.Start("fear_wrath")
				net.WriteUInt(2, 2)
			net.Broadcast()
			sound.Play("ambient/atmosphere/cave_hit3.wav", alive[1]:GetPos(), 120, 50)
		end
	end

	-- the pact's patience: the cultist earns a favor every 30 seconds
	-- (faster when enraged), capped at 6
	if not self.NextFavor then
		self.NextFavor = self:Sched(30, 30)
	end
	if CurTime() > self.NextFavor then
		self.NextFavor = self:Sched(30, 30)
		for _, tp in player.Iterator() do
			if tp.isTraitor and tp:Alive() then
				local f = tp:GetNWInt("PactFavors", 0)
				if f < 6 then tp:SetNWInt("PactFavors", f + 1) end
			end
		end
	end
	for _, tp in player.Iterator() do
		if tp.isTraitor and tp:Alive() then
			tp:SetNWFloat("PactNextFavor", self.NextFavor)
			tp:SetNWFloat("PactFavorInt", self.Enraged and 15 or 30)
		end
	end

	-- the whispers: one person at a time, every 30s - and they are
	-- never wrong. Context lines only fire when true; compliance tests
	-- (20% of whispers) are followed by the thing they warn about.
	if self.NextWhisper and CurTime() > self.NextWhisper then
		self.NextWhisper = self:Sched(30, 30)

		-- pick the target first; the truth depends on who's listening
		local target
		if IsValid(self.CurrentVictim) and self.CurrentVictim:Alive() and math.random(2) == 1 then
			target = self.CurrentVictim
		else
			local pool = {}
			for _, p in player.Iterator() do
				if p:Alive() and p:Team() != TEAM_SPECTATOR and not p.isTraitor then pool[#pool + 1] = p end
			end
			if #pool > 0 then target = pool[math.random(#pool)] end
		end

		if IsValid(target) and target.Notify then
			-- compliance tests: the whisper is a rule, breaking it has
			-- consequences
			if math.random(100) <= 20 then
				local test = math.random(3)

				if test == 1 then
					-- DON'T TURN AROUND: a figure stands behind them.
					-- Hold your nerve for 5 seconds and it leaves unseen.
					target:Notify("Don't turn around.", 0)

					local back = -target:EyeAngles():Forward()
					back.z = 0
					back:Normalize()
					local floor = util.TraceLine({
						start = target:GetPos() + back * 140 + vector_up * 40,
						endpos = target:GetPos() + back * 140 - vector_up * 200,
					})
					if floor.Hit then
						local fig = ents.Create("ent_zc_anim")
						if IsValid(fig) then
							fig:SetPos(floor.HitPos)
							fig:SetModel("models/Humans/Group01/male_06.mdl")
							fig:SetMaterial("models/debug/debugwhite")
							fig:SetColor(color_black)
							fig:SetAngles(Angle(0, (target:GetPos() - floor.HitPos):Angle().yaw, 0))
							fig:Spawn()
							fig:ResetSequence(126)
							fig:SetWhiteListToSee(true)
							fig:SetNetVar("CanSeeUserID", { [target:UserID()] = true })

							local figPos = floor.HitPos + vector_up * 50
							local deadline = CurTime() + 5
							local idx = fig:EntIndex()
							timer.Create("FearNoTurn_" .. idx, 0.1, 0, function()
								if not IsValid(fig) or not IsValid(target) or not target:Alive() then
									timer.Remove("FearNoTurn_" .. idx)
									if IsValid(fig) then fig:Remove() end
									return
								end
								if IsLookingAt(target, figPos, 0.6) then
									-- they turned. It was there.
									target:EmitSound("npc/stalker/go_alert2a.wav", 80, 95)
									target:ViewPunch(Angle(-6, 2, 0))
									timer.Remove("FearNoTurn_" .. idx)
									fig:Remove()
								elseif CurTime() > deadline then
									-- nerve held. It leaves, unseen.
									timer.Remove("FearNoTurn_" .. idx)
									fig:Remove()
								end
							end)
						end
					end

				elseif test == 2 then
					-- RUN, AND IT WILL NOTICE: sprint within 8s -> a dart
					-- at their flank
					target:Notify("Run, and it will notice you.", 0)
					local until_t = CurTime() + 8
					local tid = "FearRunTest_" .. target:EntIndex()
					timer.Create(tid, 0.2, 0, function()
						if not IsValid(target) or not target:Alive() or CurTime() > until_t then
							timer.Remove(tid)
							return
						end
						if target:GetVelocity():Length2D() > 230 then
							timer.Remove(tid)
							-- noticed: a shape cuts across their side
							local side = math.random(2) == 1 and 80 or -80
							local dir = Angle(0, target:EyeAngles().yaw + side, 0):Forward()
							local floor = util.TraceLine({
								start = target:GetPos() + dir * 300 + vector_up * 40,
								endpos = target:GetPos() + dir * 300 - vector_up * 300,
							})
							if floor.Hit then
								local fig = ents.Create("ent_zc_anim")
								if IsValid(fig) then
									fig:SetPos(floor.HitPos)
									fig:SetModel("models/Humans/Group01/male_06.mdl")
									fig:SetMaterial("models/debug/debugwhite")
									fig:SetColor(color_black)
									fig:Spawn()
									fig:ResetSequence(126)
									fig:SetWhiteListToSee(true)
									fig:SetNetVar("CanSeeUserID", { [target:UserID()] = true })
									local slideDir = Angle(0, target:EyeAngles().yaw + (side > 0 and -170 or 170), 0):Forward()
									local sp = floor.HitPos
									local t0 = CurTime()
									local idx = fig:EntIndex()
									hook.Add("Think", "FearRunDart_" .. idx, function()
										if not IsValid(fig) then hook.Remove("Think", "FearRunDart_" .. idx) return end
										local frac = (CurTime() - t0) / 0.7
										if frac >= 1 then
											hook.Remove("Think", "FearRunDart_" .. idx)
											fig:Remove()
											return
										end
										fig:SetPos(sp + slideDir * frac * 300)
									end)
								end
							end
						end
					end)

				else
					-- DO NOT ANSWER IF IT CALLS: soon after, something
					-- calls out nearby. Go toward it and meet it.
					target:Notify("Do not answer if it calls you.", 0)
					timer.Simple(math.Rand(8, 16), function()
						if not IsValid(target) or not target:Alive() then return end
						local ang = math.Rand(0, math.pi * 2)
						local lurePos = target:GetPos() + Vector(math.cos(ang) * 550, math.sin(ang) * 550, 20)
						sound.Play("vo/npc/male01/help01.wav", lurePos, 80, 95)

						local until_t = CurTime() + 25
						local tid = "FearLure_" .. target:EntIndex()
						timer.Create(tid, 1, 0, function()
							if not IsValid(target) or not target:Alive() or CurTime() > until_t then
								timer.Remove(tid)
								return
							end
							if target:GetPos():DistToSqr(lurePos) < 220 * 220 then
								timer.Remove(tid)
								-- they answered
								local fig = ents.Create("ent_zc_anim")
								if IsValid(fig) then
									fig:SetPos(lurePos - Vector(0, 0, 20))
									fig:SetModel("models/humans/charple01.mdl")
									fig:SetAngles(Angle(0, (target:GetPos() - lurePos):Angle().yaw, 0))
									fig:Spawn()
									fig:ResetSequence(126)
									target:EmitSound("ambient/wind/wind_hit1.wav", 90, 90)
									timer.Simple(0.7, function()
										if IsValid(fig) then fig:Remove() end
									end)
								end
							end
						end)
					end)
				end
			else
				-- oracle whispers: context lines only when TRUE
				local lines = {
					"It knows where you are.",
					"You are being watched.",
					"It remembers you.",
					"The dark is closer than it looks.",
					"You heard that too, didn't you?",
					"Stay in the light.",
					"Do not look for it.",
					"Something followed you here.",
					"That wasn't a door.",
					"It is standing very still.",
					"The flashlight only helps you find it.",
					"One of them has the words.",
					"It has been listening this whole time.",
					"You walked past it twice already.",
					"The others cannot hear you scream.",
					"It learned your name tonight.",
					"You were not supposed to see that.",
				}

				-- truth-gated additions
				if target == self.CurrentVictim then
					lines[#lines + 1] = "You've been marked."
					lines[#lines + 1] = "You've been marked."
				end

				if self.SwapHappened then
					lines[#lines + 1] = "It's wearing someone's face."
				end

				local nearestCorpse
				for _, rag in ipairs(ents.FindByClass("prop_ragdoll")) do
					local owner = rag.ply
					if owner != nil and (not IsValid(owner) or not owner:Alive())
						and rag:GetPos():DistToSqr(target:GetPos()) < 600 * 600 then
						nearestCorpse = rag
						break
					end
				end
				if nearestCorpse then
					lines[#lines + 1] = "Someone stopped breathing nearby."
					lines[#lines + 1] = "Someone stopped breathing nearby."
				end

				local companion, isolated = false, true
				for _, p in player.Iterator() do
					if p != target and p:Alive() and p:Team() != TEAM_SPECTATOR and not p.isTraitor then
						local d = p:GetPos():DistToSqr(target:GetPos())
						if d < 300 * 300 then companion = true end
						if d < 500 * 500 then isolated = false end
					end
				end
				if companion then
					lines[#lines + 1] = "Whoever you're with, look closer."
				end
				if isolated then
					lines[#lines + 1] = "It waits until you're alone."
					lines[#lines + 1] = "It only takes the ones who wander."
					lines[#lines + 1] = "It waits until you're alone."
				end

				target:Notify(lines[math.random(#lines)], 0)
			end
		end
	end

	-- ambient dread: positional sounds near random people - footsteps
	-- where nobody is, breathing behind you, distant moans. Mostly
	-- subtle, occasionally a distant scream or a deep boom for everyone.
	if self.NextAmbient and CurTime() > self.NextAmbient then
		self.NextAmbient = CurTime() + 30

		local subtle = {
			"ambient/creatures/town_scared_breathing1.wav",
			"ambient/creatures/town_scared_breathing2.wav",
			"ambient/creatures/town_muffled_cry1.wav",
			"ambient/creatures/town_moan1.wav",
			"ambient/levels/citadel/strange_talk1.wav",
			"ambient/levels/citadel/strange_talk3.wav",
			"ambient/levels/citadel/strange_talk8.wav",
			"ambient/materials/door_hit1.wav",
			"ambient/wind/wind_hit1.wav",
			"physics/wood/wood_box_footstep1.wav",
			"physics/wood/wood_box_footstep3.wav",
		}
		local rare = {
			"ambient/voices/f_scream1.wav",
			"ambient/creatures/town_zombie_call1.wav",
		}
		local boom = "ambient/atmosphere/cave_hit" .. math.random(1, 6) .. ".wav"

		-- rare jumpscare: one person's screen becomes a face
		if math.random(100) <= 10 then
			local jsPool = {}
			for _, p in player.Iterator() do
				if p:Alive() and p:Team() != TEAM_SPECTATOR and not p.isTraitor then jsPool[#jsPool + 1] = p end
			end
			if #jsPool > 0 then
				local victim = jsPool[math.random(#jsPool)]
				net.Start("fear_jumpscare")
					net.WriteUInt(math.random(2), 2)
				net.Send(victim)
				-- physical jolt to sell it
				victim:ViewPunch(Angle(math.Rand(-8, -14), math.Rand(-6, 6), math.Rand(-4, 4)))
			end
		end

		-- small chance: an explosive barrel somewhere just... goes off
		-- (holstered during the last-innocent toying - nothing lethal
		-- before the circle)
		if math.random(100) <= 7 and not self.LastAloneSent then
			local barrels = {}
			for _, ent in ipairs(ents.FindByClass("prop_physics")) do
				local mdl = string.lower(ent:GetModel() or "")
				if mdl:find("oildrum001_explosive") or mdl:find("explosive") then
					barrels[#barrels + 1] = ent
				end
			end
			if #barrels > 0 then
				local barrel = barrels[math.random(#barrels)]
				local dmg = DamageInfo()
				dmg:SetDamage(50)
				dmg:SetDamageType(DMG_BURN)
				dmg:SetAttacker(game.GetWorld())
				dmg:SetInflictor(game.GetWorld())
				barrel:TakeDamageInfo(dmg)
			end
		end

		local roll = math.random(100)
		if roll <= 8 then
			-- global deep boom, everyone feels it
			for _, p in player.Iterator() do
				if p:Alive() then p:EmitSound(boom, 60, math.random(85, 95)) end
			end

			-- and rarely, riding the boom: EVERYONE sees it. At once.
			-- The whole lobby screaming simultaneously, once a night.
			if math.random(100) <= 20 then
				net.Start("fear_jumpscare")
					net.WriteUInt(math.random(2), 2)
				net.Broadcast()
			end
		else
			-- positional sound near one random living person
			local pool = {}
			for _, p in player.Iterator() do
				if p:Alive() and p:Team() != TEAM_SPECTATOR and not p.isTraitor then pool[#pool + 1] = p end
			end
			if #pool > 0 then
				-- anchor on anyone alive - loners and groups alike; whoever
				-- is near the anchor hears it too
				local anchor = pool[math.random(#pool)]

				local ang = math.Rand(0, math.pi * 2)
				local dist = math.random(150, 400)
				local pos = anchor:GetPos() + Vector(math.cos(ang) * dist, math.sin(ang) * dist, math.random(0, 40))

				local snd = (roll <= 16) and rare[math.random(#rare)] or subtle[math.random(#subtle)]
				sound.Play(snd, pos, 85, math.random(90, 105))
			end
		end
	end

	-- occasional whispers: one player at a time gets a quiet notify
	if self.NextWhisper and CurTime() > self.NextWhisper then
		self.NextWhisper = self:Sched(15, 15)

		local whispers = {
			"It knows where you are.",
			"Don't turn around.",
			"You are being watched.",
			"Someone here isn't real.",
			"It remembers you.",
			"The dark is closer than it looks.",
			"You heard that too, didn't you?",
			"Stay in the light.",
			"Do not look for it.",
			"Something followed you here.",
			"It waits until you're alone.",
			"That wasn't a door.",
			"It is standing very still.",
			"The flashlight only helps you find it.",
			"One of them has the words.",
			"It has been listening this whole time.",
			"You walked past it twice already.",
			"The others cannot hear you scream.",
			"It learned your name tonight.",
			"Whoever you're with, look closer.",
			"The lights won't stay on for you.",
			"You were not supposed to see that.",
			"It only takes the ones who wander.",
			"Someone stopped breathing nearby.",
			"Do not answer if it calls you.",
			"The doors open for it, not you.",
			"You've been marked.",
			"It's wearing someone's face.",
			"Run, and it will notice you.",
		}

		-- half the time it whispers to the one being hunted
		local target
		if IsValid(self.CurrentVictim) and self.CurrentVictim:Alive() and math.random(2) == 1 then
			target = self.CurrentVictim
		else
			local pool = {}
			for _, p in player.Iterator() do
				if p:Alive() and p:Team() != TEAM_SPECTATOR and not p.isTraitor then pool[#pool + 1] = p end
			end
			if #pool > 0 then target = pool[math.random(#pool)] end
		end

		if IsValid(target) and target.Notify then
			target:Notify(whispers[math.random(#whispers)], 0)
		end
	end

	-- the final image: first person to look at a corpse sometimes sees
	-- what the victim saw (15%)
	if not self.NextCorpseCheck or CurTime() > self.NextCorpseCheck then
		self.NextCorpseCheck = CurTime() + 2

		for _, rag in ipairs(ents.FindByClass("prop_ragdoll")) do
			if not rag.fearSeen then
				local owner = rag.ply
				if owner != nil and (not IsValid(owner) or not owner:Alive()) then
					for _, p in player.Iterator() do
						if p:Alive() and not p.isTraitor and p:Team() != TEAM_SPECTATOR
							and p:GetPos():DistToSqr(rag:GetPos()) < 500 * 500
							and IsLookingAt(p, rag:GetPos(), 0.9) then
							rag.fearSeen = true
							if math.random(100) <= 15 then
								net.Start("fear_jumpscare")
									net.WriteUInt(math.random(2), 2)
								net.Send(p)
								p:ViewPunch(Angle(-10, 3, -2))
							end
							break
						end
					end
				end
			end
		end
	end

	self.CurrentVictim = IsValid(self.CurrentVictim) and self.CurrentVictim:Alive() and self.CurrentVictim or self:SelectTheBestVictim()

	-- the mark: whoever it hunts hears their own heart
	if self.CurrentVictim != self.LastMarked then
		if IsValid(self.LastMarked) then
			net.Start("fear_marked") net.WriteBool(false) net.Send(self.LastMarked)
		end
		if IsValid(self.CurrentVictim) then
			net.Start("fear_marked") net.WriteBool(true) net.Send(self.CurrentVictim)
		end
		self.LastMarked = self.CurrentVictim
	end

	local ply = self.CurrentVictim
	
	-- print(ply, CurTime(), MODE.saved.KillTime)

	if !IsValid(ply) then return end
	-- post-EndRound epilogue can arrive with a freshly wiped saved
	-- table (the round "ended" but fear's last-survivor hunt continues);
	-- re-arm the clock instead of crashing on the nil compare
	if not self.saved.KillTime then
		self.saved.KillTime = CurTime() + 10
		return
	end
	if CurTime() < self.saved.KillTime then return end

	--print(ply, CurTime(), MODE.saved.KillTime, true)

	if #players == 1 then
		if ply.isTraitor then
			self:TraitorRites(ply)
		else
			self:LastRites(ply)
		end
		return
	end

	local wep = ply:GetActiveWeapon()
	local use_weapon = math.random(2) == 1 and ishgweapon(wep) and wep.CanSuicide and wep:Clip1() > 0 and ply:GetNWFloat("willsuicide", 0) == 0
	if !use_weapon then
		local flag = true

		for i2, ply2 in ipairs(players) do
			if IsLookingAt(ply2, ply:EyePos(), 0.8) and hg.isVisible(ply:EyePos(), ply2:EyePos(), {ply, ply2}, MASK_VISIBLE) then
				flag = false
			end
		end

		local fate = self:RollAttackFate(not flag)
		if fate == "disappear" then
			self:Disappear(ply)
		elseif flag then
			-- Remaining 85%: eight equal outcomes (10.625% each).
			local fates = {
				function() ply:KillSilent() end,
				function() self:PropKill(ply) end,
				function() hg.BreakNeck(ply) end,
				function() if not ply.noHead then hg.ExplodeHead(ply) else ply:KillSilent() end end,
				function() self:StartEvent("scary_black_guy", ply) end,
				function()
					for _, v in player.Iterator() do
						v:ScreenFade(SCREENFADE.IN, Color(0, 0, 0), 0.7, 0.4)
					end
					ply:KillSilent()
				end,
				function() self:TorsoTake(ply) end,
				function() self:PropStrike(ply) end,
			}
			fates[math.random(#fates)]()
		else
			local function DoSnatch()
				if ply.isTraitor and #zb:CheckAlive() > 1 then return end
				local bot = ents.Create("bot_fear")
				bot.Victim = ply
				bot:Spawn()

				-- a second snatcher takes someone else moments later
				local candidates = {}
				for _, p2 in ipairs(players) do
					if p2 != ply and IsValid(p2) and p2:Alive() and not p2.isTraitor then
						candidates[#candidates + 1] = p2
					end
				end
				if #candidates > 0 then
					local ply2 = candidates[math.random(#candidates)]
					timer.Simple(math.Rand(2, 6), function()
						if IsValid(ply2) and ply2:Alive() then
							local bot2 = ents.Create("bot_fear")
							bot2.Victim = ply2
							bot2:Spawn()
						end
					end)
				end
			end

			-- Snatch retains 40%; disappearance already received 15%.
			if fate == "snatch" then
				DoSnatch()
				self.CurrentVictim = nil
				return
			end

			-- Remaining 45%: six equal outcomes (7.5% each).
			local fates = {
				function()
					for _, v in player.Iterator() do
						v:ScreenFade(SCREENFADE.IN, Color(0, 0, 0), 0.7, 0.4)
					end
					ply:KillSilent()
				end,
				function() if not ply.noHead then hg.ExplodeHead(ply) else ply:KillSilent() end end,
				function() self:StartEvent("scary_black_guy", ply) end,
				function() self:FloorTake(ply) end,
				function() self:TorsoTake(ply) end,
				function() self:PropStrike(ply) end,
			}
			fates[math.random(#fates)]()
		end
	else
		if ply.suiciding then
			wep:PrimaryAttack(true)
		else
			local ent = wep:GetTrace().Entity
			if IsValid(ent) and ent:IsPlayer() and math.random(2) == 1 then
				wep:PrimaryAttack(true)
			else
				ply:SetNWFloat("willsuicide", CurTime() + 5)
			end
		end
	end

	self.CurrentVictim = nil
end

function MODE:ResetNetworkVars(ply)
	ply:SetNWFloat("willsuicide", 0)
	ply:SetLocalVar("afterlife", nil)
	ply:SetNetVar("disappearance", nil)
	ply:SetCustomCollisionCheck(false)
	ply:CollisionRulesChanged()
end

function MODE:PlayerSilentDeath(ply)
	self:ResetNetworkVars(ply)
end

function MODE:PlayerDeath(ply)
	self:ResetNetworkVars(ply)

	self:CreateTimer("Fear_End", 3, 1, function()
		local alive = zb:CheckAlive()

		if #alive == 1 then
			-- the innocent survivor gets a long, toying grace; the
			-- cultist's pact is broken - collection comes quickly
			MODE.saved.KillTime = CurTime() + ((IsValid(alive[1]) and alive[1].isTraitor) and 12 or 15)
			
			for i, ent in ipairs(ents.FindByClass('env_soundscape*')) do
				ent:Remove()
			end

			if timer.Exists("disappearance " .. alive[1]:EntIndex()) then
				timer.Adjust("disappearance " .. alive[1]:EntIndex(), 0)
			end
		end
	end)
end

function MODE:Ragdoll_Create(ply, ent)
	ent:SetCustomCollisionCheck(true)
	ent:CollisionRulesChanged()
end

function MODE:HG_PlayerCanHearPlayersVoice(listener, talker)
	if listener:GetNetVar("disappearance") or talker:GetNetVar("disappearance") then return true end
end

function MODE:HG_PlayerCanSeePlayersChat(listener, talker)
	if listener:GetNetVar("disappearance") or talker:GetNetVar("disappearance") then return true end
end


-- =====================================================================
-- Map approval commands (server console or superadmin):
--   fear_allowmap        - approve the CURRENT map for fear rotation
--   fear_allowmap <map>  - approve a named map
--   fear_disallowmap <map or blank for current>
--   fear_maplist         - show approved maps
-- Night-named maps are always allowed automatically.
-- =====================================================================
local function fearMapsLoad()
	return util.JSONToTable(file.Read("fear_maps.txt", "DATA") or "") or {}
end

local function fearMapsSave(t)
	file.Write("fear_maps.txt", util.TableToJSON(t, true))
	if zb.modes["fear"] then zb.modes["fear"].FearMaps = t end
end

local function fearMapCmdAllowed(ply)
	return not IsValid(ply) or ply:IsSuperAdmin()
end

concommand.Add("fear_allowmap", function(ply, _, args)
	if not fearMapCmdAllowed(ply) then return end
	local map = string.lower(args[1] or game.GetMap())
	local t = fearMapsLoad()
	t[map] = true
	fearMapsSave(t)
	print("[Fear] '" .. map .. "' approved for fear rotation.")
end)

concommand.Add("fear_disallowmap", function(ply, _, args)
	if not fearMapCmdAllowed(ply) then return end
	local map = string.lower(args[1] or game.GetMap())
	local t = fearMapsLoad()
	t[map] = nil
	fearMapsSave(t)
	print("[Fear] '" .. map .. "' removed from fear rotation.")
end)

concommand.Add("fear_maplist", function(ply)
	if not fearMapCmdAllowed(ply) then return end
	print("[Fear] Approved maps (plus anything with 'night' in the name):")
	for map in pairs(fearMapsLoad()) do print("  " .. map) end
end)


-- =====================================================================
-- The flashlight face: sometimes, when a light comes on, it is
-- already there in the beam. 4% per toggle-on, never the cultist.
-- =====================================================================
hook.Add("PlayerSwitchFlashlight", "Fear_FlashlightFace", function(ply, on)
	if not (zb and (zb.CROUND == "fear" or zb.CROUND == "fear_soe")) then return end
	if not on or not IsValid(ply) or not ply:Alive() then return end
	if ply.isTraitor then return end
	if math.random(100) > 4 then return end

	local dir = ply:GetAimVector()
	dir.z = 0
	dir:Normalize()
	local tr = util.TraceLine({
		start = ply:EyePos(),
		endpos = ply:EyePos() + dir * 300,
		filter = ply,
	})
	local dist = math.min(tr.HitPos:Distance(ply:EyePos()) - 40, 260)
	if dist < 100 then return end

	local floor = util.TraceLine({
		start = ply:GetPos() + dir * dist + vector_up * 40,
		endpos = ply:GetPos() + dir * dist - vector_up * 300,
	})
	if not floor.Hit then return end

	local fig = ents.Create("ent_zc_anim")
	if not IsValid(fig) then return end
	fig:SetPos(floor.HitPos)
	fig:SetModel("models/Humans/Group01/male_06.mdl")
	fig:SetMaterial("models/debug/debugwhite")
	fig:SetColor(color_black)
	fig:SetAngles(Angle(0, (ply:GetPos() - floor.HitPos):Angle().yaw, 0))
	fig:Spawn()
	fig:ResetSequence(126)
	fig:SetWhiteListToSee(true)
	fig:SetNetVar("CanSeeUserID", { [ply:UserID()] = true })

	ply:EmitSound("npc/stalker/go_alert2a.wav", 78, 90)

	timer.Simple(0.6, function()
		if IsValid(fig) then fig:Remove() end
	end)
end)


concommand.Add("fear_massjumpscare", function(ply)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	net.Start("fear_jumpscare")
		net.WriteUInt(math.random(2), 2)
	net.Broadcast()
	print("[Fear] The whole lobby saw it.")
end)
