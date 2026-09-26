-- Firearm humanisation: US1 recoil is client-only and bots have none, so this
-- file adds the human-ish shooting texture (reaction delay, burst discipline,
-- aim-error growth under sustained fire/pain/injury, crouch-and-hold at range,
-- reload discipline) on top of lib.Engage's existing fire-control state
-- machine in sv_brain.lua. Loads after sv_brain.lua (loader order) and is
-- called from a small number of clearly-marked hooks left in Engage rather
-- than by rewriting it.
--
-- Every entry point here is optional at the call site (`local gh =
-- hg.botdriver.gunhandling; if gh then ... end`), so Engage keeps working
-- unchanged if this file is ever removed.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}
hg.botdriver.gunhandling = hg.botdriver.gunhandling or {}
local gh = hg.botdriver.gunhandling

hg.botdriver.DeclareBrainState("gunhandling", { fields = {
	"gunHadLOS", "gunBurstAt", "gunErrMult", "gunErrMultTarget", "gunErrMultAt", "gunLastTargetAt",
	"reloadCoverAt", "reloadCoverPos", "cmStrafeDir", "cmStrafeUntil", "cmShiftAt",
	"cmShiftUntil", "reloadCoverTarget",
	-- 2026-09-23: peek cycle (D2), fake-out duck (D3), close-quarters swap (D4)
	"peekCheckAt", "peekCoverDir", "peekStepUntil", "peekHiddenUntil", "peekNextHideAt", "peekOutUntil",
	"fakeDuckAt", "fakeDuckUntil", "cqSwapAt",
} })

----------------------------------------------------------------------
-- D4 (2026-09-23): dry clip at close range -> pull a loaded secondary, else
-- the knife/fists, instead of reloading in the target's face. Called from
-- lib.Engage's dry-clip branch. One swap per 2 s so it never ping-pongs.
----------------------------------------------------------------------

function gh.CloseQuartersSwap(bot, brain, now, dryWep)
	if now < (brain.cqSwapAt or 0) then return false end
	local pick
	for _, w in ipairs(bot:GetWeapons()) do
		if IsValid(w) and w ~= dryWep and not w.ismelee and hg.botdriver.IsGun and hg.botdriver.IsGun(w)
			and w.Clip1 and (w:Clip1() or 0) > 0 then
			pick = w:GetClass()
			break
		end
	end
	if not pick and hg.botdriver.HasMelee then pick = hg.botdriver.HasMelee(bot) end
	if not pick then return false end
	brain.cqSwapAt = now + 2
	brain.wepSwitchAt = now
	bot:SelectWeapon(pick)
	hg.botdriver.stats = hg.botdriver.stats or {}
	hg.botdriver.stats.closeSwaps = (hg.botdriver.stats.closeSwaps or 0) + 1
	return true
end

----------------------------------------------------------------------
-- Reaction delay: first shot after a target is (re)acquired is held back
-- 0.25-0.45s, scaled by (1.5 - skill) so a low-skill bot reacts slower.
-- PERSONALITY: further scaled by the bot's own reactionMult trait
-- (sv_personality.lua), 0.8-1.4.
----------------------------------------------------------------------

function gh.OnAcquire(brain, now, skill)
	local reactMult = (brain.personality and brain.personality.reactionMult) or 1
	local delay = math.Rand(0.25, 0.45) * (1.5 - (skill or 0.5)) * reactMult
	brain.fireAfter = math.max(brain.fireAfter or 0, now + delay)
end

function gh.OnLOSLost(brain)
	brain.gunHadLOS = false
end

----------------------------------------------------------------------
-- Burst discipline for Primary.Automatic weapons: 3-5 rounds beyond 600u,
-- 5-9 inside 600u, single taps beyond 1500u, with a 0.25-0.6s pause between
-- bursts. Converts a round count to a hold duration using the weapon's own
-- fire delay rather than counting bullets fired.
----------------------------------------------------------------------

function gh.BurstFire(bot, brain, now, skill, wep, dist, aggr, scared, onTarget)
	if now <= (brain.fireUntil or 0) then return end -- mid-burst, let it run
	if now <= (brain.fireAfter or 0) then return end -- in the inter-burst pause
	if not onTarget then return end

	local minRounds, maxRounds
	if dist > 1500 then
		minRounds, maxRounds = 1, 1
	elseif dist > 600 then
		minRounds, maxRounds = 3, 5
	else
		minRounds, maxRounds = 5, 9
	end

	local rounds = math.random(minRounds, maxRounds)
	-- homigrad_base weapons define Primary.Wait (seconds between shots); none
	-- define Primary.Delay, so every burst used to fall back to 0.1s.
	local prim = wep.Primary
	local fireDelay = (prim and (tonumber(prim.Wait) or tonumber(prim.Delay))) or 0.1
	local burstTime = rounds * math.max(fireDelay, 0.03)

	brain.gunBurstAt = now
	brain.fireUntil = now + burstTime * (1 - 0.3 * (scared or 0))
	local pause = math.Rand(0.25, 0.6) * (1 + 0.4 * (scared or 0)) * (1.3 - 0.5 * (aggr or 0.5))
	brain.fireAfter = brain.fireUntil + pause
end

----------------------------------------------------------------------
-- Aim error multiplier: grows with how far into the current burst we are,
-- with range, with organism pain (org.pain/100) and right-arm injury
-- (org.rarm), and decays smoothly back toward 1 between bursts.
----------------------------------------------------------------------

function gh.AimErrorMultiplier(bot, brain, now, dist)
	local burstFrac = 0
	if brain.gunBurstAt and brain.fireUntil and brain.fireUntil > brain.gunBurstAt then
		burstFrac = math.Clamp((now - brain.gunBurstAt) / (brain.fireUntil - brain.gunBurstAt), 0, 1)
	end
	local rangeTerm = math.Clamp((dist or 0) / 2000, 0, 1)

	local org = bot.organism
	local pain = math.Clamp((org and tonumber(org.pain) or 0) / 100, 0, 1)
	-- PROVISIONAL(2026-09-21, org.rarm's scale/units were not verified against
	-- an organism source file in this session -- treated defensively as a
	-- 0..100-ish injury score like org.pain and clamped either way,
	-- ratify-by: 2026-10-15)
	local rarm = math.Clamp((org and tonumber(org.rarm) or 0) / 100, 0, 1)

	local target = 1 + 0.6 * burstFrac + 0.3 * rangeTerm + 0.5 * pain + 0.4 * rarm
	brain.gunErrMultTarget = target
	-- Real elapsed time between calls: this runs at decision rate (~6 Hz), so
	-- FrameTime() (one server tick) made the approach ~10x slower than meant.
	local dt = math.Clamp(now - (brain.gunErrMultAt or now), 0, 0.5)
	brain.gunErrMultAt = now
	brain.gunErrMult = math.Approach(brain.gunErrMult or 1, target, 2 * dt)
	return brain.gunErrMult
end

----------------------------------------------------------------------
-- Crouch when stationary and firing beyond 900u.
----------------------------------------------------------------------

function gh.ApplyCrouch(bot, brain, now, dist, buttons)
	-- D3 (2026-09-23): a short crouch-toggle while strafing under return fire
	-- (hit within the last 2 s) -- the twitchy "make yourself a harder
	-- target" habit. Never on its own without incoming damage, never while
	-- sprinting, at most one per 0.8-2 s.
	if (dist or 0) < 900 and now - (brain.damageAt or -math.huge) < 2 and not brain.sprint then
		if now >= (brain.fakeDuckAt or 0) then
			brain.fakeDuckAt = now + math.Rand(0.8, 2.0)
			brain.fakeDuckUntil = now + math.Rand(0.25, 0.55)
		end
		if now < (brain.fakeDuckUntil or 0) then buttons = bit.bor(buttons, IN_DUCK) end
	end
	local stationary = math.abs(brain.forward or 0) < 1 and math.abs(brain.side or 0) < 1
		and bot:GetVelocity():Length2DSqr() < 40 * 40
	if stationary and (dist or 0) > 900 and now < (brain.fireUntil or 0) then
		-- Low cover only helps while we can shoot over it. Do not crouch the
		-- muzzle behind the very obstacle chosen as a firing position.
		if isvector(brain.lookPos) then
			local sight = util.TraceLine({start = bot:GetPos() + Vector(0, 0, 28), endpos = brain.lookPos,
				filter = {bot, brain.target}, mask = MASK_SHOT})
			if not sight.Hit then buttons = bit.bor(buttons, IN_DUCK) end
		end
	end
	return buttons
end

----------------------------------------------------------------------
-- Reload discipline: prefer to reload only when no enemy is visible or after
-- backing out of LOS. When forced to reload with an enemy still visible and
-- within 1200u (dry clip, reserve available), head for cover via
-- sv_cover.lua's lib.FindCover (1.5s cadence, same as its other callers);
-- otherwise fall back to strafing/backing toward the previous path node
-- (away from the target) while the reload runs.
----------------------------------------------------------------------

function gh.RetreatWhileReloading(bot, brain, now, target, dist)
	local lib = hg.botdriver.lib
	if brain.reloadCoverTarget ~= target then
		brain.reloadCoverTarget, brain.reloadCoverPos, brain.reloadCoverAt = target, nil, 0
	end

	if IsValid(target) and (dist or 0) < 1200 and lib and lib.FindCover then
		if now >= (brain.reloadCoverAt or 0) then
			brain.reloadCoverAt = now + 1.5
			brain.reloadCoverPos = lib.FindCover(bot, target, 700, "retreat")
		end
		if isvector(brain.reloadCoverPos) then
			if bot:GetPos():DistToSqr(brain.reloadCoverPos) < 48 * 48 then
				brain.path = nil
				brain.forward, brain.side = 0, 0
				return
			end
			lib.PathTo(bot, brain, brain.reloadCoverPos, now, 1)
			if brain.path then return end
		end
	end

	brain.forward = -180
	brain.side = (bot:EntIndex() % 2 == 0) and 120 or -120
	brain.path = nil
	brain.moveAngles = IsValid(target) and Angle(0, (target:GetPos() - bot:GetPos()):Angle().y, 0)
		or Angle(0, bot:EyeAngles().y, 0)
	if lib.SafeCombatMove then lib.SafeCombatMove(bot, brain, now) end
end

----------------------------------------------------------------------
-- Combat movement (item 7): replaces the old fixed sine-wave strafe with a
-- trait/range-based pattern. Called from sv_brain.lua's Engage once per
-- decision (~6Hz), never from StartCommand, so the one throttled trace pair
-- below (edge probe, only on a strafe-direction change) stays inside the
-- decision budget.
--
--   far   (> preferRange*0.75): stand/crouch and burst; shift 1-2 steps
--         between bursts.
--   mid   (350..preferRange*0.75): held strafe direction (0.6-1.6s, random
--         reversal); freeze the first 0.25s of a burst past 700u, mirroring
--         an accuracy-minded player counter-strafing to shoot.
--   close (< 350): continuous strafe. Never jumps -- no bunny-hopping.
--
-- Edge probe: sv_nav.lua/sv_traverse.lua expose no ledge-check (grepped both
-- files -- only sv_traverse.lua's short obstacle hop exists), so this is a
-- bespoke one-trace-per-direction-change check: a strafe direction is
-- dropped if the ground falls away more than EDGE_DROP units under a
-- EDGE_SIDE-unit sidestep.
----------------------------------------------------------------------

local CLOSE_RANGE = 350
local EDGE_SIDE = 40
local EDGE_DROP = 72

local function edgeDrops(bot, dir)
	local pos = bot:GetPos()
	local right = bot:EyeAngles():Right() * dir
	local origin = pos + right * EDGE_SIDE + Vector(0, 0, 4)
	local tr = util.TraceLine({
		start = origin,
		endpos = origin - Vector(0, 0, EDGE_DROP),
		filter = bot,
		mask = MASK_PLAYERSOLID,
	})
	return not tr.Hit
end

-- Picks/holds a strafe direction (+1/-1, or 0 if both sides drop off), only
-- re-tracing when the held duration expires.
local function pickStrafeDir(bot, brain, now)
	if brain.cmStrafeDir and now < (brain.cmStrafeUntil or 0) then return brain.cmStrafeDir end

	local dir = (brain.cmStrafeDir == -1) and 1 or -1
	if edgeDrops(bot, dir) then
		dir = -dir
		if edgeDrops(bot, dir) then dir = 0 end
	end
	brain.cmStrafeDir = dir
	brain.cmStrafeUntil = now + math.Rand(0.6, 1.6)
	return dir
end

----------------------------------------------------------------------
-- D2 (2026-09-23): peek cycle. At mid range, if a 44 u sidestep to one side
-- breaks line of sight to the aim point (i.e. the bot is at a corner/edge of
-- cover), alternate: step into cover, hold hidden 0.6-1.4 s (patience-scaled),
-- step back out and fight. One trace pair per second per bot at most. While
-- hidden the target is legitimately lost (sv_control's LOS gate), so the
-- COMBAT-band `combat.peek_hold` behaviour below keeps the bot still until
-- the hidden window ends; support.investigate/engage then walk it back out.
----------------------------------------------------------------------

local PEEK_SIDE = 44

local function peekCoverDir(bot, brain)
	if not isvector(brain.lookPos) then return 0 end
	local eye = bot:EyePos()
	local right = bot:EyeAngles():Right()
	for _, dir in ipairs({ 1, -1 }) do
		local origin = eye + right * (dir * PEEK_SIDE)
		local tr = util.TraceLine({ start = origin, endpos = brain.lookPos, filter = { bot, brain.target }, mask = MASK_SHOT })
		if tr.Hit then
			if not edgeDrops(bot, dir) then return dir end
		end
	end
	return 0
end

local function peekStep(bot, brain, now, firing)
	if now >= (brain.peekCheckAt or 0) then
		brain.peekCheckAt = now + 1.0
		brain.peekCoverDir = peekCoverDir(bot, brain)
	end
	local dir = brain.peekCoverDir or 0
	if dir == 0 then return false end
	if now < (brain.peekOutUntil or 0) then
		brain.forward, brain.side = 0, -dir * 160 -- stepping back out
		return true
	end
	if now < (brain.peekStepUntil or 0) then
		brain.forward, brain.side = 0, dir * 160 -- stepping into cover
		return true
	end
	if now >= (brain.peekNextHideAt or 0) and not firing then
		local patience = (brain.personality and brain.personality.patience) or 1
		brain.peekStepUntil = now + 0.3
		brain.peekHiddenUntil = now + 0.3 + math.Rand(0.6, 1.4) * patience
		brain.peekOutUntil = brain.peekHiddenUntil + 0.3
		brain.peekNextHideAt = brain.peekOutUntil + math.Rand(1.2, 3.0)
		brain.forward, brain.side = 0, dir * 160
		hg.botdriver.stats = hg.botdriver.stats or {}
		hg.botdriver.stats.peeks = (hg.botdriver.stats.peeks or 0) + 1
		return true
	end
	return false
end

hg.botdriver.RegisterBehavior({
	name = "combat.peek_hold",
	band = "COMBAT",
	order = 10, -- before combat.engage (20): a hidden bot stays hidden
	finalize = {},
	CanRun = function(ctx)
		local brain = ctx.brain
		return ctx.now >= (brain.peekStepUntil or 0) and ctx.now < (brain.peekHiddenUntil or 0)
			and not IsValid(ctx:AcquireTarget())
	end,
	Run = function(ctx)
		local brain = ctx.brain
		brain.path = nil
		brain.forward, brain.side = 0, 0
		brain.state = "engage"
		if isvector(brain.lastSeenPos) then
			hg.botdriver.lib.LookAt(ctx.bot, brain, brain.lastSeenPos + Vector(0, 0, 56), "peek", false)
		end
		return true
	end,
})

local function combatStance(bot, brain, now, dist, preferRange, aggr, firing)
	if dist < CLOSE_RANGE then
		local dir = pickStrafeDir(bot, brain, now)
		brain.forward = dist < math.min(180, preferRange * 0.4) and -180 or 0
		brain.side = dir * 220
		return
	end

	if dist <= preferRange * 0.75 then
		if peekStep(bot, brain, now, firing) then return end
		local dir = pickStrafeDir(bot, brain, now)
		local freezing = firing and dist > 700 and (now - (brain.gunBurstAt or -math.huge)) < 0.25
		brain.forward = 0
		brain.side = freezing and 0 or dir * 200
		return
	end

	-- Far: stand/crouch (sv_brain.lua's Engage adds IN_DUCK via ApplyCrouch)
	-- and shoot in bursts; shift 1-2 short steps between bursts, never while
	-- actively firing.
	brain.forward, brain.side = 0, 0
	if not firing and now >= (brain.cmShiftAt or 0) then
		brain.cmShiftAt = now + math.Rand(1.2, 2.6)
		brain.cmShiftUntil = now + math.Rand(0.3, 0.5)
	end
	if not firing and now < (brain.cmShiftUntil or 0) then
		brain.side = pickStrafeDir(bot, brain, now) * 150
	end
end

function gh.CombatStance(bot, brain, now, dist, preferRange, aggr, firing)
	brain.path = nil
	-- Movement is relative to the observed threat, not lagging eye yaw.
	if isvector(brain.lookPos) then
		brain.moveAngles = Angle(0, (brain.lookPos - bot:GetPos()):Angle().y, 0)
	end
	combatStance(bot, brain, now, dist, preferRange, aggr, firing)
	if hg.botdriver.lib.SafeCombatMove then hg.botdriver.lib.SafeCombatMove(bot, brain, now) end
end

----------------------------------------------------------------------
-- 2026-09-26 presentation parity: the lean keys. US1 leans on IN_ALT1
-- (right) / IN_ALT2 (left) (weapons/homigrad_base/sh_anim.lua "Bones"
-- hook: server reads KeyDown, bends spine/head/arm bones, networks
-- PlayerLean). Nothing in this package ever pressed them, so a bot was the
-- only "player" on the server that never leaned. Two habits:
--   * peek lean: after the D2 peek cycle steps back out from cover, lean
--     away from the cover for the rest of that exposure;
--   * strafe lean: some players lean into their strafe in a close/mid
--     fight. Rolled per strafe segment, so it comes and goes.
-- How much a bot leans at all is a per-personality habit (leanHabit),
-- rolled lazily so existing personalities pick it up without a re-roll.
----------------------------------------------------------------------

hg.botdriver.DeclareBrainState("gunhandling_lean", { fields = { "leanSegDir", "leanSegOn" } })

local LEAN_HABIT = { tryhard = { .55, .9 }, oldhand = { .5, .85 }, hothead = { .3, .7 }, gremlin = { .3, .75 } }

function gh.LeanHabit(brain)
	local p = brain.personality
	if not p then return 0.3 end
	if not p.leanHabit then
		local range = LEAN_HABIT[p.archetype] or { .1, .6 }
		p.leanHabit = math.Rand(range[1], range[2])
	end
	return p.leanHabit
end

local function leanKey(dir)
	return dir > 0 and IN_ALT1 or IN_ALT2
end

function gh.ApplyLean(bot, brain, now, dist, buttons)
	if bit.band(buttons, IN_SPEED) ~= 0 then return buttons end
	local habit = gh.LeanHabit(brain)
	local peekDir = brain.peekCoverDir or 0
	if peekDir ~= 0 and now >= (brain.peekStepUntil or 0) and now < (brain.peekNextHideAt or 0)
		and (now >= (brain.peekHiddenUntil or 0)) and habit > 0.35 then
		return bit.bor(buttons, leanKey(-peekDir))
	end
	local strafeDir = brain.cmStrafeDir or 0
	if strafeDir ~= 0 and (dist or 0) < 900 then
		if brain.leanSegDir ~= strafeDir then
			brain.leanSegDir = strafeDir
			brain.leanSegOn = math.random() < habit * 0.45
		end
		if brain.leanSegOn then return bit.bor(buttons, leanKey(strafeDir)) end
	end
	return buttons
end

----------------------------------------------------------------------
-- 2026-09-26: tube-fed shotguns and stripper-clip rifles (the US1 SWEPs
-- whose Reload runs the "shootgunReload" insert loop) only keep inserting
-- while IN_RELOAD is still HELD when each shell lands
-- (weapon_remington870.lua reloadFunc: hg.KeyDown(owner, IN_RELOAD)). The
-- dry-clip branch stopped asking for IN_RELOAD the moment one shell was in,
-- so bots fought an entire round one shell at a time -- start anim, one
-- shell, fire, repeat -- which no person does. A loader now commits to a
-- shell goal: a few under pressure, the whole tube when nobody is around.
----------------------------------------------------------------------

local SHELL_LOADERS = {
	weapon_remington870 = true, weapon_remington870_roullet = true, weapon_m590a1 = true,
	weapon_spas12 = true, weapon_xm1014 = true, weapon_ks23 = true,
	weapon_kar98 = true, weapon_mosin = true,
}

hg.botdriver.DeclareBrainState("gunhandling_shells", { fields = { "shellGoal" } })

function gh.IsShellLoader(wep)
	if not IsValid(wep) then return false end
	return SHELL_LOADERS[wep:GetClass()] == true
end

local function clipInfo(wep)
	local clip = wep:Clip1() or 0
	local size = (wep.GetMaxClip1 and wep:GetMaxClip1()) or (wep.Primary and wep.Primary.ClipSize) or math.max(clip, 1)
	return clip, math.max(size, 1)
end

-- Called when a loader starts reloading. Under fire it wants enough to win
-- the next exchange; patient bots and long ranges load a little more.
function gh.SetShellGoal(bot, brain, wep, underFire, dist)
	if not gh.IsShellLoader(wep) then return end
	local _, size = clipInfo(wep)
	if not underFire then
		brain.shellGoal = size
		return
	end
	local patience = (brain.personality and brain.personality.patience) or 1
	local goal = 2 + math.floor(patience * 1.5 + math.random()) + ((dist or 0) > 900 and 2 or 0)
	brain.shellGoal = math.min(size, goal)
end

-- True while a loader should keep IN_RELOAD held instead of firing: a reload
-- is in progress and the goal is not reached, unless the target is already
-- close enough that a person would stop loading and shoot what they have.
function gh.ShellReloadHold(bot, brain, now, wep, dist)
	if not gh.IsShellLoader(wep) or not wep.GetNetVar then return false end
	if (wep:GetNetVar("shootgunReload", 0) or 0) <= now then
		brain.shellGoal = nil
		return false
	end
	local clip, size = clipInfo(wep)
	local goal = brain.shellGoal or size
	-- A quiet top-up that gets interrupted by a visible enemy settles for a
	-- few shells rather than finishing the whole tube in their sights.
	if (dist or math.huge) < 1500 then goal = math.min(goal, 4) end
	if clip >= goal then return false end
	if clip >= 1 and (dist or math.huge) < 380 then return false end
	return true
end

----------------------------------------------------------------------
-- 2026-09-26: launcher self-preservation. rpg_projectile.lua blasts ~7 m
-- (BlastDis 7, ~367 u) and does not even arm inside SafetyDistance (the same
-- 7 m); weapon_hg_rpg.lua also burns anything in a 128 u cone BEHIND the
-- shooter. EquipForRange only excluded launchers under 200 u, so a bot fired
-- rockets at point blank or into a wall in front of its own face, and
-- happily torched a teammate standing behind it. Hold fire (and open the
-- distance) instead.
----------------------------------------------------------------------

local LAUNCHER_MIN = 520
local BACKBLAST = 150

function gh.LauncherUnsafe(bot, brain, wep, dist, aimPos, allyOf)
	local prof = hg.botdriver.WeaponProfile and hg.botdriver.WeaponProfile(wep)
	if not prof or prof.role ~= "launcher" then return false end
	if (dist or 0) < LAUNCHER_MIN then return true end
	local eye = bot:EyePos()
	if isvector(aimPos) then
		local tr = util.TraceLine({ start = eye, endpos = aimPos, filter = { bot, brain.target }, mask = MASK_SHOT })
		if tr.Hit and tr.HitPos:DistToSqr(eye) < LAUNCHER_MIN * LAUNCHER_MIN then return true end
	end
	if allyOf then
		local back = -bot:GetAimVector()
		for _, ply in ipairs(player.GetAll()) do
			if ply ~= bot and ply:Alive() and allyOf(ply) then
				local delta = ply:GetPos() + Vector(0, 0, 40) - eye
				local d = delta:Length()
				if d < BACKBLAST and d > 1 and back:Dot(delta / d) > 0.6 then return true end
			end
		end
	end
	return false
end

----------------------------------------------------------------------
-- Top-up reload: when a bot has had no target for 3s and its active gun's
-- clip is under 50%, tap a reload without waiting for a dry clip. Runs as a
-- non-exclusive SUPPORT-band pass (mirrors reflex.damage-response's pattern
-- of always declining ownership so ACQUIRE/IDLE still drive the tick).
--
-- Section F (human mistakes): a tidy bot also sometimes tops up almost
-- immediately after losing its target (0.15-0.5s, not the full 3s wait)
-- even with only half a mag spent and even while another enemy may already
-- be near -- a small, bounded, never-suicidal habit (it only ever taps a
-- reload, never blocks re-engaging next decision), scaled by both the
-- tidiness trait and the global zc_bots_humanize convar.
----------------------------------------------------------------------

hg.botdriver.DeclareBrainState("gunhandling_mistakes", { fields = {
	"topupQuirkAt", "topupQuirkLastSeen", "topupQuirkRolled",
} })

hg.botdriver.RegisterBehavior({
	name = "gunhandling.topup_reload",
	band = "SUPPORT",
	order = 5,
	finalize = false,
	CanRun = function(ctx)
		return not IsValid(ctx.brain.target)
	end,
	Run = function(ctx)
		local brain, bot, now = ctx.brain, ctx.bot, ctx.now
		local lastSeen = brain.lastSeenTime or 0

		local humanize = hg.botdriver.cv_humanize and hg.botdriver.cv_humanize:GetFloat() or 1
		local tidiness = (brain.personality and brain.personality.tidiness) or 0.5
		if brain.topupQuirkLastSeen ~= lastSeen then
			brain.topupQuirkLastSeen = lastSeen
			brain.topupQuirkAt = lastSeen + math.Rand(0.15, 0.5)
			brain.topupQuirkRolled = false
		end
		local dueForRoll = now - lastSeen < 3 and not brain.topupQuirkRolled and now >= (brain.topupQuirkAt or math.huge)
		local tidyQuirk = false
		if dueForRoll then
			brain.topupQuirkRolled = true
			tidyQuirk = math.random() < tidiness * 0.5 * humanize
		end
		if not tidyQuirk and now - lastSeen < 3 then return false end

		local wep = bot:GetActiveWeapon()
		if not IsValid(wep) or wep.ismelee or not wep.Clip1 then return false end
		if now < (wep.GetNextPrimaryFire and wep:GetNextPrimaryFire() or 0) then return false end

		local clip = wep:Clip1() or 0
		local clipSize = (wep.GetMaxClip1 and wep:GetMaxClip1()) or (wep.Primary and wep.Primary.ClipSize) or math.max(clip, 1)
		-- The quirk fires even on a near-full mag; a shell loader is always
		-- topped off when it is quiet (and must keep R held to do it).
		local loader = gh.IsShellLoader(wep)
		local threshold = (tidyQuirk or loader) and 1.0 or 0.5
		if clipSize <= 0 or clip / clipSize >= threshold then return false end

		local reserve = hg.botdriver.EffectiveReserve and hg.botdriver.EffectiveReserve(bot, wep) or 0
		if reserve <= 0 then return false end

		if loader then brain.shellGoal = clipSize end
		brain.buttons = bit.bor(brain.buttons or 0, IN_RELOAD)
		return false -- never claims the tick; IDLE/ACQUIRE still run this pass
	end,
})
