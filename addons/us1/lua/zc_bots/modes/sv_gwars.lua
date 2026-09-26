-- Gwars mode wiring (Part A.2). Round key "gwars" (US1
-- modes/gwars/sv_gwars.lua:1, confirmed by direct grep of MODE.name).
--
-- Research pass findings (this session, subagent read of the mode's own
-- sv_/sh_ files -- team numbers/loadout not independently re-grepped line by
-- line in this pass):
--   Teams: two symmetric teams (0 Terrorist-style / 1 Counter-Terrorist-style
--     per gamemodes/zcity/gamemode/libraries/sh_teamsetup.lua), a third SWAT
--     wave spawning ~120s into the round (sv_gwars.lua:184-224).
--   Loadout: a random pistol per team from tblweps[ply:Team()], plus bandage/
--     tourniquet/fentanyl/hands -- all generic weapon classes sv_weaponscore.lua
--     already scores by SWEP.Category/ismelee, so no bespoke weapon-choice
--     logic is needed here.
--   Objective: pure elimination, no bomb/hostage/capture point.
--   Launch guard: `player.Iterator()` counts every connected player entity
--     (a stock GMod iterator equivalent to player.GetAll() -- confirmed no
--     local override exists anywhere in this addon tree), so a bot DOES
--     count toward gwars' player-count gate, contrary to the research pass's
--     own inference of "humans only". No explicit minimum was found gating
--     gwars' own CanLaunch beyond its generic map-point requirements.
--
-- Because gwars is a plain two-team elimination mode with no special
-- objective, this file only wires the mode-agnostic squad-push behavior
-- (modes/sv_tdm.lua) via the shared SquadPushModes registry -- the same
-- generic COMBAT/ACQUIRE/melee/weapon-scoring bands already handle the SWAT
-- third wave and any asymmetric loadout without a bespoke profile.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}

hg.botdriver.SquadPushModes = hg.botdriver.SquadPushModes or {}
hg.botdriver.SquadPushModes.gwars = true

hg.botdriver.RegisterModeProfile("gwars", {
	behaviors = { "mode.tdm_squad_push" },
})
