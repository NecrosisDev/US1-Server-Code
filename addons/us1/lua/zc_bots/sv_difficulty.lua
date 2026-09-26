-- Item B6: adaptive global skill offset. Tracks player-vs-bot kills
-- (PlayerDeath's stock (victim, inflictor, attacker) signature -- engine
-- hook, not a custom one) over the last 3 rounds and nudges a shared skill
-- offset toward a 45-55% human win share of those cross kills, +-0.03/round,
-- clamped to [-0.2, 0.15]. Exposed through hg.botdriver.EffectiveSkill
-- (sv_personality.lua), the same function every bot's per-decision skill
-- already reads, so this needs no change anywhere else.
--
-- Only human<->bot kills count toward the ratio (a bot killing a bot, or a
-- human killing a human, says nothing about the human/bot balance the brief
-- asks to adapt toward).

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}

local cv_adaptive = ConVarExists("zc_bots_adaptive") and GetConVar("zc_bots_adaptive")
	or CreateConVar("zc_bots_adaptive", "1", FCVAR_ARCHIVE,
		"Adaptive bot skill offset toward a ~45-55% human win share of human/bot kills", 0, 1)

local STEP = 0.03
local OFFSET_MIN, OFFSET_MAX = -0.2, 0.15
local TARGET_LOW, TARGET_HIGH = 0.45, 0.55
local HISTORY_ROUNDS = 3

hg.botdriver.difficultyOffset = hg.botdriver.difficultyOffset or 0

local roundHumanKillsOnBots = 0
local roundBotKillsOnHumans = 0
local history = hg.botdriver._difficultyHistory or {}
hg.botdriver._difficultyHistory = history

function hg.botdriver.DifficultyOffset()
	if not cv_adaptive:GetBool() then return 0 end
	return hg.botdriver.difficultyOffset or 0
end

local function isManagedBot(ply)
	return IsValid(ply) and ply:IsPlayer() and ply:IsBot() and ply.zcBot == true
end

hook.Add("PlayerDeath", "zc_bots_difficulty_track", function(victim, _inflictor, attacker)
	if not hg.botdriver.Enabled() or not cv_adaptive:GetBool() then return end
	if not IsValid(attacker) or not attacker:IsPlayer() or attacker == victim then return end
	if not IsValid(victim) or not victim:IsPlayer() then return end

	local attackerIsBot, victimIsBot = isManagedBot(attacker), isManagedBot(victim)
	if attackerIsBot == victimIsBot then return end -- only cross (human<->bot) kills move the ratio

	if victimIsBot then
		roundHumanKillsOnBots = roundHumanKillsOnBots + 1
	else
		roundBotKillsOnHumans = roundBotKillsOnHumans + 1
	end
end)

hook.Add("ZB_EndRound", "zc_bots_difficulty_endround", function()
	if not cv_adaptive:GetBool() then
		roundHumanKillsOnBots, roundBotKillsOnHumans = 0, 0
		return
	end

	history[#history + 1] = { h = roundHumanKillsOnBots, b = roundBotKillsOnHumans }
	while #history > HISTORY_ROUNDS do table.remove(history, 1) end
	roundHumanKillsOnBots, roundBotKillsOnHumans = 0, 0

	local totalH, totalB = 0, 0
	for _, rec in ipairs(history) do
		totalH = totalH + rec.h
		totalB = totalB + rec.b
	end
	local total = totalH + totalB
	if total <= 0 then return end

	local humanShare = totalH / total
	local offset = hg.botdriver.difficultyOffset or 0
	if humanShare < TARGET_LOW then
		offset = offset - STEP -- humans losing too many duels: weaken bots
	elseif humanShare > TARGET_HIGH then
		offset = offset + STEP -- humans winning too many duels: strengthen bots
	end
	hg.botdriver.difficultyOffset = math.Clamp(offset, OFFSET_MIN, OFFSET_MAX)
end)

concommand.Add("zc_bots_difficulty_status", function(ply)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	local msg = string.format("[zc_bots] adaptive=%s offset=%.3f history=%d rounds",
		tostring(cv_adaptive:GetBool()), hg.botdriver.difficultyOffset or 0, #history)
	if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end
end, nil, "Superadmin: print the adaptive bot difficulty offset.")
