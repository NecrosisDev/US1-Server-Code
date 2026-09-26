-- Per-bot chat "voice" (2026-09-23 chat realism pass, deliverable A). Each
-- bot writes like an actual low-effort GMod player instead of a uniform
-- narrator: a stable per-bot style (capitalisation, punctuation, apostrophe
-- habits, abbreviation rate, how it writes other players' names) rolled ONCE
-- and cached by bot NAME -- same lifetime rule as sv_personality.lua's
-- personalityByName (survives a disconnect/reconnect within the same map/Lua
-- state; cleared only by a fresh Lua state). This file owns text SHAPE only
-- -- it never decides WHAT a bot says. sv_chatter.lua/sv_social.lua/
-- sv_chat_listen.lua pick lines from their own pools; this reshapes whatever
-- line they hand it, and gives them shared anti-repetition (RecentGlobal/
-- RememberGlobal), per-moment speaker caps (MomentAllowed) and irregular
-- reply timing (ReplyDelay).

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}
hg.botdriver.chat = hg.botdriver.chat or {}
local chat = hg.botdriver.chat

----------------------------------------------------------------------
-- Style: rolled once per bot name, cached like sv_personality.lua's
-- personalityByName (hotload-safe: the cache table itself is only ever
-- created once, so re-including this file on autorefresh keeps every
-- already-rolled bot's voice).
----------------------------------------------------------------------

hg.botdriver.chatStyleByName = hg.botdriver.chatStyleByName or {}
local styleByName = hg.botdriver.chatStyleByName

local TAIL_POOL = { " lol", " lmao", " xd", " haha" }
local PRONOUNS = { "that guy", "dude", "bro", "him", "my guy" }

local function weighted(choices)
	local total = 0
	for _, c in ipairs(choices) do total = total + c.weight end
	local pick = math.random() * total
	for _, c in ipairs(choices) do
		pick = pick - c.weight
		if pick <= 0 then return c.value end
	end
	return choices[#choices].value
end

-- 2026-09-26: the rolled shape now follows the bot's temperament
-- (sv_personality.lua) and tidiness instead of being independent of them,
-- so the guy who writes "Good game, everyone." is also the one who says
-- sorry, and the one typing "WHAT" in caps is the one with no composure.
-- STYLE_VERSION marks styles rolled by this rule; an older cached style is
-- re-rolled once.
local STYLE_VERSION = 2

local function rollStyle(personality)
	local tidiness = (personality and personality.tidiness) or 0.5
	local temper = (personality and personality.temperament) or "chill"
	local style = {
		v = STYLE_VERSION,
		caps = weighted({ { value = "lower", weight = 68 }, { value = "sentence", weight = 22 }, { value = "loud", weight = 10 } }),
		punct = weighted({ { value = "none", weight = 55 }, { value = "period", weight = 15 }, { value = "excl", weight = 15 }, { value = "ellipsis", weight = 15 } }),
		apostrophes = math.random() < 0.55 and "drop" or "keep",
		abbrev = math.Rand(0, 1) * (1 - tidiness),
		tailChance = math.Rand(0, 0.18),
		nameStyle = weighted({ { value = "short", weight = 55 }, { value = "full", weight = 25 }, { value = "pronoun", weight = 20 } }),
		shout = 0.2,
	}
	local tidy = tidiness >= 0.8 or (temper == "polite" and tidiness >= 0.55)
	if tidy then
		-- Proper sentences: capitalised, "I" not "i", full stops, apostrophes.
		style.caps = "proper"
		style.punct = weighted({ { value = "period", weight = 70 }, { value = "none", weight = 20 }, { value = "excl", weight = 10 } })
		style.apostrophes = "keep"
		style.abbrev = style.abbrev * 0.2
		style.tailChance = style.tailChance * 0.25
		style.nameStyle = math.random() < 0.7 and "full" or "short"
	elseif temper == "ragey" then
		style.caps = weighted({ { value = "loud", weight = 55 }, { value = "lower", weight = 45 } })
		style.punct = weighted({ { value = "excl", weight = 45 }, { value = "none", weight = 40 }, { value = "period", weight = 15 } })
		style.shout = math.Rand(0.3, 0.55)
		style.tailChance = style.tailChance * 0.4
	elseif temper == "gloomy" then
		style.caps = "lower"
		style.punct = weighted({ { value = "ellipsis", weight = 50 }, { value = "none", weight = 40 }, { value = "period", weight = 10 } })
		style.tailChance = style.tailChance * 0.2
	elseif temper == "crude" then
		style.caps = math.random() < 0.85 and "lower" or "loud"
		style.punct = weighted({ { value = "none", weight = 75 }, { value = "excl", weight = 15 }, { value = "ellipsis", weight = 10 } })
		style.apostrophes = "drop"
		style.abbrev = math.max(style.abbrev, math.Rand(0.35, 0.8))
		style.tailChance = math.Rand(0.1, 0.3)
	end
	return style
end

-- chat.Style(bot): per-bot-name cached style. An invalid bot (e.g. a unit
-- test caller with no entity) still gets a usable, just uncached, style.
function chat.Style(bot)
	if not IsValid(bot) then return rollStyle(nil) end
	local name = bot.Nick and bot:Nick() or nil
	local cached = name and styleByName[name]
	if cached and cached.v == STYLE_VERSION then return cached end
	local personality = hg.botdriver.GetPersonality and hg.botdriver.GetPersonality(bot)
	local style = rollStyle(personality)
	if name then styleByName[name] = style end
	return style
end

----------------------------------------------------------------------
-- Stylize: reshapes a chosen line to match the bot's rolled style. Never
-- touches a "!"/"/" command line, a URL, or text inside {...} (a template
-- placeholder some caller failed to substitute). Pure given (style, text,
-- rng) -- rng defaults to math.random so callers can pass a deterministic
-- stand-in.
----------------------------------------------------------------------

-- Multi-word / apostrophe-bearing phrases matched as a literal
-- case-insensitive substring (an apostrophe or a space inside the phrase
-- would never survive a %a+ word pattern). Longest-first so "oh my god"
-- cannot be partially eaten by a shorter rule first.
local PHRASE_ABBR = {
	{ "i don't know", "idk" }, { "oh my god", "omg" }, { "to be honest", "tbh" },
	{ "what the fuck", "wtf" }, { "never mind", "nvm" },
	{ "you're", "ur" }, { "right now", "rn" },
}

-- Whole-word, case-insensitive, single-token replacements.
local WORD_ABBR = {
	{ "you", "u" }, { "your", "ur" }, { "are", "r" }, { "though", "tho" },
	{ "probably", "prob" }, { "because", "cuz" }, { "with", "w" },
	{ "really", "rly" }, { "people", "ppl" }, { "about", "abt" },
	{ "something", "smth" },
}

local APOSTROPHE_WORDS = {
	{ "i'm", "im" }, { "don't", "dont" }, { "can't", "cant" },
	{ "that's", "thats" }, { "you're", "youre" },
}

-- Stash {...} spans and URL-looking tokens behind unique placeholders so
-- none of the passes below ever rewrites them; restoreSpans puts the
-- original text back once every pass is done.
local function protectSpans(text)
	local stash = {}
	local function keep(m)
		stash[#stash + 1] = m
		return "\1" .. #stash .. "\2"
	end
	text = string.gsub(text, "%b{}", keep)
	text = string.gsub(text, "%f[%w]%a[%w+.-]*://%S+", keep)
	text = string.gsub(text, "%f[%w]www%.%S+", keep)
	return text, stash
end

local function restoreSpans(text, stash)
	if #stash == 0 then return text end
	return (string.gsub(text, "\1(%d+)\2", function(i) return stash[tonumber(i)] or "" end))
end

local function applyPhrases(text, chance, rng)
	local lower = string.lower(text)
	for _, pair in ipairs(PHRASE_ABBR) do
		local phrase, repl = pair[1], pair[2]
		local start = 1
		while true do
			local s, e = string.find(lower, phrase, start, true)
			if not s then break end
			if rng() < chance then
				text = string.sub(text, 1, s - 1) .. repl .. string.sub(text, e + 1)
				lower = string.lower(text)
				start = s + #repl
			else
				start = e + 1
			end
		end
	end
	return text
end

local function applyWords(text, chance, rng)
	return (string.gsub(text, "%a+", function(word)
		local lower = string.lower(word)
		for _, pair in ipairs(WORD_ABBR) do
			if pair[1] == lower and rng() < chance then return pair[2] end
		end
		return word
	end))
end

local function dropApostrophes(text)
	for _, pair in ipairs(APOSTROPHE_WORDS) do
		local phrase, plain = pair[1], pair[2]
		local lower = string.lower(text)
		local start = 1
		while true do
			local s, e = string.find(lower, phrase, start, true)
			if not s then break end
			text = string.sub(text, 1, s - 1) .. plain .. string.sub(text, e + 1)
			lower = string.lower(text)
			start = s + #plain
		end
	end
	return text
end

function chat.Stylize(bot, text, rng)
	rng = rng or math.random
	if not isstring(text) or text == "" then return text end
	if string.find(text, "^[!/]") then return text end -- commands: untouched

	local style = chat.Style(bot)
	local body, stash = protectSpans(text)

	body = applyPhrases(body, style.abbrev, rng)
	body = applyWords(body, style.abbrev, rng)
	if style.apostrophes == "drop" then body = dropApostrophes(body) end

	-- Punctuation: strip any existing trailing . ! ? first; a line that
	-- ended in "?" keeps exactly that "?" regardless of the rolled policy.
	local hadQuestion = string.find(body, "%?%s*$") ~= nil
	body = string.gsub(body, "[%.%!%?]+%s*$", "")
	if hadQuestion then
		body = body .. "?"
	elseif style.punct == "period" then
		body = body .. "."
	elseif style.punct == "excl" then
		body = body .. (rng() < 0.5 and "!" or "!!")
	elseif style.punct == "ellipsis" then
		body = body .. "..."
	end

	local words = 0
	for _ in string.gmatch(body, "%S+") do words = words + 1 end
	if style.caps == "lower" then
		body = string.lower(body)
	elseif style.caps == "sentence" or style.caps == "loud" or style.caps == "proper" then
		body = string.lower(body)
		body = string.upper(string.sub(body, 1, 1)) .. string.sub(body, 2)
		if style.caps == "proper" then
			body = string.gsub(body, "%f[%a]i%f[%A]", "I")
			body = string.gsub(body, "([%.!%?]%s+)(%l)", function(gap, letter) return gap .. string.upper(letter) end)
		end
		if style.caps == "loud" and words <= 7 and rng() < (style.shout or 0.2) then
			body = string.upper(body)
		end
	end

	if rng() < style.tailChance then
		local hasTail = false
		local lowerBody = string.lower(body)
		-- Any laugh already in the line ("lmaooo", "lol", "hahaha") counts.
		if string.find(lowerBody, "lmao", 1, true) or string.find(lowerBody, "lol", 1, true)
			or string.find(lowerBody, "haha", 1, true) or string.find(lowerBody, "%f[%w]xd%f[%W]") then
			hasTail = true
		end
		if not hasTail then
			-- People drop the full stop before a trailing "lol".
			body = string.gsub(body, "[%.!]+$", "")
			body = body .. TAIL_POOL[math.floor(rng() * #TAIL_POOL) + 1]
		end
	end

	return restoreSpans(body, stash)
end

----------------------------------------------------------------------
-- Names: how people actually write each other's names in chat.
----------------------------------------------------------------------

-- chat.CleanNick: deterministic cleanup shared by ShortName and by
-- sv_chat_listen.lua's own "is this bot named in the message" matching.
function chat.CleanNick(ply)
	if not IsValid(ply) then return "" end
	local nick = ply.Nick and ply:Nick() or ""
	nick = string.Trim(string.gsub(nick, "%c", ""))
	nick = string.gsub(nick, "%b[]", "")
	nick = string.gsub(nick, "%b()", "")
	nick = string.gsub(nick, "^[^%w]+", "")
	local pipe = string.find(nick, "|", 1, true)
	if pipe then nick = string.sub(nick, 1, pipe - 1) end
	local dash = string.find(nick, " %- ", 1)
	if dash then nick = string.sub(nick, 1, dash - 1) end
	nick = string.Trim(nick)
	if nick == "" or #nick > 40 then nick = "you" end
	return nick
end

-- strict (2026-09-26, spectator conversations): always an actual name --
-- never dropped, never "that guy". A name in the middle of a sentence
-- ("why does {b} type like that") cannot be left out or pronoun-ed.
function chat.ShortName(bot, ply, strict)
	if not IsValid(ply) then return "" end
	local style = chat.Style(bot)
	if not strict and math.random() < 0.15 then return "" end

	local nick = chat.CleanNick(ply)
	if style.nameStyle == "full" then return nick end
	if style.nameStyle == "pronoun" and not strict then return PRONOUNS[math.random(#PRONOUNS)] end

	local firstWord = string.match(nick, "^%S+") or nick
	local letters = string.gsub(firstWord, "[^%a]", "")
	if #letters >= 3 then return string.lower(firstWord) end
	return string.lower(string.sub(nick, 1, 5))
end

----------------------------------------------------------------------
-- Anti-repetition: a server-wide ring of the last 40 normalised lines any
-- bot has said, 12-minute TTL, shared by chatter/social/listen so two bots
-- (or the same bot twice) never echo the exact same line back to back.
----------------------------------------------------------------------

local GLOBAL_RING_SIZE = 40
local GLOBAL_TTL = 12 * 60

hg.botdriver.chatGlobalRing = hg.botdriver.chatGlobalRing or {}
local globalRing = hg.botdriver.chatGlobalRing

local function normalizeLine(text)
	if not isstring(text) then return "" end
	local norm = string.lower(text)
	norm = string.gsub(norm, "%p", "")
	norm = string.gsub(norm, "%s+", " ")
	return string.Trim(norm)
end

function chat.RememberGlobal(text)
	local norm = normalizeLine(text)
	if norm == "" then return end
	globalRing[#globalRing + 1] = { norm = norm, at = CurTime() }
	while #globalRing > GLOBAL_RING_SIZE do table.remove(globalRing, 1) end
end

function chat.RecentGlobal(text)
	local norm = normalizeLine(text)
	if norm == "" then return false end
	local now = CurTime()
	for i = #globalRing, 1, -1 do
		local entry = globalRing[i]
		if now - entry.at > GLOBAL_TTL then
			table.remove(globalRing, i)
		elseif entry.norm == norm then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------
-- MomentAllowed: a global per-moment speaker cap so a shared beat (round
-- end, a greeting, an accusation) never turns into every bot piling on.
----------------------------------------------------------------------

local MOMENT_DEFAULTS = {
	roundend = { max = 2, window = 25 },
	roundstart = { max = 1, window = 90 },
	greeting = { max = 1, window = 30 },
	accusation = { max = 1, window = 45 },
	gg = { max = 2, window = 30 },
	public_reply = { max = 1, window = 8 },
}

hg.botdriver.chatMoments = hg.botdriver.chatMoments or {}
local moments = hg.botdriver.chatMoments

function chat.MomentAllowed(key, maxSpeakers, windowSeconds)
	local defaults = MOMENT_DEFAULTS[key]
	maxSpeakers = maxSpeakers or (defaults and defaults.max) or 1
	windowSeconds = windowSeconds or (defaults and defaults.window) or 30
	local now = CurTime()
	local list = moments[key]
	if not list then
		list = {}
		moments[key] = list
	end
	local i = 1
	while i <= #list do
		if now - list[i] > windowSeconds then
			table.remove(list, i)
		else
			i = i + 1
		end
	end
	if #list >= maxSpeakers then return false end
	list[#list + 1] = now
	return true
end

----------------------------------------------------------------------
-- ReplyDelay: irregular pacing so a reply never lands on a metronome.
----------------------------------------------------------------------

function chat.ReplyDelay(bot, kind)
	local base
	if not IsValid(bot) or not bot:Alive() or bot:Team() == TEAM_SPECTATOR then
		base = math.Rand(1, 5)
	else
		local brain = hg.botdriver.brains and hg.botdriver.brains[bot]
		local now = CurTime()
		local engaged = brain and (IsValid(brain.target) or (brain.chatterLastDamageAt and now - brain.chatterLastDamageAt < 3))
		if engaged then
			if math.random() < 0.4 then return nil end
			base = math.Rand(8, 25)
		else
			if math.random() < 0.15 then return nil end
			base = math.Rand(3, 12)
		end
	end
	if kind == "pm" then base = base + math.Rand(1, 3) end
	return base
end

----------------------------------------------------------------------
-- LowEffort: the base register chooseLine draws from 65% of the time
-- (deliverable A.7 / B.1). Copied verbatim from the brief.
----------------------------------------------------------------------

chat.LowEffort = {
	death = {
		"lol", "wtf", "?", "how", "nice", "bruh", "ok", "damn", "gg", "ez for u", "oof", "rip", "yep", "ah",
		"wow", "nah", "cmon", "fair", "ugh", "welp", "lmao", "lag", "1 tap wtf", "how did that hit", "ok then",
	},
	hurt = {
		"ow", "ah", "hey", "stop", "wtf", "ouch", "who", "?", "no", "hey!", "chill", "help", "im hit", "ow ow ow",
	},
	revenge = {
		"lol", "got him", "ez", "nice", "haha", "there", "finally", "ok", "gotcha", "yep", "thats it", "boom",
	},
	roundend = {
		"gg", "ggs", "gg wp", "ez", "lol", "nice", "close", "damn", "again", "one more", "gg all",
		"that was a round", "lmao", "wp",
	},
	teamkill = {
		"my bad", "oops", "sorry", "mb", "sry", "oh no", "ah sorry", "that was me?",
	},
	melee = {
		"lol", "wtf", "how", "no way", "bro", "really", "ok", "punched to death lol",
	},
}
