-- ============================================================
--  Watchdog module: ALTSHARE  (family-share / ban-evasion alt)
-- ------------------------------------------------------------
--  A Family-Shared account plays on a license it doesn't own:
--  Player:OwnerSteamID64() differs from Player:SteamID64(). That's
--  legit for shared households, but it's also the #1 ban-evasion route
--  - a banned player borrowing an unbanned family license. So:
--   * OWNER account is banned  => near-certain evasion => dossier.
--   * any family-share         => optional (altFlagAllShares), off by
--                                 default to avoid noise from legit sharers.
--  Watch mode: dossiers only - never auto-ban a family-share (many are
--  legitimate). OwnerSteamID64 is only valid after full Steam auth, so
--  the check is delayed.
-- ============================================================
if not SERVER then return end
if not WD then include("autorun/server/sv_watchdog_core.lua") end

local C = WD.Config
if C.altFlagAllShares == nil then C.altFlagAllShares = false end

local function banActive(b)
	if not istable(b) then return false end
	local unban = tonumber(b.unban)
	return unban == nil or unban == 0 or unban > os.time()   -- 0 = permanent
end

local function ownerBanned(owner64)
	if not (ULib and ULib.bans) then return false end
	local steam = util.SteamIDFrom64(owner64)
	return (steam ~= nil and banActive(ULib.bans[steam])) or banActive(ULib.bans[owner64])
end

local function check(ply)
	if not IsValid(ply) or not ply:IsPlayer() or ply:IsBot() then return end
	if WD.IsExempt(ply) then return end

	local owner = ply:OwnerSteamID64()
	local self64 = ply:SteamID64()
	if not owner or not self64 or owner == "0" or self64 == "0" then return end
	if owner == self64 then return end   -- not shared

	if ownerBanned(owner) then
		WD.AddSuspicion(ply, "altshare", 100, {
			note = "family-shared from a BANNED owner account (likely ban evasion)",
			owner64 = owner, ownerSteam = util.SteamIDFrom64(owner),
		})
	elseif C.altFlagAllShares then
		WD.AddSuspicion(ply, "altshare", 100, {
			note = "family-shared account", owner64 = owner,
			ownerSteam = util.SteamIDFrom64(owner),
		})
	end
end

hook.Add("PlayerInitialSpawn", "WD_Alt", function(ply)
	-- OwnerSteamID64 needs full auth; give it time (retry once).
	timer.Simple(8, function()
		if not IsValid(ply) then return end
		if ply.IsFullyAuthenticated and not ply:IsFullyAuthenticated() then
			timer.Simple(8, function() if IsValid(ply) then check(ply) end end)
		else
			check(ply)
		end
	end)
end)

WD.RegisterModule("altshare", {
	threshold = 100, decay = 0,
	desc = "family-share / ban-evasion alt",
})
