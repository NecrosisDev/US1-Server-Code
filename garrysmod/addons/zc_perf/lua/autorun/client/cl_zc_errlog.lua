-- ============================================================
--  ZC ERRLOG - client half: relay clientside Lua errors to the
--  server's error log.
-- ------------------------------------------------------------
--  Why this exists: the server build's OnLuaError doesn't receive
--  client-relayed errors (Joey confirmed live), but the hook DOES
--  fire clientside on each player's own machine - clients update
--  ahead of servers. So we catch locally, DEDUPE LOCALLY (a render
--  error fires every frame - thousands/min - but costs one counter
--  bump here), and ship compact batches upstream.
--
--  Wire discipline (server enforces the same caps on receive):
--   * one message at most every 20s, and only when there's news
--   * max 8 signatures per message
--   * signature <= 400 chars, stack <= 600 (sent once per sig)
--   * max 30 unique signatures tracked per map (client-side cap)
--  Worst case a few KB per player per 20s - negligible.
--  This file rides a RESTART (client lua).
-- ============================================================
if not CLIENT then return end

local pending = {}   -- sig -> { delta = n, stack = s|nil (nil once sent) }
local tracked = 0
local MAX_TRACKED = 30
local SEND_EVERY = 20

local function formatStack(stack)
	if not istable(stack) then return "" end
	local out = {}
	for i, fr in ipairs(stack) do
		if istable(fr) and i <= 8 then
			out[#out + 1] = ("    %d. %s - %s:%s"):format(i,
				tostring(fr.Function or "?"), tostring(fr.File or "?"), tostring(fr.Line or "?"))
		end
	end
	return table.concat(out, "\n")
end

hook.Add("OnLuaError", "zc_errlog_cl", function(err, realm, stack, name, id)
	local sig = string.sub(tostring(err), 1, 400)
	local rec = pending[sig]
	if rec then
		rec.delta = rec.delta + 1
		return
	end
	if tracked >= MAX_TRACKED then return end
	tracked = tracked + 1
	local s = formatStack(stack)
	if name and name ~= "" then s = "    addon: " .. tostring(name) .. "\n" .. s end
	pending[sig] = { delta = 1, stack = string.sub(s, 1, 600), sent = false }
end)

timer.Create("zc_errlog_cl_send", SEND_EVERY, 0, function()
	local batch = {}
	for sig, rec in pairs(pending) do
		if rec.delta > 0 then
			batch[#batch + 1] = { sig = sig, rec = rec }
			if #batch >= 8 then break end
		end
	end
	if #batch == 0 then return end

	-- pcall: net.Start THROWS if the server half hasn't pooled the
	-- message yet (server file hotloaded later, map transition). A
	-- failed send must not lose data or feed the log its own error -
	-- deltas are only reset on SUCCESS, so everything retries in 20s.
	local ok = pcall(function()
		net.Start("zc_errlog_c")
			net.WriteUInt(#batch, 4)
			for _, b in ipairs(batch) do
				net.WriteString(b.sig)
				net.WriteUInt(math.min(b.rec.delta, 65535), 16)
				net.WriteString(b.rec.sent and "" or (b.rec.stack or ""))
			end
		net.SendToServer()
	end)
	if ok then
		for _, b in ipairs(batch) do
			b.rec.delta = 0
			b.rec.sent = true
			b.rec.stack = nil
		end
	end
end)

hook.Add("PostCleanupMap", "zc_errlog_cl", function()
	pending = {}
	tracked = 0
end)
