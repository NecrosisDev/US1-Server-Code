-- 2026-09-22 BENCH REVERSAL: hg.botfill.SupportedModes-driven benching
-- (zc_bots/sv_bench.lua) is now the PRIMARY mechanism for a round with no
-- registered profile -- a bot sits out the whole round on TEAM_SPECTATOR
-- instead of running the generic crowd behavior this file provides. This
-- file is the FALLBACK, still reachable for the single-team edge case inside
-- a listed/profiled (i.e. NOT benched) mode, e.g. masscasualty before roles
-- are assigned -- see the rest of this header, which still describes that
-- case accurately.
--
-- Generic crowd behavior for rounds with NO registered mode profile (Task 3,
-- 2026-09-22). With a permanent population floor (sv_fill.lua), bots must
-- keep playing every round, including ones hg.botfill.SupportedModes never
-- listed (homicide itself, and any other round this package has no
-- dedicated modes/sv_<key>.lua file for) -- benching them as spectators there
-- would empty the server exactly when it should look full.
--
-- ARBITER-DEGRADES-SAFELY FINDING (verified this session, sv_arbiter.lua):
-- hg.botdriver.RunArbiter resolves `profile = ResolveModeProfile(roundKey)`,
-- which is nil for an unregistered round key. compileActive(roundKey, nil)
-- then builds `suppress`/`extra` from an absent profile as empty tables, so
-- the compiled behavior list is exactly every behavior with `def.default ~=
-- false` (RegisterBehavior defaults `def.default` to true when unset) --
-- i.e. every core band still runs unmodified: reflex.damage-response/
-- reflex.suppression-response/reflex.grenade-dodge (REFLEX), survival.preempt/
-- survival.downed-fallback/survival.outnumbered (SURVIVAL), acquire.scavenge
-- (ACQUIRE), combat.engage/combat.grenade (COMBAT), support.medical/
-- support.medic_ally/support.investigate (SUPPORT), idle.* (IDLE). None of
-- their CanRun functions require ctx.profile or a specific ctx.roundKey to be
-- non-nil (grepped every behaviors/*.lua file this session) -- a bot with no
-- profile still reflexes, self-treats, scavenges, fights and idles/roams
-- exactly like one in a profiled mode. It does NOT error or idle-freeze.
-- Conclusion: RunArbiter already degrades safely on its own; this file exists
-- only to fix the ONE thing that does not degrade safely -- the
-- relationship/friend-foe question below -- not to patch the arbiter itself.
--
-- FRIEND/FOE FINDING (verified this session): hg.botdriver.EnemyOf/AllyOf
-- (sv_brain.lua) are team-number comparisons (FFA aside). That is correct for
-- a genuinely team-split unsupported mode -- verified live example:
-- work/bots/us1/addons/cops_gangsters's "Cops/Gangsters" round
-- (sv_cb.lua:1, MODE.name = "Cops/Gangsters") really does `ply:Team() == 0`
-- (gangsters) vs `== 1` (cops), so the default team-based relationship is
-- SANE there and must be left alone. It is NOT sane for a homicide-family
-- round: US1 homicide/sv_homicide.lua puts every non-spectator player on team
-- 0 via `ply:SetupTeam(0)` (line 1156) with no team split at all; hostility is
-- carried entirely by `ply.isTraitor`, which this package's generic team
-- comparison never reads. Under the plain team-based default there, every
-- living player shares one team, so EnemyOf(ent) is false for literally
-- everyone. (Not "shoot everyone" either: that failure mode would require
-- IsFFA() to be true for the round, which it is not -- homicide is not in
-- hg.botdriver.FFAModes and carries no MODE.FFA field, verified by grepping
-- the whole US1 gamemode tree for `.FFA` this session, zero hits.)
--
-- 2026-09-22 POLICY REVISION (owner report: bots stall homicide-family
-- rounds and stay idle): the original DEFENSIVE-for-everyone policy below was
-- exactly the bug -- with nobody ever initiating, an hmcd round with no
-- human traitor has literally no source of violence, so it cannot resolve.
-- The fix is NOT "make everyone hostile" (that breaks the hidden-role social
-- mechanic homicide is built on -- an innocent does not start the round
-- already knowing who the traitor is) and NOT "leave it as pure defense"
-- (that is the stall). Split the two roles instead, using the same signal a
-- human plays by:
--   * A bot that IS the traitor (`ctx.bot.isTraitor`) gets the identical
--     hunt-everyone-else-living relationship this package already gives its
--     OWN promoted shooters in modes/sv_masscasualty.lua and
--     modes/sv_activeshooter.lua (traitorHostileEnemyOf/traitorAllyOf below
--     are the same shape as those files' shooterEnemyOf/shooterAllyOf,
--     reused rather than reinvented) -- the traitor's actual job is to
--     initiate, so now it does, and the round has a driver of action again.
--   * Every other (innocent) bot keeps the original DEFENSIVE relationship:
--     fight back at whoever damaged them recently, never initiate. This is
--     the deliberate non-omniscient half of the fix -- an innocent is not
--     handed traitorHostileEnemyOf's negation (that would just be "shoot
--     everyone who isn't me" relabelled), so the social-deduction mechanic
--     survives, while a bot that IS shot at still fights back instead of
--     dying passively.
-- This is strictly additive: with no active traitor split (nobody is a
-- traitor yet, e.g. before Intermission has picked, or a single-team mode
-- that never uses isTraitor at all) every bot still falls back to the
-- original all-DEFENSIVE behaviour, unchanged.
--
-- "fear" (named alongside hmcd in the report) was checked for directly this
-- session: grepped both work/main-design-source and work/bots/us1/addons for
-- a MODE.name/round key of "fear" -- zero hits (the only "fear" hits are the
-- unrelated fearbot_clean weapon addon). Only "hmcd" is a verified round key
-- with this single-team-plus-isTraitor shape; if "fear" is a real, separate
-- round on the live server this session could not see, it is not covered by
-- name, but IS covered by the runtime DETECTION below if it shares the same
-- shape (single team, isTraitor split).
--
-- DETECTION, not a mode-name allowlist: rather than hardcoding "homicide is
-- team-uniform, Cops/Gangsters is not" (this file must never assert a mode's
-- shape from a name it cannot re-verify every time a new unsupported mode
-- appears), this file checks at runtime whether the CURRENT round's living,
-- non-spectator players actually span more than one team number. If they do,
-- team-based hostility is real and this file steps aside entirely (default
-- hg.botdriver.EnemyOf/AllyOf keep governing, unmodified). If they do not
-- (everyone on one team, the homicide-family shape), this file substitutes
-- one of the two relationships above, chosen by a second runtime check
-- (roundHasTraitorSplit) rather than by mode name for the same reason. Both
-- scans are single player.GetAll() passes cached for their own TTL and
-- shared across every bot and every decision (round-level facts, not
-- per-bot ones) -- cheaper than the per-decision player.GetAll() passes
-- hg.botdriver.EnemyOf/Actors() already do unconditionally today.
--
-- Bots here are never routed into a special role (traitor/Homelander/etc.):
-- every such selection lives in an external wrap keyed to its OWN specific
-- round key (modes/sv_masscasualty.lua, modes/sv_activeshooter.lua,
-- modes/sv_homelanderhns.lua) and simply never fires for a round key it does
-- not match -- verified, no new wrap added or needed here for a mode this
-- session cannot verify.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}

local RB = hg.botdriver.RegisterBehavior

local TEAM_DIVERSITY_TTL = 2
local diversityCache = { roundKey = false, validUntil = -1, diverse = false }

local function roundHasTeamDiversity(roundKey, now)
	if diversityCache.roundKey == roundKey and now < diversityCache.validUntil then
		return diversityCache.diverse
	end
	local firstTeam, diverse = nil, false
	for _, ply in ipairs(player.GetAll()) do
		if IsValid(ply) and ply:Team() ~= TEAM_SPECTATOR then
			local team = ply:Team()
			if firstTeam == nil then
				firstTeam = team
			elseif team ~= firstTeam then
				diverse = true
				break
			end
		end
	end
	diversityCache.roundKey = roundKey
	diversityCache.validUntil = now + TEAM_DIVERSITY_TTL
	diversityCache.diverse = diverse
	return diverse
end

local TRAITOR_SPLIT_TTL = 2
local traitorCache = { validUntil = -1, split = false }

-- TRAITOR-SPLIT DETECTION: "split" means at least one living, non-spectator
-- player is currently a traitor AND at least one is not -- i.e. ply.isTraitor
-- is actually carrying information this round, not just sitting at its
-- post-round-reset value (US1 sv_homicide.lua:1150 sets it false for
-- everyone before each round's picks run). sv_homicide.lua's own Intermission
-- RandomPairs passes run over every non-spectator player with no :IsBot()
-- filter (the identical verified shape sv_shooter_modes.lua's header already
-- established for masscasualty/activeshooter's delegated Intermission calls),
-- so a zcBot picks up isTraitor exactly like a human would -- no wrap needed
-- here to make that happen.
local function roundHasTraitorSplit(now)
	if now < traitorCache.validUntil then return traitorCache.split end
	local sawTraitor, sawInnocent = false, false
	for _, ply in ipairs(player.GetAll()) do
		if IsValid(ply) and ply:Alive() and ply:Team() ~= TEAM_SPECTATOR then
			if ply.isTraitor then sawTraitor = true else sawInnocent = true end
			if sawTraitor and sawInnocent then break end
		end
	end
	traitorCache.validUntil = now + TRAITOR_SPLIT_TTL
	traitorCache.split = sawTraitor and sawInnocent
	return traitorCache.split
end

-- DEFENSIVE relationship (innocents, and the safe fallback with no traitor
-- split at all): reuses brain.attackedBy/damageUntil, which sv_brain.lua's
-- HomigradDamage listener already maintains for every bot
-- (reflex.damage-response's own seed) -- no new brain state to declare.
local function defensiveEnemyOf(bot, brain)
	return function(ent)
		if not IsValid(ent) or ent == bot or not ent:IsPlayer() then return false end
		if not ent:Alive() then return false end
		return ent == brain.attackedBy and CurTime() < (brain.damageUntil or 0)
	end
end

local function noAllies() return false end

-- TRAITOR relationship: identical shape to modes/sv_masscasualty.lua's and
-- modes/sv_activeshooter.lua's own shooterEnemyOf/shooterAllyOf for their
-- promoted shooters -- reused verbatim rather than reinvented, because a
-- homicide-family traitor's actual job is the same thing those modes model.
local function traitorHostileEnemyOf(bot)
	return function(ent)
		if not IsValid(ent) or ent == bot or not ent:IsPlayer() then return false end
		if not ent:Alive() or ent:Team() == TEAM_SPECTATOR then return false end
		return ent.isTraitor ~= true
	end
end

local function traitorAllyOf(bot)
	return function(ent)
		return IsValid(ent) and ent ~= bot and ent:IsPlayer() and ent.isTraitor == true
	end
end

RB({
	name = "crowd.unsupported_mode_relations",
	band = "MODE",
	order = 90,
	default = true,
	finalize = {},
	CanRun = function(ctx)
		if hg.botdriver.ResolveModeProfile(ctx.roundKey) ~= nil then return false end
		if roundHasTeamDiversity(ctx.roundKey, ctx.now) then return false end

		if ctx.bot.isTraitor and roundHasTraitorSplit(ctx.now) then
			-- The traitor initiates -- see file header for why this is not
			-- "shoot everyone" (only the traitor gets this; innocents do not).
			ctx._enemyOf = traitorHostileEnemyOf(ctx.bot)
			ctx._allyOf = traitorAllyOf(ctx.bot)
		else
			-- Innocent, or no traitor split exists yet -- stay reactive, not
			-- omniscient. See file header for why this is not "shoot nobody"
			-- either (a bot that IS attacked still fights back).
			ctx._enemyOf = defensiveEnemyOf(ctx.bot, ctx.brain)
			ctx._allyOf = noAllies
		end
		return false -- never claims the tick; only seeds the relationship for ACQUIRE/COMBAT/SUPPORT
	end,
	Run = function(ctx) return false end,
})
