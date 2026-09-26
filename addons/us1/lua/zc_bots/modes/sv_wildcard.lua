-- Wildcard mode wiring (Part A.3). Round key "wildcard" (US1
-- modes/wildcard/sh_wildcard.lua:1, MODE.name).
--
-- Confirmed directly this session: sv_wildcard.lua's own comment marks it as
-- "mode skeleton (hl2dm structure)" (line 338) and `MODE:Intermission`
-- (lines 347-355) calls `ply:SetupTeam(ply:Team())` for every player --
-- keeping whatever two-team split the round system already assigned, not a
-- team reroll -- while each player separately rolls a cosmetic class
-- override (rebel/combine/gangster/SWAT/police/national-guard/51-fighter
-- variant loadouts, sv_wildcard.lua:254-335) that changes their WEAPONS and
-- appearance but not their team or the elimination win condition
-- (`MODE:CheckAlivePlayers` delegates to `zb:CheckAliveTeams(true)`, line
-- 358-359 -- a team-based alive check, confirming it stays a two-team mode
-- under the cosmetic reroll). `MODE:CanLaunch()` is `#zb:CheckPlaying() >= 2`
-- (line 424-426) -- zb:CheckPlaying() is the same all-players (bots
-- included) helper modes/sv_criresp.lua's header already verified.
--
-- Effectively "tdm/hl2dm with a twist" per the brief's own framing: the twist
-- is purely cosmetic (weapon/skin variety per spawn), so this file is exactly
-- as thin as modes/sv_gwars.lua's -- squad-push only, via the shared
-- SquadPushModes registry. No bespoke weapon-choice logic is needed:
-- whichever of the 14 class templates a bot rolls, sv_weaponscore.lua scores
-- whatever it is actually holding by category/ismelee, generic to any
-- loadout.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}

hg.botdriver.SquadPushModes = hg.botdriver.SquadPushModes or {}
hg.botdriver.SquadPushModes.wildcard = true

hg.botdriver.RegisterModeProfile("wildcard", {
	behaviors = { "mode.tdm_squad_push" },
})
