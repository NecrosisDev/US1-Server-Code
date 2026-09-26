-- Bot use of the PLAYER RADIAL MENU's voicelines and gestures (2026-09-22,
-- MISSING FEATURE item 4). Distinct from sv_chatter.lua's text-chat
-- reactions -- this is the actual audio-voiceline/gesture-animation system
-- players reach via the radial menu (+menu bind), not zChatPrint.
--
-- ENTRY POINTS FOUND (grepped both work/main-design-source and
-- work/bots/us1/addons this session; no "cl_radial_medical.lua" or
-- "lua/homigrad/radial/" exists in either tree -- the real radial menu lives
-- at main-design-source/lua/homigrad/cl_hud.lua, `hg.CreateRadialMenu`/
-- `hg.PressRadialMenu`, populated via `hook.Add("radialOptions", ...)`):
--
--   VOICELINE -- main-design-source/lua/homigrad/sh_phrases.lua:309 registers
--   the radial's "Do Phrase" option; its RMB context list
--   (cl_hud.lua-style submenu) calls `RunConsoleCommand("hg_phrase_context",
--   context)` for one of 7 verified context keys, identical for both genders
--   (sh_phrases.lua contextPhrases table): "Scared", "Yell", "Cheer",
--   "Satisfied", "Yell for help", "Someone died", "Die!". That concommand is
--   SERVER-side (main-design-source/lua/homigrad/sv_phrases.lua:450,
--   `concommand.Add("hg_phrase_context", function(ply, cmd, args) ...
--   ply:EmitSound(phrase, ...) end)`) -- fully server-authoritative, so a bot
--   can trigger it directly via `ply:ConCommand(...)`, the same bridge this
--   reference tree already uses server-side in >10 other call sites (e.g.
--   main-design-source/lua/homigrad/sv_equipment.lua:32,
--   `ply:ConCommand("hg_dropflashlight")`). The OTHER voice path, plain
--   "Do Phrase" (`RunConsoleCommand("hg_phrase")`), is CLIENT-authoritative --
--   its concommand.Add lives inside `if CLIENT then` (sh_phrases.lua:298) and
--   its server half (sv_phrases.lua:290) only runs off an actual
--   `net.SendToServer()` byte stream a real client sends. A bot has no client
--   Lua state to run that concommand or send that net message, so that path
--   is UNUSABLE for bots and is intentionally not used here.
--
--   GESTURE -- main-design-source/lua/homigrad/cl_hud.lua:550-586 registers
--   the radial's "Do Gesture" option. Its RMB menu offers two families:
--   `RunConsoleCommand("act", ...)` for wave/salute/halt/group/forward/
--   disagree/becon (no `concommand.Add("act", ...)` exists anywhere in
--   either reference tree -- this is presumably a stock engine/base-gamemode
--   concommand not present in this addon's source, so it is UNVERIFIED
--   whether it is even client- or server-registered; NOT used here), and
--   `RunConsoleCommand("hg_hand_gesture", ...)` for point/thumb_up/fuckyou,
--   whose handler IS in this tree and IS server-side
--   (main-design-source/lua/homigrad/zmanip/sv_zmanip.lua:55) and, better
--   still, just calls the plain global `hg.RunZManipAnim(ply, anim, reverse)`
--   (sv_zmanip.lua:3) -- called directly here, skipping the concommand
--   string-parse entirely. "fuckyou" is available but deliberately unused
--   below (profanity, matches this package's existing chat-line convention
--   of never swearing).
--
-- WHAT BOTS DO WITH THIS: sparse, event-driven, hard rate-limited (global
-- cooldown + per-bot cooldown + a per-round budget, same three-layer shape
-- sv_chatter.lua's maybeSpeak already uses) -- a voiceline on spotting an
-- enemy, taking a hit, or a teammate dying; a gesture (thumb_up) greeting a
-- nearby living ally early in life, and on a kill either a taunt (voice
-- "Die!" or gesture "point") or a plain acknowledge (gesture "thumb_up"),
-- weighted by the bot's own `sportsmanship` trait so a low-sportsmanship bot
-- taunts more and a high-sportsmanship one mostly does not. Frequency is
-- scaled by `verbosity` and the per-round budget by `chatty`
-- (sv_personality.lua) -- the exact three traits the brief named.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}
hg.botdriver.radial = hg.botdriver.radial or {}
local radial = hg.botdriver.radial

hg.botdriver.DeclareBrainState("radial", { perLife = false, fields = {
	"radialVoiceCountThisRound", "radialVoiceLastAt",
	"radialGestureCountThisRound", "radialGestureLastAt",
} })
hg.botdriver.DeclareBrainState("radial_perlife", { fields = { "radialGreetedThisLife" } })

local cv_radial = ConVarExists("zc_bots_radial") and GetConVar("zc_bots_radial")
	or CreateConVar("zc_bots_radial", "0", FCVAR_ARCHIVE,
		"Sparse personality-driven bot radial voicelines and gestures", 0, 1)

local VOICE_GLOBAL_COOLDOWN = 10
local VOICE_BOT_COOLDOWN = 30
local GESTURE_GLOBAL_COOLDOWN = 14
local GESTURE_BOT_COOLDOWN = 45
local WITNESS_RANGE_SQR = 1500 * 1500
local GREET_RANGE_SQR = 350 * 350

-- Verified context keys (sh_phrases.lua contextPhrases, both genders).
local CONTEXT = {
	spotted = "Yell",
	hurt = "Scared",
	teammateDied = "Someone died",
	kill = "Die!",
	-- Item 6 (2026-09-22, TDM called strategy): the one bark modes/sv_tdm.lua
	-- fires when the squad decides its single per-round push -- "Cheer" was
	-- otherwise unused among the 7 verified contexts.
	push = "Cheer",
}

-- Verified gesture names (sv_zmanip.lua's `gestures` table). "fuckyou"
-- omitted deliberately -- see file header.
local GESTURE_POINT = "point"
local GESTURE_THUMBUP = "thumb_up"

local globalVoiceLastAt = -math.huge
local globalGestureLastAt = -math.huge

-- 2026-09-25: Player:ConCommand does nothing for bots (GMod wiki: "This does
-- not work on bots."), so no bot voiceline ever played. concommand.Run calls
-- the server-side hg_phrase_context callback directly with the bot as `ply`
-- (garrysmod/lua/includes/modules/concommand.lua Run(player, command,
-- arguments, argumentsStr), read on US1), the same callback a human's radial
-- click reaches.
local function playVoice(bot, context)
	if not IsValid(bot) or not (concommand and isfunction(concommand.Run)) then return false end
	return concommand.Run(bot, "hg_phrase_context", { context }, context) == true
end

local function playGesture(bot, gesture)
	if not IsValid(bot) or not isfunction(hg.RunZManipAnim) then return false end
	hg.RunZManipAnim(bot, gesture, false)
	return true
end

local function budgetOf(personality, chattyCount, plainCount)
	if not (personality and personality.chatty) then return plainCount end
	return chattyCount
end

local function tryVoice(bot, brain, context, chance)
	if not cv_radial:GetBool() or not IsValid(bot) or not bot:IsBot() or not bot.zcBot then return false end
	if not bot:Alive() then return false end
	local now = CurTime()
	if now - globalVoiceLastAt < VOICE_GLOBAL_COOLDOWN then return false end
	if now - (brain.radialVoiceLastAt or -math.huge) < VOICE_BOT_COOLDOWN then return false end
	local personality = brain.personality or (hg.botdriver.GetPersonality and hg.botdriver.GetPersonality(bot))
	if (brain.radialVoiceCountThisRound or 0) >= budgetOf(personality, 3, 2) then return false end
	local frequency = 0.5 + ((personality and personality.verbosity) or 0.5)
	if math.random() >= chance * frequency then return false end
	if not playVoice(bot, context) then return false end
	brain.radialVoiceCountThisRound = (brain.radialVoiceCountThisRound or 0) + 1
	brain.radialVoiceLastAt = now
	globalVoiceLastAt = now
	return true
end

local function tryGesture(bot, brain, gesture, chance)
	if not cv_radial:GetBool() or not IsValid(bot) or not bot:IsBot() or not bot.zcBot then return false end
	if not bot:Alive() then return false end
	local now = CurTime()
	if now - globalGestureLastAt < GESTURE_GLOBAL_COOLDOWN then return false end
	if now - (brain.radialGestureLastAt or -math.huge) < GESTURE_BOT_COOLDOWN then return false end
	local personality = brain.personality or (hg.botdriver.GetPersonality and hg.botdriver.GetPersonality(bot))
	if (brain.radialGestureCountThisRound or 0) >= budgetOf(personality, 2, 1) then return false end
	local frequency = 0.5 + ((personality and personality.verbosity) or 0.5)
	if math.random() >= chance * frequency then return false end
	if not playGesture(bot, gesture) then return false end
	brain.radialGestureCountThisRound = (brain.radialGestureCountThisRound or 0) + 1
	brain.radialGestureLastAt = now
	globalGestureLastAt = now
	return true
end

-- Spotting an enemy: called from sv_brain.lua's Engage, once per actual
-- (re)acquisition (not every tick a target stays visible).
function radial.OnAcquire(bot, brain, now, target)
	if not hg.botdriver.Enabled() then return end
	tryVoice(bot, brain, CONTEXT.spotted, 0.3)
end

-- Item 6: generic external entry point for a one-off contextual voiceline a
-- mode file wants to trigger directly (as opposed to OnAcquire's automatic
-- hook from Engage). Reuses the same tryVoice budget/cooldown machinery as
-- every other voice line here -- no separate rate limit invented, so a caller
-- cannot spam past cv_radial's existing global/per-bot/per-round limits.
-- Relationship memory (sv_relations.lua): a one-off gesture through the same
-- per-bot/global gesture budget every other gesture here uses.
function radial.OnGesture(bot, brain, gesture, chance)
	if not hg.botdriver.Enabled() then return false end
	return tryGesture(bot, brain, gesture, chance or 1)
end

function radial.OnCallout(bot, brain, key, chance)
	if not hg.botdriver.Enabled() then return false end
	local context = CONTEXT[key]
	if not context then return false end
	return tryVoice(bot, brain, context, chance or 1)
end

-- Taking a hit.
hook.Add("HomigradDamage", "zc_bots_radial_hurt", function(victim, dmg)
	if not hg.botdriver.Enabled() then return end
	if not IsValid(victim) or not victim.IsBot or not victim:IsBot() or not victim.zcBot then return end
	if not victim:Alive() then return end
	local attacker = dmg and dmg.GetAttacker and dmg:GetAttacker() or nil
	if not IsValid(attacker) or attacker == victim then return end
	local brain = hg.botdriver.brains[victim]
	if not brain then return end
	local damage = dmg.GetDamage and dmg:GetDamage() or 0
	tryVoice(victim, brain, CONTEXT.hurt, damage >= 30 and 0.3 or 0.12)
end)

-- A kill (taunt or acknowledge, weighted by sportsmanship) and teammates
-- reacting to a death they witnessed nearby.
hook.Add("PlayerDeath", "zc_bots_radial_death", function(victim, _inflictor, attacker)
	if not hg.botdriver.Enabled() then return end

	if IsValid(attacker) and attacker:IsPlayer() and attacker:IsBot() and attacker.zcBot and attacker ~= victim then
		local brain = hg.botdriver.brains[attacker]
		if brain then
			local personality = brain.personality or (hg.botdriver.GetPersonality and hg.botdriver.GetPersonality(attacker))
			local sportsmanship = (personality and personality.sportsmanship) or 0.5
			if math.random() < (1 - sportsmanship) * 0.5 then
				-- Low sportsmanship: taunt, either voice or gesture, not both.
				if math.random() < 0.5 then
					tryVoice(attacker, brain, CONTEXT.kill, 1)
				else
					tryGesture(attacker, brain, GESTURE_POINT, 1)
				end
			elseif math.random() < sportsmanship * 0.3 then
				-- High sportsmanship: a plain acknowledge instead of a taunt.
				tryGesture(attacker, brain, GESTURE_THUMBUP, 1)
			end
		end
	end

	if not IsValid(victim) or not victim:IsPlayer() then return end
	for bot, brain in pairs(hg.botdriver.brains) do
		if IsValid(bot) and bot:Alive() and bot ~= victim and bot.zcBot then
			local allyOf = hg.botdriver.AllyOf(bot)
			if allyOf(victim) and bot:GetPos():DistToSqr(victim:GetPos()) <= WITNESS_RANGE_SQR then
				tryVoice(bot, brain, CONTEXT.teammateDied, 0.2)
			end
		end
	end
end)

-- Greeting: once per life, a bot that finds a living ally nearby a few
-- seconds after spawning gives a thumb_up. One timer.Simple per spawn -- not
-- a per-tick/per-decision cost, so the FindInSphere-per-tick hard rule does
-- not apply (this is a single one-shot check per bot life).
hook.Add("PlayerSpawn", "zc_bots_radial_greet", function(ply)
	if not hg.botdriver.Enabled() then return end
	if not IsValid(ply) or not ply:IsBot() or not ply.zcBot then return end
	local brain = hg.botdriver.GetBrain(ply)
	timer.Simple(math.Rand(3, 6), function()
		if not hg.botdriver.Enabled() then return end
		if not IsValid(ply) or not ply:Alive() then return end
		if brain.radialGreetedThisLife then return end
		local allyOf = hg.botdriver.AllyOf(ply)
		local pos = ply:GetPos()
		for _, other in ipairs(player.GetAll()) do
			if IsValid(other) and other ~= ply and other:Alive() and allyOf(other)
				and pos:DistToSqr(other:GetPos()) <= GREET_RANGE_SQR then
				brain.radialGreetedThisLife = true
				tryGesture(ply, brain, GESTURE_THUMBUP, 1)
				break
			end
		end
	end)
end)

hook.Add("ZB_PreRoundStart", "zc_bots_radial_reset", function()
	globalVoiceLastAt = -math.huge
	globalGestureLastAt = -math.huge
	for _, brain in pairs(hg.botdriver.brains) do
		brain.radialVoiceCountThisRound = nil
		brain.radialGestureCountThisRound = nil
	end
end)
