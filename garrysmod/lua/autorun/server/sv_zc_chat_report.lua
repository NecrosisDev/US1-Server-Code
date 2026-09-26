-- Chat reports: a player flags a message, staff hear about it and it is written
-- down whether or not anyone is online to hear.
--
-- The client supplies the accused and the message body, so none of it is
-- trusted: every field is length-capped and stripped of control characters, the
-- reporter is taken from the server's own connection rather than the packet,
-- and a report is only ever a notification. Nothing here punishes anybody.
if not SERVER then return end

util.AddNetworkString("zcChatReport")

local REASONS = {
	"Inappropriate media",
	"Harassment or slurs",
	"Spam or flooding",
	"Something else",
}

local COOLDOWN = 20 -- seconds between reports from one player
local DIR = "zc_chat_media"
local LOG = DIR .. "/reports.txt"
local ROTATE_AT = 2 * 1024 * 1024
local KEEP_LINES = 200

file.CreateDir(DIR)

local function clean(text, limit)
	text = tostring(text or ""):gsub("[%z\1-\31\127]", " ")
	return string.sub(text, 1, limit)
end

local function rotate()
	if (file.Size(LOG, "DATA") or 0) < ROTATE_AT then return end
	file.Write(DIR .. "/reports_previous.txt", file.Read(LOG, "DATA") or "")
	file.Write(LOG, "")
end

function ZCChatReport_Record(entry)
	rotate()
	file.Append(LOG, util.TableToJSON(entry) .. "\n")
end

function ZCChatReport_Announce(line)
	-- The server console keeps a copy even when nobody is on and even when
	-- watchdog's staff pings are switched off.
	print("[ChatReport] " .. line)
	if WD and isfunction(WD.Notify) then
		WD.Notify(line)
		return
	end
	for _, staff in player.Iterator() do
		if IsValid(staff) and staff:IsAdmin() then staff:ChatPrint("[Chat] " .. line) end
	end
end

net.Receive("zcChatReport", function(_, ply)
	if not IsValid(ply) then return end

	local now = CurTime()
	if now < (ply.zcNextReport or 0) then return end
	ply.zcNextReport = now + COOLDOWN

	local accused = clean(net.ReadString(), 20)
	local accusedName = clean(net.ReadString(), 64)
	local reason = net.ReadUInt(4)
	local text = clean(net.ReadString(), 200)
	local media = clean(net.ReadString(), 300)

	if not accused:match("^%d+$") then return end
	reason = REASONS[reason] and reason or #REASONS

	ZCChatReport_Record({
		time = os.date("%Y-%m-%d %H:%M:%S"),
		reporter = ply:SteamID64() or ply:SteamID(),
		reporterName = ply:Nick(),
		accused = accused,
		accusedName = accusedName,
		reason = REASONS[reason],
		text = text,
		media = media,
	})

	ZCChatReport_Announce(string.format("%s reported %s for %s%s",
		ply:Nick(), accusedName ~= "" and accusedName or accused,
		REASONS[reason], media ~= "" and " (has media)" or ""))
end)

-- Staff can read the log in game instead of over SSH.
concommand.Add("zc_chat_reports", function(ply, _, args)
	if IsValid(ply) and not ply:IsAdmin() then return end

	local wanted = math.Clamp(tonumber(args and args[1]) or 10, 1, KEEP_LINES)
	local body = file.Read(LOG, "DATA")
	local function say(line)
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
	end

	if not body or body == "" then say("[ChatReport] no reports recorded") return end

	local lines = {}
	for line in body:gmatch("[^\n]+") do lines[#lines + 1] = line end

	say(string.format("[ChatReport] %d report(s) recorded, showing the last %d:",
		#lines, math.min(wanted, #lines)))
	for index = math.max(1, #lines - wanted + 1), #lines do
		local entry = util.JSONToTable(lines[index])
		if entry then
			say(string.format("  %s  %s -> %s  [%s]  %s%s",
				entry.time or "?", entry.reporterName or "?", entry.accusedName or entry.accused or "?",
				entry.reason or "?", entry.text or "",
				(entry.media or "") ~= "" and ("  " .. entry.media) or ""))
		end
	end
end)

-- Admin media purge. Presentation only: every client takes this player's chat
-- embeds down and keeps their links as plain text for a while. The messages
-- stay, and punishing anybody is still ULX's business.
util.AddNetworkString("zcChatMediaPurge")

local PURGE_DEFAULT = 600
local PURGE_MAX = 3600

-- Trim the ends only. Squashing the middle would make every nickname with a
-- space unmatchable, which is most of them.
local function trim(text)
	return (string.match(text, "^%s*(.-)%s*$"))
end

local function resolve(needle)
	if needle == "" then return nil end
	if needle:match("^%d+$") then return needle end
	local lowered = string.lower(needle)
	for _, target in player.Iterator() do
		if IsValid(target) then
			if string.lower(target:SteamID() or "") == lowered then return target:SteamID64() end
			if string.find(string.lower(target:Nick() or ""), lowered, 1, true) then return target:SteamID64() end
		end
	end
end

concommand.Add("zc_chat_media_purge", function(ply, _, args)
	if IsValid(ply) and not ply:IsAdmin() then return end

	local function say(line)
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
	end

	local steam = resolve(trim(clean(args and args[1], 64)))
	if not steam then
		say("[ChatReport] usage: zc_chat_media_purge <steamid64|steamid|name> [seconds]")
		return
	end

	local seconds = math.Clamp(math.floor(tonumber(args and args[2]) or PURGE_DEFAULT), 0, PURGE_MAX)
	net.Start("zcChatMediaPurge")
		net.WriteString(steam)
		net.WriteUInt(seconds, 16)
	net.Broadcast()

	local byName = IsValid(ply) and ply:Nick() or "console"
	ZCChatReport_Record({
		time = os.date("%Y-%m-%d %H:%M:%S"),
		reporter = IsValid(ply) and (ply:SteamID64() or ply:SteamID()) or "console",
		reporterName = byName,
		accused = steam,
		accusedName = steam,
		reason = "media purge",
		text = string.format("suppressed for %d seconds", seconds),
		media = "",
	})
	ZCChatReport_Announce(string.format("%s purged chat media from %s for %ds", byName, steam, seconds))
	say(string.format("[ChatReport] purged media from %s for %d seconds", steam, seconds))
end)

-- ZC_BALLISTICS_AUTOSWAP_BEGIN (temporary: the autoswap watcher restores this file at the next map change)
file.CreateDir("zc_ballistics_v2")
file.Write("zc_ballistics_v2/armed.txt", tostring(os.time()))
hook.Add("ShutDown", "zc_ballistics_v2_autoswap", function()
	file.Write("zc_ballistics_v2/swap_now.txt", tostring(os.time()))
end)
-- ZC_BALLISTICS_AUTOSWAP_END
