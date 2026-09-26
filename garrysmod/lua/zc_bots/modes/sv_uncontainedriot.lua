-- Uncontained Riot mode wiring (Part A.2). Round key "uncontainedriot" (US1
-- modes/zz_uncontained_riot/sv_uncontainedriot.lua:6, MODE.name -- confirmed
-- by direct grep; note the folder is zz_uncontained_riot but the round key
-- has no underscore).
--
-- Research pass findings (this session): two teams sized by player count --
-- law enforcers (floor(numPlayers/3), min 1) vs. rioters (the remainder),
-- sv_uncontainedriot.lua:152-221. Rioters roll a weighted loadout (40%
-- pistol / 25% rifle / 25% shotgun / 10% melee-only, plus a chance at
-- pipebombs/molotovs and light armor); police get an AR15, Glock17, tonfa,
-- taser, walkie-talkie, handcuffs+key, medical items, a flashbang and a smoke
-- grenade, plus heavy armor (sv_uncontainedriot.lua:152-269). Confirmed
-- directly this session: `MODE:CanLaunch()` (sv_uncontainedriot.lua:279-293)
-- is the exact same shape as modes/sv_riot.lua's own guard --
--   `for _, ply in player.Iterator() do if ply:Team()~=TEAM_SPECTATOR then
--   activePlayers=activePlayers+1 end end; if activePlayers<5 then return
--   false end` -- so bots count toward its 5-player floor too, for the same
--   reason (player.Iterator() has no local override in this addon tree).
--
-- Unlike riot, this mode's rioters CAN roll a rifle (25% chance) -- the
-- brief's "melee-heavy rioters... don't suicide-charge rifles" note applies
-- to whichever rioters roll melee-only (10%) or end up disarmed; a
-- rifle-rolling rioter is just a regular COMBAT-band gun user like any other
-- team mode, no special-casing needed. Police's less-lethal gear (taser,
-- tonfa) is scored the same way modes/sv_riot.lua's header already verified
-- for sv_weaponscore.lua (falls through to 0 rather than crashing when
-- unmapped, read directly from WeaponProfile()).

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}

hg.botdriver.SquadPushModes = hg.botdriver.SquadPushModes or {}
hg.botdriver.SquadPushModes.uncontainedriot = true

hg.botdriver.RegisterModeProfile("uncontainedriot", {
	behaviors = { "mode.tdm_squad_push" },
})
