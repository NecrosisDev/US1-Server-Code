-- zc_bots population fill: keep a target headcount of AI players in play,
-- adapted from Trauma's gamemode/libraries/sv_botfill.lua.
--
-- Rules (owner spec, 2026-09-22 permanent-floor revision -- not a 1:1 port of
-- sv_botfill's mode-floor table):
--   * Bots exist only while zc_bots_enable 1 AND navmesh.IsLoaded().
--   * The server sits at AT LEAST zc_bots_fill_to total players (humans +
--     bots) as a gradual target, including with zero humans connected -- there is no
--     human-count ceiling above which bots stop existing any more. As humans
--     join, auto-fill bots leave one-for-one so the total holds at the floor;
--     once humans alone reach zc_bots_fill_to, the auto-fill bot count is 0.
--     (Retired: the old "zc_bots_humans_max" convar used to mean "drain every
--     bot once humans reach this many" -- a name that would now contradict a
--     floor rule, so it is gone rather than repurposed. The unrelated
--     low-population MODE-VOTE lock in sv_lowpop.lua keys off its own
--     zc_lowpop_humans convar and is untouched by this change.)
--   * Adds wait 45-120 seconds; removals use the 2s tick. Only when the round is
--     not live (isnumber(zb.ROUND_STATE) and zb.ROUND_STATE ~= 1).
--   * A zcBotManual (admin-added, zc_bots_add) bot counts toward the floor
--     total but is NEVER removed by this rule -- only auto-filled bots are.
--   * Only bots this file created (ply.zcBot = true) are ever touched.

if not SERVER then return end

hg = hg or {}
hg.botfill = hg.botfill or {}

local cv_fill_to = ConVarExists("zc_bots_fill_to") and GetConVar("zc_bots_fill_to")
	or CreateConVar("zc_bots_fill_to", "24", FCVAR_ARCHIVE, "Permanent floor: minimum total (humans + bots) headcount, maintained at all times", 0, 64)

-- A broad mix of ordinary names, low-effort handles, in-jokes and the kind of
-- mildly regrettable usernames people actually keep for years. Deliberately
-- avoids a single "edgy gamer tag" house style: repeated stylistic patterns
-- are a stronger bot tell than any individual name.
local NAME_POOL = {
	-- ordinary / first-name-ish
	"mason", "Nate", "jules", "Kev", "Mara", "owen", "Tess", "danny", "Ivy",
	"Cal", "robin", "Mitch", "bea", "Eli", "frankie", "Noah", "June", "wes",
	"lou", "Milo", "rory", "Sam R", "casey", "Drew", "nick", "leah", "Toby",
	"marcus", "evan", "joel", "andie", "cam", "Max", "ian", "sasha", "benji",
	"probably dan", "not kyle", "greg from work", "some guy named matt", "jen maybe",
	-- short handles people can actually say over voice
	"moth", "ferry", "tangent", "juniper", "pigeon", "moss", "racket", "sprout",
	"sleet", "parcel", "orbit", "stove", "velcro", "pluto", "marble", "bucket",
	"gasket", "porch", "lizard", "walnut", "radish", "cobweb", "puddle", "tarmac",
	"hush", "shovel", "otter", "badger", "coyote", "goblin", "wicker", "oxide",
	"loam", "bramble", "motel", "static", "spare", "cinder", "rook", "patches",
	-- mundane internet handles
	"coldpizza", "soggyfries", "leftovers", "parking_lot", "attic fan", "printerink",
	"laundrychair", "wrong password", "lowbattery", "midwestwifi", "packetloss",
	"microwave user", "freezer aisle", "receipt enjoyer", "night shift", "door hinge",
	"small rock", "wet socks", "desk lamp", "tap water", "expired coupon", "bus stop",
	"unpaid intern", "rent is due", "coffee stain", "mystery cable", "spare change",
	"out of office", "third floor", "no signal", "one clean fork", "fridge noise",
	-- game-adjacent without looking generated
	"mouse4", "ctrl_w", "brb_water", "defaultname", "loading...", "missed again",
	"wrong server", "spectator sport", "one more round", "inventory full", "bad timing",
	"solid 40 fps", "ping enjoyer", "audio bug", "last alive somehow", "no crosshair",
	"door stuck", "fall damage", "check corners", "nice spawn", "empty mag", "map knowledge",
	"friendly fire", "respawn pending", "spectating u", "held W", "wrong bind",
	-- dry / slightly dark
	"local problem", "future evidence", "mild concern", "poor decision", "bad alibi",
	"normal person", "harmless witness", "nothing happened", "legal reasons", "no comment",
	"unmarked van", "final notice", "last warning", "known issue", "acceptable loss",
	"insurance claim", "workplace incident", "cause unknown", "mostly harmless",
	"do not resuscitate", "closed casket", "pending investigation", "quiet quitting",
	-- older accounts and mixed-case holdovers
	"Kestrel", "NightOwl", "Copperhead", "Fenwick", "Redshift", "Deadbolt", "Lowtide",
	"Longshot", "Ashfall", "Backfire", "Sidewinder", "Firebreak", "Bluebottle",
	"raven_03", "xMarlow", "ToastActual", "CrateEnjoyer", "MrTuesday", "SoupOnline",
	"DirtWizard", "ChairForceOne", "TaxSeason", "GarageDweller", "LawnOrnament",
	"RandyOnline", "actualmoth", "kev2", "sam_alt", "user_404", "jules.mp3",
}

-- Ordinary handles are more common; occasional odd names still come from NAME_POOL.
local PLAIN_NAME_POOL = {"mason", "Nate", "jules", "Kev", "Mara", "owen", "Tess", "danny", "Ivy", "Cal", "robin", "Mitch", "bea", "Eli", "frankie", "Noah", "June", "wes", "lou", "Milo", "rory", "Sam R", "casey", "Drew", "nick", "leah", "Toby", "marcus", "evan", "joel", "andie", "cam", "Max", "ian", "sasha", "benji", "moth", "ferry", "tangent", "juniper", "pigeon", "moss", "racket", "sprout", "orbit", "pluto", "marble", "bucket", "velcro", "hush", "otter", "badger", "coyote", "oxide", "bramble", "static", "cinder", "rook", "patches", "Kestrel", "Fenwick", "Redshift", "Lowtide", "Bluebottle", "kev2", "sam_alt", "raven_03", "jules.mp3", "alex_g", "Dylan", "Jess", "chris91", "mikey", "matthew", "j0sh", "riley", "Seb", "andy_", "leo", "tyler", "nolan", "Patrick", "jamesb", "steven", "ken", "vincent", "Aaron", "dave_", "ray", "wade", "Bren", "Ollie", "Luis", "ren", "devon", "morgan", "benny", "jacob", "ruben", "bryce"}

local cv_nametag = ConVarExists("zc_bots_name_tag") and GetConVar("zc_bots_name_tag")
	or CreateConVar("zc_bots_name_tag", "", FCVAR_ARCHIVE,
		"Prefix added to NEW bot names so admins can spot them in-game, e.g. \"[B] \". Empty = indistinguishable.")

local function pickName(tag)
	tag = tag or ""
	local taken = {}
	for _, ply in ipairs(player.GetAll()) do taken[string.lower(ply:Nick())] = true end
	local function available(name) return not taken[string.lower(tag .. name)] end
	if math.random() < .75 then
		local plain = table.Copy(PLAIN_NAME_POOL)
		table.Shuffle(plain)
		for _, name in ipairs(plain) do if available(name) then return tag .. name end end
	end
	local tries = {}
	for i = 1, #NAME_POOL do tries[i] = i end
	table.Shuffle(tries)
	for _, i in ipairs(tries) do
		local name = NAME_POOL[i]
		if available(name) then return tag .. name end
	end
	local base = NAME_POOL[math.random(#NAME_POOL)]
	for suffix = 2, #player.GetAll() + 2 do
		local name = string.format("%s_%d", base, suffix)
		if available(name) then return tag .. name end
	end
end

local function humansPlaying()
	return #player.GetHumans()
end

local function managedBots()
	local bots = {}
	for _, ply in ipairs(player.GetAll()) do
		if ply:IsBot() and ply.zcBot then bots[#bots + 1] = ply end
	end
	return bots
end

local cv_headroom = ConVarExists("zc_bots_slot_headroom") and GetConVar("zc_bots_slot_headroom")
	or CreateConVar("zc_bots_slot_headroom", "8", FCVAR_ARCHIVE, "Free slots bots must always leave for humans", 2, 32)

local cv_autofill = ConVarExists("zc_bots_fill") and GetConVar("zc_bots_fill")
	or CreateConVar("zc_bots_fill", "0", FCVAR_ARCHIVE, "Automatic low-population fill (zc_bots_add works without it)")

local function addBot(manual)
	local connecting = player.GetCountConnecting and player.GetCountConnecting() or 0
	-- Bots never eat into the last human slots, whatever fill_to is set to.
	local reserve = manual and 1 or cv_headroom:GetInt()
	if player.GetCount() + connecting >= game.MaxPlayers() - reserve then return nil end
	local tag = cv_nametag:GetString()
	local bot = player.CreateNextBot(pickName(tag))
	if not IsValid(bot) then return nil end
	bot.zcBot = true
	bot.zcBotBaseName = bot:Nick()
	timer.Simple(1, function()
		-- Decide bench-vs-play for the round THIS bot was created into before
		-- ever touching its team -- covers a bot added mid-round (zc_bots_add
		-- works at any round state) into a mode with no bot profile
		-- (sv_bench.lua). Falls back to the old unconditional EnsurePlaying if
		-- that file is ever missing, same "degrade to prior behaviour" idiom
		-- sv_fill.lua's own Tick() already uses for hg.botdriver.presence.
		if hg.botfill.AssertBench then
			hg.botfill.AssertBench(bot)
		elseif hg.botfill.EnsurePlaying then
			hg.botfill.EnsurePlaying(bot)
		end
	end)
	bot.zcBotManual = manual or nil
	return bot
end

local function removeOneBot(bots)
	local victim
	for _, b in ipairs(bots) do
		if not b:Alive() then victim = b break end
	end
	victim = victim or bots[#bots]
	if IsValid(victim) then
		victim:Kick("zc_bots population adjustment")
		return true
	end
	return false
end

hg.botfill.AddBot = addBot
hg.botfill.RemoveBot = removeOneBot
-- Exported so sv_bench.lua's ZB_PreRoundStart handler can re-assert bench
-- state for every managed bot without a second player.GetAll() scan of its
-- own -- same list this file's own Tick() already builds from.
hg.botfill.ManagedBots = managedBots

local function cancelPendingJoin()
	local presence = hg.botdriver.presence
	if presence and presence.CancelJoin then presence.CancelJoin() end
end

function hg.botfill.Tick()
	if not hg.botdriver.Enabled() or not cv_autofill:GetBool() then cancelPendingJoin() return end
	if game.SinglePlayer() then cancelPendingJoin() return end
	if navmesh.IsGenerating() or not (navmesh.IsLoaded() or navmesh.GetNavAreaCount() > 0) then cancelPendingJoin() return end
	-- Only adjust population between rounds; a mid-round join/leave waits for
	-- the next non-live window.
	if isnumber(zb and zb.ROUND_STATE) and zb.ROUND_STATE == 1 then return end

	local humans = humansPlaying()
	local bots, manualCount = {}, 0
	for _, bot in ipairs(managedBots()) do
		if bot.zcBotManual then manualCount = manualCount + 1 else bots[#bots + 1] = bot end
	end

	-- Permanent floor: auto-fill only ever needs to cover whatever humans and
	-- already-present manual bots do not already provide toward the target.
	-- No human-count ceiling any more -- humans alone at/above the floor
	-- naturally drives `wanted` to 0, and zero humans connected still fills
	-- to the floor (see file header).
	local wanted = math.max(0, cv_fill_to:GetInt() - humans - manualCount)

	if #bots < wanted then
		-- Only the arrival scheduler may auto-fill. A missing scheduler must
		-- not fall back to a rapid two-second stream of new bots.
		if hg.botdriver.presence then
			hg.botdriver.presence.RequestJoin(wanted - #bots)
		end
	elseif #bots > wanted then
		cancelPendingJoin()
		removeOneBot(bots)
	elseif hg.botdriver.presence then
		cancelPendingJoin()
		-- Exactly at target: no necessity-driven add/remove this tick, so this
		-- is the only place organic session-length churn is allowed to fire.
		hg.botdriver.presence.ChurnTick(bots)
	end
end

-- hg.botfill.SupportedModes: modes with a REGISTERED mode profile
-- (RegisterModeProfile in a zc_bots/modes/*.lua file), i.e. bots get
-- mode-specific role/objective logic there. 2026-09-22 SECOND REVERSAL: this
-- table is the bench/play AUTHORITY again -- after watching bots play
-- Homicide badly under the brief "metadata only, everyone plays as generic
-- crowd" policy this comment used to describe, the owner asked for the
-- opposite of that: a round key NOT listed here now benches every zcBot to
-- TEAM_SPECTATOR for the whole round instead of letting it play as crowd
-- (zc_bots/sv_bench.lua owns the flag/team; zc_bots/sv_crowd.lua stays only
-- as the fallback for a single-team edge case INSIDE a listed/profiled mode,
-- see that file's own header). NOT verified to be drift-free: this session
-- found "hmcd" and "Cops/Gangsters" listed here with no matching
-- RegisterModeProfile call anywhere (sv_bench.lua header has the full
-- comparison) -- reported, not changed, per the owner's explicit
-- do-not-edit-the-list instruction. homelanderhns (2026-09-21, Part B):
-- MODE.name = "homelanderhns" (verified, US1
-- zc_homelander_complete/gamemodes/zcity/gamemode/modes/zz_homelanderhns/
-- sv_homelanderhns.lua:1 -- the folder is zz_homelanderhns, the round key is
-- not) keeps its own profile (civilian-hider bots only, modes/sv_homelanderhns.lua).
hg.botfill.SupportedModes = {
	hmcd = true, standard = true, soe = true, wildwest = true, gunfreezone = true,
	dm = true, tdm = true, hl2dm = true, cstrike = true, superfighters = true, masscasualty = true,
	activeshooter = true, gwars = true, criresp = true, riot = true, uncontainedriot = true,
	wildcard = true, mayhem = true, coop = true, defense = true, homelanderhns = true,
	["Cops/Gangsters"] = true,
}

hg.botdriver.Every("fill_tick", 2, hg.botfill.Tick)
-- LIVE FINDING 2026-09-22: a connecting player sits on TEAM_UNASSIGNED (1001)
-- and the gamemode only moves them onto the playing team when their CLIENT
-- sends net "ZB_SpecMode" (init.lua:399-409, `ply:SetTeam(1)` = "joined the
-- players"). A bot has no client, so it never sends it, drifts to
-- TEAM_SPECTATOR, and every mode's Intermission skips spectators -- so bots
-- never spawn into a round at all. Observed live: a bot sat at 1001 then
-- 1002 across a full gwars->hmcd transition, never spawning.
-- Do for the bot what the client does for a human. Team 1 matches the
-- gamemode's own "joined the players" value; the mode's Intermission then
-- reassigns it to a real team via PLAYER:SetupTeam (init.lua:197).
local function ensurePlaying(bot)
	if not IsValid(bot) or not bot.zcBot then return end
	if not hg.botdriver.Enabled() then return end
	-- 2026-09-22 bench reversal: sv_bench.lua is the SOLE authority on a
	-- zcBot's team now -- it flips ply.zcBotBenched and is the only place
	-- that ever calls SetTeam(TEAM_SPECTATOR) on one. Skipping here (instead
	-- of this function ever setting/clearing the flag itself) is what keeps
	-- the two files from fighting over team regardless of which of their
	-- ZB_PreRoundStart hooks happens to run first -- see sv_bench.lua's
	-- header for the ordering argument.
	if bot.zcBotBenched then return end
	local t = bot:Team()
	if t == TEAM_SPECTATOR or t == TEAM_UNASSIGNED then bot:SetTeam(1) end
end

hg.botfill.EnsurePlaying = ensurePlaying

-- Also re-assert just before each round is set up, in case something parked
-- the bot in the meantime. Runs alongside sv_bench.lua's own
-- "zc_bots_bench_preround" ZB_PreRoundStart hook -- their relative order
-- does not matter (see that file's header): this loop is a no-op for any
-- bot sv_bench.lua has (or is about to) bench, and sv_bench.lua positively
-- restores play itself for any bot it unbenches rather than relying on this
-- loop to have already done it.
hook.Add("ZB_PreRoundStart", "zc_bots_fill_join_round", function()
	for _, bot in ipairs(managedBots()) do ensurePlaying(bot) end
end)

hook.Add("ZB_PreRoundStart", "zc_bots_fill", hg.botfill.Tick)
hook.Add("ZB_EndRound", "zc_bots_fill", hg.botfill.Tick)

----------------------------------------------------------------------
-- Admin/testing commands. Work regardless of the fill rules above (still
-- require zc_bots_enable 1); superadmin or server console only.
----------------------------------------------------------------------

local function allowed(ply)
	return not IsValid(ply) or ply:IsSuperAdmin()
end

local function reply(ply, msg)
	if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end
end

-- zc_bots_add [n]: works at any player count and with auto-fill off; only the
-- last server slot is kept free. Admin-added bots are never touched by auto-fill.
concommand.Add("zc_bots_add", function(ply, _, args)
	if not allowed(ply) then return end
	if not hg.botdriver.Enabled() then reply(ply, "[zc_bots] zc_bots_enable is 0") return end
	local n = math.Clamp(tonumber(args[1]) or 1, 1, 32)
	local added = 0
	for _ = 1, n do
		if addBot(true) then added = added + 1 end
	end
	reply(ply, string.format("[zc_bots] added %d/%d bot(s); players %d/%d", added, n, player.GetCount(), game.MaxPlayers()))
	if not (navmesh.IsLoaded() or navmesh.GetNavAreaCount() > 0) then
		reply(ply, "[zc_bots] WARNING: this map has no navmesh - bots can aim and shoot but cannot path")
	end
	local mode = zb and (zb.CROUND_MAIN or zb.CROUND)
	if mode and not hg.botfill.SupportedModes[mode] then
		reply(ply, "[zc_bots] note: current mode '" .. tostring(mode) .. "' has no bot profile - added bot(s) will be benched to TEAM_SPECTATOR (see zc_bots_list/zc_bots_diagnose)")
	end
end)

-- Who is a bot? Bots are deliberately hard to spot in-game, so this is the
-- authoritative answer. Prints to the caller's own console.
concommand.Add("zc_bots_list", function(ply)
	if not allowed(ply) then return end
	local bots = managedBots()
	reply(ply, string.format("[zc_bots] %d bot(s), %d human(s), %d/%d slots, map=%s mode=%s",
		#bots, #player.GetHumans(), player.GetCount(), game.MaxPlayers(),
		game.GetMap(), tostring(zb and (zb.CROUND_MAIN or zb.CROUND))))
	for _, bot in ipairs(bots) do
		local brain = hg.botdriver.brains and hg.botdriver.brains[bot]
		local p = brain and brain.personality
		local role = bot.isTraitor and "TRAITOR" or (bot.MainTraitor and "MAIN" or "-")
		local benched = hg.botfill.IsBenched and hg.botfill.IsBenched(bot)
		reply(ply, string.format("  #%-3d %-20s team=%d %s %s role=%s%s%s%s",
			bot:EntIndex(), bot:Nick(), bot:Team(),
			bot:Alive() and "alive" or "dead ",
			hg.botdriver.IsDowned(bot) and "downed" or "      ",
			role,
			bot.zcBotManual and " [manual]" or "",
			p and string.format(" skill=%.2f aggr=%.2f", p.skill or 0, p.aggression or 0) or "",
			benched and (" BENCHED: " .. tostring(hg.botfill.BenchReason(bot))) or ""))
	end
	if #bots == 0 then reply(ply, "  (none -- zc_bots_enable is " .. tostring(hg.botdriver.Enabled()) .. ")") end
	reply(ply, "[zc_bots] other tells: console 'status' shows BOT in the steamid column; bots have no SteamID64.")
end)

concommand.Add("zc_bots_kick", function(ply)
	if not allowed(ply) then return end
	for _, bot in ipairs(managedBots()) do
		bot:Kick("zc_bots_kick")
	end
end)
