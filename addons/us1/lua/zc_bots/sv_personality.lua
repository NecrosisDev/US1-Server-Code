-- Per-bot personality: stable traits rolled once per bot life-cycle (the bot
-- entity, not per spawn/death) and stored outside the per-life reset so a bot
-- keeps its "feel" across every respawn until it disconnects (a new player
-- entity on reconnect naturally re-rolls).
--
-- Wires into the seams sv_arbiter.lua/sv_brain.lua already read:
-- ctx.behavior.aggression/preferRange (sv_arbiter.lua's RunArbiter, consumed
-- by sv_brain.lua's Engage), ctx.skill (per-bot instead of purely
-- squad-wide), sv_gunhandling.lua's reaction delay (gh.OnAcquire reads
-- brain.personality directly) and sv_squad.lua's callout chattiness.
--
-- BEHAVIOR CHOICE (not dictated by the brief): zc_bots_skill is documented as
-- "squad-wide bot skill", so it is kept as an OFFSET from each bot's own
-- rolled skill (offset = convar - 0.5, then clamped 0..1) rather than a
-- second independent skill roll -- this satisfies "server convar stays as a
-- global offset" while keeping the 0.3-0.8 roll spread meaningful.
--
-- HUMANIZE traits (2026-09-21 humanization pass, section A-G of the brief):
-- flickSpeed (saccade duration multiplier -- lower is a faster hand),
-- latency (perceptual pipeline delay in seconds, sv_aim.lua), steadiness
-- (0..1, inverse motor-noise amplitude), fidgety (idle-fiddle chance while
-- not fighting), tidiness (0..1, reload-habit quirk chance, section F),
-- curiosity (0..1, chance to check a false sound / glance at a passing
-- opening, section B/F). These are rolled once per bot life-cycle like every
-- other trait here.
--
-- BEHAVIOR CHOICE (not dictated by the brief): section G asks that "the same
-- bot" (identified by name) keep the same personality across reconnects
-- within a map. A reconnect creates a brand new player entity (and therefore
-- a brand new brain table), so the per-brain rolled table cannot itself
-- survive that -- this file adds a name-keyed cache (personalityByName,
-- file-scope local, cleared only by a fresh Lua state i.e. a map change/
-- server restart, which is the natural "within a map" boundary) that
-- GetPersonality consults before rolling a fresh set.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}

hg.botdriver.DeclareBrainState("personality", { perLife = false, fields = { "personality" } })
hg.botdriver.DeclareBrainState("personality_perlife", { fields = { "spawnHoldUntil" },
	-- Re-rolled by ResetBrain after its wipe (see sv_brain.lua ResetBrain):
	-- the PlayerSpawn hook below may run before that wipe (hook order is
	-- unspecified), which silently dropped the spawn hold.
	reset = function(bot, brain)
		if not IsValid(bot) or not bot:Alive() then return end
		local humanize = hg.botdriver.cv_humanize and hg.botdriver.cv_humanize:GetFloat() or 1
		brain.spawnHoldUntil = CurTime() + math.Rand(0.3, 2.5) * humanize
	end,
})

local cv_skill = ConVarExists("zc_bots_skill") and GetConVar("zc_bots_skill")
	or CreateConVar("zc_bots_skill", "0.5", FCVAR_ARCHIVE, "Squad-wide bot skill 0..1 (aim error, discipline, turn speed)", 0, 1)

hg.botdriver.cv_humanize = hg.botdriver.cv_humanize
	or (ConVarExists("zc_bots_humanize") and GetConVar("zc_bots_humanize"))
	or CreateConVar("zc_bots_humanize", "1", FCVAR_ARCHIVE,
		"Global scale (0..1) on every human-mistake/imperfection term in the bot aim/gaze/movement model", 0, 1)

-- Name-keyed personality cache (section G): survives a bot disconnect/
-- reconnect within the same map/Lua state. Re-declaring this file (Lua
-- autorefresh) re-runs the module top-level, which would normally wipe a
-- plain local -- guarded so the cache table itself is only created once.
hg.botdriver.personalityByName = hg.botdriver.personalityByName or {}
local personalityByName = hg.botdriver.personalityByName
local PERSONALITY_SCHEMA = 2
local migrateExisting = hg.botdriver.personalitySchema ~= PERSONALITY_SCHEMA
if migrateExisting then table.Empty(personalityByName) end
hg.botdriver.personalitySchema = PERSONALITY_SCHEMA

-- Coherent profiles keep personality from feeling like a bag of unrelated
-- random numbers. Ranges still overlap, so two "cautious" bots are not
-- copies; the archetype only bends the same traits the combat owners already
-- consume. Chat style is presentation metadata used by sv_chatter.lua.
local PROFILES = {
	{ id = "regular", weight = 24, style = "casual", skill = {.35,.72}, aggression = {.35,.68}, reaction = {.9,1.25}, patience = {.8,1.25}, range = {.85,1.18}, steady = {.38,.78}, curiosity = {.25,.68}, chat = .34, composure = {.42,.78}, grudge = {.2,.55}, sports = {.45,.82} },
	{ id = "cautious", weight = 14, style = "nervous", skill = {.38,.74}, aggression = {.16,.43}, reaction = {1.02,1.38}, patience = {1.12,1.55}, range = {1.08,1.4}, steady = {.45,.84}, curiosity = {.16,.48}, chat = .31, composure = {.28,.62}, grudge = {.12,.42}, sports = {.5,.88} },
	{ id = "hothead", weight = 11, style = "blunt", skill = {.32,.72}, aggression = {.72,.94}, reaction = {.78,1.08}, patience = {.5,.84}, range = {.68,.98}, steady = {.25,.66}, curiosity = {.35,.82}, chat = .48, composure = {.16,.48}, grudge = {.64,.94}, sports = {.12,.52} },
	{ id = "deadpan", weight = 13, style = "dry", skill = {.42,.8}, aggression = {.34,.67}, reaction = {.86,1.18}, patience = {.86,1.32}, range = {.88,1.22}, steady = {.56,.9}, curiosity = {.25,.62}, chat = .33, composure = {.7,.96}, grudge = {.24,.58}, sports = {.38,.72} },
	{ id = "support", weight = 11, style = "friendly", skill = {.36,.72}, aggression = {.24,.56}, reaction = {.92,1.28}, patience = {1.0,1.48}, range = {.92,1.28}, steady = {.42,.82}, curiosity = {.32,.72}, chat = .47, composure = {.52,.86}, grudge = {.08,.36}, sports = {.72,.96} },
	{ id = "tryhard", weight = 11, style = "competitive", skill = {.58,.88}, aggression = {.5,.82}, reaction = {.72,1.0}, patience = {.76,1.16}, range = {.82,1.18}, steady = {.65,.94}, curiosity = {.22,.56}, chat = .38, composure = {.48,.82}, grudge = {.45,.78}, sports = {.28,.68} },
	{ id = "gremlin", weight = 9, style = "chaotic", skill = {.3,.7}, aggression = {.52,.9}, reaction = {.78,1.28}, patience = {.48,1.02}, range = {.7,1.18}, steady = {.2,.7}, curiosity = {.7,.96}, chat = .62, composure = {.12,.58}, grudge = {.3,.8}, sports = {.18,.68} },
	-- F3 (design brief section 1, owner's idea): the player on hotel wifi. High
	-- visible ping, genuinely slower perception (aim latency is a real
	-- mechanic), periodic movement hitches (sv_control.lua), blames lag in
	-- chat. Never harder to hit. At most ONE at a time (chooseProfile below).
	{ id = "laggy", weight = 4, style = "laggy", skill = {.36,.7}, aggression = {.4,.7}, reaction = {1.05,1.35}, patience = {.8,1.2}, range = {.85,1.15}, steady = {.35,.75}, curiosity = {.25,.65}, chat = .55, composure = {.3,.7}, grudge = {.25,.6}, sports = {.4,.8} },
	{ id = "oldhand", weight = 7, style = "dry", skill = {.52,.84}, aggression = {.3,.64}, reaction = {.88,1.2}, patience = {1.08,1.52}, range = {.98,1.34}, steady = {.7,.95}, curiosity = {.12,.42}, chat = .27, composure = {.76,.97}, grudge = {.12,.48}, sports = {.5,.84} },
}

local function between(range) return math.Rand(range[1], range[2]) end

-- Only one laggy bot at a time: several reads as "the server is lagging" and
-- players blame the box instead of the player (design brief guardrail).
local function laggyAlreadyPresent()
	for bot, brain in pairs(hg.botdriver.brains) do
		if IsValid(bot) and brain.personality and brain.personality.archetype == "laggy" then return true end
	end
	return false
end

local function chooseProfile()
	local total = 0
	for _, profile in ipairs(PROFILES) do total = total + profile.weight end
	local pick = math.random() * total
	local chosen = PROFILES[1]
	for _, profile in ipairs(PROFILES) do
		pick = pick - profile.weight
		if pick <= 0 then chosen = profile break end
	end
	if chosen.id == "laggy" and laggyAlreadyPresent() then chosen = PROFILES[1] end
	return chosen
end

local function rollPersonality()
	local profile = chooseProfile()
	local steadiness = between(profile.steady)
	return {
		archetype = profile.id,
		chatStyle = profile.style,
		skill = between(profile.skill),
		aggression = between(profile.aggression),
		reactionMult = between(profile.reaction),
		patience = between(profile.patience),
		preferRangeBias = between(profile.range),
		chatty = math.random() < profile.chat,
		composure = between(profile.composure),
		grudge = between(profile.grudge),
		sportsmanship = between(profile.sports),
		verbosity = math.Rand(.2, .9),
		typoChance = math.Rand(.01, .075),
		-- HUMANIZE traits (sv_aim.lua, sv_control.lua, section E/F consumers):
		flickSpeed = math.Rand(0.85, 1.25),
		latency = math.Rand(0.16, 0.26),
		steadiness = steadiness,
		fidgety = profile.id == "gremlin" or math.random() < 0.36,
		tidiness = profile.id == "oldhand" and math.Rand(.65,.94) or math.Rand(0.1, 0.9),
		curiosity = between(profile.curiosity),
		-- Incommensurate per-bot hand-drift phases (section A3): two fixed
		-- irrational-ish offsets so no two bots' drift sines ever line up.
		noisePhaseA = math.Rand(0, 6.283),
		noisePhaseB = math.Rand(0, 6.283),
		-- Item 4 (ping seam, sv_identity.lua): stable plausible base ping in
		-- ms; sv_identity.lua drifts the published value a few ms around this.
		pingBase = math.Rand(28, 125),
	}
end

-- F3 overrides on top of the common roll: the lag is real, not cosmetic.
local baseRollPersonality = rollPersonality
rollPersonality = function()
	local p = baseRollPersonality()
	if p.archetype == "laggy" then
		p.pingBase = math.Rand(180, 320)
		p.latency = math.Rand(0.30, 0.40)        -- vs 0.16-0.26: aims at an older world
		p.hitchInterval = math.Rand(6, 15)        -- seconds between movement hitches
		p.hitchLength = math.Rand(0.12, 0.30)     -- each hitch: a frozen moment, then catch-up
	end
	return p
end

-- Effective per-bot skill: rolled trait plus the convar's offset from its own
-- 0.5 default, plus item B6's adaptive difficulty offset (sv_difficulty.lua,
-- zero/no-op if that file is ever removed), clamped back into 0..1.
function hg.botdriver.EffectiveSkill(brain)
	local p = brain.personality
	local base = (p and p.skill) or 0.5
	local adaptive = hg.botdriver.DifficultyOffset and hg.botdriver.DifficultyOffset() or 0
	return math.Clamp(base + (cv_skill:GetFloat() - 0.5) + adaptive, 0, 1)
end

function hg.botdriver.GetPersonality(bot)
	local brain = hg.botdriver.GetBrain(bot)
	if not brain.personality then
		local name = bot.Nick and bot:Nick() or nil
		local cached = name and personalityByName[name]
		brain.personality = cached or rollPersonality()
		if name then personalityByName[name] = brain.personality end
	end
	return brain.personality
end

hook.Add("PlayerSpawn", "zc_bots_personality_roll", function(ply)
	if not hg.botdriver.Enabled() then return end
	if not ply:IsBot() or not ply.zcBot then return end
	hg.botdriver.GetPersonality(ply)
	-- Section E: humans load in and orient before moving -- each bot life
	-- waits its own 0.3-2.5s (scaled by zc_bots_humanize) before StartCommand
	-- authors any forward/side movement. A pure number on the brain, read by
	-- sv_control.lua's per-tick hook with no allocation.
	local brain = hg.botdriver.brains[ply]
	if brain then
		local humanize = hg.botdriver.cv_humanize:GetFloat()
		brain.spawnHoldUntil = CurTime() + math.Rand(0.3, 2.5) * humanize
	end
end)

-- A live update may leave old, shape-less personality tables on existing
-- brains. Migrate once per schema revision so the new archetypes and chat
-- styles take effect immediately without respawning or replacing bots.
if migrateExisting then
	timer.Simple(0, function()
		for bot, brain in pairs(hg.botdriver.brains) do
			brain.personality = nil
			if IsValid(bot) and bot:IsBot() and bot.zcBot then
				hg.botdriver.GetPersonality(bot)
			end
		end
	end)
end
