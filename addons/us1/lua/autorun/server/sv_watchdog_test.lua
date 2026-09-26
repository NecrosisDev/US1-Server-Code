-- ============================================================
--  Watchdog: SELF-TEST  (superadmin diagnostic - safe to remove)
-- ------------------------------------------------------------
--  `wd_test [module] [player]`  (superadmin console)
--
--  Exercises the REAL detection logic of the automatable modules and
--  the full report chain (dossier -> staff toast -> cmdlog Watchdog tab
--  -> AC-tag), so you can confirm everything works without a cheat.
--
--   wd_test              - run every automatable test on YOURSELF
--   wd_test <player>     - ...on another player (a user-rank volunteer)
--   wd_test pipeline     - just the report-chain test
--   wd_test luaerror     - just the cheat-loader-error test
--
--  Detections only fire on NON-EXEMPT targets, so to test on yourself:
--     wd_config exemptElevated false    (run test)    then set it back true
--  The pipeline test works regardless (it writes a dossier directly).
--
--  Modules that need real in-game input (aim/spin/trigger/speed/noclip)
--  can't be faked from console - see the printed manual tips + the
--  false-positive methodology in DEPLOY/TESTING.
-- ============================================================
if not SERVER then return end
if not WD then include("autorun/server/sv_watchdog_core.lua") end

local function findPlayer(q)
	if not q or q == "" then return nil end
	q = string.lower(q)
	for _, p in ipairs(player.GetAll()) do
		if string.lower(p:Nick()):find(q, 1, true) or string.lower(p:SteamID()):find(q, 1, true) then
			return p
		end
	end
	return nil
end

-- call a specific named hook (Watchdog's own) without firing everyone else's
local function fireHook(event, name, ...)
	local t = hook.GetTable()[event]
	local fn = t and t[name]
	if fn then fn(...) return true end
	return false
end

local MODULE_NAMES = {
	pipeline = true, luaerror = true, cslua = true,
	altshare = true, evasion = true, vpn = true, name = true,
}

concommand.Add("wd_test", function(ply, _, args)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end

	local function out(msg)
		print("[wd_test] " .. msg)
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, "[wd_test] " .. msg) end
	end

	-- args: [module] [player]  OR  [player]
	local which, targetQ = "all", nil
	if args[1] then
		if MODULE_NAMES[string.lower(args[1])] then which = string.lower(args[1]); targetQ = args[2]
		else targetQ = args[1] end
	end
	local target = targetQ and findPlayer(targetQ) or ply
	if not IsValid(target) then out("no target (run from a player, or pass a name)"); return end

	out("================ Watchdog self-test ================")
	out(string.format("v%s | mode %s | enabled %s", WD.VERSION,
		WD.Config.watchMode and "WATCH" or "ENFORCE", tostring(WD.Config.enabled)))
	out("target: " .. target:Nick() .. " (" .. target:SteamID() .. ")")
	local exempt = WD.IsExempt(target)
	out("target exempt: " .. tostring(exempt))
	if exempt then
		out("  !! EXEMPT -> logic tests below will NOT file a dossier.")
		out("  !! to test detections: wd_config exemptElevated false  (then re-run, set back true after)")
	end
	out("registered modules: " .. table.Count(WD.Modules))

	-- 1) REPORT CHAIN (always works; bypasses exemption)
	if which == "all" or which == "pipeline" then
		out("[pipeline] writing a synthetic dossier + firing the staff alert ...")
		WD.WriteDossier(target, "test", {
			note = "wd_test synthetic detection - not a real cheat",
			by = IsValid(ply) and ply:Nick() or "console",
		})
		out("  -> VERIFY: (a) a chat line + on-screen toast reached staff,")
		out("            (b) `wd_dossiers` lists a new 'test' file,")
		out("            (c) the Watchdog tab in !logs shows a 'test' row.")
	end

	-- 2) luaerror (real logic: synthetic known-cheat client error)
	if which == "all" or which == "luaerror" then
		out("[luaerror] firing a synthetic kefir client Lua error ...")
		local ok = fireHook("OnClientLuaError", "WD_LuaError",
			"[ERROR] Couldn't include file 'includes/modules/kefirvip.lua' - File not found (@gamemode/base/cl_init.lua)",
			target, {}, "ERROR")
		out(ok and "  -> expect a 'luaerror' dossier (if target non-exempt)" or "  -> module not loaded")
	end

	-- 3) cslua (real logic: synthetic RunString injected-exec error)
	if which == "all" or which == "cslua" then
		out("[cslua] firing a synthetic RunString injected-exec error ...")
		local ok = fireHook("OnClientLuaError", "WD_CSLua",
			"[ERROR] attempt to index a nil value (@RunString:12)", target, {}, "ERROR")
		out(ok and "  -> expect a 'cslua' dossier (if non-exempt)" or "  -> module not loaded")
	end

	-- 4) join-time modules (real logic on the target's real IP / name / bans)
	if which == "all" or which == "altshare" then
		out("[altshare] running the family-share check on target ...")
		fireHook("PlayerInitialSpawn", "WD_Alt", target)
		out("  -> dossier only if target's license owner is a banned account")
	end
	if which == "all" or which == "evasion" then
		out("[evasion] running the shared-IP ban-evasion check on target ...")
		fireHook("PlayerInitialSpawn", "WD_Evasion", target)
		out("  -> dossier only if target's IP was used by a banned account")
	end
	if which == "all" or which == "vpn" then
		out("[vpn] running the REAL proxycheck.io lookup on target's IP (~a few s) ...")
		fireHook("PlayerInitialSpawn", "WD_VPN", target)
		out("  -> dossier if that IP is a VPN/proxy. Tests the API key end-to-end.")
	end
	if which == "all" or which == "name" then
		out("[name] running the nick scan on target's current name ...")
		fireHook("PlayerInitialSpawn", "WD_Name", target)
		out("  -> dossier only if the name has control/RTL chars")
	end

	-- 5) modules that need real input
	if which == "all" then
		out("---- need real in-game input (can't fake from console) ----")
		out("  aim/trigger : a real fast flick landing on a player while firing")
		out("  spin        : sustained fast mouse-spin (or a spinbot) - also flags pitch>90 / rolled view")
		out("  speed       : sustained on-ground speed above your run speed")
		out("  noclip      : a non-admin entering noclip")
		out("  The real test for these is watch-mode over live play: confirm they")
		out("  stay QUIET through normal KO/fear/vehicle chaos (zero false dossiers).")
	end
	out("================ end self-test ================")
end, nil, "Superadmin: Watchdog self-test: wd_test [module] [player].")

print("[Watchdog] self-test loaded - superadmin: wd_test")
