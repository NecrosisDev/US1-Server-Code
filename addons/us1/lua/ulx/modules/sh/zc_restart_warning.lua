-- ulx zcrestart: staff restart scheduler for Goob's ZCity, backed by restart_warning.
-- ULX file.Find()s ulx/modules/sh/*.lua across every mounted addon on boot (addons/ulx/lua/ulx/init.lua)
-- and AddCSLuaFile()s it, so this file ships inside addons/restart_warning like addons/bigsay does.
-- All scheduling authority stays in autorun/server/sv_restart_warning.lua (global
-- ZC_RESTART_WARNING); this module only translates chat/console input into its API.
local CATEGORY_NAME = "Utility"
local USAGE = "Usage: !restart <time> <reason>  -  time: 30s, 10m, 1h30m, now, or a server time like 18:30  -  !restart cancel to stop"

local function controller()
	local R = ZC_RESTART_WARNING
	if type(R) ~= "table" or type(R.RequestManual) ~= "function" or type(R.Change) ~= "function"
		or type(R.Status) ~= "function" or type(R.ParseWhen) ~= "function" then
		return nil
	end
	return R
end

local function doCancel(calling_ply, R)
	local st = R.Status()
	if not st.nextAt or st.nextAt == 0 then
		ULib.tsayError(calling_ply, "No restart is pending.", true)
		return
	end
	local left = st.left
	-- Only a restart players were told about (staff restart, stated reason, or inside the notice
	-- window). A repeated "!restart cancel" must never silently skip a far-off daily restart.
	if not (st.manual or st.reason ~= "" or left <= (R.Window or 900)) then
		ULib.tsayError(calling_ply, "No announced restart to cancel. Next is the daily restart in "..R.FormatDuration(left).."; skip it in F8 > Server > Restarts.", true)
		return
	end
	local ok, msg = R.Change(calling_ply, "cancel", st.token, "")
	if ok then
		ULib.tsay(calling_ply, "Cancelled the restart that was due in "..R.FormatDuration(left)..". "..msg, true)
		ulx.fancyLogAdmin(calling_ply, true, "#A cancelled the pending restart")
	else
		ULib.tsayError(calling_ply, msg, true)
	end
end

function ulx.zcrestart(calling_ply, when, reason)
	if not SERVER then return end
	local R = controller()
	if not R then
		ULib.tsayError(calling_ply, "Restart controls are unavailable (restart_warning addon not loaded).", true)
		return
	end
	if not IsValid(calling_ply) then
		ULib.tsayError(calling_ply, "Run !restart in game as an admin; the restart controller needs a player.", true)
		return
	end

	local trimmed = (when or ""):match("^%s*(.-)%s*$")
	local lowered = trimmed:lower()

	if lowered == "" then
		ULib.tsay(calling_ply, USAGE, true)
		local st = R.Status()
		local status
		if st.error ~= "" then
			status = st.error
		elseif st.nextAt > 0 then
			status = "Next restart in "..R.FormatDuration(st.left).." ("..st.serverNext..")"
				..(st.manual and ", staff restart" or st.override and ", moved by staff" or ", daily schedule")
				..(st.reason ~= "" and (": "..st.reason) or "")
		else
			status = "No restart is scheduled."
		end
		ULib.tsay(calling_ply, status, true)
		return
	end

	if lowered == "cancel" or lowered == "stop" then
		doCancel(calling_ply, R)
		return
	end

	local seconds, err = R.ParseWhen(trimmed)
	if not seconds then
		ULib.tsayError(calling_ply, err, true)
		ULib.tsay(calling_ply, USAGE, true)
		return
	end

	local reasonTrimmed = (reason or ""):match("^%s*(.-)%s*$")
	local reasonOrNil = reasonTrimmed ~= "" and reasonTrimmed or nil
	local ok, msg = R.RequestManual(calling_ply, seconds, reasonOrNil)
	if ok then
		ULib.tsay(calling_ply, msg, true)
		ulx.fancyLogAdmin(calling_ply, true, "#A scheduled a restart in #s: #s", R.FormatDuration(seconds), reasonOrNil or "(no reason)")
	else
		ULib.tsayError(calling_ply, msg, true)
	end
end

function ulx.zcrestartcancel(calling_ply)
	if not SERVER then return end
	local R = controller()
	if not R then
		ULib.tsayError(calling_ply, "Restart controls are unavailable (restart_warning addon not loaded).", true)
		return
	end
	if not IsValid(calling_ply) then
		ULib.tsayError(calling_ply, "Run !restart in game as an admin; the restart controller needs a player.", true)
		return
	end
	doCancel(calling_ply, R)
end

local restart = ulx.command(CATEGORY_NAME, "ulx restart", ulx.zcrestart, "!restart")
restart:addParam{ type = ULib.cmds.StringArg, hint = "30s|10m|1h30m|18:30|now|cancel", ULib.cmds.optional }
restart:addParam{ type = ULib.cmds.StringArg, hint = "reason", ULib.cmds.optional, ULib.cmds.takeRestOfLine }
restart:defaultAccess(ULib.ACCESS_ADMIN)
restart:help("Schedule a maintenance restart with a reason (e.g. !restart 10m Updating maps). !restart cancel stops it; no arguments shows status.")

local restartcancel = ulx.command(CATEGORY_NAME, "ulx restartcancel", ulx.zcrestartcancel, "!restartcancel")
restartcancel:defaultAccess(ULib.ACCESS_ADMIN)
restartcancel:help("Cancel the pending restart (same as !restart cancel).")
