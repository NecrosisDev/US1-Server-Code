-- ============================================================
--  Watchdog: STAFF INTERFACE (server half)
-- ------------------------------------------------------------
--  Superadmin-gated. The client half is a dumb renderer that holds
--  NO thresholds and NO detection logic - all of that stays here on
--  the server. Every request is validated IsSuperAdmin() before any
--  data is sent, so a non-admin (or a cheater who read the client
--  file) gets nothing.
--
--  Protocol:
--    C->S  WD_UI_Req   : uint8 kind [+ strings]
--          kind 1 = index (modules + live suspicion + dossier list
--                   [+ settings schema, superadmins only])
--          kind 2 = read dossier (string filename)
--          kind 3 = toggle module (string name, bool state)
--          kind 4 = set config (string key, string value) - SUPERADMIN,
--                   whitelisted keys only, validated + clamped server-side
--    S->C  WD_UI_Data  : compressed JSON blob (kind echoed)
-- ============================================================
if not SERVER then return end
if not WD then include("autorun/server/sv_watchdog_core.lua") end

-- pcall: on a cold live install the addon folder isn't lua-mounted yet (mounts
-- happen at boot), so this path can't resolve until the next restart - don't
-- let that error kill the rest of this file. The client panel is restart cargo
-- on a cold install either way; chat pings work without it.
pcall(AddCSLuaFile, "autorun/client/cl_watchdog_ui.lua")

util.AddNetworkString("WD_UI_Req")
util.AddNetworkString("WD_UI_Data")
util.AddNetworkString("WD_Alert")

-- ---------------- Settings tab schema ----------------
-- The ONLY config the panel can see or touch. An explicit whitelist so a
-- forged net message can never set arbitrary WD.Config keys, and so the vpn
-- api key / internal excuse-window tuning are never networked. Values are
-- validated + clamped here; the client just renders rows.
local RANKS = { "operator", "admin", "superadmin" }

-- who may open/view the panel, and who may toggle modules from it
-- (the Settings tab itself stays superadmin-only, always)
WD.Config.panelMinGroup     = WD.Config.panelMinGroup     or "admin"
WD.Config.toggleMinGroup    = WD.Config.toggleMinGroup    or "admin"
WD.Config.settingsViewGroup  = WD.Config.settingsViewGroup  or "operator"    -- who can OPEN the Settings tab (read-only unless they can also write)
WD.Config.settingsWriteGroup = WD.Config.settingsWriteGroup or "superadmin"  -- who can CHANGE settings

-- rank check by inheritance: superadmin > admin > operator (custom groups
-- inheriting from these pass via IsAdmin/CheckGroup)
local function rankAtLeast(ply, group)
	if not IsValid(ply) then return false end
	if group == "superadmin" then return ply:IsSuperAdmin() end
	if group == "admin" then return ply:IsAdmin() end
	return ply:IsAdmin() or (ply.CheckGroup and ply:CheckGroup(group or "operator")) or false
end

local SCHEMA = {
	-- PANEL ACCESS
	{ key = "panelMinGroup",  group = "PANEL ACCESS", kind = "enum", options = RANKS,
	  label = "Panel opens for",       desc = "Lowest ULX rank that can open the wd panel (view live suspicion + read dossiers). Settings tab stays superadmin-only regardless" },
	{ key = "toggleMinGroup", group = "PANEL ACCESS", kind = "enum", options = RANKS,
	  label = "Modules toggle for",    desc = "Lowest rank that can switch detection modules on/off from the panel" },
	{ key = "settingsViewGroup",  group = "PANEL ACCESS", kind = "enum", options = RANKS,
	  label = "Settings open for",    desc = "Lowest rank that can OPEN the Settings tab. View-only for anyone below the write rank" },
	{ key = "settingsWriteGroup", group = "PANEL ACCESS", kind = "enum", options = RANKS,
	  label = "Settings writable by", desc = "Lowest rank that can CHANGE settings. Below this the Settings tab is read-only" },

	-- WATCH & EXEMPTION
	{ key = "enabled",        group = "WATCH & EXEMPTION", kind = "bool", risky = true,
	  label = "Watchdog enabled",      desc = "Master switch - all detection AND prevention" },
	{ key = "watchMode",      group = "WATCH & EXEMPTION", kind = "bool", risky = true,
	  label = "Watch mode",            desc = "ON = dossiers only, humans judge. (No auto-punish code exists yet, so flipping this currently changes only the label - keep ON)" },
	{ key = "evidenceRing",   group = "WATCH & EXEMPTION", kind = "number", min = 16, max = 128,
	  label = "Evidence snapshots",    desc = "Per-player rolling tick snapshots included in each dossier" },
	{ key = "exemptElevated", group = "WATCH & EXEMPTION", kind = "bool", risky = true,
	  label = "Staff immune",          desc = "Ranks above user are never watched. OFF = staff get flagged too (testing)" },
	{ key = "exemptMinGroup", group = "WATCH & EXEMPTION", kind = "enum", options = RANKS,
	  label = "Immune from rank",      desc = "Lowest ULX rank (by inheritance) that is ignored" },
	{ key = "exemptGroups",   group = "WATCH & EXEMPTION", kind = "list", hint = "ULX group name (e.g. trialmod)",
	  label = "Always-ignored groups", desc = "Custom ULX groups Watchdog never watches, regardless of their permissions" },
	{ key = "watchGroups",    group = "WATCH & EXEMPTION", kind = "list", hint = "ULX group name (e.g. vip)",
	  label = "Always-watched groups", desc = "Groups watched even if elevated (testing / override)" },
	{ key = "dossierCool",    group = "WATCH & EXEMPTION", kind = "number", min = 5, max = 300,
	  label = "Dossier cooldown (s)",  desc = "Min seconds between dossiers for the same player+module" },
	{ key = "dossierMax",     group = "WATCH & EXEMPTION", kind = "number", min = 50, max = 2000,
	  label = "Dossiers kept",         desc = "Files kept in data/watchdog before oldest are pruned" },

	-- AIM TUNING (the aim module's live knobs; loose = catches more, tighter = fewer FPs)
	{ key = "aimSnapDeg",    group = "AIM TUNING", kind = "number", min = 10, max = 60,
	  label = "Snap size (deg)",       desc = "One-tick view jump that counts as a snap. Lower catches pre-positioned aimbots; too low flags legit flicks" },
	{ key = "aimConeDeg",    group = "AIM TUNING", kind = "number", min = 2, max = 25,
	  label = "Landing cone (deg)",    desc = "Center-cone tolerance for 'landed on target' (backstop to the body-hull test)" },
	{ key = "aimHullMargin", group = "AIM TUNING", kind = "number", min = 0, max = 40,
	  label = "Body hull slop (u)",    desc = "Inflates the target's body hull so head/limb aim still counts as on-body" },
	{ key = "aimFireFollow", group = "AIM TUNING", kind = "number", min = 0, max = 5, float = true,
	  label = "Snap>shoot window (s)", desc = "A snap onto a body scores if a shot follows within this many seconds" },
	{ key = "aimRecentFire", group = "AIM TUNING", kind = "number", min = 0, max = 10, float = true,
	  label = "Shoot>snap window (s)", desc = "...or if a shot happened within this many seconds before the snap" },
	{ key = "aimNearDist",   group = "AIM TUNING", kind = "number", min = 0, max = 500,
	  label = "Min target dist (u)",   desc = "Targets closer than this are ignored. Low = catches close-range locks but point-blank brawls WILL false-positive" },
	{ key = "aimFarDist",    group = "AIM TUNING", kind = "number", min = 500, max = 8000,
	  label = "Max target dist (u)",   desc = "Targets beyond this are ignored" },
	{ key = "aimHitScore",   group = "AIM TUNING", kind = "number", min = 5, max = 100,
	  label = "Score per snap",        desc = "Suspicion per confirmed snap. Threshold is 100: 12 = ~8-9 snaps to dossier, 25 = 4, 50 = 2" },

	-- SILENT AIM (psilent out-and-back: view swaps onto the victim for the fire tick, then restores)
	{ key = "psSnapDeg",   group = "SILENT AIM", kind = "number", min = 10, max = 60,
	  label = "Out/back snap (deg)",   desc = "Both the jump out and the jump back must exceed this" },
	{ key = "psReturnDeg", group = "SILENT AIM", kind = "number", min = 1, max = 15,
	  label = "Return tolerance (deg)", desc = "The view must land back within this of where it started. Humans don't return to origin in one tick" },
	{ key = "psFireWin",   group = "SILENT AIM", kind = "number", min = 0.02, max = 0.5, float = true,
	  label = "Fire window (s)",       desc = "A shot must have fired within this window around the out-and-back" },
	{ key = "psScore",     group = "SILENT AIM", kind = "number", min = 10, max = 100,
	  label = "Score per event",       desc = "When the aimed tick was on a body (half score when no body confirmed). Threshold 100" },
	{ key = "psHitOffDeg", group = "SILENT AIM", kind = "number", min = 5, max = 60,
	  label = "Hit: view-off (deg)",   desc = "HIT-BASED check: flag when a bullet hits a player while the shooter's view was at least this far off the impact on BOTH ticks before the shot" },
	{ key = "psHitScore",  group = "SILENT AIM", kind = "number", min = 10, max = 100,
	  label = "Hit: score per hit",    desc = "Score per never-looked-at hit. Threshold 100: 34 = ~3 hits to dossier" },

	-- ALERTS
	{ key = "pingStaff",     group = "ALERTS", kind = "bool",
	  label = "Chat line to staff",    desc = "Chat ping to online staff when a dossier is filed" },
	{ key = "alertToast",    group = "ALERTS", kind = "bool",
	  label = "Toast + sound",         desc = "On-screen corner toast + sound to staff on a dossier" },
	{ key = "warnStaff",     group = "ALERTS", kind = "bool",
	  label = "Early climb warning",   desc = "Chat line to staff when a score is climbing, BEFORE the dossier fires (all modules)" },
	{ key = "warnPct",       group = "ALERTS", kind = "number", min = 10, max = 90,
	  label = "Warn at (% of threshold)", desc = "The climb warning fires when a score reaches this percent of the module's threshold" },
	{ key = "alertMinGroup", group = "ALERTS", kind = "enum", options = RANKS,
	  label = "Alerts from rank",      desc = "Lowest ULX rank that receives detection alerts" },
	{ key = "logConsole",    group = "ALERTS", kind = "bool",
	  label = "Console logging",       desc = "Watchdog lines in the server console" },

	-- PREVENTION
	{ key = "capSpeed",      group = "PREVENTION", kind = "bool",
	  label = "Cap speedhacks",        desc = "Neutralize usercmd-flooding speedhacks (no punishment)" },
	{ key = "denyNoclip",    group = "PREVENTION", kind = "bool",
	  label = "Deny noclip",           desc = "Block the noclip command for non-staff (additive to ZCity's)" },
	{ key = "revertNoclip",  group = "PREVENTION", kind = "bool", risky = true,
	  label = "Force-revert noclip",   desc = "Force a stuck noclip back to walk. LEAVE OFF - homigrad noclips KO'd bodies" },
	{ key = "hardenCSLua",   group = "PREVENTION", kind = "bool",
	  label = "Block client Lua",      desc = "Keep sv_allowcslua 0 (stops injected client code)" },
	{ key = "netMaxPerSec",  group = "PREVENTION", kind = "number", min = 100, max = 5000,
	  label = "Net msgs/sec cap",      desc = "Per-player incoming net messages per second before flagging" },
	{ key = "netDropOverCap", group = "PREVENTION", kind = "bool", risky = true,
	  label = "Drop over-cap msgs",    desc = "HARD-DROP messages over the cap. Can eat legit traffic - leave OFF" },
	{ key = "netMaxBits",     group = "PREVENTION", kind = "number", min = 50000, max = 524288,
	  label = "Oversize packet (bits)", desc = "Single net messages bigger than this get flagged as possible bigpacket DoS" },
	{ key = "noclipTicks",    group = "PREVENTION", kind = "number", min = 3, max = 50,
	  label = "Noclip watch (ticks)",  desc = "Consecutive unauthorized-noclip ticks before a dossier files" },

	-- NET DEFENCE (backdoor blocklist + honeypots; claimed net names)
	{ key = "backdoorNets",  group = "NET DEFENCE", kind = "list", hint = "net message name",
	  label = "Backdoor blocklist",    desc = "Known-malicious net names. If received we BLOCK it + file a dossier (silent, no kick). Only list names nothing legit uses - they get claimed" },
	{ key = "honeypotNets",  group = "NET DEFENCE", kind = "list", hint = "bait net name",
	  label = "Honeypot nets",         desc = "Fake bait names an exploit MENU probes but that don't exist here. A caller is an exploit tool => dossier (+ kick if enabled below)" },
	{ key = "honeypotKick",  group = "NET DEFENCE", kind = "bool", risky = true,
	  label = "Honeypot autokick",     desc = "Kick players who trip a honeypot net. OFF = dossier only" },
	{ key = "honeypotKickMsg", group = "NET DEFENCE", kind = "text", maxLen = 160,
	  label = "Honeypot kick message", desc = "Disconnect message shown to a player kicked by a honeypot" },

	-- HTTP MONITOR (outbound request visibility)
	{ key = "httpMonitor",   group = "HTTP MONITOR", kind = "bool",
	  label = "HTTP monitor",          desc = "Log outbound http.Fetch/Post by host (read with wd_http) and enforce the blocklist below" },
	{ key = "httpBlock",     group = "HTTP MONITOR", kind = "list", hint = "url substring, e.g. evil.host",
	  label = "HTTP blocklist",        desc = "Outbound requests whose URL contains one of these are dropped + staff pinged. Default empty" },

	-- PING KICK
	{ key = "pingKickEnforce", group = "PING KICK", kind = "bool", risky = true,
	  label = "Actually kick",         desc = "ON = kicks. OFF = dry-run (logs who WOULD be kicked)" },
	{ key = "pingThreshold",   group = "PING KICK", kind = "number", min = 100, max = 1000,
	  label = "Threshold (ms)",        desc = "Ping above this counts as too high" },
	{ key = "pingClear",       group = "PING KICK", kind = "number", min = 100, max = 1000,
	  label = "Recovered below (ms)",  desc = "Ping must drop under this to count as recovered (hysteresis)" },
	{ key = "pingSustain",     group = "PING KICK", kind = "number", min = 5, max = 120,
	  label = "Sustain before kick (s)", desc = "Seconds continuously over threshold before the kick" },
	{ key = "pingWarnAt",      group = "PING KICK", kind = "number", min = 5, max = 120,
	  label = "Warn at (s)",           desc = "Seconds over threshold before the chat warning" },
	{ key = "pingGrace",       group = "PING KICK", kind = "number", min = 0, max = 300,
	  label = "Join grace (s)",        desc = "Seconds after joining before ping is measured" },
	{ key = "pingServerGuard", group = "PING KICK", kind = "bool",
	  label = "Server-lag guard",      desc = "Pause the kicker when a big share of players spike at once (server lag)" },

	-- JOIN CHECKS
	{ key = "altFlagAllShares", group = "JOIN CHECKS", kind = "bool",
	  label = "Flag all family-shares", desc = "Flag EVERY shared account, not just ones with a banned owner (noisy)" },
	{ key = "evasionEnabled",   group = "JOIN CHECKS", kind = "bool",
	  label = "Shared-IP evasion",     desc = "Flag new accounts joining from an IP a banned account used" },
	{ key = "vpnEnabled",       group = "JOIN CHECKS", kind = "bool",
	  label = "VPN / proxy check",     desc = "proxycheck.io lookup on join (cached per IP)" },
	{ key = "vpnKickEnforce",   group = "JOIN CHECKS", kind = "bool", risky = true,
	  label = "VPN autokick",          desc = "Kick VPN/proxy joins. OFF = dry-run (logs who WOULD be kicked). Whitelist someone: wd_vpn_exempt <name>" },
	{ key = "vpnKickMsg",       group = "JOIN CHECKS", kind = "text", maxLen = 180,
	  label = "VPN kick message",      desc = "The disconnect message VPN users see when autokicked" },
	{ key = "vpnExempt",        group = "JOIN CHECKS", kind = "list", hint = "STEAM_0:x:xx or an online player's name",
	  label = "VPN whitelist",         desc = "Players allowed to play on a VPN - no dossier, no kick. Names resolve to the SteamID of a matching online player" },
	{ key = "luaerrSignatures", group = "JOIN CHECKS", kind = "list", hint = "substring, e.g. kefir",
	  label = "Cheat-name signatures", desc = "Substrings in a client's Lua errors that mark a known cheat loader (instant dossier). Stored lowercase" },
	{ key = "vpnCacheDays",     group = "JOIN CHECKS", kind = "number", min = 1, max = 30,
	  label = "VPN cache (days)",      desc = "How long a cached IP verdict is trusted" },
	{ key = "luaerrHeuristic",  group = "JOIN CHECKS", kind = "bool",
	  label = "Loader-error heuristic", desc = "Lower-confidence unattributed cheat-loader error detection" },
	{ key = "csluaForeign",     group = "JOIN CHECKS", kind = "bool",
	  label = "Foreign-file Lua",      desc = "Flag client Lua from files the server never sent" },

	-- EXCUSES & LATENCY (the windows that keep homigrad chaos out of detections;
	-- widen = safer/fewer FPs, narrow = stricter detection)
	{ key = "recentSpawn",  group = "EXCUSES & LATENCY", kind = "number", min = 0, max = 10, float = true,
	  label = "Spawn grace (s)",       desc = "View/move ignored this long after spawning" },
	{ key = "viewpunchWin", group = "EXCUSES & LATENCY", kind = "number", min = 0, max = 2, float = true,
	  label = "Viewpunch window (s)",  desc = "View ignored this long after taking damage (hit reactions)" },
	{ key = "teleportWin",  group = "EXCUSES & LATENCY", kind = "number", min = 0, max = 2, float = true,
	  label = "Teleport window (s)",   desc = "View/move ignored this long after a suspected teleport" },
	{ key = "postExcuse",   group = "EXCUSES & LATENCY", kind = "number", min = 0, max = 3, float = true,
	  label = "Get-up grace (s)",      desc = "Suppression after a KO/ragdoll/stun/vehicle state clears (view snaps around during get-up)" },
	{ key = "pingCeil",     group = "EXCUSES & LATENCY", kind = "number", min = 100, max = 800,
	  label = "Ping ceiling (ms)",     desc = "Above this, per-tick data isn't trusted (no view/move detection that sample)" },
	{ key = "pingJump",     group = "EXCUSES & LATENCY", kind = "number", min = 30, max = 300,
	  label = "Ping jump (ms)",        desc = "A ping swing bigger than this marks the sample unstable" },
}

local SCHEMA_BY_KEY = {}
for _, s in ipairs(SCHEMA) do SCHEMA_BY_KEY[s.key] = s end

-- ---------------- list-kind plumbing ----------------
-- Set-style tables (name -> true) vs array-style; each with its own
-- normalizer. Only these keys are editable through the list protocol.
local LISTS = {
	vpnExempt = { set = true, label = "VPN whitelist",
		norm = function(v)
			if string.match(v, "^STEAM_%d+:%d+:%d+$") then return v end
			local ql = string.lower(v)   -- resolve an online player's name -> sid
			for _, pl in ipairs(player.GetAll()) do
				if string.find(string.lower(pl:Nick()), ql, 1, true) then return pl:SteamID() end
			end
			return nil, "no SteamID or online player matched"
		end },
	exemptGroups     = { set = true, label = "always-ignored groups" },
	watchGroups      = { set = true, label = "always-watched groups" },
	luaerrSignatures = { array = true, label = "cheat-name signatures",
		norm = function(v) return string.lower(v) end },
	backdoorNets     = { array = true, label = "backdoor net blocklist", onchange = function() if WD.ClaimNets then WD.ClaimNets() end end },
	honeypotNets     = { array = true, label = "honeypot net names", onchange = function() if WD.ClaimNets then WD.ClaimNets() end end },
	httpBlock        = { array = true, label = "HTTP blocklist" },
}

-- normalized array view of a list table, for the panel
local function listValues(key)
	local t = WD.Config[key]
	if not istable(t) then return {} end
	local out = {}
	if LISTS[key] and LISTS[key].array then
		for _, v in ipairs(t) do out[#out + 1] = tostring(v) end
	else
		for k in pairs(t) do out[#out + 1] = tostring(k) end
		table.sort(out)
	end
	return out
end

-- current values + schema, for players at/above settingsViewGroup (nil otherwise).
-- Whether they can actually WRITE is a separate flag (configCanWrite in the index).
local function configFor(ply)
	if not rankAtLeast(ply, WD.Config.settingsViewGroup or "superadmin") then return nil end
	local out = {}
	for _, s in ipairs(SCHEMA) do
		-- skip keys whose owning module isn't loaded yet (value would be nil)
		if WD.Config[s.key] ~= nil then
			out[#out + 1] = {
				key = s.key, label = s.label, desc = s.desc, kind = s.kind,
				group = s.group, min = s.min, max = s.max, options = s.options,
				maxLen = s.maxLen, hint = s.hint, risky = s.risky or false,
				value = (s.kind == "list") and listValues(s.key) or WD.Config[s.key],
			}
		end
	end
	return out
end

local function sendBlob(ply, kind, tbl)
	local data = util.Compress(util.TableToJSON(tbl))
	net.Start("WD_UI_Data")
	net.WriteUInt(kind, 8)
	net.WriteUInt(#data, 32)
	net.WriteData(data, #data)
	net.Send(ply)
end

-- live suspicion rows only (shared by the full index and the panel's live poll)
local function buildLive()
	local live = {}
	for _, p in ipairs(player.GetAll()) do
		local sid = p:SteamID()
		local mods = WD.Suspicion[sid]
		local scores = {}
		local any = false
		if mods then
			for mod, sc in pairs(mods) do
				if sc > 0 then scores[mod] = math.Round(sc, 1) any = true end
			end
		end
		live[#live + 1] = { nick = p:Nick(), sid = sid, ping = p:Ping(), scores = scores, hot = any }
	end
	table.sort(live, function(a, b) return (a.hot and 1 or 0) > (b.hot and 1 or 0) end)
	return live
end

local function buildIndex(ply)
	local modules = {}
	for name, m in pairs(WD.Modules) do
		modules[#modules + 1] = { name = name, enabled = WD.ModuleEnabled(name), desc = m.desc or "" }
	end
	table.sort(modules, function(a, b) return a.name < b.name end)

	local live = buildLive()

	-- file.Find returns ALPHABETICAL order (module name first), so sort by the
	-- trailing os.time in the filename for true newest-first across modules.
	local files = file.Find(WD.Config.dossierDir .. "/*.txt", "DATA") or {}
	table.sort(files, function(a, b)
		return (tonumber(string.match(a, "_(%d+)%.txt$")) or 0) > (tonumber(string.match(b, "_(%d+)%.txt$")) or 0)
	end)
	local dossiers = {}
	for i = 1, math.min(#files, 60) do dossiers[i] = files[i] end

	return { mode = WD.Config.watchMode and "WATCH" or "ENFORCE",
	         enabled = WD.Config.enabled, version = WD.VERSION,
	         modules = modules, live = live, dossiers = dossiers,
	         config = configFor(ply),   -- Settings tab data; nil below settingsViewGroup
	         configCanWrite = rankAtLeast(ply, WD.Config.settingsWriteGroup or "superadmin") }
end

net.Receive("WD_UI_Req", function(_, ply)
	if not IsValid(ply) then return end
	local kind = net.ReadUInt(8)

	-- panel access by configurable rank; the SERVER is the authority. On an
	-- open attempt below the floor, reply kind 7 so the client can say so and
	-- close, instead of hanging on "loading". Other kinds fail silently.
	if not rankAtLeast(ply, WD.Config.panelMinGroup or "admin") then
		if kind == 1 then sendBlob(ply, 7, { reason = "panel is " .. (WD.Config.panelMinGroup or "admin") .. "+ only." }) end
		return
	end

	if kind == 1 then
		sendBlob(ply, 1, buildIndex(ply))

	elseif kind == 5 then
		-- live-only refresh for the open panel's auto-poll (cheap; no dossier
		-- disk scan, no config). Panel-open rank already checked above.
		sendBlob(ply, 5, { live = buildLive() })

	elseif kind == 6 then
		-- list add/remove (whitelists, signatures): same write rank as settings
		if not rankAtLeast(ply, WD.Config.settingsWriteGroup or "superadmin") then return end
		local listKey = net.ReadString()
		local isAdd = net.ReadBool()
		local val = net.ReadString()
		local def = LISTS[listKey]
		if not def then return end
		val = string.Trim(string.gsub(tostring(val or ""), "%c", ""))
		if val == "" or #val > 64 then return end
		if isAdd and def.norm then
			local n, why = def.norm(val)
			if not n then
				ply:ChatPrint("[Watchdog] " .. (why or "invalid entry") .. ": " .. val)
				return
			end
			val = n
		end

		local t = WD.Config[listKey]
		if not istable(t) then return end
		if def.array then
			local vl = string.lower(val)
			local found
			for i, x in ipairs(t) do
				if string.lower(tostring(x)) == vl then found = i break end
			end
			if isAdd then
				if found then return end   -- already present
				table.insert(t, val)
			else
				if not found then return end
				table.remove(t, found)
			end
		else
			if isAdd then
				if t[val] then return end
				t[val] = true
			else
				if not t[val] then return end
				t[val] = nil
			end
		end

		if WD.SaveConfig then WD.SaveConfig() end
		if def.onchange then pcall(def.onchange) end   -- e.g. re-claim backdoor/honeypot nets
		WD.Notify(string.format("%s %s '%s' %s the %s", ply:Nick(),
			isAdd and "added" or "removed", val, isAdd and "to" or "from", def.label))
		if WD.Config.logConsole then
			print(string.format("[Watchdog] list (panel) %s %s '%s' by %s",
				listKey, isAdd and "+" or "-", val, ply:Nick()))
		end
		sendBlob(ply, 1, buildIndex(ply))

	elseif kind == 2 then
		local fname = net.ReadString()
		-- sanitize: only basenames inside the dossier dir
		fname = string.GetFileFromFilename(fname or "")
		if fname == "" then return end
		local path = WD.Config.dossierDir .. "/" .. fname
		local body = file.Read(path, "DATA")
		sendBlob(ply, 2, { name = fname, body = body or "(missing)" })

	elseif kind == 3 then
		-- module toggling by its own configurable rank floor
		if not rankAtLeast(ply, WD.Config.toggleMinGroup or "admin") then return end
		local name = net.ReadString()
		local state = net.ReadBool()
		if WD.Modules[name] then
			WD.Config.modules[name] = state and true or false
			WD.Notify(ply:Nick() .. " set module " .. name .. " -> " .. tostring(state))
			if WD.SaveConfig then WD.SaveConfig() end
			sendBlob(ply, 1, buildIndex(ply))
		end

	elseif kind == 4 then
		-- Settings tab writes: gated by settingsWriteGroup, whitelisted keys only,
		-- values validated + clamped here (the client is never trusted).
		if not rankAtLeast(ply, WD.Config.settingsWriteGroup or "superadmin") then return end
		local key = net.ReadString()
		local val = net.ReadString()
		local s = SCHEMA_BY_KEY[key]
		if not s then return end

		local new
		if s.kind == "bool" then
			new = (val == "true" or val == "1")
		elseif s.kind == "number" then
			new = tonumber(val)
			if not new then return end
			new = math.Clamp(new, s.min or -math.huge, s.max or math.huge)
			-- float keys keep two decimals (e.g. 0.12s windows); the rest are whole numbers
			new = s.float and math.Round(new, 2) or math.Round(new)
		elseif s.kind == "enum" then
			for _, o in ipairs(s.options or {}) do
				if o == val then new = val break end
			end
			if new == nil then return end
		elseif s.kind == "text" then
			-- plain text: strip control chars, clamp length, refuse empty
			new = string.gsub(tostring(val), "%c", " ")
			new = string.Trim(string.sub(new, 1, s.maxLen or 200))
			if new == "" then return end
		end
		if new == nil then return end

		WD.Config[key] = new
		if WD.SaveConfig then WD.SaveConfig() end
		WD.Notify(ply:Nick() .. " set " .. key .. " -> " .. tostring(new))
		if WD.Config.logConsole then
			print("[Watchdog] config (panel) " .. key .. " -> " .. tostring(new) .. "  by " .. ply:Nick())
		end
		sendBlob(ply, 1, buildIndex(ply))
	end
end)

-- On a fresh dossier, alert every online staffer (operator and above): an
-- on-screen corner toast + sound, and a refresh of any open panel. Reaches
-- staff whether or not they have the panel open.
hook.Add("WD_Dossier", "WD_UI_Alert", function(subject, module)
	if not IsValid(subject) or not WD.Config.alertToast then return end
	local nick = subject:Nick()
	for _, a in ipairs(player.GetAll()) do
		if WD.IsStaff(a) then
			net.Start("WD_Alert")
			net.WriteString(nick)
			net.WriteString(module)
			net.Send(a)
		end
	end
end)

print("[Watchdog] staff interface (server) loaded")
