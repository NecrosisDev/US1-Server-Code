MODE.name = "Cops/Gangsters"
MODE.PrintName = "Cops/Gangsters"

MODE.ForBigMaps = false
MODE.ROUND_TIME = 250

MODE.Chance = 0.02

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

util.AddNetworkString("cb_start")
function MODE:Intermission()
	game.CleanUpMap()


	
	for i, ply in player.Iterator() do
		ply:SetupTeam(ply:Team())
	end

	net.Start("cb_start")
	net.Broadcast()
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

local gangstersWeapons = {
"weapon_m1911",
"weapon_revolver357",
"weapon_px4beretta",
"weapon_m9beretta",
"weapon_makarov",
"weapon_browninghp",
"weapon_tokarev",
"weapon_uzi",
"weapon_akm"
}
 
local policeWeapon = {
"weapon_glock17",
"weapon_medkit_sh",
"weapon_bigbandage_sh",
"weapon_handcuffs_key",
"weapon_handcuffs",
"weapon_taser",
"weapon_tourniquet",
"weapon_hg_tonfa"

}

local guysConsumables = {
    "weapon_bigbandage_sh",
    "weapon_bandage_sh",
    "weapon_medkit_sh",
    "weapon_painkillers"
    
}






function MODE:GetPlySpawn(ply)
end
function MODE:CheckAlivePlayers()
    local cPlayers = {}
    local bPlayers = {}
 
    for _, ply in ipairs(team.GetPlayers(0)) do
        if ply:Alive() and not ply:GetNetVar("handcuffed", false) then
            table.insert(bPlayers, ply)
        end
    end
 
    for _, ply in ipairs(team.GetPlayers(1)) do
        if ply:Alive() and not ply:GetNetVar("handcuffed", false) then
            table.insert(cPlayers, ply)
        end
    end
 
    return {bPlayers, cPlayers}

end
function MODE:GiveEquipment()

	timer.Simple(0.1,function()
		local teamArmorCount = { [0] = 0, [1] = 1 } 
		local akGiven = 0 -- max 2 gangsters roll the AK per round

		-- guarantee at least one AK: pre-pick a random gangster who gets
		-- it outright (rolls can still produce one more, capped at 2)
		local akChosen
		local gangsters = {}
		for _, p in player.Iterator() do
			if p:Alive() and p:Team() == 0 then gangsters[#gangsters + 1] = p end
		end
		if #gangsters > 0 then
			akChosen = gangsters[math.random(#gangsters)]
		end

		-- guarantee one cop carries the Remington 870
		local shotgunChosen
		local cops = {}
		for _, p in player.Iterator() do
			if p:Alive() and p:Team() == 1 then cops[#cops + 1] = p end
		end
		if #cops > 0 then
			shotgunChosen = cops[math.random(#cops)]
		end

		for _, ply in player.Iterator() do
			if not ply:Alive() then continue end
			ply:SetSuppressPickupNotices(true)
			ply.noSound = true

			if ply:Team() == 0 then
				ply:SetPlayerClass("groove")
				zb.GiveRole(ply, "Groover", Color(0,255,0))
				ply:SetNetVar("CurPluv", "pluvred")
                local wclass
                if ply == akChosen then
                    wclass = "weapon_akm"
                    akGiven = akGiven + 1
                else
                    wclass = gangstersWeapons[math.random(#gangstersWeapons)]
                    if wclass == "weapon_akm" then
                        if akGiven >= 2 then
                            repeat
                                wclass = gangstersWeapons[math.random(#gangstersWeapons)]
                            until wclass ~= "weapon_akm"
                        else
                            akGiven = akGiven + 1
                        end
                    end
                end
                local wep = ply:Give(wclass)
                local wep1 = ply:Give(guysConsumables[math.random(#guysConsumables)])
                ply:Give("weapon_fentanyl") -- every gangster carries fent
                ply:GiveAmmo(wep:GetMaxClip1() * 3, wep:GetPrimaryAmmoType())
				
			else
				ply:SetPlayerClass("police")
				zb.GiveRole(ply, "Police Officer", Color(0,0,255))
				ply:SetNetVar("CurPluv", "pluvgreen")
				hg.AddArmor(ply, "ent_armor_vest3") -- kevlar III-A

				if ply == shotgunChosen then
					local sg = ply:Give("weapon_remington870")
					if IsValid(sg) then
						ply:GiveAmmo(sg:GetMaxClip1() * 3, sg:GetPrimaryAmmoType())
					end
				end
				
                for n, wp in pairs(policeWeapon)do

                local s = ply:Give(wp)
				
                ply:GiveAmmo(s:GetMaxClip1() * 3, s:GetPrimaryAmmoType())
				
            end
            
			end

			
			





			local hands = ply:Give("weapon_hands_sh")
	

			timer.Simple(0.1,function()
				if not IsValid(ply) then return end
				ply.noSound = false
			end)

			ply:SetSuppressPickupNotices(false)
		end
	end)
end


function MODE:GetTeamSpawn()
	return zb.TranslatePointsToVectors(zb.GetMapPoints( "HMCD_TDM_T" )), zb.TranslatePointsToVectors(zb.GetMapPoints( "HMCD_TDM_CT" ))
end

function MODE:CanSpawn()
end

util.AddNetworkString("cb_roundend")
function MODE:EndRound()
	timer.Simple(2,function()
		net.Start("cb_roundend")
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