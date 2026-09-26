-- WILDCARD: two teams, pure identity chaos. Every player independently
-- rolls ANY class - combine, rebel, gangster, SWAT, police, national
-- guard, or one of the 51 DM fighter loadouts - regardless of team.
-- Team allegiance comes from team tags, not uniforms.
-- Kits are faithful replicas of their source modes (hl2dm, gwars,
-- homicide, criresp, dm).

util.AddNetworkString("wildcard_start")
util.AddNetworkString("wildcard_class")
util.AddNetworkString("wildcard_roundend")

-- =====================================================================
-- source pools
-- =====================================================================

-- gwars gangster pistols
local gangsterPistols = {
	"weapon_cz75", "weapon_deagle", "weapon_glock17", "weapon_glock18c",
	"weapon_revolver2", "weapon_hk_usp", "weapon_p22",
	"weapon_doublebarrel_short", "weapon_skorpion", "weapon_mac11",
	"weapon_grach", "weapon_glock22", "weapon_python", "weapon_p250",
	"weapon_mk23", "weapon_fivsevn", "weapon_tti2011", "weapon_p320alligator",
}

-- dm fighter loadouts (verbatim from modes/dm)
local loadouts = {
	{primary = "weapon_glock17", attachments = {{"supressor4"},{"holo16","laser3"},{"holo15","laser1"},""}, armor = {"vest3","helmet1"}, ammo = 3},
	{primary = "weapon_cz75", attachments = {{"supressor4"},{"supressor4"},""}, armor = {"vest3","helmet1"}, ammo = 3},
	{primary = "weapon_deagle", attachments = "", armor = {"vest3","helmet1"}, ammo = 3},
	{primary = "weapon_ar15", attachments = {{"holo1","grip1","supressor2"},{"holo5","grip3","supressor2"},{"laser4","grip2"},{"laser4","supressor2"}}, armor = {"vest4","helmet1"}, ammo = 3},
	{primary = "weapon_sr25", attachments = {{"holo1","laser2"},{"optic2"},{"holo8","supressor7"},{"holo5","supressor7"}}, armor = {"vest1","helmet1","nightvision1"}, ammo = 3},
	{primary = "weapon_ptrd", attachments = "", armor = {}, ammo = 12},
	{primary = "weapon_mp7", attachments = {{"holo1","supressor2"},{"holo5","supressor2"},{"laser4","supressor2"}}, armor = {"vest3","helmet1"}, ammo = 3},
	{primary = "weapon_p90", attachments = {{"holo15","supressor4"},{"laser1","supressor4"},{"holo14","supressor4"}}, armor = {"vest3","helmet1"}, ammo = 3},
	{primary = "weapon_doublebarrel_short", attachments = "", armor = {"vest3","helmet1","mask1"}, ammo = 6},
	{primary = "weapon_akm", attachments = {{"holo6","supressor1"},{"holo4","laser1"},{"supressor1"}}, armor = {"vest1","helmet1","nightvision1"}, ammo = 3},
	{primary = "weapon_remington870", attachments = "", armor = {"vest3","helmet1"}, ammo = 3},
	{primary = "weapon_m4a1", attachments = {{"holo1","grip1","supressor2"},{"holo5","grip3","supressor2"},{"laser4","grip2"},{"laser4","supressor2"}}, armor = {"vest1","helmet1"}, ammo = 3},
	{primary = "weapon_mac11", attachments = "", armor = {"vest3","helmet1"}, ammo = 3},
	{primary = "weapon_mp5", attachments = {{"supressor4"}}, armor = {"vest3","helmet1"}, ammo = 3},
	{primary = "weapon_m590a1", attachments = "", armor = {"vest4","helmet1","mask1"}, ammo = 3},
	{primary = "weapon_draco", attachments = "", armor = {"vest1","helmet1"}, ammo = 3},
	{primary = "weapon_uzi", attachments = "", armor = {"vest3","helmet1"}, ammo = 3},
	{primary = "weapon_tmp", attachments = {{"optic8"},{"holo3"},{"holo4"}}, armor = {"vest3","helmet1"}, ammo = 3},
	{primary = "weapon_xm1014", attachments = "", armor = {"vest3","helmet1","mask1"}, ammo = 3},
	{primary = "weapon_saiga12", attachments = "", armor = {"vest3","helmet1","mask1"}, ammo = 4},
	{primary = "weapon_svd", attachments = {{"holo13"},{"holo6"},{"holo2"}}, armor = {"vest1","helmet1"}, ammo = 3},
	{primary = "weapon_spas12", attachments = {{"supressor5"}}, armor = {"vest3","helmet1","mask1"}, ammo = 3},
	{primary = "weapon_hk416", attachments = {{"holo1","grip1","supressor2"},{"holo5","grip3","supressor2"},{"laser4","grip2"},{"laser4","supressor2"}}, armor = {"vest1","helmet1"}, ammo = 3},
	{primary = "weapon_akmwreked", attachments = "", armor = {"vest1","helmet1"}, ammo = 3},
	{primary = "weapon_hk_usp", attachments = {{"supressor3"}}, armor = {"vest3","helmet1"}, ammo = 3},
	{primary = "weapon_glock18c", attachments = {{"mag1","holo16"}}, armor = {"vest3","helmet1"}, ammo = 4},
	{primary = "weapon_skorpion", attachments = "", armor = {"vest3","helmet1"}, ammo = 4},
	{primary = "weapon_tec9", attachments = "", armor = {"vest3","helmet1"}, ammo = 3},
	{primary = "weapon_sg552", attachments = {{"optic8"},{"holo3"},{"holo4"}}, armor = {"vest4","helmet1"}, ammo = 3},
	{primary = "weapon_vector", attachments = {{"supressor4","holo3"},{"holo4"},{"holo7"}}, armor = {"vest3","helmet1"}, ammo = 4},
	{primary = "weapon_revolver2", attachments = "", armor = {"vest3","helmet1"}, ammo = 3},
	{primary = "weapon_revolver357", attachments = "", armor = {"vest3","helmet1"}, ammo = 3},
	{primary = "weapon_pkm", attachments = "", armor = {"vest1","helmet1"}, ammo = 0},
	{primary = "weapon_ak74", attachments = {{"holo6"},{"holo4"},{"optic8"}}, armor = {"vest1","helmet1"}, ammo = 3},
	{primary = "weapon_ak74u", attachments = {{"holo6"},{"holo4"}}, armor = {"vest1","helmet1"}, ammo = 3},
	{primary = "weapon_winchester", attachments = "", armor = {"vest3","helmet1"}, ammo = 4},
	{primary = "weapon_sks", attachments = {{"optic8"},{"holo6"}}, armor = {"vest3","helmet1"}, ammo = 4},
	{primary = "weapon_ruger", attachments = "", armor = {"vest3","helmet1"}, ammo = 5},
	{primary = "weapon_mini14", attachments = {{"optic8"},{"holo6"}}, armor = {"vest3","helmet1"}, ammo = 4},
	{primary = "weapon_ac556", attachments = {{"holo6"},{"holo4"}}, armor = {"vest3","helmet1"}, ammo = 3},
	{primary = "weapon_ar15", secondary = "weapon_cz75", attachments = {{"holo1","grip1"},{"holo5","grip3"}}, armor = {"vest3","helmet1"}, ammo = 3, ammo2 = 2},
	{primary = "weapon_akm", secondary = "weapon_px4beretta", attachments = {{"holo6"},{"holo4"}}, armor = {"vest3","helmet1"}, ammo = 3, ammo2 = 2},
	{primary = "weapon_m4a1", secondary = "weapon_p22", attachments = {{"holo1","grip1"},{"holo5","grip3"}}, armor = {"vest3","helmet1"}, ammo = 3, ammo2 = 2},
	{primary = "weapon_mp5", secondary = "weapon_revolver2", attachments = {{"supressor4"}}, armor = {"vest3","helmet1"}, ammo = 3, ammo2 = 2},
	{primary = "weapon_sks", secondary = "weapon_flintlock", attachments = "", armor = {"vest3","helmet1"}, ammo = 4, ammo2 = 3},
	{primary = "weapon_winchester", secondary = "weapon_cz75", attachments = "", armor = {"vest3","helmet1"}, ammo = 4, ammo2 = 2},
	{primary = "weapon_mini14", secondary = "weapon_px4beretta", attachments = {{"holo6"}}, armor = {"vest3","helmet1"}, ammo = 3, ammo2 = 2},
	{primary = "weapon_hg_bow", attachments = "", armor = {"helmet1"}, ammo = 25, melee = "weapon_pocketknife", noGrenade = true, medicine = {"weapon_bandage_sh"}, medicineCount = 1},
	{primary = "weapon_hg_bow", attachments = "", armor = {"helmet7"}, ammo = 25, melee = "weapon_pocketknife", noGrenade = true, medicine = {"weapon_bigbandage_sh"}, medicineCount = 1},
	{primary = "weapon_musket", secondary = "weapon_flintlock", attachments = "", armor = {"vest2","helmet1"}, ammo = 10, ammo2 = 6, melee = "weapon_pocketknife", randomMedicine = true},
	{primary = "weapon_musket", secondary = "weapon_flintlock", attachments = "", armor = {"vest3"}, ammo = 12, ammo2 = 8, melee = "weapon_pocketknife", randomMedicine = true},
}

local randomGrenades = {"weapon_hg_rgd_tpik", "weapon_hg_pipebomb_tpik", "weapon_hg_smokenade_tpik"}
local randomMedicine = {"weapon_bandage_sh", "weapon_bigbandage_sh", "weapon_medkit_sh", "weapon_fentanyl", "weapon_morphine", "weapon_adrenaline", "weapon_tourniquet"}
local randomMelees = {"weapon_melee", "weapon_pocketknife"}

-- =====================================================================
-- kit functions - each replicates its source mode faithfully
-- =====================================================================

local function GiveSling(ply)
	local inv = ply:GetNetVar("Inventory") or {}
	inv["Weapons"] = inv["Weapons"] or {}
	inv["Weapons"]["hg_sling"] = true
	ply:SetNetVar("Inventory", inv)
end

local function GiveFlashlight(ply)
	local inv = ply:GetNetVar("Inventory") or {}
	inv["Weapons"] = inv["Weapons"] or {}
	inv["Weapons"]["hg_flashlight"] = true
	ply:SetNetVar("Inventory", inv)
end

local function KitHL2DM(ply, side, sub, roleName)
	ply.subClass = sub
	if roleName then ply:SetNWString("PlayerRole", roleName) end
	GiveSling(ply)
	ply:SetPlayerClass(side)
end

local function KitGangster(ply)
	local flavor = math.random(2) == 1 and "bloodz" or "groove"
	ply:SetPlayerClass(flavor)
	zb.GiveRole(ply, "Gangster", flavor == "bloodz" and Color(190, 0, 0) or Color(0, 190, 0))
	local wep = ply:Give(gangsterPistols[math.random(#gangsterPistols)])
	if IsValid(wep) and wep.GetMaxClip1 then
		ply:GiveAmmo(wep:GetMaxClip1() * 3, wep:GetPrimaryAmmoType(), true)
	end
	ply:Give("weapon_bandage_sh")
	ply:Give("weapon_tourniquet")
	ply:Give("weapon_fentanyl")
	hg.AddArmor(ply, "ent_armor_vest3")
	hg.AddArmor(ply, "ent_armor_helmet2")
end

local function KitSWAT(ply)
	ply:SetPlayerClass("swat")
	zb.GiveRole(ply, "SWAT", Color(0, 0, 122))
	local gun = ply:Give("weapon_ar15")
	if IsValid(gun) and gun.GetMaxClip1 then
		ply:GiveAmmo(gun:GetMaxClip1() * 3, gun:GetPrimaryAmmoType(), true)
	end
	ply:Give("weapon_medkit_sh")
	ply:Give("weapon_tourniquet")
	ply:Give("weapon_walkie_talkie")
	hg.AddArmor(ply, "ent_armor_helmet1")
	hg.AddArmor(ply, "ent_armor_vest4")
end

local function KitPolice(ply)
	ply:SetPlayerClass("police")
	local glock = ply:Give("weapon_glock17")
	if IsValid(glock) and glock.GetMaxClip1 then
		ply:GiveAmmo(glock:GetMaxClip1() * 3, glock:GetPrimaryAmmoType(), true)
		if math.random(0, 1) == 1 then
			pcall(hg.AddAttachmentForce, ply, glock, "holo16")
		end
		if math.random(0, 1) == 1 then
			pcall(hg.AddAttachmentForce, ply, glock, "laser3")
		end
	end
	ply:Give("weapon_medkit_sh")
	ply:Give("weapon_walkie_talkie")
	ply:Give("weapon_naloxone")
	ply:Give("weapon_painkillers")
	ply:Give("weapon_handcuffs")
	ply:Give("weapon_handcuffs_key")
	ply:Give("weapon_hg_tonfa")
	local taser = ply:Give("weapon_taser")
	if IsValid(taser) and taser.GetMaxClip1 then
		ply:GiveAmmo(taser:GetMaxClip1() * 3, taser:GetPrimaryAmmoType(), true)
	end
	hg.AddArmor(ply, {"vest2"})
	GiveFlashlight(ply)
	if ply.organism then ply.organism.recoilmul = 0.8 end
	ply:SetNetVar("CurPluv", "pluvberet")
	zb.GiveRole(ply, "Police Officer", Color(15, 15, 255))
end

local function KitNationalGuard(ply, gunner)
	ply:SetPlayerClass("nationalguard")
	local gun = ply:Give(gunner and "weapon_m249" or "weapon_m4a1")
	if IsValid(gun) and gun.GetMaxClip1 then
		ply:GiveAmmo(gun:GetMaxClip1() * 3, gun:GetPrimaryAmmoType(), true)
	end
	local pistol = ply:Give("weapon_m9beretta")
	if IsValid(pistol) and pistol.GetMaxClip1 then
		ply:GiveAmmo(pistol:GetMaxClip1() * 3, pistol:GetPrimaryAmmoType(), true)
	end
	ply:Give("weapon_melee")
	ply:Give("weapon_handcuffs")
	ply:Give("weapon_handcuffs_key")
	ply:Give("weapon_walkie_talkie")
	ply:Give("weapon_bandage_sh")
	ply:Give("weapon_medkit_sh")
	local taser = ply:Give("weapon_taser")
	if IsValid(taser) and taser.GetMaxClip1 then
		ply:GiveAmmo(taser:GetMaxClip1() * 3, taser:GetPrimaryAmmoType(), true)
	end
	hg.AddArmor(ply, {"vest4", "helmet1"})
	GiveFlashlight(ply)
	GiveSling(ply)
	ply:SetNetVar("CurPluv", "pluvberet")
	zb.GiveRole(ply, "National Guard", Color(60, 90, 0))
end

local function KitFighter(ply)
	local loadout = loadouts[math.random(#loadouts)]
	local selectedAttachments = istable(loadout.attachments) and table.Random(loadout.attachments) or loadout.attachments

	GiveSling(ply)

	local gun = ply:Give(loadout.primary)
	if IsValid(gun) and gun.GetMaxClip1 then
		ply:GiveAmmo(gun:GetMaxClip1() * loadout.ammo, gun:GetPrimaryAmmoType(), true)
		pcall(hg.AddAttachmentForce, ply, gun, selectedAttachments)
	end

	if loadout.secondary then
		local pistol = ply:Give(loadout.secondary)
		if IsValid(pistol) and pistol.GetMaxClip1 then
			ply:GiveAmmo(pistol:GetMaxClip1() * (loadout.ammo2 or 2), pistol:GetPrimaryAmmoType(), true)
		end
	end

	hg.AddArmor(ply, loadout.armor)
	ply:Give(loadout.melee or randomMelees[math.random(#randomMelees)])

	if not loadout.noGrenade then
		local grenadeCount = math.random(1, 2)
		local usedGrenades = {}
		for i = 1, grenadeCount do
			local grenade = randomGrenades[math.random(#randomGrenades)]
			while usedGrenades[grenade] and i > 1 do
				grenade = randomGrenades[math.random(#randomGrenades)]
			end
			usedGrenades[grenade] = true
			ply:Give(grenade)
		end
	end

	if loadout.medicine then
		for i = 1, (loadout.medicineCount or 1) do
			ply:Give(loadout.medicine[math.random(#loadout.medicine)])
		end
	elseif loadout.randomMedicine then
		for i = 1, math.random(1, 2) do
			ply:Give(randomMedicine[math.random(#randomMedicine)])
		end
	else
		ply:Give("weapon_bandage_sh")
		ply:Give("weapon_tourniquet")
	end

	ply:Give("weapon_walkie_talkie")
	if ply.organism then ply.organism.recoilmul = 0.5 end
	zb.GiveRole(ply, "Fighter", Color(190, 15, 15))

	local gunName = string.gsub(loadout.primary, "weapon_", "")
	return "Fighter: " .. string.upper(gunName)
end

-- =====================================================================
-- the class table: name shown on splash, weight, kit function
-- =====================================================================
local classes = {
	{ name = "Combine Soldier",    weight = 1,   kit = function(p) KitHL2DM(p, "Combine", nil) end,               color = Color(120, 170, 255) },
	{ name = "Combine Elite",      weight = 1,   kit = function(p) KitHL2DM(p, "Combine", "elite", "Elite") end,  color = Color(200, 220, 255) },
	{ name = "Combine Shotgunner", weight = 1,   kit = function(p) KitHL2DM(p, "Combine", "shotgunner", "Shotgunner") end, color = Color(120, 170, 255) },
	{ name = "Combine Sniper",     weight = 1,   kit = function(p) KitHL2DM(p, "Combine", "sniper") end,          color = Color(120, 170, 255) },
	{ name = "Rebel",              weight = 1,   kit = function(p) KitHL2DM(p, "Rebel", nil) end,                 color = Color(255, 150, 90) },
	{ name = "Rebel Medic",        weight = 1,   kit = function(p) KitHL2DM(p, "Rebel", "medic") end,             color = Color(255, 190, 120) },
	{ name = "Rebel Grenadier",    weight = 1,   kit = function(p) KitHL2DM(p, "Rebel", "grenadier") end,         color = Color(255, 150, 90) },
	{ name = "Rebel Sniper",       weight = 1,   kit = function(p) KitHL2DM(p, "Rebel", "sniper") end,            color = Color(255, 150, 90) },
	{ name = "Gangster",           weight = 2,   kit = KitGangster,                                               color = Color(190, 60, 60) },
	{ name = "SWAT",               weight = 2,   kit = KitSWAT,                                                   color = Color(60, 60, 200) },
	{ name = "Police Officer",     weight = 2,   kit = KitPolice,                                                 color = Color(15, 15, 255) },
	{ name = "National Guard",     weight = 1.6, kit = function(p) KitNationalGuard(p, false) end,                color = Color(60, 90, 0) },
	{ name = "NG Machinegunner",   weight = 0.4, kit = function(p) KitNationalGuard(p, true) end,                 color = Color(90, 130, 0) },
	{ name = "Fighter",            weight = 6,   kit = KitFighter,                                                color = Color(190, 15, 15) },
}

local totalWeight = 0
for _, c in ipairs(classes) do totalWeight = totalWeight + c.weight end

local function PickClass()
	local roll = math.Rand(0, totalWeight)
	for _, c in ipairs(classes) do
		roll = roll - c.weight
		if roll <= 0 then return c end
	end
	return classes[#classes]
end

-- =====================================================================
-- the roller
-- =====================================================================
local function RollFor(ply)
	if not IsValid(ply) or not ply:Alive() then return end
	if ply:Team() == TEAM_SPECTATOR then return end

	-- BULLETPROOF: whoever calls this on an already-dealt player
	-- (ragdoll wake-ups, zcity spawn flows, anything) gets a
	-- restore, never a re-roll. The flag lives inside the roll.
	if ply.WildcardDealt then
		local keep = ply.WildcardClass
		if keep then
			pcall(function() ply:SetPlayerClass(keep) end)
		end
		return
	end
	ply.WildcardDealt = true

	ply:SetSuppressPickupNotices(true)
	ply.noSound = true
	ply.subClass = nil

	ply:Give("weapon_hands_sh")

	local class = PickClass()
	local splashName = class.name

	local ok, ret = pcall(class.kit, ply)
	if ok and isstring(ret) then splashName = ret end

	-- remember the actual class STRING the kit applied (homigrad
	-- stores it in PlayerClassName) so the wake-up restore can hand
	-- back the same identity
	ply.WildcardClass = ply.PlayerClassName

	ply.wcClass = splashName
	ply.wcRolledAt = CurTime()

	-- the splash
	net.Start("wildcard_class")
		net.WriteString(splashName)
		net.WriteColor(class.color or Color(255, 255, 255))
	net.Send(ply)
	ply:ChatPrint("[Wildcard] You are: " .. splashName)

	ply:SelectWeapon("weapon_hands_sh")

	timer.Simple(0.1, function()
		if IsValid(ply) then ply.noSound = false end
	end)
	ply:SetSuppressPickupNotices(false)
end

-- =====================================================================
-- mode skeleton (hl2dm structure)
-- =====================================================================
function MODE:ClearPlayerRoles()
	for _, ply in player.Iterator() do
		ply:SetNWString("PlayerRole", "")
		ply.subClass = nil
		ply.wcClass = nil
	end
end

function MODE:Intermission()
	game.CleanUpMap()

	for i, ply in player.Iterator() do
		ply:SetupTeam(ply:Team())
	end

	net.Start("wildcard_start")
	net.Broadcast()
end

function MODE:CheckAlivePlayers()
	return zb:CheckAliveTeams(true)
end

function MODE:ShouldRoundEnd()
	local endround, winner = zb:CheckWinner(self:CheckAlivePlayers())
	return endround
end

function MODE:RoundStart()
end

function MODE:GetPlySpawn(ply)
end

function MODE:GiveEquipment()
	timer.Simple(0.1, function()
		-- deal only the un-kitted: at round start that's everyone; on
		-- the mid-round GiveEquipment ZCity fires when someone JOINS,
		-- it's just the newcomer - the rest keep their identities
		local players_alive = zb:CheckPlaying()
		for _, ply in RandomPairs(players_alive) do
			RollFor(ply)
		end
	end)
end

function MODE:RoundThink()
end

function MODE:GetTeamSpawn()
	return zb.TranslatePointsToVectors(zb.GetMapPoints("HMCD_TDM_T")), zb.TranslatePointsToVectors(zb.GetMapPoints("HMCD_TDM_CT"))
end

function MODE:CanSpawn()
end

function MODE:EndRound()
	local team0, team1, winnerteam = 0, 0, 0
	for _, ply in player.Iterator() do
		if ply:Alive() and ply:Team() == 0 then
			team0 = team0 + 1
		elseif ply:Alive() and ply:Team() == 1 then
			team1 = team1 + 1
		end
	end
	if team0 > team1 then
		winnerteam = 0
	elseif team1 > team0 then
		winnerteam = 1
	else
		winnerteam = 2
	end

	self:ClearPlayerRoles()
	timer.Simple(2, function()
		net.Start("wildcard_roundend")
			net.WriteUInt(winnerteam, 4)
		net.Broadcast()
	end)
end

function MODE:PlayerDeath(ply)
end

function MODE:CanLaunch()
	return #zb:CheckPlaying() >= 2
end

-- respawns mid-round re-roll a fresh identity - but ONCE per round
-- per player: ZCity fires PlayerSpawn on fake-up/revival flows too,
-- which was rerolling living players' identities mid-round
hook.Add("PlayerSpawn", "Wildcard_Reroll", function(ply)
	if not (zb and zb.CROUND == "wildcard") then return end
	if zb.ROUND_STATE ~= 1 then return end
	if not zb.ROUND_BEGIN or (CurTime() - zb.ROUND_BEGIN) < 5 then return end

	-- already kitted this round: keep the identity you were dealt

	timer.Simple(0.5, function()
		if IsValid(ply) and zb.CROUND == "wildcard" then
			RollFor(ply)
		end
	end)
end)


-- the dealt flag lives exactly one round: cleared at round end so the
-- next intermission deals everyone fresh. No timestamps - deal order
-- vs round-stamp order was the hole that let mid-round re-deals through.
hook.Add("ZB_EndRound", "Wildcard_ClearDealt", function()
	for _, ply in player.Iterator() do
		ply.WildcardDealt = nil
		ply.WildcardClass = nil
	end
end)
