-- Relationship memory (design brief section 2, owner-approved 2026-09-22):
-- each bot keeps a small ledger of the HUMANS it has history with -- who
-- killed it, who it killed, who patched it up -- keyed by SteamID64 and kept
-- across maps in data/zc_bots/relations.json. The ledger changes two things:
--
--   1. Target choice (lib.AcquireTargetStep consults TargetBias): a player who
--      keeps killing this bot gets focused, scaled by the bot's `grudge`
--      trait; a player who bandaged it does not get shot FIRST next time it
--      has a choice, scaled by `sportsmanship`. Both are score nudges only --
--      a lone attacker is always answered.
--   2. Recognition: spotting a repeat killer raises the odds of the "spotted"
--      voiceline (OnAcquire); shortly after a round opens, a bot that can see
--      someone who healed it before throws a thumbs-up once.
--
-- Seams used (verified on the live tree 2026-09-23):
--   * PlayerDeath(victim, inflictor, attacker) -- engine hook.
--   * ZCity_MedicineUsed(healer, target, healMode, done) -- fired by
--     weapon_bandage_sh.lua's SecondaryAttack family; lua/zc_killcam/
--     sv_points.lua:113 consumes it the same way (target may be the patient's
--     fake ragdoll; resolve via target.organism.owner).
--   * sv_radial.lua's OnCallout("spotted") and OnGesture("thumb_up").
--
-- Bounded: 400 bot names x 24 peers, records older than 21 days pruned on
-- load, saved at most once per 60 s and on disconnect.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}
hg.botdriver.relations = hg.botdriver.relations or {}
local R = hg.botdriver.relations

local FILE = "zc_bots/relations.json"
local MAX_BOTS = 400
local MAX_PEERS = 24
local STALE_DAYS = 21
local SAVE_INTERVAL = 60

local KILLER_BIAS = 0.15       -- per kill on us, up to 4 kills, times grudge
local HEALER_BIAS = 0.35       -- per heal, up to 2 heals, times sportsmanship
local GREET_DELAY_MIN, GREET_DELAY_MAX = 8, 22
local GREET_RANGE = 380

R.ledger = R.ledger or nil
R.dirty = R.dirty or false

local function loadLedger()
	if R.ledger then return R.ledger end
	local ledger = {}
	if file.Exists(FILE, "DATA") then
		-- ignoreConversions: util.JSONToTable otherwise turns the SteamID64
		-- keys into doubles (2026-09-25: live relations.json held
		-- "7.6561199178124e+16"), which R.Get's string lookup never matches
		-- and the next save writes back mangled.
		local ok, parsed = pcall(util.JSONToTable, file.Read(FILE, "DATA") or "", false, true)
		if ok and istable(parsed) then ledger = parsed end
	end
	local cutoff = os.time() - STALE_DAYS * 86400
	for botName, peers in pairs(ledger) do
		if not istable(peers) or not isstring(botName) then
			ledger[botName] = nil
		else
			for id, rec in pairs(peers) do
				-- A key that is not a 17-digit SteamID64 string was mangled by an
				-- earlier load/save cycle and can never match a player again.
				local validId = isstring(id) and string.match(id, "^%d+$") ~= nil and #id == 17
				if not validId or not istable(rec) or (tonumber(rec.at) or 0) < cutoff then peers[id] = nil end
			end
			if next(peers) == nil then ledger[botName] = nil end
		end
	end
	R.ledger = ledger
	return ledger
end

local function save()
	if not R.dirty or not R.ledger then return end
	R.dirty = false
	file.CreateDir("zc_bots")
	local ok, json = pcall(util.TableToJSON, R.ledger)
	if ok and isstring(json) then file.Write(FILE, json) end
end

hg.botdriver.Every("relations_save", SAVE_INTERVAL, save)
hook.Add("ShutDown", "zc_bots_relations_shutdown", save)

local function prune(tbl, max, keyOfAge)
	local count = 0
	for _ in pairs(tbl) do count = count + 1 end
	while count > max do
		local oldestKey, oldestAt
		for k, v in pairs(tbl) do
			local at = keyOfAge(v)
			if not oldestAt or at < oldestAt then oldestKey, oldestAt = k, at end
		end
		if not oldestKey then break end
		tbl[oldestKey] = nil
		count = count - 1
	end
end

local function botName(bot)
	return IsValid(bot) and bot:IsBot() and bot.zcBot and bot:Nick() or nil
end

local function humanID(ply)
	if not IsValid(ply) or not ply:IsPlayer() or ply:IsBot() then return nil end
	local id = ply:SteamID64()
	if not isstring(id) or id == "" then return nil end
	return id
end

local function peersOf(name, create)
	local ledger = loadLedger()
	local peers = ledger[name]
	if not peers and create then
		peers = {}
		ledger[name] = peers
		prune(ledger, MAX_BOTS, function(p)
			local newest = 0
			for _, rec in pairs(p) do newest = math.max(newest, tonumber(rec.at) or 0) end
			return newest
		end)
	end
	return peers
end

local function touch(bot, ply, field)
	local name, id = botName(bot), humanID(ply)
	if not name or not id then return end
	local peers = peersOf(name, true)
	local rec = peers[id]
	if not rec then
		rec = { k = 0, d = 0, h = 0, at = 0, n = ply:Nick() }
		peers[id] = rec
		prune(peers, MAX_PEERS, function(r) return tonumber(r.at) or 0 end)
	end
	rec[field] = (tonumber(rec[field]) or 0) + 1
	rec.at = os.time()
	rec.n = ply:Nick()
	R.dirty = true
	return rec
end

function R.Get(bot, ply)
	local name, id = botName(bot), humanID(ply)
	if not name or not id then return nil end
	local peers = peersOf(name, false)
	return peers and peers[id] or nil
end

-- Score nudge for lib.AcquireTargetStep. Positive = more likely to be picked.
function R.TargetBias(bot, brain, ply)
	local rec = R.Get(bot, ply)
	if not rec then return 0 end
	local personality = brain and brain.personality
	local grudge = personality and personality.grudge or 0.4
	local sports = personality and personality.sportsmanship or 0.5
	local bias = KILLER_BIAS * math.min(tonumber(rec.k) or 0, 4) * grudge
	bias = bias - HEALER_BIAS * math.min(tonumber(rec.h) or 0, 2) * sports
	return bias
end

-- Recognition on (re)acquisition: a repeat killer is worth a callout.
function R.OnAcquire(bot, brain, now, target)
	local rec = R.Get(bot, target)
	if not rec or (tonumber(rec.k) or 0) < 2 then return end
	local radial = hg.botdriver.radial
	if radial and radial.OnCallout then radial.OnCallout(bot, brain, "spotted", 0.9) end
end

hook.Add("PlayerDeath", "zc_bots_relations_death", function(victim, _, attacker)
	if not IsValid(victim) or not IsValid(attacker) or victim == attacker then return end
	if not attacker:IsPlayer() then return end
	if victim:IsBot() then touch(victim, attacker, "k") end
	if attacker:IsBot() then touch(attacker, victim, "d") end
end)

hook.Add("ZCity_MedicineUsed", "zc_bots_relations_heal", function(healer, target, _, done)
	if not done or not IsValid(healer) or not healer:IsPlayer() or healer:IsBot() then return end
	local patient = target
	if IsValid(patient) and not (patient.IsPlayer and patient:IsPlayer()) then
		local org = patient.organism
		patient = org and org.owner or nil
	end
	if not IsValid(patient) or not patient:IsPlayer() or not patient:IsBot() then return end
	touch(patient, healer, "h")
end)

hook.Add("PlayerDisconnected", "zc_bots_relations_leave", function(ply)
	if IsValid(ply) and ply:IsBot() and ply.zcBot then save() end
end)

-- Greeting: a little after the round opens, a bot that can see someone who
-- has healed it before gives a thumbs-up (once per round per bot).
hook.Add("ZB_PreRoundStart", "zc_bots_relations_greet", function()
	if not hg.botdriver.Enabled() then return end
	timer.Simple(math.Rand(GREET_DELAY_MIN, GREET_DELAY_MAX), function()
		local radial = hg.botdriver.radial
		if not radial or not radial.OnGesture then return end
		local lib = hg.botdriver.lib
		for bot, brain in pairs(hg.botdriver.brains) do
			if IsValid(bot) and bot:Alive() and bot.zcBot and not bot.zcBotBenched and not hg.botdriver.IsDowned(bot) then
				local peers = peersOf(bot:Nick(), false)
				if peers then
					for _, ply in ipairs(player.GetHumans()) do
						local rec = peers[humanID(ply) or ""]
						if rec and (tonumber(rec.h) or 0) >= 1 and ply:Alive()
							and bot:GetPos():DistToSqr(ply:GetPos()) <= GREET_RANGE * GREET_RANGE
							and lib and lib.VisualContact and lib.VisualContact(bot, ply, brain, false, CurTime()) then
							if radial.OnGesture(bot, brain, "thumb_up", 0.8) then
								hg.botdriver.stats = hg.botdriver.stats or {}
								hg.botdriver.stats.greetings = (hg.botdriver.stats.greetings or 0) + 1
							end
							break
						end
					end
				end
			end
		end
	end)
end)

concommand.Add("zc_bots_relations", function(ply)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	local function out(line)
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
	end
	local ledger = loadLedger()
	local bots = 0
	for name, peers in pairs(ledger) do
		bots = bots + 1
		for id, rec in pairs(peers) do
			out(string.format("%-24s %-24s killedMe=%d iKilled=%d healedMe=%d  [%s]",
				name, tostring(rec.n), tonumber(rec.k) or 0, tonumber(rec.d) or 0, tonumber(rec.h) or 0, id))
		end
	end
	out(string.format("zc_bots_relations: %d bots with history", bots))
end)

loadLedger()
