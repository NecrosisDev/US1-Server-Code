-- Body-language emotes (2026-09-26 presentation-parity pass): the
-- crouch-spam ("teabag") and lean-wiggle dances every GMod lobby is full
-- of, done AT someone -- over a body, back at a human who is doing it at the
-- bot, or as a pre-round "hey". Plus answering a human's radial hand
-- gesture (thumbs up / point / finger) with one of the bot's own.
--
-- Inputs only. A dance is button presses in StartCommand (IN_DUCK, and the
-- US1 lean keys IN_ALT1 = right / IN_ALT2 = left -- weapons/homigrad_base/
-- sh_anim.lua, the server reads KeyDown and networks PlayerLean), exactly
-- what a human's keyboard produces, so the animation, lean bones and
-- stamina cost are all the gamemode's own.
--
-- Safety: an emote owns the tick only from the REFLEX band's tail, and only
-- while no enemy is acquired, nothing hurt the bot in the last 2 s and the
-- bot is not downed. The first sighting of a threat cancels it -- a dance
-- can never cost a bot a fight it would otherwise have taken. Walking to a
-- body happens only when nothing hostile has been seen for a while.
--
-- Mode rules: no dancing on a kill in Homicide-family rounds (it would
-- point at the killer), and never on a teamkill.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}
local D = hg.botdriver
D.emote = D.emote or {}
local E = D.emote

D.DeclareBrainState("emote", { fields = { "emote" } })
D.DeclareBrainState("emote_cooldown", { perLife = false, fields = { "emoteNextAt" } })

local cv = ConVarExists("zc_bots_emotes") and GetConVar("zc_bots_emotes")
	or CreateConVar("zc_bots_emotes", "1", FCVAR_ARCHIVE,
		"Bots crouch/lean-dance at people, mirror humans doing it, and answer hand gestures", 0, 1)

local BOT_COOLDOWN = 22           -- seconds between one bot's emotes
local SUBJECT_COOLDOWN = 12       -- one crowd at a time around the same person/body
local MIRROR_RANGE = 380
local GESTURE_SEEN_RANGE = 700
local APPROACH_MAX = 320          -- walk to a body only this close
local APPROACH_ARRIVE = 56

-- How likely each temperament is to do the thing at all. Crude players
-- teabag; polite ones wave; gloomy ones mostly do not bother.
local KILL_DANCE = { crude = .38, ragey = .26, chill = .12, gloomy = .04, polite = .02 }
local MIRROR = { crude = .7, chill = .55, ragey = .4, polite = .45, gloomy = .18 }
local GREET = { crude = .3, chill = .3, ragey = .15, polite = .35, gloomy = .08 }

E.subjectAt = E.subjectAt or setmetatable({}, { __mode = "k" })

local function temperOf(bot)
	return D.Temperament and D.Temperament(bot) or "chill"
end

local function usable(bot)
	return cv:GetBool() and D.Enabled() and IsValid(bot) and bot:IsBot() and bot.zcBot
		and not bot.zcBotBenched and bot:Alive() and not D.IsDowned(bot)
end

local function homicideRound()
	return D.homicide and D.homicide.Active and D.homicide.Active() or false
end

-- kind: "crouch" | "lean" | "both". subject: an entity (looked at, followed
-- by the eyes) or a position (a body). approach: walk up to it first.
function E.Start(bot, kind, subject, duration, opts)
	if not usable(bot) then return false end
	local brain = D.brains[bot]
	if not brain then return false end
	local now = CurTime()
	if brain.emote and now < brain.emote.untilT then return false end
	if now < (brain.emoteNextAt or 0) then return false end
	if brain.actionPolicy or brain.medicPatient or brain.grenadeState then return false end
	if now - (brain.damageAt or -math.huge) < 3 then return false end
	local key = isentity(subject) and subject or nil
	if key and now < (E.subjectAt[key] or 0) then return false end

	opts = opts or {}
	local startDelay = opts.delay or math.Rand(0.15, 0.55)
	brain.emote = {
		kind = kind,
		subject = subject,
		approach = opts.approach or false,
		arrived = not opts.approach,
		startT = now + startDelay,
		untilT = now + startDelay + (duration or math.Rand(1.6, 3.2)) + (opts.approach and 4 or 0),
		length = duration or math.Rand(1.6, 3.2),
		-- Crouch spam runs ~3-5 presses a second; a lean wiggle swings side to
		-- side about twice a second. Each bot keeps its own rhythm.
		half = kind == "lean" and math.Rand(0.28, 0.45) or math.Rand(0.11, 0.2),
		phaseAt = 0,
		on = false,
		side = math.random() < 0.5 and 1 or -1,
	}
	brain.emoteNextAt = now + BOT_COOLDOWN * math.Rand(0.8, 1.4)
	if key then E.subjectAt[key] = now + SUBJECT_COOLDOWN end
	D.stats = D.stats or {}
	D.stats.emotes = (D.stats.emotes or 0) + 1
	return true
end

function E.Cancel(brain)
	brain.emote = nil
end

local function subjectPos(subject)
	if isvector(subject) then return subject end
	if not IsValid(subject) then return nil end
	if subject:IsPlayer() then
		if IsValid(subject.FakeRagdoll) then return subject.FakeRagdoll:WorldSpaceCenter() end
		return subject:EyePos()
	end
	return subject:WorldSpaceCenter()
end

-- Per-tick overlay, called from sv_control.lua's StartCommand just before
-- the buttons are committed. Pure number/bit work on the brain.
function E.Buttons(brain, now, buttons)
	local em = brain.emote
	if not em then return buttons end
	if now >= em.untilT then
		brain.emote = nil
		return buttons
	end
	if not em.arrived or now < em.startT then return buttons end
	if now >= em.phaseAt then
		em.on = not em.on
		-- Irregular rhythm: a human hammering a key never keeps time.
		em.phaseAt = now + em.half * math.Rand(0.7, 1.35)
		if em.on then em.side = -em.side end
	end
	local kind = em.kind
	if kind == "both" then kind = (math.floor(now / 1.2) % 2 == 0) and "crouch" or "lean" end
	if kind == "crouch" then
		if em.on then buttons = bit.bor(buttons, IN_DUCK) end
	else
		buttons = bit.bor(buttons, em.side > 0 and IN_ALT1 or IN_ALT2)
	end
	return buttons
end

hg.botdriver.RegisterBehavior({
	name = "reflex.emote",
	band = "REFLEX",
	order = 95,
	stateLabel = "emote",
	finalize = false,
	CanRun = function(ctx)
		local brain = ctx.brain
		local em = brain.emote
		if not em then return false end
		local now = ctx.now
		if now >= em.untilT or ctx.downed or now - (brain.damageAt or -math.huge) < 2
			or IsValid(ctx:AcquireTarget()) then
			brain.emote = nil
			return false
		end
		return true
	end,
	Run = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		local em = brain.emote
		local pos = subjectPos(em.subject)
		if not pos then
			brain.emote = nil
			return false
		end
		if not em.arrived then
			local flat = Vector(pos.x, pos.y, bot:GetPos().z)
			if bot:GetPos():DistToSqr(flat) <= APPROACH_ARRIVE * APPROACH_ARRIVE then
				em.arrived = true
				em.startT = now + math.Rand(0.1, 0.35)
				em.untilT = em.startT + em.length
			else
				hg.botdriver.lib.PathTo(bot, brain, flat, now, 1)
				hg.botdriver.lib.LookAt(bot, brain, pos, "emote", false)
				return true, { path = true }
			end
		end
		brain.path = nil
		brain.forward, brain.side = 0, 0
		hg.botdriver.lib.LookAt(bot, brain, pos, "emote", false)
		return true
	end,
})

----------------------------------------------------------------------
-- Trigger 1: a kill. Low-sportsmanship and crude/ragey bots dance on the
-- body when the area is quiet, or answer with a hand gesture instead.
----------------------------------------------------------------------

hook.Add("PlayerDeath", "zc_bots_emote_kill", function(victim, _inflictor, attacker)
	if not IsValid(victim) or not victim:IsPlayer() or not usable(attacker) or attacker == victim then return end
	if homicideRound() then return end
	local allyOf = D.AllyOf(attacker)
	if allyOf(victim) then return end
	local p = D.GetPersonality(attacker)
	local chance = (KILL_DANCE[p.temperament or "chill"] or .1) * (1.3 - (p.sportsmanship or .5))
	-- A player who keeps killing this bot gets it back with interest.
	local rec = D.relations and D.relations.Get and D.relations.Get(attacker, victim)
	if rec and (tonumber(rec.k) or 0) >= 2 then chance = chance * 2 end
	if math.random() >= chance then return end
	local deathPos = victim:GetPos()
	timer.Simple(math.Rand(0.8, 2.2), function()
		if not usable(attacker) then return end
		local brain = D.brains[attacker]
		if not brain or IsValid(brain.target) then return end
		local body = IsValid(victim) and (IsValid(victim.FakeRagdoll) and victim.FakeRagdoll
			or (victim.GetRagdollEntity and victim:GetRagdollEntity())) or nil
		local pos = IsValid(body) and body:GetPos() or deathPos
		local dist = attacker:GetPos():Distance(pos)
		if dist > 700 then return end
		local quiet = CurTime() - (brain.lastSeenTime or -math.huge) > 2.5 and attacker:Health() > 50
		local kind = math.random() < 0.75 and "crouch" or "both"
		E.Start(attacker, kind, pos, math.Rand(1.8, 3.4), { approach = quiet and dist > APPROACH_ARRIVE and dist < APPROACH_MAX })
	end)
end)

----------------------------------------------------------------------
-- Trigger 2: a human crouch-spamming or lean-wiggling near a bot that can
-- see them. The bot answers in kind (or, for a rude one, flips them off).
-- KeyPress fires server-side for real clients' inputs only.
----------------------------------------------------------------------

E.presses = E.presses or setmetatable({}, { __mode = "k" })

local function recordPress(ply, kind, now)
	local store = E.presses[ply]
	if not store then
		store = { crouch = {}, lean = {}, answeredAt = -math.huge }
		E.presses[ply] = store
	end
	local list = store[kind]
	list[#list + 1] = now
	while #list > 0 and now - list[1] > 2.2 do table.remove(list, 1) end
	return store, #list
end

local function answerDance(human, kind)
	local now = CurTime()
	local enemyRound = zb and zb.ROUND_STATE == 1
	local lib = D.lib
	local best, bestDist
	for bot, brain in pairs(D.brains) do
		if usable(bot) and not IsValid(brain.target) then
			local hostile = enemyRound and D.EnemyOf(bot)(human)
			local d = bot:GetPos():Distance(human:GetPos())
			if not hostile and d < MIRROR_RANGE and (not bestDist or d < bestDist)
				and lib.VisualContact and lib.VisualContact(bot, human, brain, true, now) then
				best, bestDist = bot, d
			end
		end
	end
	if not best then return end
	local temper = temperOf(best)
	if math.random() >= (MIRROR[temper] or .4) then return end
	local brain = D.brains[best]
	-- A rude bot sometimes answers a teabag with the finger instead.
	if (temper == "crude" or temper == "ragey") and kind == "crouch" and math.random() < 0.3
		and D.radial and D.radial.OnGesture then
		D.lib.LookAt(best, brain, human:EyePos(), "emote", false)
		timer.Simple(math.Rand(0.4, 1.1), function()
			if usable(best) then D.radial.OnGesture(best, D.brains[best], "fuckyou", 1) end
		end)
		return
	end
	E.Start(best, kind, human, math.Rand(1.4, 2.8), { delay = math.Rand(0.35, 1.1) })
end

hook.Add("KeyPress", "zc_bots_emote_mirror", function(ply, key)
	if not cv:GetBool() or not IsValid(ply) or ply:IsBot() or not ply:Alive() then return end
	local kind
	if key == IN_DUCK then kind = "crouch"
	elseif key == IN_ALT1 or key == IN_ALT2 then kind = "lean"
	else return end
	local now = CurTime()
	local store, count = recordPress(ply, kind, now)
	local needed = kind == "crouch" and 4 or 3
	if count < needed or now - store.answeredAt < 15 then return end
	store.answeredAt = now
	store[kind] = {}
	answerDance(ply, kind)
end)

----------------------------------------------------------------------
-- Trigger 3: pre-round / intermission "hey". During downtime a bot that
-- spots a human close by sometimes wiggles or bobs at them once.
----------------------------------------------------------------------

hg.botdriver.Every("emote_greet", 3, function()
	if not cv:GetBool() or not D.Enabled() or D.RoundAllowsCombat() then return end
	local humans = player.GetHumans()
	if #humans == 0 then return end
	local now = CurTime()
	for bot, brain in RandomPairs(D.brains) do
		if usable(bot) and not brain.emote and now >= (brain.emoteNextAt or 0) then
			for _, human in ipairs(humans) do
				if human:Alive() and bot:GetPos():DistToSqr(human:GetPos()) < 300 * 300
					and D.lib.VisualContact and D.lib.VisualContact(bot, human, brain, false, now) then
					if math.random() < (GREET[temperOf(bot)] or .2) * 0.5 then
						E.Start(bot, math.random() < 0.6 and "lean" or "crouch", human, math.Rand(1.1, 2.2))
						return
					end
					break
				end
			end
		end
	end
end)

----------------------------------------------------------------------
-- Trigger 4: a human's radial hand gesture aimed at a bot. hg_hand_gesture
-- (homigrad/zmanip/sv_zmanip.lua) ends in the global hg.RunZManipAnim with
-- the SEQUENCE name; wrap it once (hotload-safe) to see gestures.
----------------------------------------------------------------------

local GESTURE_OF_SEQUENCE = { thump_up = "thumb_up", point = "point", fuckyou = "fuckyou" }

local function answerGesture(human, gesture)
	if not cv:GetBool() or not D.Enabled() then return end
	local now = CurTime()
	local aim = human:GetAimVector()
	local lib = D.lib
	for bot, brain in pairs(D.brains) do
		if usable(bot) and not IsValid(brain.target) then
			local delta = bot:EyePos() - human:EyePos()
			local d = delta:Length()
			if d > 1 and d < GESTURE_SEEN_RANGE and aim:Dot(delta / d) > 0.9
				and lib.VisualContact and lib.VisualContact(bot, human, brain, true, now) then
				local temper = temperOf(bot)
				local reply
				if gesture == "thumb_up" then
					reply = (temper ~= "gloomy" or math.random() < 0.3) and "thumb_up" or nil
				elseif gesture == "fuckyou" then
					if temper == "crude" or temper == "ragey" then reply = "fuckyou"
					elseif temper == "polite" then reply = math.random() < 0.5 and "thumb_up" or nil
					elseif math.random() < 0.4 then reply = "fuckyou" end
				elseif gesture == "point" then
					reply = math.random() < 0.35 and "point" or nil
				end
				lib.LookAt(bot, brain, human:EyePos(), "emote", false)
				if reply and D.radial and D.radial.OnGesture then
					timer.Simple(math.Rand(0.6, 1.6), function()
						if usable(bot) and D.brains[bot] then D.radial.OnGesture(bot, D.brains[bot], reply, 1) end
					end)
				elseif not reply and gesture ~= "point" and math.random() < 0.4 then
					E.Start(bot, "crouch", human, math.Rand(1, 1.8), { delay = math.Rand(0.5, 1.2) })
				end
				return
			end
		end
	end
end

if isfunction(hg.RunZManipAnim) then
	D.origRunZManipAnim = D.origRunZManipAnim or hg.RunZManipAnim
	local original = D.origRunZManipAnim
	hg.RunZManipAnim = function(ply, anim, ...)
		local gesture = GESTURE_OF_SEQUENCE[anim]
		if gesture and IsValid(ply) and ply:IsPlayer() and not ply:IsBot() then
			local ok, err = pcall(answerGesture, ply, gesture)
			if not ok and D.log and D.log.error then D.log.error("emote", tostring(err)) end
		end
		return original(ply, anim, ...)
	end
end
