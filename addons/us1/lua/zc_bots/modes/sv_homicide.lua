-- Homicide: private evidence, native roles, and bot-only encounter pacing.
-- Location guidance in the bot-only endgame never grants an attack target.
if not SERVER then return end

local D = hg.botdriver
local lib = D.lib
local H = {}
D.homicide = H
local variants = { hmcd = true, standard = true, soe = true, wildwest = true, gunfreezone = true, juggernaut = true }

function H.Active()
	return zb ~= nil and (zb.CROUND_MAIN == "hmcd" or variants[zb.CROUND_MAIN or zb.CROUND] == true)
end

local function playing(ply)
	return IsValid(ply) and ply:IsPlayer() and ply:Alive()
		and ply:Team() ~= TEAM_SPECTATOR and ply:Team() ~= TEAM_UNASSIGNED
end

-- No cache: a human spawn must immediately restore normal caution and secrecy.
function D.HomicideRush()
	if not H.Active() or not D.RoundAllowsCombat() then return false end
	local bots = 0
	for _, ply in ipairs(player.GetAll()) do
		if playing(ply) then
			if not ply:IsBot() then return false end
			bots = bots + 1
		end
	end
	return bots > 1
end

local function witnessed(bot, other, brain, now)
	return bot:GetPos():DistToSqr(other:GetPos()) <= 1800 * 1800
		and lib.VisualContact(bot, other, brain, false, now) ~= nil
end

function H.EnemyOf(bot)
	local brain = D.GetBrain(bot)
	return function(other)
		if not playing(other) or other == bot then return false end
		if bot.isTraitor then return other.isTraitor ~= true end
		-- zc_juggernaut: the Juggernaut is announced to everyone at round
		-- start (ply.zc_isJugg), so he is no secret to hunt for.
		if other.zc_isJugg == true then return true end
		local now = CurTime()
		-- Innocents can defend themselves against anyone who actually hurt them.
		if brain.attackedBy == other and now < (brain.damageUntil or 0) then return true end
		-- Hidden role alone never authorizes an innocent's attack. The role check
		-- only protects other innocents from false accusations or stolen items.
		if other.isTraitor ~= true then return false end
		local evidence = brain.hmcdEvidence and brain.hmcdEvidence[other]
		if evidence and now < evidence then return true end
		local weapon = other:GetActiveWeapon()
		return IsValid(weapon) and string.StartWith(weapon:GetClass(), "weapon_traitor_")
			and witnessed(bot, other, brain, now)
	end
end

function H.AllyOf(bot)
	local enemy = H.EnemyOf(bot)
	return function(other)
		if not playing(other) or other == bot then return false end
		if bot.isTraitor then return other.isTraitor == true end
		-- Treat unrevealed people as protected bystanders, not shared teammates.
		return not enemy(other)
	end
end

hook.Add("HomigradDamage", "zc_bots_homicide_witness", function(victim, damage)
	if not H.Active() or not D.RoundAllowsCombat() or not IsValid(victim) or not victim:IsPlayer()
		or victim:Team() == TEAM_SPECTATOR or victim:Team() == TEAM_UNASSIGNED then return end
	local attacker = damage:GetAttacker()
	if not playing(attacker) or attacker == victim or attacker.isTraitor ~= true
		or victim.isTraitor == true or damage:GetDamage() <= 0 then return end
	local now = CurTime()
	for bot, brain in pairs(D.brains) do
		if playing(bot) and bot.zcBot and not bot.isTraitor
			and (bot == victim or (witnessed(bot, attacker, brain, now) and witnessed(bot, victim, brain, now))) then
			brain.hmcdEvidence = brain.hmcdEvidence or {}
			-- A short pursuit window after a witnessed attack; no shared wallhack.
			brain.hmcdEvidence[attacker] = now + 8
		end
	end
end)

local rallyPos
local function rally()
	if rallyPos then return rallyPos end
	local anchor
	for _, ply in ipairs(player.GetAll()) do
		if playing(ply) and (not anchor or ply:EntIndex() < anchor:EntIndex()) then anchor = ply end
	end
	if anchor then rallyPos = anchor:GetPos() end
	return rallyPos
end

local function nearestVictim(bot, brain, now, rush)
	local best, distance
	for _, ply in ipairs(player.GetAll()) do
		if playing(ply) and ply ~= bot and not ply.isTraitor
			and now >= ((brain.hmcdFailed or {})[ply] or 0)
			and (rush or witnessed(bot, ply, brain, now)) then
			local d = bot:GetPos():DistToSqr(ply:GetPos())
			if not distance or d < distance then best, distance = ply, d end
		end
	end
	return best
end

D.DeclareBrainState("homicide", { fields = {
	"hmcdEvidence", "hmcdPursuit", "hmcdFailed", "hmcdTravelAt", "hmcdTravelPos",
} })

local function resetRound()
	rallyPos = nil
	for bot, brain in pairs(D.brains) do
		brain.hmcdEvidence, brain.hmcdPursuit, brain.hmcdFailed = nil, nil, nil
		brain.hmcdTravelAt, brain.hmcdTravelPos = nil, nil
		if H.Active() and IsValid(bot) then D.ResetBrain(bot) end
	end
end
hook.Add("ZB_EndRound", "zc_bots_homicide_end", resetRound)
hook.Add("ZB_PreRoundStart", "zc_bots_homicide_start", resetRound)
hook.Add("PlayerSpawn", "zc_bots_homicide_spawn", function(ply)
	-- Clear old-life accusations in other observers, including same-round respawns.
	for _, brain in pairs(D.brains) do
		if brain.hmcdEvidence then brain.hmcdEvidence[ply] = nil end
		if brain.hmcdFailed then brain.hmcdFailed[ply] = nil end
	end
	if not ply:IsBot() then rallyPos = nil end
end)
hook.Add("PlayerDisconnected", "zc_bots_homicide_disconnect", function(ply)
	for _, brain in pairs(D.brains) do
		if brain.hmcdEvidence then brain.hmcdEvidence[ply] = nil end
		if brain.hmcdFailed then brain.hmcdFailed[ply] = nil end
	end
end)

D.RegisterBehavior({
	name = "mode.homicide_progress",
	band = "MODE",
	order = 5,
	default = false,
	finalize = { path = true },
	CanRun = function(ctx)
		return H.Active() and D.RoundAllowsCombat() and not ctx.downed
	end,
	Run = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		local rush = D.HomicideRush()
		if not rush then rallyPos = nil end
		-- Existing scoring/deploy/reload/aim owns the weapon. Equip while searching
		-- as well as fighting, so bots do not wander around holding bandages.
		if IsValid(ctx:AcquireTarget()) then return false end -- ordinary combat owns fire
		-- Never fight a treatment in progress for the active weapon (this MODE
		-- behavior runs before SUPPORT's MedicalCheck/medic every decision, so
		-- switching here flip-flopped med <-> weapon and the heal never landed).
		local healing = brain.medSelfStart ~= nil or IsValid(brain.medicPatient)
		if not healing then
			if bot.isTraitor and not rush then
				-- 2026-09-25: a traitor walking around with its best gun drawn is
				-- the tell humans spot first. Keep hands out between attacks;
				-- Engage's own EquipForRange draws the weapon on acquisition.
				local active = bot:GetActiveWeapon()
				if IsValid(active) and active:GetClass() ~= "weapon_hands_sh" and bot:HasWeapon("weapon_hands_sh") then
					bot:SelectWeapon("weapon_hands_sh")
				end
			elseif D.EquipForRange then
				D.EquipForRange(bot, brain, now, 500)
			end
		end
		local goal, victim
		if bot.isTraitor then
			victim = nearestVictim(bot, brain, now, rush)
			if IsValid(victim) then goal = victim:GetPos() end
		elseif rush then
			goal = rally() -- neutral meeting point; never reveals a traitor identity
		end
		if not isvector(goal) then return false end -- existing coverage search
		if brain.hmcdPursuit ~= victim then
			brain.hmcdPursuit = victim
			brain.hmcdTravelAt, brain.hmcdTravelPos = now, bot:GetPos()
		end
		brain.hmcdTravelAt = brain.hmcdTravelAt or now
		brain.hmcdTravelPos = brain.hmcdTravelPos or bot:GetPos()
		if bot:GetPos():DistToSqr(brain.hmcdTravelPos) > 64 * 64 then
			brain.hmcdTravelAt, brain.hmcdTravelPos = now, bot:GetPos()
		elseif now - brain.hmcdTravelAt > 6 then
			if IsValid(victim) then
				brain.hmcdFailed = brain.hmcdFailed or {}
				brain.hmcdFailed[victim] = now + 10
			end
			brain.hmcdTravelAt, brain.hmcdTravelPos = nil, nil
			brain.path, brain.roamPath, brain.roamGoal = nil, nil, nil
			brain.nextRepath = 0
			return false -- try another opponent or the coverage planner, not an endless wall push
		end
		if bot:GetPos():DistToSqr(goal) < 72 * 72 then
			brain.path = nil
			lib.IdleScan(bot, brain, now)
			return true
		end
		brain.state = rush and "homicide_rush" or "homicide_hunt"
		lib.PathTo(bot, brain, goal, now, 1)
		return true
	end,
})

D.RegisterModeProfile("hmcd", {
	aliases = { "standard", "soe", "wildwest", "gunfreezone" },
	behaviors = { "mode.homicide_progress" },
	NoSquads = true,
	EnemyOf = H.EnemyOf,
	AllyOf = H.AllyOf,
})
