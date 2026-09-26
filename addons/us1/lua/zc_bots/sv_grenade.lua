-- Item B1: frag grenade throw (COMBAT band) + a REFLEX grenade-dodge.
--
-- UNVERIFIED CAVEAT (research pass, this session, not independently
-- re-grepped against weapon_tpik_base's own source in this pass): grenade
-- weapons (weapon_hg_grenade_tpik "M67", weapon_hg_rgd_tpik "RGD-5",
-- weapon_hg_hl2nade_tpik "Combine Frag") share weapon_tpik_base and expose
-- ReadyToThrow/SpoonTime/Spoon/InThrowing fields; PrimaryAttack is a
-- pull-back-then-release throw (high arc, ~1200 u/s) fired ~0.6-0.8s after
-- the attack starts. The exact press/hold/release contract that triggers the
-- actual throw was not independently confirmed against weapon_tpik_base's
-- own Think/PrimaryAttack body in this pass -- this file holds IN_ATTACK for
-- a fixed WINDUP_TIME then releases it, on the same "tap, don't hold longer
-- than needed" assumption sv_brain.lua's manual-action weapons use.
-- PROVISIONAL(2026-09-21, exact tpik_base press/release timing not directly
-- re-verified this pass, ratify-by: 2026-10-15)
--
-- weapon_hg_f1_tpik ("F1") and weapon_hg_type59_tpik ("Type-59 Grenade")
-- added 2026-09-22 (Task 4 weapon-competence pass): both files verified at
-- work/main-design-source/lua/weapons/, both `SWEP.Base =
-- "weapon_hg_grenade_tpik"` with the IDENTICAL `self:Throw(1200, ...)` high-arc
-- "attack" callback as the three classes above -- same mechanism, not a
-- guess. Both appear in supported modes' own loadouts (grepped
-- work/bots/us1/addons/zcity/gamemodes/zcity/gamemode/modes/: criresp,
-- defense, dm, gwars, sfd, tdm, zz_uncontained_riot). Their live grenade
-- entity classes (SWEP.ENT, for the dodge list below) are "ent_hg_grenade"
-- (f1) and "ent_hg_grenade_type59".
--
-- Smoke/flash/molotov/pipebomb tpik variants are deliberately excluded from
-- the throwable set (brief: "skip smokes/flashes"; pipebombs are a
-- NoSpoon=true instant-throw/trap variant with different semantics from a
-- frag arc and are out of this item's scope). weapon_hg_flashbang_tpik is
-- likewise not added here -- it gets its own dedicated tactical (not
-- lethal-combat) throw behavior in modes/sv_criresp.lua instead, since only
-- criresp's SWAT loadout hands it out and the decision of WHEN to flash a
-- room is a mode-specific breach objective, not a generic "throw at the
-- enemy" reflex. Live-grenade entity classes for the dodge below are the
-- matching frag/explosive ents only (ent_hg_grenade_m67, ent_hg_grenade_rgd5,
-- ent_hg_grenade_hl2grenade, ent_hg_grenade_pipebomb -- the last dodged
-- defensively even though this file never throws one, since a human or
-- another mode's rioter/police loadout can still throw one at a bot).

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}

local RB = hg.botdriver.RegisterBehavior

hg.botdriver.DeclareBrainState("grenade", {
	fields = {
		"grenadeCooldownAt", "grenadeThrowing", "grenadeThrowStart", "grenadeLanding",
		"grenadeDodgeUntil", "grenadeDodgeFrom", "grenadeScanAt",
	},
})

----------------------------------------------------------------------
-- REFLEX: dodge a live grenade landing nearby, only while the bot has
-- recently heard/seen combat (brain.combatAwareUntil, sv_hearing.lua) so an
-- idle bot never pays the scan cost. Bounded (ents.FindInSphere within
-- DODGE_RANGE, not a whole-map scan) and rate-limited to 2 Hz per bot via
-- brain.grenadeScanAt, well inside the ~6 Hz decision cadence.
----------------------------------------------------------------------

local DODGE_CLASSES = {
	ent_hg_grenade_m67 = true,
	ent_hg_grenade_rgd5 = true,
	ent_hg_grenade_hl2grenade = true,
	ent_hg_grenade_pipebomb = true,
	ent_hg_grenade = true,          -- weapon_hg_f1_tpik ("F1")
	ent_hg_grenade_type59 = true,   -- weapon_hg_type59_tpik ("Type-59 Grenade")
}
local DODGE_RANGE = 300
local DODGE_RANGE_SQR = DODGE_RANGE * DODGE_RANGE
local DODGE_DURATION = 1.5
local DODGE_SCAN_INTERVAL = 0.5 -- 2 Hz cap

RB({
	name = "reflex.grenade-dodge",
	band = "REFLEX",
	order = 3,
	finalize = {},
	CanRun = function(ctx)
		local brain = ctx.brain
		if ctx.now < (brain.grenadeDodgeUntil or 0) then return true end
		if ctx.now >= (brain.combatAwareUntil or 0) then return false end
		if ctx.now < (brain.grenadeScanAt or 0) then return false end
		brain.grenadeScanAt = ctx.now + DODGE_SCAN_INTERVAL

		local pos = ctx.bot:GetPos()
		for _, ent in ipairs(ents.FindInSphere(pos, DODGE_RANGE)) do
			if IsValid(ent) and DODGE_CLASSES[ent:GetClass()] and pos:DistToSqr(ent:GetPos()) <= DODGE_RANGE_SQR then
				brain.grenadeDodgeUntil = ctx.now + DODGE_DURATION
				brain.grenadeDodgeFrom = ent:GetPos()
				return true
			end
		end
		return false
	end,
	Run = function(ctx)
		local bot, brain = ctx.bot, ctx.brain
		local from = brain.grenadeDodgeFrom
		if isvector(from) then
			local away = bot:GetPos() - from
			away.z = 0
			if away:LengthSqr() > 1 then
				away:Normalize()
				brain.moveAngles = away:Angle()
			end
		end
		brain.path = nil
		brain.forward = 400
		brain.side = 0
		brain.sprint = true
		return true
	end,
})

----------------------------------------------------------------------
-- COMBAT: throw a frag when the brief's conditions all hold. Lower order
-- than combat.engage (20 in behaviors/sv_core_combat.lua) so a decided throw
-- preempts a normal engagement, but only while a throw is actually warranted
-- -- once released it falls through to combat.engage on the next decision.
----------------------------------------------------------------------

local GRENADE_CLASSES_THROW = {
	weapon_hg_grenade_tpik = true,
	weapon_hg_rgd_tpik = true,
	weapon_hg_hl2nade_tpik = true,
	weapon_hg_f1_tpik = true,
	weapon_hg_type59_tpik = true,
}

local LOS_LOST_WINDOW = 1.5
local KNOWN_DIST_MIN, KNOWN_DIST_MAX = 300, 1200
local CLUSTER_RADIUS = 250
local ALLY_SAFE_RADIUS = 350
local SELF_SAFE_RADIUS = 300
local THROW_COOLDOWN = 20
local WINDUP_TIME = 0.75
local THROW_SPEED = 1200 -- verified: weapon_hg_grenade_tpik primary (high) throw speed

local function carriedGrenade(bot)
	for _, wep in ipairs(bot:GetWeapons()) do
		if IsValid(wep) and GRENADE_CLASSES_THROW[wep:GetClass()] then return wep end
	end
	return nil
end

-- Any pair of visible-relationship enemies within CLUSTER_RADIUS of each
-- other; returns their midpoint. hg.botdriver.Actors() is the same bounded
-- player.GetAll() roster every other targeting pass already iterates, not an
-- extra scan.
local function clusterMidpoint(ctx)
	local isEnemy = ctx:EnemyOf()
	if not isfunction(isEnemy) then return nil end
	-- Item 2 (NPC targeting): ent:Alive() is player/NPC-only and Actors() can
	-- now hand back a registry NPC in coop/defense -- hg.botdriver.EntityAlive
	-- (sv_npc.lua) is the entity-agnostic stand-in.
	local enemies = {}
	for _, ent in ipairs(hg.botdriver.Actors()) do
		if hg.botdriver.EntityAlive(ent) and isEnemy(ent) then enemies[#enemies + 1] = ent end
	end
	local radiusSqr = CLUSTER_RADIUS * CLUSTER_RADIUS
	for i = 1, #enemies do
		local a = enemies[i]
		local sum, count = a:GetPos(), 1
		for j = 1, #enemies do
			if j ~= i then
				local b = enemies[j]
				if a:GetPos():DistToSqr(b:GetPos()) <= radiusSqr then
					sum = sum + b:GetPos()
					count = count + 1
				end
			end
		end
		if count >= 2 then return sum / count end
	end
	return nil
end

local function pickLanding(ctx)
	local brain, bot, now = ctx.brain, ctx.bot, ctx.now
	local myPos = bot:GetPos()

	if isvector(brain.lastSeenPos) and now - (brain.lastSeenTime or -math.huge) > LOS_LOST_WINDOW then
		local dist = myPos:Distance(brain.lastSeenPos)
		if dist >= KNOWN_DIST_MIN and dist <= KNOWN_DIST_MAX then return brain.lastSeenPos end
	end

	local cluster = clusterMidpoint(ctx)
	if cluster then
		local dist = myPos:Distance(cluster)
		if dist >= KNOWN_DIST_MIN and dist <= KNOWN_DIST_MAX then return cluster end
	end

	return nil
end

-- selfRadius/allyRadius default to the frag-throw constants above; exported
-- (Part A.2, criresp SWAT flashbang) so a caller with a different blast
-- profile can pass its own radii without duplicating the ally scan.
local function safeToThrow(bot, landing, selfRadius, allyRadius)
	selfRadius = selfRadius or SELF_SAFE_RADIUS
	allyRadius = allyRadius or ALLY_SAFE_RADIUS
	if bot:GetPos():DistToSqr(landing) <= selfRadius * selfRadius then return false end
	local allyOf = hg.botdriver.AllyOf(bot) -- always false in FFA (sv_brain.lua), so no ally check applies there
	local radiusSqr = allyRadius * allyRadius
	for _, ent in ipairs(hg.botdriver.Actors()) do
		if ent ~= bot and allyOf(ent) and hg.botdriver.EntityAlive(ent) and ent:GetPos():DistToSqr(landing) <= radiusSqr then
			return false
		end
	end
	return true
end
hg.botdriver.lib.GrenadeSafeToThrow = safeToThrow

----------------------------------------------------------------------
-- Shared aim+throw state machine, extracted out of combat.grenade's own Run
-- below so a second caller with a different throwable (Part A.2, criresp
-- SWAT flashbang) reuses the exact ballistic solve / windup hold-and-release
-- instead of a second copy of it. Caller has already confirmed
-- bot:GetActiveWeapon() == wep and owns its own cooldown field + post-throw
-- weapon switch, since those differ per caller (this file's THROW_COOLDOWN/
-- BestGun re-equip below vs. the criresp mode file's own utility-throw
-- cooldown). Returns true while still mid-windup (holding IN_ATTACK), false
-- once the throw has just been released this call.
----------------------------------------------------------------------

function hg.botdriver.lib.AimAndThrow(bot, brain, now, wep, landing, throwSpeed, windupTime)
	-- Simple ballistic pitch estimate (standard projectile-range formula) for
	-- the given throw speed against the server's own configured gravity.
	local eyePos = bot:EyePos()
	local flat = landing - eyePos
	local heightDiff = flat.z
	flat.z = 0
	local dist = math.max(flat:Length(), 1)
	local yaw = flat:Angle().y

	-- physenv.GetGravity (GMod's physics-environment library). The previous
	-- `physics.GetGravity()` is not a GMod API; on US1 it evaluated to nil and
	-- every throw decision crashed (zc_errlog/errors-2026-09-24.txt, 278x).
	local gravityVec = physenv and physenv.GetGravity and physenv.GetGravity()
	local gravity = math.max(isvector(gravityVec) and gravityVec:Length() or 600, 1)
	local speedSqr = throwSpeed * throwSpeed
	local underRoot = speedSqr * speedSqr - gravity * (gravity * dist * dist + 2 * heightDiff * speedSqr)
	local pitch
	if underRoot >= 0 then
		pitch = -math.deg(math.atan((speedSqr - math.sqrt(underRoot)) / (gravity * dist)))
	else
		pitch = -15 -- out of range for this speed/arc: best-effort lob
	end
	brain.viewAngles = Angle(pitch, yaw, 0)
	brain.lookSource = "grenade"
	brain.lookLocked = true

	brain.grenadeThrowStart = brain.grenadeThrowStart or now
	brain.grenadeThrowing = true
	brain.actionPolicy = { owner = "grenade", lockMove = true }

	if now - brain.grenadeThrowStart < windupTime then
		brain.buttons = bit.bor(brain.buttons or 0, IN_ATTACK)
		return true
	end

	brain.buttons = bit.band(brain.buttons or 0, bit.bnot(IN_ATTACK))
	brain.grenadeThrowing = nil
	brain.grenadeThrowStart = nil
	return false
end

RB({
	name = "combat.grenade",
	band = "COMBAT",
	order = 10,
	finalize = {},
	CanRun = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		if brain.grenadeThrowing then return true end
		if hg.botdriver.RoundAllowsCombat and not hg.botdriver.RoundAllowsCombat() then return false end
		if now < (brain.grenadeCooldownAt or 0) then return false end
		if not carriedGrenade(bot) then return false end

		local landing = pickLanding(ctx)
		if not landing then return false end
		if not safeToThrow(bot, landing) then return false end

		brain.grenadeLanding = landing
		return true
	end,
	Run = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		local wep = carriedGrenade(bot)
		if not IsValid(wep) then
			brain.grenadeThrowing = nil
			return false
		end
		if bot:GetActiveWeapon() ~= wep then
			bot:SelectWeapon(wep:GetClass())
			brain.grenadeThrowStart = nil
			return true
		end

		local landing = brain.grenadeLanding
		if not isvector(landing) then
			brain.grenadeThrowing = nil
			return false
		end

		if hg.botdriver.lib.AimAndThrow(bot, brain, now, wep, landing, THROW_SPEED, WINDUP_TIME) then
			return true -- still winding up
		end
		brain.grenadeCooldownAt = now + THROW_COOLDOWN
		local gun = hg.botdriver.BestGun(bot)
		if gun then bot:SelectWeapon(gun:GetClass()) end
		return true
	end,
})
