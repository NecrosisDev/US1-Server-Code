-- Shared bot survival interpreter, ported from Trauma's sv_survival.lua.
--
-- Organism field reads verified against US1's
-- homigrad/organism/tier_1/*.lua (rule 5):
--   org.blood (number, 5000 base), org.bleed, org.wounds (table),
--   org.arterialwounds (table), org.pain, org.otrub, org.canmove, org.alive,
--   org.stamina[1] / org.stamina.max (modules/sv_stamina.lua),
--   org.o2[1] / org.o2.range (modules/sv_lungs.lua, modules/sv_blood.lua).
-- Trauma's org.stamina.max / org.o2.range reads carry over unchanged; the
-- shared object shape is identical on this fork.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}

local PRIORITY_RANK = { stable = 0, caution = 1, urgent = 2, critical = 3 }

-- org.blood's base/max (homigrad/organism/tier_1/modules/sv_blood.lua:28 --
-- initialised to and regenerated toward 5000). Vanilla bot:Health() is not
-- the condition model on this fork: sv_organism.lua resets it to 100 on every
-- spawn and only nudges it via a slow regen tick, so Health()/MaxHealth reads
-- ~1.0 however badly hurt the bot is. Blood is the real fraction.
local ORGANISM_BLOOD_MAX = 5000

local function numberOrNil(value)
	value = tonumber(value)
	if value ~= nil and value == value then return value end
	return nil
end

local function clamp01(value)
	return math.Clamp(numberOrNil(value) or 0, 0, 1)
end

function hg.botdriver.MovementSuppression(ply)
	if not IsValid(ply) then return false, nil, false end
	if IsValid(ply.FakeRagdoll) then return true, 0, true end
	if IsValid(ply.FakeRagdollOld) then return true, 50, true end
	return false, nil, false
end

local function woundTotal(wounds)
	if not istable(wounds) then return 0, 0 end
	local count, bleed = 0, 0
	for _, wound in pairs(wounds) do
		count = count + 1
		if istable(wound) then
			bleed = bleed + (numberOrNil(wound[1]) or 0)
		else
			bleed = bleed + (numberOrNil(wound) or 0)
		end
	end
	return count, bleed
end

----------------------------------------------------------------------
-- Self-treatment whitelist (rule 5): bandage / big bandage / tourniquet
-- (only meaningful against an open arterial bleed) / medkit / painkillers
-- (pain relief) / consumables (satiety, see below). Never morphine -- it is
-- deliberately absent from this list, unlike .Heal which morphine also
-- exposes.
--
-- weapon_painkillers (Task 4, 2026-09-22): verified at
-- work/main-design-source/lua/weapons/weapon_painkillers.lua --
-- `SWEP.Base = "weapon_bandage_sh"`, its own SWEP:Heal adds to
-- `org.analgesiaAdd` (not blood/wounds). Verified effect chain (organism/
-- tier_1/modules/sv_pain.lua:104,116-118): `org.pain = org.avgpain * ... *
-- max(1 - org.analgesia, 0)` and `org.analgesiaAdd > 0` ramps `org.analgesia`
-- toward 4 over ~15s -- i.e. painkillers are the correct real-world response
-- to PAIN specifically, not bleeding, so they get their own condition below
-- keyed on `org.pain` rather than the bleed/blood terms the other three use.
--
-- weapon_bigconsumable / weapon_smallconsumable (Task 4, 2026-09-22):
-- verified at work/main-design-source/lua/weapons/ -- both `SWEP.Base =
-- "weapon_bandage_sh"`/"weapon_bigconsumable" respectively, both add to
-- `org.satiety` (food, not a wound). Verified effect (organism/tier_1/
-- modules/sv_metabolism.lua:56-61): satiety > 0 gives a small ALWAYS-ON blood
-- + health regen bonus regardless of the `hg_hungersystem` convar (which
-- defaults OFF and only gates the separate hunger-PAIN penalty, verified same
-- file lines 22-41) -- so eating is a real, if low-stakes, passive benefit.
-- Wired at the lowest priority tier (never above wound care) and only
-- self-treated when otherwise idle (see the "hungry" caution reason below).
----------------------------------------------------------------------

local DRESSING = { weapon_bandage_sh = true, weapon_bigbandage_sh = true }
local WOUND_CARE = { weapon_bandage_sh = true, weapon_bigbandage_sh = true, weapon_tourniquet = true, weapon_medkit_sh = true }
local PAIN_RELIEF = { weapon_painkillers = true }
local NOURISHMENT = { weapon_bigconsumable = true, weapon_smallconsumable = true }
local WHITELIST = {}
for class in pairs(WOUND_CARE) do WHITELIST[class] = true end
for class in pairs(PAIN_RELIEF) do WHITELIST[class] = true end
for class in pairs(NOURISHMENT) do WHITELIST[class] = true end

local function medicalPriority(org, class)
	if not WHITELIST[class] then return 0 end
	local cfg = hg.botdriver.GetSurvivalConfig()
	local _, bleed = woundTotal(org and org.wounds)
	local arterial = istable(org and org.arterialwounds) and #org.arterialwounds > 0
	local p = 0
	if arterial and class == "weapon_tourniquet" then p = math.max(p, 3) end
	if bleed >= 10 then
		if DRESSING[class] then p = math.max(p, 3)
		elseif class == "weapon_tourniquet" then p = math.max(p, 2) end
	end
	if (tonumber(org and org.blood) or 99999) < 3600 and class == "weapon_medkit_sh" then
		p = math.max(p, 3)
	end
	if PAIN_RELIEF[class] then
		local pain = tonumber(org and org.pain)
		if pain and pain >= cfg.pain_caution then p = math.max(p, 1) end
	end
	if NOURISHMENT[class] then
		local satiety = tonumber(org and org.satiety)
		if satiety ~= nil and satiety < cfg.satiety_caution then p = math.max(p, 1) end
	end
	return p
end

function hg.botdriver.BestCarriedMedical(bot)
	if not IsValid(bot) then return nil end
	local org = bot.organism
	local best, bestPri
	for _, wep in ipairs(bot:GetWeapons()) do
		local class = IsValid(wep) and wep.Heal and wep:GetClass() or nil
		if class and WHITELIST[class] then
			local p = medicalPriority(org, class)
			if p > 0 and (not bestPri or p > bestPri) then best, bestPri = wep, p end
		end
	end
	return best
end

----------------------------------------------------------------------
-- Threat/objective interpreter
----------------------------------------------------------------------

local function visibleHostile(bot, brain, now)
	local cfg = hg.botdriver.GetSurvivalConfig()
	local lib = hg.botdriver.lib
	local isEnemy = hg.botdriver.EnemyOf and hg.botdriver.EnemyOf(bot)
	if not isfunction(isEnemy) or not lib or not lib.VisualContact then return nil end

	local function hostileStanding(ent)
		if not IsValid(ent) or ent == bot then return false end
		if bot:GetPos():DistToSqr(ent:GetPos()) > cfg.hostile_near_range * cfg.hostile_near_range then return false end
		if not ent:IsPlayer() then return false end -- NPC targeting dropped (rule 1)
		return ent:Alive() and not hg.botdriver.IsDowned(ent) and isEnemy(ent)
	end

	local cached = brain.survivalVisibleHostile
	if now < (brain.survivalThreatScanAt or 0) then
		if hostileStanding(cached) then return cached end
		return nil
	end
	brain.survivalThreatScanAt = now + cfg.threat_scan_interval
	brain.survivalVisibleHostile = nil

	local function candidate(ent, focused)
		if not hostileStanding(ent) then return nil end
		return lib.VisualContact(bot, ent, brain, focused == true, now) and ent or nil
	end

	local found = candidate(brain.target, true) or candidate(brain.attackedBy, true)
	if not IsValid(found) then
		for _, ent in ipairs(hg.botdriver.Actors()) do
			found = candidate(ent, false)
			if IsValid(found) then break end
		end
	end

	brain.survivalVisibleHostile = found
	return found
end

local function nearbyAllies(bot)
	local count = 0
	local allyRange = hg.botdriver.GetSurvivalConfig().ally_near_range
	local isAlly = hg.botdriver.AllyOf and hg.botdriver.AllyOf(bot)
	if not isfunction(isAlly) then return 0 end
	for _, ent in ipairs(hg.botdriver.Actors()) do
		if ent ~= bot and ent:IsPlayer() and ent:Alive() and isAlly(ent)
			and bot:GetPos():DistToSqr(ent:GetPos()) <= allyRange * allyRange then
			count = count + 1
		end
	end
	return count
end

local function setPriority(state, priority, reason, action, confidence)
	if (PRIORITY_RANK[priority] or 0) <= (PRIORITY_RANK[state.priority] or 0) then return end
	state.priority = priority
	state.reason = reason
	state.recommended = action or reason
	state.confidence = confidence or state.confidence or 0.6
end

-- 2026-09-25 (owner verdict: bots "wouldn't respond to combat"): the
-- break-contact and outnumbered retreats run in the SURVIVAL band, before
-- COMBAT, drop the target and walk away every decision -- a hurt or
-- outnumbered bot with default aggression never returned fire. Both now stand
-- and fight while the bot is being hit by an attacker it can see (and it has
-- something to fight with); they still retreat once it is not under fire.
local RETURN_FIRE_WINDOW = 1.5

function hg.botdriver.UnderFireFromVisible(bot, brain, now)
	local attacker = brain and brain.attackedBy
	if not IsValid(attacker) or attacker == bot then return false end
	if now - (brain.attackedAt or -math.huge) > RETURN_FIRE_WINDOW then return false end
	if hg.botdriver.EntityAlive and not hg.botdriver.EntityAlive(attacker) then return false end
	if not (hg.botdriver.CanFight and hg.botdriver.CanFight(bot)) then return false end
	local lib = hg.botdriver.lib
	return (lib and lib.CanSeeTarget and lib.CanSeeTarget(bot, attacker)) == true
end

function hg.botdriver.SurvivalPolicyFor(bot)
	local cfg = hg.botdriver.GetSurvivalConfig()
	return {
		allowObjectiveUnderDanger = cfg.allow_objective_under_danger ~= false,
		criticalSurvivalAlwaysPreempts = cfg.critical_survival_always_preempts ~= false,
		survivalPreemptsSoft = cfg.survival_preempts_soft ~= false,
	}
end

local function objectiveState(brain, now)
	local active = isvector(brain.objectivePos) and now <= (brain.objectiveExpire or 0)
	return {
		active = active,
		priority = active and (brain.objectivePriority or "soft") or "none",
	}
end

local function objectiveAllowed(state, policy)
	if not state.objective.active then return true end
	if state.priority == "critical" then return false end
	if state.objective.priority == "hard" then return policy.allowObjectiveUnderDanger ~= false end
	if state.priority == "urgent" and policy.survivalPreemptsSoft ~= false then return false end
	return true
end

function hg.botdriver.BuildSurvivalState(bot, brain, now, modePolicy)
	modePolicy = modePolicy or hg.botdriver.SurvivalPolicyFor(bot)
	local cfg = hg.botdriver.GetSurvivalConfig()
	local org = bot.organism
	local maxHealth = math.max(bot.GetMaxHealth and bot:GetMaxHealth() or 100, 1)
	local woundCount, bleed = woundTotal(org and org.wounds)
	local arterialCount, arterialBleed = woundTotal(org and org.arterialwounds)
	woundCount = woundCount + arterialCount
	bleed = bleed + arterialBleed * 2

	local stamina = org and istable(org.stamina) and org.stamina or nil
	local staminaValue = stamina and numberOrNil(stamina[1]) or nil
	local staminaMax = stamina and math.max(numberOrNil(stamina.max) or numberOrNil(stamina.range) or staminaValue or 1, 1) or nil
	local oxygen = org and istable(org.o2) and numberOrNil(org.o2[1]) or nil
	local bestGun = hg.botdriver.BestGun and hg.botdriver.BestGun(bot) or nil
	local medicine = hg.botdriver.BestCarriedMedical(bot)
	local objective = objectiveState(brain, now)
	local hostile = visibleHostile(bot, brain, now)

	local blood = org and numberOrNil(org.blood) or nil
	local pain = org and numberOrNil(org.pain) or nil
	local satiety = org and numberOrNil(org.satiety) or nil
	local moveSuppressed, moveSpeedCap = hg.botdriver.MovementSuppression(bot)
	local state = {
		at = now,
		priority = "stable",
		reason = "clear",
		recommended = "continue",
		confidence = 0.35,
		body = {
			alive = bot:Alive(),
			downed = hg.botdriver.IsDowned(bot),
			unconscious = org and org.otrub == true or false,
			healthFrac = blood and clamp01(blood / ORGANISM_BLOOD_MAX) or clamp01(bot:Health() / maxHealth),
			blood = blood,
			bleed = bleed,
			woundCount = woundCount,
			pain = pain,
			oxygen = oxygen,
			staminaFrac = staminaValue and staminaMax and clamp01(staminaValue / staminaMax) or nil,
			canMove = not org or org.canmove ~= false,
			movementSuppressed = moveSuppressed,
			movementSpeedCap = moveSpeedCap,
		},
		threats = {
			visibleHostile = IsValid(hostile),
			recentDamage = isvector(brain.damagePos) and now < (brain.damageUntil or 0),
			nearbyAllies = nearbyAllies(bot),
		},
		capability = {
			canFight = hg.botdriver.CanFight and hg.botdriver.CanFight(bot) or false,
			hasGun = IsValid(bestGun),
			hasMedicine = IsValid(medicine),
			ammoRatio = 1,
			lowAmmo = false,
		},
		objective = objective,
	}

	if IsValid(bestGun) and bestGun.Clip1 then
		local clip = math.max(bestGun:Clip1() or 0, 0)
		local reserve = hg.botdriver.EffectiveReserve and hg.botdriver.EffectiveReserve(bot, bestGun) or 0
		local clipSize = (bestGun.GetMaxClip1 and bestGun:GetMaxClip1()) or (bestGun.Primary and bestGun.Primary.ClipSize) or math.max(clip, 1)
		state.capability.ammoRatio = math.Clamp((clip + reserve) / math.max(clipSize, 1), 0, 1)
	end
	state.capability.lowAmmo = state.capability.hasGun and state.capability.ammoRatio < cfg.low_ammo_frac

	if state.body.downed and state.threats.visibleHostile then
		setPriority(state, "critical", "downed_watched", "downed_survive", 0.9)
	elseif blood and blood < cfg.blood_critical then
		setPriority(state, "critical", "blood_critical", state.capability.hasMedicine and "self_treat" or "survive", 0.85)
	elseif state.threats.visibleHostile and not state.capability.canFight then
		setPriority(state, "critical", "unarmed_under_threat", "survive", 0.75)
	end

	if state.body.downed then
		setPriority(state, "urgent", "downed", "downed_survive", 0.8)
	end
	if bleed >= cfg.bleed_urgent or (blood and blood < cfg.blood_urgent) or state.body.healthFrac < cfg.health_urgent_frac then
		setPriority(state, "urgent", "wounded", state.capability.hasMedicine and "self_treat" or "survive", 0.75)
	end
	if state.threats.visibleHostile and state.capability.lowAmmo then
		setPriority(state, "urgent", "low_ammo_contact", "break_contact", 0.65)
	end
	-- Painkillers (Task 4, 2026-09-22): high pain alone (no bleed/blood
	-- emergency) is its own urgent reason, kept separate from "wounded" above
	-- so a bleeding-free but badly-hurting bot (e.g. broken limbs) still gets
	-- routed to self_treat -- setPriority's own rank guard means this is a
	-- no-op whenever "wounded" already claimed urgent this pass.
	if pain and pain >= cfg.pain_urgent then
		setPriority(state, "urgent", "high_pain", state.capability.hasMedicine and "self_treat" or "endure", 0.55)
	end

	if state.threats.recentDamage and not state.threats.visibleHostile then
		setPriority(state, "caution", "damage_memory", "investigate", 0.6)
	end
	if bleed > 0 and state.threats.nearbyAllies == 0 then
		setPriority(state, "caution", "wounded_isolated", "regroup", 0.45)
	end
	if (state.body.staminaFrac and state.body.staminaFrac < cfg.stamina_caution_frac)
		or (pain and pain > cfg.pain_caution)
		or (oxygen and oxygen < cfg.oxygen_caution) then
		setPriority(state, "caution", "body_degraded", "slow_down", 0.5)
	end
	-- Consumables (Task 4, 2026-09-22): satiety is a passive regen bonus, not
	-- a threat -- lowest tier, and only recommends self_treat when a
	-- consumable is actually carried (hasMedicine already reflects that via
	-- BestCarriedMedical's own NOURISHMENT check).
	if satiety and satiety < cfg.satiety_caution and state.capability.hasMedicine then
		setPriority(state, "caution", "hungry", "self_treat", 0.4)
	end

	state.allowModeObjective = objectiveAllowed(state, modePolicy)
	return state
end

-- Called from SURVIVAL band. Downed handling defers to hg.FakeUp via
-- lib.DownedDecide (sv_brain.lua); self-treat and disengage act directly.
function hg.botdriver.ApplySurvivalPreemption(bot, brain, now, state, policy)
	if not istable(state) then return false end
	policy = policy or hg.botdriver.SurvivalPolicyFor(bot)
	local lib = hg.botdriver.lib

	if state.body and state.body.downed and hg.botdriver.DownedDecide then
		local isEnemy = hg.botdriver.EnemyOf and hg.botdriver.EnemyOf(bot)
		if isfunction(isEnemy) and hg.botdriver.DownedDecide(bot, brain, now, isEnemy) then
			local stillDown = hg.botdriver.IsDowned(bot)
			if stillDown then
				state.handled = "downed"
				return true
			end
			state.body.downed = false
			state.handled = "getup"
		end
	end

	-- Item 5c: heavily hurt, low-aggression bots break contact to cover
	-- before re-engaging, instead of trading while low. Default aggression
	-- (no personality rolled yet) is treated as cautious (< 0.6).
	local personality = brain.personality
	local aggression = personality and personality.aggression or 0.5
	-- Item 1 (2026-09-22, DM endgame fix): this branch, run every SURVIVAL-band
	-- decision, was the actual defect -- a hurt bot's own low aggression kept
	-- it endlessly breaking contact to cover instead of finishing the fight,
	-- so DM never reached its real end condition (zb:CheckAlive(true) <= 1,
	-- modes/dm/sv_dm.lua). modes/sv_dm.lua's EndgameFactor (0 outside dm, only
	-- driven by the DM alive count/round clock) floors the effective
	-- aggression used by both this gate and the self-treat gate below.
	local endgame = hg.botdriver.EndgameFactor and hg.botdriver.EndgameFactor() or 0
	if hg.botdriver.HomicideRush and hg.botdriver.HomicideRush() then endgame = 1 end
	if endgame > aggression then aggression = endgame end
	-- 2026-09-26 (owner rule): ANY bot falls back to cover once it has taken
	-- too much damage -- unless the fight is close quarters or a face-off in
	-- direct line of sight (being shot right now by someone it can see), where
	-- turning away only gets it shot in the back. "Too much" scales with
	-- aggression: a hothead holds on longer than a cautious bot.
	local heavyHurt = (state.body.blood and state.body.blood < 3000) or (state.body.bleed or 0) >= 15
	local tooHurt = heavyHurt or (state.body.healthFrac or 1) < (0.74 - 0.14 * aggression)
		or (state.body.pain or 0) >= 60
	local fallbackThreat = IsValid(brain.attackedBy) and brain.attackedBy or brain.target
	local closeQuarters = IsValid(fallbackThreat) and bot:GetPos():DistToSqr(fallbackThreat:GetPos()) < 320 * 320
	if state.threats.visibleHostile and tooHurt and not closeQuarters and endgame < 0.85 and lib and lib.FindCover
		and not hg.botdriver.UnderFireFromVisible(bot, brain, now) then
		local threat = fallbackThreat
		if IsValid(threat) then
			if not brain.fellBackAt or now - brain.fellBackAt > 20 then
				brain.fellBackAt = now
				if hg.botdriver.duel and hg.botdriver.duel.End then hg.botdriver.duel.End(brain, 8) end
				if hg.botdriver.squad and hg.botdriver.squad.EmitLine then hg.botdriver.squad.EmitLine(bot, "hurt") end
				if hg.botdriver.radial and hg.botdriver.radial.OnCallout then hg.botdriver.radial.OnCallout(bot, brain, "help", 0.5) end
			end
			if now >= (brain.breakContactCoverAt or 0) then
				brain.breakContactCoverAt = now + 1.5
				brain.breakContactCoverPos = lib.KeepCover(bot, brain, "break", threat, 700)
			end
			if isvector(brain.breakContactCoverPos) then
				brain.target = nil
				lib.PathTo(bot, brain, brain.breakContactCoverPos, now, 1)
				state.handled = "break_contact"
				return true, { path = true }
			end
		end
	end

	local critical = state.priority == "critical" and policy.criticalSurvivalAlwaysPreempts ~= false
	local canInterruptObjective = state.allowModeObjective == false or not state.objective or not state.objective.active
	if (critical or canInterruptObjective) and state.recommended == "self_treat"
		and not state.threats.visibleHostile and lib and lib.MedicalCheck then
		-- Item 5b: if an enemy was seen recently (even though not visible
		-- right now), duck to cover for up to 3s before treating, rather
		-- than bandaging out in the open where it was last seen.
		local recentEnemy = now - (brain.lastSeenTime or -math.huge) < 5
		local threat = IsValid(brain.attackedBy) and brain.attackedBy or brain.target
		-- Item 1: skip the pre-treat duck-to-cover hesitation once the DM
		-- endgame curve is committed -- still self-treats below (survival is
		-- not optional), just without spending up to 3s hiding first while the
		-- round clock/alive count are the actual pressure.
		if recentEnemy and IsValid(threat) and lib.FindCover and endgame < 0.85 then
			brain.selfTreatCoverStart = brain.selfTreatCoverStart or now
			if now - brain.selfTreatCoverStart < 3 then
				if now >= (brain.selfTreatCoverAt or 0) then
					brain.selfTreatCoverAt = now + 1.5
					brain.selfTreatCoverPos = lib.KeepCover(bot, brain, "treat", threat, 700)
				end
				if isvector(brain.selfTreatCoverPos)
					and bot:GetPos():DistToSqr(brain.selfTreatCoverPos) > 96 * 96 then
					lib.PathTo(bot, brain, brain.selfTreatCoverPos, now, 1)
					state.handled = "seeking_cover"
					return true, { path = true }
				end
			end
		end
		brain.selfTreatCoverStart = nil

		if lib.MedicalCheck(bot, brain, now, false) then
			state.handled = "self_treat"
			return true, { path = true, steer = true, gait = true }
		end
	end

	return false
end

hg.botdriver.DeclareBrainState("survival", {
	fields = {
		"survival", "survivalThreatScanAt", "survivalVisibleHostile",
		"breakContactCoverAt", "breakContactCoverPos",
		"selfTreatCoverStart", "selfTreatCoverAt", "selfTreatCoverPos", "fellBackAt",
	},
})
