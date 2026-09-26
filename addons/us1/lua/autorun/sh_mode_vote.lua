-- ============================================================
-- Mode Vote: at round end, a small box near the bottom of the
-- screen offers 4 choices - 1. Homicide  2. FFA  3. TDM
-- 4. Customs. Number keys 1-4 cast the vote (everyone votes:
-- alive, dead, spectators). Winner is rolled into a specific
-- mode and forced for the next round.
--
--  * Homicide rolls Standard / SOE / Gun Free Zone / Wild West.
--    Customs carries a separate map-gated fear chance (its own
--    ChanceFunction resolving > 0 is the approval test).
--  * Each category has its own weights, independent of natural rotation.
--    Zero excludes a listed mode only from that category.
--  * No votes cast -> natural rotation, nothing forced.
--  * Streak locks (zc_modevote_streak, default 3): Homicide locks
--    after N consecutive homicide-family rounds; FFA, TDM and
--    Customs share ONE streak - any mix of the three for N rounds
--    locks all three together until a non-trio round runs. Each
--    round feeds exactly one streak (Customs ballot wins count as
--    PvP only - no masscasualty/civilwar double counts).
--
-- Category mode weights are editable in F8 > Server > Mode votes.
-- Install/reload between ballots; changing weights needs no reload afterward.
--
-- Owner 2026-09-25 (modevote6): the ballot is now SIX different
-- random modes from the natural rotation (every mode the round
-- system could roll on this map: zb.GetModesChances() > 0, drawn
-- weighted by that same rotation chance) plus "Play again" - the
-- current mode once more, roles re-rolled by the new round. The
-- streak locks still apply: a locked family is left out of the
-- draw, and "Play again" locks with its family or after N rounds
-- of the same mode. zc_modevote_random 0 = the four categories
-- above, unchanged. Labels travel in zc_modevote_start, so the
-- clients (this file, lua/zc_goobos/roundend.lua) draw any count.
-- ============================================================

local QUORUM = 4 -- minimum total votes before the result applies

local CATEGORIES = {
	[1] = {
		label = "Homicide",
		modes = { "standard", "soe", "gunfreezone", "wildwest" },
		-- Defaults: Wild West about 15%; other Homicide modes about 28.3% each.
		weights = { ["wildwest"] = 0.53 },
	},
	[2] = {
		label = "FFA",
		modes = { "dm", "superfighters" },
	},
	[3] = {
		label = "TDM",
		modes = { "tdm", "hl2dm", "civilwar", "gwars",
			"uncontainedriot", "Cops/Gangsters" },
	},
	[4] = {
		label = "Customs",
		modes = { "masscasualty", "civilwar", "uncontainedriot",
			"Cops/Gangsters", "homelanderhns", "wildcard" },
		fearChance = 0.08, -- separate map-gated Customs roll
	},
}
local MAX_OPTS = 7 -- cast index travels as WriteUInt(i, 3): 1..7

if SERVER then
	AddCSLuaFile()

	util.AddNetworkString("zc_modevote_start")
	util.AddNetworkString("zc_modevote_cast")
	util.AddNetworkString("zc_modevote_tally")
	util.AddNetworkString("zc_modevote_end")
	util.AddNetworkString("zc_modevote_extend")

	-- work/loader/killcam_20260924/BRIEF_VOTES.md V4: was a fixed 6s local; now a convar so the
	-- owner can raise it for the early-voting flow (viewers need a fair window after their
	-- highlight ends too, see ModeVote_ExtendDeadline below).
	local cvVoteTime = CreateConVar("zc_modevote_time", "6", FCVAR_ARCHIVE, "Seconds the mode vote stays open.", 3, 60)
	local function VoteTime() return cvVoteTime:GetInt() end

	local active = false
	local voteEndsAt = 0 -- CurTime() deadline; ModeVote_EndsAt/ExtendDeadline below read and adjust it
	local sentTo = {} -- [ply]=true once they have gotten this round's ballot (broadcast or ModeVote_SendTo)

	-- work/loader/round_v2/BLUEPRINT.md S1.3: exposes the vote's own `active` flag so other
	-- systems can read it without a new state table. solidmapvote already reads exactly this
	-- name defensively (`ZC_MODEVOTE_ACTIVE and ZC_MODEVOTE_ACTIVE()`, sv_hooks.lua:36 and
	-- sv_mapvote.lua:166) but it was never defined anywhere in this tree until this line -
	-- lua/zc_bots/sv_lowpop.lua:52 has a comment noting exactly that gap. Defining it fixes that
	-- pre-existing dead safety check for free; it is also how zc_vote_manager.lua (Stage 1)
	-- detects when a mode-vote slot it granted has finished.
	function ZC_MODEVOTE_ACTIVE() return active end
	local votes = {} -- steamid -> ballot index

	local cvRandom = CreateConVar("zc_modevote_random", "1", FCVAR_ARCHIVE,
		"Mode vote ballot: 1 = six random rotation modes + play again, 0 = the four categories.", 0, 1)
	local RANDOM_OPTS = 6
	-- This vote's options, fixed at StartVote: {label, locked, again, key = forced mode (random ballot) or cat = category}
	local ballot = {}

	local function EligibleModes(cat)
		-- Category membership stays fixed; the admin panel edits its weights.
		-- zc_bots low-population lock: while it is active, drop modes the bots
		-- cannot play, so a low-pop ballot still lands on a round that has bots
		-- in it. Everything degrades to the unfiltered list when zc_bots is not
		-- loaded, when the lock is off, or when a category has no supported mode
		-- at all (Homicide has none by design -- bots do not play social
		-- deduction), so that category votes exactly as it does today.
		local allows = hg and hg.botdriver and hg.botdriver.LowpopVoteAllows
		if isfunction(allows) then
			local out = {}
			for _, m in ipairs(cat.modes) do
				local ok, permitted = pcall(allows, m)
				if not ok or permitted then out[#out + 1] = m end
			end
			if #out > 0 then return out end
		end
		return cat.modes
	end

	local function FearApproved()
		local f = zb.modes["fear"]
		local t = f and f.Types and f.Types.fear
		if t and t.ChanceFunction then
			local ok, v = pcall(t.ChanceFunction)
			return ok and type(v) == "number" and v == v and v > 0
		end
		return false
	end

	local function PickFrom(keys, weights)
		local total, last = 0, nil
		for _, k in ipairs(keys) do
			local weight = weights and weights[k] or 1
			if weight > 0 then total = total + weight; last = k end
		end
		if not last then return nil end
		local roll = math.Rand(0, total)
		for _, k in ipairs(keys) do
			local weight = weights and weights[k] or 1
			if weight > 0 then
				roll = roll - weight
				if roll < 0 then return k end
			end
		end
		return last
	end

	-- Category-specific vote weights. Natural rotation remains separate.
	local SETTINGS_PATH = "zc_modevote_weights.json"
	local settings = {schema = 1, categories = {}, fearChance = CATEGORIES[4].fearChance}
	for i, cat in ipairs(CATEGORIES) do
		local weights = {}
		for _, id in ipairs(cat.modes) do weights[id] = cat.weights and cat.weights[id] or 1 end
		settings.categories[tostring(i)] = weights
	end
	local storageError
	local function Finite(n) return type(n) == "number" and n == n and math.abs(n) < math.huge end
	local function ValidateSettings(data)
		if type(data) ~= "table" or data.schema ~= 1 or type(data.categories) ~= "table"
			or not Finite(data.fearChance) or data.fearChance < 0 or data.fearChance > 1 then return false end
		for key in pairs(data.categories) do if not tostring(key):match("^[1-4]$") then return false end end
		for i, cat in ipairs(CATEGORIES) do
			local weights, known, total = data.categories[tostring(i)], {}, 0
			if type(weights) ~= "table" then return false end
			for _, id in ipairs(cat.modes) do
				known[id] = true
				local n = weights[id]
				if not Finite(n) or n < 0 or n > 100 then return false end
				total = total + n
			end
			for id in pairs(weights) do if not known[id] then return false end end
			if total <= 0 then return false end
		end
		return true
	end
	local saved = file.Read(SETTINGS_PATH, "DATA")
	if saved then
		-- Preserve category IDs "1".."4" as strings when loading saved JSON.
		local decoded = #saved <= 16384 and util.JSONToTable(saved, false, true)
		if ValidateSettings(decoded) then settings = decoded
		else storageError = "Saved vote weights are invalid; editing is disabled to preserve the file." end
	end
	local function ApplyWeights()
		for i, cat in ipairs(CATEGORIES) do cat.weights = table.Copy(settings.categories[tostring(i)]) end
		CATEGORIES[4].fearChance = settings.fearChance
	end
	ApplyWeights()
	local function Token()
		local parts = {string.format("%.17g", settings.fearChance)}
		for i, cat in ipairs(CATEGORIES) do
			for _, id in ipairs(cat.modes) do parts[#parts + 1] = string.format("%.17g", settings.categories[tostring(i)][id]) end
		end
		return util.CRC(table.concat(parts, ":"))
	end
	local names = {standard="Standard",soe="State of Emergency",gunfreezone="Gun Free Zone",wildwest="Wild West",
		dm="Deathmatch",superfighters="Superfighters",tdm="Team Deathmatch",hl2dm="HL2 Deathmatch",civilwar="Civil War",
		gwars="Gang Wars",uncontainedriot="Uncontained Riot",["Cops/Gangsters"]="Cops/Gangsters",masscasualty="Mass Casualty",
		homelanderhns="Homelander HnS",wildcard="Wildcard"}
	names.fear, names.fear_soe = "Fear", "Fear (SOE)" -- modevote6: the random ballot can draw them
	ZC_MODEVOTE_WEIGHTS = {Version = "1.0.1"}
	function ZC_MODEVOTE_WEIGHTS.Status()
		local out = {available=true,canSave=not storageError,error=storageError,token=Token(),categories={},fearChance=settings.fearChance,fearApproved=FearApproved()}
		for i, cat in ipairs(CATEGORIES) do
			local group = {id=tostring(i),label=cat.label,rows={}}
			local total = 0
			for _, id in ipairs(cat.modes) do total = total + cat.weights[id] end
			for _, id in ipairs(cat.modes) do
				group.rows[#group.rows+1] = {id=id,title=names[id] or id,weight=cat.weights[id],percent=100*cat.weights[id]/total}
			end
			out.categories[#out.categories+1] = group
		end
		return out
	end
	function ZC_MODEVOTE_WEIGHTS.Change(ply, action, target, value)
		if not IsValid(ply) or not (ply:IsAdmin() or ply:IsSuperAdmin()) then return false,"Admin access required." end
		if storageError then return false,storageError end
		if type(value) ~= "string" or #value > 700 then return false,"Invalid request." end
		local request = util.JSONToTable(value)
		if type(request) ~= "table" or request.token ~= Token() then return false,"Weights changed; refresh and try again." end
		local n = request.value
		if not Finite(n) or n < 0 or n > 100 then return false,"Enter a weight from 0 to 100." end
		local nextSettings = table.Copy(settings)
		if action == "weight" then
			local category, id = tostring(target):match("^([1-4])|(.+)$")
			if not category or nextSettings.categories[category][id] == nil then return false,"Unknown vote category or mode." end
			nextSettings.categories[category][id] = n
		elseif action == "fear" and target == "4" then nextSettings.fearChance = n / 100
		else return false,"Unknown vote weight action." end
		if not ValidateSettings(nextSettings) then return false,"Keep at least one positive mode weight in every category." end
		local raw = util.TableToJSON(nextSettings, true)
		if type(raw) ~= "string" or #raw > 16384 then return false,"Could not encode vote weights." end
		local before = file.Read(SETTINGS_PATH, "DATA")
		local ok = pcall(file.Write, SETTINGS_PATH, raw)
		if not ok or file.Read(SETTINGS_PATH, "DATA") ~= raw then
			if before then pcall(file.Write, SETTINGS_PATH, before) else pcall(file.Delete, SETTINGS_PATH) end
			if file.Read(SETTINGS_PATH, "DATA") ~= before then storageError = "Save and recovery failed; check server storage before editing weights." end
			return false,storageError or "Save failed; previous weights retained."
		end
		settings = nextSettings
		ApplyWeights()
		return true,"Saved. Applies to the next category roll; an already-picked round stays unchanged."
	end

	local function Tally()
		local t = {}
		for i = 1, #ballot do t[i] = 0 end
		for _, v in pairs(votes) do
			if t[v] then t[v] = t[v] + 1 end
		end
		return t
	end

	-- wire: count (3 bits), then one byte per option
	local function WriteTally(t)
		net.WriteUInt(#ballot, 3)
		for i = 1, #ballot do net.WriteUInt(math.min(t[i] or 0, 255), 8) end
	end

	local function BroadcastTally()
		net.Start("zc_modevote_tally")
			WriteTally(Tally())
		net.Broadcast()
	end

	-- wire: seconds, count, then per option label / locked / "play again"
	local function WriteStart(seconds)
		net.WriteUInt(math.Clamp(seconds, 0, 255), 8)
		net.WriteUInt(#ballot, 3)
		for _, opt in ipairs(ballot) do
			net.WriteString(opt.label)
			net.WriteBool(opt.locked == true)
			net.WriteBool(opt.again == true)
		end
	end

	local appliedCategory = nil -- ballot index of the applied leader
	local customsRound = false

	-- streak state. Declared BEFORE ApplyLeader so its lock check
	-- captures these as upvalues - previously `locked` was declared
	-- AFTER the function, so ApplyLeader silently read a nil GLOBAL
	-- and the lock was never enforced in the live-apply path.
	--  * Homicide keeps its own consecutive streak.
	--  * FFA / TDM / Customs share ONE "PvP" streak: any mix of the
	--    three counts, and at the limit all three lock together
	--    until a non-trio round runs.
	local homicideStreak = 0
	local pvpStreak = 0
	local sameRound, sameStreak = nil, 0 -- consecutive rounds of the exact same mode ("Play again" lock)
	local locked = { false, false, false, false }
	local cv_streak = CreateConVar("zc_modevote_streak", "3", FCVAR_ARCHIVE,
		"Consecutive rounds before a ballot group locks (Homicide alone; FFA/TDM/Customs share one streak)", 1, 10)

	-- the customsRound flag is only TRUSTED when the round that
	-- actually started is a mode Customs can roll - if an admin
	-- zb_setforcemode's over the ballot's pick between apply and
	-- round start, the stale flag must not mislabel that round
	local CUSTOMS_MODES = { ["fear"] = true } -- cat-4's fearChance roll
	for _, m in ipairs(CATEGORIES[4].modes) do CUSTOMS_MODES[m] = true end

	local function RollCategory(i)
		local cat = CATEGORIES[i]
		if cat.fearChance and FearApproved() and math.Rand(0, 1) < cat.fearChance then
			return "fear"
		end
		return PickFrom(EligibleModes(cat), cat.weights)
	end

	-- LIVE application: the current leader is written into
	-- zb.nextround the moment it leads. However early the
	-- roundsystem rolls, an answer is already in place - the vote
	-- window never races the transition.
	local function ApplyLeader()
		local t = Tally()
		local total = 0
		for i = 1, #ballot do total = total + t[i] end
		-- quorum: below the threshold nothing is ever written -
		-- votes accumulate monotonically, so once reached it can't
		-- un-reach; live-apply simply unlocks at the 4th ballot
		if total < QUORUM then return end

		local best, bestN, ties = nil, 0, 0
		for i = 1, #ballot do
			if not ballot[i].locked then
				if t[i] > bestN then best = i bestN = t[i] ties = 1
				elseif t[i] == bestN and bestN > 0 then ties = ties + 1 end
			end
		end
		if not best or bestN == 0 then return end
		-- on a tie, keep whatever's already applied (no flip-flop)
		if ties > 1 and appliedCategory then return end

		if best ~= appliedCategory then
			appliedCategory = best
			local opt = ballot[best]
			local forced = opt.key or RollCategory(opt.cat)
			if forced then
				zb.nextround = forced
				customsRound = (opt.cat == 4)
				print("[ModeVote] leader: " .. opt.label ..
					" -> nextround '" .. forced .. "'")
			end
		end
	end

	local function CloseVote()
		if not active then return end
		active = false

		ApplyLeader() -- final word

		local opt = appliedCategory and ballot[appliedCategory]
		net.Start("zc_modevote_end")
			net.WriteString(opt and (opt.again and ("Play again: " .. opt.label) or opt.label) or "")
		net.Broadcast()

		if opt then
			print("[ModeVote] closed: " .. opt.label .. (opt.again and " (again)" or "") ..
				" (" .. table.concat(Tally(), "/") .. ")")
		else
			print("[ModeVote] no votes - natural rotation")
		end
		appliedCategory = nil
	end

	local votedThisRound = false
	local teamRound = false

	-- which vote category each round type belongs to
	local CATEGORY_OF = {
		-- homicide family
		["standard"] = 1, ["soe"] = 1, ["gunfreezone"] = 1,
		["masscasualty"] = 1, ["wildwest"] = 1,
		["fear"] = 1, ["fear_soe"] = 1,
		-- ffa
		["dm"] = 2,
		-- tdm family
		["tdm"] = 3, ["hl2dm"] = 3, ["civilwar"] = 3, ["criresp"] = 3,
		["gwars"] = 3, ["uncontainedriot"] = 3, ["wildcard"] = 3,
		["Cops/Gangsters"] = 3,
	}

	-- rounds where the early "decided" trigger must NOT fire:
	-- cstrike's own round logic breaks, fear's finale is theater
	local NO_EARLY = { ["cstrike"] = true, ["fear"] = true, ["fear_soe"] = true }

	local HMCD_FAM = {
		["standard"] = true, ["soe"] = true, ["gunfreezone"] = true,
		["wildwest"] = true, ["masscasualty"] = true,
	}

	local skipNext = false

	-- admin: suppress the next vote (one round), e.g. before a
	-- planned event round. modevote_skip again to cancel the skip.
	concommand.Add("modevote_skip", function(ply)
		if IsValid(ply) and not ply:IsAdmin() then return end
		skipNext = not skipNext
		local msg = skipNext and "[ModeVote] next vote will be SKIPPED"
			or "[ModeVote] skip cancelled - votes run normally"
		print(msg)
		if IsValid(ply) then ply:ChatPrint(msg) end
	end)

	-- the streak lock a mode falls under: Homicide family -> locked[1], FFA/TDM family -> the shared PvP lock
	local function FamilyLocked(key)
		local cat = CATEGORY_OF[key]
		if cat == 1 then return locked[1] end
		if cat == 2 or cat == 3 then return locked[2] end
		return false
	end

	local function ModeLabel(key)
		if names[key] then return names[key] end
		local main = zb:GetMode(key)
		local m = main and zb.modes[main]
		local t = m and istable(m.Types) and m.Types[key]
		local n = istable(t) and (t.PrintName or t.Name) or (m and m.PrintName)
		return (isstring(n) and n ~= "") and n or tostring(key)
	end

	-- keep a filtered list only when something survives the filter (EligibleModes' degrade rule)
	local function Narrow(list, keep)
		local out = {}
		for _, e in ipairs(list) do
			local ok, yes = pcall(keep, e.key)
			if not ok or yes then out[#out + 1] = e end
		end
		return #out > 0 and out or list
	end

	-- The random ballot: every mode the natural rotation could roll right now (same source as
	-- zb.RerollChances: zb.GetModesChances(), chance > 0 on this map), minus the current mode
	-- ("Play again" covers it), low-pop and streak-lock filtered, then drawn without replacement
	-- weighted by that rotation chance.
	local function RandomBallot()
		local out = {}
		local ok, chances = pcall(zb.GetModesChances)
		if not ok or not istable(chances) then
			print("[ModeVote] rotation pool unavailable: " .. tostring(chances))
			chances = {}
		end
		local pool = {}
		for key, w in pairs(chances) do
			if isstring(key) and isnumber(w) and w == w and w > 0 and w < math.huge and key ~= zb.CROUND then
				pool[#pool + 1] = { key = key, w = w }
			end
		end
		table.sort(pool, function(a, b) return a.key < b.key end) -- pairs order must not bias the draw
		local allows = hg and hg.botdriver and hg.botdriver.LowpopVoteAllows
		if isfunction(allows) then pool = Narrow(pool, allows) end
		pool = Narrow(pool, function(key) return not FamilyLocked(key) end)
		while #out < RANDOM_OPTS and #pool > 0 do
			local total = 0
			for _, e in ipairs(pool) do total = total + e.w end
			local roll, pick = math.Rand(0, total), #pool
			for i, e in ipairs(pool) do
				roll = roll - e.w
				if roll < 0 then pick = i break end
			end
			local e = table.remove(pool, pick)
			out[#out + 1] = { key = e.key, label = ModeLabel(e.key), locked = FamilyLocked(e.key) }
		end

		-- "Play again": the current mode, if the round system can still launch it here
		local cur = zb.CROUND
		local main = isstring(cur) and zb:GetMode(cur)
		local m = main and zb.modes[main]
		if m then
			local launch = true
			if isfunction(m.CanLaunch) then
				local ok2, can = pcall(m.CanLaunch, m)
				launch = ok2 and can and true or false
			end
			if launch then
				out[#out + 1] = { key = cur, label = ModeLabel(cur), again = true,
					locked = FamilyLocked(cur) or sameStreak >= cv_streak:GetInt() }
			end
		end
		return out
	end

	local function BuildBallot()
		if cvRandom:GetBool() then
			local b = RandomBallot()
			if #b > 0 then return b end
			print("[ModeVote] random ballot came up empty - using the categories")
		end
		local b = {}
		for i, cat in ipairs(CATEGORIES) do b[i] = { cat = i, label = cat.label, locked = locked[i] } end
		return b
	end

	local function StartVote()
		if active or votedThisRound then return end
		if zb.CROUND == "cstrike" then return end
		-- work/loader/round_v2/BLUEPRINT.md S1.3: dark unless zc_vote_manager.lua defines this
		-- AND its own convar is on (ZC_VoteManagerGate itself checks zc_vote_manager, defaulting
		-- to permissive). A refusal here does NOT set votedThisRound, so the next PlayerDeath or
		-- the ZB_EndRound fallback retries - the same queued-retry shape the map vote gets.
		if isfunction(ZC_VoteManagerGate) and not ZC_VoteManagerGate("mode") then return end
		if skipNext then
			skipNext = false
			votedThisRound = true -- fallback can't re-trigger it either
			print("[ModeVote] vote skipped this round (admin)")
			return
		end
		votedThisRound = true
		active = true
		votes = {}
		appliedCategory = nil
		sentTo = {}
		ballot = BuildBallot()
		local labels = {}
		for i, opt in ipairs(ballot) do labels[i] = (opt.again and "again:" or "") .. opt.label .. (opt.locked and "[locked]" or "") end
		print("[ModeVote] ballot: " .. table.concat(labels, " | "))
		local voteTime = VoteTime()
		voteEndsAt = CurTime() + voteTime
		net.Start("zc_modevote_start")
			WriteStart(voteTime)
		net.Broadcast()
		-- Everyone just got the ballot via the broadcast above; mark them sent so
		-- ModeVote_SendTo (work/loader/killcam_20260924/BRIEF_VOTES.md V1/V2) never
		-- re-delivers zc_modevote_start to a player who would just have their local
		-- vote/tally state reset by a second copy of it.
		for _, p in ipairs(player.GetHumans()) do sentTo[p] = true end
		timer.Create("ModeVote_Close", voteTime, 1, CloseVote)
	end

	-- work/loader/killcam_20260924/BRIEF_VOTES.md V1/V2: per-player send path for
	-- zc_vote_manager.lua's early-voting arbiter (a player who won't see the round-end killcam
	-- highlight, or whose own highlight just finished). Idempotent via sentTo; the normal
	-- StartVote broadcast above already marks every player present at open time as sent, so this
	-- is a no-op for them and only actually unicasts to someone the broadcast missed.
	function ModeVote_SendTo(ply)
		if not active or not IsValid(ply) then return false end
		if sentTo[ply] then return true end
		sentTo[ply] = true
		net.Start("zc_modevote_start")
			WriteStart(math.max(0, math.ceil(voteEndsAt - CurTime())))
		net.Send(ply)
		net.Start("zc_modevote_tally")
			WriteTally(Tally())
		net.Send(ply)
		return true
	end

	-- V3: extend the deadline through the vote's own state (never END_TIME). Reused by the
	-- arbiter when a vote would otherwise end less than zc_vote_min_window after a highlight ends.
	function ModeVote_EndsAt() return active and voteEndsAt or nil end
	function ModeVote_ExtendDeadline(extra)
		if not active or not isnumber(extra) or extra <= 0 then return false end
		extra = math.min(extra, 60)
		voteEndsAt = voteEndsAt + extra
		local remaining = timer.TimeLeft("ModeVote_Close")
		if remaining then timer.Adjust("ModeVote_Close", remaining + extra) end
		net.Start("zc_modevote_extend")
			net.WriteUInt(math.max(0, math.ceil(voteEndsAt - CurTime())), 8)
		net.Broadcast()
		return true
	end

	hook.Add("ZB_StartRound", "ModeVote_RoundReset", function()
		votedThisRound = false

		-- streak accounting - each round feeds EXACTLY ONE streak:
		--  * a round won on the Customs ballot (customsRound flag, set
		--    at apply time) counts ONLY toward the shared PvP streak,
		--    even when the rolled mode also maps to Homicide
		--    (masscasualty) or TDM (civilwar / uncontainedriot /
		--    Cops/Gangsters / wildcard) in CATEGORY_OF - the ballot's
		--    intent wins, no double counts
		--  * otherwise CATEGORY_OF decides: 1 -> Homicide streak
		--    (fear/fear_soe map to 1, so a fear round EXTENDS the
		--    homicide streak - it's a homicide-family experience),
		--    2 or 3 -> shared PvP streak
		--  * cstrike and unmapped rounds reset BOTH
		local cat = CATEGORY_OF[zb.CROUND or ""]
		local isCustoms = customsRound and CUSTOMS_MODES[zb.CROUND or ""] == true
		customsRound = false -- consumed
		local isHomicide = (cat == 1) and not isCustoms
		local isPvP = isCustoms or cat == 2 or cat == 3

		homicideStreak = isHomicide and homicideStreak + 1 or 0
		pvpStreak = isPvP and pvpStreak + 1 or 0
		sameStreak = (zb.CROUND ~= nil and zb.CROUND == sameRound) and sameStreak + 1 or 1
		sameRound = zb.CROUND

		local need = cv_streak:GetInt()
		locked[1] = homicideStreak >= need
		local pvpLocked = pvpStreak >= need
		locked[2], locked[3], locked[4] = pvpLocked, pvpLocked, pvpLocked

		print(("[ModeVote] round '%s' -> homicide streak %d%s | pvp streak %d%s")
			:format(tostring(zb.CROUND), homicideStreak, locked[1] and " LOCKED" or "",
				pvpStreak, pvpLocked and " (FFA/TDM/CUSTOMS LOCKED)" or ""))
		-- team round? snapshot after spawns settle
		timer.Simple(5, function()
			local teams = {}
			local n = 0
			for _, p in ipairs(zb:CheckAlive()) do
				local t = p:Team()
				if not teams[t] then teams[t] = true n = n + 1 end
			end
			teamRound = n >= 2
		end)
	end)

	-- the round is DECIDED: last player standing, last of a side in
	-- homicide, or a full team wiped in team modes. Vote starts the
	-- moment the outcome is settled - not at the formal round end.
	local function CheckDecided()
		if active or votedThisRound then return end
		if not zb.CROUND or NO_EARLY[zb.CROUND] then return end
		if zb.ROUND_STATE ~= 1 then return end
		-- rounds 0 and 1 of a fresh map never early-vote (world
		-- still filling); zb.Roundscount is the roundsystem's own
		-- counter, the same one natural RTV reads
		if (zb.Roundscount or 0) < 2 then return end
		if zb.ROUND_START and CurTime() - zb.ROUND_START < 15 then return end

		local alive = zb:CheckAlive()
		if #alive <= 1 then StartVote() return end

		if HMCD_FAM[zb.CROUND] then
			-- everyone left on the same side of the traitor line
			local side = alive[1].isTraitor == true
			for i = 2, #alive do
				if (alive[i].isTraitor == true) ~= side then return end
			end
			StartVote()
		elseif teamRound then
			local t = alive[1]:Team()
			for i = 2, #alive do
				if alive[i]:Team() ~= t then return end
			end
			StartVote()
		end
	end

	hook.Add("PlayerDeath", "ModeVote_Decided", function()
		timer.Simple(0.5, CheckDecided)
	end)

	-- fallback: rounds that end by timer or means no death triggered
	hook.Add("ZB_EndRound", "ModeVote_Start", function()
		if zb.CROUND == "cstrike" then return end
		timer.Simple(0.3, StartVote)
	end)

	net.Receive("zc_modevote_cast", function(_, ply)
		if not active or not IsValid(ply) then return end
		local v = net.ReadUInt(3)
		if v < 1 or v > #ballot then return end
		if ballot[v].locked then return end
		votes[ply:SteamID()] = v
		BroadcastTally()
		ApplyLeader()
	end)

	return
end

-- ======================= CLIENT =======================
local voteActive = false
local voteEnds = 0
local myVote = nil
local tally = {}

-- this vote's options as the server sent them: {label, locked, again}
local options = {}
local lockedCats = {} -- [i] = options[i].locked (Cast's gate)

-- work/loader/killcam_20260924/BRIEF_VOTES.md V5: don't pop the ballot on top of a running
-- killcam replay. Coded against ZCKillcamView with nil-guards, per the brief - none of these
-- names existed anywhere in lua/zc_killcam/ (or its patch copies) at the time this file was
-- written, since that contract belongs to the concurrently-worked killcam builder; every branch
-- below falls through to "not playing" (open immediately), matching today's behaviour, until it
-- lands. Checked in priority order: an explicit IsPlaying() query, then a boolean flag, then the
-- player's own zc_killcam_show client convar as a last, coarser signal (off means no replay to
-- interrupt, so it is not itself a "defer" reason - only used to short-circuit when the killcam
-- addon is not loaded at all and nothing else answered).
--
-- Adversarial review fix (2026-09-23): the defer had no off switch and no upper bound. Both are
-- fixed here, mirroring cl_net.lua's identical fix:
--  * `zc_vote_defer_killcam` (client convar, default 1) - default-on is acceptable only because
--    the defer is bounded (below), per the owner.
--  * `DEFER_TIMEOUT` (20s, RealTime()-based): if killcamPlaying() stays true this long, open
--    anyway rather than risk never opening.
local cvDeferKillcam = CreateClientConVar("zc_vote_defer_killcam", "1", true, false,
	"Wait for a running killcam replay to finish before opening the mode-vote panel (bounded to 20s). 0 = never wait.", 0, 1)
local DEFER_TIMEOUT = 20

local function killcamPlaying()
	if not cvDeferKillcam:GetBool() then return false end
	local V = ZCKillcamView
	if not istable(V) then return false end
	if isfunction(V.IsPlaying) then
		local ok, playing = pcall(V.IsPlaying)
		if ok then return playing == true end
	end
	if V.Playing ~= nil then return V.Playing == true end
	if V.playing ~= nil then return V.playing == true end
	if V.Life and V.Life.playing ~= nil then return V.Life.playing == true end
	return false
end

local pendingStart -- {endsAt, opts, armedAt}: a ballot held back while killcamPlaying() is true

local function applyStart(endsAt, opts)
	voteActive = true
	myVote = nil
	options = opts
	tally, lockedCats = {}, {}
	for i, o in ipairs(opts) do tally[i], lockedCats[i] = 0, o.locked end
	voteEnds = endsAt
end

net.Receive("zc_modevote_start", function()
	local seconds = net.ReadUInt(8)
	local opts = {}
	for i = 1, net.ReadUInt(3) do opts[i] = { label = net.ReadString(), locked = net.ReadBool(), again = net.ReadBool() } end
	local endsAt = CurTime() + seconds -- fixed now, so deferring the open below never shortens it
	if killcamPlaying() then
		pendingStart = { endsAt = endsAt, opts = opts, armedAt = RealTime() }
		return
	end
	applyStart(endsAt, opts)
end)

net.Receive("zc_modevote_extend", function()
	local endsAt = CurTime() + net.ReadUInt(8)
	if pendingStart then pendingStart.endsAt = endsAt
	elseif voteActive then voteEnds = endsAt end
end)

hook.Add("Think", "ModeVote_DeferredOpen", function()
	if not pendingStart then return end
	local timedOut = RealTime() - pendingStart.armedAt >= DEFER_TIMEOUT
	if not timedOut and killcamPlaying() then return end
	local p = pendingStart
	pendingStart = nil
	-- Stale-drop: the deadline (kept current by zc_modevote_extend above) already passed while
	-- we waited - the vote is over, so opening a panel to "vote" on it now would show a dead
	-- ballot. See cl_net.lua's identical fix for the map-vote side.
	if CurTime() >= p.endsAt then return end
	applyStart(p.endsAt, p.opts)
end)

net.Receive("zc_modevote_tally", function()
	for i = 1, net.ReadUInt(3) do tally[i] = net.ReadUInt(8) end
end)

local function optLabel(i)
	local o = options[i]
	if not o then return "" end
	return o.again and ("Play again: " .. o.label) or o.label
end

net.Receive("zc_modevote_end", function()
	pendingStart = nil
	voteActive = false
end)

local function Cast(i)
	if not voteActive or myVote == i then return end
	if lockedCats[i] then return end
	myVote = i
	net.Start("zc_modevote_cast")
		net.WriteUInt(i, 3)
	net.SendToServer()
end

-- number keys 1..#options: intercept the slot binds while the vote is up
hook.Add("PlayerBindPress", "ModeVote_Keys", function(ply, bind, pressed)
	if not voteActive or not pressed then return end
	local n = tonumber(string.match(bind or "", "^slot(%d)$"))
	if n and options[n] then Cast(n) return true end
end)

-- backup: raw key poll (rebound slots, dead players in odd states)
local lastPoll = 0
hook.Add("Think", "ModeVote_KeyPoll", function()
	if not voteActive then return end
	if CurTime() - lastPoll < 0.15 then return end
	lastPoll = CurTime()
	for i = 1, math.min(#options, MAX_OPTS) do
		if input.IsKeyDown(KEY_1 + i - 1) then Cast(i) break end
	end
end)

surface.CreateFont("ModeVote_Title", { font = "Bahnschrift", size = 18, weight = 800, antialias = true })
surface.CreateFont("ModeVote_Opt", { font = "Bahnschrift", size = 17, weight = 600, antialias = true })

local COL_BG = Color(15, 15, 18, 235)
local COL_ACC = Color(255, 230, 0)
local COL_TXT = Color(225, 225, 225)
local COL_DIM = Color(140, 140, 140)
local COL_LOCKED = Color(80, 80, 85)

-- The box eases in and out over 0.2 s (RealTime) with a 12 px rise; it keeps its last state while fading out.
local voteVis, voteVisAt = 0, RealTime()
-- Pre-restyle drawing, verbatim from the live A+B file; used when the GoobOS kit is not loaded.
local legacyDraw = function()
	local rnow = RealTime()
	local dt = math.Clamp(rnow - voteVisAt, 0, 0.1)
	voteVisAt = rnow
	voteVis = math.Approach(voteVis, voteActive and 1 or 0, dt / 0.2)
	if voteVis <= 0 then return end
	local ease = voteVis * voteVis * (3 - 2 * voteVis)
	local left = math.max(0, voteEnds - CurTime())

	local w, h = 260, 40 + #options * 26
	local x = math.floor(ScrW() / 2 - w / 2)
	local y = math.floor(ScrH() - h * 2 - 120 + (1 - ease) * 12)
	surface.SetAlphaMultiplier(ease)

	local total = 0
	for i = 1, #options do total = total + (tally[i] or 0) end
	local needQuorum = total < 4

	draw.RoundedBox(6, x, y, w, h + (needQuorum and 18 or 0), COL_BG)
	draw.SimpleText("NEXT ROUND?  (" .. math.ceil(left) .. "s)", "ModeVote_Title",
		x + 12, y + 8, COL_ACC)

	for i = 1, #options do
		local oy = y + 34 + (i - 1) * 26
		local mine = (myVote == i)
		local locked = lockedCats[i] == true
		draw.SimpleText(i .. ".  " .. optLabel(i), "ModeVote_Opt",
			x + 16, oy, locked and COL_LOCKED or (mine and COL_ACC or COL_TXT))
		draw.SimpleText(locked and "-" or tostring(tally[i] or 0), "ModeVote_Opt",
			x + w - 28, oy, locked and COL_LOCKED or (mine and COL_ACC or COL_DIM))
	end

	if needQuorum then
		draw.SimpleText("min 4 votes needed  (" .. total .. "/4)", "ModeVote_Opt",
			x + 16, y + h - 4, COL_DIM)
	end
	surface.SetAlphaMultiplier(1)
end

hook.Add("HUDPaint", "ModeVote_Draw", function()
	local K = ZCGoobApps and ZCGoobApps.Kit
	local T = ZCGoobApps and ZCGoobApps.Theme
	if not (K and K.HudPlate and T) then return legacyDraw() end
	local rnow = RealTime()
	local dt = math.Clamp(rnow - voteVisAt, 0, 0.1)
	voteVisAt = rnow
	voteVis = math.Approach(voteVis, voteActive and 1 or 0, dt / 0.2)
	if voteVis <= 0 then return end
	local ease = voteVis * voteVis * (3 - 2 * voteVis)
	local left = math.max(0, voteEnds - CurTime())

	-- 2026-09-25 HUD pass: GoobOS plate, keycaps and tokens; right-centre, clear of the bottom-centre stack.
	local s = K.HudScale()
	local total = 0
	for i = 1, #options do total = total + (tally[i] or 0) end
	local needQuorum = total < 4
	local pad, rowH, keyH = math.floor(14 * s), math.floor(30 * s), math.floor(22 * s)
	local w = math.floor(300 * s)
	local h = math.floor(40 * s) + #options * rowH + math.floor((needQuorum and 30 or 10) * s)
	local x = ScrW() - w - math.floor(24 * s)
	local y = math.floor(ScrH() * 462 / 1080 + (1 - ease) * 12 * s)
	surface.SetAlphaMultiplier(ease)
	K.HudPlate(x, y, w, h)
	local optFont = K.HudFont(16, 500)
	draw.SimpleText("Next round", K.HudFont(15, 700), x + pad, y + math.floor(12 * s), T.text)
	draw.SimpleText(math.ceil(left) .. "s", K.HudFont(15, 500), x + w - pad, y + math.floor(12 * s), T.muted, TEXT_ALIGN_RIGHT)

	for i = 1, #options do
		local oy = y + math.floor(40 * s) + (i - 1) * rowH
		local cy = oy + math.floor(rowH / 2)
		local mine = (myVote == i)
		local locked = lockedCats[i] == true
		local kw = K.HudKey(tostring(i), x + pad, cy - math.floor(keyH / 2), keyH, locked and 0.5 or 1)
		draw.SimpleText(optLabel(i), optFont, x + pad + kw + math.floor(10 * s), cy,
			locked and COL_LOCKED or (mine and T.accent or T.text), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText(locked and "-" or tostring(tally[i] or 0), optFont, x + w - pad, cy,
			locked and COL_LOCKED or (mine and T.accent or T.muted), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end

	if needQuorum then
		draw.SimpleText("Needs 4 votes (" .. total .. "/4)", K.HudFont(13, 500),
			x + pad, y + h - math.floor(10 * s), T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
	end
	surface.SetAlphaMultiplier(1)
end)
