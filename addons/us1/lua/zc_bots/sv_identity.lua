-- Item 1 (visual identity) + item 4 (ping seam): how a bot PRESENTS itself
-- to a human -- its look and its scoreboard-adjacent "connection quality" --
-- rather than anything about how it plays.
--
-- VISUAL IDENTITY -- what US1 already does (verified, not assumed):
--   * bots/us1/addons/zcity/gamemodes/zcity/gamemode/init.lua:205-229's
--     GM:PlayerSpawn calls ApplyAppearance(ply,nil,nil,nil,true) for every
--     spawning player whose round has not set CurrentRound().OverrideSpawn.
--   * main-design-source/lua/homigrad/new_appearance/sv_init.lua:123-129's
--     ApplyAppearance: `if bRandom or (Client.IsBot and Client:IsBot()) ...
--     then tAppearance = APmodule.GetRandomAppearance() ... WearAppearance
--     (...) return end` -- this branch is checked FIRST, before the
--     bUseCahsed/Client.CachedAppearance branch a human takes, so a bot's
--     model/clothes/bodygroups/facemap/accessory/name-color are already
--     randomised by the game itself on every single spawn via
--     hg.Appearance.GetRandomAppearance() (new_appearance/sh_shared.lua:437),
--     which only ever draws from the 15 models already registered in
--     PlayerModels[1|2] (sh_shared.lua:67-171: models/zcity/m/male_01..09.mdl,
--     models/zcity/f/female_01..06.mdl) -- the exact roster every human
--     character on this server already wears, so it is guaranteed
--     ValveBiped/organism-safe. No model path is invented here.
--
-- The actual tell: unlike a human (whose branch reuses Client.CachedAppearance
-- so their look is stable for their session), a bot's branch calls
-- GetRandomAppearance() fresh on EVERY spawn -- the same "player" can look
-- like a different person every time it respawns, and again on reconnect. A
-- real player's look does not change mid-session. This file caches one
-- rolled appearance per bot NAME (same survival contract as
-- sv_personality.lua's personalityByName: cleared only by a fresh Lua state,
-- i.e. a map change/restart) and re-applies it after every spawn via the
-- already-existing hg.Appearance.ForceApplyAppearance(ply, tbl) seam
-- (new_appearance/sv_init.lua:47, exposed at :119) -- the exact function the
-- playerclass system itself calls to reskin a player, so this is not a new
-- code path.
--
-- Defer-to-mode: every SupportedModes mode file was grepped this session for
-- SetPlayerClass/SetModel/ApplyAppearance. Role/team modes (tdm, gwars, riot,
-- hl2dm, defense, criresp, uncontainedriot, wildcard, coop) call
-- ply:SetPlayerClass(...), which sets ply.PlayerClassName
-- (playerclass/sv_tier_0.lua:11) and re-skins the bot itself (e.g.
-- sh_swat.lua's CLASS.On calls SetModel/ApplyAppearance again -- for tdm this
-- runs from MODE:GiveEquipment's timer.Simple(0.1, ...), i.e. after this
-- file's own timer.Simple(0, ...), so the mode's costume always wins the
-- race regardless). FFA-ish modes (dm, masscasualty, activeshooter, sfd,
-- mayhem, cstrike) never call SetPlayerClass, so this file's identity stays
-- in effect there. The guard below is ply.PlayerClassName being unset/"none"
-- ("none" is what Player:SetPlayerClass() sets on death,
-- playerclass/sv_tier_0.lua:6-7), so this file never fights a role costume.
--
-- PING SEAM (item 4): a bot's real Ping() is always 0 (no real connection) and
-- US1's scoreboard reads ply:Ping() directly -- client-side engine call, not
-- overridable from a server-only package. This publishes a stable, drifting,
-- plausible value as a netvar instead (verified server-authoritative --
-- see sv_chatter.lua's header for the SetNetVar/GetNetVar citation) for
-- anything client-side that chooses to prefer it; see the completion report
-- for the exact one-line scoreboard change this enables (not made here --
-- never edit files outside work/bots/).

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}

local cv_identity = ConVarExists("zc_bots_models") and GetConVar("zc_bots_models")
	or CreateConVar("zc_bots_models", "1", FCVAR_ARCHIVE,
		"Give each bot a stable, name-keyed appearance (reuses the server's own hg.Appearance random-appearance system) instead of a fresh reroll every spawn", 0, 1)

-- Name-keyed cache, same lifetime contract as sv_personality.lua's
-- personalityByName: survives a bot disconnect/reconnect within the same
-- map/Lua state, cleared only by a fresh Lua state (map change/restart).
hg.botdriver.appearanceByName = hg.botdriver.appearanceByName or {}
local appearanceByName = hg.botdriver.appearanceByName

local function hasRoleClass(ply)
	local name = ply.PlayerClassName
	return isstring(name) and name ~= "" and name ~= "none"
end

hook.Add("PlayerSpawn", "zc_bots_identity_apply", function(ply)
	if not cv_identity:GetBool() then return end
	if not hg.botdriver.Enabled() then return end
	if not ply:IsBot() or not ply.zcBot then return end
	local appearanceLib = hg.Appearance
	if not istable(appearanceLib) or not isfunction(appearanceLib.GetRandomAppearance)
		or not isfunction(appearanceLib.ForceApplyAppearance) then return end

	local name = ply.Nick and ply:Nick() or nil
	if not name then return end

	-- Deferred so it runs after GM:PlayerSpawn's own ApplyAppearance call for
	-- this same spawn (hook.Add listeners run before the gamemode's method,
	-- so a same-tick call here would be overwritten a moment later).
	timer.Simple(0, function()
		if not IsValid(ply) or not ply:Alive() then return end
		if hasRoleClass(ply) then return end -- a mode already costumed this bot; never fight it

		local appearance = appearanceByName[name]
		if not appearance then
			appearance = appearanceLib.GetRandomAppearance()
			appearanceByName[name] = appearance
		end
		appearanceLib.ForceApplyAppearance(ply, appearance)
	end)
end)

----------------------------------------------------------------------
-- Ping seam: pingBase is rolled once per bot life-cycle in
-- sv_personality.lua's rollPersonality (name-cached the same way every other
-- trait there is), so it survives reconnect within the map exactly like the
-- appearance above. This just drifts the published value a few ms every few
-- seconds and republishes only when the rounded value actually changes, so
-- an idle server sends no extra net traffic.
----------------------------------------------------------------------

local PING_DRIFT_STEP = 4    -- max ms nudge per publish tick, either direction
local PING_DRIFT_RANGE = 15  -- max ms the live value may wander from pingBase

hg.botdriver.Every("identity_ping", 5, function()
	if not hg.botdriver.Enabled() then return end
	for bot, brain in pairs(hg.botdriver.brains) do
		if IsValid(bot) and bot:IsBot() and bot.zcBot then
			local personality = brain.personality
			local base = personality and personality.pingBase
			if base then
				local current = bot.zcPingCurrent or base
				current = math.Clamp(current + math.Rand(-PING_DRIFT_STEP, PING_DRIFT_STEP), base - PING_DRIFT_RANGE, base + PING_DRIFT_RANGE)
				bot.zcPingCurrent = current
				local rounded = math.floor(current + 0.5)
				if bot.zcPingPublished ~= rounded then
					bot.zcPingPublished = rounded
					bot:SetNetVar("zcPing", rounded)
				end
			end
		end
	end
end)
