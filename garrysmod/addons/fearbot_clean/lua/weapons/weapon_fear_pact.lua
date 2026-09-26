-- The Pact Idol: the fear traitor's command over the entity.
-- LMB = lethal strike on the aimed player (3 favors, exposure risk)
-- RMB = scare on the aimed player (1 favor, untraceable)
-- R   = cycle which lethal strike LMB performs
-- Favors: start with 3, +1 each time the entity takes a soul itself.

SWEP.PrintName = "Pact Idol"
SWEP.Author = ""
SWEP.Instructions = "LMB: lethal strike. RMB: scare. R: cycle strike."
SWEP.Category = "ZCity Other"

SWEP.Spawnable = true
SWEP.AdminOnly = true

SWEP.ViewModel = "models/weapons/c_arms.mdl"
SWEP.WorldModel = "models/Gibs/HGIBS.mdl"
SWEP.UseHands = true

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

SWEP.DrawAmmo = false
SWEP.Slot = 5
SWEP.SlotPos = 5

-- Lane search for the charple sprint, matching the Fear Event context menu
-- (sh_zc_fearevents.lua). The old version drew 8 purely random yaws and
-- discarded anything under 450u, so one unlucky roll or a mid-sized room meant
-- the scare silently did nothing. Now the sweep is evenly spaced with a random
-- phase so it covers the circle instead of clustering, players and ragdolls do
-- not block it, the wall pull-back scales with the room available, and the
-- longest lane found is kept as a fallback instead of the attempt failing.
-- Deliberately duplicated rather than shared: each file has to stay
-- independently hot-reloadable on a live server.
local LANE_TRIES = 24
local LANE_IDEAL = 450 -- stop looking once a lane is at least this long
local LANE_MIN = 140 -- below this a sprint reads as a teleport, not a charge
local LANE_REACH = 900

local function LaneFilter(victim, body)
	return function(e)
		if e == victim or e == body then return false end
		if e:IsPlayer() then return false end
		if e:GetClass() == "prop_ragdoll" then return false end
		return true
	end
end

local function FindLane(victim, body, origin)
	local filter = LaneFilter(victim, body)
	local best, bestYaw, bestDist
	local phase = math.random() * 360

	for i = 0, LANE_TRIES - 1 do
		local yaw = (phase + i * (360 / LANE_TRIES)) % 360
		local dir = Angle(0, yaw, 0):Forward()
		local lane = util.TraceHull({
			start = origin, endpos = origin + dir * LANE_REACH,
			filter = filter, mins = Vector(-20, -20, 0), maxs = Vector(20, 20, 40),
		})

		local reach = lane.HitPos:Distance(origin)
		if not lane.StartSolid and reach >= LANE_MIN then
			-- Clear the wall we just hit without stepping back past the target.
			local mouth = lane.HitPos - dir * math.Clamp(reach * 0.25, 32, 72)
			local floor = util.TraceLine({
				start = mouth + vector_up * 24,
				endpos = mouth - vector_up * 900,
				filter = filter,
			})

			if floor.Hit and not floor.StartSolid then
				local spawn = floor.HitPos + vector_up * 2
				local room = util.TraceHull({
					start = spawn + vector_up * 4, endpos = spawn + vector_up * 4,
					filter = filter, mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 68),
				})

				if not room.StartSolid then
					local dist = spawn:Distance(origin)
					if not bestDist or dist > bestDist then
						best, bestYaw, bestDist = spawn, yaw, dist
					end
					if dist >= LANE_IDEAL then break end
				end
			end
		end
	end

	return best, bestYaw
end

local STRIKES = {
	{ name = "Feed Them To It", desc = "a natural fate, indistinguishable" },
	{ name = "Send The Snatcher", desc = "dragged into the dark" },
	{ name = "The Floor Take", desc = "the ground claims them" },
	{ name = "The Hunt", desc = "it runs them down" },
	{ name = "The Fling", desc = "hurled at the wall" },
}

function SWEP:SetupDataTables()
	self:NetworkVar("Int", 0, "StrikeMode")
end

function SWEP:Initialize()
	self:SetHoldType("normal")
end

-- nobody sees the idol - the pact is private
function SWEP:DrawWorldModel() end
function SWEP:DrawWorldModelTranslucent() end

local function fearMode()
	return zb and zb.modes and zb.modes["fear"]
end

local function inFearRound()
	return zb and (zb.CROUND == "fear" or zb.CROUND == "fear_soe")
end

function SWEP:IsPactAdmin()
	local ply = self:GetOwner()
	return IsValid(ply) and ply:IsSuperAdmin() and not ply.isTraitor
end

function SWEP:CanCommand()
	local ply = self:GetOwner()
	if not IsValid(ply) or not ply:Alive() then return false end

	-- superadmins holding a spawned idol answer to no pact
	if self:IsPactAdmin() then
		if (ply.PactCooldown or 0) > CurTime() then
			return false, "The pact must rest."
		end
		return true
	end

	if not inFearRound() then return false, "The pact sleeps." end
	if not ply.isTraitor then return false, "The pact is not yours." end
	if zb.ROUND_START and CurTime() < zb.ROUND_START + 15 then
		return false, "Too early. Let them settle."
	end
	if (ply.PactCooldown or 0) > CurTime() then
		return false, "The pact must rest."
	end
	return true
end

function SWEP:GetTargetPlayer()
	-- forgiving cone: nearest-to-crosshair valid target within ~8
	-- degrees and 1500u, line of sight required
	local ply = self:GetOwner()
	local eye = ply:EyePos()
	local aim = ply:GetAimVector()

	local best, bestDot = nil, 0.96
	for _, p in player.Iterator() do
		if p != ply and p:Alive() and p:Team() != TEAM_SPECTATOR
			and not p.isTraitor and not p:GetNetVar("disappearance") then
			local to = (p:WorldSpaceCenter() - eye)
			if to:Length() <= 1500 then
				to:Normalize()
				local dot = aim:Dot(to)
				if dot > bestDot then
					-- walls block; bodies, props and players do not
					local tr = util.TraceLine({
						start = eye,
						endpos = p:WorldSpaceCenter(),
						mask = MASK_SOLID_BRUSHONLY,
					})
					if not tr.Hit or tr.Fraction > 0.95 then
						best = p
						bestDot = dot
					end
				end
			end
		end
	end
	return best
end

local function getFavors(ply)
	return ply:GetNWInt("PactFavors", 0)
end

local function spendFavors(ply, n)
	ply:SetNWInt("PactFavors", math.max(getFavors(ply) - n, 0))
end

function SWEP:Reload()
	if CLIENT then return end
	if (self.LastCycle or 0) > CurTime() - 0.3 then return end
	self.LastCycle = CurTime()
	self:SetStrikeMode((self:GetStrikeMode() + 1) % #STRIKES)
	local ply = self:GetOwner()
	if IsValid(ply) then
		ply:ChatPrint("[Pact] Strike: " .. STRIKES[self:GetStrikeMode() + 1].name)
	end
end

function SWEP:PrimaryAttack()
	if CLIENT then return end
	local ply = self:GetOwner()

	local ok, why = self:CanCommand()
	if not ok then
		if why then ply:ChatPrint("[Pact] " .. why) end
		return
	end

	if not self:IsPactAdmin() and getFavors(ply) < 2 then
		ply:ChatPrint("[Pact] Not enough favors (need 2). It grows stronger with each soul it takes.")
		return
	end

	local target = self:GetTargetPlayer()
	if not target then
		ply:ChatPrint("[Pact] Look upon the one you offer.")
		return
	end

	local MODE = fearMode()
	if not MODE then return end

	if not self:IsPactAdmin() then spendFavors(ply, 2) end
	ply.PactCooldown = CurTime() + (self:IsPactAdmin() and 3 or 20)

	local mode = self:GetStrikeMode() + 1
	target.PactKilled = CurTime() -- commanded deaths earn nothing

	if mode == 1 then
		-- a natural fate: fade-kill, snatch, or head-pop - the entity's
		-- own repertoire, on command
		local roll = math.random(3)
		if roll == 1 then
			for _, v in player.Iterator() do
				v:ScreenFade(SCREENFADE.IN, Color(0, 0, 0), 0.7, 0.4)
			end
			target:KillSilent()
		elseif roll == 2 then
			local bot = ents.Create("bot_fear")
			if IsValid(bot) then bot.Victim = target bot:Spawn() end
		else
			if not target.noHead and hg and hg.ExplodeHead then
				hg.ExplodeHead(target)
			else
				target:KillSilent()
			end
		end
	elseif mode == 2 then
		local bot = ents.Create("bot_fear")
		if IsValid(bot) then bot.Victim = target bot:Spawn() end
	elseif mode == 3 then
		if MODE.FloorTake then MODE:FloorTake(target) else target:KillSilent() end
	elseif mode == 4 then
		-- THE HUNT: the burnt thing runs them down. Contact is lethal.
		local sp, sy
		for i = 1, 8 do
			local yw = math.random(0, 359)
			local d = Angle(0, yw, 0):Forward()
			local tr2 = util.TraceHull({
				start = target:EyePos(), endpos = target:EyePos() + d * 900,
				filter = target, maxs = Vector(20, 20, 40), mins = Vector(-20, -20, 0),
			})
			if tr2.HitPos:Distance(target:EyePos()) >= 500 then
				local fl = util.TraceLine({ start = tr2.HitPos - d * 60, endpos = tr2.HitPos - d * 60 - vector_up * 500 })
				if fl.Hit then sp = fl.HitPos sy = yw break end
			end
		end
		if not sp then
			-- no run-up room: it takes them where they stand
			if MODE.FloorTake then MODE:FloorTake(target) else target:KillSilent() end
		else
			local fig = ents.Create("ent_zc_anim")
			if IsValid(fig) then
				fig:SetPos(sp)
				fig:SetModel("models/humans/charple01.mdl")
				fig:SetAngles(Angle(0, sy + 180, 0))
				fig:Spawn()
				local seq = fig:LookupSequence("run_all")
				fig:ResetSequence(seq >= 0 and seq or 126)
				fig:EmitSound("npc/fast_zombie/gurgle_loop1.wav", 88, 100)
				target:SetEyeAngles(Angle(5, sy, 0))
				local idx = fig:EntIndex()
				hook.Add("Think", "PactHunt_" .. idx, function()
					if not IsValid(fig) or not IsValid(target) or not target:Alive() then
						hook.Remove("Think", "PactHunt_" .. idx)
						if IsValid(fig) then fig:Remove() end
						return
					end
					local v = target:GetPos() - fig:GetPos()
					local dist = v:Length()
					if dist < 40 then
						fig:StopSound("npc/fast_zombie/gurgle_loop1.wav")
						target:EmitSound("lurker_scream.wav", 100, 100)
						hg.BreakNeck(target)
						for _, w in player.Iterator() do
							w:ScreenFade(SCREENFADE.IN, Color(0, 0, 0), 0.8, 0.4)
						end
						hook.Remove("Think", "PactHunt_" .. idx)
						timer.Simple(1.2, function()
							if IsValid(fig) then fig:Remove() end
						end)
						return
					end
					fig:SetPos(fig:GetPos() + v:GetNormalized() * math.min(1250 * FrameTime(), dist))
					fig:SetAngles(Angle(0, v:Angle().yaw, 0))
					local l = (fig:GetPos() + vector_up * 50 - target:EyePos()):Angle()
					target:SetEyeAngles(Angle(l.pitch, l.yaw, 0))
				end)
			end
		end
	else
		-- THE FLING: grabbed, dropped limp, hurled at the nearest wall
		pcall(function() MODE:FlingPlayer(target) end)
	end

	-- exposure: lethal commands sometimes leave a trace
	if math.random(100) <= 20 then
		timer.Simple(math.Rand(1, 3), function()
			if IsValid(target) and target.Notify then
				target:Notify("Someone sent it.", 0)
			end
		end)
	end

	print("[Pact] " .. ply:Nick() .. " -> " .. STRIKES[mode].name .. " on " .. target:Nick())
end

function SWEP:SecondaryAttack()
	if CLIENT then return end
	local ply = self:GetOwner()

	local ok, why = self:CanCommand()
	if not ok then
		if why then ply:ChatPrint("[Pact] " .. why) end
		return
	end

	if not self:IsPactAdmin() and getFavors(ply) < 1 then
		ply:ChatPrint("[Pact] No favors. It grows stronger with each soul it takes.")
		return
	end

	local target = self:GetTargetPlayer()
	if not target then
		ply:ChatPrint("[Pact] Look upon the one you would torment.")
		return
	end

	local MODE = fearMode()
	if not MODE then return end

	if not self:IsPactAdmin() then spendFavors(ply, 1) end
	ply.PactCooldown = CurTime() + (self:IsPactAdmin() and 3 or 20)

	local roll = math.random(6)
	if roll == 1 then
		local lines = {
			"It knows where you are.", "Don't look for it.",
			"You've been noticed.", "It is very close to you now.",
		}
		if target.Notify then target:Notify(lines[math.random(#lines)], 0) end
	elseif roll == 2 then
		pcall(function() MODE:StartEvent("scary_black_guy", target) end)
	elseif roll == 3 then
		for _, ent in ipairs(ents.FindInSphere(target:GetPos(), 500)) do
			if hgIsDoor(ent) then ent:Use(target) end
		end
	elseif roll == 4 then
		-- their light dies for 30 seconds
		local inv = target:GetNetVar("Inventory")
		if inv and inv["Weapons"] and inv["Weapons"]["hg_flashlight"] then
			inv["Weapons"]["hg_flashlight"] = nil
			target:SetNetVar("Inventory", inv)
			target:Flashlight(false)
			if target.Notify then target:Notify("The lights won't stay on for you.", 0) end
			timer.Simple(30, function()
				if IsValid(target) and target:Alive() then
					local inv2 = target:GetNetVar("Inventory")
					if inv2 and inv2["Weapons"] then
						inv2["Weapons"]["hg_flashlight"] = true
						target:SetNetVar("Inventory", inv2)
					end
				end
			end)
		elseif target.Notify then
			target:Notify("It is watching your light.", 0)
		end
	elseif roll == 5 then
		net.Start("fear_jumpscare")
			net.WriteUInt(math.random(2), 2)
		net.Send(target)
		target:ViewPunch(Angle(-10, 3, -2))
	else
		-- the burnt thing sprints at them
		local sp, sy = FindLane(target, target, target:EyePos())
		if sp then
			local fig = ents.Create("ent_zc_anim")
			if IsValid(fig) then
				fig:SetPos(sp)
				fig:SetModel("models/humans/charple01.mdl")
				fig:SetAngles(Angle(0, sy + 180, 0))
				fig:Spawn()
				local seq = fig:LookupSequence("run_all")
				fig:ResetSequence(seq >= 0 and seq or 126)
				fig:EmitSound("npc/fast_zombie/gurgle_loop1.wav", 85, 110)
				target:SetEyeAngles(Angle(5, sy, 0))
				local idx = fig:EntIndex()
				hook.Add("Think", "PactCharple_" .. idx, function()
					if not IsValid(fig) or not IsValid(target) or not target:Alive() then
						hook.Remove("Think", "PactCharple_" .. idx)
						if IsValid(fig) then fig:Remove() end
						return
					end
					local v = target:GetPos() - fig:GetPos()
					local dist = v:Length()
					if dist < 30 then
						fig:StopSound("npc/fast_zombie/gurgle_loop1.wav")
						target:EmitSound("ambient/wind/wind_hit1.wav", 90, 95)
						hook.Remove("Think", "PactCharple_" .. idx)
						fig:Remove()
						return
					end
					fig:SetPos(fig:GetPos() + v:GetNormalized() * math.min(1500 * FrameTime(), dist))
					fig:SetAngles(Angle(0, v:Angle().yaw, 0))
					local l = (fig:GetPos() + vector_up * 50 - target:EyePos()):Angle()
					target:SetEyeAngles(Angle(l.pitch, l.yaw, 0))
				end)
			end
		end
	end

	print("[Pact] " .. ply:Nick() .. " -> scare on " .. target:Nick())
end

if CLIENT then
	surface.CreateFont("PactHUD", { font = "Bahnschrift", size = 22, weight = 700, antialias = true })
	surface.CreateFont("PactHUDBig", { font = "Bahnschrift", size = 28, weight = 900, antialias = true })

	function SWEP:DrawHUD()
		local ply = LocalPlayer()
		local favors = ply:GetNWInt("PactFavors", 0)
		local strike = STRIKES[self:GetStrikeMode() + 1]

		local x, y = ScrW() / 2, ScrH() - 160

		draw.SimpleText("THE PACT", "PactHUDBig", x, y, Color(255, 230, 0, 230), TEXT_ALIGN_CENTER)
		draw.SimpleText("Favors: " .. favors .. (favors >= 6 and "  (MAX)" or ""), "PactHUD", x, y + 30, Color(255, 255, 255, 220), TEXT_ALIGN_CENTER)

		if favors < 6 then
			local nextAt = ply:GetNWFloat("PactNextFavor", 0)
			local interval = ply:GetNWFloat("PactFavorInt", 30)
			local frac = 1 - math.Clamp((nextAt - CurTime()) / interval, 0, 1)
			local bw, bh = 220, 8
			local bx, by = x - bw / 2, y + 52
			surface.SetDrawColor(0, 0, 0, 160)
			surface.DrawRect(bx, by, bw, bh)
			surface.SetDrawColor(255, 230, 0, 220)
			surface.DrawRect(bx + 1, by + 1, (bw - 2) * frac, bh - 2)
			surface.SetDrawColor(120, 90, 0, 255)
			surface.DrawOutlinedRect(bx, by, bw, bh, 1)
		end
		draw.SimpleText("LMB  " .. strike.name .. " (2)     RMB  Scare (1)     R  cycle strike", "PactHUD", x, y + 68,
			Color(190, 190, 190, 200), TEXT_ALIGN_CENTER)

		-- target readout: same forgiving cone as the server
		local eye = ply:EyePos()
		local aim = ply:GetAimVector()
		local best, bestDot = nil, 0.96
		for _, p in player.Iterator() do
			if p != ply and p:Alive() and p:Team() != TEAM_SPECTATOR
				and not p:GetNetVar("disappearance") then
				local to = (p:WorldSpaceCenter() - eye)
				if to:Length() <= 1500 then
					to:Normalize()
					local dot = aim:Dot(to)
					if dot > bestDot then
						local tr = util.TraceLine({
							start = eye,
							endpos = p:WorldSpaceCenter(),
							mask = MASK_SOLID_BRUSHONLY,
						})
						if not tr.Hit or tr.Fraction > 0.95 then
							best = p
							bestDot = dot
						end
					end
				end
			end
		end
		if IsValid(best) then
			draw.SimpleText("Offering: " .. best:Nick(), "PactHUD", x, y + 94, Color(180, 0, 0, 230), TEXT_ALIGN_CENTER)
		end
	end
end

function SWEP:Deploy() return true end
function SWEP:Holster() return true end
