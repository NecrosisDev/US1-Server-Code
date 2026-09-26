local MODE = MODE

function MODE:Intermission()
	-- Set loot table from hmcd
	if MODE.Types and MODE.Types.masscasualty and not MODE.Types.masscasualty.LootTable then
		local hmcd = zb.modes["hmcd"]
		if hmcd then
			MODE.Types.masscasualty.LootTable = hmcd.LootTableStandard
		end
	end

	-- Force hmcd.Type to masscasualty since hooks use the hmcd MODE table
	local hmcd = zb.modes["hmcd"]
	if hmcd then
		hmcd.Types = hmcd.Types or {}
		hmcd.Types.masscasualty = MODE.Types.masscasualty

		hmcd.Roles = hmcd.Roles or {}
		hmcd.Roles.masscasualty = MODE.Roles.masscasualty

		hmcd.Type = "masscasualty"
	end

	-- Call hmcd's Intermission
	zb.modes["hmcd"].Intermission(self)

	-- Force 3 traitors at 0.5s (this happens during pre-round)
	timer.Simple(0.5, function()
		local current = 0
		for _, ply in player.Iterator() do
			if ply.isTraitor then current = current + 1 end
		end

		-- Need to assign more traitors if we have fewer than 3
		local needed = math.min(3, math.floor(#player.GetAll() / 2)) - current
		if needed > 0 then
			local candidates = {}
			for _, ply in player.Iterator() do
				if not ply.isTraitor and ply:Team() ~= TEAM_SPECTATOR then
					table.insert(candidates, ply)
				end
			end

			for i = 1, needed do
				if #candidates == 0 then break end
				local idx = math.random(#candidates)
				local target = candidates[idx]
				table.remove(candidates, idx)

				target.isTraitor = true
				-- Give them traitor loot
				if hmcd and hmcd.Types and hmcd.Types.masscasualty then
					hmcd.Types.masscasualty.TraitorLoot(target)
				end
				-- Give role
				zb.GiveRole(target, "Mass Shooter", Color(190, 0, 0))
			end
		end
	end)

	-- Give 1-2 random bystanders a concealed pistol AFTER they've actually spawned
	timer.Simple(2, function()
		local pistols = {"weapon_px4beretta", "weapon_p250", "weapon_p220", "weapon_glock17"}
		local bystanders = {}
		for _, ply in player.Iterator() do
			if ply:Alive() and not ply.isTraitor and not ply.isPolice and ply:Team() ~= TEAM_SPECTATOR then
				table.insert(bystanders, ply)
			end
		end

		local count = math.random(1, 2)
		for i = 1, math.min(count, #bystanders) do
			local idx = math.random(#bystanders)
			local target = bystanders[idx]
			table.remove(bystanders, idx)

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

function MODE:PlayerDeath(ply)
end

-- Second wave logic - spawn 30 seconds after first wave with double count
hook.Add("Think", "MassCasualty_SecondWave", function()
	if zb.CROUND ~= "masscasualty" then return end
	local mode = zb.modes["hmcd"]
	if not mode then return end
	if mode.Type ~= "masscasualty" then return end
	if zb.ROUND_STATE ~= 1 then return end
	if not mode.PoliceSpawned then return end
	if mode.SecondWaveSpawned then return end

	mode.MC_FirstWaveTime = mode.MC_FirstWaveTime or CurTime()
	if CurTime() < mode.MC_FirstWaveTime + 30 then return end

	local available = mode:GetActivePlayers()
	local max = math.min(#available, 8)

	if max > 0 then
		mode:SpawnForce("police", max)
		mode.SecondWaveSpawned = true
		PrintMessage(HUD_PRINTTALK, "Backup units have arrived!")
		EmitSound("snd_jack_hmcd_policesiren.wav", vector_origin, 0, CHAN_AUTO, 1, 125, 0, 100)
	end
end)

hook.Add("ZB_StartRound", "MassCasualty_ResetWave", function()
	local mode = zb.modes["hmcd"]
	if mode then
		mode.SecondWaveSpawned = false
		mode.MC_FirstWaveTime = nil
		mode.MC_BoringEnded = false
	end
end)

-- End round 2 minutes after first wave to prevent boring stalemates
hook.Add("Think", "MassCasualty_BoringTimer", function()
	if zb.CROUND ~= "masscasualty" then return end
	local mode = zb.modes["hmcd"]
	if not mode then return end
	if mode.Type ~= "masscasualty" then return end
	if zb.ROUND_STATE ~= 1 then return end
	if not mode.MC_FirstWaveTime then return end
	if mode.MC_BoringEnded then return end

	if CurTime() >= mode.MC_FirstWaveTime + 120 then
		mode.MC_BoringEnded = true
		PrintMessage(HUD_PRINTTALK, "Stopping round because it's too boring.")
		zb:EndRound()
	end
end)
