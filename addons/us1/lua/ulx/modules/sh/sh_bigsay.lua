-- ulx bigsay: full-screen banner announcement, impossible to miss.
-- Registers as a real ULX command: XGUI permissions, targeting-free,
-- captured by the command logger automatically.
local CATEGORY_NAME = "Chat"

if SERVER then
	util.AddNetworkString("ULXBigSay_Show")
end

function ulx.bigsay(calling_ply, seconds, message)
	if not SERVER then return end

	net.Start("ULXBigSay_Show")
		net.WriteFloat(math.Clamp(seconds or 8, 2, 20))
		net.WriteString(string.sub(message or "", 1, 200))
	net.Broadcast()

	ulx.fancyLogAdmin(calling_ply, "#A made an announcement: #s", message)
end

local bigsay = ulx.command(CATEGORY_NAME, "ulx bigsay", ulx.bigsay, "!bigsay")
bigsay:addParam{ type = ULib.cmds.NumArg, min = 2, max = 20, default = 8, hint = "seconds", ULib.cmds.optional, ULib.cmds.round }
bigsay:addParam{ type = ULib.cmds.StringArg, hint = "message", ULib.cmds.takeRestOfLine }
bigsay:defaultAccess( ULib.ACCESS_ADMIN )
bigsay:help( "Show a large screen-wide announcement to all players." )
