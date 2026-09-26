-- Bot decision arbiter, ported from Trauma's lua/homigrad/botdriver/sv_arbiter.lua.
-- Behaviors register into priority bands; RunArbiter walks the compiled list
-- and the first behavior whose CanRun+Run claim the tick owns it.
--
-- Loads before sv_brain.lua (loader order), so nothing here may touch
-- hg.botdriver.lib at file scope -- resolve primitives at run time.
--
-- Cut vs Trauma: no legacy Decide bridge (never existed here), no director
-- objective generators, no offline-harness debug branch. RegisterModeProfile
-- is kept so a later phase can add mode files without touching this file.

hg = hg or {}
hg.botdriver = hg.botdriver or {}
hg.botdriver.modeBrains = hg.botdriver.modeBrains or {}

local BAND_ORDER = { "REFLEX", "SURVIVAL", "MODE", "ACQUIRE", "COMBAT", "SUPPORT", "IDLE" }
local BANDS = {}
for index, name in ipairs(BAND_ORDER) do BANDS[name] = index end
hg.botdriver.BANDS = BANDS
hg.botdriver.BAND_ORDER = BAND_ORDER

local registry = {}
local generation = 0
hg.botdriver.behaviorRegistry = registry

function hg.botdriver.RegisterBehavior(def)
	if not istable(def) or not isstring(def.name) or def.name == "" then
		hg.botdriver.log.error("bots", "RegisterBehavior: missing name")
		return false
	end
	if not BANDS[def.band] then
		hg.botdriver.log.error("bots", "RegisterBehavior: unknown band for " .. def.name .. ": " .. tostring(def.band))
		return false
	end
	if not isfunction(def.Run) then
		hg.botdriver.log.error("bots", "RegisterBehavior: " .. def.name .. " has no Run")
		return false
	end
	def.order = tonumber(def.order) or 50
	if def.default == nil then def.default = true end
	registry[def.name] = def
	generation = generation + 1
	return true
end

function hg.botdriver.UnregisterBehavior(name)
	if not registry[name] then return false end
	registry[name] = nil
	generation = generation + 1
	return true
end

function hg.botdriver.RegisterModeProfile(key, profile)
	if not isstring(key) or not istable(profile) then
		hg.botdriver.log.error("bots", "RegisterModeProfile: bad arguments for " .. tostring(key))
		return false
	end
	profile.Decide = nil
	profile.behaviors = profile.behaviors or {}
	profile.suppress = profile.suppress or {}
	hg.botdriver.modeBrains[key] = profile
	if istable(profile.aliases) then
		for _, alias in ipairs(profile.aliases) do
			hg.botdriver.modeBrains[alias] = profile
		end
	end
	generation = generation + 1
	return true
end

function hg.botdriver.ResolveModeProfile(key)
	if not key then return nil end
	return hg.botdriver.modeBrains[key]
end

-- Is weapon-level combat allowed in the CURRENT round state? Verified round
-- hooks/fields (rule 6): zb.ROUND_STATE, zb.ROUND_START, zb.CROUND_MAIN /
-- zb.CROUND (gamemode/libraries/sv_roundsystem.lua).
function hg.botdriver.RoundAllowsCombat()
	local roundState = zb and zb.ROUND_STATE
	if roundState == nil then return true end
	if roundState == 1 then return true end
	local rk = zb.CROUND_MAIN or zb.CROUND
	local profile = hg.botdriver.ResolveModeProfile(rk)
	return profile ~= nil and profile.IntermissionCombat == true
end

-- FFA: MODE.FFA if the round table carries it, else the FFAModes fallback
-- table in sv_shim.lua (rule 6 -- zb.modes[...].FFA may not exist on US1).
function hg.botdriver.IsFFA()
	local rk = zb and (zb.CROUND_MAIN or zb.CROUND)
	if not rk then return false end
	local mode = zb.modes and zb.modes[rk]
	if istable(mode) and mode.FFA ~= nil then return mode.FFA == true end
	return hg.botdriver.FFAModes[rk] == true
end

local compiled = { key = false, generation = -1, list = {} }

hook.Add("ZB_PreRoundStart", "zc_bots_arbiter_recompile", function()
	compiled.key = false
end)

local EMPTY = {}

local function compileActive(roundKey, profile)
	local list = {}
	local suppress = {}
	local extra = {}
	if profile then
		for _, name in ipairs(profile.suppress or EMPTY) do suppress[name] = true end
		for _, name in ipairs(profile.behaviors or EMPTY) do extra[name] = true end
	end
	for name, def in pairs(registry) do
		if not suppress[name] and (def.default or extra[name]) then
			list[#list + 1] = def
		end
	end
	table.sort(list, function(a, b)
		local ba, bb = BANDS[a.band], BANDS[b.band]
		if ba ~= bb then return ba < bb end
		if a.order ~= b.order then return a.order < b.order end
		return a.name < b.name
	end)
	compiled.key = roundKey or false
	compiled.generation = generation
	compiled.list = list
	return list
end

local function activeList(roundKey, profile)
	if compiled.key == (roundKey or false) and compiled.generation == generation then
		return compiled.list
	end
	return compileActive(roundKey, profile)
end

local CTX_FIELDS = {
	"bot", "brain", "now", "skill", "behavior", "survival", "survivalPolicy",
	"roundKey", "profile", "downed", "investigating", "targetDist", "prevState",
	"_enemyOf", "_allyOf", "_target", "_acquired", "_hardObjective", "_hardKnown",
}

local ctxMeta = {}
ctxMeta.__index = ctxMeta

function ctxMeta:EnemyOf()
	local fn = self._enemyOf
	if not fn then
		fn = hg.botdriver.EnemyOf(self.bot)
		self._enemyOf = fn
	end
	return fn
end

function ctxMeta:AllyOf()
	local fn = self._allyOf
	if not fn then
		fn = hg.botdriver.AllyOf(self.bot)
		self._allyOf = fn
	end
	return fn
end

-- No mode ever sets a "hard" travel objective in Phase 1 (SetObjective exists
-- for a later phase to call), so this always reads false; kept as a method so
-- the ACQUIRE/IDLE behaviors ported from Trauma need no further edits.
function ctxMeta:HardObjective()
	if self._hardKnown then return self._hardObjective end
	local lib = hg.botdriver.lib
	local brain = self.brain
	local hard = lib.ObjectiveActive(brain, self.now) and brain.objectivePriority == "hard"
		and brain.objectivePhase ~= "arrived"
		and (not self.survival or self.survival.allowModeObjective ~= false)
	self._hardObjective = hard or false
	self._hardKnown = true
	return self._hardObjective
end

function ctxMeta:AcquireTarget()
	if self._acquired then return self._target, self.targetDist end
	self._acquired = true
	local lib = hg.botdriver.lib
	local target, dist, investigating = lib.AcquireTargetStep(
		self.bot, self.brain, self.now, self.skill, self:EnemyOf())
	self._target = target
	self.targetDist = dist
	self.investigating = investigating or false
	return target, dist
end

local function getCtx(brain)
	local ctx = brain.__arbCtx
	if not ctx then
		ctx = setmetatable({}, ctxMeta)
		brain.__arbCtx = ctx
	end
	for i = 1, #CTX_FIELDS do ctx[CTX_FIELDS[i]] = nil end
	return ctx
end

local cv_skill = ConVarExists("zc_bots_skill") and GetConVar("zc_bots_skill")
	or CreateConVar("zc_bots_skill", "0.5", FCVAR_ARCHIVE, "Squad-wide bot skill 0..1 (aim error, discipline, turn speed)", 0, 1)

function hg.botdriver.RunArbiter(bot, brain, now)
	local lib = hg.botdriver.lib

	-- PERSONALITY: per-bot skill (sv_personality.lua), falling back to the
	-- squad-wide convar if the personality module is ever removed.
	local skill = hg.botdriver.EffectiveSkill and hg.botdriver.EffectiveSkill(brain) or cv_skill:GetFloat()
	brain.aimSkill = skill
	brain.forward, brain.side = 0, 0
	brain.buttons = 0
	brain.moveAngles = nil
	brain.aimLocked = nil
	brain.lookLocked = nil
	brain.lookSource = nil
	brain.lookPos = nil
	brain.sprint = nil
	brain.actionPolicy = nil
	brain.traverseButtons = nil
	local survivalPolicy = hg.botdriver.SurvivalPolicyFor and hg.botdriver.SurvivalPolicyFor(bot) or nil
	local survival = hg.botdriver.BuildSurvivalState and hg.botdriver.BuildSurvivalState(bot, brain, now, survivalPolicy) or nil
	brain.survival = survival

	local roundKey = zb and (zb.CROUND_MAIN or zb.CROUND)
	local profile = hg.botdriver.ResolveModeProfile(roundKey)

	local ctx = getCtx(brain)
	ctx.bot, ctx.brain, ctx.now, ctx.skill = bot, brain, now, skill
	-- PERSONALITY: aggression/preferRange authored per-bot from
	-- sv_personality.lua's rolled traits (a reused table, not a fresh
	-- allocation per decision -- Engage's `behavior.aggression`/
	-- `behavior.preferRange` fallbacks in sv_brain.lua cover the case where
	-- no personality has been rolled yet).
	local personality = brain.personality
	local behaviorTbl = brain.__behaviorTbl
	if not behaviorTbl then
		behaviorTbl = {}
		brain.__behaviorTbl = behaviorTbl
	end
	behaviorTbl.aggression = personality and personality.aggression or nil
	if hg.botdriver.HomicideRush and hg.botdriver.HomicideRush() then behaviorTbl.aggression = 1 end
	behaviorTbl.preferRange = personality and (600 * personality.preferRangeBias) or nil
	ctx.behavior = behaviorTbl
	ctx.survival, ctx.survivalPolicy = survival, survivalPolicy
	ctx.roundKey, ctx.profile = roundKey, profile
	ctx.downed = hg.botdriver.IsDowned(bot)
	ctx.investigating = false
	ctx.prevState = brain.state

	local list = activeList(roundKey, profile)
	local arb = brain.arb
	if not arb then
		arb = {}
		brain.arb = arb
	end
	local prevOwner = arb.owner

	local owner, ownerDef, finalizeOpts
	local survivalBody = survival and survival.body
	local prevOffered = false
	for i = 1, #list do
		local def = list[i]
		if def.name == prevOwner then prevOffered = true end
		if survivalBody ~= nil then ctx.downed = survivalBody.downed or false end
		if not def.CanRun or def.CanRun(ctx) then
			if def.stateLabel then brain.state = def.stateLabel end
			local owned, override = def.Run(ctx)
			if owned then
				owner, ownerDef = def.name, def
				finalizeOpts = override or def.finalize
				break
			end
		end
	end

	if prevOwner and owner ~= prevOwner then
		local prevDef = registry[prevOwner]
		if prevDef and prevDef.OnPreempt then
			prevDef.OnPreempt(ctx, owner, prevOffered)
		end
	end

	arb.owner = owner
	arb.band = ownerDef and ownerDef.band or nil
	arb.at = now

	if finalizeOpts then
		lib.Finalize(bot, brain, now, finalizeOpts)
	end

	-- Item 2 (NPC targeting): brain.target may now be a registry NPC, which
	-- has no :Nick() -- fall back to its class name for the debug line.
	local targetLabel = "-"
	if IsValid(brain.target) then
		targetLabel = (brain.target.Nick and brain.target:Nick()) or brain.target:GetClass()
	end
	hg.botdriver.log.debug("bots", string.format("bot %s: owner=%s target=%s",
		bot:Nick(), tostring(owner), targetLabel))
end
