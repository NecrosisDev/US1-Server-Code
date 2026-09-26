-- REFLEX band, ported from Trauma's behaviors/sv_core_reflex.lua.
--
-- Cut vs Trauma: reflex.gunpoint-response (needs sv_surrender_ai.lua's
-- GunpointMemory, dropped with the surrender layer, rule 1) and
-- reflex.deadman (needs TraitorDeadmanSwitch, same layer) are both omitted
-- rather than shipped as permanently-inert stubs.

local RB = hg.botdriver.RegisterBehavior

local cv_damage = ConVarExists("zc_bots_damage_reflex") and GetConVar("zc_bots_damage_reflex")
	or CreateConVar("zc_bots_damage_reflex", "1", FCVAR_ARCHIVE,
		"Bots react to being shot: turn toward the source and keep avenge priority on a remembered attacker", 0, 1)
local cv_damageTurn = ConVarExists("zc_bots_damage_turn") and GetConVar("zc_bots_damage_turn")
	or CreateConVar("zc_bots_damage_turn", "1.25", FCVAR_ARCHIVE, "Seconds a shot bot holds its gaze on the hit direction", 0, 10)

local GRUDGE = 4
-- 2026-09-23 (D1): 1.5 s of avenge priority meant a shooter who tagged the bot
-- and ducked away was forgotten almost at once. Humans hold that. The hold
-- now scales with the rolled `grudge` trait: 1.5 s (no grudge) .. 5 s.
local AVENGE_HOLD = 1.5
local AVENGE_GRUDGE = 3.5

function hg.botdriver.DamageTurnActive(brain, now)
	if not cv_damage:GetBool() then return false end
	return now - (brain.damageAt or -math.huge) < cv_damageTurn:GetFloat()
end

RB({
	name = "reflex.damage-response",
	band = "REFLEX",
	order = 5,
	finalize = false,
	CanRun = function(ctx)
		if not cv_damage:GetBool() then return false end
		return ctx.now < (ctx.brain.damageUntil or 0)
	end,
	Run = function(ctx)
		local brain, now = ctx.brain, ctx.now

		local attacker = brain.attackedBy
		if now > (brain.damageTargetUntil or 0)
			and IsValid(attacker) and attacker ~= ctx.bot
			and now - (brain.attackedAt or -math.huge) < GRUDGE then
			brain.damageTargetIndex = attacker:EntIndex()
			local grudge = (brain.personality and brain.personality.grudge) or 0.4
			brain.damageTargetUntil = now + AVENGE_HOLD + AVENGE_GRUDGE * grudge
		end

		if not ctx.downed and not IsValid(brain.target)
			and isvector(brain.damagePos)
			and hg.botdriver.DamageTurnActive(brain, now) then
			hg.botdriver.lib.LookAt(ctx.bot, brain, brain.damagePos, "damage", true)
		end

		return false -- never owns the tick: ACQUIRE/COMBAT act on the seed
	end,
})
