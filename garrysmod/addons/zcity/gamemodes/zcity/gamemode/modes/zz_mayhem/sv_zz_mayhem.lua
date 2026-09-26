local MODE = MODE

MODE.name = "mayhem"
MODE.PrintName = "Mayhem"
MODE.LootSpawn = false
MODE.GuiltDisabled = true
MODE.randomSpawns = true
MODE.noBoxes = true

MODE.ForBigMaps = false
MODE.Chance = 0.03

util.AddNetworkString("mayhem_start")
util.AddNetworkString("mayhem_end")

function MODE:CanLaunch()
	return true
end

function MODE:Intermission()
	game.CleanUpMap()

	for k, ply in player.Iterator() do
		if ply:Team() == TEAM_SPECTATOR then
			continue
		end

		ApplyAppearance(ply)
		ply:SetupTeam(0)
	end

	local rndpoints = zb.GetMapPoints("RandomSpawns")
	local zonepoint = table.Random(rndpoints)

	net.Start("mayhem_start")
		net.WriteVector(zonepoint and zonepoint.pos or Vector(0, 0, 0))
	net.Broadcast()
end

function MODE:CheckAlivePlayers()
	local AlivePlyTbl = {}
	for _, ply in player.Iterator() do
		if not ply:Alive() then continue end
		if ply.organism and ply.organism.incapacitated then continue end
		AlivePlyTbl[#AlivePlyTbl + 1] = ply
	end
	return AlivePlyTbl
end

function MODE:ShouldRoundEnd()
	return (#zb:CheckAlive(true) <= 1)
end

function MODE:RoundStart()
	for _, ply in player.Iterator() do
		if not ply:Alive() then continue end
		ply:SetSuppressPickupNotices(true)
		ply.noSound = true

		ply:StripWeapons()
		ply:StripAmmo()

		local hands = ply:Give("weapon_hands_sh")
		ply:SelectWeapon("weapon_hands_sh")

		local inv = ply:GetNetVar("Inventory")
		if inv then
			inv["Weapons"] = inv["Weapons"] or {}
			inv["Weapons"]["hg_sling"] = true
			ply:SetNetVar("Inventory", inv)
		end

		-- Force-inject 5 doses of Fury-13 (each dose = +2 berserk)
		-- plus 20% of a Fentanyl syringe so pain doesn't knock anyone out
		if ply.organism then
			ply.organism.berserk = (ply.organism.berserk or 0) + 10
			ply.organism.analgesiaAdd = math.min((ply.organism.analgesiaAdd or 0) + 0.2, 4)
			ply.organism.recoilmul = 0.25
		end

		local entOwner = IsValid(ply.FakeRagdoll) and ply.FakeRagdoll or ply
		entOwner:EmitSound("snd_jack_hmcd_needleprick.wav", 80, math.random(75, 90))

		ply:ChatPrint("Five doses of Fury-13 course through your veins.")

		timer.Simple(0.1, function()
			if IsValid(ply) then ply.noSound = false end
		end)

		ply:SetSuppressPickupNotices(false)
		zb.GiveRole(ply, "Maniac", Color(190, 15, 15))
	end
end

function MODE:GiveWeapons()
end

function MODE:GiveEquipment()
end

function MODE:RoundThink()
end

function MODE:PlayerDeath(ply)
end

function MODE:CanSpawn()
end

function MODE:EndRound()
	timer.Simple(2, function()
		net.Start("mayhem_end")
		local ent = zb:CheckAlive(true)[1]
		net.WriteEntity(IsValid(ent) and ent:Alive() and ent or NULL)
		net.Broadcast()
	end)
end
