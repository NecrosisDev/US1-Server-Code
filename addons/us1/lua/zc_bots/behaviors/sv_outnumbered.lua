-- SURVIVAL band: outnumbered fallback (item B5). Team modes only (FFA has no
-- "allies" -- hg.botdriver.AllyOf/EnemyOf already read that way; this
-- behavior just declines outright under IsFFA() so it never runs there).
--
-- Counts visible-or-recently-damaging-us enemies vs. living allies within
-- NEARBY_RANGE (reuses sv_survival_defaults.lua's ally_near_range value); a
-- cautious bot (aggression < 0.7, sv_personality.lua trait, default 0.5 with
-- no roll yet) at 2x-or-worse odds falls back to the squad centroid, or to
-- cover from the nearest threat via sv_cover.lua's shared lib.FindCover when
-- no squad module/mates are available -- the same no-squad fallback shape
-- sv_survival.lua's break_contact preemption already uses.
--
-- BEHAVIOR CHOICE (not dictated by the brief): claims the tick outright
-- (like sv_survival.lua's break_contact/self_treat preemptions) rather than
-- only nudging a soft travel objective, so an outnumbered bot actually
-- disengages instead of still trading shots while "retreating" toward an
-- objective that COMBAT-band engagement would otherwise ignore.

local RB = hg.botdriver.RegisterBehavior
local lib = hg.botdriver.lib

hg.botdriver.DeclareBrainState("outnumbered", { fields = { "outnumberedCoverAt", "outnumberedCoverPos" } })

local NEARBY_RANGE = 900
local NEARBY_RANGE_SQR = NEARBY_RANGE * NEARBY_RANGE
local RECENT_DAMAGE_WINDOW = 4
local AGGRESSION_THRESHOLD = 0.7

local function countThreats(ctx)
	local bot, brain, now = ctx.bot, ctx.brain, ctx.now
	local isEnemy, isAlly = ctx:EnemyOf(), ctx:AllyOf()
	if not isfunction(isEnemy) then return 0, 0 end
	local pos = bot:GetPos()
	local enemies, allies = 0, 0
	for _, ent in ipairs(hg.botdriver.Actors()) do
		if ent ~= bot and pos:DistToSqr(ent:GetPos()) <= NEARBY_RANGE_SQR then
			if isEnemy(ent) then
				local counted = lib.VisualContact(bot, ent, brain, false, now) ~= nil
					or (brain.attackedBy == ent and now - (brain.attackedAt or -math.huge) < RECENT_DAMAGE_WINDOW)
				if counted then enemies = enemies + 1 end
			elseif isfunction(isAlly) and isAlly(ent) then
				allies = allies + 1
			end
		end
	end
	return enemies, allies
end

local function squadCentroid(bot)
	local squad = hg.botdriver.squad
	if not squad or not squad.Squadmates then return nil end
	local mates = squad.Squadmates(bot)
	if #mates <= 1 then return nil end
	local centroid, n = Vector(0, 0, 0), 0
	for _, m in ipairs(mates) do
		if IsValid(m) then
			centroid = centroid + m:GetPos()
			n = n + 1
		end
	end
	return n > 0 and (centroid / n) or nil
end

RB({
	name = "survival.outnumbered",
	band = "SURVIVAL",
	order = 12,
	finalize = { path = true },
	CanRun = function(ctx)
		if ctx.downed then return false end
		if hg.botdriver.HomicideRush and hg.botdriver.HomicideRush() then return false end
		if hg.botdriver.IsFFA() then return false end
		local aggression = (ctx.brain.personality and ctx.brain.personality.aggression) or 0.5
		if aggression >= AGGRESSION_THRESHOLD then return false end
		-- Being hit by an attacker it can see: return fire, do not retreat
		-- (sv_survival.lua UnderFireFromVisible, 2026-09-25).
		if hg.botdriver.UnderFireFromVisible and hg.botdriver.UnderFireFromVisible(ctx.bot, ctx.brain, ctx.now) then return false end
		local enemies, allies = countThreats(ctx)
		return enemies > 0 and enemies >= 2 * math.max(allies, 1)
	end,
	Run = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		local dest = squadCentroid(bot)
		if not dest then
			local threat = IsValid(brain.attackedBy) and brain.attackedBy or brain.target
			if IsValid(threat) then
				if now >= (brain.outnumberedCoverAt or 0) then
					brain.outnumberedCoverAt = now + 1.5
					brain.outnumberedCoverPos = lib.KeepCover(bot, brain, "outnumbered", threat, 700)
				end
				dest = brain.outnumberedCoverPos
			end
		end
		if not isvector(dest) then return false end

		brain.target = nil
		lib.PathTo(bot, brain, dest, now, 1)
		return true
	end,
})
