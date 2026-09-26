-- ulx quiet / !quiet (owner 2026-09-25): cap how loud a player's voice is, for everyone on the server.
--   !quiet kovak 50   everyone hears kovak at no more than 50% of the volume they set for him
--   !quiet * 30       every player but you
--   !quiet kovak 100  clears it
-- The server sets NWFloat "zc_voice_limit" (0..1) on the target; each client applies it on top of its own volume
-- setting (lua/zc_goobos/voice.lua, "Voice volume"). The limit is kept by SteamID for the rest of the map, so a
-- reconnect keeps it; a map change clears it.
local CATEGORY_NAME = "Chat"

if SERVER then
	ZCVoiceQuiet = ZCVoiceQuiet or {} -- [SteamID64] = limit 0..1
	hook.Add("PlayerInitialSpawn", "ZCVoiceQuiet.Restore", function(ply)
		local sid = not ply:IsBot() and ply:SteamID64() -- bots share one placeholder id: never persisted
		local v = sid and ZCVoiceQuiet[sid]
		if v then ply:SetNWFloat("zc_voice_limit", v) end
	end)
end

function ulx.quiet(calling_ply, target_plys, volume)
	if not SERVER then return end
	volume = math.Clamp(math.floor(tonumber(volume) or 50), 0, 100)
	local limit = volume / 100
	local affected = {}
	for _, ply in ipairs(target_plys) do
		if IsValid(ply) and ply ~= calling_ply then
			ply:SetNWFloat("zc_voice_limit", limit)
			local sid = not ply:IsBot() and ply:SteamID64()
			if sid then ZCVoiceQuiet[sid] = limit < 1 and limit or nil end
			affected[#affected + 1] = ply
		end
	end
	if #affected == 0 then
		ULib.tsayError(calling_ply, "No other players matched.", true)
		return
	end
	if volume >= 100 then
		ulx.fancyLogAdmin(calling_ply, "#A restored the voice volume of #T", affected)
	else
		ulx.fancyLogAdmin(calling_ply, "#A limited the voice volume of #T to #i percent", affected, volume)
	end
end

local quiet = ulx.command(CATEGORY_NAME, "ulx quiet", ulx.quiet, "!quiet")
quiet:addParam{ type = ULib.cmds.PlayersArg }
quiet:addParam{ type = ULib.cmds.NumArg, min = 0, max = 100, default = 50, hint = "volume", ULib.cmds.optional, ULib.cmds.round }
quiet:defaultAccess(ULib.ACCESS_ADMIN)
quiet:help("Limit a player's voice volume for everyone (0-100; 100 clears). * targets everyone but you.")
