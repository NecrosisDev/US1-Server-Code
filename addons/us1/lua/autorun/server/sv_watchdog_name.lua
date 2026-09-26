-- ============================================================
--  Watchdog module: NAME  (malformed / spoofed player name)
-- ------------------------------------------------------------
--  Flags Steam names carrying characters used to impersonate staff,
--  break logs, or evade name-bans:
--   * control bytes  < 0x20  (newline / carriage-return / tab / etc.)
--   * U+202E RTL-override and other bidi/zero-width marks
--  Legit Unicode names are fine - only these specific dangerous
--  codepoints trip it. WATCH MODE: dossiers only.
-- ============================================================
if not SERVER then return end
if not WD then include("autorun/server/sv_watchdog_core.lua") end

-- UTF-8 byte sequences for the genuinely-abusive bidi controls. Deliberately
-- NARROW: zero-width-joiner (U+200D) is part of legit compound emoji and LRM/RLM
-- appear in some legit international names, so we flag only the RTL OVERRIDE /
-- EMBEDDING marks (used to disguise/impersonate) plus control bytes below.
local BAD_SEQ = {
	["\226\128\174"] = "RTL-override U+202E",
	["\226\128\173"] = "LTR-override U+202D",
	["\226\128\171"] = "RTL-embedding U+202B",
	["\226\128\170"] = "LTR-embedding U+202A",
}

local function scan(nick)
	local hits = {}
	for i = 1, #nick do
		local b = string.byte(nick, i)
		if b < 0x20 then
			hits[#hits + 1] = "control-byte 0x" .. string.format("%02X", b)
		end
	end
	for seq, label in pairs(BAD_SEQ) do
		if string.find(nick, seq, 1, true) then hits[#hits + 1] = label end
	end
	return hits
end

local function check(ply)
	if not IsValid(ply) or not ply:IsPlayer() or ply:IsBot() then return end
	if WD.IsExempt(ply) then return end
	local nick = ply:Nick()
	local hits = scan(nick)
	if #hits > 0 then
		WD.AddSuspicion(ply, "name", 100, { nick = nick, issues = hits })
	end
end

hook.Add("PlayerInitialSpawn", "WD_Name", function(ply)
	timer.Simple(2, function() if IsValid(ply) then check(ply) end end)
end)

WD.RegisterModule("name", {
	threshold = 100, decay = 0,
	desc = "malformed / spoofed player name",
})
