-- ============================================================
--  ZC PERF - client: staff alert toasts (v1.1)
-- ------------------------------------------------------------
--  Mirrors the Watchdog alert style deliberately so the two read
--  as one suite: bottom-right notification.AddLegacy toast + a
--  sound + a coloured chat line. Only admins/superadmins are ever
--  sent these (the server picks recipients).
--  Fires on: auto-capture armed, manual arm, recording stopped,
--  report saved.
--  Client file = restart cargo.
-- ============================================================
if not CLIENT then return end

local col = {
	amber = Color(255, 190, 70),
	text  = Color(235, 238, 242),
	dim   = Color(150, 156, 165),
	good  = Color(120, 210, 120),
}

-- 1 = auto-armed, 2 = manual arm, 3 = stopped, 4 = report saved
net.Receive("ZCPERF_Alert", function()
	local kind = net.ReadUInt(3)
	local text = net.ReadString()

	local ntype = NOTIFY_GENERIC
	local snd = "buttons/button17.wav"
	local lead = col.amber

	if kind == 1 then
		ntype, snd = NOTIFY_ERROR, "buttons/button17.wav"
	elseif kind == 2 then
		ntype, snd = NOTIFY_HINT, "buttons/button15.wav"
	elseif kind == 3 then
		ntype, snd = NOTIFY_GENERIC, "buttons/button19.wav"
	elseif kind == 4 then
		ntype, snd, lead = NOTIFY_HINT, "buttons/button9.wav", col.good
	end

	notification.AddLegacy("PERF: " .. text, ntype, 8)
	surface.PlaySound(snd)
	chat.AddText(lead, "[zc_perf] ", col.text, text)
end)

-- announce ourselves so the server sends real toasts instead of the
-- no-client-file ZCity-notification fallback (retried briefly in case
-- the net channel isn't ready on the very first frame)
local hello = 0
timer.Create("zc_perf_hello", 2, 5, function()
	hello = hello + 1
	net.Start("ZCPERF_Hello")
	net.SendToServer()
	if hello >= 2 then timer.Remove("zc_perf_hello") end
end)

print("[zc_perf] client alerts loaded")
