-- Spectator conversations (2026-09-26 presentation-parity pass). Dead bots
-- used to manage one ambient line plus, at most, one bland reply
-- (sv_social.lua spec_open/spec_reply). Real dead chat is a running
-- conversation: people rib each other about how they died, argue about
-- nothing, explain mechanics to whoever just asked the obvious question,
-- and comment on each other's personalities. This file runs those
-- conversations between DEAD bots, only while a DEAD human is there to read
-- them (dead chat stays dead-only during a live round -- sv_chatter.lua
-- doSay's spectatorOnly path, same as every other spectator line).
--
-- Conversations are grounded in what actually happened this round, recorded
-- below per bot (how it died, to whom, with what, while reloading/healing,
-- how long it lived, kills and damage) and in each bot's rolled temperament
-- (sv_personality.lua). The script bank lives in sv_spec_talk_lines.lua;
-- this file owns memory, casting, pacing and delivery.
--
-- Delivery reuses the shared funnel (chatTyping.SendWithTyping -> Stylize ->
-- chatter.Say), so every line gets the speaker's own typing speed and
-- typing style, the typing indicator, and joins the shared anti-repetition
-- ring. Never reveals anything a dead player could not see for themselves:
-- a dead bot only talks about its own death, other dead players' deaths and
-- personalities, and general game knowledge.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}
local D = hg.botdriver
local chat = D.chat

D.specTalk = D.specTalk or { epoch = 0 }
local T = D.specTalk
T.epoch = (T.epoch or 0) + 1
T.memory = T.memory or setmetatable({}, { __mode = "k" })
T.recentScripts = T.recentScripts or {}
T.nextAt = T.nextAt or 0
T.roundCount = T.roundCount or 0
T.active = nil

local cv_chatter = GetConVar("zc_bots_chatter")
local cv_spec = ConVarExists("zc_bots_spec_talk") and GetConVar("zc_bots_spec_talk")
	or CreateConVar("zc_bots_spec_talk", "1", FCVAR_ARCHIVE, "Dead bots hold conversations in spectator chat while a dead human is watching", 0, 1)

local GAP_MIN, GAP_MAX = 40, 110      -- quiet time between conversations
local MAX_PER_ROUND = 3
local SCRIPT_REPEAT_TTL = 25 * 60     -- the same script is not reused for this long
local STALL_TIMEOUT = 25              -- a conversation that stops progressing is dropped

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function isOurBot(p)
	return IsValid(p) and p:IsPlayer() and p:IsBot() and p.zcBot and not p.zcBotBenched
end

local function spectating(p)
	return not p:Alive() or p:Team() == TEAM_SPECTATOR
end

local function liveRound()
	return zb and zb.ROUND_STATE == 1
end

local function humanSpectatorPresent()
	for _, p in ipairs(player.GetHumans()) do
		if spectating(p) then return true end
	end
	return false
end

local function mem(bot)
	local m = T.memory[bot]
	if not m then
		m = { kills = 0, botKills = 0, dmg = 0, hits = 0, victims = setmetatable({}, { __mode = "k" }) }
		T.memory[bot] = m
	end
	return m
end
T.Mem = mem

-- A readable weapon name ("AKM", "Remington 870") from a weapon entity,
-- lower-cased the way people type it, or nil.
local function weaponName(ent)
	if not IsValid(ent) or not ent.IsWeapon or not ent:IsWeapon() then return nil end
	local name = ent.GetPrintName and ent:GetPrintName() or ent.PrintName
	if not isstring(name) or name == "" or string.sub(name, 1, 1) == "#" then return nil end
	name = string.Trim(string.gsub(name, "%b()", ""))
	if #name > 22 or name == "" then return nil end
	return string.lower(name)
end

local function killerWeapon(attacker, inflictor)
	if IsValid(inflictor) and inflictor ~= attacker then
		local n = weaponName(inflictor)
		if n then return n end
	end
	if IsValid(attacker) and attacker.GetActiveWeapon then return weaponName(attacker:GetActiveWeapon()) end
	return nil
end

local function isMeleeWeapon(ent)
	return IsValid(ent) and ent.ismelee == true
end

----------------------------------------------------------------------
-- Round memory
----------------------------------------------------------------------

hook.Add("PlayerSpawn", "zc_bots_spec_talk_spawn", function(ply)
	if not isOurBot(ply) then return end
	mem(ply).spawnAt = CurTime()
end)

hook.Add("EntityTakeDamage", "zc_bots_spec_talk_dmgtype", function(ent, dmg)
	if not isOurBot(ent) then return end
	local m = mem(ent)
	m.lastDmgType = dmg:GetDamageType()
	m.lastDmgAt = CurTime()
end)

hook.Add("HomigradDamage", "zc_bots_spec_talk_dealt", function(victim, dmg)
	local attacker = dmg and dmg.GetAttacker and dmg:GetAttacker() or nil
	if not isOurBot(attacker) or attacker == victim then return end
	if not IsValid(victim) or not victim:IsPlayer() then return end
	local m = mem(attacker)
	m.dmg = math.min(m.dmg + math.max(dmg.GetDamage and dmg:GetDamage() or 0, 0), 5000)
	m.hits = m.hits + 1
end)

hook.Add("PlayerDeath", "zc_bots_spec_talk_death", function(victim, inflictor, attacker)
	if not IsValid(victim) or not victim:IsPlayer() then return end
	local now = CurTime()
	local attackerPlayer = IsValid(attacker) and attacker:IsPlayer() and attacker ~= victim

	if attackerPlayer and isOurBot(attacker) then
		local am = mem(attacker)
		am.kills = am.kills + 1
		if victim:IsBot() then am.botKills = am.botKills + 1 end
		am.victims[victim] = now
		local allyOf = D.AllyOf and D.AllyOf(attacker)
		if allyOf and allyOf(victim) then am.teamkills = (am.teamkills or 0) + 1 end
	end

	if not isOurBot(victim) then return end
	local m = mem(victim)
	m.died = true
	m.diedAt = now
	m.life = m.spawnAt and (now - m.spawnAt) or nil
	m.killer = attackerPlayer and attacker or nil
	m.killerBot = attackerPlayer and attacker:IsBot() or false
	m.weapon = attackerPlayer and killerWeapon(attacker, inflictor) or nil
	m.melee = attackerPlayer and (isMeleeWeapon(inflictor) or (IsValid(attacker) and isMeleeWeapon(attacker:GetActiveWeapon()))) or false
	m.headshot = victim.LastHitGroup and victim:LastHitGroup() == HITGROUP_HEAD or false
	m.dist = attackerPlayer and victim:GetPos():Distance(attacker:GetPos()) or nil
	m.suicide = not attackerPlayer
	m.fall = m.suicide and m.lastDmgType ~= nil and bit.band(m.lastDmgType, DMG_FALL) ~= 0
		and now - (m.lastDmgAt or -math.huge) < 2
	local allyOf = attackerPlayer and D.AllyOf and D.AllyOf(victim)
	m.teamkilled = allyOf and allyOf(attacker) or false
	local wep = victim:GetActiveWeapon()
	-- homigrad_base: wep.reload is the reload's end time (nil when idle);
	-- tube loaders run their own "shootgunReload" netvar instead.
	m.reloading = IsValid(wep) and ((isnumber(wep.reload) and wep.reload > now)
		or (wep.GetNetVar and (tonumber(wep:GetNetVar("shootgunReload", 0)) or 0) > now)) or false
	m.healing = IsValid(wep) and wep.Heal ~= nil or false
end)

local function resetRound()
	T.epoch = T.epoch + 1
	T.active = nil
	T.roundCount = 0
	T.memory = setmetatable({}, { __mode = "k" })
	T.nextAt = CurTime() + math.Rand(20, 45)
end
hook.Add("ZB_PreRoundStart", "zc_bots_spec_talk_reset", resetRound)
hook.Add("ZB_EndRound", "zc_bots_spec_talk_end", function()
	T.epoch = T.epoch + 1
	T.active = nil
end)

----------------------------------------------------------------------
-- Casting: predicates the script bank's roles use. `ctx` is the cast built
-- so far ({ a = bot, b = bot, ... }); `m` the candidate's round memory,
-- `p` its personality.
----------------------------------------------------------------------

local P = {}
T.pred = P

function P.any() return true end
function P.died(_, m) return m.died == true end
function P.killedByPlayer(_, m) return m.died and IsValid(m.killer) end
function P.killedByOther(bot, m) return m.died and IsValid(m.killer) and m.killer ~= bot end
function P.headshot(_, m) return m.died and m.headshot and IsValid(m.killer) end
function P.reloading(_, m) return m.died and m.reloading and IsValid(m.killer) end
function P.healing(_, m) return m.died and m.healing and IsValid(m.killer) end
function P.teamkilled(_, m) return m.died and m.teamkilled and IsValid(m.killer) end
function P.melee(_, m) return m.died and m.melee end
function P.longshot(_, m) return m.died and (m.dist or 0) > 1800 end
function P.shortLife(_, m) return m.died and m.life ~= nil and m.life < 25 end
function P.longLife(_, m) return m.died and m.life ~= nil and m.life > 150 end
function P.whiffed(_, m) return m.died and m.kills == 0 and m.hits <= 1 end
function P.fragger(_, m) return m.kills >= 2 end
function P.fell(_, m) return m.died and m.fall end
function P.selfkill(_, m) return m.died and m.suicide and not m.fall end
function P.withWeapon(_, m) return m.died and m.weapon ~= nil and IsValid(m.killer) end

function P.temper(...)
	local set = {}
	for _, t in ipairs({ ... }) do set[t] = true end
	return function(_, _, p) return p ~= nil and set[p.temperament or "chill"] == true end
end
function P.archetype(...)
	local set = {}
	for _, t in ipairs({ ... }) do set[t] = true end
	return function(_, _, p) return p ~= nil and set[p.archetype] == true end
end
function P.tidyWriter(bot)
	local style = chat and chat.Style and chat.Style(bot)
	return style ~= nil and style.caps == "proper"
end
function P.all(...)
	local fns = { ... }
	return function(bot, m, p, ctx)
		for _, fn in ipairs(fns) do
			if not fn(bot, m, p, ctx) then return false end
		end
		return true
	end
end
-- This candidate killed the bot already cast as `role` this round.
function P.killerOf(role)
	return function(bot, _, _, ctx)
		local other = ctx[role]
		local om = other and T.memory[other]
		return om ~= nil and om.killer == bot
	end
end
-- This candidate was killed by the bot already cast as `role`.
function P.victimOf(role)
	return function(_, m, _, ctx)
		return ctx[role] ~= nil and m.killer == ctx[role]
	end
end

----------------------------------------------------------------------
-- Text: placeholders and temperament-keyed pools.
--
-- A turn's `say` is either a plain list or { any = {...}, crude = {...},
-- polite = {...}, ragey = {...}, gloomy = {...}, chill = {...} }. The
-- speaker's own temperament pool is preferred (70%) when present.
--
-- Placeholders: {a} {b} {c} (another cast member, written the way THIS
-- speaker writes names), {killer} {weapon} {kills} {life} (about the cast
-- member named by the turn's `about`, default "b"), {live} (a random living
-- player -- spectators watch them).
----------------------------------------------------------------------

local function pickPool(say, temper)
	if say[1] ~= nil then return say end
	local own = say[temper]
	if own and (not say.any or math.random() < 0.7) then return own end
	return say.any or own
end

local function tidyName(line)
	line = string.gsub(line, "%s%s+", " ")
	line = string.gsub(line, "%s+([,%.!%?'])", "%1")
	line = string.gsub(line, ",([%.!%?])", "%1")
	line = string.gsub(line, "^[,%s]+", "")
	line = string.gsub(line, "[,%s]+$", "")
	return string.Trim(line)
end

local function nameOf(speaker, target)
	if not IsValid(target) then return "" end
	if chat and chat.ShortName then return chat.ShortName(speaker, target, true) end
	return target:Nick()
end

local function livePlayer(conv)
	if IsValid(conv.live) and conv.live:Alive() then return conv.live end
	local alive = {}
	for _, p in ipairs(player.GetAll()) do
		if p:Alive() and p:Team() ~= TEAM_SPECTATOR then alive[#alive + 1] = p end
	end
	conv.live = alive[math.random(math.max(#alive, 1))]
	return conv.live
end

local function fill(conv, speaker, template, about)
	local subject = conv.cast[about or "b"]
	local sm = subject and T.memory[subject]
	local missing = false
	local line = string.gsub(template, "{(%w+)}", function(key)
		if key == "a" or key == "b" or key == "c" or key == "d" then
			local who = conv.cast[key]
			if not IsValid(who) then missing = true return "" end
			if who == speaker then return "i" end
			return nameOf(speaker, who)
		elseif key == "killer" then
			local k = sm and sm.killer
			if not IsValid(k) then missing = true return "" end
			return nameOf(speaker, k)
		elseif key == "weapon" then
			local w = sm and sm.weapon
			if not w then missing = true return "" end
			return w
		elseif key == "kills" then
			return tostring(sm and sm.kills or 0)
		elseif key == "life" then
			return tostring(math.max(1, math.floor(sm and sm.life or 0)))
		elseif key == "live" then
			local p = livePlayer(conv)
			if not IsValid(p) then missing = true return "" end
			return nameOf(speaker, p)
		end
		return "{" .. key .. "}"
	end)
	if missing then return nil end
	return tidyName(line)
end

local function chooseLine(conv, speaker, turn)
	local p = D.GetPersonality and D.GetPersonality(speaker)
	local pool = pickPool(turn.say, p and p.temperament or "chill")
	if not pool or #pool == 0 then return nil end
	local order = {}
	for i = 1, #pool do order[i] = i end
	table.Shuffle(order)
	local fallback
	for _, i in ipairs(order) do
		local line = fill(conv, speaker, pool[i], turn.about)
		if line and line ~= "" then
			if not (chat and chat.RecentGlobal and chat.RecentGlobal(line)) then return line end
			fallback = fallback or line
		end
	end
	return fallback
end

----------------------------------------------------------------------
-- Conversation runtime
----------------------------------------------------------------------

local function participants(conv)
	local out = {}
	for _, bot in pairs(conv.cast) do out[#out + 1] = bot end
	return out
end

local function convValid(conv)
	if T.active ~= conv or conv.epoch ~= T.epoch then return false end
	if not cv_spec:GetBool() or not (cv_chatter and cv_chatter:GetBool()) or not D.Enabled() then return false end
	if not liveRound() or not humanSpectatorPresent() then return false end
	for _, bot in ipairs(participants(conv)) do
		if not isOurBot(bot) or not spectating(bot) then return false end
	end
	return true
end

local function finish(conv)
	if T.active == conv then
		T.active = nil
		T.nextAt = CurTime() + math.Rand(GAP_MIN, GAP_MAX)
	end
end

local advance

local function deliver(conv, speaker, line, attempt)
	if not convValid(conv) then return finish(conv) end
	local p = D.GetPersonality and D.GetPersonality(speaker)
	-- The occasional fat-fingered word, same helper as sv_chatter.lua (no
	-- follow-up correction here; conversations move on).
	if p and D.chatTyping and D.chatTyping.Typo and math.random() < (p.typoChance or 0) * 2.5 then
		line = D.chatTyping.Typo(line)
	end
	local queued = D.chatTyping.SendWithTyping(speaker, line, function(bot, text)
		if not convValid(conv) then return finish(conv) end
		D.chatter.Say(bot, text, true)
		if chat and chat.RememberGlobal then chat.RememberGlobal(text) end
		if D.chatterRuntime then D.chatterRuntime.lastAt = CurTime() end
		conv.progressAt = CurTime()
		advance(conv)
	end, false)
	if not queued then
		if (attempt or 1) >= 3 then return finish(conv) end
		timer.Simple(math.Rand(1.2, 2.4), function() deliver(conv, speaker, line, (attempt or 1) + 1) end)
	end
end

advance = function(conv)
	conv.turn = conv.turn + 1
	local turn = conv.script.turns[conv.turn]
	if not turn then return finish(conv) end
	local speaker = conv.cast[turn.who]
	if not IsValid(speaker) or (turn.chance and math.random() >= turn.chance) then
		return advance(conv)
	end
	local line = chooseLine(conv, speaker, turn)
	if not line then return advance(conv) end
	-- Read the previous line, think, then start typing. A double text from
	-- the same speaker follows faster.
	local previous = conv.script.turns[conv.turn - 1]
	local sameSpeaker = previous and previous.who == turn.who
	local delay = sameSpeaker and math.Rand(0.4, 1.4) or math.Rand(0.9, 3.4)
	if turn.pause then delay = delay + turn.pause end
	timer.Simple(delay, function() deliver(conv, speaker, line) end)
end

----------------------------------------------------------------------
-- Script selection and casting
----------------------------------------------------------------------

local function deadBots()
	local out = {}
	for bot in pairs(D.brains) do
		if isOurBot(bot) and spectating(bot) and not (bot.zcTypingUntil and bot.zcTypingUntil > CurTime()) then
			out[#out + 1] = bot
		end
	end
	return out
end

local ROLE_ORDER = { "a", "b", "c", "d" }

-- Returns a cast table or nil. Required roles must be filled; optional ones
-- (script.optional[role]) are filled if anyone fits. Backtracking: a later
-- role can depend on an earlier one ("b was killed by a"), so an early pick
-- that leaves a later required role empty is undone and the next candidate
-- tried. Candidates are shuffled so the cast still varies; the predicate
-- budget bounds the worst case on a full server.
local CAST_BUDGET = 3000

local function castScript(script, pool)
	local roles = {}
	for _, role in ipairs(ROLE_ORDER) do
		if script.cast[role] then roles[#roles + 1] = role end
	end
	local cast, used = {}, {}
	local budget = CAST_BUDGET

	local function fillFrom(index)
		local role = roles[index]
		if not role then return true end
		local want = script.cast[role]
		local order = {}
		for _, bot in ipairs(pool) do
			if not used[bot] then order[#order + 1] = bot end
		end
		table.Shuffle(order)
		for _, bot in ipairs(order) do
			budget = budget - 1
			if budget <= 0 then return false end
			if want(bot, mem(bot), D.GetPersonality and D.GetPersonality(bot), cast) then
				cast[role], used[bot] = bot, true
				if fillFrom(index + 1) then return true end
				cast[role], used[bot] = nil, nil
			end
		end
		if script.optional and script.optional[role] then return fillFrom(index + 1) end
		return false
	end

	if fillFrom(1) then return cast end
	return nil
end

local function scriptFresh(script, now)
	local last = T.recentScripts[script.id]
	return not last or now - last > SCRIPT_REPEAT_TTL
end

local function startConversation(now)
	local bank = D.specTalkScripts
	if not istable(bank) then return false end
	local pool = deadBots()
	if #pool < 2 then return false end
	-- Let the most recent death's own reaction land before a conversation.
	for _, bot in ipairs(pool) do
		local m = T.memory[bot]
		if m and m.diedAt and now - m.diedAt < 6 then return false end
	end

	local options, total = {}, 0
	for _, script in ipairs(bank) do
		if scriptFresh(script, now) and (not script.when or script.when()) then
			local cast = castScript(script, pool)
			if cast then
				local w = script.weight or 1
				options[#options + 1] = { script = script, cast = cast, w = w }
				total = total + w
			end
		end
	end
	if #options == 0 then return false end
	local pick = math.random() * total
	local chosen = options[#options]
	for _, option in ipairs(options) do
		pick = pick - option.w
		if pick <= 0 then chosen = option break end
	end

	local conv = { script = chosen.script, cast = chosen.cast, turn = 0, epoch = T.epoch, progressAt = now, startedAt = now }
	T.active = conv
	T.recentScripts[chosen.script.id] = now
	T.roundCount = T.roundCount + 1
	T.stats = T.stats or { started = 0 }
	T.stats.started = T.stats.started + 1
	advance(conv)
	return true
end

----------------------------------------------------------------------
-- Answering a human's gameplay question (called by sv_chat_listen.lua).
----------------------------------------------------------------------

function T.MatchQuestion(lower)
	for _, topic in ipairs(T.questionTopics or {}) do
		local all = true
		for _, group in ipairs(topic.all) do
			local any = false
			for _, word in ipairs(group) do
				if string.find(lower, word, 1, true) then any = true break end
			end
			if not any then all = false break end
		end
		if all and T.topicAnswers and T.topicAnswers[topic.id] then return topic.id end
	end
	return nil
end

function T.AnswerLine(topic, bot)
	local answer = T.topicAnswers and T.topicAnswers[topic]
	if not answer then return nil end
	local p = D.GetPersonality and D.GetPersonality(bot)
	local pool = pickPool(answer, p and p.temperament or "chill")
	if not pool or #pool == 0 then return nil end
	return pool[math.random(#pool)]
end

-- True while a conversation runs or has only just ended; sv_social.lua's
-- one-line spectator ambient stays out of the way meanwhile.
function T.Busy()
	return T.active ~= nil
end

hg.botdriver.Every("spec_talk", 5, function()
	local now = CurTime()
	local conv = T.active
	if conv then
		if conv.epoch ~= T.epoch or now - (conv.progressAt or now) > STALL_TIMEOUT then finish(conv) end
		return
	end
	if not cv_spec:GetBool() or not (cv_chatter and cv_chatter:GetBool()) or not D.Enabled() then return end
	if not liveRound() or now < T.nextAt or T.roundCount >= MAX_PER_ROUND then return end
	if not humanSpectatorPresent() then return end
	if math.random() > 0.4 then return end
	startConversation(now)
end)

-- Admin: force a conversation now (superadmin/console), for listening in.
concommand.Add("zc_bots_spec_talk_now", function(ply)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	T.active = nil
	local ok = startConversation(CurTime())
	local msg = ok and ("[zc_bots] spectator conversation started: " .. T.active.script.id)
		or "[zc_bots] no conversation could be cast (need 2+ dead bots and a fitting script)"
	if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end
end)
