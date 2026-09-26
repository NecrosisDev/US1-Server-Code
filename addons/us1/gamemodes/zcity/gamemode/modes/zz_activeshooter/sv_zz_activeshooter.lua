local MODE = MODE

-- Override the GuiltCheck inherited from sh_ file
-- The shooter killing bystanders shouldn't trigger guilt bans
function MODE.GuiltCheck(Attacker, Victim, add, harm, amt)
	-- Active shooter killing anyone is fine
	if Attacker.isTraitor then
		return 0, false
	end
	-- Police killing the shooter is fine
	if Attacker.isPolice and Victim.isTraitor then
		return 0, false
	end
	-- Bystanders shouldn't kill each other - standard guilt
	return 1, true
end

function MODE:Intermission()
	-- Set loot table from hmcd
	if MODE.Types and MODE.Types.activeshooter and not MODE.Types.activeshooter.LootTable then
		local hmcd = zb.modes["hmcd"]
		if hmcd then
			MODE.Types.activeshooter.LootTable = hmcd.LootTableStandard
		end
	end

	-- Force hmcd.Type to activeshooter since hooks use the hmcd MODE table
	local hmcd = zb.modes["hmcd"]
	if hmcd then
		hmcd.Types = hmcd.Types or {}
		hmcd.Types.activeshooter = MODE.Types.activeshooter

		hmcd.Roles = hmcd.Roles or {}
		hmcd.Roles.activeshooter = MODE.Roles.activeshooter

		hmcd.Type = "activeshooter"
		hmcd.SecondWaveSpawned = false
	end

	-- Call hmcd's Intermission
	zb.modes["hmcd"].Intermission(self)

	-- Give 1-2 random bystanders a concealed pistol
	timer.Simple(2, function()
		local pistols = {"weapon_px4beretta", "weapon_p250", "weapon_p220", "weapon_glock17"}
		local candidates = {}
		for _, ply in player.Iterator() do
			if ply:Alive() and not ply.isTraitor and not ply.isPolice and ply:Team() ~= TEAM_SPECTATOR then
				table.insert(candidates, ply)
			end
		end

		local count = math.random(1, 2)
		for i = 1, math.min(count, #candidates) do
			local idx = math.random(#candidates)
			local target = candidates[idx]
			table.remove(candidates, idx)

			local pistol = pistols[math.random(#pistols)]
			local wep = target:Give(pistol)
			if IsValid(wep) then
				target:GiveAmmo(wep:GetMaxClip1(), wep:GetPrimaryAmmoType(), true)
			end
			target.organism.recoilmul = 1
			target:Notify("You have a concealed pistol with one spare magazine.", 0)
		end
	end)
end

-- Track second wave separately by hooking into RoundThink
hook.Add("Think", "ActiveShooter_SecondWave", function()
	if zb.CROUND ~= "activeshooter" then return end
	local mode = zb.modes["hmcd"]
	if not mode then return end
	if mode.Type ~= "activeshooter" then return end
	if zb.ROUND_STATE ~= 1 then return end
	if not mode.PoliceSpawned then return end
	if mode.SecondWaveSpawned then return end

	-- Wait until 30 seconds after first wave
	mode.FirstWaveTime = mode.FirstWaveTime or CurTime()
	if CurTime() < mode.FirstWaveTime + 30 then return end

	-- Spawn second wave - double count
	local available = mode:GetActivePlayers()
	local max = math.min(#available, 8)

	if max > 0 then
		mode:SpawnForce("police", max)
		mode.SecondWaveSpawned = true
		PrintMessage(HUD_PRINTTALK, "Backup units have arrived!")
		EmitSound("snd_jack_hmcd_policesiren.wav", vector_origin, 0, CHAN_AUTO, 1, 125, 0, 100)
	end
end)

-- Reset on round start
hook.Add("ZB_StartRound", "ActiveShooter_ResetWave", function()
	local mode = zb.modes["hmcd"]
	if mode then
		mode.SecondWaveSpawned = false
		mode.FirstWaveTime = nil
		-- Reset type back to standard if next round isn't activeshooter
		if zb.CROUND ~= "activeshooter" and mode.Type == "activeshooter" then
			mode.Type = "standard"
		end
	end
end)

-- Track when first wave actually spawns
hook.Add("Think", "ActiveShooter_TrackFirstWave", function()
	if zb.CROUND ~= "activeshooter" then return end
	local mode = zb.modes["hmcd"]
	if not mode then return end
	if mode.Type ~= "activeshooter" then return end
	if mode.PoliceSpawned and not mode.FirstWaveTime then
		mode.FirstWaveTime = CurTime()
	end
end)

-- End round 2 minutes after first wave to prevent boring stalemates
hook.Add("Think", "ActiveShooter_BoringTimer", function()
	if zb.CROUND ~= "activeshooter" then return end
	local mode = zb.modes["hmcd"]
	if not mode then return end
	if mode.Type ~= "activeshooter" then return end
	if zb.ROUND_STATE ~= 1 then return end
	if not mode.FirstWaveTime then return end
	if mode.BoringEnded then return end

	if CurTime() >= mode.FirstWaveTime + 120 then
		mode.BoringEnded = true
		PrintMessage(HUD_PRINTTALK, "Stopping round because it's too boring.")
		zb:EndRound()
	end
end)

hook.Add("ZB_StartRound", "ActiveShooter_ResetBoring", function()
	local mode = zb.modes["hmcd"]
	if mode then
		mode.BoringEnded = false
	end
end)

function MODE:PlayerDeath(ply)
end
