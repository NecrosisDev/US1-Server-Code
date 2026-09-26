-- Criresp mode wiring (Part A.2 base + 2026-09-21 mode-expansion pass). Round
-- key "criresp" (US1 modes/criresp/sv_criresp.lua:1, MODE.name).
--
-- Facts verified this session (work/bots/us1/addons/zcity/gamemodes/zcity/
-- gamemode/modes/criresp/{sv,sh}_criresp.lua):
--   * Team 0 = SWAT, team 1 = Suspects (AssignTeams, sv_criresp.lua:21-51).
--     Suspects spawn immediately -- MODE:Intermission kills team 0/spectator
--     and SetupTeam()s everyone else (sv_criresp.lua:59-62). SWAT does NOT
--     spawn at round start: each SWAT ply gets its own
--     timer.Create("SWATSpawn"..EntIndex, 90, 1, ...) in GiveEquipment
--     (sv_criresp.lua:171-213); a single random SWAT survivor is given
--     weapon_ram at t=91s (sv_criresp.lua:246-252).
--   * Win condition: MODE:ShouldRoundEnd -> CheckAlivePlayers's alive test is
--     `ply:Alive() and not ply:GetNetVar("handcuffed", false)`
--     (sv_criresp.lua:74,80) -- cuffing a suspect removes them from the alive
--     count, the same as a kill. ShouldRoundEnd also hard-blocks any round
--     end before zb.ROUND_START+91 (sv_criresp.lua:93).
--   * weapon_hammer (main-design-source/lua/weapons/weapon_hammer.lua):
--     SecondaryAttack (IN_ATTACK2) while SWEP.AttackMode==1 (the default; the
--     only way to change it is holding IN_ATTACK+IN_RELOAD together,
--     ThinkAdd:116-124 -- never done here) nails whatever is under the
--     crosshair (hg.eyeTrace, ~60u default range -- sh_utility.lua:834's
--     `hg.eye(..., dist or 60)`). Aimed at a door (hgIsDoor, defined
--     main-design-source/lua/homigrad/sv_util.lua) it SEALS the door shut
--     (Fire("lock"), LockedDoorNail=true, weapon_hammer.lua:325-346), costing
--     3 nails for a non-builder (`> (builder and 1 or 2)`, line 326);
--     OwnerChanged gives a fresh hammer exactly 3 Nails (lines 244-254) -- one
--     door-seal per hammer, no more. Aimed at two nearby non-player/NPC props
--     instead it nails them together (BindObjects, lines 128-188), which
--     needs a second distinct entity inside a ~1u jitter cone at 60u -- not
--     something a bot can aim reliably, so only the door-seal case is driven
--     here.
--   * weapon_ducttape (Base weapon_tpik_base, main-design-source/lua/weapons/
--     weapon_ducttape.lua): holding PrimaryAttack (IN_ATTACK, not IN_SPEED)
--     aimed at a door charges SetHolding() 25->100 over ~75 held ticks
--     (Think/PrimaryAttack, lines 155-160, 279-345); at 100 it seals the door
--     the same way the hammer does and consumes the whole roll (TapeAmount -=
--     100, self:Remove() once spent) -- also one door-seal, needs a
--     continuous ~1.5-2s hold instead of a single press.
--   * weapon_handcuffs (work/bots/us1/addons/zcity/lua/weapons/
--     weapon_handcuffs.lua): PrimaryAttack (IN_ATTACK, Automatic=false, 2s
--     SWEP.CoolDown) plays the "attack" anim, whose own callback (AnimList
--     "attack", lines 48-52) re-traces (hg.eyeTrace, same ~60u default) and
--     calls self:Tie(tr). Tie() requires the traced entity within 500u AND
--     `ent:IsRagdoll() or (ent:IsPlayer() and ent:GetVelocity():Length()<1)`
--     (line 153) -- the same shape hg.botdriver.IsDowned already tests
--     (ragdoll/FakeRagdoll). On success both organism/NetVar get
--     handcuffed=true, both players are force-switched to weapon_hands_sh,
--     and the handcuffs self:Remove()s (single use).
--     PROVISIONAL(2026-09-21, the exact anim-callback delay before Tie()
--     fires was not traced past the AnimList entry's own 2.5s/0.5s
--     CallbackTimeAdjust fields -- this file holds the bot in place, facing
--     the target, for a fixed wait budget comfortably longer than that
--     estimate rather than the exact figure, ratify-by: 2026-10-15)
--   * weapon_ram: referenced only as a class string across this addon tree
--     (sv_criresp.lua:250, riot/sv_riot.lua:180, homicide/sv_homicide.lua:1520,
--     tdm's buy menu sh_tdm.lua:156) -- grepped BOTH
--     work/main-design-source/lua/weapons/ and work/bots/us1/addons/**/lua/
--     for a weapon_ram.lua definition and found none in either tree (a
--     genuine absence in this snapshot, not an invented one). Its actual
--     PrimaryAttack/breach behaviour is UNVERIFIED -- this file never drives
--     it; a ram holder is only ever preferred for the squad's point slot
--     (sv_squad.lua), same as any other point bot would be.
--   * weapon_hg_flashbang_tpik (CORRECTED 2026-09-22 -- the prior "absence
--     class as weapon_ram" note above was wrong, from an incomplete earlier
--     search; re-grepped this session and the file exists at
--     work/main-design-source/lua/weapons/weapon_hg_flashbang_tpik.lua):
--     `SWEP.Base = "weapon_hg_grenade_tpik"` -- the exact same base
--     sv_grenade.lua's three verified frag classes already build on. Its own
--     "attack" AnimList callback (the high/IN_ATTACK throw) calls
--     `self:Throw(1200, ...)` (weapon_hg_flashbang_tpik.lua:66) -- IDENTICAL
--     to sv_grenade.lua's own verified THROW_SPEED=1200 for
--     weapon_hg_grenade_tpik's primary throw, not a guess. FLASHBANG_THROW_SPEED
--     below is now pinned to that verified value instead of the previous
--     provisional 1000.
--
-- BEHAVIOUR CHOICES (not dictated by the brief -- see final report):
--   * Suspect posts are built with the same bounded navmesh.Find + visibility
--     -sort technique modes/sv_defense.lua's buildPosts already established
--     in this codebase for "posts near an objective, preferring cover from a
--     known approach direction" -- NOT a literal lib.FindCover call, since
--     FindCover requires a live threatEnt and none exists before SWAT spawns.
--   * mode.tdm_squad_push (the base file's only behavior) is dropped for
--     criresp: it would pull suspects toward the freshest team contact,
--     directly against "should NOT leave the defended area to hunt SWAT".
--     SWAT's own systematic-clear objective replaces its role as a push.
--   * survival.outnumbered (behaviors/sv_outnumbered.lua, default-on for any
--     team mode) already gives the "fall back when outnumbered" behaviour the
--     brief asks to reuse -- nothing added here.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}
local RB = hg.botdriver.RegisterBehavior
local lib = hg.botdriver.lib

hg.botdriver.DeclareBrainState("criresp", { fields = {
	"crirespPosts", "crirespPostIdx", "crirespRoamer", "crirespNextPostSwitch",
	"crirespFortifyState", "crirespFortifyDoor", "crirespFortifyStartedAt", "crirespFortifyUntil", "crirespFortified",
	"crirespClearArea", "crirespClearAreaSince",
	"crirespArrestTarget", "crirespArrestState", "crirespArrestUntil",
	"crirespFlashbangCooldownAt", "crirespFlashbangLanding",
} })

local SETUP_DEADLINE = 85       -- SWAT's own 90s spawn timer minus a safety margin
local FORTIFY_GIVEUP = 12
local FORTIFY_RANGE = 90
local FORTIFY_ALIGN_TIME = 0.3
local FORTIFY_HAMMER_HOLD = 0.6
local FORTIFY_TAPE_HOLD = 2.6   -- comfortably past the ~1.5-2s charge estimate above

local POST_RADIUS = 1400
local POST_MIN_SEPARATION = 250
local RETURN_LEASH = 900
local ROAM_INTERVAL_MIN, ROAM_INTERVAL_MAX = 12, 22

local ARREST_RANGE = 55         -- inside hg.eyeTrace's ~60u default (see header)
local ARREST_ALIGN_TIME = 0.2
local ARREST_WAIT_BUDGET = 3.0  -- PROVISIONAL, see header
local ARREST_THREAT_RANGE = 700

local FLASHBANG_TRIGGER_RANGE = 500
local FLASHBANG_COOLDOWN = 45
local FLASHBANG_THROW_SPEED = 1200 -- verified: weapon_hg_flashbang_tpik's own "attack" throw (see header, 2026-09-22 correction)
local FLASHBANG_WINDUP = 0.6

local CLEAR_HOLD_TIME = 2.0
local CLEAR_ARRIVE_RADIUS = 140
local CLEAR_SCAN_RADIUS = 2000
local STACK_OFFSET = 140

-- Per-round shared bookkeeping, reset at ZB_StartRound below. Bounded by the
-- (finite, static) map's own point/player/nav-area counts, never grown
-- unboundedly.
local suspectPosts = {}
local clearedAreas = {}
local arrestClaims = {}
local sealedDoors = setmetatable({}, { __mode = "k" })

hook.Add("ZB_StartRound", "zc_bots_criresp_round_reset", function()
	local roundKey = zb and (zb.CROUND_MAIN or zb.CROUND)
	if roundKey ~= "criresp" then return end
	suspectPosts, clearedAreas, arrestClaims = {}, {}, {}
	sealedDoors = setmetatable({}, { __mode = "k" })
end)

----------------------------------------------------------------------
-- A: Suspects -- defensive posts, fortification, hold/patrol.
----------------------------------------------------------------------

local function buildSuspectPosts()
	if not (zb and zb.GetMapPoints and navmesh and navmesh.Find) then return {} end
	local tPts = zb.GetMapPoints("HMCD_CRI_T")
	if not istable(tPts) or #tPts == 0 then return {} end

	local center, n = Vector(0, 0, 0), 0
	for _, p in ipairs(tPts) do
		if istable(p) and isvector(p.pos) then center = center + p.pos n = n + 1 end
	end
	if n == 0 then return {} end
	center = center / n

	local areas = navmesh.Find(center, POST_RADIUS, 150, 150)
	if not areas then return {} end

	local posts = {}
	for _, area in ipairs(areas) do
		if #posts >= 12 then break end
		local pos = area:GetCenter()
		local farEnough = true
		for _, p in ipairs(posts) do
			if p:DistToSqr(pos) < POST_MIN_SEPARATION * POST_MIN_SEPARATION then farEnough = false break end
		end
		if farEnough then posts[#posts + 1] = pos end
	end

	-- Prefer posts shielded from the CT (SWAT) approach direction -- see file
	-- header's BEHAVIOUR CHOICE on why this is a raw trace sort, not
	-- lib.FindCover.
	local ctPts = zb.GetMapPoints("HMCD_CRI_CT")
	if istable(ctPts) and #ctPts > 0 and #posts > 1 then
		local approach, an = Vector(0, 0, 0), 0
		for _, p in ipairs(ctPts) do
			if istable(p) and isvector(p.pos) then approach = approach + (p.pos - center) an = an + 1 end
		end
		if an > 0 and approach:LengthSqr() > 1 then
			approach:Normalize()
			local threatPos = center + approach * 1800
			local covered = {}
			for i, p in ipairs(posts) do
				covered[i] = util.TraceLine({ start = threatPos, endpos = p + Vector(0, 0, 40), mask = MASK_SHOT }).Hit
			end
			local order = {}
			for i = 1, #posts do order[i] = i end
			table.sort(order, function(a, b)
				if covered[a] ~= covered[b] then return covered[a] end
				return a < b
			end)
			local sorted = {}
			for i, idx in ipairs(order) do sorted[i] = posts[idx] end
			posts = sorted
		end
	end

	return posts
end

local function getSuspectPosts()
	if #suspectPosts == 0 then suspectPosts = buildSuspectPosts() end
	return suspectPosts
end

-- PERSONALITY: patience/curiosity decide who patrols between 2-3 claimed
-- posts vs. holds a single one all round.
local function assignPosts(bot, brain)
	if brain.crirespPosts then return end
	local posts = getSuspectPosts()
	local n = #posts
	if n == 0 then return end
	local base = bot:EntIndex() % n
	local count = math.min(3, n)
	local list = {}
	for i = 0, count - 1 do
		list[#list + 1] = posts[(base + i) % n + 1]
	end
	brain.crirespPosts = list
	brain.crirespPostIdx = 1
	local personality = brain.personality
	local patience = (personality and personality.patience) or 1
	local curiosity = (personality and personality.curiosity) or 0.5
	brain.crirespRoamer = count > 1 and (curiosity > 0.5 or patience < 1)
	brain.crirespNextPostSwitch = CurTime() + math.Rand(ROAM_INTERVAL_MIN, ROAM_INTERVAL_MAX) * patience
end

local function carriedFortifyWeapon(bot)
	for _, wep in ipairs(bot:GetWeapons()) do
		if IsValid(wep) then
			local class = wep:GetClass()
			if class == "weapon_hammer" or class == "weapon_ducttape" then return wep, class end
		end
	end
	return nil
end

RB({
	name = "criresp.suspect_fortify",
	band = "MODE",
	order = 5,
	default = false,
	finalize = {},
	CanRun = function(ctx)
		if ctx.roundKey ~= "criresp" then return false end
		if ctx.downed then return false end
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		if hg.botdriver.TeamOf(bot) ~= 1 then return false end
		if brain.crirespFortified then return false end
		if now > ((zb and zb.ROUND_START) or 0) + SETUP_DEADLINE then
			brain.crirespFortified = true
			return false
		end
		if brain.crirespFortifyState then
			if now - (brain.crirespFortifyStartedAt or now) > FORTIFY_GIVEUP then
				brain.crirespFortified = true
				brain.crirespFortifyState, brain.crirespFortifyDoor = nil, nil
				return false
			end
			return true
		end
		if IsValid(ctx:AcquireTarget()) then return false end
		if not carriedFortifyWeapon(bot) then
			brain.crirespFortified = true
			return false
		end
		local door = lib.FindDoorAhead(bot, bot:GetAimVector())
		if not IsValid(door) or sealedDoors[door] then return false end
		brain.crirespFortifyDoor = door
		brain.crirespFortifyState = "approach"
		brain.crirespFortifyStartedAt = now
		return true
	end,
	Run = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		local door = brain.crirespFortifyDoor
		if not IsValid(door) or sealedDoors[door] then
			brain.crirespFortifyState, brain.crirespFortifyDoor = nil, nil
			return false
		end
		local wep, class = carriedFortifyWeapon(bot)
		if not wep then
			brain.crirespFortified = true
			brain.crirespFortifyState = nil
			return false
		end
		if bot:GetActiveWeapon() ~= wep then
			bot:SelectWeapon(wep:GetClass())
			return true
		end

		if brain.crirespFortifyState == "approach" then
			if bot:GetPos():DistToSqr(door:GetPos()) <= FORTIFY_RANGE * FORTIFY_RANGE then
				brain.crirespFortifyState = "align"
				brain.crirespFortifyUntil = now + FORTIFY_ALIGN_TIME
				return true
			end
			lib.LookAt(bot, brain, door:WorldSpaceCenter(), "criresp_fortify", false)
			lib.PathTo(bot, brain, door:GetPos(), now, 1)
			return true, { path = true }
		end

		brain.path = nil
		brain.forward, brain.side = 0, 0
		brain.actionPolicy = { owner = "criresp_fortify", lockMove = true }
		lib.LookAt(bot, brain, door:WorldSpaceCenter(), "criresp_fortify", true)

		if brain.crirespFortifyState == "align" then
			if now < brain.crirespFortifyUntil then return true end
			brain.crirespFortifyState = "acting"
			brain.crirespFortifyUntil = now + (class == "weapon_hammer" and FORTIFY_HAMMER_HOLD or FORTIFY_TAPE_HOLD)
			return true
		end

		-- acting: hammer needs one IN_ATTACK2 secondary press (see header);
		-- ducttape needs IN_ATTACK held continuously to charge its Holding.
		if class == "weapon_hammer" then
			brain.buttons = bit.bor(brain.buttons or 0, IN_ATTACK2)
		else
			brain.buttons = bit.bor(brain.buttons or 0, IN_ATTACK)
		end
		if now < brain.crirespFortifyUntil then return true end

		sealedDoors[door] = true
		brain.crirespFortified = true
		brain.crirespFortifyState, brain.crirespFortifyDoor = nil, nil
		return true
	end,
})

RB({
	name = "criresp.suspect_hold",
	band = "MODE",
	order = 15,
	default = false,
	finalize = { path = true, roam = true },
	CanRun = function(ctx)
		if ctx.roundKey ~= "criresp" then return false end
		if ctx.downed then return false end
		local bot = ctx.bot
		if hg.botdriver.TeamOf(bot) ~= 1 then return false end
		if hg.botdriver.RoundAllowsCombat and not hg.botdriver.RoundAllowsCombat() then return false end
		assignPosts(bot, ctx.brain)

		local target = ctx:AcquireTarget()
		if not IsValid(target) then return true end

		-- Brief: hold posts and watch approaches rather than pushing out, and
		-- never leave the defended area to hunt -- refuse an engagement more
		-- than RETURN_LEASH from every claimed post.
		local posts = ctx.brain.crirespPosts
		if istable(posts) and #posts > 0 then
			local nearest
			for _, p in ipairs(posts) do
				local d = target:GetPos():DistToSqr(p)
				if not nearest or d < nearest then nearest = d end
			end
			if nearest and nearest > RETURN_LEASH * RETURN_LEASH then return true end
		end
		return false -- within leash: COMBAT engages
	end,
	Run = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		local posts = brain.crirespPosts
		if not istable(posts) or #posts == 0 then
			brain.forward, brain.side = 0, 0
			return true
		end

		if brain.crirespRoamer and now >= (brain.crirespNextPostSwitch or 0) then
			brain.crirespPostIdx = (brain.crirespPostIdx % #posts) + 1
			local patience = (brain.personality and brain.personality.patience) or 1
			brain.crirespNextPostSwitch = now + math.Rand(ROAM_INTERVAL_MIN, ROAM_INTERVAL_MAX) * patience
		end

		local post = posts[brain.crirespPostIdx or 1]
		if not isvector(post) then return true end

		if bot:GetPos():Distance(post) > 56 then
			lib.PathTo(bot, brain, post, now, 1)
		else
			brain.path = nil
			brain.forward, brain.side = 0, 0
			-- Finalize's roam branch below runs lib.IdleScan once stationary,
			-- giving the "watch the approach" head-sweep for free.
		end
		return true
	end,
})

----------------------------------------------------------------------
-- B: SWAT -- stacked squad advance, systematic area clearing, flashbang
-- before entry, handcuff arrest.
----------------------------------------------------------------------

local function liveThreatNearby(ctx)
	local isEnemy = ctx:EnemyOf()
	if not isfunction(isEnemy) then return false end
	local bot, brain, now = ctx.bot, ctx.brain, ctx.now
	local myPos = bot:GetPos()
	for _, ent in ipairs(hg.botdriver.Actors()) do
		if ent ~= bot and isEnemy(ent) and not hg.botdriver.IsDowned(ent)
			and myPos:DistToSqr(ent:GetPos()) <= ARREST_THREAT_RANGE * ARREST_THREAT_RANGE
			and lib.VisualContact(bot, ent, brain, false, now) then
			return true
		end
	end
	return false
end

local function nearestDownedSuspect(bot)
	local myPos = bot:GetPos()
	local best, bestDistSqr
	for _, ply in ipairs(player.GetAll()) do
		if IsValid(ply) and ply ~= bot and ply:Team() == 1 and hg.botdriver.IsDowned(ply)
			and (not arrestClaims[ply] or arrestClaims[ply] == bot) then
			local d = myPos:DistToSqr(ply:GetPos())
			if not bestDistSqr or d < bestDistSqr then best, bestDistSqr = ply, d end
		end
	end
	return best
end

-- Prefer arresting over executing: high priority (order 6), independent of
-- ctx:AcquireTarget() so it can pre-empt COMBAT band finishing off a downed
-- suspect it would otherwise just keep shooting.
RB({
	name = "criresp.swat_arrest",
	band = "MODE",
	order = 6,
	default = false,
	finalize = {},
	CanRun = function(ctx)
		if ctx.roundKey ~= "criresp" then return false end
		if ctx.downed then return false end
		local bot, brain = ctx.bot, ctx.brain
		if hg.botdriver.TeamOf(bot) ~= 0 then return false end

		if brain.crirespArrestState then
			local target = brain.crirespArrestTarget
			if not IsValid(target) or not hg.botdriver.IsDowned(target) or arrestClaims[target] ~= bot
				or liveThreatNearby(ctx) then
				arrestClaims[target] = nil
				brain.crirespArrestState, brain.crirespArrestTarget = nil, nil
				return false
			end
			return true
		end

		if not bot:HasWeapon("weapon_handcuffs") then return false end
		if liveThreatNearby(ctx) then return false end
		local target = nearestDownedSuspect(bot)
		if not IsValid(target) then return false end

		arrestClaims[target] = bot
		brain.crirespArrestTarget = target
		brain.crirespArrestState = "approach"
		return true
	end,
	Run = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		local target = brain.crirespArrestTarget
		if not IsValid(target) then
			brain.crirespArrestState = nil
			return false
		end

		if bot:GetPos():DistToSqr(target:GetPos()) > ARREST_RANGE * ARREST_RANGE then
			brain.crirespArrestState = "approach"
			lib.LookAt(bot, brain, target:GetPos() + Vector(0, 0, 40), "criresp_arrest", false)
			lib.PathTo(bot, brain, target:GetPos(), now, 1)
			return true, { path = true }
		end

		local active = bot:GetActiveWeapon()
		if not IsValid(active) or active:GetClass() ~= "weapon_handcuffs" then
			bot:SelectWeapon("weapon_handcuffs")
		end

		brain.path = nil
		brain.forward, brain.side = 0, 0
		brain.actionPolicy = { owner = "criresp_arrest", lockMove = true }
		lib.LookAt(bot, brain, lib.AimPosOf(target), "criresp_arrest", true)

		if brain.crirespArrestState == "approach" then
			brain.crirespArrestState = "align"
			brain.crirespArrestUntil = now + ARREST_ALIGN_TIME
			return true
		end

		if brain.crirespArrestState == "align" then
			if now < brain.crirespArrestUntil then return true end
			brain.crirespArrestState = "cuffing"
			brain.crirespArrestUntil = now + ARREST_WAIT_BUDGET
			return true
		end

		-- cuffing: hold IN_ATTACK + position/facing for the wait budget.
		-- weapon_handcuffs's own 2s SWEP.CoolDown prevents a second trigger;
		-- success/abort is detected next decision via the CanRun re-checks
		-- above (target no longer downed/valid, or the claim's weapon gone).
		brain.buttons = bit.bor(brain.buttons or 0, IN_ATTACK)
		if now < brain.crirespArrestUntil and bot:HasWeapon("weapon_handcuffs") then return true end

		-- Exit either way (cuffed successfully -- the weapon just Remove()d
		-- itself, see header -- or gave up waiting): weapon_handcuffs.lua's
		-- own Tie() already force-switched us to weapon_hands_sh, so get back
		-- on a real gun rather than staying fistless.
		arrestClaims[target] = nil
		brain.crirespArrestState, brain.crirespArrestTarget = nil, nil
		local gun = hg.botdriver.BestGun(bot)
		if gun then bot:SelectWeapon(gun:GetClass()) end
		return true
	end,
})

local function carriedFlashbang(bot)
	for _, wep in ipairs(bot:GetWeapons()) do
		if IsValid(wep) and wep:GetClass() == "weapon_hg_flashbang_tpik" then return wep end
	end
	return nil
end

-- Flashbang a suspected room before entry: only the squad's point bot leads
-- with it, and only when a teammate's fresh contact places a threat inside
-- the area SWAT is about to clear. Integrates with sv_grenade.lua's own
-- ballistic solve/ally-safety check rather than a second copy of either.
RB({
	name = "criresp.swat_flashbang",
	band = "MODE",
	order = 8,
	default = false,
	finalize = {},
	CanRun = function(ctx)
		if ctx.roundKey ~= "criresp" then return false end
		if ctx.downed then return false end
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		if hg.botdriver.TeamOf(bot) ~= 0 then return false end
		if brain.grenadeThrowing then return false end
		if IsValid(ctx:AcquireTarget()) then return false end
		if now < (brain.crirespFlashbangCooldownAt or 0) then return false end

		local squad = hg.botdriver.squad
		if squad and squad.PointOf and squad.PointOf(bot) ~= bot then return false end

		if not carriedFlashbang(bot) then return false end
		local area = brain.crirespClearArea
		if not IsValid(area) then return false end
		local contactPos = squad and squad.FreshestContact and squad.FreshestContact(bot)
		if not isvector(contactPos) then return false end

		local center = area:GetCenter()
		if center:DistToSqr(contactPos) > FLASHBANG_TRIGGER_RANGE * FLASHBANG_TRIGGER_RANGE then return false end
		if bot:GetPos():DistToSqr(center) > (FLASHBANG_TRIGGER_RANGE * 1.5) ^ 2 then return false end
		if not lib.GrenadeSafeToThrow(bot, center, 250, 300) then return false end

		brain.crirespFlashbangLanding = center
		return true
	end,
	Run = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		local wep = carriedFlashbang(bot)
		if not IsValid(wep) then
			brain.crirespFlashbangLanding = nil
			return false
		end
		if bot:GetActiveWeapon() ~= wep then
			bot:SelectWeapon(wep:GetClass())
			return true
		end
		local landing = brain.crirespFlashbangLanding
		if not isvector(landing) then return false end

		if lib.AimAndThrow(bot, brain, now, wep, landing, FLASHBANG_THROW_SPEED, FLASHBANG_WINDUP) then
			return true
		end
		brain.crirespFlashbangCooldownAt = now + FLASHBANG_COOLDOWN
		brain.crirespFlashbangLanding = nil
		local gun = hg.botdriver.BestGun(bot)
		if gun then bot:SelectWeapon(gun:GetClass()) end
		return true
	end,
})

local function pickClearTarget(bot)
	if not navmesh.IsLoaded() then return nil end
	local from = navmesh.GetNearestNavArea(bot:GetPos())
	if IsValid(from) then
		for _, area in ipairs(from:GetAdjacentAreas() or {}) do
			if IsValid(area) and not clearedAreas[area:GetID()] then return area end
		end
	end

	-- Fallback (round start, or no uncleared neighbour yet): nearest
	-- uncleared area within CLEAR_SCAN_RADIUS, bounded/stride-sampled the
	-- same way lib.FindCover already scans navmesh.Find results.
	local areas = navmesh.Find(bot:GetPos(), CLEAR_SCAN_RADIUS, 200, 200)
	if not areas or #areas == 0 then return nil end
	local n = #areas
	local offset, stride = math.random(n) - 1, math.max(1, math.floor(n / 10))
	local myPos = bot:GetPos()
	local best, bestDistSqr
	local checked = 0
	for i = 0, n - 1, stride do
		if checked >= 10 then break end
		checked = checked + 1
		local area = areas[(offset + i) % n + 1]
		if IsValid(area) and not clearedAreas[area:GetID()] then
			local d = myPos:DistToSqr(area:GetCenter())
			if not bestDistSqr or d < bestDistSqr then best, bestDistSqr = area, d end
		end
	end
	return best
end

RB({
	name = "criresp.swat_clear",
	band = "MODE",
	order = 16,
	default = false,
	finalize = { path = true, roam = true },
	CanRun = function(ctx)
		if ctx.roundKey ~= "criresp" then return false end
		if ctx.downed then return false end
		local bot = ctx.bot
		if hg.botdriver.TeamOf(bot) ~= 0 then return false end
		if hg.botdriver.RoundAllowsCombat and not hg.botdriver.RoundAllowsCombat() then return false end
		if ctx.brain.crirespArrestState then return false end
		return not IsValid(ctx:AcquireTarget())
	end,
	Run = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now

		-- Stack: a non-point squadmate holds a lateral offset near the point
		-- bot instead of independently pathing to the clear objective, so the
		-- squad advances together with spacing (one grenade can't take the
		-- stack).
		local squad = hg.botdriver.squad
		local point = squad and squad.PointOf and squad.PointOf(bot)
		if IsValid(point) and point ~= bot then
			local dir = point:GetAimVector()
			dir.z = 0
			if dir:LengthSqr() < 1 then dir = Vector(1, 0, 0) else dir:Normalize() end
			local right = Vector(-dir.y, dir.x, 0)
			local side = (bot:EntIndex() % 2 == 0) and 1 or -1
			local dest = point:GetPos() - dir * STACK_OFFSET + right * (side * STACK_OFFSET * 0.6)
			if bot:GetPos():DistToSqr(dest) > 80 * 80 then
				lib.PathTo(bot, brain, dest, now, 1)
				return true, { path = true }
			end
			brain.path = nil
			brain.forward, brain.side = 0, 0
			return true
		end

		-- Point bot (or solo/no squad module): advance area-by-area.
		local area = brain.crirespClearArea
		if not IsValid(area) or clearedAreas[area:GetID()] then
			area = pickClearTarget(bot)
			brain.crirespClearArea = area
			brain.crirespClearAreaSince = nil
		end
		if not IsValid(area) then
			brain.forward, brain.side = 0, 0
			return true
		end

		local center = area:GetCenter()
		if bot:GetPos():DistToSqr(center) > CLEAR_ARRIVE_RADIUS * CLEAR_ARRIVE_RADIUS then
			brain.crirespClearAreaSince = nil
			lib.PathTo(bot, brain, center, now, 1)
			return true, { path = true }
		end

		brain.path = nil
		brain.forward, brain.side = 0, 0
		if not brain.crirespClearAreaSince then brain.crirespClearAreaSince = now end
		if now - brain.crirespClearAreaSince >= CLEAR_HOLD_TIME then
			clearedAreas[area:GetID()] = true
			brain.crirespClearArea, brain.crirespClearAreaSince = nil, nil
		end
		return true
	end,
})

----------------------------------------------------------------------
-- Mode profile. mode.tdm_squad_push is intentionally NOT listed here -- see
-- the file header's BEHAVIOUR CHOICES.
----------------------------------------------------------------------

hg.botdriver.RegisterModeProfile("criresp", {
	behaviors = {
		"criresp.suspect_fortify",
		"criresp.swat_arrest",
		"criresp.swat_flashbang",
		"criresp.suspect_hold",
		"criresp.swat_clear",
	},
})
