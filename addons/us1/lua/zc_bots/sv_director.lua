-- Round director (2026-09-26 owner ask): a stage manager above the bots, so
-- a round reads clearly for the people alive in it and the people watching.
--
-- Pacing. Every live round runs a curve read off the round clock and the
-- head count:
--   opening   first 25-40 s: positioning. Bot-vs-bot firefights can start,
--             but nobody dies to one -- no bot wipe before people have
--             even found each other.
--   build     skirmishes. Bot-vs-bot kills are spaced out (6-12 s apart,
--             sooner with a big crowd) so deaths trickle instead of the
--             whole lobby dying in the same five seconds.
--   climax    last 30% of the clock, or four bots or fewer left: fights
--             resolve fast (2-4 s between kills).
-- While a human is alive, the last two bots that human is up against are
-- never killed off by other bots (until the last 15% of the clock) -- there
-- is always someone left for the human to play against.
--
-- Scenes (bot-vs-bot choreography). Two enemy bots fighting each other at
-- range become a scene. The director decides the winner up front (health,
-- skill, and whichever side is losing the head count), then:
--   * both take turns peeking from cover (sv_duel.lua, via duelAllowBot);
--   * while the scene builds up, both bots' aim is offset a few degrees to
--     the side -- real bullets that crack past and hit the cover and the
--     wall behind, never through the target;
--   * when the scene resolves the winner's aim goes true; the loser keeps
--     missing. The kill still has to be earned by the real aim model.
-- Close quarters (under SCRIPT_MIN_DIST) is never scripted -- a point-blank
-- miss looks fake. A scene that anyone human touches (damages either bot)
-- is dropped on the spot and both bots fight for real, and a scene that
-- someone is watching (a living human with sight of it, or a spectator
-- following either bot) builds up faster and misses closer.
--
-- Placement. Every 10-28 s the director checks where human attention is --
-- each living human not already in a fight, and whatever each spectator is
-- following -- and, when nothing is happening there, walks a pair of idle
-- enemy bots toward a meeting point in earshot of the human (700-1200 u
-- away, not on top of them) or brings an enemy to the bot a spectator is
-- watching. It uses its own IDLE behaviour: anything a mode or a fight wants
-- the bot to do comes first.
--
-- Stays out of Homicide (every hmcd round type): the director never touches
-- a round built on hidden roles. Rounds with no enemy bots (co-op, NPC
-- defense) simply never form scenes.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}
local D = hg.botdriver
local lib = D.lib
D.director = D.director or {}
local Dir = D.director

D.DeclareBrainState("director", { fields = {
	"dirScene", "dirGoal", "dirGoalRadius", "dirGoalUntil", "dirGoalAt", "dirMissSide",
} })

local cv = ConVarExists("zc_bots_director") and GetConVar("zc_bots_director")
	or CreateConVar("zc_bots_director", "1", FCVAR_ARCHIVE,
		"Round director: paces bot-vs-bot kills, choreographs bot-vs-bot fights, stages fights where humans are looking", 0, 1)

local OPENING_MIN, OPENING_MAX = 25, 40
local CLIMAX_FRAC, LATE_FRAC = 0.7, 0.85
local CLIMAX_BOTS = 4
local RESERVE = 2
local SCRIPT_MIN_DIST = 420
local SCENE_MAX_AGE = 45
local SCENE_APART = 8
local RESOLVE_MAX = 12
local BUILD = { opening = { 4, 8 }, build = { 5, 10 }, climax = { 2.5, 5 } }
local KILL_GAP = { build = { 6, 12 }, climax = { 2, 4 } }
local MISS_DEG, MISS_DEG_WATCHED = { 2.4, 4.2 }, { 2.0, 3.0 }
local PLACE_EVERY = { opening = { 20, 30 }, build = { 18, 28 }, climax = { 10, 16 } }
local MEET_DIST = { 700, 1200 }
local ATTENTION_RADIUS = 1800
local RECRUIT_RANGE = 4000
local GOAL_TTL = 25
local HUMAN_BUSY = 20
-- A pair whose scene ended without a kill is not re-scripted for this long:
-- a human who stepped in keeps the fight real, and a timed-out standoff
-- does not just start over.
local PAIR_COOLDOWN = { human = 60, timeout = 30, apart = 12 }

D.stats = D.stats or {}
local stats = D.stats

local R = Dir.round or { scenes = {}, nextKillAt = 0, nextPlaceAt = 0 }
R.pairCooldown = R.pairCooldown or {}
Dir.round = R

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function playing(ply)
	return IsValid(ply) and ply:IsPlayer() and ply:Alive()
		and ply:Team() ~= TEAM_SPECTATOR and ply:Team() ~= TEAM_UNASSIGNED
end

local function isBot(ply)
	return playing(ply) and ply:IsBot() and ply.zcBot == true and not ply.zcBotBenched
end

local function nick(ent)
	return IsValid(ent) and ent.Nick and ent:Nick() or "-"
end

local function roundTime()
	local t = zb and tonumber(zb.ROUND_TIME)
	if t and t > 0 and t < 3600 then return t end
	return nil
end

local function roundStart()
	return (zb and tonumber(zb.ROUND_START)) or R.startedAt or CurTime()
end

local function aliveBots()
	local list = {}
	for bot in pairs(D.brains or {}) do
		if isBot(bot) then list[#list + 1] = bot end
	end
	return list
end

local function livingHumans()
	local list = {}
	for _, ply in ipairs(player.GetHumans()) do
		if playing(ply) then list[#list + 1] = ply end
	end
	return list
end

local function enemyOfAnyHuman(bot, humans)
	local isEnemy = D.EnemyOf(bot)
	if not isfunction(isEnemy) then return false end
	for _, h in ipairs(humans) do
		if isEnemy(h) then return true end
	end
	return false
end

function Dir.Active()
	if not cv:GetBool() or not D.Enabled() then return false end
	if not zb or zb.ROUND_STATE ~= 1 or not D.RoundAllowsCombat() then return false end
	if D.homicide and D.homicide.Active and D.homicide.Active() then return false end
	return true
end

function Dir.Phase(now)
	if not Dir.Active() then return "off" end
	now = now or CurTime()
	local elapsed = now - roundStart()
	local total = roundTime()
	local opening = math.Clamp(total and total * 0.12 or 30, OPENING_MIN, OPENING_MAX)
	if elapsed < opening then return "opening", elapsed, total end
	if (total and elapsed >= total * CLIMAX_FRAC) or #aliveBots() <= CLIMAX_BOTS then return "climax", elapsed, total end
	return "build", elapsed, total
end

local function openingEndsAt()
	local total = roundTime()
	return roundStart() + math.Clamp(total and total * 0.12 or 30, OPENING_MIN, OPENING_MAX)
end

local function isLate(now)
	local total = roundTime()
	return total ~= nil and now - roundStart() >= total * LATE_FRAC
end

local function killGap(phase)
	local gap = KILL_GAP[phase] or KILL_GAP.build
	local crowd = math.Clamp(8 / math.max(#aliveBots(), 1), 0.4, 1.5)
	return math.Rand(gap[1], gap[2]) * crowd
end

----------------------------------------------------------------------
-- Scenes
----------------------------------------------------------------------

local function healthFrac(ply)
	local org = ply.organism
	local blood = org and tonumber(org.blood)
	if blood then return math.Clamp(blood / 5000, 0, 1) end
	return math.Clamp(ply:Health() / math.max(ply:GetMaxHealth(), 1), 0, 1)
end

local function teamAlive(ply)
	if D.IsFFA() then return 1 end
	local team, n = D.TeamOf(ply), 0
	for _, other in ipairs(player.GetAll()) do
		if playing(other) and D.TeamOf(other) == team then n = n + 1 end
	end
	return n
end

local function chooseWinner(a, b)
	local function weight(x, other, first)
		local brain = D.brains[x] or {}
		local w = 0.6 + healthFrac(x) + 0.5 * (brain.aimSkill or 0.5)
		if teamAlive(x) < teamAlive(other) then w = w + 0.6 end -- keep the sides even: a longer round
		if first then w = w + 0.3 end -- whoever started it has the jump
		return w
	end
	local wa, wb = weight(a, b, true), weight(b, a, false)
	if math.random() * (wa + wb) < wa then return a, b end
	return b, a
end

local function sceneKey(a, b)
	local ia, ib = a:EntIndex(), b:EntIndex()
	if ia > ib then ia, ib = ib, ia end
	return ia .. ":" .. ib
end

local function closeScene(s, reason)
	for _, pair in ipairs({ { s.a, s.b }, { s.b, s.a } }) do
		local brain = IsValid(pair[1]) and D.brains[pair[1]]
		if brain and brain.dirScene == s then
			brain.dirScene = nil
			brain.dirMissSide = nil
			if brain.duelAllowBot == pair[2] then brain.duelAllowBot = nil end
		end
	end
	R.scenes[s.key] = nil
	if PAIR_COOLDOWN[reason] then R.pairCooldown[s.key] = CurTime() + PAIR_COOLDOWN[reason] end
	stats["directorScene_" .. reason] = (stats["directorScene_" .. reason] or 0) + 1
end

local function openScene(a, b, now, phase)
	local winner, loser = chooseWinner(a, b)
	local build = BUILD[phase] or BUILD.build
	local resolveAt = now + math.Rand(build[1], build[2])
	if phase == "opening" then resolveAt = math.max(resolveAt, openingEndsAt() + math.Rand(1, 4)) end
	local s = {
		key = sceneKey(a, b), a = a, b = b, winner = winner, loser = loser,
		state = "build", startedAt = now, engagedAt = now, resolveAt = resolveAt,
		watched = false, watchCheckAt = 0, openedIn = phase,
	}
	R.scenes[s.key] = s
	for _, pair in ipairs({ { a, b }, { b, a } }) do
		local brain = D.brains[pair[1]]
		brain.dirScene = s
		brain.dirGoal = nil
		-- Take turns peeking from cover (sv_duel.lua) -- unless already in a
		-- duel with a human, which always wins.
		if not (brain.duel and IsValid(brain.duel.target) and not brain.duel.target:IsBot()) then
			brain.duelAllowBot = pair[2]
		end
	end
	stats.directorScenes = (stats.directorScenes or 0) + 1
	return s
end

-- Someone is looking at this fight: a living human with a clear line to
-- either bot, or a spectator following either bot.
local function sceneWatched(s)
	for _, h in ipairs(player.GetHumans()) do
		if playing(h) then
			local eye = h:EyePos()
			for _, x in ipairs({ s.a, s.b }) do
				if eye:DistToSqr(x:GetPos()) < 2500 * 2500 then
					local tr = util.TraceLine({ start = eye, endpos = x:EyePos(), filter = { h, x }, mask = MASK_VISIBLE })
					if not tr.Hit then return true end
				end
			end
		else
			local e = h.chosenSpectEntity
			if not IsValid(e) then e = h:GetNWEntity("spect") end
			if e == s.a or e == s.b then return true end
		end
	end
	return false
end

-- May the scene's loser die now?
local function canKill(loser, now, phase)
	if phase == "opening" or phase == "off" then return false end
	if now < (R.nextKillAt or 0) then return false end
	if isLate(now) then return true end
	local humans = livingHumans()
	if #humans == 0 or not enemyOfAnyHuman(loser, humans) then return true end
	local left = 0
	for _, bot in ipairs(aliveBots()) do
		if bot ~= loser and enemyOfAnyHuman(bot, humans) then left = left + 1 end
	end
	return left >= RESERVE
end

local function engagedPair(s)
	local ba, bb = D.brains[s.a], D.brains[s.b]
	return (ba and ba.target == s.b) or (bb and bb.target == s.a)
end

local function tickScenes(now, phase)
	for _, s in pairs(R.scenes) do
		if not playing(s.a) or not playing(s.b) or s.a.zcBotBenched or s.b.zcBotBenched then
			closeScene(s, "gone")
		elseif s.humanTouched then
			closeScene(s, "human")
		elseif phase == "off" or now - s.startedAt > SCENE_MAX_AGE then
			closeScene(s, "timeout")
		else
			if engagedPair(s) then s.engagedAt = now end
			if now - s.engagedAt > SCENE_APART then
				closeScene(s, "apart")
			else
				if now >= s.watchCheckAt then
					s.watchCheckAt = now + 1
					local watched = sceneWatched(s)
					if watched and not s.watched and s.state == "build" and phase ~= "opening" then
						-- Someone is looking: less standing around trading misses.
						s.resolveAt = math.min(s.resolveAt, now + (s.resolveAt - now) * 0.7)
					end
					s.watched = watched
				end
				if s.state == "build" and now >= s.resolveAt then
					if canKill(s.loser, now, phase) then
						s.state, s.resolvedAt = "resolve", now
					else
						s.resolveAt = now + math.Rand(2, 4)
					end
				elseif s.state == "resolve" and now - s.resolvedAt > RESOLVE_MAX then
					s.state = "real" -- the winner could not close it out: let it play
				end
			end
		end
	end
end

local function findScenes(now, phase)
	for bot, brain in pairs(D.brains) do
		local target = brain.target
		if not brain.dirScene and isBot(bot) and isBot(target) then
			local tb = D.brains[target]
			if tb and not tb.dirScene and not D.IsDowned(bot) and not D.IsDowned(target)
				and now >= (R.pairCooldown[sceneKey(bot, target)] or 0) then
				local isEnemy = D.EnemyOf(bot)
				if isfunction(isEnemy) and isEnemy(target) then openScene(bot, target, now, phase) end
			end
		end
	end
end

-- lib.Engage hook: where this bot actually aims at `target`. Returns nil
-- for "aim where you were going to".
function Dir.AimFor(bot, brain, target, aimPos, now)
	local s = brain.dirScene
	if not s or s.state == "real" then return nil end
	local other = s.a == bot and s.b or s.a
	if target ~= other then return nil end
	if s.state == "resolve" and bot == s.winner then return nil end
	local eye = bot:EyePos()
	local delta = aimPos - eye
	local dist = delta:Length()
	if dist < SCRIPT_MIN_DIST then return nil end
	if not brain.dirMissSide or math.random() < 0.08 then
		brain.dirMissSide = math.random() < 0.5 and 1 or -1
	end
	local range = s.watched and MISS_DEG_WATCHED or MISS_DEG
	local off = math.max(dist * math.tan(math.rad(math.Rand(range[1], range[2]))), 24)
	local dir = delta / dist
	local right = dir:Cross(Vector(0, 0, 1))
	if right:LengthSqr() < 0.01 then return nil end
	right:Normalize()
	return aimPos + right * (off * brain.dirMissSide) + Vector(0, 0, off * math.Rand(-0.35, 0.5))
end

hook.Add("HomigradDamage", "zc_bots_director_human", function(victim, dmg)
	if not IsValid(victim) or not victim:IsPlayer() then return end
	local brain = D.brains and D.brains[victim]
	local s = brain and brain.dirScene
	if not s then return end
	local attacker = dmg and dmg.GetAttacker and dmg:GetAttacker() or nil
	if IsValid(attacker) and attacker:IsPlayer() and not attacker:IsBot() then s.humanTouched = true end
end)

hook.Add("PlayerDeath", "zc_bots_director_kills", function(victim, _, attacker)
	if not Dir.Active() or not IsValid(victim) or not victim:IsBot() then return end
	if not (IsValid(attacker) and attacker:IsPlayer() and attacker:IsBot() and attacker ~= victim) then return end
	local phase = Dir.Phase()
	local now = CurTime()
	R.nextKillAt = math.max(R.nextKillAt or 0, now + killGap(phase))
	local brain = D.brains[victim]
	if brain and brain.dirScene then
		stats.directorSceneKills = (stats.directorSceneKills or 0) + 1
		if brain.dirScene.winner == attacker then stats.directorScriptedKills = (stats.directorScriptedKills or 0) + 1 end
		closeScene(brain.dirScene, "kill")
	end
end)

----------------------------------------------------------------------
-- Placement: stage fights where people are looking
----------------------------------------------------------------------

local function humanBusy(h, now)
	if D.lastFireAt and D.lastFireAt[h] and now - D.lastFireAt[h] < HUMAN_BUSY then return true end
	for _, brain in pairs(D.brains) do
		if brain.target == h then return true end
	end
	return false
end

local function attentionPoints(now)
	local pts = {}
	for _, h in ipairs(player.GetHumans()) do
		if playing(h) then
			if not humanBusy(h, now) then pts[#pts + 1] = { kind = "human", ent = h, weight = 1 } end
		elseif IsValid(h) then
			local e = h.chosenSpectEntity
			if not IsValid(e) then e = h:GetNWEntity("spect") end
			if playing(e) then
				if e:IsBot() then
					pts[#pts + 1] = { kind = "spect", ent = e, weight = 1.5 }
				elseif not humanBusy(e, now) then
					pts[#pts + 1] = { kind = "human", ent = e, weight = 1.5 }
				end
			end
		end
	end
	return pts
end

local function sceneNear(pos)
	for _, s in pairs(R.scenes) do
		if (IsValid(s.a) and s.a:GetPos():DistToSqr(pos) < ATTENTION_RADIUS ^ 2)
			or (IsValid(s.b) and s.b:GetPos():DistToSqr(pos) < ATTENTION_RADIUS ^ 2) then return true end
	end
	return false
end

local function idleBot(bot, now)
	if not isBot(bot) or D.IsDowned(bot) then return false end
	local brain = D.brains[bot]
	if not brain or IsValid(brain.target) or brain.dirScene or brain.duel then return false end
	if now - (brain.dirGoalAt or -math.huge) < 30 then return false end
	return brain.arb == nil or brain.arb.band == "IDLE"
end

local function nearestIdle(pos, now, filter)
	local best, bestD
	for bot in pairs(D.brains) do
		if (not filter or filter(bot)) and idleBot(bot, now) then
			local d = bot:GetPos():DistToSqr(pos)
			if d < RECRUIT_RANGE * RECRUIT_RANGE and (not bestD or d < bestD) then best, bestD = bot, d end
		end
	end
	return best
end

local function navPoint(pos)
	if navmesh and navmesh.GetNearestNavArea then
		local area = navmesh.GetNearestNavArea(pos, false, 600, false, true)
		if area then return area:GetClosestPointOnArea(pos) or area:GetCenter() end
	end
	return nil
end

local function sendTo(bot, pos, radius, now)
	local brain = D.brains[bot]
	brain.dirGoal, brain.dirGoalRadius = pos, radius
	brain.dirGoalAt, brain.dirGoalUntil = now, now + GOAL_TTL
end

local function place(now)
	local pts = attentionPoints(now)
	if #pts == 0 then return false end
	local total = 0
	for _, p in ipairs(pts) do total = total + p.weight end
	local roll, pt = math.random() * total, pts[#pts]
	for _, p in ipairs(pts) do
		roll = roll - p.weight
		if roll <= 0 then pt = p break end
	end
	local focus = pt.ent:GetPos()
	if sceneNear(focus) then return false end

	if pt.kind == "spect" then
		-- A spectator is following this bot: bring it someone to fight.
		local watchedBot = pt.ent
		local wb = D.brains[watchedBot]
		if not wb or IsValid(wb.target) or wb.dirScene then return false end
		local isEnemy = D.EnemyOf(watchedBot)
		local rival = nearestIdle(focus, now, function(b) return isfunction(isEnemy) and isEnemy(b) end)
		if not rival then return false end
		sendTo(rival, focus, 500, now)
		stats.directorPlacements = (stats.directorPlacements or 0) + 1
		return true
	end

	-- A human: a meeting point in earshot, not on top of them.
	local first = nearestIdle(focus, now)
	if not first then return false end
	local away = first:GetPos() - focus
	away.z = 0
	if away:LengthSqr() < 1 then away = VectorRand() away.z = 0 end
	away:Normalize()
	local meet = navPoint(focus + away * math.Rand(MEET_DIST[1], MEET_DIST[2]))
	if not meet then return false end
	local isEnemy = D.EnemyOf(first)
	local second = nearestIdle(meet, now, function(b) return b ~= first and isfunction(isEnemy) and isEnemy(b) end)
	if not second then return false end
	sendTo(first, meet, 250, now)
	sendTo(second, meet, 250, now)
	stats.directorPlacements = (stats.directorPlacements or 0) + 1
	return true
end

D.RegisterBehavior({
	name = "idle.director",
	band = "IDLE",
	order = 22,
	stateLabel = "roam",
	finalize = { path = true },
	CanRun = function(ctx)
		local brain, now = ctx.brain, ctx.now
		local goal = brain.dirGoal
		if not isvector(goal) then return false end
		if now > (brain.dirGoalUntil or 0) or brain.dirScene or not Dir.Active()
			or ctx.bot:GetPos():DistToSqr(goal) <= (brain.dirGoalRadius or 250) ^ 2 then
			brain.dirGoal = nil
			return false
		end
		return true
	end,
	Run = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		lib.PathTo(bot, brain, brain.dirGoal, now, 1)
		if not brain.path and brain.pathFailedAt == now then
			brain.dirGoal = nil
			return false
		end
		return true
	end,
})

----------------------------------------------------------------------
-- Round lifecycle + tick
----------------------------------------------------------------------

local function resetRound()
	for _, s in pairs(R.scenes) do closeScene(s, "round") end
	R.scenes = {}
	R.pairCooldown = {}
	R.startedAt = CurTime()
	R.nextKillAt = 0
	R.nextPlaceAt = CurTime() + math.Rand(8, 14)
end

hook.Add("ZB_StartRound", "zc_bots_director_round", resetRound)
hook.Add("ZB_EndRound", "zc_bots_director_round_end", function()
	for _, s in pairs(R.scenes) do closeScene(s, "round") end
	R.scenes = {}
end)

D.Every("director_tick", 0.25, function()
	if not D.Enabled() then return end
	local now = CurTime()
	local phase = Dir.Phase(now)
	tickScenes(now, phase)
	if phase == "off" then return end
	findScenes(now, phase)
	if now >= (R.nextPlaceAt or 0) then
		local every = PLACE_EVERY[phase] or PLACE_EVERY.build
		R.nextPlaceAt = now + math.Rand(every[1], every[2])
		place(now)
	end
end)

----------------------------------------------------------------------
-- zc_bots_director_debug: what the director and each bot are doing
----------------------------------------------------------------------

concommand.Add("zc_bots_director_debug", function(ply)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	local function out(line)
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
	end
	local now = CurTime()
	local phase, elapsed, total = Dir.Phase(now)
	out(string.format("[director] %s  phase=%s  elapsed=%s/%s  nextKill=%s  nextPlace=%.0fs  round=%s",
		cv:GetBool() and "on" or "OFF", phase, elapsed and string.format("%.0f", elapsed) or "-",
		total and string.format("%.0f", total) or "-",
		(R.nextKillAt or 0) > now and string.format("%.1fs", R.nextKillAt - now) or "open",
		math.max((R.nextPlaceAt or 0) - now, 0), tostring(zb and (zb.CROUND or zb.CROUND_MAIN))))
	local n = 0
	for _, s in pairs(R.scenes) do
		n = n + 1
		out(string.format("  scene %s vs %s  winner=%s  %s  age=%.0fs  resolve=%s%s",
			nick(s.a), nick(s.b), nick(s.winner), s.state, now - s.startedAt,
			s.state == "build" and string.format("in %.1fs", s.resolveAt - now) or "-",
			s.watched and "  WATCHED" or ""))
	end
	if n == 0 then out("  no scenes") end
	for _, p in ipairs(attentionPoints(now)) do
		out(string.format("  attention: %s %s", p.kind, nick(p.ent)))
	end
	out("  bot              state        owner                      target           notes")
	for bot, brain in pairs(D.brains) do
		if IsValid(bot) and bot.zcBot then
			local notes = {}
			if bot.zcBotBenched then notes[#notes + 1] = "benched" end
			if not bot:Alive() then notes[#notes + 1] = "dead" end
			if brain.dirScene then
				notes[#notes + 1] = (brain.dirScene.winner == bot and "scene:WIN" or "scene:lose")
			end
			if isvector(brain.dirGoal) then
				notes[#notes + 1] = string.format("goal %.0fu", bot:GetPos():Distance(brain.dirGoal))
			end
			local duel = D.duel and D.duel.Describe and D.duel.Describe(brain)
			if duel then notes[#notes + 1] = "duel " .. duel end
			local lr = D.lastResort and D.lastResort.Describe and D.lastResort.Describe(brain)
			if lr then notes[#notes + 1] = lr end
			if brain.kbHeld then notes[#notes + 1] = string.format("keys %d", brain.kbHeld) end
			if brain.unstick and now < (brain.unstick.until_ or 0) then notes[#notes + 1] = "UNSTICK" end
			if brain.path then notes[#notes + 1] = string.format("path %d/%d", brain.pathIdx or 0, #brain.path) end
			if bot:Alive() then notes[#notes + 1] = string.format("v=%.0f", bot:GetVelocity():Length2D()) end
			out(string.format("  %-16s %-12s %-26s %-16s %s", string.sub(bot:Nick(), 1, 16),
				tostring(brain.state), tostring(brain.arb and brain.arb.owner), nick(brain.target),
				table.concat(notes, " ")))
		end
	end
end)
