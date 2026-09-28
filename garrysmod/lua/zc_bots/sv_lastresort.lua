-- Last resort (2026-09-26 owner ask): what a human does when the round is
-- over for them but the body has not caught up yet.
--
--   Give up   Knocked out (org.otrub) for 20-40 s -- quicker for gloomy and
--             ragey bots, longer for patient/polite ones -- the bot "presses
--             K": the same kill the giveup_button addon performs for a human
--             (addons/giveup_button/.../sv_giveup.lua), through the same
--             justice terminal ("giveup"). Held while consciousness is coming
--             back (the ko_reaper's WAKE_THRESHOLD), while an ally medic has
--             claimed the bot, and for a while after a human hurt it (let
--             them walk up and finish it for the kill).
--
--   End it    Conscious, bleeding out with nothing on them that treats it,
--             nobody hostile in sight, no ally medic coming, and NO human has
--             damaged the bot in the last 60 s (a human must never lose a
--             kill to this): the bot draws a gun that allows it, types the
--             `suicide` command (hg/sh_utility.lua toggles ply.suiciding;
--             the weapon swings to the head over ~1 s), hesitates, then
--             fires -- the homigrad_base bullet sources from the head once
--             the swing has finished (sh_bullet.lua willsuicidereal). Any
--             hostile in sight, fresh damage or a found med aborts it and
--             lowers the gun again.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}
local D = hg.botdriver
D.lastResort = D.lastResort or {}
local LR = D.lastResort

D.DeclareBrainState("last_resort", { perLife = true, fields = {
	"koSince", "koGiveUpAfter", "lastHumanHitAt", "lastHitAt", "endIt", "endItRolled", "endItWilling",
	"endItCooldownUntil", "bloodSampleAt", "bloodSample", "bloodRate",
} })

local cv = ConVarExists("zc_bots_lastresort") and GetConVar("zc_bots_lastresort")
	or CreateConVar("zc_bots_lastresort", "1", FCVAR_ARCHIVE,
		"Bots give up after lying unconscious a while, and end it with a gun when bleeding out with no way to treat it", 0, 1)

local HUMAN_HIT_WINDOW = 60      -- no suicide within this long of human damage
local GIVEUP_HUMAN_HOLD = 15     -- a KO'd bot waits this long after human damage
local WAKE_THRESHOLD = 0.75      -- ko_reaper: "close to getting up", spared
local ABORT_HIT_WINDOW = 4       -- anyone's damage this recent: still a fight
local BLOOD_DYING = 3700         -- below this and still losing blood: dying
local BLOOD_SAMPLE_EVERY = 2

-- Seconds unconscious before pressing K, per temperament.
local GIVEUP_RANGE = {
	gloomy = { 18, 26 }, ragey = { 20, 28 }, crude = { 22, 32 },
	chill = { 26, 38 }, polite = { 28, 40 },
}
-- Chance a bot that CAN end it actually does (per life).
local WILLING = { gloomy = 1.0, ragey = 0.9, crude = 0.85, chill = 0.8, polite = 0.7 }

local LINES = {
	gloomy = { "welp", "cya", "yeah no", "not waiting for that" },
	ragey = { "fuck this", "fuck it", "whatever" },
	crude = { "fuck it", "bye", "lmao bye" },
	chill = { "gg", "im out", "welp" },
	polite = { "no meds, sorry guys", "gg all", "out of bandages, bye" },
}

local function temperament(bot)
	return (D.Temperament and D.Temperament(bot)) or "chill"
end

local function isHumanActor(ent)
	return IsValid(ent) and ent:IsPlayer() and not ent:IsBot()
end

local function roundLive()
	return zb and zb.ROUND_STATE == 1
end

-- An ally bot medic has this bot as its patient (behaviors/sv_medic.lua).
local function medicComing(bot)
	for other, brain in pairs(D.brains or {}) do
		if other ~= bot and IsValid(other) and other:Alive() and brain.medicPatient == bot then return true end
	end
	return false
end

hook.Add("HomigradDamage", "zc_bots_lastresort_hits", function(ply, dmg)
	if not IsValid(ply) or not ply:IsPlayer() or not ply:IsBot() or not ply.zcBot then return end
	local brain = D.brains and D.brains[ply]
	if not brain then return end
	local now = CurTime()
	brain.lastHitAt = now
	local attacker = dmg and dmg.GetAttacker and dmg:GetAttacker() or nil
	if isHumanActor(attacker) and attacker ~= ply then brain.lastHumanHitAt = now end
end)

----------------------------------------------------------------------
-- Give up while unconscious
----------------------------------------------------------------------

local function rollGiveUp(bot, brain)
	local range = GIVEUP_RANGE[temperament(bot)] or GIVEUP_RANGE.chill
	local patience = math.Clamp((brain.personality and brain.personality.patience) or 1, 0.8, 1.25)
	return math.Clamp(math.Rand(range[1], range[2]) * patience, 18, 42)
end

local function giveUp(bot)
	print("[GiveUp] " .. bot:Nick() .. " gave up while unconscious.")
	local justice = ZCJusticeV3Integration
	if justice and justice.enabled and justice.WithTerminal then
		justice:WithTerminal(bot, "giveup", function() bot:Kill() end)
	else
		bot:Kill()
	end
	D.stats = D.stats or {}
	D.stats.gaveUp = (D.stats.gaveUp or 0) + 1
end

D.Every("lastresort_giveup", 1, function()
	if not D.Enabled() or not cv:GetBool() then return end
	local live = roundLive()
	local now = CurTime()
	for bot, brain in pairs(D.brains or {}) do
		if IsValid(bot) and bot.zcBot and bot:Alive() and not bot.zcBotBenched then
			local org = bot.organism
			if live and org and org.otrub == true then
				if not brain.koSince then
					brain.koSince = now
					brain.koGiveUpAfter = rollGiveUp(bot, brain)
				end
				local waking = (tonumber(org.consciousness) or 0) >= WAKE_THRESHOLD
				local held = waking or medicComing(bot)
					or now - (brain.lastHumanHitAt or -math.huge) < GIVEUP_HUMAN_HOLD
				if not held and now - brain.koSince >= brain.koGiveUpAfter then
					brain.koSince = nil
					giveUp(bot)
				end
			else
				brain.koSince = nil
			end
		end
	end
end)

----------------------------------------------------------------------
-- End it: bleeding out with no way to treat it
----------------------------------------------------------------------

-- A gun this bot can put to its head right now (hg.CanSuicide's test).
local function suicideGun(bot)
	local best, bestClip
	for _, wep in ipairs(bot:GetWeapons()) do
		if IsValid(wep) and wep.CanSuicide and wep.ishgweapon and not wep.ismelee and wep.Clip1 then
			local clip = wep:Clip1() or 0
			local reserve = D.EffectiveReserve and D.EffectiveReserve(bot, wep) or 0
			if clip > 0 or reserve > 0 then
				-- Prefer a loaded pistol: what a person would actually use.
				local score = (clip > 0 and 2 or 0) + ((wep.IsPistolHoldType and wep:IsPistolHoldType()) and 1 or 0)
				if not bestClip or score > bestClip then best, bestClip = wep, score end
			end
		end
	end
	return best
end

-- Blood trend, sampled every couple of seconds (organism blood only drops
-- in steps, so a per-decision delta is noise).
local function sampleBlood(brain, org, now)
	local blood = tonumber(org.blood)
	if not blood then return nil end
	if not brain.bloodSampleAt or now - brain.bloodSampleAt >= BLOOD_SAMPLE_EVERY then
		if brain.bloodSample and brain.bloodSampleAt then
			brain.bloodRate = (brain.bloodSample - blood) / math.max(now - brain.bloodSampleAt, 0.1)
		end
		brain.bloodSample, brain.bloodSampleAt = blood, now
	end
	return blood
end

local function bleedingOut(bot, brain, now)
	local org = bot.organism
	if not org then return false end
	local blood = sampleBlood(brain, org, now)
	if not blood or blood >= BLOOD_DYING then return false end
	local survival = brain.survival
	local bleed = survival and survival.body and tonumber(survival.body.bleed) or tonumber(org.bleed) or 0
	local arterial = istable(org.arterialwounds) and #org.arterialwounds > 0
	return (bleed > 0 or arterial) and (brain.bloodRate or 0) > 0
end

local function canEndIt(ctx)
	local bot, brain, now = ctx.bot, ctx.brain, ctx.now
	if ctx.downed or not roundLive() then return false end
	if now < (brain.endItCooldownUntil or 0) then return false end
	if now - (brain.lastHumanHitAt or -math.huge) < HUMAN_HIT_WINDOW then return false end
	if now - (brain.lastHitAt or -math.huge) < ABORT_HIT_WINDOW then return false end
	local survival = brain.survival
	if survival and survival.threats and survival.threats.visibleHostile then return false end
	if D.BestCarriedMedical and D.BestCarriedMedical(bot) then return false end
	if not bleedingOut(bot, brain, now) then return false end
	if medicComing(bot) then return false end
	return true
end

local function lowerGun(bot)
	if bot.suiciding and concommand and isfunction(concommand.Run) then
		concommand.Run(bot, "suicide", {}, "")
	end
end

local function abort(brain, bot, cooldown)
	brain.endIt = nil
	brain.endItCooldownUntil = CurTime() + (cooldown or 8)
	lowerGun(bot)
end

function LR.Describe(brain)
	local e = brain and brain.endIt
	if e then return "end-it:" .. e.phase end
	if brain and brain.koSince then
		return string.format("ko %.0f/%.0fs", CurTime() - brain.koSince, brain.koGiveUpAfter or 0)
	end
	return nil
end

D.RegisterBehavior({
	name = "reflex.last-resort",
	band = "REFLEX",
	order = 2,
	stateLabel = "last_resort",
	finalize = false,
	CanRun = function(ctx)
		if not cv:GetBool() then return false end
		local bot, brain = ctx.bot, ctx.brain
		if brain.endIt then
			if canEndIt(ctx) and IsValid(brain.endIt.gun) and brain.endIt.gun:GetOwner() == bot then return true end
			abort(brain, bot, 10)
			return false
		end
		if not canEndIt(ctx) then return false end
		if not brain.endItRolled then
			brain.endItRolled = true
			brain.endItWilling = math.random() < (WILLING[temperament(bot)] or 0.8)
		end
		if not brain.endItWilling then return false end
		local gun = suicideGun(bot)
		if not gun then return false end
		local p = brain.personality or {}
		local t = temperament(bot)
		-- Hesitation once the gun is up: gloomy barely, polite/patient longest.
		local hesitate = (t == "gloomy" and math.Rand(1.2, 2.2)) or (t == "ragey" and math.Rand(1.2, 2.6))
			or math.Rand(1.8, 4.2) * math.Clamp(p.patience or 1, 0.8, 1.3)
		brain.endIt = { phase = "draw", gun = gun, phaseAt = ctx.now, hesitate = hesitate, said = false }
		D.stats = D.stats or {}
		D.stats.endItStarted = (D.stats.endItStarted or 0) + 1
		return true
	end,
	Run = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		local e = brain.endIt
		local gun = e.gun
		brain.forward, brain.side = 0, 0
		brain.path = nil
		brain.buttons = 0

		if e.phase == "draw" then
			if bot:GetActiveWeapon() ~= gun then
				bot:SelectWeapon(gun:GetClass())
				if now - e.phaseAt > 3 then abort(brain, bot, 20) end
				return true
			end
			if (gun:Clip1() or 0) <= 0 then
				brain.buttons = IN_RELOAD
				if now - e.phaseAt > 8 then abort(brain, bot, 20) end
				return true
			end
			if isnumber(gun.reload) and gun.reload > now then return true end
			e.phase, e.phaseAt = "raise", now
		end

		if e.phase == "raise" then
			if not bot.suiciding and concommand and isfunction(concommand.Run) then
				concommand.Run(bot, "suicide", {}, "")
			end
			if not e.said and math.random() < 0.35 and D.chatter and D.chatter.Say then
				local pool = LINES[temperament(bot)] or LINES.chill
				D.chatter.Say(bot, pool[math.random(#pool)])
			end
			e.said = true
			if not bot.suiciding then
				-- The weapon refused (hg.CanSuicide false: reloading, a
				-- suppressed rifle, a class that cannot): give it up.
				if now - e.phaseAt > 1.5 then abort(brain, bot, 30) end
				return true
			end
			e.phase, e.phaseAt = "hold", now
		end

		if e.phase == "hold" then
			if not bot.suiciding then e.phase, e.phaseAt = "raise", now return true end
			-- The swing to the head takes ~1 s; fire only after it and the
			-- hesitation have both passed, so the shot sources from the head.
			if now - e.phaseAt >= math.max(e.hesitate, 1.3) then
				e.phase, e.phaseAt = "fire", now
			end
			return true
		end

		if e.phase == "fire" then
			if not bot.suiciding then e.phase, e.phaseAt = "raise", now return true end
			brain.fireGatedUntil = 0
			brain.buttons = IN_ATTACK
			if now - e.phaseAt > 2.5 then abort(brain, bot, 15) end -- dry fire / jammed
			return true
		end
		return true
	end,
	OnPreempt = function(ctx)
		if ctx.brain.endIt then abort(ctx.brain, ctx.bot, 8) end
	end,
})
