-- Mayhem mode wiring (Part A.3). Round key "mayhem" (US1
-- modes/zz_mayhem/sv_zz_mayhem.lua:3, MODE.name).
--
-- Confirmed directly this session (sv_zz_mayhem.lua:16-117): every non-
-- spectator player is `ply:SetupTeam(0)`'d in Intermission (line 29) with no
-- team split anywhere else in the file; MODE:ShouldRoundEnd() is
-- `#zb:CheckAlive(true) <= 1` (line 51) -- a plain last-one-standing FFA.
-- MODE:RoundStart (lines 54-93) gives every player ONLY weapon_hands_sh
-- (fists) plus a berserk/analgesia/recoil buff -- MODE:GiveWeapons and
-- MODE:GiveEquipment are both empty stubs (lines 95-99), so no real weapon
-- is ever issued. MODE:CanLaunch() is an unconditional `return true`
-- (line 16-18); MODE.Chance = 0.03 (line 11).
--
-- This needs no bespoke mode file beyond registering "mayhem" as FFA
-- (sv_shim.lua's hg.botdriver.FFAModes, this same change) -- the generic
-- EnemyOf/AllyOf already treat every other actor as hostile once that flag
-- is set, and sv_melee.lua's fists-raise-on-IN_ATTACK path already handles a
-- fists-only fight (this mode never gives a real weapon). Registered here
-- only for documentation/consistency with every other supported mode having
-- its own modes/sv_<key>.lua, and as the seam a later phase could extend
-- (e.g. an explicit spread-out-from-spawn opener) without touching sv_shim.lua.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}

hg.botdriver.RegisterModeProfile("mayhem", {})
