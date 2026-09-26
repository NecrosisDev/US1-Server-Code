-- ============================================================
--  ZC Watchdog - COLD-INSTALL BOOTSTRAP (live server, no restart)
-- ------------------------------------------------------------
--  Purpose: bring the whole server half up on a LIVE server that has
--  never loaded the addon (an addon folder uploaded mid-session is not
--  lua-mounted until the next boot, so autorun never ran and include()
--  paths don't resolve - but file.Read with "GAME" sees the raw disk).
--
--  Steps:
--   1. Upload zc_watchdog/ into garrysmod/addons/ and merge the
--      ulx_cmdlog files (the whole ZCity-Anticheat zip extracts to that
--      layout) via the file manager.
--   2. Run ONE console command:
--      lua_run RunString(file.Read("addons/zc_watchdog/wd_bootstrap.lua","GAME"))
--
--  Loads every server file in dependency order (CORE FIRST) and prints
--  ok/FAIL per file. Safe to run twice (all files are hotload-safe).
--  Client panels (wd panel, toasts, Staff Logs Watchdog tab) stay
--  restart cargo - staff still get chat-line alerts immediately.
-- ============================================================
if not SERVER then return end

local WD_FILES = {
	"sv_watchdog_core.lua",       -- MUST be first
	"sv_watchdog_aim.lua",
	"sv_watchdog_silentaim.lua",
	"sv_watchdog_spin.lua",
	"sv_watchdog_trigger.lua",
	"sv_watchdog_movement.lua",
	"sv_watchdog_prevent.lua",
	"sv_watchdog_net.lua",
	"sv_watchdog_http.lua",
	"sv_watchdog_pingkick.lua",
	"sv_watchdog_luaerror.lua",
	"sv_watchdog_cslua.lua",
	"sv_watchdog_alt.lua",
	"sv_watchdog_evasion.lua",
	"sv_watchdog_vpn.lua",
	"sv_watchdog_name.lua",
	"sv_watchdog_ui.lua",
	"sv_watchdog_test.lua",
}
-- Staff Logs integration (skipped per-file if not on disk yet)
local CMDLOG_FILES = {
	"addons/ulx_cmdlog/lua/autorun/server/sv_watchdog_log.lua",
	"addons/ulx_cmdlog/lua/autorun/server/sv_ulx_logpanel.lua",
	"addons/ulx_cmdlog/lua/autorun/server/sv_punish_history.lua",
}

local ok, fail, miss = 0, 0, 0
local function boot(path)
	local src = file.Read(path, "GAME")
	if not src then
		miss = miss + 1
		print("[WD boot] MISSING (not uploaded?): " .. path)
		return
	end
	local err = RunString(src, path, false)   -- false => return the error text
	if err then
		fail = fail + 1
		print("[WD boot] FAIL " .. path .. "  ->  " .. tostring(err))
	else
		ok = ok + 1
		print("[WD boot] ok   " .. path)
	end
end

print("[WD boot] ================ ZC Watchdog cold install ================")
for _, f in ipairs(WD_FILES) do
	boot("addons/zc_watchdog/lua/autorun/server/" .. f)
end
for _, p in ipairs(CMDLOG_FILES) do
	boot(p)
end
print(string.format("[WD boot] done: %d loaded, %d failed, %d missing", ok, fail, miss))
print("[WD boot] verify with: wd_status   (expect the module list + staff shown EXEMPT)")
print("[WD boot] NOTES for a live install:")
print("[WD boot]  - pingkick ENFORCES by default. Dry-run it first:  wd_config pingKickEnforce false")
print("[WD boot]  - sv_allowcslua goes to 0 a couple seconds after load (intended).")
print("[WD boot]  - wd panel / toasts / Staff Logs Watchdog tab are RESTART CARGO;")
print("[WD boot]    until then staff get chat-line alerts only.")
print("[WD boot]  - join checks (vpn/evasion/altshare/name) screen NEW joins; sweep")
print("[WD boot]    players already online with:  wd_test <name>")
print("[WD boot] ==========================================================")
