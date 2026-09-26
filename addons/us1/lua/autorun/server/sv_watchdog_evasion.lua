-- ============================================================
--  Watchdog module: EVASION  (ban-evasion alt via shared IP)
-- ------------------------------------------------------------
--  Catches a previously-banned player rejoining on a DIFFERENT account
--  (an alt, or a non-shared second account) by connection history: we
--  keep a disk-backed log of which SteamIDs have connected from which
--  IP, and when a new account joins from an IP a BANNED account has used,
--  we flag it. (Family-Share evasion is handled separately by the
--  `altshare` module via the license owner.)
--
--  Disk-backed SQLite (sv.db), 90-day retention. WATCH MODE: dossiers
--  only for now - built to become an auto-kick/ban later by flipping
--  watchMode off. FP note: shared households / dorms / CGNAT share IPs,
--  so this is a lead, not proof.
-- ============================================================
if not SERVER then return end
if not WD then include("autorun/server/sv_watchdog_core.lua") end

local C = WD.Config
if C.evasionEnabled == nil then C.evasionEnabled = true end

sql.Query([[CREATE TABLE IF NOT EXISTS wd_connections (
    sid TEXT NOT NULL,
    ip  TEXT NOT NULL,
    ts  INTEGER NOT NULL
)]])
sql.Query("CREATE INDEX IF NOT EXISTS wdconn_ip ON wd_connections (ip)")
sql.Query("CREATE INDEX IF NOT EXISTS wdconn_sid ON wd_connections (sid)")

local function ipOf(ply)
	local ip = ply:IPAddress() or ""
	return string.match(ip, "^(%d+%.%d+%.%d+%.%d+)") or ip   -- strip :port
end

-- is a ULib ban entry still ACTIVE (not expired)? unban 0 = permanent.
local function banActive(b)
	if not istable(b) then return false end
	local unban = tonumber(b.unban)
	return unban == nil or unban == 0 or unban > os.time()
end

-- banned (and still active) here? tolerate ULib keying by STEAM_0 or SteamID64.
local function isBanned(sid)
	if not (ULib and ULib.bans) then return false end
	local sid64 = util.SteamIDTo64(sid)
	return banActive(ULib.bans[sid]) or (sid64 ~= nil and banActive(ULib.bans[sid64]))
end

local function check(ply)
	if not IsValid(ply) or not ply:IsPlayer() or ply:IsBot() then return end
	if not C.evasionEnabled then return end
	local sid = ply:SteamID()
	local ip = ipOf(ply)
	if ip == "" or ip == "loopback" then return end

	-- other accounts seen on this IP (query BEFORE recording, so no self-match)
	local rows = sql.Query("SELECT DISTINCT sid FROM wd_connections WHERE ip = " ..
		sql.SQLStr(ip) .. " AND sid != " .. sql.SQLStr(sid))
	local banned = {}
	if rows then
		for _, r in ipairs(rows) do
			if isBanned(r.sid) then banned[#banned + 1] = r.sid end
		end
	end

	-- record this connection (everyone, so history is complete)
	sql.Query(string.format("INSERT INTO wd_connections (sid, ip, ts) VALUES (%s, %s, %d)",
		sql.SQLStr(sid), sql.SQLStr(ip), os.time()))

	if WD.IsExempt(ply) then return end   -- staff: recorded, never flagged
	if #banned > 0 then
		WD.AddSuspicion(ply, "evasion", 100, {
			note = "connected from an IP used by a BANNED account (possible ban-evasion alt)",
			ip = ip,
			bannedAccounts = banned,
		})
	end
end

hook.Add("PlayerInitialSpawn", "WD_Evasion", function(ply)
	timer.Simple(6, function() if IsValid(ply) then check(ply) end end)
end)

local function prune() sql.Query("DELETE FROM wd_connections WHERE ts < " .. (os.time() - 90 * 86400)) end
prune()
timer.Create("WD_Evasion_Prune", 43200, 0, prune)

WD.RegisterModule("evasion", {
	threshold = 100, decay = 0,
	desc = "ban-evasion alt (shared IP with a banned account)",
})
