local MODE = MODE

MODE.base      = "hmcd"
MODE.name      = "masscasualty"
MODE.PrintName = "Mass Casualty Event"
MODE.Chance    = 0.03
MODE.ROUND_TIME = 300
MODE.ForBigMaps = false
MODE.GuiltDisabled = true

function MODE:CanLaunch()
	return true
end

function MODE.GuiltCheck(Attacker, Victim, add, harm, amt)
	if Attacker.isTraitor then return 0, false end
	if Attacker.isPolice and Victim.isTraitor then return 0, false end
	return 1, true
end

function MODE:SubModes()
	return {"masscasualty"}
end

function MODE:AfterBaseInheritance()
	-- Clear inherited Types so queue doesn't show standard/gunfreezone/wildwest combos
	MODE.Types = {}

	-- Roles for title screen
	MODE.Roles = MODE.Roles or {}
	MODE.Roles.masscasualty = {
		traitor = {
			name      = "Mass Shooter",
			color     = Color(190, 0, 0),
			objective = "You and your cell are striking together.",
		},
		gunner = {
			name      = "Bystander",
			color     = Color(0, 120, 190),
			objective = "Multiple active shooters. Run. Hide. Fight.",
		},
		innocent = {
			name      = "Bystander",
			color     = Color(0, 120, 190),
			objective = "Multiple active shooters. Run. Hide. Fight.",
		},
	}

	-- Add to hmcd's client-side tables
	local hmcd = zb.modes["hmcd"]
	if hmcd then
		hmcd.TypeSounds = hmcd.TypeSounds or {}
		hmcd.TypeSounds["masscasualty"] = "snd_jack_hmcd_psycho.mp3"

		hmcd.TypeNames = hmcd.TypeNames or {}
		hmcd.TypeNames["masscasualty"] = "Mass Casualty Event"

		hmcd.TypeObjectives = hmcd.TypeObjectives or {}
		hmcd.TypeObjectives.masscasualty = {
			traitor = {
				objective = "You and your cell are striking together.",
				name = "a Mass Shooter",
				color1 = Color(190, 0, 0),
				color2 = Color(190, 0, 0)
			},
			gunner = {
				objective = "Multiple active shooters. Run. Hide. Fight.",
				name = "a Bystander",
				color1 = Color(0, 120, 190),
				color2 = Color(0, 120, 190)
			},
			innocent = {
				objective = "Multiple active shooters. Run. Hide. Fight.",
				name = "a Bystander",
				color1 = Color(0, 120, 190),
				color2 = Color(0, 120, 190)
			},
		}
	end

	MODE.Types = MODE.Types or {}
	MODE.Types.masscasualty = {
		Chance         = 1,
		ChanceFunction = function() return 0.03 end,
		LootTable      = nil,
		-- Force 3 traitors for this mode
		TraitorCount   = 3,
		Messages = {
			[3] = "Everyone is gone.",
			[1] = "The shooters have killed everyone.",
			[0] = "The shooters have been stopped.",
		},
		Message = "The shooters were ",
		TraitorLoot = function(ply)
			if not SERVER then return end
			-- AK with EOTech and 4 mags
			local rifle = ply:Give("weapon_akm")
			if IsValid(rifle) then
				ply:GiveAmmo(rifle:GetMaxClip1() * 4, rifle:GetPrimaryAmmoType(), true)
				hg.AddAttachmentForce(ply, rifle, "holo1")
			end
			-- P220 with 2 spare mags
			local p220 = ply:Give("weapon_p220")
			if IsValid(p220) then
				ply:GiveAmmo(p220:GetMaxClip1() * 2, p220:GetPrimaryAmmoType(), true)
			end
			ply:Give("weapon_sogknife")
			hg.AddArmor(ply, {"vest3", "helmet2"})
			ply.organism.recoilmul = 0.9
			local inv = ply:GetNetVar("Inventory") or {}
			inv["Weapons"] = inv["Weapons"] or {}
			inv["Weapons"]["hg_flashlight"] = true
			ply:SetNetVar("Inventory", inv)
		end,
		GunManLoot = function(ply)
			-- Bystanders unarmed
		end,
		PoliceTime    = 30,
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
		PoliceText  = "Police have arrived. Mass casualty event.",
		PoliceSound = "snd_jack_hmcd_heli2.mp3",
	}
end
