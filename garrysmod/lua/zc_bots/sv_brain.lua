-- Bot brain: per-bot roam/engage state, decision scheduler, perception,
-- targeting and the combat/medical/movement primitives every behavior calls
-- through hg.botdriver.lib. Ported and slimmed from Trauma's sv_brain.lua
-- (3128 lines -> this file): NPC targeting, witness/reputation, surrender,
-- traitor, rescue, squad/director, loot planning and finish-the-downed are
-- all cut (rule 1). Bots fight players only.
--
-- FIREARM INPUT CONTRACT (rule 3, US1-specific -- differs from Trauma):
--   * ADS is IN_ATTACK2 HELD when the bot wants sights (not an IN_SPEED
--     chord -- Trauma's IN_SPEED-for-ADS is removed outright).
--   * IN_USE is never combined with IN_ATTACK (that is a gun-bash on US1,
--     not a hip-fire combo, and IN_USE while firing blocks the shot).
--   * IN_SPEED is always cleared on any tick IN_ATTACK is set (speed > 150
--     triggers IsSprinting, which blocks firing).
--   * IN_WALK is never combined with IN_RELOAD (this driver never authors
--     IN_WALK at all, so this is satisfied structurally).
--   * A manual-action weapon (AutomaticDraw == false and drawBullet == false
--     and Clip1() > 0) is never fired -- IN_RELOAD is tapped instead
--     (pressed one tick, released the next).
--   * After a weapon switch the bot waits 1.0s (deploy) before firing.
--   * "Is a gun": ishgweapon(wep) if the global exists, else wep.ZoomPos ~= nil.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}
hg.botdriver.brains = hg.botdriver.brains or {}
hg.botdriver.lib = hg.botdriver.lib or {}
local lib = hg.botdriver.lib

local cv_decide_budget = ConVarExists("zc_bots_decide_budget") and GetConVar("zc_bots_decide_budget")
	or CreateConVar("zc_bots_decide_budget", "3", FCVAR_ARCHIVE, "Max full bot decision passes per server tick", 1, 32)
local cv_aimerr = ConVarExists("zc_bots_aim_error") and GetConVar("zc_bots_aim_error")
	or CreateConVar("zc_bots_aim_error", "5", FCVAR_ARCHIVE, "Max bot aim error in degrees at skill 0", 0, 45)
local cv_ms_budget = ConVarExists("zc_bots_ms_budget") and GetConVar("zc_bots_ms_budget")
	or CreateConVar("zc_bots_ms_budget", "1.5", FCVAR_ARCHIVE, "Max milliseconds of bot decisions spent per server tick", 0, 50)

local ENGAGE_RANGE = 2500
local MELEE_REACH = 70
local AIM_ERR_FLOOR = 0.35
local LOW_AMMO_FRAC = 0.2
local DEPLOY_DELAY = 1.0 -- rule 3: hold fire this long after a weapon switch
local FISTS_RAISE_DELAY = 0.4 -- rule 4
local VISION_PERIPHERAL_DOT = math.cos(math.rad(104))
local STUCK_PROGRESS_EPS = 12
-- 2026-09-22: was 0.9, which fired BEFORE sv_traverse.lua's fast diagnosis
-- (0.5s) or sv_doors.lua's staged escalation (1.2s) ever got a turn --
-- verified this session by reading the call order: this blunt jump+duck
-- always wiped brain.path first, so sv_doors' later stages (sidestep, forced
-- repath) were effectively dead code in practice. Bumped past both so this
-- stays the universal LAST-resort net the file's own comments already say it
-- is, instead of winning the race every time.
local STUCK_PROGRESS_TIME = 1.6
local WAYPOINT_REACHED = 40
local DAMAGE_MEMORY = 4
local CLOSE_SWAP_RANGE = 220 -- D4: dry clip closer than this -> swap weapon, do not reload

----------------------------------------------------------------------
-- Weapon probes (rule 3)
----------------------------------------------------------------------

local function isGun(wep)
	if not IsValid(wep) then return false end
	if isfunction(ishgweapon) then return ishgweapon(wep) end
	return wep.ZoomPos ~= nil
end
hg.botdriver.IsGun = isGun

----------------------------------------------------------------------
-- Brain lifecycle + due-time scheduler
--
-- PROVISIONAL(2026-09-21, Trauma's binary-heap decision scheduler is
-- replaced with a per-tick table.sort over the small bot roster this package
-- targets (<= zc_bots_fill_to, headroom-capped against game.MaxPlayers() --
-- 24 by default as of the 2026-09-22 permanent-floor revision); a heap is not
-- worth the complexity at this scale. Revisit if a later phase raises the
-- bot ceiling well past 24, ratify-by: 2026-10-15)
----------------------------------------------------------------------

local scheduled = hg.botdriver.scheduled or {} -- survives brain-only autorefresh
hg.botdriver.scheduled = scheduled

function hg.botdriver.ScheduleDecision(bot, brain, due)
	scheduled[brain] = due or 0
end

function hg.botdriver.UnscheduleDecision(brain)
	scheduled[brain] = nil
end

local CORE_PER_LIFE_FIELDS = {
	"target", "lastSeenPos", "lastSeenTime", "path", "pathIdx", "roamPath", "roamGoal",
	"roamPauseUntil", "attackedBy", "attackedAt", "aimErrAt", "aimErrYaw", "aimErrPitch",
	"aimErrGoalYaw", "aimErrGoalPitch", "aimErrUpdatedAt", "wepSwitchAt", "tgtPrevEnt",
	"tgtPrevPos", "tgtPrevAt", "tgtVel", "lastSeenLookPos", "lastSeenEntIndex", "lookSource",
	"lookPos", "dryClipSince", "meleeStrafeTime", "meleeStrafeDir", "meleeRetreatUntil",
	"nextKickAt", "damageAt", "damagePos", "damageUntil", "damageTargetIndex", "damageTargetUntil",
	"idleScanAt", "idleScanBaseYaw", "actualForward", "actualSide", "sprint", "objectivePos",
	"objectiveRadius", "objectiveExpire", "objectivePriority", "objectiveSource", "objectivePhase",
	"survival", "survivalThreatScanAt", "survivalVisibleHostile", "fistsRaisedAt", "manualCycle", "fireGatedUntil",
	"nextHop", "nextHopCheck", "traverseButtons", "arb",
	"progressPath", "progressIdx", "progressAt", "progressPos", "progressDist",
	"ffCheckAt", "ffHold", "ffHoldUntil", "lastShotAt", "roamJog",
	-- Section C (perception): per-target awareness accumulator + double-take
	-- glance state, reset with everything else on a new life.
	"awareness", "doubleTakeEnt", "doubleTakePos", "doubleTakeLevel", "doubleTakeAt",
	"aimGunErrMult", "lookBehindAt", "lastCorpseGlanced", "lastCorpseGlancedAt",
	"lateralOffset", "pathSpeed", "pathSpeedAt", "pathMeta",
	-- zc_bots_diagnose snapshot fields (sv_diagnose.lua) -- reset per life like
	-- every other perception/decision field above.
	"diagEnemyCount", "diagBestAwareness", "diagBestAwarenessName", "diagEngageAt",
	-- 2026-09-23 medical/downed competence (lib.MedicalCheck / DownedDecide).
	"medSelfStart", "medSelfGiveUpUntil", "medSelfCounted",
	"downedSince", "downedNextTry", "downedScanAt", "downedHostileSeen",
}

local brainStateDecls = hg.botdriver.brainStateDecls or {}
hg.botdriver.brainStateDecls = brainStateDecls

function hg.botdriver.DeclareBrainState(owner, decl)
	decl.fields = decl.fields or {}
	if decl.perLife == nil then decl.perLife = true end
	brainStateDecls[owner] = decl
	return true
end

function hg.botdriver.GetBrain(ply)
	local brain = hg.botdriver.brains[ply]
	if brain then return brain end
	brain = {
		bot = ply,
		state = "roam",
		pathIdx = 1,
		nextDecide = 0,
		nextRepath = 0,
		nextRoam = 0,
		fireUntil = 0,
		fireAfter = 0,
		lastPos = ply:GetPos(),
		buttons = 0,
		viewAngles = ply:EyeAngles(),
		lookSource = "spawn",
		forward = 0,
		side = 0,
	}
	hg.botdriver.brains[ply] = brain
	if ply:Alive() then hg.botdriver.ScheduleDecision(ply, brain, 0) end
	return brain
end

function hg.botdriver.ResetBrain(ply)
	local brain = hg.botdriver.brains[ply]
	if not brain then return end
	for _, field in ipairs(CORE_PER_LIFE_FIELDS) do brain[field] = nil end
	for _, decl in pairs(brainStateDecls) do
		if decl.perLife then
			for _, field in ipairs(decl.fields) do brain[field] = nil end
		end
	end
	brain.state = "roam"
	brain.pathIdx = 1
	brain.nextDecide = 0
	brain.nextRepath = 0
	brain.nextRoam = 0
	brain.fireUntil = 0
	brain.fireAfter = 0
	brain.lastPos = ply:GetPos()
	brain.buttons = 0
	brain.forward, brain.side = 0, 0
	brain.viewAngles = ply:EyeAngles()
	brain.lookSource = "spawn"
	-- Per-life state a module must RE-CREATE after the wipe above (sv_aim's
	-- ring buffers, sv_personality's spawn hold). 2026-09-25: those modules
	-- used to allocate from their own PlayerSpawn hooks, but hook.Add order is
	-- unspecified in GMod -- on US1 the aim hook ran first, this wipe then
	-- nil'd its state and every Engage crashed at sv_aim.lua's
	-- RecordCombatSample (zc_errlog/errors-2026-09-24.txt). Doing it here makes
	-- the result independent of hook order.
	for owner, decl in pairs(brainStateDecls) do
		if decl.perLife and isfunction(decl.reset) then
			local ok, err = pcall(decl.reset, ply, brain)
			if not ok then
				local logRuntime = hg.botdriver.log.runtime or hg.botdriver.log.error
				logRuntime("brain", "reset '" .. tostring(owner) .. "' failed: " .. tostring(err), "reset:" .. tostring(owner))
			end
		end
	end
	if ply:Alive() then
		hg.botdriver.ScheduleDecision(ply, brain, 0)
	else
		hg.botdriver.UnscheduleDecision(brain)
	end
end

hook.Add("PlayerSpawn", "zc_bots_brain_spawn", function(ply)
	if not hg.botdriver.Enabled() then return end
	if not ply:IsBot() or not ply.zcBot then return end
	-- GetBrain first so ResetBrain (and its per-module reset callbacks) also
	-- runs for a bot's very first tracked life.
	hg.botdriver.GetBrain(ply)
	hg.botdriver.ResetBrain(ply)
end)

hook.Add("PlayerDeath", "zc_bots_brain_death", function(ply)
	local brain = hg.botdriver.brains[ply]
	if brain then hg.botdriver.UnscheduleDecision(brain) end
end)

hook.Add("PlayerDisconnected", "zc_bots_brain_disconnect", function(ply)
	local brain = hg.botdriver.brains[ply]
	if brain then hg.botdriver.UnscheduleDecision(brain) end
	hg.botdriver.brains[ply] = nil
end)

----------------------------------------------------------------------
-- Section B/C support state: a tiny fixed-size ring of recent death
-- positions (for "glance at a fresh corpse"/"look toward where a teammate
-- was killed") and a weak last-fire timestamp table (for the awareness
-- accumulator's "target firing = near-instant" gain and "look at a teammate
-- who just fired"). Both are bounded and event-driven, never scanned per
-- tick -- PlayerDeath/the fire record below fire far less than once per
-- decision per bot.
----------------------------------------------------------------------

local RECENT_DEATH_SLOTS = 6
hg.botdriver.recentDeaths = hg.botdriver.recentDeaths or {}
local recentDeaths = hg.botdriver.recentDeaths
local recentDeathIdx = 0

hg.botdriver.lastFireAt = hg.botdriver.lastFireAt or setmetatable({}, { __mode = "k" })

hook.Add("PlayerDeath", "zc_bots_death_memory", function(victim)
	if not IsValid(victim) or not isvector(victim:GetPos()) then return end
	recentDeathIdx = (recentDeathIdx % RECENT_DEATH_SLOTS) + 1
	local slot = recentDeaths[recentDeathIdx]
	if not slot then
		slot = {}
		recentDeaths[recentDeathIdx] = slot
	end
	slot.pos = victim:GetPos()
	slot.at = CurTime()
	slot.team = hg.botdriver.TeamOf(victim)
end)

----------------------------------------------------------------------
-- HomigradDamage listener: seeds attackedBy/damagePos/damageAt for
-- reflex.damage-response and the survival "recentDamage" threat term.
-- Verified signature (rule 7): (ply, dmg, hitgroup, ent, harm).
----------------------------------------------------------------------

hook.Add("HomigradDamage", "zc_bots_damage_awareness", function(ply, dmg, hitgroup, ent, harm)
	if not IsValid(ply) or not ply:IsPlayer() or not ply:IsBot() or not ply.zcBot then return end
	local brain = hg.botdriver.brains[ply]
	if not brain then return end
	local now = CurTime()
	local attacker = dmg and dmg.GetAttacker and dmg:GetAttacker() or nil
	-- Item 3 (NPC targeting): accept an NPC/NextBot attacker too, not just a
	-- player, so a bot under NPC fire registers a threat like human fire.
	local attackerIsActor = IsValid(attacker) and attacker ~= ply
		and (attacker:IsPlayer() or (attacker.IsNPC and attacker:IsNPC()) or (attacker.IsNextBot and attacker:IsNextBot()))
	if attackerIsActor then
		brain.attackedBy = attacker
		brain.attackedAt = now
		brain.damagePos = (attacker.EyePos and attacker:EyePos()) or attacker:GetPos()
	elseif isvector(ply:GetPos()) then
		brain.damagePos = ply:GetPos()
	end
	brain.damageAt = now
	brain.damageUntil = now + DAMAGE_MEMORY
end)

----------------------------------------------------------------------
-- Relationship: players only (rule 1). FFA overrides team comparison.
----------------------------------------------------------------------

function hg.botdriver.EnemyOf(bot)
 local profile = hg.botdriver.ResolveModeProfile(zb and (zb.CROUND_MAIN or zb.CROUND))
 if profile and profile.EnemyOf then return profile.EnemyOf(bot) end
	local ffa = hg.botdriver.IsFFA()
	local myTeam = hg.botdriver.TeamOf(bot)
	return function(ent)
		if not IsValid(ent) or ent == bot or not ent:IsPlayer() then return false end
		if not ent:Alive() then return false end
		if ffa then return true end
		return hg.botdriver.TeamOf(ent) ~= myTeam
	end
end

function hg.botdriver.AllyOf(bot)
 local profile = hg.botdriver.ResolveModeProfile(zb and (zb.CROUND_MAIN or zb.CROUND))
 if profile and profile.AllyOf then return profile.AllyOf(bot) end
	local ffa = hg.botdriver.IsFFA()
	local myTeam = hg.botdriver.TeamOf(bot)
	return function(ent)
		if ffa then return false end
		return IsValid(ent) and ent ~= bot and ent:IsPlayer() and hg.botdriver.TeamOf(ent) == myTeam
	end
end

----------------------------------------------------------------------
-- Look / aim
----------------------------------------------------------------------

function lib.SetLookAngles(brain, ang, source, lock)
	brain.viewAngles = ang
	brain.lookSource = source
	brain.lookLocked = lock or nil
	return true
end

function lib.LookAt(bot, brain, pos, source, lock)
	if not IsValid(bot) or not isvector(pos) then return false end
	local delta = pos - bot:EyePos()
	if delta:LengthSqr() < 1 then return false end
	brain.lookPos = pos
	return lib.SetLookAngles(brain, delta:Angle(), source, lock)
end

function lib.AimPosOf(ent)
	if ent:IsPlayer() and IsValid(ent.FakeRagdoll) then
		local rag = ent.FakeRagdoll
		local phys = rag.GetPhysicsObjectNum and rag:GetPhysicsObjectNum(10)
		return (phys and IsValid(phys)) and phys:GetPos() or rag:WorldSpaceCenter()
	end
	-- Item 2 (NPC targeting): NPC/NextBot aim point (HeadTarget/BodyTarget or
	-- an eyes attachment, small NPCs at WorldSpaceCenter) -- sv_npc.lua.
	if not ent:IsPlayer() and ((ent.IsNPC and ent:IsNPC()) or (ent.IsNextBot and ent:IsNextBot())) then
		local npcMod = hg.botdriver.npc
		if npcMod and npcMod.AimPosOf then return npcMod.AimPosOf(ent) end
	end
	if ent.EyePos then return ent:EyePos() end
	return ent:WorldSpaceCenter()
end

function lib.VisualPerceptionAllowed(bot)
	return IsValid(bot) and not hg.SCP939.IsCreature(bot)
end

local visMemo, visMemoTick = {}, -1
function lib.VisibleAimPos(bot, target)
	if not IsValid(bot) or not IsValid(target) then return nil end
	if not lib.VisualPerceptionAllowed(bot) then return nil end

	local tick = CurTime()
	if tick ~= visMemoTick then
		visMemoTick = tick
		visMemo = {}
	end
	local memoKey = bot:EntIndex() * 65536 + target:EntIndex()
	local memo = visMemo[memoKey]
	if memo ~= nil then
		if memo == false then return nil end
		return memo
	end

	local filter = { bot, target }
	local candidates = {}
	if target:IsPlayer() and IsValid(target.FakeRagdoll) then
		local rag = target.FakeRagdoll
		filter[#filter + 1] = rag
		local phys = rag.GetPhysicsObjectNum and rag:GetPhysicsObjectNum(10)
		if phys and IsValid(phys) then candidates[#candidates + 1] = phys:GetPos() end
		candidates[#candidates + 1] = rag:WorldSpaceCenter()
	else
		candidates[#candidates + 1] = lib.AimPosOf(target)
		if target.GetPos then candidates[#candidates + 1] = target:GetPos() + Vector(0, 0, 36) end
	end

	local eyes = bot:EyePos()
	local found
	for i = 1, #candidates do
		local pos = candidates[i]
		if isvector(pos) and not util.TraceLine({ start = eyes, endpos = pos, filter = filter, mask = MASK_VISIBLE }).Hit
			and not hg.gas.SightBlocked(eyes, pos) then
			found = pos
			break
		end
	end
	visMemo[memoKey] = found or false
	return found
end

function lib.CanSeeTarget(bot, target)
	return lib.VisibleAimPos(bot, target) ~= nil
end

function lib.VisualContact(bot, target, brain, focused, now)
	if not IsValid(bot) or not IsValid(target) then return nil end
	brain = brain or hg.botdriver.GetBrain(bot)
	now = now or CurTime()
	local rough = lib.AimPosOf(target)
	local delta = rough - bot:EyePos()
	local dist = delta:Length()
	if dist < 1 then return lib.VisibleAimPos(bot, target) end
	delta:Div(dist)
	local dot = bot:GetAimVector():Dot(delta)
	if not focused and dot < VISION_PERIPHERAL_DOT then return nil end
	if focused and dot < -0.3 then return nil end
	return lib.VisibleAimPos(bot, target)
end

----------------------------------------------------------------------
-- Targeting: threat-scored visible enemy player within engage range.
-- Simpler than Trauma's pickTarget (400 lines of avenge/paranoia/search
-- heuristics, dropped with witness/reputation). Score terms (higher wins):
-- distance (closer better), a big bonus for whoever damaged us in the last
-- DAMAGE_MEMORY seconds, a bonus if the enemy is aiming roughly at us, a
-- smaller bonus for the current target (stickiness, so a bot does not
-- flicker between two similarly-scored enemies), divided by sv_squad.lua's
-- claim penalty, and a penalty for a downed enemy so bots stop pouring fire
-- into a ragdoll -- but only a penalty, never a hard exclusion, so a downed
-- enemy still gets picked when it is the only visible threat.
--
-- BEHAVIOR CHOICE (not dictated by the brief): the previous hard early-return
-- on a still-visible current target (pure hysteresis, no scoring at all) is
-- replaced by the stickiness bonus above -- the brief asks for both
-- "current target" stickiness AND threat scoring in the same pass, and a hard
-- early-return would make the new score terms unreachable whenever a target
-- stays visible.
----------------------------------------------------------------------

local TARGET_DAMAGED_BONUS = 0.6
-- F2 anti-frustration (2026-09-23, design brief section 7): never gang up
-- four-on-one on a human, and never re-engage a human in their first seconds
-- after spawning unless they started it. Both are score penalties that only
-- apply when another candidate exists, so a lone bot still fights back.
local FAIR_MAX_ENGAGERS = 3
local FAIR_CROWD_PENALTY = 1.2
local FAIR_SPAWN_GRACE = 6
local FAIR_SPAWN_PENALTY = 1.5
local TARGET_AIMING_BONUS = 0.35
local TARGET_STICKY_BONUS = 0.25
local TARGET_DOWNED_PENALTY = 0.5
local TARGET_AIM_DOT = 0.9
-- Item 2 (NPC targeting): threat terms for NPC candidates.
local NPC_TARGETING_US_BONUS = 0.5 -- NPC:GetEnemy() is this bot or any human
local NPC_RUSHER_BONUS = 0.4       -- melee-rusher class within 300u
local NPC_RUSHER_RANGE_SQR = 300 * 300
local NPC_LOW_TIER_PENALTY = 0.2   -- D_FR: hostile but low priority

----------------------------------------------------------------------
-- Section C: perception that builds up. An awareness accumulator per
-- (bot, target) replaces instant detection -- gain depends on angle from
-- gaze centre (foveal fast, peripheral slow, beyond the existing
-- VISION_PERIPHERAL_DOT cone none), distance, target speed/crouch/firing,
-- and decays when the target is not currently visible. Engaged only above
-- AWARE_THRESHOLD; between DOUBLETAKE_THRESHOLD and AWARE_THRESHOLD the bot
-- glances (idle/gaze consumer below) without firing. While actively engaged,
-- other candidates' gain is halved (tunnel vision). Storage is a small
-- per-brain table keyed by entity, reused record tables, pruned to
-- AWARENESS_MAX entries -- no per-decision allocation beyond the first time
-- a given entity is ever seen (a table literal per NEW contact, same cost
-- class sv_hearing.lua/sv_squad.lua already pay for their own contact state).
----------------------------------------------------------------------

local AWARE_THRESHOLD = 1.0
local DOUBLETAKE_THRESHOLD = 0.5
local AWARENESS_MAX_ENTRIES = 12
-- Exported so zc_bots_diagnose (sv_diagnose.lua) can print "best X/threshold"
-- without hardcoding a second copy of this constant that could drift.
hg.botdriver.AWARE_THRESHOLD = AWARE_THRESHOLD
local AWARENESS_FOVEAL_DEG = 20
local AWARENESS_PERIPHERAL_DEG = 80
local AWARENESS_DECAY_RATE = 0.6 -- level/second while not visible

local function angleFromGaze(bot, aimPos)
	local delta = aimPos - bot:EyePos()
	local dist = delta:Length()
	if dist < 1 then return 0, 0 end
	delta:Div(dist)
	local dot = bot:GetAimVector():Dot(delta)
	return math.deg(math.acos(math.Clamp(dot, -1, 1))), dist
end

-- Updates (or decays) one (bot,target) awareness record and returns its
-- level. `aimPos`/`visible` nil means the target is not currently visible at
-- all this decision -- pure decay, no gain.
local function stepAwareness(brain, ent, bot, now, aimPos, tunneled)
	brain.awareness = brain.awareness or {}
	local table_awareness = brain.awareness
	local rec = table_awareness[ent]
	if not rec then
		if table.Count(table_awareness) >= AWARENESS_MAX_ENTRIES then
			-- Bounded storage: drop the least-aware stale entry before adding
			-- a new one, same "prune, never grow unbounded" contract
			-- sv_hearing.lua's contact table already follows.
			local worstEnt, worstLevel
			for otherEnt, otherRec in pairs(table_awareness) do
				if not worstLevel or otherRec.level < worstLevel then
					worstEnt, worstLevel = otherEnt, otherRec.level
				end
			end
			if worstEnt then table_awareness[worstEnt] = nil end
		end
		rec = { level = 0, at = now, lastPos = ent:GetPos() }
		table_awareness[ent] = rec
	end

	local dt = math.Clamp(now - (rec.at or now), 0, 1)
	rec.at = now

	if not aimPos then
		rec.level = math.max(0, rec.level - AWARENESS_DECAY_RATE * dt)
		return rec.level
	end

	local angle, dist = angleFromGaze(bot, aimPos)
	local rate
	if angle <= AWARENESS_FOVEAL_DEG then
		rate = 2.5
	elseif angle <= AWARENESS_PERIPHERAL_DEG then
		rate = Lerp((angle - AWARENESS_FOVEAL_DEG) / (AWARENESS_PERIPHERAL_DEG - AWARENESS_FOVEAL_DEG), 2.5, 0.3)
	else
		rate = 0
	end

	local distTerm = math.Clamp(1 - dist / ENGAGE_RANGE, 0.15, 1)

	local pos = ent:GetPos()
	local speed = pos:Distance(rec.lastPos or pos) / math.max(dt, 0.001)
	rec.lastPos = pos
	local movingTerm = 1 + 0.8 * math.Clamp(speed / 250, 0, 1)
	local stillCrouchTerm = 1
	if ent.Crouching and ent:Crouching() then stillCrouchTerm = stillCrouchTerm * 0.7 end
	if speed < 5 then stillCrouchTerm = stillCrouchTerm * 0.65 end

	local firing = hg.botdriver.lastFireAt and hg.botdriver.lastFireAt[ent]
	local instant = firing and (now - firing) < 0.3

	if instant then
		rec.level = math.max(rec.level, AWARE_THRESHOLD)
	else
		local gain = rate * distTerm * movingTerm * stillCrouchTerm * dt
		if tunneled then gain = gain * 0.5 end
		rec.level = math.min(rec.level + gain, AWARE_THRESHOLD * 1.5)
	end
	return rec.level
end
lib.StepAwareness = stepAwareness

-- How many OTHER bots currently hold `ent` as their target (bounded by the
-- bot roster; runs only for human candidates that are otherwise pickable).
local function engagersOn(ent, self)
	local n = 0
	for other, otherBrain in pairs(hg.botdriver.brains) do
		if other ~= self and IsValid(other) and other:Alive() and otherBrain.target == ent then n = n + 1 end
	end
	return n
end

hook.Add("PlayerSpawn", "zc_bots_fair_spawn_stamp", function(ply)
	if IsValid(ply) then ply.zcSpawnedAt = CurTime() end
end)

function lib.AcquireTargetStep(bot, brain, now, skill, isEnemy)
	if not isfunction(isEnemy) then return nil, nil, false end

	local current = brain.target
	local tunneled = IsValid(current)
	local myPos = bot:GetPos()
	local best, bestScore, bestDist
	brain.doubleTakeLevel = nil

	-- Diagnostic snapshot (zc_bots_diagnose, sv_diagnose.lua reads these):
	-- reset every call so a bot with no enemies this tick reports 0/0, not a
	-- stale number from several decisions ago. Plain number/reference writes
	-- only -- same cost class as the scoring locals already assigned below.
	brain.diagEnemyCount = 0
	brain.diagBestAwareness = 0
	brain.diagBestAwarenessName = nil

	for _, ent in ipairs(hg.botdriver.Actors()) do
		if ent ~= bot and isEnemy(ent) then
			brain.diagEnemyCount = brain.diagEnemyCount + 1
			local dist = myPos:Distance(ent:GetPos())
			local visPos = dist <= ENGAGE_RANGE and lib.VisualContact(bot, ent, brain, ent == current, now) or nil
			if visPos then
				-- C: awareness accumulator gate -- below AWARE_THRESHOLD the
				-- candidate cannot be picked as an engageable target yet; between
				-- DOUBLETAKE_THRESHOLD and AWARE_THRESHOLD it is remembered as a
				-- "double take" glance for the gaze layer instead.
				local awareLevel = stepAwareness(brain, ent, bot, now, visPos, tunneled and ent ~= current)
				if awareLevel > brain.diagBestAwareness then
					brain.diagBestAwareness = awareLevel
					brain.diagBestAwarenessName = (ent.Nick and ent:Nick()) or ent:GetClass()
				end
				if awareLevel >= AWARE_THRESHOLD then
					local score = 1 - (dist / ENGAGE_RANGE)

					if brain.attackedBy == ent and now - (brain.attackedAt or -math.huge) < DAMAGE_MEMORY then
						score = score + TARGET_DAMAGED_BONUS
					end

					local toMe = myPos - ent:GetPos()
					-- ent:GetAimVector is player/NPC-only; guard for a NextBot
					-- registry entry (item 2, NPC targeting).
					if toMe:LengthSqr() > 1 and ent.GetAimVector then
						toMe:Normalize()
						local ok, aimVec = pcall(ent.GetAimVector, ent)
						if ok and aimVec and aimVec:Dot(toMe) > TARGET_AIM_DOT then
							score = score + TARGET_AIMING_BONUS
						end
					end

					if ent == current then score = score + TARGET_STICKY_BONUS end

					-- Item 2 (NPC targeting): threat terms for a registry NPC.
					local npcMod = hg.botdriver.npc
					local entIsNpcActor = npcMod ~= nil and not ent:IsPlayer()
						and ((ent.IsNPC and ent:IsNPC()) or (ent.IsNextBot and ent:IsNextBot()))
					if entIsNpcActor then
						local tier = npcMod.ThreatTier(ent, bot)
						if tier == "low" then score = score - NPC_LOW_TIER_PENALTY end
						local enemyEnt = ent.GetEnemy and ent:GetEnemy()
						local enemyIsUs = IsValid(enemyEnt) and (enemyEnt == bot or enemyEnt:IsPlayer())
						if enemyIsUs then score = score + NPC_TARGETING_US_BONUS end
						local isRusherClose = npcMod.IsMeleeRusher(ent) and myPos:DistToSqr(ent:GetPos()) <= NPC_RUSHER_RANGE_SQR
						if isRusherClose then score = score + NPC_RUSHER_BONUS end
					end

					-- SQUAD: sv_squad.lua target spreading -- a target already
					-- claimed by 2+ living squadmates scores lower unless it is
					-- the only visible enemy, so a lone bot still fights back.
					if hg.botdriver.squad then
						score = score / hg.botdriver.squad.ClaimPenalty(bot, ent)
					end

					if hg.botdriver.IsDowned(ent) then
						score = score - TARGET_DOWNED_PENALTY
					end

					-- Relationship memory (sv_relations.lua): repeat killers draw
					-- focus, past healers are not shot first.
					if hg.botdriver.relations and hg.botdriver.relations.TargetBias then
						score = score + hg.botdriver.relations.TargetBias(bot, brain, ent)
					end

					-- F2: fairness penalties against HUMANS only (bots may swarm bots).
					if ent:IsPlayer() and not ent:IsBot() then
						local startedIt = brain.attackedBy == ent and now - (brain.attackedAt or -math.huge) < DAMAGE_MEMORY
						if not startedIt then
							if now - (ent.zcSpawnedAt or -math.huge) < FAIR_SPAWN_GRACE
								and not (hg.botdriver.lastFireAt[ent] and now - hg.botdriver.lastFireAt[ent] < FAIR_SPAWN_GRACE) then
								score = score - FAIR_SPAWN_PENALTY
							end
							if ent ~= current and engagersOn(ent, bot) >= FAIR_MAX_ENGAGERS then
								score = score - FAIR_CROWD_PENALTY
							end
						end
					end

					if not bestScore or score > bestScore then
						best, bestScore, bestDist = ent, score, dist
					end
				elseif awareLevel >= DOUBLETAKE_THRESHOLD
					and (not brain.doubleTakeLevel or awareLevel > brain.doubleTakeLevel) then
					brain.doubleTakeEnt = ent
					brain.doubleTakePos = visPos
					brain.doubleTakeLevel = awareLevel
					brain.doubleTakeAt = now
				end
			end
		end
	end

	-- Decay awareness for every tracked entity this pass did not touch
	-- (invalid, out of range, or occluded this decision) -- bounded to the
	-- small per-brain table, no per-tick cost.
	if brain.awareness then
		for ent, rec in pairs(brain.awareness) do
			if rec.at < now then
				local decayDt = math.Clamp(now - rec.at, 0, 1)
				rec.level = math.max(0, rec.level - AWARENESS_DECAY_RATE * decayDt)
				rec.at = now
				if rec.level <= 0.001 and not IsValid(ent) then brain.awareness[ent] = nil end
			end
		end
	end

	if best then return best, bestDist, false end
	return nil, nil, false
end

----------------------------------------------------------------------
-- Movement: path following + roam + stuck recovery
----------------------------------------------------------------------

function lib.ObjectiveActive(brain, now)
	return isvector(brain.objectivePos) and now <= (brain.objectiveExpire or 0)
end

function hg.botdriver.SetObjective(bot, pos, radius, ttl, priority, source)
	local brain = hg.botdriver.GetBrain(bot)
	brain.objectivePos = pos
	brain.objectiveRadius = radius or 96
	brain.objectiveExpire = CurTime() + (ttl or 10)
	brain.objectivePriority = priority or "soft"
	brain.objectiveSource = source
	brain.objectivePhase = "travel"
end

function lib.ObjectiveTravel(bot, brain, now)
	if not lib.ObjectiveActive(brain, now) then return false end
	local radius = brain.objectiveRadius or 96
	if bot:GetPos():DistToSqr(brain.objectivePos) <= radius * radius then
		brain.objectivePhase = "arrived"
		brain.path = nil
		return false
	end
	brain.objectivePhase = "travel"
	lib.PathTo(bot, brain, brain.objectivePos, now, 0.8)
	return true
end

-- Known gap fix (2026-09-22): a goal that only drifted a little (a moving
-- target, an objective easing toward its own destination) used to wait out
-- the full repath cadence and then run a brand-new A* search from scratch --
-- "paths are recomputed rather than repaired when a goal moves slightly".
-- When a route is already committed and the cadence hasn't elapsed, patch the
-- corridor's final leg to the new goal instead; full A* still runs once the
-- goal moves further than this or the cadence lapses.
local PATH_REPAIR_DIST = 120

function lib.PathTo(bot, brain, pos, now, cadence)
	brain.roamPath = nil
	brain.roamGoal = nil
	if brain.path and brain.pathGoal and now <= (brain.nextRepath or 0) then
		local drift = pos - brain.pathGoal
		drift.z = 0
		if drift:LengthSqr() <= PATH_REPAIR_DIST * PATH_REPAIR_DIST then
			brain.path[#brain.path] = pos
			brain.pathGoal = pos
		end
		return
	end
	if now <= (brain.nextRepath or 0) then return end
	if not hg.botdriver.CanPath() then return end
	brain.nextRepath = now + (cadence or 2)
	local path, _, _, _, meta = hg.botdriver.FindPath(bot:GetPos(), pos)
	brain.path = path
	brain.pathMeta = path and meta or nil -- sv_nav.lua: { path, narrow[i], areaIndex[id] }
	brain.pathGoal = brain.path and pos or nil
	brain.pathIdx = 1
end

-- D: corner cutting -- once close to the current waypoint and the turn into
-- the next leg is shallow, steer toward the FOLLOWING waypoint instead of
-- walking exactly onto this one. BEHAVIOR CHOICE: the brief asks for a
-- "cheap width check" against the nav area connection; sv_nav.lua exposes no
-- portal-width query (grepped this session, only area/adjacency helpers), so
-- this uses a heading-angle + distance proxy instead -- still no traces, pure
-- vector math over the already-computed path array.
local CORNER_CUT_DOT = math.cos(math.rad(25))
local CORNER_CUT_DIST = 90

function lib.FollowPath(bot, brain)
	if lib.TraverseStep and lib.TraverseStep(bot, brain) then return end
	if not brain.path then return end

	local now = CurTime()
	local activePath = brain.path
	local pos = bot:GetPos()
	local wp = activePath[brain.pathIdx]
	while wp do
		local reached = wp - pos
		local vertOk = math.abs(reached.z) <= 56
		reached.z = 0
		if reached:Length() >= WAYPOINT_REACHED or not vertOk then break end
		if hg.botdriver.HealAreaAt then hg.botdriver.HealAreaAt(wp) end
		brain.pathIdx = brain.pathIdx + 1
		wp = brain.path[brain.pathIdx]
	end
	if not wp then
		brain.path = nil
		brain.pathIdx = 1
		if brain.roamPath == activePath then
			brain.roamPath = nil
			brain.roamGoal = nil
			-- People do not stop at the end of every walk; a short look-around
			-- pause sometimes, otherwise straight on to the next place.
			brain.roamPauseUntil = math.random() < 0.3 and (now + math.Rand(0.4, 1.6)) or now
			brain.nextRoam = brain.roamPauseUntil
			brain.forward, brain.side = 0, 0
		end
		return
	end

	-- Narrow nav area (doorway / tight corridor, flagged by sv_nav.lua): no
	-- corner cutting and no lateral lane offset -- go through the middle.
	local meta = brain.pathMeta
	local narrowHere = meta ~= nil and meta.path == activePath and meta.narrow ~= nil
		and (meta.narrow[brain.pathIdx] == true or meta.narrow[brain.pathIdx + 1] == true)
	local steerWp = wp
	local nextWp = activePath[brain.pathIdx + 1]
	if nextWp and not narrowHere then
		local toWp = wp - pos
		toWp.z = 0
		local legOut = nextWp - wp
		legOut.z = 0
		if toWp:Length() < CORNER_CUT_DIST and legOut:LengthSqr() > 1 and toWp:LengthSqr() > 1 then
			if toWp:GetNormalized():Dot(legOut:GetNormalized()) > CORNER_CUT_DOT then
				steerWp = nextWp
			end
		end
	end

	-- D: a persistent per-life lateral offset inside the lane (not the
	-- centreline every time), applied perpendicular to the travel direction.
	if brain.lateralOffset == nil then brain.lateralOffset = math.Rand(-18, 18) end
	local toSteer = steerWp - pos
	toSteer.z = 0
	local dist = toSteer:Length()
	if dist < 1 then return end
	if brain.lateralOffset ~= 0 and not narrowHere then
		local right = toSteer:Angle():Right()
		local offsetSteer = steerWp + right * brain.lateralOffset
		toSteer = offsetSteer - pos
		toSteer.z = 0
	end

	local dirAng = toSteer:Angle()
	-- Proactive obstacle avoidance (sv_steer.lua): bend the heading around
	-- props/walls/people BEFORE contact instead of after a stall.
	local steerSpeedMul = 1
	if lib.LocalSteer then
		dirAng, steerSpeedMul = lib.LocalSteer(bot, brain, dirAng, brain.pathSpeed or 250, now)
	end
	brain.moveAngles = dirAng
	-- D: slight speed variation, re-rolled on a slow cadence so it reads as
	-- natural gait drift rather than tick-to-tick jitter.
	if now >= (brain.pathSpeedAt or 0) then
		brain.pathSpeedAt = now + math.Rand(2, 4)
		brain.pathSpeed = math.Rand(220, 260)
	end
	brain.forward = (brain.pathSpeed or 250) * steerSpeedMul
	brain.side = 0
	-- Known gap fixes (2026-09-22, sv_traverse.lua): duck for a measured low
	-- ceiling, pick sprint vs. walk pace from context, and watch one step
	-- ahead for an unmarked dropoff -- all guarded (lib.X and lib.X(...)) so a
	-- future load-order change or a stripped-down traverse file degrades to
	-- the old behaviour instead of erroring.
	if lib.NavPosture then lib.NavPosture(bot, brain, wp) end
	-- Gait tier (sv_movement.lua): sprint by default, run in tight spots and
	-- near the goal, slow-walk to listen. Owns brain.sprint / IN_SPEED / IN_WALK.
	if lib.Gait then lib.Gait(bot, brain, now) end
	if lib.EdgeProbe then lib.EdgeProbe(bot, brain) end
	if not brain.lookLocked and not lib.PreAimSteer(bot, brain, wp, dist) then
		-- Eyes are NOT welded to the feet: sv_movement.lua leads the gaze down
		-- the corridor with sweeps and side glances (smooth pursuit in sv_aim).
		if lib.TravelGaze then
			lib.TravelGaze(bot, brain, wp, steerWp, dist, now)
		else
			lib.LookAt(bot, brain, steerWp + Vector(0, 0, 40), "path", false)
		end
	end
end

----------------------------------------------------------------------
-- Pre-aim while travelling (item B3): when a threat direction is already
-- known (a recent lastSeenPos/heardPos, or the squad's freshest contact) look
-- toward where the path becomes visible to it instead of straight down the
-- next waypoint, and slow to a walk while looking past a sharp corner. No new
-- traces -- pure vector math over the already-computed path array and
-- threat-position fields sv_hearing.lua/sv_brain.lua/sv_squad.lua already
-- maintain. Returns true if it drove the look this call (FollowPath then
-- skips its own default LookAt).
----------------------------------------------------------------------

local PREAIM_RECENCY = 6
local CORNER_TURN_DOT = math.cos(math.rad(40)) -- direction change > 40 degrees
local CORNER_SLOW_DIST = 200
local CORNER_WALK_SPEED = 140

local function knownThreatPos(bot, brain, now)
	if isvector(brain.lastSeenPos) and now - (brain.lastSeenTime or -math.huge) < PREAIM_RECENCY then
		return brain.lastSeenPos
	end
	if isvector(brain.heardPos) and now - (brain.heardAt or -math.huge) < PREAIM_RECENCY then
		return brain.heardPos
	end
	local squad = hg.botdriver.squad
	if squad and squad.FreshestContact then
		local pos = squad.FreshestContact(bot)
		if isvector(pos) then return pos end
	end
	return nil
end

function lib.PreAimSteer(bot, brain, wp, distToWp)
	local now = CurTime()
	local threat = knownThreatPos(bot, brain, now)
	if not threat then return false end

	local path, idx = brain.path, brain.pathIdx
	if not path then return false end

	-- Look toward the path node 2-3 ahead (clamped to the path's end) at head
	-- height, biased toward the known threat direction rather than the
	-- immediate waypoint.
	local lookIdx = math.min(idx + 3, #path)
	local lookNode = path[lookIdx] or wp
	local lookPos = lookNode + Vector(0, 0, 64)

	-- Corner detection: direction into the current waypoint vs. direction out
	-- of it toward the next one. A turn sharper than 40 degrees within
	-- CORNER_SLOW_DIST of the corner slows the bot to a walk and looks past it
	-- toward the threat's general bearing instead of into the wall.
	local nextWp = path[idx + 1]
	if nextWp and distToWp <= CORNER_SLOW_DIST then
		local inDir = wp - bot:GetPos()
		local outDir = nextWp - wp
		inDir.z, outDir.z = 0, 0
		if inDir:LengthSqr() > 1 and outDir:LengthSqr() > 1 then
			inDir:Normalize()
			outDir:Normalize()
			if inDir:Dot(outDir) < CORNER_TURN_DOT then
				brain.forward = CORNER_WALK_SPEED
				local towardThreat = threat - wp
				if towardThreat:LengthSqr() > 1 then
					towardThreat:Normalize()
					lookPos = wp + towardThreat * 128 + Vector(0, 0, 64)
				end
			end
		end
	end

	lib.LookAt(bot, brain, lookPos, "path", false)
	return true
end

-- Nearest living squadmate (excluding self), for idle glances (item 9).
local function nearestMate(bot)
	local squad = hg.botdriver.squad
	local mates = squad and squad.Squadmates(bot)
	if not mates then return nil end
	local pos = bot:GetPos()
	local best, bestDistSqr
	for _, m in ipairs(mates) do
		if m ~= bot and IsValid(m) then
			local d = pos:DistToSqr(m:GetPos())
			if not bestDistSqr or d < bestDistSqr then best, bestDistSqr = m, d end
		end
	end
	return best
end

function lib.Roam(bot, brain, now)
	if hg.botdriver.SearchStep and hg.botdriver.SearchStep(bot, brain, now) then return end
	if now < (brain.roamPauseUntil or 0) then return end
	if not brain.roamGoal or not brain.roamPath then
		if now < (brain.nextRoam or 0) then return end
		local goal = hg.botdriver.RandomRoamPos(bot:GetPos())
		if not goal then return end
		brain.roamGoal = goal
		-- PERSONALITY (item 9): not everyone sprints everywhere -- walk most
		-- of a roam leg, jog sometimes, biased by aggression.
		local aggression = (brain.personality and brain.personality.aggression) or 0.5
		brain.roamJog = math.random() < (0.2 + aggression * 0.3)
		lib.PathTo(bot, brain, goal, now, 3)
		brain.roamPath = brain.path
		brain.roamGoal = brain.path and goal or nil
	end
	-- Gait (sprint/run/walk) is decided by sv_movement.lua's lib.Gait from
	-- FollowPath every decision; roamJog only survives as a personality hint.
end

function lib.IdleScan(bot, brain, now)
	if now < (brain.idleScanAt or 0) then return end
	brain.idleScanAt = now + math.Rand(2, 4)
	local base = brain.idleScanBaseYaw or bot:EyeAngles().y
	brain.idleScanBaseYaw = base

	-- Section B: check-behind cadence, 8-20s scaled by curiosity (nosier bots
	-- check more often). Own schedule so it fires even on decisions that don't
	-- roll the 30% glance below.
	local curiosity = (brain.personality and brain.personality.curiosity) or 0.5
	if now >= (brain.lookBehindAt or 0) then
		brain.lookBehindAt = now + math.Rand(8, 20) * (1.3 - 0.5 * curiosity)
		local behindYaw = base + 180 + math.Rand(-20, 20)
		lib.SetLookAngles(brain, Angle(0, behindYaw, 0), "scan", false)
		return
	end

	-- Section B/C: glance priority -- a fresh "double take" candidate from the
	-- awareness accumulator outranks everything else (it is the freshest,
	-- most specific reason to look somewhere); then a nearby fresh corpse
	-- seen for the first time; then a recent sound/teammate-fire/teammate
	-- position; otherwise a blind random sweep. Weapon is never ADS'd here
	-- (this path never sets IN_ATTACK2).
	if isvector(brain.doubleTakePos) and now - (brain.doubleTakeAt or -math.huge) < 0.6 then
		lib.SetLookAngles(brain, (brain.doubleTakePos - bot:EyePos()):Angle(), "doubletake", false)
		return
	end

	if not hg.botdriver.IsFFA() then
		local myPos = bot:GetPos()
		for _, slot in pairs(hg.botdriver.recentDeaths or {}) do
			if slot.pos and (now - (slot.at or -math.huge)) < 6
				and (slot ~= brain.lastCorpseGlanced or slot.at ~= brain.lastCorpseGlancedAt)
				and myPos:DistToSqr(slot.pos) < 700 * 700 then
				brain.lastCorpseGlanced = slot
				brain.lastCorpseGlancedAt = slot.at
				lib.SetLookAngles(brain, (slot.pos - bot:EyePos()):Angle(), "corpse", false)
				return
			end
		end
	end

	if math.random() < 0.3 then
		local glance
		if isvector(brain.heardPos) and now - (brain.heardAt or -math.huge) < 8 then
			glance = brain.heardPos
		elseif not hg.botdriver.IsFFA() then
			-- Prefer a squadmate who just fired (item B: "look at a teammate
			-- who just fired") over a plain nearest-mate glance.
			local squad = hg.botdriver.squad
			local mates = squad and squad.Squadmates(bot)
			local lastFireAt = hg.botdriver.lastFireAt
			if mates then
				for _, m in ipairs(mates) do
					if m ~= bot and IsValid(m) and lastFireAt[m] and now - lastFireAt[m] < 1 then
						glance = m:GetPos()
						break
					end
				end
			end
			if not glance then
				local mate = nearestMate(bot)
				if IsValid(mate) then glance = mate:GetPos() end
			end
		end
		if isvector(glance) then
			lib.SetLookAngles(brain, (glance - bot:EyePos()):Angle(), "scan", false)
			return
		end
	end

	local yaw = base + math.Rand(-45, 45)
	lib.SetLookAngles(brain, Angle(0, yaw, 0), "scan", false)
end

function lib.StuckCheck(bot, brain, now, buttons)
	if brain.traverseButtons then
		buttons = bit.bor(buttons, brain.traverseButtons)
		brain.traverseButtons = nil
	end

	local pos = bot:GetPos()
	local moving = math.abs(brain.forward or 0) > 1 or math.abs(brain.side or 0) > 1
	local suppressed = (brain.survival and brain.survival.body and brain.survival.body.movementSuppressed) or false
	local wp = brain.path and brain.path[brain.pathIdx]
	-- Reallocating a route is not physical progress.

	if not moving or suppressed then
		brain.progressAt = now
		brain.progressPos = pos
		brain.progressDist = wp and pos:Distance(wp) or nil
	elseif not brain.progressAt then
		brain.progressAt = now
		brain.progressPos = pos
		brain.progressDist = wp and pos:Distance(wp) or nil
	else
        local progressed = pos:DistToSqr(brain.progressPos or pos) >= STUCK_PROGRESS_EPS * STUCK_PROGRESS_EPS

		if progressed then
			brain.progressAt = now
			brain.progressPos = pos
		elseif now - brain.progressAt > STUCK_PROGRESS_TIME then
			brain.progressAt = now
			brain.progressPos = pos
			brain.progressDist = wp and pos:Distance(wp) or nil
			if not (lib.OnStairs and lib.OnStairs(bot, brain, now)) then
				buttons = bit.bor(buttons, IN_JUMP, IN_DUCK)
			end
			brain.nextRepath = 0
			if brain.roamPath == brain.path then
				brain.roamPath = nil
				brain.roamGoal = nil
			end
			if wp and hg.botdriver.PenalizeArea then
				local area = navmesh.IsLoaded() and navmesh.GetNearestNavArea(wp)
				if IsValid(area) then hg.botdriver.PenalizeArea(area:GetID()) end
			end
			brain.path = nil
		end
	end

	brain.progressPath = brain.path
	brain.progressIdx = brain.pathIdx
	brain.lastPos = pos
	return buttons
end

----------------------------------------------------------------------
-- Downed / get-up (rule 5: hg.FakeUp verified at fake/sv_tier_0.lua:730)
----------------------------------------------------------------------

-- 2026-09-23: a human who goes down does not spring back up the same tick.
-- They lie there a beat, look toward whoever did it, wait for the shooter to
-- lose interest (or bleed out trying), then get up -- and hg.FakeUp itself
-- refuses while "Should Fake Up" hooks (organism consciousness, tape, taser)
-- say no. This paces the attempt like that instead of spamming FakeUp every
-- decision, which both looked robotic and made a downed bot pop up into the
-- gun that just dropped it.
local DOWNED_MIN_WAIT = 1.4
local DOWNED_RETRY = 2.0
local DOWNED_PLAY_DEAD_MAX = 8
local DOWNED_HOSTILE_RANGE = 520

function hg.botdriver.DownedDecide(bot, brain, now, isEnemy)
	if not hg.botdriver.IsDowned(bot) then
		brain.downedSince = nil
		return false
	end
	brain.forward, brain.side = 0, 0
	brain.downedSince = brain.downedSince or now
	local org = bot.organism
	if org and org.otrub == true then return true end -- unconscious: nothing to decide

	-- Look toward the last hurt/threat direction from the floor.
	local threatPos = isvector(brain.damagePos) and brain.damagePos or brain.lastSeenPos
	if isvector(threatPos) and not brain.lookLocked then
		lib.LookAt(bot, brain, threatPos + Vector(0, 0, 32), "downed", false)
	end

	local patience = (brain.personality and brain.personality.patience) or 1
	if now - brain.downedSince < DOWNED_MIN_WAIT * patience then return true end

	-- Play dead while the shooter is still standing over us (bounded).
	local blood = org and tonumber(org.blood)
	local bloodCritical = blood ~= nil and blood < 2600
	if not bloodCritical and now - brain.downedSince < DOWNED_PLAY_DEAD_MAX and isfunction(isEnemy) then
		if now >= (brain.downedScanAt or 0) then
			brain.downedScanAt = now + 0.5
			brain.downedHostileSeen = false
			local myPos = bot:GetPos()
			for _, ent in ipairs(hg.botdriver.Actors()) do
				if ent ~= bot and isEnemy(ent) and myPos:DistToSqr(ent:GetPos()) <= DOWNED_HOSTILE_RANGE * DOWNED_HOSTILE_RANGE
					and lib.VisualContact(bot, ent, brain, true, now) then
					brain.downedHostileSeen = true
					break
				end
			end
		end
		if brain.downedHostileSeen then return true end
	end

	if now < (brain.downedNextTry or 0) then return true end
	brain.downedNextTry = now + DOWNED_RETRY
	if isfunction(hg.FakeUp) then
		hg.FakeUp(bot)
		hg.botdriver.stats = hg.botdriver.stats or {}
		hg.botdriver.stats.getUpAttempts = (hg.botdriver.stats.getUpAttempts or 0) + 1
	end
	return true
end

----------------------------------------------------------------------
-- Medical (rule 5)
----------------------------------------------------------------------

local MED_SELF_MAX_TIME = 9

function lib.MedicalCheck(bot, brain, now, inCombat)
	local org = bot.organism
	if not org then return false end

	local bleed = 0
	if istable(org.wounds) then
		for _, wound in pairs(org.wounds) do bleed = bleed + (istable(wound) and (wound[1] or 0) or 0) end
	end
	local arterial = istable(org.arterialwounds) and #org.arterialwounds > 0
	local hurting = (org.blood or 99999) < 3100 or bleed >= 15 or arterial
	-- 2026-09-25: sv_survival.lua recommends self_treat for high pain
	-- ("high_pain") and hunger ("hungry"), and BestCarriedMedical already
	-- offers painkillers/food for exactly those conditions -- but this gate
	-- only knew about blood loss, so painkillers and food were never used.
	-- Same thresholds as the survival reasons; both items are single-use
	-- (weapon_painkillers / weapon_*consumable Remove() themselves).
	if not hurting then
		local cfg = hg.botdriver.GetSurvivalConfig and hg.botdriver.GetSurvivalConfig() or {}
		local painful = (tonumber(org.pain) or 0) >= (cfg.pain_urgent or 50)
		local satiety = tonumber(org.satiety)
		local hungry = satiety ~= nil and satiety < (cfg.satiety_caution or 25)
		if (painful or hungry) and hg.botdriver.BestCarriedMedical(bot) ~= nil then hurting = true end
	end

	local active = bot:GetActiveWeapon()
	local holdingMed = IsValid(active) and active.Heal ~= nil

	if inCombat or not hurting then
		brain.medSelfStart = nil
		brain.medSelfCounted = nil
		if not holdingMed then return false end
		local best = hg.botdriver.BestGun(bot)
		if best then
			bot:SelectWeapon(best:GetClass())
			return false
		end
		local meleeClass = hg.botdriver.HasMelee(bot)
		if meleeClass then bot:SelectWeapon(meleeClass) end
		return false
	end

	local med = hg.botdriver.BestCarriedMedical(bot)
	if not med then return false end
	if now < (brain.medSelfGiveUpUntil or 0) then return false end

	brain.state = "medic"
	-- Bounded: a treatment that is not finishing (no supplies left for this
	-- wound type, heal-anim hold never completing) is abandoned for a while
	-- instead of standing still forever holding a bandage.
	if brain.medSelfStart and now - brain.medSelfStart > MED_SELF_MAX_TIME then
		brain.medSelfStart = nil
		brain.medSelfCounted = nil
		brain.medSelfGiveUpUntil = now + 12
		local best = hg.botdriver.BestGun(bot)
		if best then bot:SelectWeapon(best:GetClass()) end
		return false
	end
	brain.medSelfStart = brain.medSelfStart or now
	if active ~= med then
		bot:SelectWeapon(med:GetClass())
		return true
	end

	-- Medkit: pick the mode that matches the condition, and only a mode that
	-- still has supplies (weapon_medkit_sh.lua modeValues[1..6]; mode is the
	-- plain server field the radial's net handler writes, weapon_bandage_sh.lua:398).
	if med:GetClass() == "weapon_medkit_sh" and istable(med.modeValues) then
		local mv = med.modeValues
		local pain = tonumber(org.pain) or 0
		local internal = tonumber(org.internalBleed) or 0
		local want = med.mode or 1
		if arterial and (mv[4] or 0) > 0 then want = 4
		elseif bleed > 0 and (mv[1] or 0) > 0 then want = 1
		elseif internal > 0 and (mv[3] or 0) > 0 then want = 3
		elseif pain >= 20 and (mv[2] or 0) > 0 then want = 2
		elseif (mv[1] or 0) > 0 then want = 1 end
		if med.mode ~= want then med.mode = want end
	end

	if not brain.medSelfCounted then
		brain.medSelfCounted = true
		hg.botdriver.stats = hg.botdriver.stats or {}
		hg.botdriver.stats.selfTreats = (hg.botdriver.stats.selfTreats or 0) + 1
	end

	brain.path = nil
	brain.forward, brain.side = 0, 0
	brain.actionPolicy = { owner = "medic:self", lockMove = true }
	-- Hold the primary (heal anims accumulate per call) and crouch: a person
	-- patching themselves gets low and keeps an eye on where the trouble was.
	brain.buttons = bit.bor(brain.buttons or 0, IN_ATTACK, IN_DUCK)
	if isvector(brain.lastSeenPos) and now - (brain.lastSeenTime or -math.huge) < 20 and not brain.lookLocked then
		lib.LookAt(bot, brain, brain.lastSeenPos + Vector(0, 0, 40), "medic:self", false)
	end
	return true
end

----------------------------------------------------------------------
-- Engage: aim, stance, fire discipline, melee. See file header for the
-- firearm input contract this differs from Trauma on.
----------------------------------------------------------------------

function lib.Engage(bot, brain, now, skill, target, dist, behavior, buttons)
	buttons = buttons or 0
	behavior = behavior or {}
	-- zc_bots_diagnose (sv_diagnose.lua): "did Engage run this tick" is read
	-- back as (now - brain.diagEngageAt) < a small window. Plain number write,
	-- decision-rate (~6Hz) function -- not the StartCommand/aim.Tick budget.
	brain.diagEngageAt = now

	if not hg.botdriver.RoundAllowsCombat() then
		brain.fireUntil = 0
		brain.aimLocked = nil
		return bit.band(buttons, bit.bnot(bit.bor(IN_ATTACK, IN_ATTACK2)))
	end

	if not IsValid(target) then
		brain.fireUntil = 0
		brain.aimLocked = nil
		return bit.band(buttons, bit.bnot(IN_ATTACK))
	end

	local visibleAim = lib.VisibleAimPos(bot, target)
	if not visibleAim then
		brain.fireUntil = 0
		brain.aimLocked = nil
		if brain.target == target then
			-- A5: pre-aim hold -- sv_aim.lua keeps pursuing the extrapolated
			-- last-seen angle for 0.3-0.6s (overshooting slightly, then
			-- settling on the corner) instead of the view instantly snapping
			-- to whatever claims the tick next.
			if hg.botdriver.aim then hg.botdriver.aim.BeginOcclusion(brain, now) end
			brain.target = nil
			brain.path = nil
		end
		-- HUMANIZE: sv_gunhandling.lua reaction delay (LOS lost).
		if hg.botdriver.gunhandling then hg.botdriver.gunhandling.OnLOSLost(brain) end
		return bit.band(buttons, bit.bnot(IN_ATTACK))
	end

	brain.state = "engage"
	local reacquired = brain.target ~= target or brain.gunHadLOS == false
	if brain.target ~= target then
		brain.target = target
		brain.targetSince = now
		-- The aim model's latency ring still holds the PREVIOUS target's
		-- samples; extrapolating those (velocity x age, age possibly many
		-- seconds) flicked the view in a random direction on every new
		-- engagement. Start the new target from an empty ring.
		if hg.botdriver.aim and hg.botdriver.aim.ClearRing then hg.botdriver.aim.ClearRing(brain) end
	end
	brain.gunHadLOS = true
	-- HUMANIZE: sv_gunhandling.lua reaction delay (new/re-acquired target).
	if reacquired and hg.botdriver.gunhandling then
		hg.botdriver.gunhandling.OnAcquire(brain, now, skill)
	end
	-- RADIAL (sv_radial.lua, optional): "spotted an enemy" voiceline hook,
	-- same optional-module shape as gunhandling above -- fires only on an
	-- actual (re)acquisition, not every tick the target stays visible.
	if reacquired and hg.botdriver.radial then
		hg.botdriver.radial.OnAcquire(bot, brain, now, target)
	end
	if reacquired and hg.botdriver.relations and hg.botdriver.relations.OnAcquire then
		hg.botdriver.relations.OnAcquire(bot, brain, now, target)
	end
	brain.lastSeenPos = target:GetPos()
	brain.lastSeenLookPos = visibleAim
	brain.lastSeenEntIndex = target:EntIndex()
	brain.lastSeenTime = now

	-- HUMANIZE (2026-09-21): sv_aim.lua's per-tick motor model now owns the
	-- aim-error tremor this block used to author directly (section A4: "fold
	-- the existing aim-error/lead logic in lib.Engage into this model so
	-- there is ONE source of aim error"). This decision (running at ~6Hz)
	-- only ever records a raw angle+distance sample into the aim model's
	-- perceptual-latency ring -- the one vector/Angle allocation per decision
	-- this file already paid for before this pass. gunhandling's contextual
	-- widening (burst/pain/range) becomes an extra multiplier the aim model
	-- applies on top of zc_bots_aim_error, so the single source of error is
	-- preserved rather than duplicated.
	local gunErrMult = 1
	if hg.botdriver.gunhandling then
		gunErrMult = hg.botdriver.gunhandling.AimErrorMultiplier(bot, brain, now, dist or 0)
	end
	brain.aimGunErrMult = math.max(0.3, gunErrMult)

	local eyePos = bot:EyePos()
	local ang = (visibleAim - eyePos):Angle()
	if hg.botdriver.aim then
		hg.botdriver.aim.RecordCombatSample(brain, ang.y, ang.p, now, dist or eyePos:Distance(visibleAim))
	end
	brain.lookSource = "combat"
	brain.lookLocked = true
	brain.lookPos = visibleAim
	brain.aimLocked = true

	local prevWep = bot:GetActiveWeapon()
	if hg.botdriver.EquipForRange and hg.botdriver.EquipForRange(bot, brain, now, dist or 0) then
		return buttons -- deploy started this tick, hold fire
	end

	local wep = bot:GetActiveWeapon()
	if wep ~= prevWep then brain.wepSwitchAt = now end

	----------------------------------------------------------------
	-- Melee: raise fists first (rule 4), then close and swing
	----------------------------------------------------------------
	-- Item 2 (NPC targeting): a bot carrying a working gun never chooses
	-- melee against an NPC target -- switch back before entering the melee
	-- branch at all.
	local targetIsNPC = not target:IsPlayer() and ((target.IsNPC and target:IsNPC()) or (target.IsNextBot and target:IsNextBot()))
	if targetIsNPC and IsValid(wep) and wep.ismelee then
		local gun = hg.botdriver.BestGun and hg.botdriver.BestGun(bot)
		if gun then
			bot:SelectWeapon(gun:GetClass())
			return buttons -- deploy switch started this tick, hold fire
		end
	end
	if IsValid(wep) and wep.ismelee then
		return lib.MeleeEngage(bot, brain, now, skill, target, dist, buttons, wep)
	end

	-- 2026-09-22 (kick expansion, owner ask): a gun-wielding bot can still
	-- kick a point-blank target to interrupt a heal or finish a downed/
	-- getting-up one -- sv_melee.lua's lib.TryOpportunisticKick own-gates on
	-- KICK_RANGE and shares the same lib.TryLegKick cooldown/ally-check every
	-- other kick trigger in this package uses, so this is cheap (one range
	-- compare) and never fights those triggers.
	lib.TryOpportunisticKick(bot, brain, now, target, dist)

	----------------------------------------------------------------
	-- Ranged: US1 firearm input contract (see file header)
	----------------------------------------------------------------
	local preferRange = behavior.preferRange or 600
	local aggr = behavior.aggression or 0.5

	local deployBlocked = now - (brain.wepSwitchAt or 0) < DEPLOY_DELAY

	local isManualAction = IsValid(wep) and wep.AutomaticDraw == false and wep.drawBullet == false
		and wep.Clip1 and wep:Clip1() > 0
	if (isManualAction or deployBlocked) and lib.TryGunBash then
		local bash = lib.TryGunBash(bot, brain, now, dist, buttons)
		if bash then return bash end
	end
	if isManualAction then
		-- Tap, don't hold: press one tick, release the next.
		if brain.manualCycle then
			brain.manualCycle = false
		else
			brain.manualCycle = true
			buttons = bit.bor(buttons, IN_RELOAD)
		end
		return bit.band(buttons, bit.bnot(bit.bor(IN_ATTACK, IN_SPEED)))
	end
	brain.manualCycle = nil

	local ammoRatio = 1
	local dryClip = false
	if IsValid(wep) and not wep.ismelee and wep.Clip1 then
		local clip = wep:Clip1() or 0
		local reserve = hg.botdriver.EffectiveReserve and hg.botdriver.EffectiveReserve(bot, wep) or 0
		local clipSize = (wep.GetMaxClip1 and wep:GetMaxClip1()) or (wep.Primary and wep.Primary.ClipSize) or math.max(clip, 1)
		ammoRatio = math.Clamp((clip + reserve) / math.max(clipSize, 1), 0, 1)
		dryClip = clip <= 0
	end

	if dryClip then
		-- 2026-09-23 (D4): inside CLOSE_SWAP_RANGE a person does not stand
		-- there reloading -- they pull the sidearm/knife. sv_gunhandling.lua
		-- owns the choice (loaded secondary first, melee second).
		if (dist or 0) < CLOSE_SWAP_RANGE and hg.botdriver.gunhandling and hg.botdriver.gunhandling.CloseQuartersSwap then
			if hg.botdriver.gunhandling.CloseQuartersSwap(bot, brain, now, wep) then
				return bit.band(buttons, bit.bnot(bit.bor(IN_ATTACK, IN_SPEED)))
			end
		end
		if lib.TryGunBash then
			local bash = lib.TryGunBash(bot, brain, now, dist, buttons)
			if bash then return bash end
		end
		-- Reload when Clip1()==0 and reserve>0 (rule 5's sibling rule 3 term).
		local reserve = hg.botdriver.EffectiveReserve and hg.botdriver.EffectiveReserve(bot, wep) or 0
		local buttonsNoFire = bit.band(buttons, bit.bnot(bit.bor(IN_ATTACK, IN_SPEED)))
		if reserve > 0 then
			-- HUMANIZE: sv_gunhandling.lua -- enemy still visible here, so
			-- head for cover (or fall back to backing toward the previous
			-- path node) while reloading.
			if hg.botdriver.gunhandling then
				hg.botdriver.gunhandling.RetreatWhileReloading(bot, brain, now, target, dist)
				if hg.botdriver.gunhandling.SetShellGoal and not brain.shellGoal then
					hg.botdriver.gunhandling.SetShellGoal(bot, brain, wep, true, dist)
				end
			end
			return bit.bor(buttonsNoFire, IN_RELOAD)
		end
		return buttonsNoFire
	end

	-- 2026-09-26: a tube/stripper loader mid-reload keeps R held until its
	-- shell goal (sv_gunhandling.lua ShellReloadHold) instead of firing the
	-- first shell that lands.
	local ghMod = hg.botdriver.gunhandling
	if ghMod and ghMod.ShellReloadHold and ghMod.ShellReloadHold(bot, brain, now, wep, dist) then
		ghMod.RetreatWhileReloading(bot, brain, now, target, dist)
		return bit.bor(bit.band(buttons, bit.bnot(bit.bor(IN_ATTACK, IN_SPEED))), IN_RELOAD)
	end

	local scared = 1 - ammoRatio
	local aggrEff = aggr * (1 - 0.6 * scared)
	-- Item 1 (2026-09-22, DM endgame fix): shorten the low-ammo disengage
	-- threshold as modes/sv_dm.lua's EndgameFactor rises (0 outside dm, so
	-- this is a no-op in every other mode) -- part of the same escalation
	-- curve as sv_survival.lua's cover-seeking floor, so a committed bot does
	-- not still bail out of a fight at a fixed 20% ammo cutoff.
	local endgame = hg.botdriver.EndgameFactor and hg.botdriver.EndgameFactor() or 0
	if hg.botdriver.HomicideRush and hg.botdriver.HomicideRush() then endgame = 1 end
	local breakOff = ammoRatio < (LOW_AMMO_FRAC * (1 - 0.75 * endgame))

	if breakOff then
		brain.target = nil
		brain.path = nil
		brain.state = "disengage"
		return bit.band(buttons, bit.bnot(bit.bor(IN_ATTACK, IN_ATTACK2, IN_SPEED)))
	end

	-- 2026-09-26: never fire a launcher inside its own blast/arming radius,
	-- into a wall at arm's length, or with a teammate in the backblast
	-- (sv_gunhandling.lua LauncherUnsafe). Back off to open the range.
	if ghMod and ghMod.LauncherUnsafe
		and ghMod.LauncherUnsafe(bot, brain, wep, dist, visibleAim, (behavior and behavior.allyOf) or hg.botdriver.AllyOf(bot)) then
		brain.fireUntil = 0
		brain.path = nil
		brain.moveAngles = Angle(0, (target:GetPos() - bot:GetPos()):Angle().y, 0)
		brain.forward = (dist or 0) < 520 and -200 or 0
		brain.side = (bot:EntIndex() % 2 == 0) and 140 or -140
		if lib.SafeCombatMove then lib.SafeCombatMove(bot, brain, now) end
		return bit.band(buttons, bit.bnot(bit.bor(IN_ATTACK, IN_SPEED)))
	end

	brain.fireGatedUntil = now + 0.3

	-- ADS: IN_ATTACK2 held when we want sights (rule 3), never IN_SPEED.
	if (dist or 0) > preferRange then
		buttons = bit.bor(buttons, IN_ATTACK2)
	end

	-- FRIENDLY FIRE (team modes only): re-checked at most every 0.2s per bot
	-- and cached between checks -- a hull-less trace along the current aim;
	-- if the first thing it hits is a living ally, hold fire and sidestep.
	local ffBlocked = false
	if not hg.botdriver.IsFFA() then
		if now >= (brain.ffCheckAt or 0) then
			brain.ffCheckAt = now + 0.2
			brain.ffHold = false
			local aimDir = visibleAim - eyePos
			if aimDir:LengthSqr() > 1 then
				local tr = util.TraceLine({
					start = eyePos,
					endpos = eyePos + aimDir:GetNormalized() * 4096,
					filter = bot,
					mask = MASK_SHOT,
				})
				local hitEnt = tr.Entity
				-- 2026-09-22 fix: prefer the ctx-resolved relationship
				-- combat.engage now stashes on `behavior.allyOf` (MODE-band
				-- overrides, e.g. masscasualty's shooterAllyOf or
				-- sv_crowd.lua's defensive no-allies) over the raw team-based
				-- default -- see behaviors/sv_core_combat.lua's Run for why:
				-- a homicide-family round has no team split at all, so the
				-- raw check would treat a shooter's own civilian target (or a
				-- defensive bot's own attacker) as an "ally" on team number
				-- alone and hold fire forever. Falls back to the raw
				-- function unchanged for every mode that never sets it.
				local isAlly = (behavior and behavior.allyOf) or hg.botdriver.AllyOf(bot)
				if IsValid(hitEnt) and hitEnt:IsPlayer() and hitEnt:Alive() and isAlly(hitEnt) then
					brain.ffHold = true
					brain.ffHoldUntil = now + 0.4
				end
			end
		end
		ffBlocked = brain.ffHold and now < (brain.ffHoldUntil or 0)
	end

	local canFireNow = not deployBlocked and not ffBlocked
	local aimDelta = visibleAim - eyePos
	local onTarget = aimDelta:LengthSqr() > 1 and bot:GetAimVector():Dot(aimDelta:GetNormalized()) > 0.985

	-- HUMANIZE: sv_gunhandling.lua burst discipline for automatic weapons;
	-- everything else keeps the original single-decision fire timing below.
	local ghAuto = canFireNow and hg.botdriver.gunhandling and wep.Primary and wep.Primary.Automatic
	if ghAuto then
		hg.botdriver.gunhandling.BurstFire(bot, brain, now, skill, wep, dist or 0, aggr, scared, onTarget)
	elseif canFireNow and now > brain.fireAfter then
		if onTarget then
			brain.fireUntil = now + 0.3 * (1 - 0.5 * scared)
			brain.fireAfter = now + (0.3 + math.Rand(0.2, 0.5) * (1.5 - skill) * (1.3 - 0.6 * aggr)) * (1 + scared)
		end
	end
	if canFireNow and now < (brain.squadSuppressUntil or 0) and now > brain.fireUntil then
		brain.fireUntil = now + 0.35
	end
	if canFireNow and now < brain.fireUntil then
		buttons = bit.bor(buttons, IN_ATTACK)
	end

	-- Rule 3: IN_SPEED never coexists with IN_ATTACK, and IN_USE never
	-- coexists with IN_ATTACK (US1 gun-bash), whatever authored either bit.
	if bit.band(buttons, IN_ATTACK) ~= 0 then
		buttons = bit.band(buttons, bit.bnot(bit.bor(IN_SPEED, IN_USE)))
		brain.lastShotAt = now -- item 10: squad "down" callout timing
		hg.botdriver.lastFireAt[bot] = now -- section B/C: "target firing" perception + teammate glance
	end

	-- HUMANIZE: sv_gunhandling.lua crouch when stationary and firing beyond 900u.
	if hg.botdriver.gunhandling then
		buttons = hg.botdriver.gunhandling.ApplyCrouch(bot, brain, now, dist, buttons)
	end

	-- Teamplay known gap (2026-09-22): sv_squad.lua's OnReloadStart already
	-- stamps the nearest ally-with-LOS's brain.squadSuppressUntil and the
	-- extended brain.fireUntil above already keeps that ally shooting -- but
	-- nothing stopped it from ALSO closing distance on its own target mid-
	-- cover, which defeats the point of covering a squadmate that just went
	-- defenseless to reload. Hold this firing position instead for the
	-- window; a fight is still fought (fire/strafe), just not repositioned.
	if now < (brain.squadSuppressUntil or 0) then
		brain.path = nil
		if hg.botdriver.gunhandling and hg.botdriver.gunhandling.CombatStance then
			hg.botdriver.gunhandling.CombatStance(bot, brain, now, dist or 0, preferRange, aggrEff, now < brain.fireUntil)
		else
			brain.forward, brain.side = 0, 0
		end
	elseif (dist or 0) > preferRange * (1.5 - 0.4 * aggrEff) then
		lib.PathTo(bot, brain, target:GetPos(), now, 2)
	else
		brain.path = nil
		if ffBlocked then
			brain.forward = 0
			brain.side = (bot:EntIndex() % 2 == 0) and 220 or -220
		elseif hg.botdriver.gunhandling and hg.botdriver.gunhandling.CombatStance then
			-- HUMANIZE: sv_gunhandling.lua trait/range-based movement pattern
			-- (replaces the old fixed sine-wave strafe).
			hg.botdriver.gunhandling.CombatStance(bot, brain, now, dist or 0, preferRange, aggrEff, now < brain.fireUntil)
		else
			brain.forward = -150
			brain.side = math.sin(now * 2 + bot:EntIndex()) * 200
		end
	end

	-- 2026-09-26: lean habits (peek lean / strafe lean), authored after the
	-- stance above has picked this decision's strafe direction.
	if ghMod and ghMod.ApplyLean then
		buttons = ghMod.ApplyLean(bot, brain, now, dist, buttons)
	end

	return buttons
end

----------------------------------------------------------------------
-- Finalize: the single post-decision pass every behavior's finalize table
-- runs through.
----------------------------------------------------------------------

local function finalize(bot, brain, now, opts)
	local policy = brain.actionPolicy
	local locked = policy ~= nil and policy.lockMove == true
	if locked then
		brain.forward, brain.side = 0, 0
		brain.sprint = nil
	else
		if opts.roam and brain.state == "roam" then
			lib.Roam(bot, brain, now)
		end
		if opts.path then lib.FollowPath(bot, brain) end
		if opts.roam and brain.state == "roam" and not brain.path then lib.IdleScan(bot, brain, now) end
	end
	local buttons = lib.StuckCheck(bot, brain, now, brain.buttons or 0)
	if lib.StallWatch then lib.StallWatch(bot, brain, now) end
	if brain.traverseButtons then
		-- StallWatch may author a last-resort hop after StuckCheck consumed
		-- the previous traverse bits.
		buttons = bit.bor(buttons, brain.traverseButtons)
		brain.traverseButtons = nil
	end
	brain.buttons = buttons
end
lib.Finalize = finalize

----------------------------------------------------------------------
-- Scheduler: Think pops up to zc_bots_decide_budget decisions per tick,
-- earliest-due first.
----------------------------------------------------------------------

local function runDecision(bot, brain, now)
	local ok, err = xpcall(hg.botdriver.RunArbiter, debug.traceback, bot, brain, now)
	if not ok then
		-- A crashed decision leaves buttons/movement at zero (the bot stands
		-- still), so it must be visible: kept on the brain for
		-- zc_bots_diagnose, counted in zc_bots_stats, and written to
		-- data/zc_bots/errors.txt once per distinct first line.
		local text = tostring(err)
		local firstLine = string.match(text, "^[^\n]*") or text
		brain.lastDecisionError = firstLine
		brain.lastDecisionErrorAt = now
		brain.decisionErrorCount = (brain.decisionErrorCount or 0) + 1
		hg.botdriver.stats = hg.botdriver.stats or {}
		hg.botdriver.stats.decisionErrors = (hg.botdriver.stats.decisionErrors or 0) + 1
		-- Fallback keeps this path safe if sv_brain.lua is ever pushed without
		-- the sv_shim.lua that defines log.runtime.
		local logRuntime = hg.botdriver.log.runtime or hg.botdriver.log.error
		logRuntime("bots", "decide error for " .. tostring(IsValid(bot) and bot:Nick() or "?") .. ": " .. text, firstLine)
	end
	if now < (brain.meleeFastUntil or 0) then
		brain.nextDecide = now + 0.05
	else
		brain.nextDecide = now + 0.15 + (bot:EntIndex() % 3) * 0.02
	end
	hg.botdriver.ScheduleDecision(bot, brain, brain.nextDecide)
end

-- `selected`/`selectedDue` are reused across ticks (never reallocated) so
-- picking the earliest-due brains costs one full-roster pass plus a bounded
-- insertion into a `budget`-sized window, instead of copying the whole
-- scheduled set into a fresh array and sorting it every tick.
local selected = {}
local selectedDue = {}

hook.Add("Think", "zc_bots_brain_think", function()
	if not hg.botdriver.Enabled() then return end
	local now = CurTime()

	local budget = cv_decide_budget:GetInt()
	if budget <= 0 then return end

	local count = 0
	for brain, due in pairs(scheduled) do
		if due <= now then
			if count < budget then
				count = count + 1
				selected[count], selectedDue[count] = brain, due
				local i = count
				while i > 1 and selectedDue[i - 1] > selectedDue[i] do
					selected[i], selected[i - 1] = selected[i - 1], selected[i]
					selectedDue[i], selectedDue[i - 1] = selectedDue[i - 1], selectedDue[i]
					i = i - 1
				end
			elseif due < selectedDue[count] then
				selected[count], selectedDue[count] = brain, due
				local i = count
				while i > 1 and selectedDue[i - 1] > selectedDue[i] do
					selected[i], selected[i - 1] = selected[i - 1], selected[i]
					selectedDue[i], selectedDue[i - 1] = selectedDue[i - 1], selectedDue[i]
					i = i - 1
				end
			end
		end
	end

	-- Per-tick SysTime budget: stop running further decisions this tick once
	-- zc_bots_ms_budget has been spent, even if `count` selected brains remain.
	local msBudget = cv_ms_budget:GetFloat() / 1000
	local startTime = SysTime()
	for i = 1, count do
		if SysTime() - startTime < msBudget then
			local brain = selected[i]
			if scheduled[brain] and scheduled[brain] <= now then
				local bot = brain.bot
				if IsValid(bot) and bot:Alive() and bot:IsBot() and bot.zcBot then
					runDecision(bot, brain, now)
				else
					hg.botdriver.UnscheduleDecision(brain)
				end
			end
		end
		selected[i] = nil
		selectedDue[i] = nil
	end
end)

-- Rehydrate existing live brains on a first upgrade from the old local scheduler.
for bot, brain in pairs(hg.botdriver.brains) do
 if IsValid(bot) and bot:IsBot() and bot.zcBot and bot:Alive() and not bot.zcBotBenched then
  hg.botdriver.ScheduleDecision(bot, brain, 0)
 else
  hg.botdriver.UnscheduleDecision(brain)
 end
end
