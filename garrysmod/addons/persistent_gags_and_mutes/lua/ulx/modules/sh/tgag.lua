
-- Created by RussEfarmer on 11/26/2020 for Dinklebergs Gmod
-- These commands are adapted from the votemute, votegag and pgag commands in cobalt77's "Custom-ULX-Commands" package (https://github.com/cobalt77/Custom-ULX-Commands)

-- ZCity timed-gag repair v1.0.0. Keep the original remaining-minutes
-- persistence format and ULX command names/access rules.
local function InvalidateBridge(ply)
    local bridge = ULXZChatBridge
    if bridge and type(bridge.PDataCache) == "table" then
        bridge.PDataCache[ply] = nil
    end
end

local function RemainingMinutes(ply)
    local raw = ply:GetPData("tgagged")
    local minutes = tonumber(raw)
    if minutes and minutes == minutes and minutes > 0 and minutes < math.huge then
        return minutes, raw
    end
    return nil, raw
end

local function ClearTimedGag(ply)
    if not IsValid(ply) then return end
    -- Always clear both halves, including zero/absent PData with a stale flag.
    -- Permanent ULX gag and all mute state are deliberately separate.
    ply:RemovePData("tgagged")
    ply.tgagged = nil
    InvalidateBridge(ply)
end

local function RestoreTimedGag(ply)
    if not IsValid(ply) then return end
    local remaining = RemainingMinutes(ply)
    if remaining then
        ply.tgagged = true
        InvalidateBridge(ply)
    else
        ClearTimedGag(ply)
    end
end

--Hook to gag players
if SERVER then
	hook.Remove("PlayerCanHearPlayersVoice", "tgaghook")
	hook.Add("PlayerCanHearPlayersVoice", "tgaghook", function(listener, talker)
		if IsValid(talker) and talker.tgagged then return false end
	end)
end

-- Restore only a positive saved duration; "0" is truthy in Lua.
if SERVER then
    hook.Remove("PlayerAuthed", "tgagretryhook")
    hook.Add("PlayerAuthed", "tgagretryhook", RestoreTimedGag)
end

--ULX tgag command
function ulx.tgag( calling_ply, target_ply, minutes)
	minutes = math.ceil(minutes)
	target_ply:SetPData("tgagged", minutes)
	target_ply.tgagged = true
	InvalidateBridge(target_ply)
	ulx.fancyLogAdmin( calling_ply, "#A has gagged #T for #i minute(s)", target_ply, minutes )
end
local tgag = ulx.command( "Chat", "ulx tgag", ulx.tgag, "!tgag" )
tgag:defaultAccess( ULib.ACCESS_ADMIN )
tgag:addParam{ type=ULib.cmds.PlayerArg }
tgag:addParam{ type=ULib.cmds.NumArg, min=1, max=60, default=3, hint="minutes", ULib.cmds.optional, ULib.cmds.round }
tgag:help( "Gags a player for a number of minutes." )

-- Preserve the original once-per-minute, connected-player countdown.
-- Expire the actual player object synchronously: no nickname targeting,
-- half-second delayed callback, or race against a newly issued gag.
if SERVER then
    timer.Create("tgagtimer", 60, 0, function()
        for _, ply in ipairs(player.GetAll()) do
            if IsValid(ply) then
                local remaining, raw = RemainingMinutes(ply)
                if remaining then
                    remaining = remaining - 1
                    if remaining <= 0 then
                        ulx.untgag(nil, {ply})
                    else
                        ply:SetPData("tgagged", remaining)
                        ply.tgagged = true
                        InvalidateBridge(ply)
                    end
                elseif raw ~= nil or ply.tgagged ~= nil then
                    ClearTimedGag(ply)
                end
            end
        end
    end)
end

--ULX untgag command
function ulx.untgag(calling_ply, target_plys)
    local cleared = {}
    for _, ply in ipairs(target_plys) do
        if IsValid(ply) then
            ClearTimedGag(ply)
            cleared[#cleared + 1] = ply
        end
    end
    if #cleared > 0 then
        ulx.fancyLogAdmin(calling_ply, "#A ungagged #T", cleared)
    end
end
local untgag = ulx.command( "Chat", "ulx untgag", ulx.untgag, "!untgag", false)
untgag:addParam{ type=ULib.cmds.PlayersArg }
untgag:defaultAccess( ULib.ACCESS_ADMIN )
untgag:help( "Ungag the player" )

--ULX printtgags command
function ulx.printtgags(calling_ply)
	local timedGaggedPlayers = {}
	
	for k,v in pairs(player.GetHumans()) do
		if RemainingMinutes(v) then
			table.insert(timedGaggedPlayers, v:Nick())
		end
	end
	local message = table.concat(timedGaggedPlayers, ", ")
	ulx.fancyLog({calling_ply}, "Players currently with gags: #s", message)
end
local printtgags = ulx.command( "Chat", "ulx printtgags", ulx.printtgags, "!printtgags", true )
printtgags:defaultAccess( ULib.ACCESS_ADMIN )
printtgags:help("Lists players who are connected and have gags.")

-- Also recover already-connected players with stale flags when this module
-- starts. Offline records are validated when the player authenticates.
if SERVER then
    for _, ply in ipairs(player.GetAll()) do RestoreTimedGag(ply) end
end
