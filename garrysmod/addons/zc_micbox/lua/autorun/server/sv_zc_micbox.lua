-- ============================================================
--  ZC MIC BOX v3 - SERVER half
-- ------------------------------------------------------------
--  The server tracks who is transmitting voice ANYWHERE on the
--  map and sends the speaking list ONLY to operator+ staff.
--
--  Why this exists (v2 limits it fixes):
--   * v2 was purely clientside, driven by PlayerStartVoice on the
--     staff member's client - with proximity voice you only saw
--     speakers you could personally hear. Staff now see EVERYONE
--     talking, map-wide, regardless of range.
--   * v2's operator gate was clientside only. Now the gate is
--     server-authoritative: non-staff clients never receive the
--     data at all, so there is nothing for a user to display.
--
--  Detection is belt-and-braces (either alone suffices):
--   * ply:IsSpeaking() polled serverside
--   * a purely-observational PlayerCanHearPlayersVoice stamp
--     (never returns, so ZCity's voice routing is untouched)
--
--  This file is serverside = hotloadable live.
-- ============================================================
if not SERVER then return end

util.AddNetworkString("zc_micbox_state")

local speakStart = {}   -- ply -> CurTime() they started transmitting
local lastPacket = {}   -- ply -> last time the voice system saw them transmit

-- observational stamp: the engine calls this per listener pair while a
-- player transmits. We only record the talker; returning nothing leaves
-- ZCity's routing rules exactly as they are.
hook.Add("PlayerCanHearPlayersVoice", "zc_micbox_stamp", function(listener, talker)
	if IsValid(talker) then lastPacket[talker] = CurTime() end
end)

local function isTransmitting(ply)
	if ply.IsSpeaking and ply:IsSpeaking() then return true end
	local t = lastPacket[ply]
	return t ~= nil and (CurTime() - t) < 0.3
end

-- operator+ (ULib inheritance, falls back to admin) - SERVERSIDE authority
local function allowedSV(ply)
	if not IsValid(ply) then return false end
	if ply:IsAdmin() then return true end
	if ply.CheckGroup and ply:CheckGroup("operator") then return true end
	return false
end

local lastKey, lastSend = "", 0

timer.Create("zc_micbox_poll", 0.15, 0, function()
	local now = CurTime()

	local list = {}
	for _, ply in player.Iterator() do
		if isTransmitting(ply) then
			speakStart[ply] = speakStart[ply] or now
			list[#list + 1] = ply
		else
			speakStart[ply] = nil
		end
	end

	-- prune stale/invalid entries
	for ply in pairs(speakStart) do
		if not IsValid(ply) then speakStart[ply] = nil end
	end
	for ply in pairs(lastPacket) do
		if not IsValid(ply) or (now - lastPacket[ply]) > 5 then lastPacket[ply] = nil end
	end

	table.sort(list, function(a, b) return (speakStart[a] or 0) < (speakStart[b] or 0) end)

	-- only send when the SET of speakers changes (plus a 2s keepalive while
	-- someone is talking) - not every poll
	local key = ""
	for _, p in ipairs(list) do key = key .. p:UserID() .. "," end

	if key ~= lastKey or (key ~= "" and (now - lastSend) > 2) then
		lastKey = key
		lastSend = now

		local rcpt = {}
		for _, p in player.Iterator() do
			if allowedSV(p) then rcpt[#rcpt + 1] = p end
		end
		if #rcpt == 0 then return end

		net.Start("zc_micbox_state")
		net.WriteUInt(math.min(#list, 100), 7)
		for i = 1, math.min(#list, 100) do
			local p = list[i]
			net.WriteUInt(p:UserID(), 32)
			net.WriteFloat(speakStart[p] or now)
		end
		net.Send(rcpt)
	end
end)

hook.Add("ShutDown", "zc_micbox_sv_shutdown", function()
	timer.Remove("zc_micbox_poll")
end)

print("[ZC Mic Box] server tracker loaded - speaking list goes to operator+ only")
