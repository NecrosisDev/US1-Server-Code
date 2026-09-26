MODE.name = "gwars"
MODE.PrintName = "Gang Wars"

MODE.ForBigMaps = false
MODE.ROUND_TIME = 180

MODE.Chance = 0.026

MODE.OverideSpawnPos = true
MODE.LootSpawn = false

function MODE:CanLaunch()
	return true
	--[[local points = zb.GetMapPoints( "HMCD_TDM_T" )
	local points2 = zb.GetMapPoints( "HMCD_TDM_CT" )
    return (#points > 0) and (#points2 > 0)--]]
end

function MODE.GuiltCheck(Attacker, Victim, add, harm, amt)
	return 1, true--returning true so guilt bans
end

util.AddNetworkString("gwars_start")
function MODE:Intermission()
	game.CleanUpMap()

	self.CTPoints = {}
	table.CopyFromTo(zb.GetMapPoints( "HMCD_TDM_CT" ),self.CTPoints)
	self.TPoints = {}
	table.CopyFromTo(zb.GetMapPoints( "HMCD_TDM_T" ),self.TPoints)
	
	for i, ply in player.Iterator() do
		ply:SetupTeam(ply:Team())
	end

	net.Start("gwars_start")
	net.Broadcast()
end

function MODE:CheckAlivePlayers()
	return zb:CheckAliveTeams(true)
end

function MODE:ShouldRoundEnd()
	local endround, winner = zb:CheckWinner(self:CheckAlivePlayers())

	return endround or boringround
end

function MODE:BoringRoundFunction()		
	timer.Simple(2, function()
		//PrintMessage(HUD_PRINTTALK, "IT IS A GANG SHOOTOUT FFS...")
	end)
end

local swatSpawned = false

function MODE:RoundStart()
    swatSpawned = false 
end

local tblweps = {
	[0] = {
		"weapon_cz75",
		"weapon_deagle",
		"weapon_glock17",
		"weapon_glock18c",
		"weapon_revolver2",
		"weapon_hk_usp",
		"weapon_p22",
		"weapon_doublebarrel_short",
		"weapon_skorpion",
		//"weapon_uzi",
		"weapon_mac11",
		//"weapon_draco",
		//"weapon_ar_pistol",
		-- WFA Pistols
		"weapon_grach",
		"weapon_glock22",
		"weapon_python",
		"weapon_p250",
		"weapon_mk23",
		"weapon_fivsevn",
		"weapon_tti2011",
		"weapon_p320alligator",
	},
	[1] = {
		"weapon_cz75",
		"weapon_deagle",
		"weapon_glock17",
		"weapon_glock18c",
		"weapon_revolver2",
		"weapon_hk_usp",
		"weapon_p22",
		"weapon_doublebarrel_short",
		"weapon_skorpion",
		//"weapon_uzi",
		"weapon_mac11",
		//"weapon_draco",
		//"weapon_ar_pistol",
		-- WFA Pistols
		"weapon_grach",
		"weapon_glock22",
		"weapon_python",
		"weapon_p250",
		"weapon_mk23",
		"weapon_fivsevn",
		"weapon_tti2011",
		"weapon_p320alligator",
	}
}


--[[local tblatts = {
	[0] = {
		{"optic4"},
	},
	[1] = {
		{"holo14","laser2","grip3"}
	}
}]]

local tblarmors = {
	[0] = {
		{"ent_armor_vest3","ent_armor_helmet2"}
	},
	[1] = {
		{"ent_armor_vest3","ent_armor_helmet2"}
	}
}

function MODE:GetPlySpawn(ply)
end

-- A spectator/unassigned player or missing optional SWEP must not abort
-- equipment for the rest of the server.
function MODE:GiveGangEquipment(ply,repairOnly,equipmentToken)
    if not IsValid(ply) or not ply:Alive() then return false end
    local teamID=ply:Team()
    local list=tblweps[teamID]
    if not list then return false end

    local hands=ply:GetWeapon("weapon_hands_sh")
    local needsHands=not IsValid(hands)
    local classMissing=not isstring(ply.PlayerClassName) or ply.PlayerClassName=="none"
    local tokenComplete=equipmentToken and ply.ZCGwarsEquipmentToken==equipmentToken
    if repairOnly and not needsHands and not classMissing then return true end

    local quiet=ply.noSound
    ply.noSound=true
    ply:SetSuppressPickupNotices(true)
    local ok,err=xpcall(function()
        -- Hands are essential; complete this before optional firearm selection.
        if needsHands then
            hands=ply:Give("weapon_hands_sh")
            if not IsValid(hands) then error("weapon_hands_sh was not granted") end
        end
        if IsValid(hands) and (not repairOnly or not IsValid(ply:GetActiveWeapon())) then
            ply:SelectWeapon("weapon_hands_sh")
        end

        -- Normal round setup always assigns the Gangwar identity. A repair only
        -- fills in a missing identity so it cannot disturb an active player.
        if not repairOnly or classMissing then
            ply:SetPlayerClass(teamID==0 and "bloodz" or "groove")
            zb.GiveRole(ply,teamID==0 and "Bloodz" or "Groove",teamID==0 and Color(190,0,0) or Color(0,190,0))
            ply:SetNetVar("CurPluv",teamID==0 and "pluvred" or "pluvgreen")
        end

        if repairOnly or tokenComplete then return end

        local available={}
        for _,class in ipairs(list) do
            if isstring(class) and weapons.GetStored(class) then available[#available+1]=class end
        end
        if #available>0 then
            local wep=ply:Give(available[math.random(#available)])
            if IsValid(wep) then
                local amount,ammo=wep:GetMaxClip1()*3,wep:GetPrimaryAmmoType()
                if amount>0 and ammo>=0 then ply:GiveAmmo(amount,ammo) end
            end
        end
        for _,class in ipairs({"weapon_bandage_sh","weapon_tourniquet","weapon_fentanyl"}) do
            if weapons.GetStored(class) then ply:Give(class) end
        end
        ply.ZCGwarsEquipmentToken=equipmentToken
    end,debug.traceback)
    if IsValid(ply) then
        ply.noSound=quiet
        ply:SetSuppressPickupNotices(false)
    end
    if not ok then ErrorNoHalt("[GangWars] Player equipment failed: "..tostring(err).."\n") end
    return ok
end
MODE.EquipmentVersion="20260923.spawn2"
function MODE:GiveEquipment()
    self.CTPoints={}
    table.CopyFromTo(zb.GetMapPoints("HMCD_TDM_CT"),self.CTPoints)
    self.TPoints={}
    table.CopyFromTo(zb.GetMapPoints("HMCD_TDM_T"),self.TPoints)

    local token=(self.ZCGwarsEquipmentGeneration or 0)+1
    self.ZCGwarsEquipmentGeneration=token
    local timerName="ZCity.GWarsEquipment"
    timer.Remove(timerName)
    local attempts=0
    timer.Create(timerName,0.1,30,function()
        attempts=attempts+1
        -- A later mode owns the round; never equip players from an obsolete mode.
        if CurrentRound()~=self then
            timer.Remove(timerName)
            return
        end

        local pending=false
        for _,ply in player.Iterator() do
            if IsValid(ply) and ply:Alive() and tblweps[ply:Team()] then
                if not self:GiveGangEquipment(ply,false,token) then pending=true end
            end
        end

        if not pending then
            timer.Remove(timerName)
        elseif attempts>=30 then
            ErrorNoHalt("[GangWars] Equipment retry exhausted for generation "..tostring(token).."\n")
        end
    end)
end

function MODE:RoundThink()
    if not swatSpawned and (CurTime() - zb.ROUND_BEGIN) >= 120 then
        local deadPlayers = {}

        for _, ply in player.Iterator() do
            if not ply:Alive() and ply:Team() != TEAM_SPECTATOR then
                table.insert(deadPlayers, ply)
            end
        end

		local startpos = self.TPoints and #self.TPoints > 0 and self.TPoints[1].pos or zb:GetRandomSpawn()

		for i = 1, math.min(4, #deadPlayers) do
            local ply = deadPlayers[i]

            //if self.TPoints and #self.TPoints > 0 then
                ply:Spawn()
				ply:SetTeam(2)
				if !startpos then
					startpos = ply:GetPos()
				else
					hg.tpPlayer(startpos, ply, i, 0)
				end

                ply:SetPlayerClass("swat")
				zb.GiveRole(ply, "SWAT", Color(0,0,122))
				local gun = ply:Give("weapon_ar15")
                ply:GiveAmmo(gun:GetMaxClip1() * 3, gun:GetPrimaryAmmoType(), true)
                ply:Give("weapon_medkit_sh")
                ply:Give("weapon_tourniquet")
                ply:Give("weapon_walkie_talkie")
                ply:Give("weapon_hg_flashbang_tpik")
                hg.AddArmor(ply, "ent_armor_helmet1")
                hg.AddArmor(ply, "ent_armor_vest4")

                local hands = ply:Give("weapon_hands_sh")
                ply:SelectWeapon("weapon_hands_sh")
            //end
        end

        swatSpawned = true
    end
end

function MODE:GetTeamSpawn()
	return zb.TranslatePointsToVectors(zb.GetMapPoints( "HMCD_TDM_T" )), zb.TranslatePointsToVectors(zb.GetMapPoints( "HMCD_TDM_CT" ))
end

function MODE:CanSpawn()
end

util.AddNetworkString("gwars_roundend")
function MODE:EndRound()
	timer.Simple(2,function()
		net.Start("gwars_roundend")
		net.Broadcast()
	end)

	local endround, winner = zb:CheckWinner(self:CheckAlivePlayers())
	for k,ply in player.Iterator() do
		if ply:Team() == winner then
			ply:GiveExp(math.random(15,30))
			ply:GiveSkill(math.Rand(0.1,0.15))
			--print("give",ply)
		else
			--print("take",ply)
			ply:GiveSkill(-math.Rand(0.05,0.1))
		end
	end
end

function MODE:PlayerDeath(ply)
end