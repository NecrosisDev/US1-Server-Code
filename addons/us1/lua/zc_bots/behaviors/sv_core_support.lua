-- SUPPORT band, ported from Trauma's behaviors/sv_core_support.lua.
--
-- support.rescue is omitted: it depends entirely on sv_rescue.lua (RescueCheck/
-- RescueAbort), which the porting brief drops (rule 1, "rescue... layers").
-- support.medical has no such dependency (only lib.MedicalCheck, ported in
-- sv_brain.lua), so it ships.

local RB = hg.botdriver.RegisterBehavior

local function noTargetNoHardObjective(ctx)
	if ctx:HardObjective() then return false end
	local target = ctx:AcquireTarget()
	return not IsValid(target)
end

RB({
	name = "support.medical",
	band = "SUPPORT",
	order = 10,
	finalize = { path = true },
	CanRun = noTargetNoHardObjective,
	Run = function(ctx)
		return hg.botdriver.lib.MedicalCheck(ctx.bot, ctx.brain, ctx.now, false) == true
	end,
})
