-- ============================================================
--  HYDROXOCOBALAMIN (vitamin B12a) - cyanide antidote
-- ------------------------------------------------------------
--  Binds cyanide into harmless cyanocobalamin. Reverses BOTH of
--  ZCity's cyanide paths:
--    * org.poison3      - HCN gas (traitor's cyanide canister cloud)
--    * org.Poison_KCN   - ingested potassium cyanide (poisoned consumables)
--  and restores the organism's oxygen regen (cyanide zeroes
--  org.o2.regen and NOTHING else in the gamemode ever sets it back),
--  plus purges the accumulated HCN/KCN chemical load so one more
--  breath of gas doesn't instantly re-poison a rescued player.
--
--  Uses the decompression-needle autoinjector model. LMB = inject
--  yourself, RMB = inject someone else (works on downed/ragdolled
--  players - that's the whole point, cyanide KOs people).
--  Single use, like naloxone.
-- ============================================================
if SERVER then AddCSLuaFile() end
SWEP.Base = "weapon_bandage_sh"
SWEP.PrintName = "Hydroxocobalamin"
SWEP.Instructions = "Vitamin B12a - binds cyanide into harmless cyanocobalamin. LMB to inject yourself, RMB to inject someone else. Reverses cyanide poisoning (gas or ingested) so the lungs can work again."
SWEP.Category = "ZCity Medicine"
SWEP.Spawnable = true
SWEP.Primary.Wait = 1
SWEP.Primary.Next = 0
SWEP.HoldType = "normal"
SWEP.ViewModel = ""
SWEP.WorldModel = "models/bloocobalt/l4d/items/w_eq_adrenaline.mdl"
if CLIENT then
	SWEP.WepSelectIcon = Material("vgui/icons/ico_decompression_needle.png")
	SWEP.IconOverride = "vgui/icons/ico_decompression_needle.png"
	SWEP.BounceWeaponIcon = false
end
SWEP.AutoSwitchTo = false
SWEP.AutoSwitchFrom = false
SWEP.Slot = 3
SWEP.SlotPos = 1
SWEP.WorkWithFake = true
SWEP.offsetVec = Vector(3, -2.5, -1)
SWEP.offsetAng = Angle(-30, 20, -90)
SWEP.ModelScale = 0.7
SWEP.modeNames = {
	[1] = "hydroxocobalamin"
}

SWEP.DeploySnd = ""
SWEP.HolsterSnd = ""

SWEP.showstats = false

function SWEP:InitializeAdd()
	self:SetHold(self.HoldType)

	self.modeValues = {
		[1] = 1
	}
end

SWEP.modeValuesdef = {
	[1] = 1,
}

local hg_healanims = ConVarExists("hg_healanims") and GetConVar("hg_healanims") or CreateConVar("hg_healanims", 0, FCVAR_REPLICATED + FCVAR_ARCHIVE, "Toggle heal/food animations", 0, 1)

function SWEP:Think()
	self:SetBodyGroups("11")
	if not self:GetOwner():KeyDown(IN_ATTACK) and hg_healanims:GetBool() then
		self:SetHolding(math.max(self:GetHolding() - 4, 0))
	end
end

function SWEP:Animation()
	local hold = self:GetHolding()
	self:BoneSet("r_upperarm", vector_origin, Angle(0, -hold + (100 * (hold / 100)), 0))
	self:BoneSet("r_forearm", vector_origin, Angle(-hold / 6, -hold * 2, -15))
end

function SWEP:DrawWorldModel()
	self.model = IsValid(self.model) and self.model or ClientsideModel(self.WorldModel)
	local WorldModel = self.model
	local owner = self:GetOwner()
	WorldModel:SetNoDraw(true)
	WorldModel:SetModelScale(self.ModelScale or 1)
	if IsValid(owner) then
		local offsetVec = self.offsetVec
		local offsetAng = self.offsetAng
		local boneid = owner:LookupBone(((owner.organism and owner.organism.rarmamputated) or (owner.zmanipstart ~= nil and owner.zmanipseq == "interact" and not owner.organism.larmamputated)) and "ValveBiped.Bip01_L_Hand" or "ValveBiped.Bip01_R_Hand")
		if not boneid then return end
		local matrix = owner:GetBoneMatrix(boneid)
		if not matrix then return end
		local newPos, newAng = LocalToWorld(offsetVec, offsetAng, matrix:GetTranslation(), matrix:GetAngles())
		WorldModel:SetPos(newPos)
		WorldModel:SetAngles(newAng)
		WorldModel:SetupBones()
	else
		WorldModel:SetPos(self:GetPos())
		WorldModel:SetAngles(self:GetAngles())
	end

	WorldModel:DrawModel()
end

function SWEP:OwnerChanged()
	local owner = self:GetOwner()
	if IsValid(owner) and owner:IsNPC() then
		self:SpawnGarbage(nil, nil, nil, nil, "2211")
		self:NPCHeal(owner, 0.1, "snd_jack_hmcd_needleprick.wav")
	end
end

if SERVER then
	function SWEP:Heal(ent, mode)
		if ent:IsNPC() then
			self:SpawnGarbage(nil, nil, nil, nil, "2211")
			self:NPCHeal(ent, 0.1, "snd_jack_hmcd_needleprick.wav")
			return
		end

		local org = ent.organism
		if not org then return end

		local owner = self:GetOwner()
		if ent == hg.GetCurrentCharacter(owner) and hg_healanims:GetBool() then
			self:SetHolding(math.min(self:GetHolding() + 4, 100))

			if self:GetHolding() < 100 then return end
		end

		-- resolve the actual PLAYER behind whatever we injected (player or
		-- their ragdoll) - the chemical accumulation lives on the player
		local ply = ent:IsPlayer() and ent or (IsValid(ent.ply) and ent.ply or org.owner)

		local entOwner = IsValid(owner.FakeRagdoll) and owner.FakeRagdoll or owner
		entOwner:EmitSound("snd_jack_hmcd_needleprick.wav", 60, math.random(95, 105))

		-- was there any cyanide on board? (either active poisoning, or a
		-- sub-threshold gas/ingestion load still accumulating)
		local hadCyanide = (org.poison3 ~= nil) or (org.Poison_KCN ~= nil)
		if not hadCyanide and IsValid(ply) and GetChemicalOfPlayer then
			hadCyanide = GetChemicalOfPlayer(ply, "HCN") > 0 or GetChemicalOfPlayer(ply, "KCN") > 0
		end

		-- BIND THE CYANIDE: clear both poison paths + the accumulated load
		org.poison3 = nil
		org.poison3notificate = nil
		org.Poison_KCN = nil
		if IsValid(ply) and SetChemicalToPlayer then
			SetChemicalToPlayer(ply, "HCN", 0)
			SetChemicalToPlayer(ply, "KCN", 0)
		end

		if hadCyanide then
			-- let the lungs work again: cyanide sets o2.regen to 0 every tick
			-- and nothing else ever restores it (4 is the organism default)
			if (org.o2.regen or 0) <= 0 then org.o2.regen = 4 end
			-- one saving gasp - enough O2 to climb out of the critical band,
			-- NOT a full heal; damage already done stays done
			org.o2[1] = math.max(org.o2[1] or 0, 12)

			local victim = org.owner or ply
			if IsValid(victim) then
				local sndEnt = IsValid(victim.FakeRagdoll) and victim.FakeRagdoll or victim
				sndEnt:EmitSound((ThatPlyIsFemale and ThatPlyIsFemale(victim))
					and "breathing/inhale/female/inhale_0" .. math.random(5) .. ".wav"
					or "breathing/inhale/male/inhale_0" .. math.random(4) .. ".wav", 65)
				if victim.Notify then
					victim:Notify("Your chest loosens - you can breathe again. Your skin flushes red.", true, "hydroxo1", 4)
				end
				if victim ~= owner and owner.ChatPrint then
					owner:ChatPrint("The B12a binds the cyanide - they're breathing again.")
				end
			end
		else
			if owner.ChatPrint then owner:ChatPrint("The injection finds no cyanide to bind.") end
		end

		self.modeValues[1] = 0

		-- the traitor can still taint medical items - honour it like naloxone does
		if self.poisoned2 then
			org.poison4 = CurTime()

			self.poisoned2 = nil
		end

		if self.modeValues[1] == 0 then
			owner:SelectWeapon("weapon_hands_sh")
			self:SpawnGarbage(nil, nil, nil, nil, "2211")
			self:Remove()
		end
	end
end
