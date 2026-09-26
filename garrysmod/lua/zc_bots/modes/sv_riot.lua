-- Riot mode wiring (Part A.2). Round key "riot" (US1 modes/riot/sv_riot.lua:1,
-- MODE.name).
--
-- Research pass findings (this session): two dynamic teams sized by player
-- count -- rioters (majority) vs. law enforcement (floor(numPlayers/2)),
-- sv_riot.lua:102-148. Rioters carry melee weapons (leadpipe, brick, hammer,
-- bat, shovel) plus one molotov and one mp-80; law enforcement carries a
-- tonfa, taser, walkie-talkie, handcuffs, and a ram/shotgun for the first two
-- officers (sv_riot.lua:9-37, 151-194). Launch guard
-- (sv_riot.lua:204-217, read directly this session):
--   `for _, ply in player.Iterator() do if ply:Team()~=TEAM_SPECTATOR then
--   activePlayers=activePlayers+1 end end; if activePlayers<5 then return
--   false end` -- player.Iterator() is the stock all-players iterator (no
--   local override anywhere in this addon, confirmed by the same
--   CheckPlaying-adjacent grep modes/sv_criresp.lua's header cites), so a bot
--   DOES count toward the 5-player floor -- this is a correction against the
--   research pass's own "(humans only)" inference for this exact call.
--
-- No special AI logic is added for the rioter-vs-police asymmetry: the melee
-- brain (sv_melee.lua) already refuses to close on a visible gun across open
-- ground (shouldCommit()'s isGun/COMMIT_RANGE/facing checks) and instead
-- breaks line of sight and works closer, which is exactly "melee-heavy
-- rioters use the melee brain and don't suicide-charge rifles" -- no rifle
-- exists on either loadout here regardless (police carry tonfa/taser/
-- shotgun, not a rifle), and sv_weaponscore.lua's roleOf() already classes
-- tonfa/taser as melee/generic via wep.ismelee or its SWEP.Category, with no
-- unmapped-weapon crash risk (an unmapped category just falls through
-- WeaponProfile's `if not role then return nil end`, scoring 0 -- verified by
-- reading sv_weaponscore.lua directly, not assumed).

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}

hg.botdriver.SquadPushModes = hg.botdriver.SquadPushModes or {}
hg.botdriver.SquadPushModes.riot = true

hg.botdriver.RegisterModeProfile("riot", {
	behaviors = { "mode.tdm_squad_push" },
})
