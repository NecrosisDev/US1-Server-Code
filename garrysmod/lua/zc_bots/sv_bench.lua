-- Bench (spectator-park) AI bots out of any round they have no profile for.
-- 2026-09-22 SECOND REVERSAL: the owner watched bots play Homicide (hmcd)
-- badly under the "join every round as generic crowd" policy sv_crowd.lua
-- and sv_fill.lua's own SupportedModes comment used to describe, and now
-- wants the opposite -- a bot must be forced to TEAM_SPECTATOR for the WHOLE
-- of any round whose mode key is not in hg.botfill.SupportedModes
-- (sv_fill.lua), and restored to play the moment a supported round starts.
-- sv_crowd.lua is left in place, not deleted -- see its own header, it is
-- now only the fallback for a single-team edge case inside a SUPPORTED mode.
--
-- SINGLE AUTHORITY, so this cannot fight hg.botfill.EnsurePlaying
-- (sv_fill.lua): EnsurePlaying's only job is "move a zcBot off
-- unassigned/spectator onto team 1" (it exists because a bot has no client
-- to send the ZB_SpecMode net message a human's "join players" click sends,
-- verified init.lua:399-409); it has been given exactly one added line --
-- skip a bot whose ply.zcBotBenched flag is currently true -- and it never
-- sets TEAM_SPECTATOR itself. This file is the ONLY place that ever sets
-- TEAM_SPECTATOR on a zcBot or flips ply.zcBotBenched. Ordering argument
-- (why the two files' independent ZB_PreRoundStart hooks cannot oscillate,
-- whichever runs first): sv_fill.lua's own hook is now a no-op for any bot
-- this file benches (EnsurePlaying's new skip-guard) or is about to bench
-- (that bot's team was already 0/1 from the PREVIOUS, supported round, so
-- EnsurePlaying's unassigned/spectator check does not match yet either way);
-- and whenever THIS file decides a bot should be UNbenched, it clears the
-- flag and positively calls EnsurePlaying itself in the same function call,
-- rather than assuming sv_fill.lua's loop already ran or will run. Neither
-- file depends on running before or after the other for the round-end state
-- to be correct.
--
-- Entry paths covered (owner brief, 2026-09-22):
--   1. Round transition -- ZB_PreRoundStart below, keyed on zb.nextround,
--      NOT zb.CROUND/zb.CROUND_MAIN. Verified (sv_roundsystem.lua:156-159):
--      hook.Run("ZB_PreRoundStart") fires BEFORE `zb.CROUND = zb.nextround or
--      "hmcd"` runs, so CROUND/CROUND_MAIN still name the OLD round at this
--      point -- only zb.nextround names the round about to start. The same
--      `or "hmcd"` fallback is reused here for consistency with that line.
--      This also runs before zb:KillPlayers()/zb:AutoBalance() (called later
--      in the same synchronous RoundStart flow), both of which already skip
--      TEAM_SPECTATOR players themselves (verified sv_roundsystem.lua:215,
--      sv_teamsetup.lua:25+30) -- so a bot benched here is never handed a
--      fresh :Spawn() by either of them for the round that follows.
--   2. A bot added mid-round -- zc_bots_add works at any round state
--      (sv_fill.lua's own comment on that concommand), unlike the auto-fill
--      Tick. sv_fill.lua's addBot() now calls hg.botfill.AssertBench(bot)
--      (below) before EnsurePlaying in its post-creation timer, using the
--      CURRENT round key (zb.CROUND_MAIN or zb.CROUND -- the idiom
--      sv_arbiter.lua/sv_diagnose.lua/the zc_bots_add concommand already use)
--      since there is no "next round" at that moment.
--   3. Any other spawn, from any cause -- the backstop. GM:PlayerSpawn
--      (init.lua:215-239 on the 2026-09-25 live tree) un-spectates and
--      assigns a playing team via zb:BalancedChoice(0,1) every time :Spawn()
--      is called -- it never preserves TEAM_SPECTATOR. CORRECTED 2026-09-25:
--      hook.Add("PlayerSpawn", ...) callbacks run BEFORE the gamemode's own
--      function (GMod wiki, Hook Library Usage), so the backstop defers one
--      tick (timer.Simple(0), the same trick sv_identity.lua uses) and only
--      then re-benches; acting inside the hook was undone by GM:PlayerSpawn a
--      moment later. This branch deliberately never touches a NOT-benched
--      bot's team (see reassertSpawn()'s comment below) so it does not race
--      sv_fill.lua's own ~1s post-creation EnsurePlaying timer for a
--      brand-new bot's very first spawn.
--
-- "Not competent" = hg.botfill.SupportedModes[roundKey] ~= true. That table
-- is the authority (owner brief) -- this file never adds/removes a mode from
-- it. DRIFT FOUND, reported not fixed (owner brief: do not edit the list):
-- of the 18 keys currently in SupportedModes (sv_fill.lua), 16 have a
-- matching `hg.botdriver.RegisterModeProfile("<key>", ...)` call under
-- zc_bots/modes/*.lua (grepped this session, one call per file, no
-- `aliases` field used anywhere). The two WITHOUT one: "hmcd" and
-- "Cops/Gangsters" -- both are exactly the modes sv_crowd.lua's own header
-- names as its verified generic-crowd examples. Practical effect: because
-- SupportedModes (not "has a real profile") is what this file benches
-- against, hmcd and Cops/Gangsters bots are NOT benched by this change and
-- keep running sv_crowd.lua's generic behavior exactly as before -- which
-- for hmcd is the single-team-plus-isTraitor shape the owner's own "bots
-- play Homicide badly" report was about. Cops/Gangsters is a genuinely
-- team-split mode (verified, sv_crowd.lua header) so its generic-crowd
-- fallback is comparatively sound; hmcd's is not. Whether hmcd should be
-- removed from SupportedModes (which would bench it under this file) is an
-- owner call, not made here.
--
-- Cost: near-zero when zc_bots_enable is 0 or for a human (every entry point
-- checks hg.botdriver.Enabled()/ply.zcBot first, same as every other file in
-- this package). Both hooks are event-driven (a round transition or a life
-- spawning), never per-tick; no ents.GetAll/FindByClass, no per-tick
-- allocation. Re-runnable under autorefresh: hook.Add replaces by name,
-- every table access is guarded with `X = X or {}`.

if not SERVER then return end

hg = hg or {}
hg.botfill = hg.botfill or {}
hg.botdriver = hg.botdriver or {}

local function benchReasonText(roundKey)
	return string.format("mode '%s' has no bot profile", tostring(roundKey))
end

-- Shared core: if `roundKey` is not competent, force TEAM_SPECTATOR + flag +
-- unschedule (item 6: genuinely inert -- no decision left scheduled for it,
-- belt-and-braces alongside PlayerDeath's own unschedule when :Kill() below
-- fires one). Returns true when it benched (or kept benched) the bot, so
-- callers can decide what "did not bench" means for them (see
-- applyBenchState vs reassertSpawn).
local function benchIfNeeded(bot, roundKey)
	local shouldBench = roundKey ~= nil and not hg.botfill.SupportedModes[roundKey]
	if not shouldBench then return false end
	bot.zcBotBenched = true
	bot.zcBotBenchReason = benchReasonText(roundKey)
	-- Kill first if alive, then set the team (the human "join spectators"
	-- shape, init.lua ZB_SpecMode). KillSilent, as the gamemode's own
	-- zb:ResetRoundPlayer does: a bench is bookkeeping, not a death, so it
	-- must not fire PlayerDeath (death chat, relations, kill stats).
	if bot:Alive() then bot:KillSilent() end
	if bot:Team() ~= TEAM_SPECTATOR then bot:SetTeam(TEAM_SPECTATOR) end
	local brain = hg.botdriver.brains and hg.botdriver.brains[bot]
	if brain and hg.botdriver.UnscheduleDecision then hg.botdriver.UnscheduleDecision(brain) end
	return true
end

-- Full authority: bench OR actively restore play. Used wherever a bot's team
-- needs a POSITIVE decision one way or the other right now -- a round
-- transition (every managed bot) and a freshly created bot (which has no
-- team yet worth leaving alone).
local function applyBenchState(bot, roundKey)
	if benchIfNeeded(bot, roundKey) then return end
	if bot.zcBotBenched then
		bot.zcBotBenched = nil
		bot.zcBotBenchReason = nil
	end
	if hg.botfill.EnsurePlaying then hg.botfill.EnsurePlaying(bot) end
end

-- Backstop-only variant for the PlayerSpawn hook (entry path 3): only ever
-- forces TEAM_SPECTATOR when the round calls for it. When it does NOT, this
-- deliberately does not touch team/call EnsurePlaying -- GM:PlayerSpawn has
-- already assigned this spawn's playing team (or, for a brand-new bot's
-- ply.initialspawn branch, deliberately left it on TEAM_UNASSIGNED for
-- sv_fill.lua's own ~1s post-creation timer to pick up, same as before this
-- file existed). It only clears a stale bench flag so zc_bots_list/
-- zc_bots_diagnose stop reporting an unbenched bot as benched.
local function reassertSpawn(bot, roundKey)
	if benchIfNeeded(bot, roundKey) then return end
	if bot.zcBotBenched then
		bot.zcBotBenched = nil
		bot.zcBotBenchReason = nil
	end
end

-- Entry path 2: a freshly created bot, current round key (there is no "next
-- round" concept mid-creation). Called from sv_fill.lua's addBot().
function hg.botfill.AssertBench(bot)
	if not IsValid(bot) or not bot.zcBot then return end
	if not hg.botdriver.Enabled() then return end
	local roundKey = zb and (zb.CROUND_MAIN or zb.CROUND)
	applyBenchState(bot, roundKey)
end

function hg.botfill.IsBenched(bot)
	return IsValid(bot) and bot.zcBotBenched == true
end

function hg.botfill.BenchReason(bot)
	return IsValid(bot) and bot.zcBotBenchReason or nil
end

-- Entry path 1: round transition, keyed on zb.nextround (see file header).
hook.Add("ZB_PreRoundStart", "zc_bots_bench_preround", function()
	if not hg.botdriver.Enabled() then return end
	if not (hg.botfill.ManagedBots and zb) then return end
	local nextKey = zb.nextround or "hmcd"
	for _, bot in ipairs(hg.botfill.ManagedBots()) do
		applyBenchState(bot, nextKey)
	end
end)

-- Entry path 3: any spawn, from any cause (see file header for why
-- GM:PlayerSpawn itself cannot be trusted to leave a spectator alone).
-- Deferred one tick so it runs AFTER GM:PlayerSpawn's team assignment.
hook.Add("PlayerSpawn", "zc_bots_bench_spawn", function(bot)
	if not hg.botdriver.Enabled() then return end
	if not bot:IsBot() or not bot.zcBot then return end
	timer.Simple(0, function()
		if not IsValid(bot) or not hg.botdriver.Enabled() then return end
		local roundKey = zb and (zb.CROUND_MAIN or zb.CROUND)
		reassertSpawn(bot, roundKey)
	end)
end)
