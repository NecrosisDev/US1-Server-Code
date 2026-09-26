-- ============================================================
--  Watchdog module: VPN  (VPN / proxy on join)
-- ------------------------------------------------------------
--  Flags a player joining from a VPN / proxy / datacenter IP - a common
--  throwaway-alt / evasion signal. Uses proxycheck.io (free tier, 1000
--  lookups/day). A key is configured below (see apiKey()).
--  Results are cached on disk per IP so we don't re-query known addresses
--  and burn the quota.
--
--  Needs outbound HTTP (http.Fetch). WATCH MODE: dossiers only - built to
--  become an auto-kick/ban later. FP note: plenty of legit players use
--  VPNs / mobile CGNAT, so never auto-ban on this alone.
-- ============================================================
if not SERVER then return end
if not WD then include("autorun/server/sv_watchdog_core.lua") end

local C = WD.Config
if C.vpnEnabled == nil then C.vpnEnabled = true end
C.vpnCacheDays = C.vpnCacheDays or 7  -- how long to trust a cached IP verdict

-- ---- ENFORCEMENT: VPN autokick ----
-- A POLICY kick (like pingkick), not a cheat verdict: the server owner has
-- decided VPNs aren't allowed. Staff exempt as always; wd_vpn_exempt whitelists
-- a specific player; vpnKickEnforce false = dry-run (logs who WOULD be kicked).
if C.vpnKickEnforce == nil then C.vpnKickEnforce = true end
C.vpnKickMsg = C.vpnKickMsg or "VPNs are not allowed on this server. Please turn it off to play."
C.vpnExempt  = C.vpnExempt or {}   -- sid -> true: allowed to play on a VPN (persists)

-- proxycheck.io API key (free tier: 1000 lookups/day). Baked default below so
-- it works out of the box; to ROTATE it without editing this file, drop the new
-- key into  garrysmod/data/watchdog_vpnkey.txt  and it wins over the default.
-- Keep this addon PRIVATE - the key travels with the file.
if C.vpnApiKey == nil or C.vpnApiKey == "" then
	C.vpnApiKey = ""
end
local function apiKey()
	local f = file.Read("watchdog_vpnkey.txt", "DATA")
	if f then f = string.Trim(f) if f ~= "" then return f end end
	return C.vpnApiKey or ""
end

sql.Query([[CREATE TABLE IF NOT EXISTS wd_vpncache (
    ip TEXT PRIMARY KEY,
    isvpn INTEGER NOT NULL,
    vtype TEXT,
    ts INTEGER NOT NULL
)]])

local function ipOf(ply)
	local ip = ply:IPAddress() or ""
	return string.match(ip, "^(%d+%.%d+%.%d+%.%d+)") or ip
end

-- skip loopback / RFC1918 private ranges
local function isLocal(ip)
	return ip == "" or ip == "loopback"
		or string.match(ip, "^127%.") or string.match(ip, "^10%.")
		or string.match(ip, "^192%.168%.") or string.match(ip, "^172%.1[6-9]%.")
		or string.match(ip, "^172%.2[0-9]%.") or string.match(ip, "^172%.3[0-1]%.")
end

local function flag(ply, ip, vtype, provider)
	if not IsValid(ply) then return end
	if WD.IsExempt(ply) then return end
	if C.vpnExempt[ply:SteamID()] then return end   -- whitelisted: allowed, no dossier, no kick
	WD.AddSuspicion(ply, "vpn", 100, {
		note = "joined under a VPN / proxy",
		ip = ip, type = vtype or "?", provider = provider or "?",
	}, C.vpnKickEnforce and "kicked" or "logged")   -- action tag rides into the dossier
	-- policy enforcement
	if C.vpnKickEnforce then
		WD.Notify(string.format("VPN kick: %s (%s / %s)", ply:Nick(), vtype or "?", provider or "?"))
		if C.logConsole then
			print(string.format("[Watchdog] VPN kick: %s (%s) ip %s type %s provider %s",
				ply:Nick(), ply:SteamID(), ip, tostring(vtype), tostring(provider)))
		end
		ply:Kick(C.vpnKickMsg)
	else
		WD.Notify("[dry-run] WOULD VPN-kick: " .. ply:Nick() .. " (" .. (provider or "?") .. ")")
	end
end

-- superadmin: toggle a player's VPN allowance (whitelist), persists.
--   wd_vpn_exempt STEAM_0:1:234567   or   wd_vpn_exempt <partial name>
--   wd_vpn_exempt                    lists current whitelist
concommand.Add("wd_vpn_exempt", function(p, _, a)
	if IsValid(p) and not p:IsSuperAdmin() then return end
	local q = a[1]
	if not q or q == "" then
		local n = 0
		for sid in pairs(C.vpnExempt) do print("[Watchdog] vpn-exempt: " .. sid) n = n + 1 end
		print("[Watchdog] " .. n .. " VPN-exempt id(s). usage: wd_vpn_exempt <STEAM_0:x:xx | partial name> (toggles)")
		return
	end
	local sid = string.match(q, "^STEAM_%d+:%d+:%d+$")
	if not sid then
		local ql = string.lower(q)
		for _, pl in ipairs(player.GetAll()) do
			if string.find(string.lower(pl:Nick()), ql, 1, true) then sid = pl:SteamID() break end
		end
	end
	if not sid then print("[Watchdog] no SteamID or online player matched '" .. q .. "'") return end
	if C.vpnExempt[sid] then C.vpnExempt[sid] = nil else C.vpnExempt[sid] = true end
	if WD.SaveConfig then WD.SaveConfig() end
	print("[Watchdog] " .. sid .. " VPN-exempt -> " .. tostring(C.vpnExempt[sid] == true))
end, nil, "Superadmin: toggle a player's VPN allowance: wd_vpn_exempt <SteamID|name>; no argument lists them.")

local function query(ply, ip)
	local key = apiKey()
	local url = "https://proxycheck.io/v2/" .. ip .. "?vpn=1&asn=1" ..
		(key ~= "" and ("&key=" .. key) or "")
	http.Fetch(url, function(body)
		local ok, data = pcall(util.JSONToTable, body)
		if not ok or not istable(data) then return end
		local rec = data[ip]
		if not istable(rec) then return end   -- API error / quota / no record: do NOT cache a false "clean"
		local isvpn = string.lower(tostring(rec.proxy)) == "yes"
		local vtype = rec.type
		local provider = rec.provider or rec.organisation
		sql.Query(string.format("REPLACE INTO wd_vpncache (ip, isvpn, vtype, ts) VALUES (%s, %d, %s, %d)",
			sql.SQLStr(ip), isvpn and 1 or 0, vtype and sql.SQLStr(vtype) or "NULL", os.time()))
		if isvpn then flag(ply, ip, vtype, provider) end
	end, function() end)  -- swallow HTTP errors quietly
end

local function check(ply)
	if not IsValid(ply) or not ply:IsPlayer() or ply:IsBot() then return end
	if not C.vpnEnabled then return end
	local ip = ipOf(ply)
	if isLocal(ip) then return end

	-- cached verdict still fresh?
	local row = sql.QueryRow("SELECT isvpn, vtype, ts FROM wd_vpncache WHERE ip = " .. sql.SQLStr(ip))
	if row and (os.time() - tonumber(row.ts)) < (C.vpnCacheDays * 86400) then
		if tonumber(row.isvpn) == 1 then flag(ply, ip, row.vtype, "cached") end
		return
	end
	query(ply, ip)
end

hook.Add("PlayerInitialSpawn", "WD_VPN", function(ply)
	timer.Simple(5, function() if IsValid(ply) then check(ply) end end)
end)

WD.RegisterModule("vpn", {
	threshold = 100, decay = 0,
	desc = "VPN / proxy on join (proxycheck.io)",
})
