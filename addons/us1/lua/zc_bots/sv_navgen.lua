-- Builds a navmesh once for maps that ship without one, so bots can exist there.
--
-- zc_bots_navgen: 0 off (default) | 1 only while no human is connected
--                 | 2 build shortly after map load even with players on.
--
-- Generation is brutal on the server and, going by the engine's nav_generate
-- path, ends in a map reload; GMod documents neither. It has also crashed
-- servers (garrysmod-issues #2332, #3999, #5375), so every attempt is written
-- to disk BEFORE it starts and a map that fails twice is never tried again.
-- PROVISIONAL(2026-09-21, reload/save behaviour unverified on a dedicated server, ratify-by: 2026-10-15)

if not SERVER then return end

hg.botdriver.navgen = hg.botdriver.navgen or {}
local navgen = hg.botdriver.navgen
local log = hg.botdriver.log

local cv_mode = ConVarExists("zc_bots_navgen") and GetConVar("zc_bots_navgen")
	or CreateConVar("zc_bots_navgen", "0", FCVAR_ARCHIVE, "Auto-build missing navmeshes: 0 off, 1 when empty, 2 always", 0, 2)
local cv_delay = ConVarExists("zc_bots_navgen_delay") and GetConVar("zc_bots_navgen_delay")
	or CreateConVar("zc_bots_navgen_delay", "45", FCVAR_ARCHIVE, "Seconds of warning before a forced (mode 2) build", 15, 600)

local MAX_ATTEMPTS = 2
local STATE_FILE = "zc_bots/navgen_attempts.json"
local SPAWN_PREFIXES = { "info_player_", "gmod_player_start", "info_survivor_", "info_zombie_" }
local POINT_GROUPS = { "RandomSpawns", "HMCD_TDM_T", "HMCD_TDM_CT" }

local function readState()
	local raw = file.Read(STATE_FILE, "DATA")
	local tbl = raw and util.JSONToTable(raw, false, true) -- keep keys as strings
	return istable(tbl) and tbl or {}
end

local function writeState(tbl)
	file.CreateDir("zc_bots")
	file.Write(STATE_FILE, util.TableToJSON(tbl, true))
end

function navgen.HasNav()
	return navmesh.IsLoaded() or navmesh.GetNavAreaCount() > 0
end

local function groundSeed(pos)
	local tr = util.TraceLine({ start = pos + Vector(0, 0, 16), endpos = pos - Vector(0, 0, 256), mask = MASK_PLAYERSOLID_BRUSHONLY })
	if not tr.Hit or tr.StartSolid then return false end
	navmesh.AddWalkableSeed(tr.HitPos, tr.HitNormal)
	return true
end

-- Homigrad maps often have no info_player_start, which is all the generator
-- looks for by default: seed from every spawn entity and the gamemode's points.
local function addSeeds()
	navmesh.ClearWalkableSeeds()
	local count, spawnClass = 0, nil
	for _, ent in ents.Iterator() do
		local class = ent:GetClass()
		for i = 1, #SPAWN_PREFIXES do
			if string.StartWith(class, SPAWN_PREFIXES[i]) then
				spawnClass = spawnClass or class
				if groundSeed(ent:GetPos()) then count = count + 1 end
				break
			end
		end
	end
	if zb and isfunction(zb.GetMapPoints) then
		for _, group in ipairs(POINT_GROUPS) do
			local ok, points = pcall(zb.GetMapPoints, group)
			if ok and istable(points) then
				for _, point in ipairs(points) do
					if istable(point) and isvector(point.pos) and groundSeed(point.pos) then count = count + 1 end
				end
			end
		end
	end
	if spawnClass then navmesh.SetPlayerSpawnName(spawnClass) end
	return count
end

local function begin(reason)
	if navgen.HasNav() or navmesh.IsGenerating() then return false end
	local map = game.GetMap()

	local state = readState()
	local rec = state[map] or { attempts = 0 }
	if rec.attempts >= MAX_ATTEMPTS then return false end

	local seeds = addSeeds()
	if seeds == 0 then
		log.warn("navgen", map .. ": no walkable seed found, not generating")
		rec.attempts = MAX_ATTEMPTS
		rec.note = "no seeds"
		state[map] = rec
		writeState(state)
		return false
	end

	rec.attempts = rec.attempts + 1
	rec.lastStart = os.time()
	state[map] = rec
	-- Remember the operator's own hibernate setting so restoreHibernate() can
	-- put it back; persisted because a finished build reloads the map.
	local hib = GetConVar("sv_hibernate_think")
	local prevHib = hib and hib:GetString() or nil
	if prevHib and prevHib ~= "1" and state._hibernatePrev == nil then state._hibernatePrev = prevHib end
	writeState(state)

	-- Keep frames running with nobody connected, or an empty-server build never advances.
	RunConsoleCommand("sv_hibernate_think", "1")
	navgen.startedAt = SysTime()
	navgen.running = true
	log.info("navgen", string.format("%s: generating navmesh (%s, %d seeds, attempt %d/%d)", map, reason, seeds, rec.attempts, MAX_ATTEMPTS))
	navmesh.BeginGeneration()
	return true
end

local function humansPresent()
	if #player.GetHumans() > 0 then return true end
	return player.GetCountConnecting and player.GetCountConnecting() > 0 or false
end

-- Undo begin()'s sv_hibernate_think 1 once no build is running.
local function restoreHibernate()
	if navgen.running or navmesh.IsGenerating() then return end
	local state = readState()
	local prev = state._hibernatePrev
	if prev == nil then return end
	state._hibernatePrev = nil
	writeState(state)
	RunConsoleCommand("sv_hibernate_think", tostring(prev))
end

local function tick()
	if navgen.running then
		if navmesh.IsGenerating() then return end
		-- Only reached if the engine did not reload the map on completion.
		navgen.running = false
		if navmesh.GetNavAreaCount() > 0 then
			navmesh.Save()
			log.info("navgen", string.format("%s: done, %d areas in %.0f s", game.GetMap(), navmesh.GetNavAreaCount(), SysTime() - (navgen.startedAt or SysTime())))
		else
			log.warn("navgen", game.GetMap() .. ": generation ended with no areas")
		end
		restoreHibernate()
		return
	end

	local mode = cv_mode:GetInt()
	if mode == 0 or navgen.HasNav() then return end
	-- 2026-09-25: automatic builds only while the bot package is enabled. A
	-- build lags the server for minutes and ends in a map reload; with
	-- zc_bots_enable 0 that was pure cost to players (US1 kept building on
	-- 9/25 with bots off). zc_bots_navgen_now still works on demand.
	if not hg.botdriver.Enabled() then
		navgen.warnAt, navgen.emptySince = nil, nil
		return
	end
	if CurTime() < 20 then return end -- let the map settle; navmesh calls made too early crash

	if mode == 1 then
		if humansPresent() then navgen.emptySince = nil return end
		navgen.emptySince = navgen.emptySince or CurTime()
		if CurTime() - navgen.emptySince >= 30 then begin("server empty") end
		return
	end

	-- mode 2: warn, then build regardless
	if not humansPresent() then begin("forced, empty") return end
	local state = readState()[game.GetMap()]
	if state and state.attempts >= MAX_ATTEMPTS then return end
	if not navgen.warnAt then
		navgen.warnAt = CurTime()
		PrintMessage(HUD_PRINTTALK, string.format("[Server] This map has no bot navigation yet. Building it in %d s: expect heavy lag for a few minutes, then a map reload. This happens once per map.", cv_delay:GetInt()))
	elseif CurTime() - navgen.warnAt >= cv_delay:GetInt() then
		PrintMessage(HUD_PRINTTALK, "[Server] Building bot navigation now.")
		begin("forced")
	end
end

-- A nav exists now: the map's earlier attempts succeeded, forget them.
local function settle()
	restoreHibernate()
	if not navgen.HasNav() then return end
	local state = readState()
	if state[game.GetMap()] then
		state[game.GetMap()] = nil
		writeState(state)
	end
end

timer.Create("zc_bots_navgen_tick", 5, 0, tick)
timer.Create("zc_bots_navgen_settle", 25, 1, settle)

concommand.Add("zc_bots_navgen_now", function(ply)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	if navgen.HasNav() then print("[zc_bots] this map already has a navmesh") return end
	print(begin("manual") and "[zc_bots] generation started" or "[zc_bots] not started (attempt limit, no seeds, or already running)")
end, nil, "Superadmin: generate a navmesh for this map now.")

concommand.Add("zc_bots_navgen_status", function(ply)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	print(string.format("[zc_bots] map=%s hasNav=%s areas=%d generating=%s mode=%d", game.GetMap(), tostring(navgen.HasNav()), navmesh.GetNavAreaCount(), tostring(navmesh.IsGenerating()), cv_mode:GetInt()))
	PrintTable(readState())
end, nil, "Superadmin: print navmesh generation status.")

concommand.Add("zc_bots_navgen_forget", function(ply, _, args)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	local state = readState()
	state[args[1] or game.GetMap()] = nil
	writeState(state)
	print("[zc_bots] cleared navgen attempts for " .. (args[1] or game.GetMap()))
end, nil, "Superadmin: forget failed navmesh attempts: zc_bots_navgen_forget [map].")
