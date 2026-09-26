-- Active Shooter mode wiring for zc_bots (Part A.1). Round key "activeshooter"
-- (US1 modes/zz_activeshooter/sh_zz_activeshooter.lua:4).
--
-- VERIFIED (US1 tree, this session):
--   sh_zz_activeshooter.lua:3-12 -- MODE.base="hmcd", MODE.Chance=0 (confirmed
--     by direct grep, matching the brief's own note), MODE:CanLaunch()
--     unconditionally `return true` (no player-count/map-point gate) -- so
--     the mode IS launchable standalone, just never picked by the normal
--     weighted-chance roll; only admin/vote (or this package's own
--     sv_lowpop.lua LOCK_CHANCES override) can select it. That satisfies the
--     brief's own condition for giving it a lock weight.
--   sv_zz_activeshooter.lua:18-41 -- MODE:Intermission() does NOT run its own
--     top-up loop the way masscasualty's does; it delegates the whole traitor
--     selection to `zb.modes["hmcd"].Intermission(self)` (self ==
--     zb.modes.activeshooter here, so hmcd's own generic role-count formula
--     runs against activeshooter's own Types/Roles tables, which this same
--     function copies onto hmcd first).
--   modes/homicide/sv_homicide.lua:1166-1173 -- hmcd's needed-count formula:
--     `traitors_needed = math.min(player_count - 1, homicide_traitoramount:GetInt())`,
--     UNLESS MODE.ShouldStartRoleRound() is true, which it never is (a hard
--     `do return false end`, sv_homicide.lua:1702-1705, already cited by
--     modes/sv_masscasualty.lua for the same function). So activeshooter's
--     real needed-count is `min(playerCount-1, homicide_traitoramount)`, NOT
--     masscasualty's `min(3, floor(playerCount/2))` -- confirmed different,
--     per the brief's explicit warning not to assume they match.
--     `homicide_traitoramount` (sv_homicide.lua:1131) defaults to 1 -- an
--     "active shooter" is singular by default, matching the mode's name.
--   sh_zz_activeshooter.lua:82-92 -- MODE.Types.activeshooter.TraitorLoot
--     exists (used below); no `zb.GiveRole(ply, "Active Shooter", ...)` call
--     was found anywhere in this mode's files (grepped both activeshooter
--     source files) -- only Police Officer gets an explicit GiveRole call
--     (sh_zz_activeshooter.lua:149). The shooter's own role/name display is
--     therefore carried entirely by hmcd's isTraitor/MainTraitor/TraitorWord
--     plumbing, so this file passes no roleName to the shared wrap (unlike
--     masscasualty's verified "Mass Shooter" GiveRole call).
--
-- Sibling of modes/sv_masscasualty.lua: this file reuses
-- hg.botdriver.WrapShooterIntermission (sv_shooter_modes.lua, Part A.1) for
-- the park/promote/unpark plumbing, and duplicates only the small
-- sweep-when-idle helper (RandomSpawns nearest-unvisited-point walk) since
-- that piece is intentionally NOT part of the shared wrap -- it is this
-- mode's own MODE-band targeting behavior, not Intermission bookkeeping.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}

local function neededShooters(playerCount)
	local cv = ConVarExists("homicide_traitoramount") and GetConVar("homicide_traitoramount")
	local amount = cv and cv:GetInt() or 1
	return math.min(math.max(playerCount - 1, 0), amount)
end

local function installWrap()
	hg.botdriver.WrapShooterIntermission({
		modeKey = "activeshooter",
		needed = neededShooters,
		typesKey = "activeshooter",
		-- roleName intentionally omitted -- see header, no verified GiveRole
		-- call for this role on US1.
	})
end

hook.Add("InitPostEntity", "zc_bots_activeshooter_wrap", installWrap)
hg.botdriver._shooterReinstall["activeshooter"] = installWrap
installWrap() -- covers lua_openscript loading this file mid-session

----------------------------------------------------------------------
-- Mode profile: identical relationship shape to masscasualty (shooter fights
-- non-traitor living players; other traitors, if the convar is ever raised
-- above 1, are allies) -- installed as its own MODE-band behavior rather than
-- overriding the shared hg.botdriver.EnemyOf/AllyOf, same reasoning as
-- modes/sv_masscasualty.lua's own comment on this.
----------------------------------------------------------------------

local function shooterEnemyOf(bot)
	return function(ent)
		if not IsValid(ent) or ent == bot or not ent:IsPlayer() then return false end
		if not ent:Alive() then return false end
		if ent:Team() == TEAM_SPECTATOR then return false end
		return ent.isTraitor ~= true
	end
end

local function shooterAllyOf(bot)
	return function(ent)
		return IsValid(ent) and ent ~= bot and ent:IsPlayer() and ent.isTraitor == true
	end
end

-- PROVISIONAL(2026-09-21, same reasoning as modes/sv_masscasualty.lua's own
-- sweepTarget -- no verified "patrol route" concept exists for this mode
-- either, ratify-by: 2026-10-15)
local function sweepTarget(bot, brain)
	local pts = zb.GetMapPoints and zb.GetMapPoints("RandomSpawns")
	if not istable(pts) or #pts == 0 then return nil end

	brain.asVisited = brain.asVisited or {}
	local pos = bot:GetPos()
	local best, bestIdx, bestDistSqr

	for i, pt in ipairs(pts) do
		if not brain.asVisited[i] and istable(pt) and isvector(pt.pos) then
			local distSqr = pos:DistToSqr(pt.pos)
			if not bestDistSqr or distSqr < bestDistSqr then
				best, bestIdx, bestDistSqr = pt.pos, i, distSqr
			end
		end
	end

	if not best then
		brain.asVisited = {}
		for i, pt in ipairs(pts) do
			if istable(pt) and isvector(pt.pos) then
				local distSqr = pos:DistToSqr(pt.pos)
				if not bestDistSqr or distSqr < bestDistSqr then
					best, bestIdx, bestDistSqr = pt.pos, i, distSqr
				end
			end
		end
	end

	if best and bestIdx and pos:DistToSqr(best) <= (96 * 96) then
		brain.asVisited[bestIdx] = true
	end
	return best
end

hg.botdriver.DeclareBrainState("activeshooter", { fields = { "asVisited" } })

hg.botdriver.RegisterBehavior({
	name = "activeshooter.shooter_targeting",
	band = "MODE",
	order = 10,
	default = false,
	finalize = { path = true, roam = true },
	CanRun = function(ctx)
		if ctx.roundKey ~= "activeshooter" then return false end
		if not ctx.bot.isTraitor then return false end
		ctx._enemyOf = shooterEnemyOf(ctx.bot)
		ctx._allyOf = shooterAllyOf(ctx.bot)
		local target = ctx:AcquireTarget()
		return not IsValid(target)
	end,
	Run = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		local dest = sweepTarget(bot, brain)
		if dest then
			hg.botdriver.lib.PathTo(bot, brain, dest, now, 1.5)
		end
		return true
	end,
})

hg.botdriver.RegisterModeProfile("activeshooter", {
	behaviors = { "activeshooter.shooter_targeting" },
})
