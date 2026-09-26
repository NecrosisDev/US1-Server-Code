-- Sparse, action-aware bot chat. Lines use the established zChatPrint path,
-- never reveal hidden game state, and are globally throttled so a full bot
-- lobby still reads like people occasionally reacting rather than a chatbot
-- feed. Personality archetypes come from sv_personality.lua.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}
local chat = hg.botdriver.chat

hg.botdriver.DeclareBrainState("chatter", { perLife = false, fields = {
	"chatterCountThisRound", "chatterLastAt", "chatterDeathsBy",
	"chatterObserved", "chatterLastDamageAt",
} })

local cv_chatter = ConVarExists("zc_bots_chatter") and GetConVar("zc_bots_chatter")
	or CreateConVar("zc_bots_chatter", "0", FCVAR_ARCHIVE, "Sparse personality-driven bot chat reactions", 0, 1)

local GLOBAL_COOLDOWN = 6
local BOT_COOLDOWN = 17
local runtime = hg.botdriver.chatterRuntime or { epoch = 0, lastAt = -math.huge, recent = {} }
hg.botdriver.chatterRuntime = runtime
runtime.epoch = runtime.epoch + 1
local recentLines = runtime.recent
local recentSet = {}
for _, line in ipairs(recentLines) do recentSet[line] = true end

local LINES = {
	death = {
		"yeah that tracks", "i walked into that", "okay {name}", "well that's embarrassing",
		"fair", "i had a plan for like two seconds", "my fault", "there goes the medical bill",
		"tell my inventory i tried", "that angle was disgusting", "i'm cooked", "i deserved that",
		"did not see you there", "good shot unfortunately", "i would like a second opinion",
		"respawn department please", "that was avoidable", "i pressed every wrong key",
		"we'll pretend that was lag", "so much for that", "adding that to the incident report",
		"gonna stare at the killcam for a minute", "okay yeah you got it", "zero survival instincts",
		"i really committed to the bad idea", "that peek had negative value", "back to spectator jail",
	},
	melee = {
		"you really walked all the way over here", "{name} chose violence", "that was personal",
		"melee in this economy", "i heard you coming and still lost", "the disrespect",
		"getting folded up close is crazy", "could've at least knocked first",
		"that weapon has my fingerprints now", "i'm never living that down",
	},
	longrange = {
		"from over there seriously", "{name} has pixels for eyes", "that angle is illegal",
		"i was three business days away", "okay sniper", "didn't know that was a sightline",
		"render distance diff", "i was apparently visible from space", "clean shot {name}",
	},
	teamkill = {
		"{name} we are literally the same color", "wrong guy {name}", "check the uniform",
		"friendly fire is still fire i guess", "bro read the room", "that's coming out of your paycheck",
		"team recognition needs work", "i was on your side but okay", "excellent target selection",
	},
	repeatkill = {
		"{name} again", "i'm developing a {name} problem", "{name} has a subscription",
		"this is becoming a pattern", "i need a different route", "okay i'm staying away from {name}",
		"rent free apparently", "{name} please find a hobby", "same time next round i guess",
	},
	propdeath = {
		"killed by furniture incredible", "physics has chosen", "that prop had intent",
		"OSHA is typing", "cause of death: map decoration", "the chair won",
		"physics entered the chat", "that object had a family to feed",
	},
	hurt = {
		"ow", "okay {name}", "{name} chill", "that was my good arm", "i felt that one",
		"warning shot received", "you could've just said hi", "all right i'm moving",
		"that plate was rented", "noted", "medical is gonna love this", "bro i just got here",
		"that sounded expensive", "i'm fine probably", "little aggressive {name}",
	},
	heavyhurt = {
		"okay that actually hurt", "{name} took most of my health with that", "i need a minute",
		"everything is making a noise now", "that was nearly the whole warranty",
		"i can work with one lung probably", "suddenly reconsidering this fight",
		"my screen has opinions", "one more of those and i'm furniture",
	},
	revenge = {
		"we're even {name}", "had to do it", "nothing personal {name}", "that was for earlier",
		"got one", "we take those", "finally", "problem solved", "{name} almost had me",
		"that was way too close", "my hands are shaking", "okay i can breathe now",
		"one useful thing all round", "the comeback starts and ends here",
	},
	roundend = {
		"gg", "gg that got messy", "well that escalated", "that went fast", "good round",
		"that map owes me money", "i need water", "one more", "i have learned nothing",
		"solid round honestly", "we take those", "that could've gone worse", "barely counts but gg",
		"everyone okay no great", "inventory management simulator", "time to repeat every mistake",
		"my team was a social experiment", "i was useful emotionally", "close enough",
	},
}

local STYLE_LINES = {
	dry = {
		death = {"great", "of course", "excellent", "should've stayed home", "noted", "love that for me"},
		hurt = {"there goes my deposit", "that seems unhealthy", "well that's annoying", "very normal interaction"},
		revenge = {"we can both stop now", "about time", "got there eventually"},
		roundend = {"that happened", "well then", "no further questions"},
	},
	blunt = {
		death = {"{name} relax", "bro what", "oh we're doing this", "run that back", "actual crime"},
		hurt = {"back up {name}", "yeah i see you", "do that again i dare you"},
		revenge = {"sit down {name}", "there it is", "had enough of that"},
		roundend = {"gg i guess", "next map please", "that was rough"},
	},
	friendly = {
		death = {"nice one {name}", "gg {name}", "okay that was clean", "can't even be mad"},
		hurt = {"easy {name}", "hey we're talking this out", "all good mostly"},
		revenge = {"sorry {name}", "had to return that one", "gg {name}"},
		roundend = {"gg everyone", "good try team", "that was fun"},
	},
	nervous = {
		death = {"i knew that corner was bad", "nope nope too late", "why did i peek that", "panic aim failed"},
		hurt = {"nope i'm leaving", "where did that come from", "i do not like this angle"},
		revenge = {"oh thank god", "i thought i lost that", "never doing that again"},
		roundend = {"that was stressful", "i need a safer hobby", "i can unclench now"},
	},
	competitive = {
		death = {"one more and i adapt", "{name} is locked in", "okay you're on the list", "round's not over"},
		hurt = {"i know where you are now", "good tag {name}", "okay lock in"},
		revenge = {"caught the peek", "got you that time", "got the runback"},
		roundend = {"gg go next", "close one", "run it back"},
	},
	chaotic = {
		death = {"ragdoll speedrun", "free trial expired", "canon event", "chat is this real", "lost all my aura"},
		hurt = {"my bones are buffering", "health bar jumpscare", "bad vibes from that bullet"},
		revenge = {"huge for the economy", "plot armor activated", "calculated probably"},
		roundend = {"cinema", "absolute scenes", "the server survived us"},
	},
	laggy = {
		death = {"240 ping btw", "i swear i shot first", "my game froze", "i was already dead on my screen",
			"lag diff", "did not even see him on my end", "packet loss moment", "hotel wifi strikes again"},
		hurt = {"my screen is stuttering", "why am i teleporting", "hitreg is a myth", "rubberbanding again"},
		revenge = {"that one registered", "finally a hit that counts", "ping dropped for a second"},
		roundend = {"gg my internet", "ggs, gonna restart my router", "next round with less ping hopefully"},
	},
	casual = {
		death = {"ah okay", "yeah fair enough", "my bad honestly", "unlucky"},
		hurt = {"hey now", "okay okay", "i'm going i'm going"},
		revenge = {"there we go", "got lucky", "i'll take it"},
		roundend = {"ggs", "not bad", "that was a round"},
	},
}

hg.botdriver.chatTyping = hg.botdriver.chatTyping or {}

-- WS-D5: applies at most one typo to a whitespace-delimited, purely
-- alphabetic token of >= 4 letters (this alone excludes {name}
-- substitutions once `skip` is passed as the exact substituted name, and
-- excludes URLs, which never match ^%a+$). rng is an optional function
-- returning a number in [0,1) (defaults to math.random) so tests can drive
-- it deterministically. Returns the mutated text, plus the original word
-- and its mutated form (nil, nil if no eligible word existed) so a caller
-- can build a tidiness follow-up correction from the same roll.
function hg.botdriver.chatTyping.Typo(text, rng, skip)
	rng = rng or math.random
	if not isstring(text) or text == "" then return text end
	local candidates = {}
	for s, token, e in string.gmatch(text, "()(%S+)()") do
		if #token >= 4 and token == string.match(token, "^%a+$") and token ~= skip then
			candidates[#candidates + 1] = { s = s, e = e, w = token }
		end
	end
	if #candidates == 0 then return text end
	local pick = candidates[math.floor(rng() * #candidates) + 1]
	local word = pick.w
	local mode = math.floor(rng() * 3) -- 0 swap adjacent, 1 drop, 2 double
	local mutated
	if mode == 0 then
		local i = math.floor(rng() * (#word - 1)) + 1 -- swap i,i+1, i in [1,#word-1]
		mutated = string.sub(word, 1, i - 1) .. string.sub(word, i + 1, i + 1) .. string.sub(word, i, i) .. string.sub(word, i + 2)
	elseif mode == 1 then
		local i = math.floor(rng() * #word) + 1 -- drop the letter at i
		mutated = string.sub(word, 1, i - 1) .. string.sub(word, i + 1)
	else
		local i = math.floor(rng() * #word) + 1 -- double the letter at i
		mutated = string.sub(word, 1, i) .. string.sub(word, i, i) .. string.sub(word, i + 1)
	end
	return string.sub(text, 1, pick.s - 1) .. mutated .. string.sub(text, pick.e), word, mutated
end

local function clearPending(bot)
	if not IsValid(bot) then return end
	timer.Remove("zc_bots_typing_" .. bot:EntIndex())
	timer.Remove("zc_bots_hurt_chat_" .. bot:EntIndex())
	timer.Remove("zc_bots_revenge_chat_" .. bot:EntIndex())
	timer.Remove("zc_bots_death_chat_" .. bot:EntIndex())
	bot.zcTypingUntil = nil
	bot.zcTypingWasAliveAtStart = nil
	bot:SetNetVar("bIsTyping", false)
end

local function available(bot)
	return IsValid(bot) and bot.IsBot and bot:IsBot() and bot.zcBot and not bot.zcBotBenched and hg.botdriver.Enabled()
end

local function busy(bot, brain)
	return bot:Alive() and (hg.botdriver.IsDowned(bot)
		or (brain and (brain.actionPolicy or brain.medicPatient or brain.grenadeState
			or (brain.lastShotAt and CurTime() - brain.lastShotAt < 2))))
end

local function typingDuration(text, personality)
	local words = 0
	for _ in string.gmatch(text, "%S+") do words = words + 1 end
	local pace = personality and personality.verbosity or .5
	local duration = math.Clamp(words * math.Rand(.18, .36) * (1.12 - pace * .2), .65, 3.5)
	duration = duration * math.Rand(0.7, 1.6)
	if #text <= 3 then duration = math.Rand(0.35, 0.9) end
	return duration
end

-- Also used by squad callouts; retain its callback contract and cancel all
-- pending typing across lives, rounds, disconnects and code reloads.
function hg.botdriver.chatTyping.SendWithTyping(bot, text, sendFn, private)
	if not available(bot) then return false end
	if bot.zcTypingUntil and bot.zcTypingUntil > CurTime() then return false end
	local wasAlive = bot:Alive()
	local brain = hg.botdriver.brains[bot]
	if busy(bot, brain) then return false end
	local token = runtime.epoch
	local styledText = (chat and chat.Stylize) and chat.Stylize(bot, text) or text
	local duration = typingDuration(styledText, brain and brain.personality)
	bot.zcTypingWasAliveAtStart = wasAlive
	bot.zcTypingUntil = CurTime() + duration
	if not private then bot:SetNetVar("bIsTyping", true) end
	timer.Create("zc_bots_typing_" .. bot:EntIndex(), duration, 1, function()
		if not IsValid(bot) then return end
		bot:SetNetVar("bIsTyping", false)
		bot.zcTypingUntil = nil
		bot.zcTypingWasAliveAtStart = nil
		if token ~= runtime.epoch or not available(bot) or bot:Alive() ~= wasAlive then return end
		if not busy(bot, brain) then sendFn(bot, styledText) end
	end)
	return true
end

-- One death hook owns cancellation and the replacement death reaction.
hook.Remove("PlayerDeath", "zc_bots_typing_cancel")

local function doSay(bot, line, spectatorOnly)
	if not cv_chatter:GetBool() or not available(bot) then return end
	local dead = not bot:Alive() or bot:Team() == TEAM_SPECTATOR
	local liveRound = zb and zb.ROUND_STATE == 1
	local col = _G.team.GetColor(hg.botdriver.TeamOf(bot) or 0) or color_white
	local recipients = {}
	for _, ply in ipairs(player.GetHumans()) do
		if IsValid(ply) and (ply.zChatPrintMeta or ply.zChatPrint) and ((not spectatorOnly and (not dead or not liveRound)) or not ply:Alive() or ply:Team() == TEAM_SPECTATOR) then
			recipients[#recipients + 1] = ply
		end
	end
	if #recipients == 0 then return end
	local messageID = ZCChatReaction_Register and ZCChatReaction_Register(bot, recipients) or 0
	local speaker = (dead and "(DEAD) " or "") .. bot:Nick()
	for _, ply in ipairs(recipients) do
		if ply.zChatPrintMeta then
			ply:zChatPrintMeta(messageID, bot, col, speaker, color_white, ": " .. line)
		else
			ply:zChatPrint(col, speaker, color_white, ": " .. line)
		end
	end

	-- WS-E5: relay above the bot's head the same way
	-- addons/pats_text_presence's sv_pat_textpresence_bridge.lua does for a
	-- human's PlayerCanSeePlayersChat line -- that hook only ever fires for
	-- real PlayerSay traffic, and bots print via zChatPrintMeta/zChatPrint
	-- above (not PlayerSay), so the bridge never sees a bot's line on its
	-- own; this is the same relay done manually. Alive-only: dead chat is
	-- never shown over a human's head either, since the bridge only relays
	-- what PlayerCanSeePlayersChat actually passes to a live listener.
	if not dead and util.NetworkStringToID("PAT_TextPresence_Speech") ~= 0 then
		local origin = bot:GetPos()
		local heard = {}
		for _, ply in player.Iterator() do
			if IsValid(ply) and ply:GetPos():DistToSqr(origin) <= 1400 * 1400 then
				heard[#heard + 1] = ply
			end
		end
		if #heard > 0 then
			net.Start("PAT_TextPresence_Speech")
			net.WriteEntity(bot)
			net.WriteString(string.sub(line, 1, 240))
			net.WriteBool(false)
			net.Send(heard)
		end
	end
end

hg.botdriver.chatter = hg.botdriver.chatter or {}
function hg.botdriver.chatter.Say(bot, line)
	doSay(bot, line)
end

-- WS-chat-realism: chat.ShortName replaces the old fixed safeName() -- it
-- rolls per-bot how THIS bot writes another player's name (short/full/
-- pronoun, 15% no name at all). When it comes back "", collapse the
-- resulting doubled/leading/trailing space so "{name} again" reads as
-- "again" instead of " again".
local function applyName(template, bot, actor)
	if not string.find(template, "{name}", 1, true) then return template, nil end
	local name = chat and chat.ShortName and chat.ShortName(bot, actor) or "you"
	local line = string.gsub(template, "{name}", name)
	if name == "" then
		local collapsed = string.gsub(line, "%s%s+", " ")
		line = string.Trim(collapsed)
	end
	return line, name
end

local function rememberLine(template)
	recentLines[#recentLines + 1] = template
	recentSet[template] = true
	if #recentLines > 10 then recentSet[table.remove(recentLines, 1)] = nil end
end

local function chooseLine(bot, event, personality, actor)
	local social = hg.botdriver.socialLines and hg.botdriver.socialLines[event]
	local common = social and social.default or LINES[event] or LINES.death
	local styledLines = STYLE_LINES[personality and personality.chatStyle or "casual"]
	styledLines = social and social[personality and personality.archetype or "regular"] or (styledLines and styledLines[event] or nil)
	local lowEffort = chat and chat.LowEffort and chat.LowEffort[event]

	local function candidatesFrom(lines)
		local out = {}
		for _, template in ipairs(lines) do
			if not recentSet[template] and (IsValid(actor) or not string.find(template, "{name}", 1, true)) then
				out[#out + 1] = template
			end
		end
		return out
	end

	-- WS-chat-realism (B1): 65% of the time draw from the low-effort base
	-- register instead of the witty/style pools; reject a candidate the
	-- server has heard recently (chat.RecentGlobal) up to 4 times, then give
	-- up silently rather than force a stale line out.
	for _attempt = 1, 4 do
		local pool
		if lowEffort and math.random() < .65 then
			pool = lowEffort
		else
			pool = (styledLines and math.random() < .58 and styledLines) or common
		end
		local candidates = candidatesFrom(pool)
		if #candidates == 0 and pool ~= common then candidates = candidatesFrom(common) end
		if #candidates > 0 then
			local template = candidates[math.random(#candidates)]
			local line, name = applyName(template, bot, actor)
			if not chat or not chat.RecentGlobal or not chat.RecentGlobal(line) then
				if chat and chat.RememberGlobal then chat.RememberGlobal(line) end
				return line, template, name
			end
		end
	end
	return nil
end

local function maybeSpeak(bot, brain, event, actor, chance, requireAlive, options)
	if not cv_chatter:GetBool() or not available(bot) or not brain or #player.GetHumans() == 0 then return false end
	if requireAlive and not bot:Alive() then return false end
	if busy(bot, brain) then return false end
	local now = CurTime()
	if now - runtime.lastAt < GLOBAL_COOLDOWN or now - (brain.chatterLastAt or -math.huge) < BOT_COOLDOWN then return false end
	local p = hg.botdriver.GetPersonality(bot)
	local budget = p.chatty and (p.archetype == "gremlin" and 3 or 2) or 1
	if (brain.chatterCountThisRound or 0) >= budget then return false end
	local frequency = p.chatty and 1 or .22
	if event == "hurt" or event == "heavyhurt" then frequency = frequency * (1.3 - (p.composure or .5) * .6) end
	if event == "repeatkill" or event == "revenge" then frequency = frequency * (.6 + (p.grudge or .5)) end
	if event == "roundend" then frequency = frequency * (.5 + (p.sportsmanship or .5)) end
	if math.random() >= chance * frequency then return false end
	local line, template, resolvedName = chooseLine(bot, event, p, actor)
	if not line then return false end
	-- WS-D5: personality.typoChance consumer. ~6-45% of lines (typoChance is
	-- rolled .01-.075 in sv_personality.lua, so *6 lands in that band) get
	-- exactly one typo; never on the substituted name text itself (`skip`).
	-- A tidiness > 0.72 bot then has a 35% chance (WS-chat-realism B4, was
	-- unconditional) to schedule a separate "*word" correction through the
	-- same SendWithTyping path 1.2-2.6s later -- it deliberately bypasses
	-- maybeSpeak's own cooldown/budget gate (called directly below, not
	-- recursed back into this function) so it counts as a continuation of
	-- this same utterance, not a second one: chatterCountThisRound is not
	-- bumped for it and runtime.lastAt/brain.chatterLastAt are left alone.
	local typoWord
	if math.random() < math.Clamp((p.typoChance or 0) * 6, 0, 1) then
		local skip = resolvedName and resolvedName ~= "" and resolvedName or nil
		local mutatedLine, original = hg.botdriver.chatTyping.Typo(line, nil, skip)
		if original then
			line = mutatedLine
			typoWord = original
		end
	end
	if not hg.botdriver.chatTyping.SendWithTyping(bot, line, function(speaker, text)
		if options and options.validate and not options.validate(speaker) then return end
		doSay(speaker, text, options and options.spectatorOnly)
		if options and options.after then options.after(speaker) end
		if typoWord and p.tidiness and p.tidiness > 0.72 and math.random() < 0.35 then
			-- 10% of the time the "correction" is itself another wrong
			-- spelling -- apply Typo again to the word that would have been
			-- the fix, so the follow-up reads like a second fumbled attempt.
			local correctionWord = typoWord
			if math.random() < 0.10 then
				correctionWord = hg.botdriver.chatTyping.Typo(typoWord, nil, nil)
			end
			timer.Simple(math.Rand(1.2, 2.6), function()
				if not available(speaker) then return end
				hg.botdriver.chatTyping.SendWithTyping(speaker, "*" .. correctionWord, function(correctSpeaker, correctText)
					if options and options.validate and not options.validate(correctSpeaker) then return end
					doSay(correctSpeaker, correctText, options and options.spectatorOnly)
				end, false)
			end)
		end
	end) then return false end
	rememberLine(template)
	brain.chatterCountThisRound = (brain.chatterCountThisRound or 0) + 1
	brain.chatterLastAt = now
	runtime.lastAt = now
	return true
end

hg.botdriver.ChatterSpeak = maybeSpeak

local function weaponClass(attacker, inflictor)
	if IsValid(inflictor) and inflictor ~= attacker and inflictor.GetClass then return string.lower(inflictor:GetClass() or "") end
	if IsValid(attacker) and attacker.GetActiveWeapon then
		local wep = attacker:GetActiveWeapon()
		if IsValid(wep) then return string.lower(wep:GetClass() or "") end
	end
	return ""
end

local function isMeleeClass(class)
	return string.find(class, "melee", 1, true) or string.find(class, "knife", 1, true)
		or string.find(class, "axe", 1, true) or string.find(class, "shovel", 1, true)
		or string.find(class, "crowbar", 1, true) or string.find(class, "fist", 1, true)
end

local function observed(bot, brain, actor)
	local seen = brain.chatterObserved and brain.chatterObserved[actor]
	return seen and CurTime() - seen < 12
end

local TEAM_MODES = { tdm = true, gwars = true, cstrike = true, hl2dm = true, criresp = true,
	coop = true, defense = true, riot = true, ["Cops/Gangsters"] = true }

hook.Add("PlayerSpawn", "zc_bots_chatter_spawn", function(bot)
	if not IsValid(bot) or not bot:IsBot() or not bot.zcBot then return end
	clearPending(bot)
	local brain = hg.botdriver.GetBrain(bot)
	brain.chatterLastDamageAt = nil
	brain.chatterObserved = nil
end)

hook.Add("PlayerDisconnected", "zc_bots_chatter_disconnect", clearPending)

hook.Add("PlayerDeath", "zc_bots_chatter_death", function(victim, inflictor, attacker)
	if not IsValid(victim) or not victim:IsBot() or not victim.zcBot then return end
	clearPending(victim)
	if not available(victim) then return end
	if not IsValid(attacker) or not attacker:IsPlayer() or attacker:IsBot() then return end
	local brain = hg.botdriver.brains[victim]
	if not brain then return end
	local known = observed(victim, brain, attacker)
	local event = "death"
	if known then
		-- Weak entity keys and a three-minute expiry keep this social history
		-- bounded. It is never used for targeting or traitor identification.
		brain.chatterDeathsBy = brain.chatterDeathsBy or setmetatable({}, { __mode = "k" })
		local prior = brain.chatterDeathsBy[attacker]
		local count = prior and CurTime() - prior.at < 180 and prior.count + 1 or 1
		brain.chatterDeathsBy[attacker] = { at = CurTime(), count = count }
		local class = weaponClass(attacker, inflictor)
		local mode = zb and (zb.CROUND_MAIN or zb.CROUND)
		if TEAM_MODES[mode] and not hg.botdriver.IsFFA() and hg.botdriver.TeamOf(victim) == hg.botdriver.TeamOf(attacker) then
			event = "teamkill"
		elseif count >= 2 then event = "repeatkill"
		elseif string.StartWith(class, "prop_") then event = "propdeath"
		elseif isMeleeClass(class) then event = "melee"
		elseif victim:GetPos():DistToSqr(attacker:GetPos()) > 1500 * 1500 then event = "longrange" end
	end
	local actor = known and attacker or nil
	local token = runtime.epoch
	timer.Create("zc_bots_death_chat_" .. victim:EntIndex(), math.Rand(0.4, 4), 1, function()
		if token ~= runtime.epoch or not available(victim) then return end
		maybeSpeak(victim, brain, event, actor, .58, false)
	end)
end)

hook.Add("HomigradDamage", "zc_bots_chatter_hurt", function(victim, dmg)
	if not IsValid(victim) or not victim.IsBot or not available(victim) or not cv_chatter:GetBool() then return end
	local attacker = dmg and dmg.GetAttacker and dmg:GetAttacker() or nil
	if not IsValid(attacker) or not attacker:IsPlayer() or attacker:IsBot() or attacker == victim then return end
	local brain = hg.botdriver.brains[victim]
	local damage = dmg.GetDamage and dmg:GetDamage() or 0
	if not brain or damage <= 0 then return end
	local known = hg.botdriver.lib.VisualContact and hg.botdriver.lib.VisualContact(victim, attacker, brain, false, CurTime())
	if known then
		brain.chatterObserved = brain.chatterObserved or setmetatable({}, { __mode = "k" })
		brain.chatterObserved[attacker] = CurTime()
	end
	clearPending(victim)
	brain.chatterLastDamageAt = CurTime()
	local token = runtime.epoch
	-- A single replaceable timer per bot coalesces pellets and burst fire.
	timer.Create("zc_bots_hurt_chat_" .. victim:EntIndex(), math.Rand(1.5, 9), 1, function()
		if token ~= runtime.epoch or not available(victim) or not victim:Alive() then return end
		if IsValid(brain.target) or busy(victim, brain) then return end
		local event = (damage >= 35 or victim:Health() <= 35) and "heavyhurt" or "hurt"
		maybeSpeak(victim, brain, event, known and attacker or nil, damage >= 35 and .24 or .12, true)
	end)
end)

hook.Add("PlayerDeath", "zc_bots_chatter_revenge", function(victim, _inflictor, attacker)
	if not IsValid(victim) or not victim:IsPlayer() or victim:IsBot() then return end
	if not available(attacker) then return end
	local brain = hg.botdriver.brains[attacker]
	if not brain or not observed(attacker, brain, victim) then return end
	local wasThreat = brain.attackedBy == victim and CurTime() - (brain.attackedAt or -math.huge) < 18
	if not wasThreat then return end
	local token = runtime.epoch
	timer.Create("zc_bots_revenge_chat_" .. attacker:EntIndex(), math.Rand(1.5, 6), 1, function()
		if token ~= runtime.epoch or not available(attacker) or not attacker:Alive() then return end
		if IsValid(brain.target) and brain.target:Alive() then return end
		maybeSpeak(attacker, brain, "revenge", victim, .34, true)
	end)
end)

local function cancelRound()
	runtime.epoch = runtime.epoch + 1
	for bot, brain in pairs(hg.botdriver.brains) do
		clearPending(bot)
		brain.chatterObserved = nil
		brain.chatterLastDamageAt = nil
	end
end

hook.Add("ZB_EndRound", "zc_bots_chatter_roundend", function()
	cancelRound()
	if not hg.botdriver.Enabled() then return end
	for bot, brain in RandomPairs(hg.botdriver.brains) do
		if not chat or not chat.MomentAllowed or chat.MomentAllowed("roundend", 2, 25) then
			maybeSpeak(bot, brain, "roundend", nil, .22, false)
		end
	end
end)

hook.Add("ZB_PreRoundStart", "zc_bots_chatter_reset", function()
	cancelRound()
	for _, brain in pairs(hg.botdriver.brains) do brain.chatterCountThisRound = nil end
end)

-- Retain rate limits and recent-line history through hotload, but invalidate
-- callbacks created by the previous module version.
for bot, brain in pairs(hg.botdriver.brains) do
	clearPending(bot)
	-- Upgrade the previous SteamID/count map to weak entity/timestamp records.
	if not brain.chatterDeathsBy or not getmetatable(brain.chatterDeathsBy) then brain.chatterDeathsBy = nil end
end
