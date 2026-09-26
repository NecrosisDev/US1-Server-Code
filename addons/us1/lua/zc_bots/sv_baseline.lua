-- Read-only census command, cut down from Trauma's sv_baseline.lua. The
-- original correlated the performance and fakelod profiler windows -- both
-- dropped systems here (rule 1) -- so this keeps only the actor census and
-- precondition checks that are still meaningful on US1.

if not SERVER then return end

hg = hg or {}

local function line(ply, text)
	if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, text) else print(text) end
end

concommand.Add("zc_bots_baseline", function(ply)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end

	local fakes = 0
	for _, actor in ipairs(player.GetAll()) do
		if IsValid(actor.FakeRagdoll) then fakes = fakes + 1 end
	end

	line(ply, "")
	line(ply, "[zc_bots] baseline census -- " .. game.GetMap())
	line(ply, string.format("  zc_bots_enable=%s navmesh=%s humans=%d bots=%d fake-ragdolls=%d",
		tostring(hg.botdriver.Enabled()), tostring(navmesh.IsLoaded()),
		#player.GetHumans(), #player.GetBots(), fakes))
	line(ply, "")
end, nil, "Superadmin: print a census of bots, players and ragdolls.")
