-- NPC targeting for PvE modes (coop, defense). Adds engine-NPC/NextBot
-- awareness to the otherwise player-only targeting core, gated so every
-- hook here is a cheap early-return outside coop/defense and while
-- zc_bots_enable is 0 (brief hard rule).
--
-- VERIFIED (this session, work/bots/us1/addons/zcity/gamemodes/zcity/gamemode):
--   * modes/coop/sv_coop.lua -- native HL2 map NPCs (npc_combine_s,
--     npc_metropolice, npc_zombie), no mode-side spawn/scaling code; the
--     mode's own EntityTakeDamage listener ("dontfuckingdamagethem",
--     sv_coop.lua:136-142) reads Disposition() directly for guilt purposes,
--     confirming D_HT/D_LI/D_NU are the live relationship values on this
--     map's engine NPCs.
--   * modes/defense/sv_defense_waves.lua -- every DEFENSE_WAVE_DEFINITIONS
--     entry is spawned via SpawnWave() and stamped `npc.IsDefenseWaveNPC =
--     true` (sv_defense_waves.lua:364,421) or, for anything OnEntityCreated
--     independently notices while a wave is active,
--     modes/defense/sv_defense_hooks.lua:184-237's "DefenseAddNewNPCs"
--     handler stamps the same field. That field is the mode's own
--     "this is an enemy I spawned/adopted" marker for classes that may be
--     VJBase NextBots (npc_vj_*, sent_vj_*, zb_*, terminator_nextbot_*) with
--     no Disposition() -- used below exactly as the brief's "field those
--     modes set on spawned enemies".
--   * DEFENSE_WAVE_DEFINITIONS (defense/sv_defense_config.lua:139-262) is the
--     enemy-class census for defense across all three submodes; every type
--     string there is an engine NPC and is Disposition-capable (no VJBase
--     class appears in the AUTHORED wave tables in this checkout -- VJBase
--     handling above is defence-in-depth for the hooks' own generic pattern
--     matching, not a class this repo's own tables spawn).

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}
hg.botdriver.lib = hg.botdriver.lib or {}
hg.botdriver.npc = hg.botdriver.npc or {}
local npc = hg.botdriver.npc
local lib = hg.botdriver.lib

-- Round keys (zb.CROUND_MAIN or zb.CROUND spelling, matching sv_arbiter.lua's
-- IsFFA/RoundAllowsCombat lookups) that get a maintained NPC registry.
hg.botdriver.NPC_MODES = hg.botdriver.NPC_MODES or { coop = true, defense = true }
local NPC_MODES = hg.botdriver.NPC_MODES

local function npcModeActive()
	local rk = zb and (zb.CROUND_MAIN or zb.CROUND)
	return NPC_MODES[rk or false] == true
end
npc.ModeActive = npcModeActive

----------------------------------------------------------------------
-- Registry: one reused array + a parallel ent->index set, so List() never
-- allocates and removal is O(1) (swap-with-last). Seeded once per
-- PostCleanupMap/enable-toggle via a single ents.Iterator() pass; maintained
-- incrementally by OnEntityCreated (deferred one tick, per the brief) and
-- EntityRemoved. Never touched outside an NPC_MODES round.
----------------------------------------------------------------------

local list = {}
local set = {}

local function isTrackableNPC(ent)
	if not IsValid(ent) then return false end
	if ent.IsNPC and ent:IsNPC() then return true end
	if ent.IsNextBot and ent:IsNextBot() then return true end
	return false
end

local function addNPC(ent)
	if set[ent] then return end
	list[#list + 1] = ent
	set[ent] = #list
end

local function removeNPC(ent)
	local idx = set[ent]
	if not idx then return end
	local last = #list
	local lastEnt = list[last]
	list[idx] = lastEnt
	if lastEnt then set[lastEnt] = idx end
	list[last] = nil
	set[ent] = nil
end

local function clearRegistry()
	for i = #list, 1, -1 do list[i] = nil end
	for k in pairs(set) do set[k] = nil end
end

-- Reused array: callers ipairs() it, never mutate it.
function npc.List()
	return list
end

local function seedRegistry()
	clearRegistry()
	if not hg.botdriver.Enabled() then return end
	if not npcModeActive() then return end
	for _, ent in ents.Iterator() do
		if isTrackableNPC(ent) then addNPC(ent) end
	end
end
npc.SeedRegistry = seedRegistry

hook.Add("PostCleanupMap", "zc_bots_npc_seed", seedRegistry)
hook.Add("ZB_EndRound", "zc_bots_npc_clear", clearRegistry)

cvars.RemoveChangeCallback("zc_bots_enable", "zc_bots_npc_seed_on_enable")
cvars.AddChangeCallback("zc_bots_enable", function(_, _, new)
	if tonumber(new) == 1 then seedRegistry() end
end, "zc_bots_npc_seed_on_enable")

seedRegistry() -- covers lua_openscript / autorefresh loading this file mid-round

hook.Add("OnEntityCreated", "zc_bots_npc_register", function(ent)
	if not hg.botdriver.Enabled() then return end
	if not npcModeActive() then return end
	timer.Simple(0, function()
		if not hg.botdriver.Enabled() or not npcModeActive() then return end
		if isTrackableNPC(ent) then addNPC(ent) end
	end)
end)

hook.Add("EntityRemoved", "zc_bots_npc_unregister", function(ent)
	if not hg.botdriver.Enabled() then return end
	if not npcModeActive() then return end
	removeNPC(ent)
end)

----------------------------------------------------------------------
-- Hostility. Engine NPCs: Disposition() is authoritative -- D_HT is hostile,
-- D_FR ("afraid") counts as hostile-but-low-priority (brief), D_LI/D_NU never
-- hostile (citizens, allied rebels/combine depending on the mode). NextBots
-- carry no Disposition -- hostile only via the mode's own
-- IsDefenseWaveNPC marker or a verified class-list entry, never by default.
----------------------------------------------------------------------

-- Verified defense enemy classes (DEFENSE_WAVE_DEFINITIONS, all three
-- submodes, defense/sv_defense_config.lua:139-262) plus the generic VJBase/
-- terminator NextBot spellings the mode's own hooks pattern-match on
-- (defense/sv_defense_hooks.lua:203-211) -- listed here only as a secondary
-- signal; IsDefenseWaveNPC is the primary one for anything without
-- Disposition.
local ENEMY_NPC_CLASSES = {
	coop = {
		npc_combine_s = true, npc_metropolice = true, npc_zombie = true,
	},
	defense = {
		npc_metropolice = true, npc_combine_s = true, npc_manhack = true,
		npc_clawscanner = true, npc_hunter = true, npc_turret_floor = true,
		npc_zombie = true, npc_headcrab = true, npc_fastzombie = true,
		npc_headcrab_fast = true, npc_zombine = true, npc_poisonzombie = true,
		npc_headcrab_poison = true, npc_headcrab_black = true,
	},
}

-- Melee-rushers: close fast, get a targeting-priority bump inside 300u
-- (brief item 2). Small/no-gun classes across both modes' wave tables.
local MELEE_RUSHER_CLASSES = {
	npc_headcrab = true, npc_headcrab_fast = true, npc_headcrab_poison = true,
	npc_headcrab_black = true, npc_zombie = true, npc_fastzombie = true,
	npc_zombine = true, npc_poisonzombie = true, npc_manhack = true,
}

-- Small NPCs whose EyePos()/head attachment is not a meaningful aim point --
-- aim at WorldSpaceCenter instead (brief item 2).
local SMALL_NPC_CLASSES = {
	npc_headcrab = true, npc_headcrab_fast = true, npc_headcrab_poison = true,
	npc_headcrab_black = true, npc_manhack = true, npc_clawscanner = true,
}

function npc.IsMeleeRusher(ent)
	return IsValid(ent) and MELEE_RUSHER_CLASSES[ent:GetClass()] == true
end

-- Returns hostile(bool), tier("high"|"low"|nil).
function npc.IsHostileTo(ent, bot)
	if not IsValid(ent) or not IsValid(bot) then return false end
	if ent.Health and ent:Health() <= 0 then return false end

	if ent.IsNPC and ent:IsNPC() and isfunction(ent.Disposition) then
		local ok, d = pcall(ent.Disposition, ent, bot)
		if not ok then return false end
		if d == D_HT then return true, "high" end
		if d == D_FR then return true, "low" end
		return false -- D_LI / D_NU / D_NE -- never a target
	end

	if ent.IsNextBot and ent:IsNextBot() then
		if ent.IsDefenseWaveNPC == true then return true, "high" end
		local rk = zb and (zb.CROUND_MAIN or zb.CROUND)
		local classes = ENEMY_NPC_CLASSES[rk or false]
		if classes and classes[ent:GetClass()] then return true, "high" end
		return false
	end

	return false
end

function npc.ThreatTier(ent, bot)
	local hostile, tier = npc.IsHostileTo(ent, bot)
	if not hostile then return nil end
	return tier or "high"
end

----------------------------------------------------------------------
-- isEnemy/isAlly for the two PvE modes: NPCs are the only enemies, every
-- living human is an ally. Shared here so modes/sv_coop.lua and
-- modes/sv_defense.lua don't each duplicate the closure (brief: "how a mode
-- profile overrides them").
----------------------------------------------------------------------

function npc.EnemyOfPve(bot)
	return function(ent)
		if not IsValid(ent) or ent == bot then return false end
		if ent:IsPlayer() then return false end -- PvE: never target a human
		return (npc.IsHostileTo(ent, bot))
	end
end

function npc.AllyOfPve(bot)
	return function(ent)
		return IsValid(ent) and ent ~= bot and ent:IsPlayer() and ent:Alive()
	end
end

----------------------------------------------------------------------
-- Entity-agnostic aliveness: Entity:Alive() is documented player/NPC-only on
-- some engine builds and not independently re-verified for every entity type
-- this registry can hand back (UNVERIFIED this session) -- this helper is the
-- safe stand-in anywhere a target might now be a generic NPC/NextBot rather
-- than a player.
----------------------------------------------------------------------

function hg.botdriver.EntityAlive(ent)
	if not IsValid(ent) then return false end
	if ent.IsPlayer and ent:IsPlayer() then return ent:Alive() end
	if ent.Health then
		local ok, hp = pcall(ent.Health, ent)
		if ok and isnumber(hp) then return hp > 0 end
	end
	return true
end

----------------------------------------------------------------------
-- Aim point (brief item 2): small NPCs aim at WorldSpaceCenter; everything
-- else prefers an authored HeadTarget/BodyTarget field (ZBase-style NPCs),
-- then an "eyes" attachment, falling back to EyePos()/WorldSpaceCenter.
----------------------------------------------------------------------

function npc.AimPosOf(ent)
	if not IsValid(ent) then return nil end
	if SMALL_NPC_CLASSES[ent:GetClass()] then return ent:WorldSpaceCenter() end

	if isvector(ent.HeadTarget) then return ent.HeadTarget end
	if isvector(ent.BodyTarget) then return ent.BodyTarget end

	if ent.LookupAttachment and ent.GetAttachment then
		local ok, idx = pcall(ent.LookupAttachment, ent, "eyes")
		if ok and idx and idx > 0 then
			local ok2, att = pcall(ent.GetAttachment, ent, idx)
			if ok2 and istable(att) and isvector(att.Pos) then return att.Pos end
		end
	end

	if ent.EyePos then
		local ok, pos = pcall(ent.EyePos, ent)
		if ok and isvector(pos) then return pos end
	end

	return ent:WorldSpaceCenter()
end

----------------------------------------------------------------------
-- Melee vs. NPC (brief item 2): NPCs never telegraph via GetInAttack, so this
-- skips sv_melee.lua's whole block/parry/read machinery -- approach, swing
-- when in range, back-pedal for a beat after swinging, repeat. Dispatched
-- from lib.MeleeEngage (sv_melee.lua) before any player-only field is read.
-- PROVISIONAL(2026-09-21, exact swing/back-pedal timings are this port's own
-- choice, not dictated by the brief beyond "back-pedal while swinging",
-- ratify-by: 2026-10-15)
----------------------------------------------------------------------

local NPC_MELEE_PAD = 22
local NPC_MELEE_APPROACH_PAD = 40

local function npcMeleeReach(wep)
	if not IsValid(wep) then return 40 end
	return (tonumber(wep.AttackLen1) or tonumber(wep.ReachDistance) or 55) + NPC_MELEE_PAD
end

function lib.MeleeEngageNPC(bot, brain, now, skill, target, dist, buttons, wep)
	skill = skill or 0.5
	dist = dist or 0

	if wep.GetFists and not wep:GetFists() then
		if now >= (brain.fistsRaisedAt or 0) then
			brain.fistsRaisedAt = now + 0.4
			buttons = bit.bor(buttons, IN_ATTACK)
		end
		return buttons
	end

	local reach = npcMeleeReach(wep)

	if dist > reach + NPC_MELEE_APPROACH_PAD then
		brain.sprint = dist > 320
		brain.forward = 350
		brain.side = 0
		if lib.PathTo then lib.PathTo(bot, brain, target:GetPos(), now, 1) end
		return bit.band(buttons, bit.bnot(IN_ATTACK))
	end
	brain.path = nil
	brain.sprint = nil

	if now < (brain.meleeRetreatUntil or 0) then
		-- Back-pedal while the last swing's cooldown runs (brief).
		brain.forward = -200
		brain.side = (bot:EntIndex() % 2 == 0) and 120 or -120
		return bit.band(buttons, bit.bnot(IN_ATTACK))
	end

	local ready = now >= (brain.meleeNextSwingAt or 0)
	if ready and dist <= reach then
		brain.forward, brain.side = 0, 0
		local wait = (tonumber(wep.WaitTime1) or 0.5) + (tonumber(wep.AttackTime) or 0.2)
		brain.meleeNextSwingAt = now + wait + math.Rand(0.1, 0.3) * (1.4 - skill)
		brain.meleeRetreatUntil = now + 0.2 + math.Rand(0.2, 0.4)
		buttons = bit.bor(buttons, IN_ATTACK)
	else
		brain.forward = dist > reach - 10 and 150 or -60
		brain.side = (bot:EntIndex() % 2 == 0) and 80 or -80
		buttons = bit.band(buttons, bit.bnot(IN_ATTACK))
	end

	return buttons
end
