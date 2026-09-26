-- Jump kick (airborne leg attacks), nativized 2026-09-24 from the loose addon addons/pat's_jump_kick (moved to
-- data/zc_bak_moved_20260924/addons/ at the same time). Globals, convars and hook ids are unchanged (PAT_JumpKick,
-- pat_jumpkick_*, PAT_JumpKick_*). The addon's client file only re-included the shared file, so it has no counterpart.
if SERVER then AddCSLuaFile("zc_jumpkick/sh_jumpkick.lua") end
include("zc_jumpkick/sh_jumpkick.lua")
if SERVER then include("zc_jumpkick/sv_jumpkick.lua") end
