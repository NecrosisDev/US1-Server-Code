-- Mass Casualty mode wiring for zc_bots.
--
-- Round key: "masscasualty" -- zz_masscasualty's MODE.name (US1
-- modes/zz_masscasualty/sh_zz_masscasualty.lua:4) is what loader.lua's
-- InitMode() stores into zb.modes[name] (loader.lua:80), and zb:GetMode(round)
-- returns `round` unchanged whenever zb.modes[round] already exists
-- (libraries/sv_roundsystem.lua:13-21). So when this mode is live,
-- zb.CROUND == zb.CROUND_MAIN == "masscasualty" -- NOT "hmcd". hmcd is a
-- separate, independently-selectable round with its own CROUND == "hmcd";
-- no alias is registered for it here.
--
-- UNVERIFIED: none. Every mechanism this file depends on (Intermission
-- delegation chain, TraitorLoot/GiveRole call sites, TEAM_SPECTATOR/team-0
-- semantics, the RandomSpawns point set, SpawnForce field names) was read
-- directly from the US1 reference tree; see the report accompanying this
-- change for exact file:line citations. The one behaviour NOT dictated by
-- the porting brief -- what a parked bot's un-suppressed sweep objective
-- looks like -- is marked PROVISIONAL below at its own site.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}

----------------------------------------------------------------------
-- Idempotent wrap of zb.modes.masscasualty.Intermission
--
-- Verified call chain (US1 modes/zz_masscasualty/sv_zz_masscasualty.lua):
--   MODE:Intermission() [lines 3-86]
--     -> zb.modes["hmcd"].Intermission(self) [line 25], which is US1
--        modes/homicide/sv_homicide.lua's MODE:Intermission [line 1133]:
--        it KillSilent()s and resets isTraitor/isGunner/MainTraitor/SubRole/
--        Profession/isPolice for every non-spectator player (sv_homicide.lua
--        1145-1160, gated by `ply:Team() == TEAM_SPECTATOR then continue`),
--        then rolls its own traitor picks against `self` (the masscasualty
--        MODE table, so self.Types.masscasualty / self.Roles.masscasualty
--        apply). ShouldStartRoleRound() is a hard `do return false end`
--        (sv_homicide.lua:1702-1705), so the HMCD_RoundStart net message
--        block (sv_homicide.lua:1247-1272, gated on that same function) never
--        fires during Intermission.
--     -> timer.Simple(0.5, ...) [sv_zz_masscasualty.lua 27-59]: tops up to
--        `needed = math.min(3, math.floor(#player.GetAll() / 2))` traitors,
--        candidates are non-traitor, non-spectator (`ply:Team() ~=
--        TEAM_SPECTATOR`) players (lines 38-41), and for each pick it calls
--        `hmcd.Types.masscasualty.TraitorLoot(target)` [line 53] then
--        `zb.GiveRole(target, "Mass Shooter", Color(190, 0, 0))` [line 56].
--
-- CORRECTION vs the porting brief: `MODE:GiveEquipment` (sv_homicide.lua
-- 1756-1757) is an EMPTY stub on US1 -- it does nothing. The loot-on-spawn
-- application actually happens in MODE.SpawnPlayers (called from
-- MODE:RoundStart at sv_homicide.lua:1752), which calls
-- `MODE.Types[MODE.Type].TraitorLoot(current_ply)` for every `isTraitor`
-- player at spawn time (sv_homicide.lua:2141-2143). This file does not rely
-- on GiveEquipment for anything.
--
-- zb.GiveRole signature verified at US1
-- libraries/sh_giverole.lua:4 -- `function zb.GiveRole(ply, name, color)`.
--
-- TEAM_SPECTATOR is never locally redefined anywhere in the US1 zcity
-- gamemode (grepped the whole addon tree) -- it resolves to GMod's engine
-- global (TEAM_SPECTATOR == 1 by default). The "back in the round" team is
-- team 0 (TEAM_UNASSIGNED), verified via `ply:SetupTeam(0)`
-- (sv_homicide.lua:1156, modes/{dm,sfd,eventhandler}/sv_*.lua) and
-- `PLAYER:SetupTeam` (US1 init.lua:197-203, just `self:SetTeam(team_)` plus
-- inventory/spawn setup). This CORRECTS the porting brief's guess of team 1.

-- 2026-09-21: this Intermission wrap now delegates to the shared
-- hg.botdriver.WrapShooterIntermission helper (sv_shooter_modes.lua, Part
-- A.1 of the mode expansion) -- it was the first mode to need this exact
-- shape, and modes/sv_activeshooter.lua now reuses the same park/promote/
-- unpark plumbing with its own verified needed-count formula instead of a
-- second copy of this code. The unpark-on-ZB_EndRound hook also now lives in
-- sv_shooter_modes.lua (keyed per modeKey), so this file no longer registers
-- its own.
local function installMcWrap()
	hg.botdriver.WrapShooterIntermission({
		modeKey = "masscasualty",
		needed = function(playerCount) return math.min(3, math.floor(playerCount / 2)) end,
		typesKey = "masscasualty",
		roleName = "Mass Shooter",
		roleColor = Color(190, 0, 0),
	})
end

hook.Add("InitPostEntity", "zc_bots_masscasualty_wrap", installMcWrap)
hg.botdriver._shooterReinstall["masscasualty"] = installMcWrap
installMcWrap() -- covers lua_openscript loading this file mid-session

----------------------------------------------------------------------
-- Mode profile: shooter bots fight only living non-traitor players;
-- everyone else (unarmed/other-traitor zcBots) falls through untouched to
-- the generic ACQUIRE/COMBAT/IDLE bands, which is why this file registers
-- a MODE-band behavior instead of overriding the shared hg.botdriver.EnemyOf.
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

-- PROVISIONAL(2026-09-21, no verified "civilian sweep route" concept exists
-- on US1 for this mode -- RandomSpawns is a generic point set shared by sfd/
-- eventhandler/sv_roundsystem, not a masscasualty-specific patrol route, so
-- nearest-first-with-visited-set over it is this port's own choice for what
-- a shooter without a target does between engagements, ratify-by:
-- 2026-10-15) Sweep target selection: nearest unvisited RandomSpawns point,
-- falling back to a full reset of the visited set once exhausted.
local function sweepTarget(bot, brain)
	local pts = zb.GetMapPoints and zb.GetMapPoints("RandomSpawns")
	if not istable(pts) or #pts == 0 then return nil end

	brain.mcVisited = brain.mcVisited or {}
	local pos = bot:GetPos()
	local best, bestIdx, bestDistSqr

	for i, pt in ipairs(pts) do
		if not brain.mcVisited[i] and istable(pt) and isvector(pt.pos) then
			local distSqr = pos:DistToSqr(pt.pos)
			if not bestDistSqr or distSqr < bestDistSqr then
				best, bestIdx, bestDistSqr = pt.pos, i, distSqr
			end
		end
	end

	if not best then
		brain.mcVisited = {}
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
		brain.mcVisited[bestIdx] = true
	end
	return best
end

local RB = hg.botdriver.RegisterBehavior

-- MODE band runs before ACQUIRE/COMBAT (BAND_ORDER in sv_arbiter.lua), so
-- installing ctx._enemyOf/_allyOf here -- rather than overriding the shared
-- hg.botdriver.EnemyOf/AllyOf, which every other mode also reads -- is what
-- lets combat.engage (behaviors/sv_core_combat.lua) and any later ACQUIRE
-- behavior pick up the masscasualty-specific relationship for the rest of
-- this tick via ctx:EnemyOf()/ctx:AcquireTarget()'s own memoization
-- (sv_arbiter.lua ctxMeta:EnemyOf/AcquireTarget). Everyone else (bots that
-- are not shooters this round) is untouched and keeps the generic
-- team-based hg.botdriver.EnemyOf.
--
-- Caveat: SURVIVAL band's survival.downed-fallback (sv_core_survival.lua)
-- can call ctx:EnemyOf() before MODE runs, but only when sv_survival.lua's
-- ApplySurvivalPreemption is entirely absent -- a defence-in-depth path this
-- package's own loader (autorun/server/sv_zc_bots.lua) does not normally hit.
RB({
	name = "masscasualty.shooter_targeting",
	band = "MODE",
	order = 10,
	default = false,
	finalize = { path = true, roam = true },
	CanRun = function(ctx)
		if ctx.roundKey ~= "masscasualty" then return false end
		if not ctx.bot.isTraitor then return false end
		ctx._enemyOf = shooterEnemyOf(ctx.bot)
		ctx._allyOf = shooterAllyOf(ctx.bot)
		local target = ctx:AcquireTarget()
		-- Claim (sweep) only when nothing to fight; otherwise decline so the
		-- shared ACQUIRE/COMBAT bands engage with the target already cached.
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

-- Shooters squad up through sv_squad.lua like any team: parked bots are
-- spectators, so the only zcBots left on team 0 are the shooters.

hg.botdriver.RegisterModeProfile("masscasualty", {
	behaviors = { "masscasualty.shooter_targeting" },
	suppress = {},
	-- IntermissionCombat left unset (nil/false): RoundAllowsCombat() already
	-- gates lib.Engage during pre-round freeze (sv_arbiter.lua:79-86, honored
	-- by lib.Engage per sv_brain.lua:577-581), so no extra check is needed
	-- here and shooters correctly hold fire until the round actually starts.
})
