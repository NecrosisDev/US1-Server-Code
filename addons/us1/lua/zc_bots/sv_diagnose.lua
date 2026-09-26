-- zc_bots_diagnose [name]: prints the decision chain and first blocking
-- reason for every tracked bot (or one matching `name`), in plain words.
--
-- WHY THIS EXISTS (owner report, 2026-09-22): prior state probes reported
-- "alive, pathing, investigate" while bots were actually doing nothing --
-- those labels describe the ARBITER BAND, not whether the fire chain
-- (awareness -> Engage -> aim -> control) is actually converging. This file
-- reads the diagnostic snapshot fields sv_brain.lua/sv_aim.lua already stamp
-- every decision/tick (diagEnemyCount, diagBestAwareness, diagEngageAt,
-- aimGateCode/aimErrMagLast/aimConeLast) rather than re-deriving them with a
-- second copy of the targeting/aim math that could silently drift from the
-- real one.
--
-- Superadmin/console gate: identical shape to sv_weaponscore.lua's own
-- zc_bots_debug_weaponscore concommand (`if IsValid(ply) and not
-- ply:IsSuperAdmin() then return end` -- false for a valid non-admin caller,
-- false for the server console since IsValid(ply) is false there, so both
-- superadmins and the console pass).
--
-- Cost: admin-invoked only, never runs per-tick/per-decision. The one loop is
-- over hg.botdriver.brains (already-tracked bots, not ents.GetAll/FindByClass).

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}

local BUTTON_NAMES = {
	{ IN_ATTACK, "ATTACK" }, { IN_ATTACK2, "ATTACK2" }, { IN_RELOAD, "RELOAD" },
	{ IN_FORWARD, "FORWARD" }, { IN_BACK, "BACK" }, { IN_MOVELEFT, "LEFT" }, { IN_MOVERIGHT, "RIGHT" },
	{ IN_JUMP, "JUMP" }, { IN_DUCK, "DUCK" }, { IN_SPEED, "SPEED" }, { IN_USE, "USE" }, { IN_WALK, "WALK" },
}

local function describeButtons(buttons)
	buttons = buttons or 0
	if buttons == 0 then return "(none)" end
	local parts = {}
	for _, pair in ipairs(BUTTON_NAMES) do
		if bit.band(buttons, pair[1]) ~= 0 then parts[#parts + 1] = pair[2] end
	end
	if #parts == 0 then return "(none)" end
	return table.concat(parts, "+")
end

local AIM_GATE_TEXT = {
	["no target"] = "no target yet this life",
	startled = "startle-flinch freeze (recent hit from outside FOV)",
	flick = "flick active",
	offtarget = "aim error exceeds fire cone",
	confirm = "post-flick confirmation delay pending",
	ready = "aim is on-target and confirmed",
}

local function aimGateText(brain)
	local code = brain.aimGateCode or "no target"
	local text = AIM_GATE_TEXT[code] or code
	if code == "offtarget" then
		text = string.format("%s (%.1f deg error vs %.1f deg cone)",
			text, brain.aimErrMagLast or 0, brain.aimConeLast or 0)
	end
	return text
end

-- Priority-ordered, mirrors the actual gate order in sv_brain.lua's Engage /
-- sv_control.lua's StartCommand -- the FIRST reason in that real order that
-- applies is the one actually stalling this bot, not just "something is off".
local function firstBlocker(bot, brain, now, roundKey)
	-- Checked first, ahead of "dead/respawning" -- a benched bot IS dead (or
	-- about to be re-killed on its next spawn, sv_bench.lua), but that is not
	-- why it isn't playing; the bench is.
	if hg.botfill.IsBenched and hg.botfill.IsBenched(bot) then
		return "benched - " .. tostring(hg.botfill.BenchReason and hg.botfill.BenchReason(bot) or "mode not supported")
	end
	if not bot:Alive() then return "bot is dead/respawning" end
	-- 2026-09-25: a crashing decision leaves every other field looking
	-- healthy (target set, Engage stamped) while the bot stands still -- the
	-- US1 failure this tool reported as "no blocker found". Check it first.
	if brain.lastDecisionErrorAt and now - brain.lastDecisionErrorAt < 3 then
		return "decision crashed: " .. tostring(brain.lastDecisionError)
	end
	if hg.botdriver.RoundAllowsCombat and not hg.botdriver.RoundAllowsCombat() then
		return "round state does not currently allow combat"
	end
	if not IsValid(brain.target) then
		local enemyCount = brain.diagEnemyCount or 0
		local best = brain.diagBestAwareness or 0
		local threshold = hg.botdriver.AWARE_THRESHOLD or 1.0
		if enemyCount == 0 then
			return "no enemy actor considered (none alive/in range this decision)"
		elseif best < threshold then
			return string.format("no enemy passes awareness threshold (best %.2f/%.1f%s)",
				best, threshold, brain.diagBestAwarenessName and (" vs " .. brain.diagBestAwarenessName) or "")
		end
		return "no target acquired (behavior band above COMBAT is holding the tick)"
	end
	local engagedRecently = brain.diagEngageAt and (now - brain.diagEngageAt) < 0.35
	if not engagedRecently then
		return string.format("target acquired but Engage did not run this tick (owner=%s)",
			tostring(brain.arb and brain.arb.owner or "?"))
	end
	if not brain.aimAngle then
		return "aim state not allocated this life (aim model not running)"
	end
	if brain.aimCanFire == false then
		return "aimCanFire false: " .. aimGateText(brain)
	end
	if brain.ffHold and now < (brain.ffHoldUntil or 0) then
		return "holding fire: an ally is in the line of fire"
	end
	return "no blocker found -- bot should be able to fire"
end

local function describeBot(bot, brain, now, out)
	local roundKey = zb and (zb.CROUND_MAIN or zb.CROUND)
	out(string.format("--- %s (%s) ---", bot:Nick(), bot:Alive() and "alive" or "dead"))

	local owner = brain.arb and brain.arb.owner or "-"
	local band = brain.arb and brain.arb.band or "-"
	local decidedAgo = brain.arb and brain.arb.at and (now - brain.arb.at) or -1
	out(string.format("  behavior=%s band=%s (decided %.2fs ago)", tostring(owner), tostring(band), decidedAgo))

	local enemyCount = brain.diagEnemyCount or 0
	local best = brain.diagBestAwareness or 0
	local threshold = hg.botdriver.AWARE_THRESHOLD or 1.0
	out(string.format("  enemies considered=%d best awareness=%.2f/%.1f%s",
		enemyCount, best, threshold, brain.diagBestAwarenessName and (" (" .. brain.diagBestAwarenessName .. ")") or ""))

	local targetName = IsValid(brain.target) and ((brain.target.Nick and brain.target:Nick()) or brain.target:GetClass()) or "none"
	out("  current target=" .. targetName)

	local engagedRecently = brain.diagEngageAt and (now - brain.diagEngageAt) < 0.35
	out("  Engage ran this tick=" .. (engagedRecently and "yes" or "no"))

	out(string.format("  aimCanFire=%s (%s)", tostring(brain.aimCanFire), aimGateText(brain)))
	if brain.decisionErrorCount then
		out(string.format("  decision errors=%d, last %.1fs ago: %s", brain.decisionErrorCount,
			now - (brain.lastDecisionErrorAt or now), tostring(brain.lastDecisionError)))
	end

	out("  buttons authored last tick=" .. describeButtons(brain.buttons))

	-- 2026-09-22 (door breach + kick expansion, owner ask): visible without
	-- guessing -- breach phase/attempts while a locked door is being fought
	-- through (sv_doors.lua), and the reason/age of the last leg kick this
	-- bot threw for any reason (sv_melee.lua's lib.TryLegKick stamps both).
	if IsValid(brain.doorBreachDoor) then
		out(string.format("  door breach: phase=%s attempts=%d elapsed=%.1fs/%.1fs",
			tostring(brain.doorBreachPhase or "-"), brain.doorBreachAttempts or 0,
			now - (brain.doorBreachStartedAt or now), hg.botdriver.DOOR_BREACH_MAX_TIME or 0))
	end
	if brain.lastKickAt then
		out(string.format("  last kick: reason=%s %.1fs ago", tostring(brain.lastKickReason or "?"), now - brain.lastKickAt))
	else
		out("  last kick: never this life")
	end

	local wep = IsValid(bot) and bot:GetActiveWeapon()
	local wepName = IsValid(wep) and wep:GetClass() or "none"
	local lastFireAgo = brain.lastShotAt and (now - brain.lastShotAt) or -1
	out(string.format("  weapon=%s last fire attempt=%s",
		wepName, lastFireAgo >= 0 and string.format("%.2fs ago", lastFireAgo) or "never this life"))

	out("  BLOCKER: " .. firstBlocker(bot, brain, now, roundKey))
end

concommand.Add("zc_bots_diagnose", function(ply, cmd, args)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end

	local function out(line)
		if IsValid(ply) then
			ply:PrintMessage(HUD_PRINTCONSOLE, line)
		else
			print(line)
		end
	end

	if not hg.botdriver.Enabled() then
		out("zc_bots_diagnose: zc_bots_enable is 0 -- no bots are running")
		return
	end

	local roundKey = zb and (zb.CROUND_MAIN or zb.CROUND)
	local profile = hg.botdriver.ResolveModeProfile(roundKey)
	out(string.format("=== zc_bots_diagnose: mode=%s profile=%s ===",
		tostring(roundKey or "?"), profile ~= nil and "registered" or "none (generic crowd behavior)"))

	-- Item 1 (2026-09-22, DM endgame escalation): modes/sv_dm.lua's
	-- EndgameFactor, 0 outside dm -- verifiable without a live round.
	if hg.botdriver.EndgameFactor then
		out(string.format("endgame=%.2f alive=%d",
			hg.botdriver.EndgameFactor(), (hg.botdriver.dmEndgame and hg.botdriver.dmEndgame.aliveCount) or 0))
	end

	local wantName = args and args[1]
	local now = CurTime()
	local any = false

	for bot, brain in pairs(hg.botdriver.brains) do
		-- Combined into one condition (not a nested if) so short-circuiting
		-- still guarantees IsValid/IsBot/zcBot pass before bot:Nick() is ever
		-- called on `bot`.
		if IsValid(bot) and bot:IsBot() and bot.zcBot
			and (not wantName or string.find(string.lower(bot:Nick()), string.lower(wantName), 1, true)) then
			any = true
			if not brain then
				out(string.format("--- %s: no brain state tracked yet ---", bot:Nick()))
			else
				describeBot(bot, brain, now, out)
			end
		end
	end

	if not any then
		out(wantName and ("zc_bots_diagnose: no tracked bot matching '" .. wantName .. "'")
			or "zc_bots_diagnose: no bots currently tracked")
	end
end, nil, "Print the decision chain and first blocking reason for zc_bots AI (optionally filtered by name). Superadmin/console only.")

----------------------------------------------------------------------
-- zc_bots_stats [reset]: OUTCOME counters (2026-09-23). The 2026-09-22 lesson
-- was that state probes ("alive, pathing, investigate") passed while bots did
-- nothing. These are things that actually happened: shots, self-treats,
-- items looted, doors opened, hops, steering avoids, peeks, get-up attempts.
-- Written by the modules that do the thing; reset on round start so a round
-- reads as a unit. Superadmin/console gate identical to zc_bots_diagnose.
----------------------------------------------------------------------

hg.botdriver.stats = hg.botdriver.stats or {}
hg.botdriver.statsRoundStartedAt = hg.botdriver.statsRoundStartedAt or CurTime()

local function resetStats()
	for k in pairs(hg.botdriver.stats) do hg.botdriver.stats[k] = 0 end
	hg.botdriver.statsRoundStartedAt = CurTime()
end
hook.Add("ZB_PreRoundStart", "zc_bots_stats_round", resetStats)

hook.Add("PlayerDeath", "zc_bots_stats_kills", function(victim, _, attacker)
	if IsValid(attacker) and attacker:IsPlayer() and attacker:IsBot() and attacker.zcBot and attacker ~= victim then
		hg.botdriver.stats.kills = (hg.botdriver.stats.kills or 0) + 1
	end
	if IsValid(victim) and victim:IsPlayer() and victim:IsBot() and victim.zcBot then
		hg.botdriver.stats.deaths = (hg.botdriver.stats.deaths or 0) + 1
	end
end)

-- US1 fires this hook as (weapon, bulletInfo) from ENTITY:FireLuaBullets
-- (see sv_hearing.lua); the shooter is bulletInfo.Attacker.
hook.Add("EntityFireBullets", "zc_bots_stats_shots", function(_, tInfo)
	local shooter = tInfo and tInfo.Attacker
	if IsValid(shooter) and shooter:IsPlayer() and shooter:IsBot() and shooter.zcBot then
		hg.botdriver.stats.shots = (hg.botdriver.stats.shots or 0) + 1
	end
end)

concommand.Add("zc_bots_stats", function(ply, _, args)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	local function out(line)
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
	end
	if args and args[1] == "reset" then resetStats() out("zc_bots_stats: reset") return end
	local elapsed = math.max(CurTime() - (hg.botdriver.statsRoundStartedAt or CurTime()), 1)
	local bots = 0
	for _, b in ipairs(player.GetBots()) do if b.zcBot and b:Alive() and not b.zcBotBenched then bots = bots + 1 end end
	out(string.format("zc_bots_stats: %.0fs into round, %d live bots", elapsed, bots))
	local keys = {}
	for k in pairs(hg.botdriver.stats) do keys[#keys + 1] = k end
	table.sort(keys)
	for _, k in ipairs(keys) do
		local v = hg.botdriver.stats[k] or 0
		out(string.format("  %-16s %6d   (%.2f/min)", k, v, v / (elapsed / 60)))
	end
end, nil, "Superadmin: print bot decision stats: zc_bots_stats [reset].")
