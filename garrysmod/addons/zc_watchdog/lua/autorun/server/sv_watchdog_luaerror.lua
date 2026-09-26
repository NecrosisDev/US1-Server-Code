-- ============================================================
--  Watchdog module: LUAERROR  (clientside cheat-loader fingerprint)
-- ------------------------------------------------------------
--  GMod relays a client's Lua errors to the server (GM:OnClientLuaError,
--  native - no binary module, no client file). Injected cheat menus
--  routinely error while loading - trying to include their own modules
--  that aren't present, or throwing from their loader. Those errors
--  carry the cheat's own file/module names, which is a near-certain
--  fingerprint of a client running cheat code.
--
--  Two tiers:
--   1. BRAND signature - the error text contains a known cheat name
--      (kefir, zxc, ...). Near-certain => immediate dossier.
--   2. LOADER heuristic - an UNATTRIBUTED client (no addon name) failing
--      to include files from includes/modules/ (the classic partial-inject
--      signature). Lower confidence => needs a couple; can be disabled.
--
--  Extend WD.Config.luaerrSignatures as you spot new cheat names.
--  WATCH MODE: dossiers only. Staff (operator+) are exempt.
-- ============================================================
if not SERVER then return end
if not WD then include("autorun/server/sv_watchdog_core.lua") end

local C = WD.Config
-- case-insensitive substrings that mark a client cheat loader. Seeded from
-- what has actually shown up on the server; add new names as you see them.
C.luaerrSignatures = C.luaerrSignatures or {
	"kefirvip", "zxcmodule", "kefir", "zxc",
	"cheatmenu", "aimbot", "lmaobox", "hexpwn", "nixware",
}
if C.luaerrHeuristic == nil then C.luaerrHeuristic = true end

local BRAND_SCORE = 100   -- one hit => dossier
local HEUR_SCORE  = 45    -- ~2-3 hits => dossier
local THRESHOLD   = 100

local function lc(s) return string.lower(tostring(s or "")) end

hook.Add("OnClientLuaError", "WD_LuaError", function(err, ply, stack, name)
	if not WD.Config.enabled or not WD.ModuleEnabled("luaerror") then return end
	if not IsValid(ply) or not ply:IsPlayer() then return end
	if WD.IsExempt(ply) then return end

	local e = lc(err)

	-- 1) known cheat brand / module name in the error text
	for _, sig in ipairs(C.luaerrSignatures) do
		if sig ~= "" and e:find(lc(sig), 1, true) then
			WD.AddSuspicion(ply, "luaerror", BRAND_SCORE, {
				match = sig,
				error = string.sub(tostring(err), 1, 400),
				addon = tostring(name),
			})
			return
		end
	end

	-- 2) unattributed loader failing to pull its own modules
	if C.luaerrHeuristic then
		local unattributed = (name == nil or name == "" or lc(name) == "error")
		if unattributed
			and e:find("includes/modules/", 1, true)
			and e:find("not found or is empty", 1, true) then
			WD.AddSuspicion(ply, "luaerror", HEUR_SCORE, {
				match = "loader-pattern",
				error = string.sub(tostring(err), 1, 400),
				addon = tostring(name),
			})
		end
	end
end)

WD.RegisterModule("luaerror", {
	threshold = THRESHOLD,
	decay = 0,   -- these don't fade; a client that errored with cheat code did so
	desc = "clientside cheat-loader Lua errors",
})
