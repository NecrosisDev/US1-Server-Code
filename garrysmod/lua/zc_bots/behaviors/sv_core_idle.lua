-- IDLE band, ported and simplified from Trauma's behaviors/sv_core_idle.lua.
-- idle.roam always claims, guaranteeing every decision has an owner.
--
-- Simplified vs Trauma: idle.investigate no longer runs the full search-plan
-- state machine (BeginInvestigation/InvestigationStep/SoundInvestigate --
-- multi-point corner-checking search, part of the perception system this
-- port trims down, rule 1's spirit). It walks once toward the last known
-- damage source and lets idle.roam take back over once that path completes.

local RB = hg.botdriver.RegisterBehavior
local TAIL = { path = true, roam = true }

hg.botdriver.DeclareBrainState("idle_downtime", { fields = { "downtimeActAt", "downtimeCrouchUntil" } })

-- Section E: pre-round/intermission life. hg.botdriver.RoundAllowsCombat()
-- (verified sv_arbiter.lua) is true during a live round and false during the
-- pre-round freeze/buy/intermission window this section targets -- reusing
-- it here needs no new round-state API. Ahead of idle.objective/idle.roam so
-- a bot never chases a hard objective or roams the map while the round has
-- not actually started.
--
-- NOT implemented (see report): a genuine cosmetic weapon-swap fidget would
-- need a verified inventory-cycle entry point; none was confirmed against
-- US1 this session, so this stays limited to crouch-pulses + gaze (still
-- routed through lib.IdleScan, which already glances at teammates/sounds/
-- corpses per section B) rather than inventing a weapon-switch call.
RB({
	name = "idle.downtime",
	band = "IDLE",
	order = 8,
	stateLabel = "downtime",
	finalize = false,
	CanRun = function(ctx)
		return not hg.botdriver.RoundAllowsCombat()
	end,
	Run = function(ctx)
		local brain, bot, now = ctx.brain, ctx.bot, ctx.now
		brain.forward, brain.side = 0, 0
		brain.path = nil

		local personality = brain.personality
		local fidgety = personality and personality.fidgety
		if now >= (brain.downtimeActAt or 0) then
			-- Staggered per-bot: EntIndex spreads the fidget cadence so a whole
			-- squad does not crouch-spam in lockstep.
			brain.downtimeActAt = now + math.Rand(3, 7) + (bot:EntIndex() % 5) * 0.3
			if fidgety and math.random() < 0.4 then
				brain.downtimeCrouchUntil = now + math.Rand(0.2, 0.5)
			end
		end
		if now < (brain.downtimeCrouchUntil or 0) then
			brain.buttons = bit.bor(brain.buttons or 0, IN_DUCK)
		end

		hg.botdriver.lib.IdleScan(bot, brain, now)
		return true
	end,
})

RB({
	name = "idle.objective",
	band = "IDLE",
	order = 10,
	stateLabel = "objective",
	finalize = TAIL,
	CanRun = function(ctx)
		return ctx:HardObjective()
	end,
	Run = function(ctx)
		hg.botdriver.lib.ObjectiveTravel(ctx.bot, ctx.brain, ctx.now)
		return true
	end,
})

RB({
	name = "idle.investigate",
	band = "IDLE",
	order = 20,
	finalize = TAIL,
	CanRun = function(ctx)
		local brain, now = ctx.brain, ctx.now
		local turning = hg.botdriver.DamageTurnActive and hg.botdriver.DamageTurnActive(brain, now)
		return not turning and isvector(brain.damagePos) and now < (brain.damageUntil or 0)
	end,
	Run = function(ctx)
		local brain, now = ctx.brain, ctx.now
		brain.state = "search"
		hg.botdriver.lib.PathTo(ctx.bot, brain, brain.damagePos, now, 1)
		hg.botdriver.lib.LookAt(ctx.bot, brain, brain.damagePos, "sound:damage", true)
		return true
	end,
})

-- Item 9: in team modes, an idle bot with nothing else to do drifts toward
-- its squad instead of wandering off alone. squad.push (sv_squad.lua, MODE
-- band) already computes a soft objective toward the freshest team contact
-- or the squad centroid every decision (cheap vector math, no tracing); IDLE
-- is the only band that never consumed a *soft* objective before this (only
-- ctx:HardObjective() ones), so the regroup/push destination went unused
-- whenever nothing else claimed the tick.
RB({
	name = "idle.squad_drift",
	band = "IDLE",
	order = 25,
	stateLabel = "regroup",
	finalize = TAIL,
	CanRun = function(ctx)
		if hg.botdriver.IsFFA() then return false end
		local brain = ctx.brain
		if not hg.botdriver.lib.ObjectiveActive(brain, ctx.now) then return false end
		local source = brain.objectiveSource
		if hg.botdriver.UsesSharedSearch and hg.botdriver.UsesSharedSearch() then
			if source == "squad_formation" or source == "squad_regroup" then return false end
			if (source == "tdm_called_push" or source == "tdm_enemy_spawn")
				and hg.botdriver.SearchVisited(ctx.bot, brain.objectivePos) then return false end
		end
		-- An arrived soft objective must yield to roaming/search, even when a
		-- mode refreshes its TTL each decision. Otherwise the squad camps it forever.
		return ctx.bot:GetPos():DistToSqr(brain.objectivePos) > (brain.objectiveRadius or 96) ^ 2
	end,
	Run = function(ctx)
		hg.botdriver.lib.ObjectiveTravel(ctx.bot, ctx.brain, ctx.now)
		return true
	end,
})

RB({
	name = "idle.roam",
	band = "IDLE",
	order = 30,
	stateLabel = "roam",
	finalize = TAIL,
	Run = function()
		return true
	end,
})
