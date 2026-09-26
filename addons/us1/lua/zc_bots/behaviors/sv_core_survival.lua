-- SURVIVAL band, ported from Trauma's behaviors/sv_core_survival.lua. The
-- dodge-fallback behavior is dropped (needs lib.DangerDodge / the grenade
-- layer, rule 1). survival.preempt is the only real owner; the downed
-- fallback stays as defence-in-depth if sv_survival.lua is ever missing.

local RB = hg.botdriver.RegisterBehavior

local function survivalModuleAbsent()
	return hg.botdriver.ApplySurvivalPreemption == nil
end

RB({
	name = "survival.preempt",
	band = "SURVIVAL",
	order = 10,
	finalize = false,
	CanRun = function(ctx)
		return hg.botdriver.ApplySurvivalPreemption ~= nil
	end,
	Run = function(ctx)
		local handled, finalizeOpts = hg.botdriver.ApplySurvivalPreemption(
			ctx.bot, ctx.brain, ctx.now, ctx.survival, ctx.survivalPolicy)
		if not handled then return false end
		return true, finalizeOpts or false
	end,
})

RB({
	name = "survival.downed-fallback",
	band = "SURVIVAL",
	order = 20,
	finalize = false,
	CanRun = function(ctx)
		return survivalModuleAbsent() and ctx.downed and hg.botdriver.DownedDecide ~= nil
	end,
	Run = function(ctx)
		local downedEnemy = ctx:EnemyOf()
		if not isfunction(downedEnemy) then return false end
		return hg.botdriver.DownedDecide(ctx.bot, ctx.brain, ctx.now, downedEnemy) == true
	end,
})
