-- Defense mode profile for zc_bots (NPC horde defense). Round key "defense"
-- (MODE.name, us1/.../modes/defense/sh_defense.lua:12).
--
-- VERIFIED this session (us1/.../modes/defense/*.lua):
--   * Waves: DEFENSE_WAVE_DEFINITIONS (defense/sv_defense_config.lua:139-262),
--     one array per submode (STANDARD/EXTENDED/ZOMBIE) x wave number, each
--     entry {type, count, health, weapon, boss?, ...}. Every count/health
--     value is a fixed literal -- no player.GetCount()/#player.GetHumans()
--     term appears anywhere in sv_defense_config.lua, sv_defense_waves.lua or
--     sv_defense.lua's spawn/wave path. Reported per the brief; nothing here
--     scales by player count, so nothing is touched.
--   * Objective/defended area: no single "objective entity" field exists.
--     The closest verified concepts are the DEFENSE_POINT and PLY_DEFENSE_SPAWN
--     map-point groups (zb.Points registrations, sh_defense.lua:6-16) plus
--     MODE:GetUsualPlayerSpawnPoints() (sv_defense.lua:198-226, the players'
--     own spawn set) -- NPC_DEFENSE_SPAWN/DEFENSE_POINT are where NPCs anchor
--     and advance FROM (MODE:GetDefenseAnchorPoints, sv_defense.lua:228-240),
--     not what is defended. objectivePos() below treats DEFENSE_POINT/
--     PLY_DEFENSE_SPAWN's averaged position as the defended area, falling
--     back to the living humans' centroid -- BEHAVIOUR CHOICE, since no more
--     specific field exists.
--   * Roles (sv_defense_roles.lua): AssignPlayerRoles() (lines 74-179) builds
--     `players` from every non-spectator ALIVE player (line 76-80, no
--     :IsBot() filter) and hands the FIRST shuffled entry the Commander role
--     unconditionally (line 129). Bots CAN be picked. installCommanderGuard
--     below wraps zb.modes.defense.AssignPlayerRoles from outside, the same
--     idempotent-wrap idiom sv_shooter_modes.lua/sv_lowpop.lua use, and swaps
--     a bot Commander's role with a human's after the original runs.
--   * Votes: MODE.VoteInProgress (sv_defense.lua:68) blocks ShouldRoundEnd
--     (sv_defense.lua:392-395) but the vote itself ends on a fixed
--     `self:CreateTimer("vote_end_timer", self.VoteTime, 1, ...)`
--     (sv_defense.lua:293-295) -- not on vote count -- so an abstaining bot
--     never stalls the vote. Voting/purchasing/support-call net.Receive
--     handlers (sv_defense.lua, sv_defense_support.lua) are all client-UI
--     driven; a zcBot (a NextBot player with no client Lua) structurally
--     cannot send them, so "bots ignore support calls/votes" holds with no
--     code change needed here.
--   * Commander is never a bot after this file's guard runs, so the
--     Commander-only paths above (support calls, purchases, votes) are also
--     never reachable FROM a bot in the sense of being that mode's commander.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}
local RB = hg.botdriver.RegisterBehavior
local lib = hg.botdriver.lib

----------------------------------------------------------------------
-- Commander guard: idempotent wrap of zb.modes.defense.AssignPlayerRoles,
-- same guard-token idiom as sv_shooter_modes.lua's Intermission wrap. Runs
-- AFTER the original so equipment (already handed out per-slot by the
-- original) is untouched -- only the PlayerRole/CommanderPoints label swaps.
----------------------------------------------------------------------

local function installCommanderGuard()
	if not (zb and zb.modes and zb.modes.defense) then return false end
	local mode = zb.modes.defense
	if mode.AssignPlayerRoles == hg.botdriver._defenseCommanderGuardWrapped then return true end

	-- The live function is not our wrapper, so it IS the current original --
	-- re-capture it (2026-09-25). Keeping the first-ever capture (`X = X or`)
	-- meant a hot-reloaded defense mode got its old AssignPlayerRoles back on
	-- the next install, silently reverting the reload until map change.
	hg.botdriver._defenseCommanderGuardOriginal = mode.AssignPlayerRoles
	local original = hg.botdriver._defenseCommanderGuardOriginal
	if not isfunction(original) then return false end

	local function wrapped(self, ...)
		local results = { original(self, ...) }

		local commander
		for _, ply in ipairs(player.GetAll()) do
			if IsValid(ply) and ply:GetNWString("PlayerRole") == "Commander" then
				commander = ply
				break
			end
		end

		if IsValid(commander) and commander.zcBot then
			local human
			for _, ply in ipairs(player.GetHumans()) do
				if IsValid(ply) and ply ~= commander and ply:Team() ~= TEAM_SPECTATOR and ply:Alive() then
					human = ply
					break
				end
			end
			if IsValid(human) then
				local humanRole = human:GetNWString("PlayerRole")
				local commanderPoints = commander:GetNWInt("CommanderPoints", 0)
				commander:SetNWString("PlayerRole", humanRole ~= "" and humanRole or "Soldier")
				commander:SetNWInt("CommanderPoints", 0)
				human:SetNWString("PlayerRole", "Commander")
				human:SetNWInt("CommanderPoints", commanderPoints)
				net.Start("defense_player_role_assigned")
				net.WriteString("Commander")
				net.Send(human)
			end
			-- No human present at all: leave the bot Commander in place --
			-- a bot commander (whose menu no one can open) beats no commander.
		end

		return unpack(results)
	end

	hg.botdriver._defenseCommanderGuardWrapped = wrapped
	mode.AssignPlayerRoles = wrapped
	return true
end

hook.Add("InitPostEntity", "zc_bots_defense_commander_guard", installCommanderGuard)
-- Re-checked each round like the homelanderhns guard, so a mode-table
-- rebuild mid-map does not silently drop the wrap.
hook.Add("ZB_PreRoundStart", "zc_bots_defense_commander_guard_reinstall", installCommanderGuard)
installCommanderGuard() -- lua_openscript / autorefresh mid-round

----------------------------------------------------------------------
-- Defended-area posts (brief item 5): nav areas within ~900u of the
-- objective, spread > 250u apart, preferring cover from the dominant NPC
-- approach direction (NPC_DEFENSE_SPAWN points averaged, once any exist).
-- Rebuilt only when the round's current wave number changes -- not per tick.
----------------------------------------------------------------------

local POST_RADIUS = 900
local POST_MIN_SEPARATION = 250
local RETURN_LEASH = 700

local function objectivePos()
	local pts = zb.GetMapPoints and (zb.GetMapPoints("DEFENSE_POINT") or zb.GetMapPoints("PLY_DEFENSE_SPAWN"))
	if istable(pts) and #pts > 0 then
		local sum, n = Vector(0, 0, 0), 0
		for _, p in ipairs(pts) do
			local pos = istable(p) and p.pos or p
			if isvector(pos) then sum = sum + pos; n = n + 1 end
		end
		if n > 0 then return sum / n end
	end

	local sum, n = Vector(0, 0, 0), 0
	for _, ply in ipairs(player.GetHumans()) do
		if IsValid(ply) and ply:Alive() then sum = sum + ply:GetPos(); n = n + 1 end
	end
	if n > 0 then return sum / n end
	return nil
end

local function approachDirOf(objPos)
	local pts = zb.GetMapPoints and zb.GetMapPoints("NPC_DEFENSE_SPAWN")
	if not istable(pts) or #pts == 0 then return nil end
	local sum, n = Vector(0, 0, 0), 0
	for _, p in ipairs(pts) do
		local pos = istable(p) and p.pos or p
		if isvector(pos) then sum = sum + (pos - objPos); n = n + 1 end
	end
	if n == 0 then return nil end
	if sum:LengthSqr() < 1 then return nil end
	sum:Normalize()
	return sum
end

local function buildPosts(objPos)
	local posts = {}
	if not (navmesh and navmesh.Find) then return posts end
	local areas = navmesh.Find(objPos, POST_RADIUS, 120, 120)
	if not areas then return posts end

	for _, area in ipairs(areas) do
		if #posts >= 12 then break end
		local center = area:GetCenter()
		local farEnough = true
		for _, p in ipairs(posts) do
			if p:DistToSqr(center) < POST_MIN_SEPARATION * POST_MIN_SEPARATION then
				farEnough = false
				break
			end
		end
		if farEnough then posts[#posts + 1] = center end
	end

	-- Prefer cover from the dominant approach direction once it is known: a
	-- single trace per candidate (bounded, <=12), sorted covered-first.
	local approachDir = approachDirOf(objPos)
	if approachDir and #posts > 1 then
		local threatPos = objPos + approachDir * 1500
		local function covered(p)
			local tr = util.TraceLine({ start = threatPos, endpos = p + Vector(0, 0, 40), mask = MASK_SHOT })
			return tr.Hit
		end
		local coveredFlags = {}
		for i, p in ipairs(posts) do coveredFlags[i] = covered(p) end
		local indices = {}
		for i = 1, #posts do indices[i] = i end
		table.sort(indices, function(a, b)
			if coveredFlags[a] ~= coveredFlags[b] then return coveredFlags[a] end
			return a < b
		end)
		local sorted = {}
		for i, idx in ipairs(indices) do sorted[i] = posts[idx] end
		posts = sorted
	end

	return posts
end

local postsCache = { wave = nil, list = {} }

local function getPosts()
	local round = isfunction(CurrentRound) and CurrentRound()
	local wave = istable(round) and round.Wave or 0
	if postsCache.wave == wave and #postsCache.list > 0 then return postsCache.list end
	local objPos = objectivePos()
	if not objPos then return postsCache.list end
	postsCache.list = buildPosts(objPos)
	postsCache.wave = wave
	return postsCache.list
end

----------------------------------------------------------------------
-- PvE targeting + hold-post band (brief item 5).
----------------------------------------------------------------------

RB({
	name = "defense.hold_post",
	band = "MODE",
	order = 10,
	default = false,
	finalize = { path = true, roam = true },
	CanRun = function(ctx)
		if ctx.roundKey ~= "defense" then return false end
		local npcMod = hg.botdriver.npc
		if not npcMod then return false end
		ctx._enemyOf = npcMod.EnemyOfPve(ctx.bot)
		ctx._allyOf = npcMod.AllyOfPve(ctx.bot)

		local posts = getPosts()
		local post
		if #posts > 0 then
			post = posts[(ctx.bot:EntIndex() % #posts) + 1]
			ctx.brain.defensePost = post
		end

		local target = ctx:AcquireTarget()
		if not IsValid(target) then return true end -- nothing to fight: hold/return to post

		-- Brief: never chase an NPC more than 700u from the assigned post --
		-- refuse this engagement (return to post instead) rather than closing
		-- distance toward a far-off threat.
		if isvector(post) and target:GetPos():DistToSqr(post) > RETURN_LEASH * RETURN_LEASH then
			return true
		end
		return false -- within leash: let ACQUIRE/COMBAT fight it
	end,
	Run = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		local post = brain.defensePost
		if not isvector(post) then
			brain.forward, brain.side = 0, 0
			return true
		end
		if bot:GetPos():Distance(post) > 48 then
			lib.PathTo(bot, brain, post, now, 1)
		else
			brain.path = nil
			brain.forward, brain.side = 0, 0
		end
		-- Reload/heal-between-waves (brief) is already generic: SUPPORT band's
		-- gunhandling.topup_reload and support.medical both run whenever no
		-- target is claimed, which is exactly this state.
		return true
	end,
})

hg.botdriver.RegisterModeProfile("defense", {
	behaviors = { "defense.hold_post" },
})
