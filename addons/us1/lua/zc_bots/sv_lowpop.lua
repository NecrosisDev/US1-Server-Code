-- zc_bots low-pop mode lock: while the server is thin on humans, narrow the
-- round-vote candidate pool to a small, reliably-fun-with-bots set and bias
-- their weights, instead of letting the full mode roster (including modes
-- that need a crowd) come up.
--
-- Verified against the US1 reference tree
-- (us1/addons/zcity/gamemodes/zcity/gamemode/libraries/sv_roundsystem.lua):
--   * zb.GetAvailableModes() [287-311]: builds newtbl by iterating
--     zb.GetModes() (the zb.modes registry keys, which are each MODE.name --
--     see loader.lua:59,80). For each mode whose CanLaunch()/ForBigMaps gate
--     passes, if tbl.SubModes exists it inserts every entry SubModes()
--     returns instead of the registry key; otherwise it inserts the key
--     itself. Returns a plain array (ipairs-style) of mode-key strings --
--     no other fields, so filtering must only remove entries, never reshape
--     them.
--   * zb.GetChance(name, addtbl) [353-360]: signature is (name, addtbl).
--     Looks up mode := zb:GetMode(name), tbl := zb.modes[mode], then
--     newtbl := tbl.Types and tbl.Types[name] or tbl, and returns
--     newtbl.ChanceFunction and newtbl:ChanceFunction(addtbl or {})
--     or zb.ModesChances[name] or newtbl.Chance or 0.1. A mode with no
--     ChanceFunction, no ModesChances override and no authored .Chance
--     falls through to 0.1, NOT 0.
--   * zb.RerollChances() [448-460]: zb.RoundList = {} (full clear), refills
--     it with 20 fresh WeightedChanceMode(chances) picks, then pops the
--     first into zb.nextround. This is a full, idempotent rebuild -- calling
--     it again always starts from an empty table, so it cannot double up an
--     existing queue. Safe to call from ZB_EndRound when the lock's active
--     state has flipped.
--
-- Mode key spellings (loader.lua:59 "local name = MODE.name"; zb.modes is
-- keyed by MODE.name, not the folder name):
--   dm            -- modes/dm/sv_dm.lua:5           (Chance 0.04)
--   tdm           -- modes/tdm/sv_tdm.lua:3          (Chance 0.04)
--   hl2dm         -- modes/hl2dm/sv_hl2dm.lua:1      (Chance 0.05)
--   cstrike       -- modes/tdm_cstrike/sh_cstrike.lua:6 (folder is
--                    tdm_cstrike, MODE.name is "cstrike" -- confirmed, brief's
--                    caveat about the folder name was correct to flag but the
--                    round key really is "cstrike")
--   superfighters -- modes/sfd/sv_sfd.lua:3 (folder is sfd, MODE.name is
--                    "superfighters" -- confirmed; MODE.Chance = 0 at
--                    modes/sfd/sv_sfd.lua:12, matching the brief)
--   masscasualty  -- modes/zz_masscasualty/sh_zz_masscasualty.lua:4, Chance
--                    0.03 (line 6). This mode DOES define SubModes()
--                    (line 21-23) but SubModes() just returns {"masscasualty"}
--                    -- so GetAvailableModes still emits the literal key
--                    "masscasualty", same as brief's guess, via the SubModes
--                    branch rather than the plain-name branch.
--
-- Mode-vote seam (grepped work/bots/us1/** for ZC_MODEVOTE and sh_mode_vote,
-- and work/bots/** for any main-design-source or shitterhunt tree): neither
-- exists in this workspace snapshot. The only trace of a mode-vote layer is
-- the global ZC_MODEVOTE_ACTIVE(), read (never defined) at
-- us1/addons/zc_solidmapvote/lua/solidmapvote/core/server/sv_mapvote.lua:166
-- and .../sv_hooks.lua:36 as a "don't run the map-vote path while a mode vote
-- is active" gate. Its defining addon/file is not present in this checkout,
-- so there is no ballot-building code here to hook, and no file:line to name
-- for a filter seam -- this is a genuine absence-in-this-snapshot, not an
-- invented one. This file therefore only narrows the two zb functions that
-- feed every round-selection path (zb.CheckChances / zb.RerollChances /
-- zb.WeightedChanceMode all read zb.GetAvailableModes/zb.GetChance), which
-- covers the vote-candidate list indirectly if the absent mode-vote layer
-- itself calls zb.GetAvailableModes for its ballot -- unconfirmed.
--
-- Ships inert: zc_lowpop_lock defaults to "0".

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}

local cv_lock = ConVarExists("zc_lowpop_lock") and GetConVar("zc_lowpop_lock")
	or CreateConVar("zc_lowpop_lock", "0", FCVAR_ARCHIVE, "Lock the round vote to a small bot-friendly mode set while humans are below zc_lowpop_humans", 0, 1)
local cv_humans = ConVarExists("zc_lowpop_humans") and GetConVar("zc_lowpop_humans")
	or CreateConVar("zc_lowpop_humans", "10", FCVAR_ARCHIVE, "Below this many humans (and at least 1), zc_lowpop_lock narrows the mode pool", 1, 64)

hg.botdriver.cv_lowpop_lock = cv_lock
hg.botdriver.cv_lowpop_humans = cv_humans

-- Verified mode keys (see header, plus each mode's own modes/sv_<key>.lua
-- header for the 2026-09-21 Part A additions below). masscasualty is dropped
-- separately below when humans < 3, so it stays in the allowlist here.
--
-- 2026-09-21 additions (Part A): gwars, criresp, riot, uncontainedriot,
-- wildcard, mayhem, activeshooter are all fully bot-playable -- each mode's
-- own launch guard was verified this session to count bots toward its
-- player-count floor (player.Iterator()/zb:CheckPlaying() have no :IsBot()
-- filter anywhere in this addon tree, per each mode file's own header
-- citation), and each has a registered mode profile
-- (RegisterModeProfile/RegisterBehavior) in this package. activeshooter gets
-- a lock weight per the brief's own condition: its MODE.Chance is 0
-- (admin/vote only) but MODE:CanLaunch() is an unconditional `return true`
-- (sh_zz_activeshooter.lua:11-13), so it IS launchable standalone.
-- The owner's six are the rotation. The rest are bot-capable but opt-in
-- (zc_lowpop_extra_modes 1); criresp joined this opt-in EXTRA group
-- 2026-09-21 once modes/sv_criresp.lua gave bots a handcuff-arrest
-- objective (see EXTRA's own comment below).
local cv_extra = ConVarExists("zc_lowpop_extra_modes") and GetConVar("zc_lowpop_extra_modes")
	or CreateConVar("zc_lowpop_extra_modes", "0", FCVAR_ARCHIVE, "Also offer gwars/riot/uncontainedriot/wildcard/mayhem/activeshooter/coop/defense under the low-pop lock")
-- NPC targeting (2026-09-21): coop/defense join the EXTRA opt-in group, NOT
-- the default six -- both are PvE-heavy modes zc_bots's NPC targeting is new
-- and unproven for, so a low-pop server keeps them out of the narrowed pool
-- unless an admin explicitly opts in, same as gwars/riot/etc.
--
-- criresp (2026-09-21, Part A): joins EXTRA too, now that modes/sv_criresp.lua
-- gives bots a handcuff-arrest objective (the header note above about staying
-- out "until bots can play its handcuff objective" is resolved) -- still
-- opt-in, not one of the owner's default six, since the asymmetric SWAT-vs-
-- Suspects timing (SWAT doesn't even spawn for 90s) is new and unproven at
-- low pop.
local EXTRA = {
	gwars = true, riot = true, uncontainedriot = true, wildcard = true, mayhem = true, activeshooter = true,
	coop = true, defense = true, criresp = true,
}
local SHOOTER_MODES = { masscasualty = true, activeshooter = true }

local function allowed(key, humans)
	if EXTRA[key] and not cv_extra:GetBool() then return false end
	if SHOOTER_MODES[key] and humans < 3 then return false end
	return true
end

local ALLOWLIST = {
	-- Keep the native map/variant chances; Homicide now has a real bot profile.
	hmcd = true, standard = true, soe = true, wildwest = true, gunfreezone = true,
	dm = true,
	tdm = true,
	hl2dm = true,
	cstrike = true,
	superfighters = true,
	masscasualty = true,
	gwars = true,
	riot = true,
	uncontainedriot = true,
	wildcard = true,
	mayhem = true,
	activeshooter = true,
	coop = true,
	defense = true,
	criresp = true,
}

-- Relative weights across all 16 allowlisted modes (15 before the criresp
-- addition below; these summed to ~0.90, not exactly 1.0, even before this
-- addition -- not re-derived this pass, see the normalisation UNVERIFIED note
-- a few lines down). criresp is given a modest opt-in weight in line with the
-- other EXTRA-group modes (gwars/riot/etc), not the owner's default six.
-- NOTE (2026-09-21, report this): coop's native
-- MODE.Chance is 1 with MODE.ForBigMaps = true (modes/coop/sv_coop.lua:144-146)
-- -- outside the lock it is a routine, high-weight big-map pick -- and
-- defense's native MODE.Chance is 0 (modes/defense/sh_defense.lua:20, admin/
-- vote-only, never chosen by the random weighted pick on its own). Under the
-- lock with zc_lowpop_extra_modes enabled, BOTH values below fully replace
-- those native chances (zb.GetChance's wrap short-circuits before ever
-- reading MODE.Chance) -- so this lock downgrades coop from "a big map's
-- default filler mode" to a modest opt-in weight, and it is the ONLY thing
-- that makes defense reachable via the random pick at all while low-pop is
-- active. Whether WeightedChanceMode normalises weights that no longer sum to
-- exactly 1.0 across every mode still in GetAvailableModes (e.g. when a mode
-- is later hidden by CanLaunch()) was not independently re-verified this
-- session -- UNVERIFIED.
local LOCK_CHANCES = {
	dm = 0.09,
	tdm = 0.11,
	hl2dm = 0.09,
	cstrike = 0.09,
	superfighters = 0.07,
	masscasualty = 0.05,
	gwars = 0.07,
	riot = 0.06,
	uncontainedriot = 0.05,
	wildcard = 0.05,
	mayhem = 0.05,
	activeshooter = 0.04,
	coop = 0.05,
	defense = 0.03,
	criresp = 0.04,
}

local function lowpopActive()
	return cv_lock:GetBool() and #player.GetHumans() >= 1 and #player.GetHumans() < cv_humans:GetInt()
end

hg.botdriver.LowpopActive = lowpopActive

----------------------------------------------------------------------
-- Idempotent wrap of zb.GetAvailableModes. Guarded the same way a repeat
-- include (autorefresh) must not stack another layer of wrapping: only wrap
-- when the live zb.GetAvailableModes isn't already the wrapper this file
-- installed last time.
----------------------------------------------------------------------

local function wrapGetAvailableModes()
	if not (zb and zb.GetAvailableModes) then return end
	if zb.GetAvailableModes == hg.botdriver._lowpopGetAvailableModesWrapped then return end

	hg.botdriver._lowpopGetAvailableModesOriginal = zb.GetAvailableModes

	local original = hg.botdriver._lowpopGetAvailableModesOriginal

	local function wrapped(...)
		local result = original(...)
		if not lowpopActive() then return result end

		local humans = #player.GetHumans()
		local filtered = {}
		for _, key in ipairs(result) do
			if ALLOWLIST[key] and allowed(key, humans) then
				filtered[#filtered + 1] = key
			end
		end

		if #filtered == 0 then return result end
		return filtered
	end

	hg.botdriver._lowpopGetAvailableModesWrapped = wrapped
	zb.GetAvailableModes = wrapped
end

----------------------------------------------------------------------
-- Idempotent wrap of zb.GetChance, same guard idiom.
----------------------------------------------------------------------

local function wrapGetChance()
	if not (zb and zb.GetChance) then return end
	if zb.GetChance == hg.botdriver._lowpopGetChanceWrapped then return end

	hg.botdriver._lowpopGetChanceOriginal = zb.GetChance

	local original = hg.botdriver._lowpopGetChanceOriginal

	local function wrapped(name, addtbl)
		if lowpopActive() and ALLOWLIST[name] and LOCK_CHANCES[name]
			and allowed(name, #player.GetHumans()) then
			return LOCK_CHANCES[name]
		end
		return original(name, addtbl)
	end

	hg.botdriver._lowpopGetChanceWrapped = wrapped
	zb.GetChance = wrapped
end

wrapGetAvailableModes()
wrapGetChance()

-- zb may not exist yet at include time (load order); retry once shortly
-- after in case this file loaded before the round system did. Harmless if
-- zb was already present -- both wrappers no-op when already installed.
timer.Simple(0, function()
	wrapGetAvailableModes()
	wrapGetChance()
end)
hook.Add("InitPostEntity", "zc_bots_lowpop_install", function()
	wrapGetAvailableModes()
	wrapGetChance()
end)

----------------------------------------------------------------------
-- End-of-round rebuild: if the lock's active/inactive state flipped since
-- zb.RoundList was last built, force a fresh rebuild so the queue reflects
-- the new pool/weights. zb.RerollChances() clears zb.RoundList before
-- refilling it (verified above), so calling it again is a plain rebuild,
-- never a double-populate.
----------------------------------------------------------------------

hg.botdriver._lowpopLastActive = hg.botdriver._lowpopLastActive
if hg.botdriver._lowpopLastActive == nil then
	hg.botdriver._lowpopLastActive = lowpopActive()
end

local function onEndRound()
	local active = lowpopActive()
	if active ~= hg.botdriver._lowpopLastActive then
		hg.botdriver._lowpopLastActive = active
		if zb and zb.RerollChances then
			zb.RerollChances()
		end
	end
end

hook.Add("ZB_EndRound", "zc_bots_lowpop", onEndRound)

----------------------------------------------------------------------
-- Status command: server console or superadmin only (same gate as sv_fill's
-- zc_bots_add/zc_bots_kick).
----------------------------------------------------------------------

-- Named apart from allowed(key, humans) above: this used to be a second
-- `local function allowed`, which shadowed the mode rule for every function
-- defined after it -- LowpopVoteAllows then ran this admin check on a mode
-- string (always true), so the vote ignored zc_lowpop_extra_modes and the
-- shooter-mode human minimum (2026-09-25).
local function adminAllowed(ply)
	return not IsValid(ply) or ply:IsSuperAdmin()
end

-- Vote seam. The live mode vote (addons/admin_max_karma/lua/autorun/
-- sh_mode_vote.lua) rolls its ballot from its own hardcoded category lists and
-- writes zb.nextround directly, so neither GetAvailableModes nor GetChance sees
-- it. Its EligibleModes() calls this to drop modes the bots cannot play while
-- the lock is active. Returns true for everything when the lock is off, so the
-- vote behaves exactly as before.
function hg.botdriver.LowpopVoteAllows(modeKey)
	if not lowpopActive() then return true end
	if not ALLOWLIST[modeKey] then return false end
	return allowed(modeKey, #player.GetHumans())
end

concommand.Add("zc_lowpop_status", function(ply)
	if not adminAllowed(ply) then return end

	local active = lowpopActive()
	local humans = #player.GetHumans()
	local keys = {}
	if zb and zb.GetAvailableModes then
		for _, key in ipairs(zb.GetAvailableModes()) do
			keys[#keys + 1] = key
		end
	end

	local msg = string.format(
		"[zc_lowpop] active=%s humans=%d modes=%s",
		tostring(active), humans, table.concat(keys, ",")
	)

	if IsValid(ply) then
		ply:PrintMessage(HUD_PRINTCONSOLE, msg)
	else
		print(msg)
	end
end, nil, "Superadmin: print the low-population mode lock and its mode pool.")
