-- zc_bots shim: US1 has no botdriver namespace under hg, and none of
-- Trauma's satellite systems: the combatant actor abstraction, the stagger
-- scheduler helper, the log module, or the director/gas/infected/SCP939/npc/
-- acoustics/pacing/vox/selftest/performance/DebugTools/BotsDisabled systems.
-- This file is the seam every ported file reads instead of those, and it
-- must be safe to run more than once (lua_openscript / autorefresh re-run).
--
-- Verified against the US1 reference tree (main-design-source/lua/homigrad):
-- the FakeUp function (fake/sv_tier_0.lua:730), ply.FakeRagdoll
-- (fake/sv_input.lua), org.otrub (organism/tier_1/sv_organism.lua:21),
-- player.GetAll/GetHumans (engine). The botdriver namespace itself does not
-- exist on US1 -- this file creates it.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}

local cv_enable = ConVarExists("zc_bots_enable") and GetConVar("zc_bots_enable")
	or CreateConVar("zc_bots_enable", "0", FCVAR_ARCHIVE, "Master kill switch for the zc_bots AI package. 0 kicks every bot this addon created.", 0, 1)
local cv_debug = ConVarExists("zc_bots_debug") and GetConVar("zc_bots_debug")
	or CreateConVar("zc_bots_debug", "0", FCVAR_ARCHIVE, "Verbose zc_bots logging.", 0, 1)

hg.botdriver.cv_enable = cv_enable
hg.botdriver.cv_debug = cv_debug

function hg.botdriver.Enabled()
	return cv_enable:GetBool()
end

----------------------------------------------------------------------
-- Logging (replaces the log module Trauma keeps under the hg namespace)
----------------------------------------------------------------------

hg.botdriver.log = hg.botdriver.log or {}

local function fmt(tag, msg)
	return string.format("[zc_bots:%s] %s", tostring(tag), tostring(msg))
end

function hg.botdriver.log.info(tag, msg)
	print(fmt(tag, msg))
end

function hg.botdriver.log.warn(tag, msg)
	print(fmt(tag, msg))
end

function hg.botdriver.log.error(tag, msg)
	ErrorNoHalt(fmt(tag, msg) .. "\n")
end

function hg.botdriver.log.debug(tag, msg)
	if not cv_debug:GetBool() then return end
	print(fmt(tag, msg))
end

-- Runtime errors this package CATCHES itself (runDecision's xpcall, brain
-- reset callbacks). 2026-09-25 review: those were only ever reported through
-- ErrorNoHalt, which the loader's OnLuaError hook never receives, so
-- data/zc_bots/errors.txt stayed empty while every combat decision crashed
-- on US1 (zc_errlog/errors-2026-09-24.txt). ErrorNoHalt is kept (zc_errlog
-- still captures it); the first occurrence of each distinct `key` is also
-- written to errors.txt, and repeats are counted and summarised once a minute.
local ERROR_FILE = "zc_bots/errors.txt"
local ERROR_KEYS_MAX = 60
local ERROR_LINES_MAX = 200 -- per map (Lua state), first lines + summaries together

hg.botdriver.errorLog = hg.botdriver.errorLog or { keys = {}, keyCount = 0, dirty = false, lines = 0 }
local errorLog = hg.botdriver.errorLog

local function appendErrorFile(text)
	if (errorLog.lines or 0) >= ERROR_LINES_MAX then return end
	errorLog.lines = (errorLog.lines or 0) + 1
	file.CreateDir("zc_bots")
	file.Append(ERROR_FILE, os.date("%H:%M:%S ") .. text .. "\n")
end

function hg.botdriver.log.runtime(tag, msg, key)
	local text = fmt(tag, msg)
	ErrorNoHalt(text .. "\n")
	key = tostring(key or msg)
	local rec = errorLog.keys[key]
	if rec then
		rec.count = rec.count + 1
		errorLog.dirty = true
		return
	end
	if errorLog.keyCount >= ERROR_KEYS_MAX then return end
	errorLog.keyCount = errorLog.keyCount + 1
	errorLog.keys[key] = { count = 1, reported = 1 }
	appendErrorFile(text)
end

timer.Create("zc_bots_error_summary", 60, 0, function()
	if not errorLog.dirty then return end
	errorLog.dirty = false
	for key, rec in pairs(errorLog.keys) do
		if rec.count > rec.reported then
			appendErrorFile(string.format("x%d more (total %d): %s", rec.count - rec.reported, rec.count, key))
			rec.reported = rec.count
		end
	end
end)

----------------------------------------------------------------------
-- Actor helpers (replace Trauma's combatant actor abstraction)
----------------------------------------------------------------------

-- IsDowned: verified via the FakeUp function / ply.FakeRagdoll
-- (fake/sv_tier_0.lua) and org.otrub (organism/tier_1/sv_organism.lua). NPC
-- downing does not exist in this Phase 1 package -- bots fight players only
-- (rule: NPC targeting dropped).
function hg.botdriver.IsDowned(ply)
	if not IsValid(ply) then return false end
	if IsValid(ply.FakeRagdoll) then return true end
	local org = ply.organism
	return org ~= nil and org.otrub == true
end

function hg.botdriver.TeamOf(ply)
	return IsValid(ply) and ply:Team() or nil
end

-- Item 2 (NPC targeting): in coop/defense, append the maintained NPC
-- registry (sv_npc.lua) to the actor roster so AcquireTargetStep sees hostile
-- NPCs too. player.GetAll() returns a fresh table each call, so extending it
-- here never aliases sv_npc.lua's own reused array. Zero cost outside those
-- two modes (one field/function lookup, then the plain player-only path).
function hg.botdriver.Actors()
	local actors = player.GetAll()
	local npcMod = hg.botdriver.npc
	if npcMod and npcMod.ModeActive and npcMod.ModeActive() then
		local npcs = npcMod.List()
		for i = 1, #npcs do
			actors[#actors + 1] = npcs[i]
		end
	end
	return actors
end

-- Round keys that are FFA even without a MODE.FFA flag. zb.modes[key].FFA may
-- not exist on US1 (brief 6) -- this table is the fallback, checked in
-- addition to any MODE.FFA the round table does carry.
hg.botdriver.FFAModes = {
	dm = true,
	superfighters = true,
	-- Part A.3 (2026-09-21): mayhem is an all-Team-0 free-for-all (US1
	-- modes/zz_mayhem/sv_zz_mayhem.lua:28-47, confirmed by direct grep this
	-- session -- every player is Team 0 with no team-vs-team relationship
	-- anywhere in the mode's own CheckAlive/damage handling).
	mayhem = true,
}

----------------------------------------------------------------------
-- Stubs for dropped Trauma layers. Every one returns the same "nothing here"
-- answer Trauma's real modules would give when disabled, so ported callers
-- (survival, brain) keep working unchanged.
----------------------------------------------------------------------

hg.gas = hg.gas or {}
function hg.gas.SightBlocked() return false end
function hg.gas.GetHazardScore() return 0 end

hg.infected = hg.infected or {}
function hg.infected.IsInfected() return false end

hg.SCP939 = hg.SCP939 or {}
function hg.SCP939.IsCreature() return false end

hg.npc = hg.npc or {}
function hg.npc.HatesPlayer() return false end
function hg.npc.Living() return {} end

----------------------------------------------------------------------
-- Every: replacement for Trauma's stagger-scheduler Every helper, built on
-- timer.Create so repeated
-- includes (autorefresh) reuse the same timer id instead of stacking more.
----------------------------------------------------------------------

function hg.botdriver.Every(id, interval, fn)
	timer.Create("zc_bots_" .. id, interval, 0, fn)
end

----------------------------------------------------------------------
-- Kill switch: while zc_bots_enable is 0, kick every bot this addon created
-- (tagged ply.zcBot = true) and let Think/StartCommand early-return elsewhere.
----------------------------------------------------------------------

local function kickDisabledBots()
	if cv_enable:GetBool() then return end
	for _, ply in ipairs(player.GetAll()) do
		if IsValid(ply) and ply:IsBot() and ply.zcBot then
			ply:Kick("zc_bots_enable is 0")
		end
	end
end

cvars.RemoveChangeCallback("zc_bots_enable", "zc_bots_kill_switch")
cvars.AddChangeCallback("zc_bots_enable", function(_, _, new)
	if tonumber(new) == 0 then kickDisabledBots() end
end, "zc_bots_kill_switch")

hg.botdriver.Every("kill_switch_sweep", 5, kickDisabledBots)
