-- ============================================================
--  Watchdog: HTTP MONITOR  (outbound request visibility)
-- ------------------------------------------------------------
--  Wraps http.Fetch / http.Post to give the server owner visibility of what
--  is phoning OUT: a backdoor exfiltrating data, or an addon calling home to a
--  host you didn't expect. Two things:
--    * LOG - a per-host tally (count, last-seen, methods) you can read with
--      `wd_http`. Purely observational; never blocks or accuses.
--    * BLOCKLIST - optional URL-substring blocklist. A matching request is
--      dropped (its onFailure fires) and staff are pinged. Default empty.
--
--  The wrapper only OBSERVES then calls the original untouched (args passed
--  straight through), so it can't corrupt outbound HTTP. It is installed once
--  (guarded) and delegates to a WD-scoped observer, so the logic hotloads.
--  NOTE: covers http.Fetch / http.Post (what addons use); the low-level HTTP()
--  struct API is not wrapped. HTTP calls are not attributable to a player, so
--  this files no player dossiers - it is a server-integrity log + alert.
-- ============================================================
if not SERVER then return end
if not WD then include("autorun/server/sv_watchdog_core.lua") end

local C = WD.Config
if C.httpMonitor == nil then C.httpMonitor = true end
C.httpBlock  = C.httpBlock or {}     -- list of URL substrings to block (default none)
C.httpLogMax = C.httpLogMax or 200   -- distinct hosts kept in the log

WD._httpLog = WD._httpLog or {}      -- host -> { count, last, fetch, post }

local function hostOf(url)
	url = tostring(url or "")
	return string.match(url, "^%w+://([^/]+)") or string.match(url, "^([^/]+)") or "?"
end

-- returns true to BLOCK the request. Logs every call; pings staff on a block.
function WD._HttpObserve(url, method)
	if not C.httpMonitor then return false end
	url = tostring(url or "")

	-- blocklist (substring, case-insensitive)
	local lurl = string.lower(url)
	for _, frag in ipairs(C.httpBlock) do
		if isstring(frag) and frag ~= "" and string.find(lurl, string.lower(frag), 1, true) then
			WD.Notify("BLOCKED outbound HTTP (" .. method .. "): " .. string.sub(url, 1, 120))
			if C.logConsole then print("[Watchdog] BLOCKED HTTP " .. method .. " -> " .. url) end
			return true
		end
	end

	-- log by host
	local host = hostOf(url)
	local row = WD._httpLog[host]
	if not row then
		-- cap distinct hosts: drop the oldest when full
		if table.Count(WD._httpLog) >= C.httpLogMax then
			local oldestHost, oldestT
			for h, r in pairs(WD._httpLog) do
				if not oldestT or (r.last or 0) < oldestT then oldestT = r.last or 0 oldestHost = h end
			end
			if oldestHost then WD._httpLog[oldestHost] = nil end
		end
		row = { count = 0, fetch = 0, post = 0 }
		WD._httpLog[host] = row
	end
	row.count = row.count + 1
	row[method] = (row[method] or 0) + 1
	row.last = os.time()
	return false
end

-- install the wrap once; the closures call the WD-scoped observer (hotloadable)
if not WD._httpWrapped then
	WD._httpWrapped = true

	local oldFetch = http.Fetch
	function http.Fetch(url, onOK, onFail, headers)
		if WD._HttpObserve and WD._HttpObserve(url, "fetch") then
			if onFail then onFail("blocked by watchdog") end
			return
		end
		return oldFetch(url, onOK, onFail, headers)
	end

	local oldPost = http.Post
	function http.Post(url, params, onOK, onFail, headers)
		if WD._HttpObserve and WD._HttpObserve(url, "post") then
			if onFail then onFail("blocked by watchdog") end
			return
		end
		return oldPost(url, params, onOK, onFail, headers)
	end
end

concommand.Add("wd_http", function(ply)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	local rows = {}
	for host, r in pairs(WD._httpLog) do rows[#rows + 1] = { host = host, r = r } end
	table.sort(rows, function(a, b) return a.r.count > b.r.count end)
	print("[Watchdog] outbound HTTP hosts (" .. #rows .. "):")
	for i = 1, math.min(#rows, 40) do
		local e = rows[i]
		print(string.format("  %-40s x%-6d (fetch %d / post %d)  last %s",
			string.sub(e.host, 1, 40), e.r.count, e.r.fetch or 0, e.r.post or 0,
			e.r.last and os.date("%m-%d %H:%M", e.r.last) or "?"))
	end
	if #rows == 0 then print("  (nothing logged yet)") end
end, nil, "Superadmin: list outbound HTTP hosts seen by Watchdog.")

print("[Watchdog] HTTP monitor loaded")
