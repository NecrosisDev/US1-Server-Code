-- REFLEX band: reaction to being suppressed by nearby hostile gunfire the
-- bot cannot see the source of (brain.suppressedUntil/suppressedFrom, set by
-- sv_hearing.lua's EntityFireBullets line-distance check -- item B2).
--
-- By aggression trait (sv_personality.lua, 0.25-0.85 roll, default 0.5 when
-- no personality has rolled yet): a cautious bot (< 0.5) crouches and moves
-- to cover found via sv_cover.lua's lib.FindCover (same shared finder
-- sv_melee.lua/sv_gunhandling.lua/sv_survival.lua already use, own 1.5s
-- re-scan cadence so this never adds a second per-tick trace budget); a
-- braver bot just turns to face the source, ready to return fire the instant
-- something becomes visible.
--
-- Never claims the tick when a live target is already known (ctx:AcquireTarget
-- returning something combat.engage should own instead), and always declines
-- ownership itself so ACQUIRE/COMBAT/IDLE still drive movement/aim on every
-- tick this fires -- mirrors reflex.damage-response's "seed, don't own"
-- pattern in behaviors/sv_core_reflex.lua.

local RB = hg.botdriver.RegisterBehavior
local lib = hg.botdriver.lib

RB({
	name = "reflex.suppression-response",
	band = "REFLEX",
	order = 8,
	finalize = false,
	CanRun = function(ctx)
		local brain = ctx.brain
		if ctx.now >= (brain.suppressedUntil or 0) then return false end
		if not isvector(brain.suppressedFrom) then return false end
		return not ctx.downed
	end,
	Run = function(ctx)
		local bot, brain = ctx.bot, ctx.brain
		-- A visible enemy already seeds ACQUIRE/COMBAT; let them own the tick.
		if IsValid(ctx:AcquireTarget()) then return false end

		local aggression = (brain.personality and brain.personality.aggression) or 0.5
		if aggression < 0.5 then
			-- lib.FindCover needs a threat ENTITY (it traces LOS from its eyes)
			-- and no shooter entity survives the hearing event by the time this
			-- runs (only a position), so there is no cover-search target here --
			-- crouch and back away from the shot line instead, the same
			-- no-cover fallback sv_melee.lua's evade path and
			-- gh.RetreatWhileReloading use.
			brain.buttons = bit.bor(brain.buttons or 0, IN_DUCK)
			local away = bot:GetPos() - brain.suppressedFrom
			away.z = 0
			if away:LengthSqr() > 1 then
				away:Normalize()
				brain.moveAngles = away:Angle()
				brain.forward = 200
				brain.side = 0
			end
		end
		lib.LookAt(bot, brain, brain.suppressedFrom, "suppression", false)

		return false
	end,
})
