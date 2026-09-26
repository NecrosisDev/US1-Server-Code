-- COMBAT band, ported from Trauma's behaviors/sv_core_combat.lua.
-- combat.grenade is dropped (grenade layer, rule 1); combat.engage is the
-- engagement core, unchanged in shape from Trauma.

local RB = hg.botdriver.RegisterBehavior

-- Item 4 (2026-09-22, weapon-appropriate positioning): rate-limited per bot,
-- reuses sv_weaponscore.lua's existing CATEGORY_ROLE classification (via
-- WeaponProfile/RoleBands) and sv_cover.lua's FindCover/FindSightline scans --
-- no new weapon taxonomy, no per-tick trace cost.
hg.botdriver.DeclareBrainState("weapon_position", { fields = {
	"posRoleCheckAt", "combatPosition", "combatPositionTarget", "combatPositionWeapon", "combatPositionUntil", "combatRoute",
} })

local POSITION_RECHECK = 2.5
-- Sniper: too close to its ideal band's low bound -> look for a farther spot
-- with a clear sightline instead of trading in someone else's range.
local SNIPER_TOO_CLOSE_FRAC = 0.6
-- Shotgun/SMG: past their ideal band's high bound -> close in via cover
-- (corners/close angles) instead of a straight line across open ground.
local CLOSE_RANGE_TOO_FAR_FRAC = 1.4

RB({
	name = "combat.engage",
	band = "COMBAT",
	order = 20,
	finalize = { path = true, roam = true },
	CanRun = function(ctx)
		if hg.botdriver.RoundAllowsCombat and not hg.botdriver.RoundAllowsCombat() then return false end
		local target = ctx:AcquireTarget()
		return IsValid(target)
	end,
	Run = function(ctx)
		local brain = ctx.brain
		local target, dist = ctx:AcquireTarget()
		local lib = hg.botdriver.lib
		local weapon = ctx.bot:GetActiveWeapon()
		local profile = IsValid(weapon) and hg.botdriver.WeaponProfile(weapon)
		local band = profile and hg.botdriver.RoleBands[profile.role]
		if band and profile.role ~= "melee" then
			local bias = brain.personality and brain.personality.preferRangeBias or 1
			ctx.behavior.preferRange = math.Clamp(band.ideal[1] + (band.ideal[2] - band.ideal[1]) * 0.35, 220, 1800)
				* math.Clamp(bias, 0.8, 1.2)
		end
		local route = brain.combatRoute
		if route then
			if brain.path == route.path then route.idx = brain.pathIdx
			else brain.combatPosition, brain.combatRoute = nil, nil end
		end
		-- 2026-09-22 fix: stash the ctx-resolved (possibly MODE-band-overridden,
		-- e.g. masscasualty's shooterAllyOf or sv_crowd.lua's defensive
		-- no-allies) relationship onto the reused ctx.behavior table so
		-- lib.Engage's own friendly-fire raytrace check can prefer it over the
		-- raw team-based hg.botdriver.AllyOf -- see sv_brain.lua's Engage for
		-- why the raw fallback alone is wrong whenever a MODE band already
		-- established that team number is not what hostility means this round
		-- (masscasualty/activeshooter shooters and everyone else share team 0,
		-- so the raw check would treat their own target as an "ally" and hold
		-- fire forever). ctx.behavior is the same per-brain reused table
		-- sv_arbiter.lua already populates every decision -- no new allocation.
		ctx.behavior.allyOf = ctx:AllyOf()

		-- Item 1 (2026-09-22, DM endgame fix): floor the aggression term
		-- Engage reads from ctx.behavior as modes/sv_dm.lua's EndgameFactor
		-- rises (0 outside dm) -- a hurt/cautious bot presses the fight once
		-- few players remain instead of only fixing the SURVIVAL-band
		-- cover-seeking that was the actual stall (sv_survival.lua).
		local endgame = hg.botdriver.EndgameFactor and hg.botdriver.EndgameFactor() or 0
		if endgame > 0 then
			ctx.behavior.aggression = math.max(ctx.behavior.aggression or 0.5, endgame)
		end

		local buttons = hg.botdriver.lib.Engage(
			ctx.bot, brain, ctx.now, ctx.skill, target, dist, ctx.behavior, brain.buttons or 0)
		brain.buttons = buttons

		local now = ctx.now
		local canPosition = IsValid(weapon) and not weapon.ismelee and brain.target == target and brain.aimLocked
			and ctx.bot:GetActiveWeapon() == weapon and not brain.actionPolicy and not weapon.reload
			and weapon.Clip1 and weapon:Clip1() > 0 and now >= (brain.squadSuppressUntil or 0)
		if not canPosition or brain.combatPositionTarget ~= target or brain.combatPositionWeapon ~= weapon
			or now >= (brain.combatPositionUntil or 0)
			or (isvector(brain.combatPosition) and ctx.bot:GetPos():DistToSqr(brain.combatPosition) < 56 * 56) then
			brain.combatPosition, brain.combatRoute = nil, nil
		end
		if canPosition and not brain.combatPosition and now >= (brain.posRoleCheckAt or 0) then
			brain.posRoleCheckAt = now + POSITION_RECHECK
			local role = profile and profile.role
			local spot
			if band and role == "sniper" and (dist or 0) < band.ideal[1] * SNIPER_TOO_CLOSE_FRAC then
				spot = lib.FindSightline(ctx.bot, target, 1500)
			elseif band and (role == "shotgun" or role == "smg") and (dist or 0) > band.ideal[2] * CLOSE_RANGE_TOO_FAR_FRAC then
				spot = lib.FindCover(ctx.bot, target, 700)
				if isvector(spot) and spot:Distance(target:GetPos()) >= (dist or 0) - 64 then spot = nil end
			elseif lib.FindCombatPosition then
				spot = lib.FindCombatPosition(ctx.bot, target, ctx.behavior.preferRange or 600)
			end
			if isvector(spot) then
				brain.combatPosition, brain.combatPositionTarget, brain.combatPositionWeapon = spot, target, weapon
				brain.combatPositionUntil = now + 4
				brain.nextRepath = 0
			end
		end
		if canPosition and brain.combatPosition then
			-- Restore our committed corridor after Engage's range/stance logic.
			-- Keep the index advanced by Finalize; do not restart at node one.
			route = brain.combatRoute
			if route then
				brain.path, brain.pathIdx = route.path, route.idx
				brain.pathGoal, brain.nextRepath = brain.combatPosition, route.repath
			end
			lib.PathTo(ctx.bot, brain, brain.combatPosition, now, 1)
			if brain.path and brain.pathGoal == brain.combatPosition then
				brain.combatRoute = { path = brain.path, idx = brain.pathIdx, repath = brain.nextRepath }
			else
				brain.combatPosition, brain.combatRoute = nil, nil
			end
		end
		if lib.SafeCombatMove then lib.SafeCombatMove(ctx.bot, brain, now) end

		return true
	end,
})
