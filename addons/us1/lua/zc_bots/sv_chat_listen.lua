-- Restrained public-chat listener (2026-09-23 chat realism pass, deliverable
-- D). Bots occasionally react to what HUMANS say in public chat -- being
-- named/accused, greeted, a shared "gg" moment, or a teammate asking for a
-- medic/ammo -- without ever reading like a chatbot that answers everything.
--
-- addons/zcity/lua/homigrad/zchat/sh_chat.lua owns PlayerSay and its
-- dead/alive chat-visibility rules; this hook returns NOTHING so ZChat's own
-- return value (and nobody else's) decides what actually gets delivered. A
-- living bot must never "see" chat a living human in its own state could not
-- see: during a live round, a dead/spectating human's chat is only ever
-- shown to other dead/spectating parties, so only DEAD bots may react to it.
--
-- Loads after sv_social.lua (see the loader), so hg.botdriver.chat,
-- hg.botdriver.chatter.Say and hg.botdriver.chatTyping are all already
-- populated by the time this file's own top-level code runs.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}
local D = hg.botdriver
local chat = D.chat

hg.botdriver.DeclareBrainState("chatlisten", { perLife = false, fields = { "chatListenLastAt" } })

----------------------------------------------------------------------
-- Small shared helpers
----------------------------------------------------------------------

local function human(p) return IsValid(p) and p:IsPlayer() and not p:IsBot() end
local function spectator(p) return not p:Alive() or p:Team() == TEAM_SPECTATOR end

local function isBotEntity(bot)
	return IsValid(bot) and bot:IsBot() and bot.zcBot and not bot.zcBotBenched
end

-- Per bot: never mid-reply-cooldown (40s), never with a live target unless
-- dead, never while the package is disabled. Returns (ok, isDead).
local function canReply(bot, brain, now)
	if not isBotEntity(bot) or not D.Enabled() then return false end
	local dead = not bot:Alive() or bot:Team() == TEAM_SPECTATOR
	if IsValid(brain.target) and not dead then return false end
	if brain.chatListenLastAt and now - brain.chatListenLastAt < 40 then return false end
	return true, dead
end

local function filterEligible(list, requireDead, now)
	local out = {}
	for _, bot in ipairs(list) do
		local brain = D.brains[bot]
		if brain then
			local ok, dead = canReply(bot, brain, now)
			if ok and (not requireDead or dead) then out[#out + 1] = bot end
		end
	end
	return out
end

local function allBots()
	local out = {}
	for bot in pairs(D.brains) do
		if isBotEntity(bot) then out[#out + 1] = bot end
	end
	return out
end

local function otherBots(exclude)
	local out = {}
	for bot in pairs(D.brains) do
		if bot ~= exclude and isBotEntity(bot) then out[#out + 1] = bot end
	end
	return out
end

local function chattyBots()
	local out = {}
	for bot in pairs(D.brains) do
		if isBotEntity(bot) then
			local p = D.GetPersonality and D.GetPersonality(bot)
			if p and p.chatty then out[#out + 1] = bot end
		end
	end
	return out
end

local function containsToken(text, token)
	if not token or token == "" then return false end
	local escaped = string.gsub(token, "%W", "%%%1")
	return string.find(text, "%f[%w]" .. escaped .. "%f[%W]") ~= nil
end

local function startsWithAny(text, prefixes)
	for _, prefix in ipairs(prefixes) do
		if string.sub(text, 1, #prefix) == prefix then return true end
	end
	return false
end

-- Accusation naming: the bot's ShortName-style short form, its first word,
-- and its full cleaned nick.
local function accusationTokens(bot)
	local nick = chat.CleanNick(bot)
	if nick == "" or nick == "you" then return {} end
	local firstWord = string.match(nick, "^%S+") or nick
	local letters = string.gsub(firstWord, "[^%a]", "")
	local short = (#letters >= 3) and firstWord or string.sub(nick, 1, 5)
	return { string.lower(nick), string.lower(firstWord), string.lower(short) }
end

-- Mention naming (deliverable D.2's own, slightly different, rule): cleaned
-- nick, first word only if it has >= 4 letters, and first 5 letters.
local function mentionTokens(bot)
	local nick = chat.CleanNick(bot)
	if nick == "" or nick == "you" then return {} end
	local firstWord = string.match(nick, "^%S+") or nick
	local letters = string.gsub(firstWord, "[^%a]", "")
	local tokens = { string.lower(nick), string.lower(string.sub(nick, 1, 5)) }
	if #letters >= 4 then tokens[#tokens + 1] = string.lower(firstWord) end
	return tokens
end

local function findNamedBot(text, tokenFn)
	local matches = {}
	for bot in pairs(D.brains) do
		if isBotEntity(bot) then
			for _, token in ipairs(tokenFn(bot)) do
				if containsToken(text, token) then
					matches[#matches + 1] = bot
					break
				end
			end
		end
	end
	return matches
end

local function hasAnyAmmo(bot)
	for _, wep in ipairs(bot:GetWeapons()) do
		if IsValid(wep) and wep.GetPrimaryAmmoType then
			local ammoType = wep:GetPrimaryAmmoType()
			if ammoType and ammoType >= 0 and bot:GetAmmoCount(ammoType) > 0 then return true end
		end
	end
	return false
end

local function currentMode()
	return zb and (zb.CROUND_MAIN or zb.CROUND)
end

-- hg.botdriver.relations (sv_relations.lua) exposes only Get/TargetBias, both
-- read-only -- there is no write entry point to bump a grudge record from a
-- chat insult. Per the brief's own "call nothing that does not exist" guard
-- this stays a no-op until sv_relations.lua grows one.
local function bumpGrudge(bot, ply) end

----------------------------------------------------------------------
-- Pools
----------------------------------------------------------------------

local ACCUSATION = {
	"?", "lol what", "bro what", "im not a bot lol", "ok", "which one", "lmao", "u good?",
	"everyone u lose to is a bot huh", "wdym", "ive been here since like july", "nah", "bot detected", "cope",
}
local ACCUSATION_SECOND = {
	"leave him alone lol", "hes been here for ages", "not everything is a bot man", "lol", "ok detective",
}
local MENTION = { "?", "what", "yea?", "hm?", "sup", "who me", "wat", "yeah", "im here", "what did i do" }
local INSULT = { "ok", "cry", "?", "u first", "sure", "lol", "and?", "k", "says u", "big talk" }
local GREETING = { "hey", "yo", "hi", "sup", "o/", "hello", "hey man", "hi hi", "ayo" }
local HELP = { "where u at", "i got one", "coming", "where", "i have a bandage", "otw" }
local ROUNDEND_FALLBACK = { "gg", "ggs", "gg wp" }

local INSULT_WORDS = { "trash", "bad", "noob", "shit", "garbage", "dogshit", "awful", "terrible", "suck", "useless" }
local MEDICAL_WORDS = { "medkit", "med", "bandage", "heal", "medic" }
local HELP_WORDS = { "medkit", "med", "bandage", "heal", "medic", "ammo", "help" }
local GREETING_PREFIXES = { "hi all", "hello everyone", "hey all", "hi", "hello", "hey", "yo", "sup", "o/" }
local GG_PHRASES = { gg = true, ggs = true, ["gg wp"] = true, wp = true, ez = true, ["gg all"] = true }

local TEAM_MODES = {
	tdm = true, gwars = true, cstrike = true, hl2dm = true, criresp = true,
	coop = true, defense = true, riot = true, ["Cops/Gangsters"] = true,
}

local lastRoundEndAt = -math.huge
hook.Add("ZB_EndRound", "zc_bots_chat_listen_roundend", function() lastRoundEndAt = CurTime() end)

local lastAccusationAt, lastAccusationBot = -math.huge, nil

----------------------------------------------------------------------
-- Delivery: one shared reservation/scheduling path for every classifier.
-- Global public_reply cap first (cheapest to fail), then the classifier's
-- own moment (if any), then an irregular ReplyDelay, then the send itself
-- goes through the same typing + Stylize funnel chatter/social/squad use.
----------------------------------------------------------------------

local function attemptReply(bot, line, momentKey, momentMax, momentWindow)
	if not IsValid(bot) or not line then return false end
	if not chat or not chat.MomentAllowed then return false end
	if chat.RecentGlobal and chat.RecentGlobal(line) then return false end
	if not chat.MomentAllowed("public_reply", 1, 8) then return false end
	if momentKey and not chat.MomentAllowed(momentKey, momentMax, momentWindow) then return false end

	local delay = chat.ReplyDelay and chat.ReplyDelay(bot, "public")
	if chat.ReplyDelay and not delay then return false end
	delay = delay or math.Rand(3, 12)

	if chat.RememberGlobal then chat.RememberGlobal(line) end
	local brain = D.brains[bot]
	if brain then brain.chatListenLastAt = CurTime() end

	timer.Create("zc_bots_listen_" .. bot:EntIndex(), delay, 1, function()
		local liveBrain = D.brains[bot]
		if not liveBrain then return end
		local ok = canReply(bot, liveBrain, CurTime())
		if not ok then return end
		D.chatTyping.SendWithTyping(bot, line, function(speaker, styledLine)
			D.chatter.Say(speaker, styledLine)
		end)
	end)
	return true
end

----------------------------------------------------------------------
-- Classifiers
----------------------------------------------------------------------

local function handleAccusation(lower, requireDead, now)
	local named = findNamedBot(lower, accusationTokens)
	local isRepeat = lastAccusationBot ~= nil and now - lastAccusationAt < 60
	local candidates, lines
	if isRepeat and math.random() < 0.30 then
		candidates = filterEligible(otherBots(lastAccusationBot), requireDead, now)
		lines = ACCUSATION_SECOND
	else
		candidates = filterEligible(#named > 0 and named or chattyBots(), requireDead, now)
		lines = ACCUSATION
	end
	if #candidates == 0 or math.random() >= 0.45 then return end
	local bot = candidates[math.random(#candidates)]
	if attemptReply(bot, lines[math.random(#lines)], "accusation", 1, 45) then
		lastAccusationAt, lastAccusationBot = now, bot
	end
end

local function handleMention(ply, lower, mentionedBots, requireDead, now)
	local eligible = filterEligible(mentionedBots, requireDead, now)
	if #eligible == 0 then return end
	local bot = eligible[math.random(#eligible)]

	local hasInsult = false
	for _, w in ipairs(INSULT_WORDS) do
		if containsToken(lower, w) then hasInsult = true break end
	end

	if hasInsult then
		local personality = D.GetPersonality and D.GetPersonality(bot)
		local composure = (personality and personality.composure) or 0.5
		local chance = 0.80 - composure * 0.50 -- low composure -> 80%, high -> 30%
		if math.random() < chance and attemptReply(bot, INSULT[math.random(#INSULT)], nil, nil, nil) then
			bumpGrudge(bot, ply)
		end
	elseif math.random() < 0.60 then
		attemptReply(bot, MENTION[math.random(#MENTION)], nil, nil, nil)
	end
end

local function handleGreeting(requireDead, now)
	local eligible = filterEligible(allBots(), requireDead, now)
	if #eligible == 0 or math.random() >= 0.40 then return end
	local bot = eligible[math.random(#eligible)]
	attemptReply(bot, GREETING[math.random(#GREETING)], "greeting", 1, 30)
end

local function handleGG(requireDead, now)
	if now - lastRoundEndAt > 40 then return end
	local eligible = filterEligible(allBots(), requireDead, now)
	local attempts = math.min(2, #eligible)
	for _ = 1, attempts do
		if #eligible == 0 then break end
		local idx = math.random(#eligible)
		local bot = table.remove(eligible, idx)
		local pool = (chat and chat.LowEffort and chat.LowEffort.roundend) or ROUNDEND_FALLBACK
		attemptReply(bot, pool[math.random(#pool)], "gg", 2, 30)
	end
end

local function handleHelp(ply, lower, requireDead, now)
	if not TEAM_MODES[currentMode() or ""] or D.IsFFA() then return end

	local hasMedicalWord, hasAmmoWord = false, false
	for _, w in ipairs(MEDICAL_WORDS) do if containsToken(lower, w) then hasMedicalWord = true break end end
	if containsToken(lower, "ammo") then hasAmmoWord = true end

	local team = D.TeamOf(ply)
	local candidates = {}
	for bot in pairs(D.brains) do
		if isBotEntity(bot) and bot:Alive() and D.TeamOf(bot) == team then
			local qualifies
			if hasMedicalWord then
				qualifies = D.BestCarriedMedical and D.BestCarriedMedical(bot) ~= nil
			elseif hasAmmoWord then
				qualifies = hasAnyAmmo(bot)
			else
				qualifies = (D.BestCarriedMedical and D.BestCarriedMedical(bot) ~= nil) or hasAnyAmmo(bot)
			end
			if qualifies then candidates[#candidates + 1] = bot end
		end
	end
	candidates = filterEligible(candidates, requireDead, now)
	if #candidates == 0 or math.random() >= 0.50 then return end

	local bot = candidates[math.random(#candidates)]
	local line = HELP[math.random(#HELP)]
	if attemptReply(bot, line, nil, nil, nil) and (line == "coming" or line == "otw" or line == "where u at") then
		D.SetObjective(bot, ply:GetPos(), 120, 25, "soft", "chat_help")
	end
end

----------------------------------------------------------------------
-- PlayerSay: dispatch only. Must return nothing -- ZChat owns the return
-- value that decides delivery.
----------------------------------------------------------------------

hook.Add("PlayerSay", "zc_bots_chat_listen", function(ply, text, teamChat)
	if not D.Enabled() then return end
	if not human(ply) then return end
	if not isstring(text) then return end
	text = string.Trim(text)
	if text == "" or #text > 200 then return end
	if string.find(text, "^[!/]") then return end

	local lower = string.lower(text)
	local isGG = GG_PHRASES[lower] == true
	if teamChat and not isGG then return end

	local liveRound = zb and zb.ROUND_STATE == 1
	local requireDead = liveRound and spectator(ply)
	local now = CurTime()

	local hasBotWord = string.find(lower, "%f[%w]bots?%f[%W]") ~= nil
	local mentionedBots = findNamedBot(lower, mentionTokens)
	local isGreeting = #lower <= 24 and startsWithAny(lower, GREETING_PREFIXES)
	local hasQuestionOrAnyone = string.find(lower, "?", 1, true) ~= nil or containsToken(lower, "anyone")
	local hasHelpWord = false
	for _, w in ipairs(HELP_WORDS) do if containsToken(lower, w) then hasHelpWord = true break end end
	local isHelpRequest = hasQuestionOrAnyone and hasHelpWord

	if hasBotWord then
		handleAccusation(lower, requireDead, now)
	elseif #mentionedBots > 0 then
		handleMention(ply, lower, mentionedBots, requireDead, now)
	elseif isGreeting then
		handleGreeting(requireDead, now)
	elseif isGG then
		handleGG(requireDead, now)
	elseif isHelpRequest then
		handleHelp(ply, lower, requireDead, now)
	end
end, HOOK_MONITOR_HIGH or -4) -- ULib: monitor priority runs BEFORE ZChat's handler (which returns "" and would
-- otherwise stop the chain before a normal-priority tap ever ran); monitor returns are ignored, so this can never alter chat.

-- clearPending (sv_chatter.lua) is file-local and unreachable from here, so
-- this owns cleanup of its own pending timer by the same naming convention.
hook.Add("PlayerDeath", "zc_bots_chat_listen_death", function(victim)
	if not IsValid(victim) then return end
	timer.Remove("zc_bots_listen_" .. victim:EntIndex())
end)
hook.Add("PlayerDisconnected", "zc_bots_chat_listen_disconnect", function(victim)
	if not IsValid(victim) then return end
	timer.Remove("zc_bots_listen_" .. victim:EntIndex())
end)
