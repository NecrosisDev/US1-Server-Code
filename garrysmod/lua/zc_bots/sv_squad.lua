-- Per-team squad blackboard. Team modes only (squadsDisabled() gates
-- every entry point) -- FFA rounds never see a squad or a shared contact.
--
-- Provides: shared contacts (fed by any bot's already-computed AcquireTarget,
-- 8s decay) surfaced to teammates as a low-priority objective; target
-- spreading (consumed by sv_brain.lua's AcquireTargetStep -- see the "SQUAD"
-- marker there); squads of up to 4 by spawn order with point/flank/support
-- slots; a regroup objective when a bot strays from its squad; and a reload
-- handshake between squadmates. All upkeep runs from one hg.botdriver.Every
-- tick per the porting budget.
--
-- zChatPrint (verified at
-- us1/addons/zcity/gamemodes/zcity/gamemode/loader.lua:106) is a per-player
-- print (`ply:zChatPrint(text)`), not a team broadcast -- no team-only text
-- path was found anywhere in this tree. Per the brief's own fallback, no
-- ply:Say and no chat text is sent; EmitLine below is the single seam a
-- later phase can wire to whatever chat layer the live server actually runs.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}
hg.botdriver.squad = hg.botdriver.squad or {}
local squad = hg.botdriver.squad


local function squadsDisabled()
 local profile = hg.botdriver.ResolveModeProfile(zb and (zb.CROUND_MAIN or zb.CROUND))
 return hg.botdriver.IsFFA() or (profile and profile.NoSquads == true)
end
local CONTACT_DECAY = 8
local CLAIM_RADIUS = 900        -- a squadmate "claims" a target while inside this range and targeting it
local CLAIM_PENALTY_SQR = 2.25  -- distSqr multiplier (1.5^2) applied once claimed by >=2 living bots
local SQUAD_SIZE = 4
local REGROUP_DIST = 1200
local FLANK_OFFSET_MIN, FLANK_OFFSET_MAX = 250, 400
-- Formation-following (no active contact): how far out of slot before a
-- non-point member re-forms, and where its slot sits relative to the point
-- bot's current facing.
local FORMATION_SLACK = 220
local SUPPORT_BEHIND = 220
local FLANK_BEHIND = 80
local FLANK_SIDE = 180
local CALLOUT_COOLDOWN = 6
local RELOAD_SUPPRESS_WINDOW = 2

----------------------------------------------------------------------
-- Squad membership: assigned by spawn order, up to SQUAD_SIZE per squad.
-- Rebuilt lazily whenever the roster changes (spawn/disconnect), not every
-- tick.
----------------------------------------------------------------------

local roster = {}        -- team -> ordered array of bots (spawn order)
local rosterDirty = {}   -- team -> true when roster needs a squad recompute
local squadOf = {}       -- bot -> { team, index, slot, squadId }

local SLOTS = { "point", "flank", "support", "flank" }

-- Known gap fix (2026-09-22, role assignment by weapon class): slots used to
-- be handed out by raw spawn order alone. hg.botdriver.WeaponProfile
-- (sv_weaponscore.lua) already classifies a weapon into one of
-- hg.botdriver.RoleBands' roles for combat scoring; reuse that same
-- classification here instead of a second weapon taxonomy. Close-range roles
-- lead, long-range roles hang back in support, everything else flanks.
local SLOT_BY_ROLE = {
	shotgun = "point", smg = "point", melee = "point",
	sniper = "support", rifle = "support", lmg = "support",
	pistol = "flank", carbine = "flank", launcher = "flank",
}

local function preferredSlot(bot)
	if not IsValid(bot) then return nil end
	local wep = bot:GetActiveWeapon()
	local prof = IsValid(wep) and hg.botdriver.WeaponProfile and hg.botdriver.WeaponProfile(wep)
	return prof and SLOT_BY_ROLE[prof.role] or nil
end

local function markDirty(team)
	if team then rosterDirty[team] = true end
end

-- 2026-09-25: rosters used to be filed from a PlayerSpawn hook, but hook.Add
-- callbacks run BEFORE GM:PlayerSpawn (which assigns zb:BalancedChoice) and
-- before the mode's own SetupTeam, so every bot was filed under LAST round's
-- team and never moved -- squads mixed both teams and Squadmates could return
-- enemies. Membership now follows each bot's CURRENT team, re-checked by the
-- upkeep tick below (syncRosters), and a team change moves the bot.
local rosterTeam = {}    -- bot -> team it is currently filed under

local function unfile(bot)
	local team = rosterTeam[bot]
	if team == nil then return end
	local list = roster[team]
	if list then
		for i = #list, 1, -1 do
			if list[i] == bot then table.remove(list, i) end
		end
	end
	rosterTeam[bot] = nil
	markDirty(team)
end

local function fileBot(bot, team)
	if rosterTeam[bot] == team then return end
	unfile(bot)
	roster[team] = roster[team] or {}
	local list = roster[team]
	list[#list + 1] = bot
	rosterTeam[bot] = team
	markDirty(team)
end

local function syncRosters()
	for bot in pairs(rosterTeam) do
		if not IsValid(bot) then
			local team = rosterTeam[bot]
			rosterTeam[bot] = nil
			squadOf[bot] = nil
			markDirty(team)
		end
	end
	for bot in pairs(hg.botdriver.brains) do
		if IsValid(bot) and bot:IsBot() and bot.zcBot and bot:Alive() and not bot.zcBotBenched then
			local team = hg.botdriver.TeamOf(bot)
			if team ~= nil then fileBot(bot, team) end
		end
	end
end
squad.SyncRosters = syncRosters

-- Retire the old spawn-time filing hook on a live reload of this file.
hook.Remove("PlayerSpawn", "zc_bots_squad_roster")

hook.Add("PlayerDisconnected", "zc_bots_squad_roster_leave", function(ply)
	unfile(ply)
	squadOf[ply] = nil
end)

-- Assigns each SQUAD_SIZE-sized group its slots in two passes: first, hand a
-- member its weapon-preferred slot if that slot in ITS group is still free
-- (spawn order breaks ties among identical loadouts); second, fill whatever
-- is left over in spawn order. Runs only when the roster is dirty
-- (spawn/disconnect), not on a tick cadence, so a mid-round weapon pickup
-- does not thrash slots -- PROVISIONAL(2026-09-22, slot reassignment on
-- loadout change was judged not worth the extra roster-wide recompute for
-- this pass; a bot keeps its spawn-time slot for the rest of its life,
-- ratify-by: 2026-10-20).
local function rebuildSquads(team)
	local list = roster[team]
	if not list then return end
	for i = #list, 1, -1 do
		if not IsValid(list[i]) then table.remove(list, i) end
	end

	local n = #list
	local groupCount = math.ceil(n / SQUAD_SIZE)
	for g = 0, groupCount - 1 do
		local from = g * SQUAD_SIZE + 1
		local to = math.min(from + SQUAD_SIZE - 1, n)
		local size = to - from + 1
		local slotsLeft = {}
		for slotIdx = 1, size do slotsLeft[slotIdx] = SLOTS[slotIdx] end
		local memberSlot = {}

		for i = from, to do
			local want = preferredSlot(list[i])
			if want then
				for slotIdx = 1, size do
					if slotsLeft[slotIdx] == want then
						memberSlot[i] = want
						slotsLeft[slotIdx] = false
						break
					end
				end
			end
		end

		local nextSlotIdx = 1
		for i = from, to do
			if not memberSlot[i] then
				while slotsLeft[nextSlotIdx] == false do nextSlotIdx = nextSlotIdx + 1 end
				memberSlot[i] = slotsLeft[nextSlotIdx]
				slotsLeft[nextSlotIdx] = false
			end
		end

		for i = from, to do
			squadOf[list[i]] = { team = team, index = i, slot = memberSlot[i], squadId = g }
		end
	end
	rosterDirty[team] = nil
end

function squad.SquadOf(bot)
	if squadsDisabled() then return nil end
	local info = squadOf[bot]
	if not info then return nil end
	local team = hg.botdriver.TeamOf(bot)
	if team ~= info.team then return nil end -- team switch invalidates membership
	return info
end

-- Every squadmate sharing a squadId + team, point bot first.
function squad.Squadmates(bot)
	local info = squad.SquadOf(bot)
	if not info then return {} end
	local out = {}
	local list = roster[info.team]
	if not list then return out end
	for _, other in ipairs(list) do
		local otherInfo = squadOf[other]
		-- Same squad AND still on this team right now (a team change between
		-- two upkeep ticks must never hand back an enemy as a squadmate).
		if otherInfo and otherInfo.squadId == info.squadId and otherInfo.team == info.team
			and IsValid(other) and other:Alive() and hg.botdriver.TeamOf(other) == info.team then
			out[#out + 1] = other
		end
	end
	return out
end

function squad.PointOf(bot)
	local mates = squad.Squadmates(bot)
	local best
	for _, m in ipairs(mates) do
		local info = squadOf[m]
		if info and info.slot == "point" then return m end
		if not best then best = m end
	end
	return best
end

----------------------------------------------------------------------
-- Shared contacts: team -> array of {ent, pos, time}, deduped by ent.
----------------------------------------------------------------------

local contacts = {} -- team -> { [ent] = { pos = Vector, time = number } }

function squad.ReportContact(team, ent, pos, now, reporter)
	if squadsDisabled() then return end
	if not team or not IsValid(ent) or not isvector(pos) then return end
	contacts[team] = contacts[team] or {}
	if not contacts[team][ent] and IsValid(reporter) then squad.EmitLine(reporter, "contact") end
	contacts[team][ent] = { pos = pos, time = now }
end

local function pruneContacts(team, now)
	local set = contacts[team]
	if not set then return end
	for ent, rec in pairs(set) do
		if now - rec.time > CONTACT_DECAY or not IsValid(ent) then
			set[ent] = nil
		end
	end
end

-- Freshest live contact for BOT's team, excluding one it can already see
-- itself (mode files call this to feed hg.botdriver.SetObjective).
function squad.FreshestContact(bot)
	if squadsDisabled() then return nil end
	local team = hg.botdriver.TeamOf(bot)
	local set = team and contacts[team]
	if not set then return nil end
	local bestEnt, bestRec
	for ent, rec in pairs(set) do
		if IsValid(ent) and (not bestRec or rec.time > bestRec.time) then
			bestEnt, bestRec = ent, rec
		end
	end
	if not bestEnt then return nil end
	return bestRec.pos, bestEnt, bestRec.time
end

----------------------------------------------------------------------
-- Target spreading: how many LIVING bots on the claimer's team are within
-- CLAIM_RADIUS of `target` and currently holding it as their brain.target.
-- Consumed from sv_brain.lua's AcquireTargetStep (the "SQUAD" marker there).
----------------------------------------------------------------------

function squad.ClaimPenalty(bot, target)
	if squadsDisabled() then return 1 end
	local team = hg.botdriver.TeamOf(bot)
	if not team then return 1 end
	local claimants = 0
	for other, brain in pairs(hg.botdriver.brains) do
		if other ~= bot and IsValid(other) and other:Alive() and other:IsBot() and other.zcBot
			and hg.botdriver.TeamOf(other) == team
			and brain.target == target
			and other:GetPos():DistToSqr(target:GetPos()) <= CLAIM_RADIUS * CLAIM_RADIUS then
			claimants = claimants + 1
			if claimants >= 2 then return CLAIM_PENALTY_SQR end
		end
	end
	return 1
end

----------------------------------------------------------------------
-- Reload handshake: a reloading bot marks itself; the nearest living
-- squadmate with LOS to the same contact gets a 2s suppress flag.
-- brain.squadSuppressUntil is consumed in two places (2026-09-22, teamplay
-- known gap fix -- this comment used to say nothing read it; it now does):
-- sv_brain.lua's Engage extends brain.fireUntil (keep shooting) and holds the
-- covering ally's position instead of closing on its own target (stop
-- repositioning while a squadmate is defenseless mid-reload).
----------------------------------------------------------------------

function squad.OnReloadStart(bot, now)
	local info = squad.SquadOf(bot)
	if not info then return end
	local brain = hg.botdriver.brains[bot]
	local target = brain and brain.target
	if not IsValid(target) then return end

	local mates = squad.Squadmates(bot)
	local best, bestDistSqr
	local lib = hg.botdriver.lib
	for _, mate in ipairs(mates) do
		if mate ~= bot and IsValid(mate) then
			local mateBrain = hg.botdriver.brains[mate]
			if mateBrain and lib and lib.CanSeeTarget and lib.CanSeeTarget(mate, target) then
				local d = mate:GetPos():DistToSqr(bot:GetPos())
				if not bestDistSqr or d < bestDistSqr then best, bestDistSqr = mate, d end
			end
		end
	end
	if best then
		local mateBrain = hg.botdriver.brains[best]
		mateBrain.squadSuppressUntil = now + RELOAD_SUPPRESS_WINDOW
		squad.EmitLine(bot, "cover_me")
	end
end

----------------------------------------------------------------------
-- Callouts: text is intentionally not sent (see file header). EmitLine is
-- the single seam a later phase wires to whatever chat layer the live
-- server runs; per-squad cooldown still applies so the seam fires at a
-- realistic cadence even before anything consumes it.
----------------------------------------------------------------------

local lastCallout = {} -- squadId -> time

local cv_callouts = ConVarExists("zc_bots_callouts") and GetConVar("zc_bots_callouts")
	or CreateConVar("zc_bots_callouts", "0", FCVAR_ARCHIVE, "Bot team-chat callouts to human teammates")

-- 2026-09-26: worded the way people actually type mid-fight (short, no
-- radio-speak like "enemy spotted").
local CALLOUT_LINES = {
	contact = { "contact", "one over here", "hes here", "theyre here", "here", "one here" },
	cover_me = { "reloading", "cover me", "reload", "cover me im reloading" },
	regroup = { "on me", "wait up", "wait for me", "come here" },
	down = { "got him", "hes down", "one down", "got one" },
}

-- Team modes only: in masscasualty/activeshooter the shooter(s) share team 0
-- with their victims (isTraitor is a flag, not a real team split -- see each
-- mode's own header), so both stay excluded here. gwars/criresp/riot/
-- uncontainedriot/wildcard (2026-09-21, Part A) are confirmed real two-team
-- splits (ply:Team() 0/1) in each mode's own header citation, so callouts
-- work the same way they do for tdm/cstrike/hl2dm.
local CALLOUT_MODES = {
	tdm = true, cstrike = true, hl2dm = true,
	gwars = true, criresp = true, riot = true, uncontainedriot = true, wildcard = true,
}

function squad.EmitLine(bot, key)
	local info = squad.SquadOf(bot)
	local squadId = info and info.squadId or bot
	local now = CurTime()
	if now - (lastCallout[squadId] or -math.huge) < CALLOUT_COOLDOWN then return end
	if not cv_callouts:GetBool() or not CALLOUT_MODES[zb and (zb.CROUND_MAIN or zb.CROUND) or ""] then return end
	-- PERSONALITY: a non-chatty bot still respects the cooldown above but
	-- speaks up less often even when it is clear to.
	local brain = hg.botdriver.brains[bot]
	local personality = brain and brain.personality
	if personality and personality.chatty == false and math.random() < 0.6 then return end
	local hasHuman = false
	local team = hg.botdriver.TeamOf(bot)
	for _, ply in ipairs(player.GetHumans()) do
		if hg.botdriver.TeamOf(ply) == team then hasHuman = true break end
	end
	if not hasHuman then return end
	local lines = CALLOUT_LINES[key]
	if not lines then return end
	lastCallout[squadId] = now
	local line = lines[math.random(#lines)]

	-- Item 3 (typing indicator): the cooldown slot above is consumed the
	-- instant a bot decides to call out; only the actual print is deferred
	-- behind sv_chatter.lua's shared typing helper. doEmit re-checks
	-- cv_callouts/IsValid itself since the send can land up to 4s later.
	-- 2026-09-26 parity: ZChat gives humans no team channel, so a
	-- "(TEAM) name:" line was a format only bots could produce (and it
	-- skipped the typing-style pass). A callout is now ordinary chat through
	-- sv_chatter.lua's funnel: styled, proximity-limited and rendered like
	-- anyone else's line -- the teammates near enough to matter read it.
	local function doEmit(speaker, styledText)
		if not cv_callouts:GetBool() then return end
		if not IsValid(bot) then return end
		if hg.botdriver.chatter and hg.botdriver.chatter.Say then
			hg.botdriver.chatter.Say(bot, styledText or line, false, true)
		end
	end

	if hg.botdriver.chatTyping then
		hg.botdriver.chatTyping.SendWithTyping(bot, line, doEmit)
	else
		doEmit()
	end
end

----------------------------------------------------------------------
-- MODE-band objective: push toward the freshest team contact at low
-- priority (soft), so a bot with its own direct sight always wins over this.
-- Flank slot offsets its approach 250-400u sideways of the point bot's line
-- to the contact. Regroup when far from the squad centroid with no contact.
----------------------------------------------------------------------

hg.botdriver.RegisterBehavior({
	name = "squad.push",
	band = "MODE",
	order = 15,
	finalize = false,
	CanRun = function(ctx)
		return not squadsDisabled() and not ctx.downed
	end,
	Run = function(ctx)
		local bot = ctx.bot
		local pos = squad.FreshestContact(bot)
		if pos then
			local info = squad.SquadOf(bot)
			local dest = pos
			if info and info.slot == "flank" then
				local point = squad.PointOf(bot)
				if IsValid(point) then
					local toContact = (pos - point:GetPos())
					toContact.z = 0
					if toContact:LengthSqr() > 1 then
						toContact:Normalize()
						local side = Vector(-toContact.y, toContact.x, 0)
						if bot:EntIndex() % 2 == 0 then side = -side end
						dest = pos + side * math.Rand(FLANK_OFFSET_MIN, FLANK_OFFSET_MAX)
					end
				end
			end
			hg.botdriver.SetObjective(bot, dest, 96, 4, "soft", "squad")
			return false -- soft: direct sight (ACQUIRE/COMBAT) still wins
		end

		-- Known gap fix (2026-09-22, formation movement): no contact, but the
		-- squad exists -- a non-point member holds a slot position relative
		-- to the point bot's current facing (Trauma's sv_squadmove.lua spacing/
		-- follow concept) instead of doing nothing until it's REGROUP_DIST
		-- away. This is what turns "everyone paths individually toward the
		-- objective" into a squad that visibly moves together; the old
		-- far-away regroup-to-centroid case below still covers a squad that
		-- has come apart (e.g. its point died mid-round).
		local info = squad.SquadOf(bot)
		local mates = squad.Squadmates(bot)
		if info and info.slot ~= "point" and #mates > 1 then
			local point = squad.PointOf(bot)
			if IsValid(point) and point ~= bot then
				local pointPos = point:GetPos()
				if bot:GetPos():DistToSqr(pointPos) > FORMATION_SLACK * FORMATION_SLACK then
					local faceDir = point:GetAimVector()
					faceDir.z = 0
					if faceDir:LengthSqr() < 1 then faceDir = Vector(1, 0, 0) else faceDir:Normalize() end
					local right = Vector(-faceDir.y, faceDir.x, 0)
					local dest
					if info.slot == "support" then
						dest = pointPos - faceDir * SUPPORT_BEHIND
					else -- flank
						local side = (bot:EntIndex() % 2 == 0) and 1 or -1
						dest = pointPos - faceDir * FLANK_BEHIND + right * (side * FLANK_SIDE)
					end
					hg.botdriver.SetObjective(bot, dest, 90, 3, "soft", "squad_formation")
				end
				return false -- soft: direct sight/a mode's own hard objective still wins
			end
		end

		-- No contact and no point to form on: regroup if far from centroid.
		if #mates > 1 then
			local centroid = Vector(0, 0, 0)
			local n = 0
			for _, m in ipairs(mates) do
				if IsValid(m) then centroid = centroid + m:GetPos() n = n + 1 end
			end
			if n > 0 then
				centroid = centroid / n
				if bot:GetPos():DistToSqr(centroid) > REGROUP_DIST * REGROUP_DIST then
					hg.botdriver.SetObjective(bot, centroid, 200, 4, "soft", "squad_regroup")
					-- Item 10: "regroup" callout when the objective triggers.
					-- EmitLine's own per-squad cooldown throttles the repeat
					-- calls this produces while the condition holds.
					squad.EmitLine(bot, "regroup")
				end
			end
		end
		return false
	end,
})

----------------------------------------------------------------------
-- Upkeep tick: rebuild dirty rosters, prune decayed contacts, feed contacts
-- from each bot's own already-computed target (no extra tracing). Single
-- Every(0.5) per the porting budget.
----------------------------------------------------------------------

hg.botdriver.Every("squad_upkeep", 0.5, function()
	if not hg.botdriver.Enabled() or squadsDisabled() then return end
	local now = CurTime()

	syncRosters()
	for team in pairs(rosterDirty) do rebuildSquads(team) end
	for team in pairs(contacts) do pruneContacts(team, now) end

	for bot, brain in pairs(hg.botdriver.brains) do
		if IsValid(bot) and bot:Alive() and bot:IsBot() and bot.zcBot then
			local team = hg.botdriver.TeamOf(bot)
			if team and IsValid(brain.target) then
				squad.ReportContact(team, brain.target, brain.target:GetPos(), now, bot)
			end
		end
	end
end)

-- Reload start: HGReloading (verified in sv_weaponscore.lua's infinite-reserve
-- hook against weapons/homigrad_base/sv_reload.lua) fires once per reload
-- begin, which is exactly the edge sv_squad.lua's handshake needs -- no
-- per-tick GetReloading() poll (that getter is not verified to exist).
-- Item 10: "down" callout when a bot's current target dies within 1s of the
-- bot's own last shot (brain.lastShotAt, set in sv_brain.lua's Engage).
hook.Add("PlayerDeath", "zc_bots_squad_down_callout", function(victim)
	if not hg.botdriver.Enabled() or squadsDisabled() then return end
	if not IsValid(victim) or not victim:IsPlayer() then return end
	local now = CurTime()
	for bot, brain in pairs(hg.botdriver.brains) do
		if bot ~= victim and IsValid(bot) and bot:Alive() and bot:IsBot() and bot.zcBot
			and brain.target == victim and now - (brain.lastShotAt or -math.huge) < 1 then
			squad.EmitLine(bot, "down")
			break
		end
	end
end)

-- Item 2 (NPC targeting): the OnNPCKilled equivalent of the "down" callout
-- above -- OnNPCKilled(npc, attacker, inflictor) is a real engine hook,
-- verified in use at defense/sv_defense_hooks.lua:241's "DefenseNPCKilled".
hook.Add("OnNPCKilled", "zc_bots_squad_npc_down_callout", function(deadNpc)
	if not hg.botdriver.Enabled() or squadsDisabled() then return end
	if not IsValid(deadNpc) then return end
	local now = CurTime()
	for bot, brain in pairs(hg.botdriver.brains) do
		if bot ~= deadNpc and IsValid(bot) and bot:Alive() and bot:IsBot() and bot.zcBot
			and brain.target == deadNpc and now - (brain.lastShotAt or -math.huge) < 1 then
			squad.EmitLine(bot, "down")
			break
		end
	end
end)

----------------------------------------------------------------------
-- Item 3 (2026-09-22, TDM kill trading): "a teammate just died here, killed
-- by X" -- one record per team (not per squad, so any nearby teammate can
-- react, matching sv_squad.lua's other team-wide state like `contacts`).
-- Cheap PlayerDeath early-return, no scan; consumed by
-- modes/sv_tdm.lua's mode.tdm_kill_trade, which itself bounds the reaction to
-- bots already near the death (not the whole team) and to KILL_TRADE_WINDOW.
----------------------------------------------------------------------

local teamDeath = {} -- team -> { pos = Vector, killer = Entity|nil, at = number }
local KILL_TRADE_WINDOW = 6

hook.Add("PlayerDeath", "zc_bots_squad_kill_trade_report", function(victim, _inflictor, attacker)
	if not hg.botdriver.Enabled() or squadsDisabled() then return end
	if not IsValid(victim) or not victim:IsPlayer() then return end
	local team = hg.botdriver.TeamOf(victim)
	if not team then return end
	teamDeath[team] = {
		pos = victim:GetPos(),
		killer = IsValid(attacker) and attacker or nil,
		at = CurTime(),
	}
end)

-- The team's most recent death report, or nil once KILL_TRADE_WINDOW has
-- passed. Plain field reads -- safe to call every decision.
function squad.TeamDeath(team)
	local rec = team and teamDeath[team]
	if not rec or CurTime() - rec.at > KILL_TRADE_WINDOW then return nil end
	return rec.pos, rec.killer, rec.at
end

hook.Add("HGReloading", "zc_bots_squad_reload_handshake", function(wep)
	if not IsValid(wep) then return end
	local owner = wep:GetOwner()
	if not IsValid(owner) or not owner.IsBot or not owner:IsBot() or not owner.zcBot then return end
	if squadsDisabled() then return end
	squad.OnReloadStart(owner, CurTime())
end)
