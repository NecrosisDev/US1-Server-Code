local MODE = MODE

MODE.base      = "hmcd"
MODE.name      = "activeshooter"
MODE.PrintName = "Active Shooter"
MODE.Chance    = 0
MODE.ROUND_TIME = 300
MODE.ForBigMaps = false
MODE.GuiltDisabled = true

function MODE:CanLaunch()
	return true
end

function MODE.GuiltCheck(Attacker, Victim, add, harm, amt)
	return 1, true
end

function MODE:SubModes()
	return {"activeshooter"}
end

function MODE:AfterBaseInheritance()
	-- Clear inherited Types so queue doesn't show standard/gunfreezone/wildwest combos
	MODE.Types = {}

	-- Roles
	MODE.Roles = MODE.Roles or {}
	MODE.Roles.activeshooter = {
		traitor = {
			name      = "Active Shooter",
			color     = Color(190, 0, 0),
			objective = "You've had enough.",
		},
		gunner = {
			name      = "Bystander",
			color     = Color(0, 120, 190),
			objective = "Active shooter in the area. Run. Hide. Fight.",
		},
		innocent = {
			name      = "Bystander",
			color     = Color(0, 120, 190),
			objective = "Active shooter in the area. Run. Hide. Fight.",
		},
	}

	-- Add to hmcd's client-side tables so the title screen works
	-- These need to be on the hmcd table since cl_homicide.lua references MODE.* which is hmcd
	local hmcd = zb.modes["hmcd"]
	if hmcd then
		hmcd.TypeSounds = hmcd.TypeSounds or {}
		hmcd.TypeSounds["activeshooter"] = "snd_jack_hmcd_psycho.mp3"

		hmcd.TypeNames = hmcd.TypeNames or {}
		hmcd.TypeNames["activeshooter"] = "Active Shooter"

		hmcd.TypeObjectives = hmcd.TypeObjectives or {}
		hmcd.TypeObjectives.activeshooter = {
			traitor = {
				objective = "You've had enough.",
				name = "the Active Shooter",
				color1 = Color(190, 0, 0),
				color2 = Color(190, 0, 0)
			},
			gunner = {
				objective = "Active shooter in the area. Run. Hide. Fight.",
				name = "a Bystander",
				color1 = Color(0, 120, 190),
				color2 = Color(0, 120, 190)
			},
			innocent = {
				objective = "Active shooter in the area. Run. Hide. Fight.",
				name = "a Bystander",
				color1 = Color(0, 120, 190),
				color2 = Color(0, 120, 190)
			},
		}
	end

	-- Types definition
	MODE.Types = MODE.Types or {}
	MODE.Types.activeshooter = {
		Chance         = 1,
		ChanceFunction = function() return 0 end,
		LootTable      = nil,
		Messages = {
			[3] = "Everyone is gone.",
			[1] = "The shooter has killed everyone.",
			[0] = "The shooter was stopped. The suspect is",
		},
		Message = "The shooter was ",
		TraitorLoot = function(ply)
			if not SERVER then return end
			local ar = ply:Give("weapon_ar15")
			if IsValid(ar) then
				ply:GiveAmmo(ar:GetMaxClip1() * 5, ar:GetPrimaryAmmoType(), true)
				hg.AddAttachmentForce(ply, ar, "holo1")
			end
			local p250 = ply:Give("weapon_p250")
			if IsValid(p250) then
				ply:GiveAmmo(p250:GetMaxClip1() * 5, p250:GetPrimaryAmmoType(), true)
			end
			ply:Give("weapon_sogknife")
			hg.AddArmor(ply, {"vest4", "helmet2"})
			ply.organism.recoilmul = 0.9
			local inv = ply:GetNetVar("Inventory") or {}
			inv["Weapons"] = inv["Weapons"] or {}
			inv["Weapons"]["hg_flashlight"] = true
			ply:SetNetVar("Inventory", inv)
		end,
		GunManLoot = function(ply)
			-- Bystanders spawn unarmed
		end,
		PoliceTime    = 90,
		PoliceAllowed = true,
		SkillIssue    = 4,
		PoliceEquipment = function(ply)
			if not SERVER then return end
			ply:SetPlayerClass("swat")
			local ar = ply:Give("weapon_ar15")
			if IsValid(ar) then
				ply:GiveAmmo(ar:GetMaxClip1() * 3, ar:GetPrimaryAmmoType(), true)
				hg.AddAttachmentForce(ply, ar, "holo1")
			end
			local glock = ply:Give("weapon_glock17")
			if IsValid(glock) then
				ply:GiveAmmo(glock:GetMaxClip1() * 3, glock:GetPrimaryAmmoType(), true)
			end
			ply:Give("weapon_medkit_sh")
			ply:Give("weapon_walkie_talkie")
			ply:Give("weapon_naloxone")
			ply:Give("weapon_painkillers")
			ply:Give("weapon_handcuffs")
			ply:Give("weapon_handcuffs_key")
			ply:Give("weapon_hg_tonfa")
			local taser = ply:Give("weapon_taser")
			if IsValid(taser) then
				ply:GiveAmmo(taser:GetMaxClip1() * 3, taser:GetPrimaryAmmoType(), true)
			end
			hg.AddArmor(ply, {"vest4", "helmet1"})
			local hands = ply:Give("weapon_hands_sh")
			ply:SetActiveWeapon(hands)
			local inv = ply:GetNetVar("Inventory") or {}
			inv["Weapons"] = inv["Weapons"] or {}
			inv["Weapons"]["hg_flashlight"] = true
			ply:SetNetVar("Inventory", inv)
			ply.organism.recoilmul = 0.7
			ply:SetNetVar("CurPluv", "pluvberet")
			zb.GiveRole(ply, "Police Officer", Color(15, 15, 255))
		end,
		PoliceText  = "Police have arrived. Active shooter situation.",
		PoliceSound = "snd_jack_hmcd_heli2.mp3",
	}
end
