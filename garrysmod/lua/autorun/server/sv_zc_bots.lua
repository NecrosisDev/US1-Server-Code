-- zc_bots loader: explicit ordered include list. Server realm only, plain
-- include() everywhere -- nothing here has a client half, so no file is ever
-- registered for client download.
--
-- Re-runnable by design: lua_openscript can run this on a live server, and
-- Lua autorefresh re-runs an edited file. Every file it includes guards its
-- own state with `X = X or {}` and registers hooks/timers under fixed ids
-- (hook.Add replaces by name; timer.Create replaces by name), so re-running
-- this list is safe.

if not SERVER then return end

local FILES = {
	"zc_bots/sv_shim.lua",
	"zc_bots/sv_npc.lua",
	"zc_bots/sv_survival_defaults.lua",
	"zc_bots/sv_arbiter.lua",
	"zc_bots/sv_baseline.lua",
	"zc_bots/sv_brain.lua",
	"zc_bots/sv_personality.lua",
	"zc_bots/sv_identity.lua",
	"zc_bots/sv_persona.lua",
	"zc_bots/sv_relations.lua",
	"zc_bots/sv_aim.lua",
	"zc_bots/sv_control.lua",
	"zc_bots/sv_nav.lua",
	"zc_bots/sv_traverse.lua",
	"zc_bots/sv_steer.lua",
	"zc_bots/sv_movement.lua",
	"zc_bots/sv_doors.lua",
	"zc_bots/sv_weaponscore.lua",
	"zc_bots/sv_cover.lua",
	"zc_bots/sv_survival.lua",
	"zc_bots/sv_melee.lua",
	"zc_bots/sv_gunhandling.lua",
	"zc_bots/sv_grenade.lua",
	"zc_bots/sv_squad.lua",
	"zc_bots/sv_hearing.lua",
	"zc_bots/sv_difficulty.lua",
	"zc_bots/sv_chat_style.lua",
	"zc_bots/sv_chatter.lua",
	"zc_bots/sv_social_lines.lua",
	"zc_bots/sv_social.lua",
	"zc_bots/sv_chat_listen.lua",
	"zc_bots/sv_spec_talk.lua",
	"zc_bots/sv_spec_talk_lines.lua",
	"zc_bots/sv_radial.lua",
	"zc_bots/sv_emote.lua",
	"zc_bots/behaviors/sv_core_reflex.lua",
	"zc_bots/behaviors/sv_core_survival.lua",
	"zc_bots/behaviors/sv_core_acquire.lua",
	"zc_bots/behaviors/sv_core_combat.lua",
	"zc_bots/behaviors/sv_core_idle.lua",
	"zc_bots/behaviors/sv_core_support.lua",
	"zc_bots/behaviors/sv_core_investigate.lua",
	"zc_bots/behaviors/sv_suppression.lua",
	"zc_bots/behaviors/sv_medic.lua",
	"zc_bots/behaviors/sv_loot.lua",
	"zc_bots/behaviors/sv_outnumbered.lua",
	"zc_bots/sv_duel.lua",
	"zc_bots/sv_lastresort.lua",
	"zc_bots/sv_shooter_modes.lua",
	"zc_bots/sv_crowd.lua",
	"zc_bots/modes/sv_homicide.lua",
	"zc_bots/modes/sv_tdm.lua",
	"zc_bots/modes/sv_coop.lua",
	"zc_bots/modes/sv_defense.lua",
	"zc_bots/modes/sv_cstrike.lua",
	"zc_bots/modes/sv_hl2dm.lua",
	"zc_bots/modes/sv_dm.lua",
	"zc_bots/modes/sv_sfd.lua",
	"zc_bots/modes/sv_masscasualty.lua",
	"zc_bots/modes/sv_activeshooter.lua",
	"zc_bots/modes/sv_gwars.lua",
	"zc_bots/modes/sv_criresp.lua",
	"zc_bots/modes/sv_homelanderhns.lua",
	"zc_bots/modes/sv_riot.lua",
	"zc_bots/modes/sv_uncontainedriot.lua",
	"zc_bots/modes/sv_mayhem.lua",
	"zc_bots/modes/sv_wildcard.lua",
	"zc_bots/sv_navgen.lua",
	"zc_bots/sv_presence.lua",
	"zc_bots/sv_fill.lua",
	"zc_bots/sv_bench.lua",
	"zc_bots/sv_lowpop.lua",
	"zc_bots/sv_diagnose.lua",
}

-- Each file is compiled and run under xpcall so one bad file cannot take the
-- rest down silently, and the outcome is written where it can be read without
-- console access: data/zc_bots/load_report.txt.
local function loadAll(reason)
	local lines = { string.format("zc_bots load (%s) map=%s time=%s", reason, game.GetMap(), os.date("%Y-%m-%d %H:%M:%S")) }
	local failed = 0
	for _, path in ipairs(FILES) do
		local fn = CompileFile(path)
		if not isfunction(fn) then
			failed = failed + 1
			lines[#lines + 1] = "COMPILE-FAIL " .. path
		else
			local ok, err = xpcall(fn, debug.traceback)
			if ok then
				lines[#lines + 1] = "ok   " .. path
			else
				failed = failed + 1
				lines[#lines + 1] = "ERROR " .. path .. "\n" .. tostring(err)
			end
		end
	end
	lines[#lines + 1] = string.format("RESULT files=%d failed=%d", #FILES, failed)
	file.CreateDir("zc_bots")
	file.Write("zc_bots/load_report.txt", table.concat(lines, "\n") .. "\n")
	print(lines[#lines])
end

-- Runtime errors from this package, bounded, for remote reading.
local errorCount = 0
hook.Add("OnLuaError", "zc_bots_error_log", function(err, _, stack)
	if errorCount >= 60 then return end
	local text = tostring(err)
	local ours = string.find(text, "zc_bots", 1, true) ~= nil
	if not ours and istable(stack) then
		for i = 1, math.min(#stack, 6) do
			local frame = stack[i]
			if istable(frame) and isstring(frame.File) and string.find(frame.File, "zc_bots", 1, true) then ours = true break end
		end
	end
	if not ours then return end
	errorCount = errorCount + 1
	file.CreateDir("zc_bots")
	file.Append("zc_bots/errors.txt", os.date("%H:%M:%S ") .. text .. "\n")
end)

-- Cold boot runs autorun before the gamemode exists; mid-session
-- lua_openscript finds it already there.
if zb and zb.modes then
	loadAll("live")
else
	hook.Add("InitPostEntity", "zc_bots_deferred_load", function() loadAll("boot") end)
end
