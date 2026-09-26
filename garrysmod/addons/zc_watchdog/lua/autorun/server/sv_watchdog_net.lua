-- ============================================================
--  Watchdog: NET / EXPLOIT HARDENING  (prevention)
-- ------------------------------------------------------------
--  Standalone servers need the exploit-proofing LSAC was quietly
--  doing. This module:
--    * sv_allowcslua 0  - stop clients running arbitrary clientside
--      Lua (the usual foothold for net-spoof / concommand cheats).
--      (Does NOT affect the server's own AddCSLuaFile addons.)
--    * startup audit - warn if sv_cheats / sv_allowcslua are unsafe.
--    * net FLOOD guard - counts incoming net messages per player.
--      The wrapper only COUNTS then calls the original dispatcher
--      untouched (it never reads the message buffer), so it cannot
--      corrupt networking. Sustained floods file a dossier; dropping
--      over-cap messages is opt-in (netDropOverCap, default off).
-- ============================================================
if not SERVER then return end
if not WD then include("autorun/server/sv_watchdog_core.lua") end

local C = WD.Config
if C.hardenCSLua     == nil then C.hardenCSLua     = true  end
-- IMPORTANT: measure real per-player incoming (homigrad syncs aim/bones/inv a
-- lot) on a FULL server before trusting this. Default is deliberately high so
-- steady-state traffic never files a false netflood dossier. Only after you've
-- measured a real peak should you lower it - and keep netDropOverCap OFF unless
-- you are certain, since dropping is applied to LEGIT traffic too.
if C.netMaxPerSec    == nil then C.netMaxPerSec    = 500   end   -- per-player incoming/sec cap
if C.netDropOverCap  == nil then C.netDropOverCap  = false end   -- opt-in hard drop (DANGEROUS)
if C.netMaxBits      == nil then C.netMaxBits      = 520000 end  -- ~63.5KB; flag only near-cap "bigpacket" messages

-- ---------------- sv_allowcslua + audit ----------------
timer.Simple(2, function()
	if C.hardenCSLua then
		RunConsoleCommand("sv_allowcslua", "0")
		if C.logConsole then print("[Watchdog] sv_allowcslua -> 0 (client Lua disabled)") end
	end
	local cheats = GetConVar("sv_cheats")
	if cheats and cheats:GetBool() then
		WD.Notify("WARNING: sv_cheats is 1 - cheats/noclip are wide open")
		print("[Watchdog] WARNING: sv_cheats is 1")
	end
end)

-- ---------------- net flood guard ----------------
-- WD-scoped so it SURVIVES a hotload: the net.Incoming wrap is installed once
-- (guarded), so its closure keeps referencing this same table across reloads,
-- and the re-created window timer / cleanup clear the same one it fills.
WD._netCount = WD._netCount or {}   -- sid -> messages this window

if not WD._netWrapped then
	WD._netWrapped = true
	local original = net.Incoming
	net.Incoming = function(len, client)
		if C.enabled and IsValid(client) and client:IsPlayer() and not WD.IsExempt(client) then
			local sid = client:SteamID()

			-- oversized single message (bigpacket DoS attempt)
			if len and len > C.netMaxBits then
				pcall(WD.AddSuspicion, client, "netflood", 100, {
					note = "oversized net message (possible bigpacket)",
					bits = len,
				})
			end

			local n = (WD._netCount[sid] or 0) + 1
			WD._netCount[sid] = n
			if n > C.netMaxPerSec then
				if n == C.netMaxPerSec + 1 then     -- log once per window
					-- pcall: this runs inside net.Incoming; never let a logging
					-- error break message dispatch for the whole server.
					pcall(WD.AddSuspicion, client, "netflood", 100, {
						note = "incoming net flood",
						perWindow = n,
						cap = C.netMaxPerSec,
					})
				end
				if C.netDropOverCap then
					return   -- drop this message (opt-in; may drop legit traffic)
				end
			end
		end
		return original(len, client)   -- dispatch untouched
	end
end

timer.Create("WD_Net_Window", 1, 0, function()
	for k in pairs(WD._netCount) do WD._netCount[k] = 0 end
end)

hook.Add("PlayerDisconnected", "WD_Net_Cleanup", function(ply)
	if IsValid(ply) then WD._netCount[ply:SteamID()] = nil end
end)

WD.RegisterModule("netflood", {
	threshold = 100, decay = 0,
	desc = "PREVENT: net-message flood guard",
})

-- ============================================================
--  BACKDOOR BLOCKLIST + HONEYPOTS  (claimed net names)
-- ------------------------------------------------------------
--  These do NOT touch the flood wrapper / net.Incoming dispatch above - they
--  only register net RECEIVERS, so they cannot affect normal networking, and
--  they keep working even if another addon owns net.Incoming.
--    backdoorNets - known-malicious net message names. If one is received we
--      BLOCK it (our receiver runs instead of the backdoor's) and file a
--      dossier. Silent, no kick.
--    honeypotNets - fake "bait" names a cheat/exploit MENU blindly probes but
--      which do not exist on this gamemode (DarkRP economy nets on homigrad).
--      A caller is almost certainly running an exploit tool => dossier + kick.
--  CAUTION: any listed name is CLAIMED. If a real addon uses that exact net
--  name its messages get intercepted - only list names nothing legit uses.
-- ============================================================
C.backdoorNets = C.backdoorNets or {
	"OdiumBackDoor", "SessionBackdoor", "blacksmurfBackdoor", "DefqonBackdoor",
	"ZimbaBackdoor", "ZernaxBackdoor", "GaySploitBackdoor", "_GaySploit",
	"Remove_Exploiters", "disablebackdoor", "enablevac", "killserver", "fuckserver",
	"rconadmin", "ULX_QUERY2", "ULXQUERY2", "ULX_QUERY_TEST2", "_CAC_ReadMemory",
	"__G____CAC", "LuaCmd", "cvaraccess", "GMOD_NETDBG", "pwn_wake", "pwn_http_send",
	"pwn_http_answer", "Sbox_gm_attackofnullday_key", "elfamosabackdoormdr",
	"jeveuttonrconleul", "legrandguzmanestla", "thefrenchenculer",
}
C.honeypotNets = C.honeypotNets or {
	"SendMoney", "rp_givemoney", "darkrp_setmoney", "DarkRP_AdminWeapons",
}
if C.honeypotKick == nil then C.honeypotKick = true end
C.honeypotKickMsg = C.honeypotKickMsg or "Kicked: exploit tool activity detected."

WD._claimedNets = WD._claimedNets or {}   -- lname -> "backdoor" | "honeypot"

local function netGuard(name, kind)
	return function(_, ply)
		if not (IsValid(ply) and ply:IsPlayer()) then return end
		if WD.IsExempt(ply) then return end
		local honey = (kind == "honeypot")
		pcall(WD.AddSuspicion, ply, kind, 100, {
			note = honey and "called a honeypot net (exploit tool)" or "received a known-backdoor net (blocked)",
			net = name,
		}, (honey and C.honeypotKick) and "kicked" or "logged")
		if honey and C.honeypotKick and IsValid(ply) then
			ply:Kick(C.honeypotKickMsg)
		end
		-- never dispatch: the message is dropped
	end
end

local function claimNets()
	if not C.enabled then return end
	-- desired = what the two lists currently want claimed
	local desired = {}   -- lname -> { name, kind }
	local function want(list, kind)
		for _, name in ipairs(istable(list) and list or {}) do
			if isstring(name) and name ~= "" then desired[string.lower(name)] = { name = name, kind = kind } end
		end
	end
	want(C.backdoorNets, "backdoor")
	want(C.honeypotNets, "honeypot")
	-- release names we previously claimed but that were removed from the lists
	WD._netGuards = WD._netGuards or {}   -- lname -> the guard fn WE installed
	local changed = 0
	for lname in pairs(WD._claimedNets) do
		if not desired[lname] then
			if net.Receivers[lname] then net.Receivers[lname] = nil end
			WD._claimedNets[lname] = nil
			WD._netGuards[lname] = nil
			changed = changed + 1
		end
	end
	-- (re)claim the desired set - but only touch entries whose receiver isn't
	-- already our own guard, so the periodic 120s re-claim stays SILENT when
	-- nothing tried to take a name back (no more console spam), and a print
	-- now actually means something changed
	for lname, d in pairs(desired) do
		local guard = WD._netGuards[lname]
		if not guard or net.Receivers[lname] ~= guard or WD._claimedNets[lname] ~= d.kind then
			guard = netGuard(d.name, d.kind)
			util.AddNetworkString(d.name)
			net.Receivers[lname] = guard
			WD._netGuards[lname] = guard
			changed = changed + 1
		end
		WD._claimedNets[lname] = d.kind
	end
	if C.logConsole and changed > 0 then
		print("[Watchdog] claimed " .. table.Count(WD._claimedNets) ..
			" backdoor/honeypot net names (" .. changed .. " new/changed this pass)")
	end
end
WD.ClaimNets = claimNets   -- exposed so a panel list edit can re-claim immediately

-- claim after other addons register their receivers, then periodically re-claim
-- in case a late-loading addon (or the backdoor itself) re-registers the name.
hook.Add("InitPostEntity", "WD_ClaimNets", function() timer.Simple(15, claimNets) end)
timer.Simple(20, claimNets)               -- also fires on a hotload (InitPostEntity already passed)
timer.Create("WD_ReclaimNets", 120, 0, claimNets)

WD.RegisterModule("backdoor", {
	threshold = 100, decay = 0,
	desc = "PREVENT: blocks known-backdoor net messages",
})
WD.RegisterModule("honeypot", {
	threshold = 100, decay = 0,
	desc = "bait net names: exploit-tool callers (kicks)",
})

print("[Watchdog] net/exploit hardening loaded")
