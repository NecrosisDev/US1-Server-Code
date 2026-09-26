-- SUPPORT band: team medic (item B4). A bot carrying a bandage/tourniquet/
-- medkit walks to a downed or heavily-bleeding ally (team modes, plus
-- masscasualty shooters healing each other via ctx:AllyOf()'s MODE-band
-- override -- modes/sv_masscasualty.lua's shooterAllyOf) and holds IN_ATTACK2
-- on them until their bleed stops or 6s pass.
--
-- Verified against weapons/weapon_bandage_sh.lua (research pass, this
-- session): SecondaryAttack traces `hg.eyeTrace(self:GetOwner()).Entity` and
-- calls `self:Heal(self.healbuddy, self.mode)` on whatever it hits -- i.e.
-- IN_ATTACK2 heals whoever the bot is looking at, exactly the brief's
-- IN_ATTACK2-applies-to-eyeTrace-target contract. hg.eyeTrace's default trace
-- distance is 60 units (homigrad/sh_utility.lua's hg.eye() call), so the
-- treat-range gate below is a closer stand-off (90u dwell distance, walking
-- the last stretch) rather than the exact 60u so imperfect aim/lerp on
-- SetEyeAngles doesn't leave the bot just outside trace range while it
-- thinks it is close enough.
-- org.arterialwounds / org.wounds field shapes reused from sv_survival.lua's
-- already-verified WHITELIST/medicalPriority reads (same file header
-- citation, homigrad/organism/tier_1/modules/sv_blood.lua).
--
-- One medic per patient: `claims` is a weak-keyed patient->medic map, not
-- per-brain state, since a patient (including a human) has no zc_bots brain.

local RB = hg.botdriver.RegisterBehavior
local lib = hg.botdriver.lib

hg.botdriver.DeclareBrainState("medic", { fields = { "medicPatient", "medicStartAt", "medicCounted", "medicGaveUp" } })

-- A patient this medic treated for the full MAX_TREAT_TIME without the bleed
-- stopping (e.g. downed from pain/unconsciousness, which a bandage cannot
-- fix) is skipped this long, instead of being re-claimed on the very next
-- decision and "treated" forever (2026-09-25 review).
local GIVE_UP_COOLDOWN = 30

local MEDIC_RANGE = 500
local NO_ENEMY_WINDOW = 4
local TREAT_RANGE = 90
local MAX_TREAT_TIME = 6

local MED_CLASSES = {
	weapon_bandage_sh = true, weapon_bigbandage_sh = true,
	weapon_tourniquet = true, weapon_medkit_sh = true,
}

local claims = setmetatable({}, { __mode = "k" }) -- patient (Entity) -> medic (Entity)

local function carriedMedical(bot)
	for _, wep in ipairs(bot:GetWeapons()) do
		if IsValid(wep) and wep.Heal and MED_CLASSES[wep:GetClass()] then return wep end
	end
	return nil
end

local function woundBleed(org)
	if not istable(org) or not istable(org.wounds) then return 0 end
	local bleed = 0
	for _, wound in pairs(org.wounds) do
		bleed = bleed + (istable(wound) and (wound[1] or 0) or 0)
	end
	return bleed
end

local function needsTreatment(ent)
	if not IsValid(ent) or not ent:IsPlayer() or not ent:Alive() then return false end
	if hg.botdriver.IsDowned(ent) then return true end
	local org = ent.organism
	if istable(org) and istable(org.arterialwounds) and #org.arterialwounds > 0 then return true end
	local cfg = hg.botdriver.GetSurvivalConfig()
	return woundBleed(org) >= (cfg and cfg.bleed_urgent or 15)
end

local function bleedStopped(ent)
	if not IsValid(ent) then return true end
	if hg.botdriver.IsDowned(ent) then return false end
	local org = ent.organism
	if istable(org) and istable(org.arterialwounds) and #org.arterialwounds > 0 then return false end
	return woundBleed(org) <= 0
end

local function releaseClaim(brain, patient)
	if claims[patient] then claims[patient] = nil end
	brain.medicPatient = nil
	brain.medicStartAt = nil
	brain.medicCounted = nil
end

-- Nearest unclaimed (or self-claimed) ally patient within MEDIC_RANGE.
local function findPatient(bot, brain, allyOf)
	if IsValid(brain.medicPatient) and needsTreatment(brain.medicPatient)
		and claims[brain.medicPatient] == bot then
		return brain.medicPatient
	end
	releaseClaim(brain, brain.medicPatient)

	local pos = bot:GetPos()
	local best, bestDistSqr
	local gaveUp = brain.medicGaveUp
	local now = CurTime()
	for _, ent in ipairs(hg.botdriver.Actors()) do
		if ent ~= bot and allyOf(ent) and needsTreatment(ent)
			and not (gaveUp and (gaveUp[ent] or 0) > now) then
			local claimant = claims[ent]
			if not IsValid(claimant) or claimant == bot then
				local distSqr = pos:DistToSqr(ent:GetPos())
				if distSqr <= MEDIC_RANGE * MEDIC_RANGE and (not bestDistSqr or distSqr < bestDistSqr) then
					best, bestDistSqr = ent, distSqr
				end
			end
		end
	end
	if best then
		claims[best] = bot
		brain.medicPatient = best
	end
	return best
end

RB({
	name = "support.medic_ally",
	band = "SUPPORT",
	order = 8,
	finalize = { path = true },
	CanRun = function(ctx)
		if ctx.downed then return false end
		if ctx.now - (ctx.brain.lastSeenTime or -math.huge) < NO_ENEMY_WINDOW then return false end
		if IsValid(ctx:AcquireTarget()) then return false end
		local allyOf = ctx:AllyOf()
		if not isfunction(allyOf) then return false end
		if not carriedMedical(ctx.bot) then return false end
		return IsValid(findPatient(ctx.bot, ctx.brain, allyOf))
	end,
	Run = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		local patient = brain.medicPatient
		if not IsValid(patient) or not needsTreatment(patient) then
			releaseClaim(brain, patient)
			return false
		end

		local med = carriedMedical(bot)
		if not IsValid(med) then
			releaseClaim(brain, patient)
			return false
		end
		if bot:GetActiveWeapon() ~= med then
			bot:SelectWeapon(med:GetClass())
			return true
		end

		local dist = bot:GetPos():Distance(patient:GetPos())
		if dist > TREAT_RANGE then
			brain.medicStartAt = nil
			lib.PathTo(bot, brain, patient:GetPos(), now, 1)
			lib.LookAt(bot, brain, patient:GetPos() + Vector(0, 0, 40), "medic", false)
			return true
		end

		brain.medicStartAt = brain.medicStartAt or now
		-- Medkit: match the mode to what the patient actually has (same
		-- selection as self-treatment in sv_brain.lua's lib.MedicalCheck;
		-- weapon_medkit_sh.lua modeValues[1..6], mode is the plain server field).
		if med:GetClass() == "weapon_medkit_sh" and istable(med.modeValues) then
			local mv, porg = med.modeValues, patient.organism
			local pArterial = istable(porg) and istable(porg.arterialwounds) and #porg.arterialwounds > 0
			local pBleed = woundBleed(porg)
			local pInternal = istable(porg) and tonumber(porg.internalBleed) or 0
			local want = med.mode or 1
			if pArterial and (mv[4] or 0) > 0 then want = 4
			elseif pBleed > 0 and (mv[1] or 0) > 0 then want = 1
			elseif pInternal > 0 and (mv[3] or 0) > 0 then want = 3
			elseif (mv[1] or 0) > 0 then want = 1 end
			if med.mode ~= want then med.mode = want end
		end
		if not brain.medicCounted then
			brain.medicCounted = true
			hg.botdriver.stats = hg.botdriver.stats or {}
			hg.botdriver.stats.allyTreats = (hg.botdriver.stats.allyTreats or 0) + 1
		end
		brain.path = nil
		brain.actionPolicy = { owner = "medic_ally", lockMove = true }
		lib.LookAt(bot, brain, patient:GetPos() + Vector(0, 0, 40), "medic", true)
		brain.buttons = bit.bor(brain.buttons or 0, IN_ATTACK2)

		if bleedStopped(patient) then
			releaseClaim(brain, patient)
		elseif now - brain.medicStartAt >= MAX_TREAT_TIME then
			brain.medicGaveUp = brain.medicGaveUp or setmetatable({}, { __mode = "k" })
			brain.medicGaveUp[patient] = now + GIVE_UP_COOLDOWN
			releaseClaim(brain, patient)
		end
		return true
	end,
})

hook.Add("PlayerDisconnected", "zc_bots_medic_release", function(ply)
	claims[ply] = nil
end)
