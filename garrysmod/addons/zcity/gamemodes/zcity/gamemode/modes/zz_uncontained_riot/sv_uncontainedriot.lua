-- Native file refresh has no loader-owned global MODE; reuse this mode only.
local refreshing = MODE == nil
local MODE = MODE or (zb and zb.modes and zb.modes.uncontainedriot)
if not MODE then return end

MODE.name = "uncontainedriot"
MODE.PrintName = "Uncontained Riot"

MODE.OverideSpawnPos = true
MODE.LootSpawn = false
MODE.ForBigMaps = false
MODE.Chance = 0.03
MODE.ROUND_TIME = 300

-- Rioter weapons - lower grade pistols, rifles, shotguns
local rioterPistols = {
    "weapon_mp-80",
    "weapon_makarov",
    "weapon_ruger",
    "weapon_p22",
    "weapon_revolver2",
    "weapon_m1911",
    "weapon_zoraki",
    "weapon_ppk",
    "weapon_grach",
}

local rioterRifles = {
    "weapon_mini14",
    "weapon_kar98",
    "weapon_sks",
    "weapon_ak74u",
    "weapon_vpo136",
    "weapon_musket",
    "weapon_draco",
}

local rioterShotguns = {
    "weapon_doublebarrel_short",
    "weapon_doublebarrel",
    "weapon_winchester",
    "weapon_remington870",
    "weapon_toz194",
    "weapon_mossy500",
}

local rioterMelee = {
    "weapon_leadpipe",
    "weapon_brick",
    "weapon_hammer",
    "weapon_bat",
    "weapon_hg_axe",
    "weapon_hg_machete",
    "weapon_hg_sledgehammer",
    "weapon_hatchet",
}

local rioterConsumables = {
    "weapon_bigconsumable",
    "weapon_smallconsumable",
    "weapon_ducttape",
    "weapon_matches",
    "weapon_bandage_sh",
}

-- Workshop weapon availability differs between installations. Keep the category
-- roll, but choose only definitions that are actually mounted on this server.
local function GiveRandom(ply, choices)
    local available = {}
    for _, class in ipairs(choices) do
        if weapons.GetStored(class) then available[#available + 1] = class end
    end
    if #available == 0 then return end
    return ply:Give(available[math.random(#available)])
end

local function GiveReserve(ply, wep, magazines)
    if not IsValid(wep) then return end
    local clip, ammo = wep:GetMaxClip1(), wep:GetPrimaryAmmoType()
    if type(clip) == "number" and clip > 0 and clip < math.huge
        and type(ammo) == "number" and ammo >= 0 then
        ply:GiveAmmo(clip * magazines, ammo, true)
    end
end

local function SpawnPoints(preferred, fallback)
    local points = zb.TranslatePointsToVectors(zb.GetMapPoints(preferred) or {})
    if #points == 0 then
        points = zb.TranslatePointsToVectors(zb.GetMapPoints(fallback) or {})
    end
    return points -- Empty lists intentionally use ZCity's ordinary map-spawn fallback.
end

function MODE.GuiltCheck(Attacker, Victim, add, harm, amt)
    return 0, false
end

MODE.GuiltDisabled = true

util.AddNetworkString("uncontainedriot_start")
util.AddNetworkString("uncontainedriot_roundend")

function MODE:Intermission()
    game.CleanUpMap()

    for i, ply in player.Iterator() do
        if IsValid(ply) and ply:Team() ~= TEAM_SPECTATOR then
            ply:SetupTeam(ply:Team())
        end
    end

    net.Start("uncontainedriot_start")
    net.Broadcast()
end

function MODE:CheckAlivePlayers()
    local lawPlayers = {}
    local rioterPlayers = {}

    for _, ply in ipairs(team.GetPlayers(1)) do
        if ply:Alive() and not ply:GetNetVar("handcuffed", false) then
            table.insert(lawPlayers, ply)
        end
    end

    for _, ply in ipairs(team.GetPlayers(0)) do
        if ply:Alive() and not ply:GetNetVar("handcuffed", false) then
            table.insert(rioterPlayers, ply)
        end
    end

    return {lawPlayers, rioterPlayers}
end

function MODE:EndRound()
    local stamp = zb.ROUND_START
    timer.Simple(2, function()
        if CurrentRound() ~= self or zb.ROUND_STATE ~= 3 or zb.ROUND_START ~= stamp then return end
        net.Start("uncontainedriot_roundend")
        net.Broadcast()
    end)
end

function MODE:ShouldRoundEnd()
    local endround, winner = zb:CheckWinner(self:CheckAlivePlayers())
    return endround
end

function MODE:RoundStart()
end

function MODE:GiveEquipment()
    local players = player.GetAll()
    local valid = {}
    for _, ply in ipairs(players) do
        if IsValid(ply) and ply:Team() ~= TEAM_SPECTATOR then
            table.insert(valid, ply)
        end
    end
    table.Shuffle(valid)

    local numPlayers = #valid
    if numPlayers == 0 then return end
    -- Rioters get 2/3 of players, police get 1/3 (minimum 1 cop)
    local numLawEnforcers = math.max(math.floor(numPlayers / 3), 1)
    local numRioters = numPlayers - numLawEnforcers

    local pipebomberCount = 0
    local maxPipebombers = math.max(math.floor(numRioters / 4), 1)

    -- RIOTERS
    for i = 1, numRioters do
        local ply = valid[i]

        ply:SetupTeam(0)
        ply:SetPlayerClass("terrorist")
        zb.GiveRole(ply, "Rioter", Color(190, 0, 0))
        ply:SetNetVar("CurPluv", "pluvmajima")

        local hands = ply:Give("weapon_hands_sh")

        -- Roll for weapon type: 40% pistol, 25% rifle, 25% shotgun, 10% melee-only
        local roll = math.random(100)
        local mainWep

        if roll <= 40 then
            mainWep = GiveRandom(ply, rioterPistols)
        elseif roll <= 65 then
            mainWep = GiveRandom(ply, rioterRifles)
        elseif roll <= 90 then
            mainWep = GiveRandom(ply, rioterShotguns)
        end

        GiveReserve(ply, mainWep, 2)

        -- Everyone gets a melee
        GiveRandom(ply, rioterMelee)

        -- ~25% chance of pipebomb up to max
        if pipebomberCount < maxPipebombers and math.random(100) <= 25 then
            ply:Give("weapon_hg_pipebomb_tpik")
            pipebomberCount = pipebomberCount + 1
        end

        -- Also a chance for molotov
        if math.random(100) <= 15 then
            ply:Give("weapon_hg_molotov_tpik")
        end

        -- Consumable
        GiveRandom(ply, rioterConsumables)

        -- 40% chance for light armor
        if math.random(100) <= 40 then
            hg.AddArmor(ply, "ent_armor_helmet2")
        end

        if IsValid(mainWep) then
            ply:SelectWeapon(mainWep:GetClass())
        end
    end

    -- POLICE
    for i = numRioters + 1, numPlayers do
        local ply = valid[i]

        ply:SetupTeam(1)
        ply:SetPlayerClass("police")
        zb.GiveRole(ply, "Law Enforcement", Color(0, 0, 190))
        ply:SetNetVar("CurPluv", "pluvberet")

        local inv = ply:GetNetVar("Inventory")
        if not istable(inv) then inv = {} end
        if not istable(inv.Weapons) then inv.Weapons = {} end
        inv["Weapons"]["hg_sling"] = true
        inv["Weapons"]["hg_flashlight"] = true
        ply:SetNetVar("Inventory", inv)

        local hands = ply:Give("weapon_hands_sh")

        -- Heavy police loadout
        local ar = ply:Give("weapon_ar15")
        if IsValid(ar) then
            GiveReserve(ply, ar, 4)
            hg.AddAttachmentForce(ply, ar, "holo1")
        end

        local glock = ply:Give("weapon_glock17")
        if IsValid(glock) then
            GiveReserve(ply, glock, 3)
        end

        ply:Give("weapon_hg_tonfa")
        ply:Give("weapon_taser")
        ply:Give("weapon_walkie_talkie")
        ply:Give("weapon_handcuffs")
        ply:Give("weapon_handcuffs_key")
        ply:Give("weapon_medkit_sh")
        ply:Give("weapon_bandage_sh")
        ply:Give("weapon_tourniquet")
        ply:Give("weapon_hg_flashbang_tpik")
        ply:Give("weapon_hg_smokenade_tpik")

        -- Heavy armor for police
        hg.AddArmor(ply, "ent_armor_helmet1")
        hg.AddArmor(ply, "ent_armor_vest4")

        ply:SelectWeapon("weapon_ar15")
    end
end

function MODE:GetTeamSpawn()
    return SpawnPoints("RIOT_TDM_RIOTERS", "HMCD_TDM_T"), SpawnPoints("RIOT_TDM_LAW", "HMCD_TDM_CT")
end

function MODE:RoundThink()
end

function MODE:CanLaunch()
    local activePlayers = 0

    for _, ply in player.Iterator() do
        if ply:Team() ~= TEAM_SPECTATOR then
            activePlayers = activePlayers + 1
        end
    end

    if activePlayers < 5 then
        return false
    end

    return true
end

MODE.ZCRiotServerRevision = "1.0.1"
if refreshing then
    local callbacks = zb.modesHooks and zb.modesHooks.uncontainedriot
    if callbacks then
        -- The loader already registered these dispatch hooks. Refresh only ours.
        for _, key in ipairs({"GuiltCheck", "Intermission", "CheckAlivePlayers", "EndRound", "ShouldRoundEnd", "RoundStart", "GiveEquipment", "GetTeamSpawn", "RoundThink", "CanLaunch"}) do
            callbacks[key] = MODE[key]
        end
    end
    print("[RiotFix] 1.0.1 server callbacks refreshed")
end

return MODE
