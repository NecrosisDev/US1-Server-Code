-- ============================================================
--  ZC LOOTFAST - kill the 18-trace random walk in SpawnTheBoxes
-- ------------------------------------------------------------
--  MEASURED (zc_perf auto-capture): timer "SpawnTheBoxes" cost
--  8.6ms in a single frame, every 8 seconds, forever, on every
--  map, in every mode that has LootSpawn.
--
--  WHY IT IS THAT BIG (sv_lootspawn.lua:609 "Boxes Think"/"SpawnBoxes"):
--    the gamemode picks a random player and then does a DRUNKEN
--    RANDOM WALK from that player's eyes to find a loot position -
--    1 long TraceLine along (velocity * rand(1,100) + VectorRand),
--    then 8 iterations of { TraceLine along VectorRand(-1024,1024),
--    QuickTrace down 1024 }. That is SEVENTEEN full-length world
--    traces through the BSP, plus an ents.FindInBox over a 1000-unit
--    cube, plus a visibility TraceLine per player inside it - all in
--    ONE frame, and if any player can see the result the whole thing
--    is thrown away and nothing spawns.
--
--  THE GAMEMODE ALREADY HAS THE ANSWER, COMMENTED OUT. Two lines
--  above the walk:
--        //local spawnPos = table.Random(spawns) + vec
--  `spawns` is the map-wide table of ground-validated points built
--  once at PostCleanupMap (info_* entities + navmesh centres + 500
--  MakeRandomSpawns jitter passes, ~19ms once per map) and then
--  never used by this hook. The author wrote the cheap version
--  first, commented it out - presumably because it spawns loot
--  anywhere on the map instead of near a player - and shipped the
--  walk instead.
--
--  WHAT THIS DOES: takes the cheap version and gives it the ONE
--  property the walk had that mattered - proximity to a player.
--  We build our own validated point cache once per map, then each
--  cycle pick a random (alive, by default) player and choose a
--  cached point within zc_lootfast_radius of them. Cost per cycle:
--  ~1500 DistToSqr calls (~0.15ms) instead of 17 world traces, and
--  ZERO validation traces because every cached point was validated
--  at build time. The visibility check is kept EXACTLY as stock so
--  loot still never materialises in someone's line of sight, and
--  the 50/50 loot-box-vs-item tail is a literal copy of the stock
--  tail so drop rates and models are unchanged.
--
--  THE CACHE (built in slices, never in one frame):
--    seed  = zb.GetMapPoints("RandomSpawns")   (free - the gamemode
--            just wrote it) + ents.FindByClass("info_*") positions
--            + navmesh area centres (underwater skipped)
--    dedup = one point per 128-unit grid cell, so dense navmesh
--            areas cannot swamp the pool
--    valid = the same two traces MakeRandomSpawns uses - down 256
--            to real ground (reject sky / **studio** / **empty** /
--            nodraw / slosh / startsolid), then a headroom trace
--            (zc_lootfast_headroom, default 64 so loot BOXES fit,
--            not just items) - run zc_lootfast_slice points per
--            0.05s tick, so the whole build is ~0.5ms/tick for
--            about two seconds instead of one 25ms stall.
--
--  SAFETY / FALLBACK:
--   * the stock function is captured and CALLED VERBATIM whenever we
--     cannot do better: cache still building, cache empty (no navmesh
--     and no info_* points), or no cached point anywhere near the
--     chosen player after two radius expansions. Loot never stops.
--   * `zc_lootfast 0` restores the stock hook live, no map change.
--   * self-healing 1s sync re-installs if the gamemode loads late or
--     a hotload ships new code (same pattern as zc_orgsched).
--   * behaviour is deliberately IDENTICAL to stock on the parts
--     players can feel: one candidate per cycle, abandon if visible
--     (zc_lootfast_retries 0), same 50/50 split, same model tables,
--     same TraceEntity guard before a box spawns.
--
--  KNOWN COUPLING: the loot-creation tail below is a copy of
--  sv_lootspawn.lua:645-709. If that file is ever updated by a
--  gamemode patch, re-check this tail or run zc_lootfast 0.
--
--  Convars (FCVAR_ARCHIVE, live):
--    zc_lootfast            1     master (0 = stock random walk)
--    zc_lootfast_radius     3000  max distance from the chosen player
--                                 (0 = whole map = the author's
--                                 original commented-out line)
--    zc_lootfast_mindist    250   never spawn closer than this
--    zc_lootfast_alive      1     prefer picking a LIVING player
--    zc_lootfast_retries    0     extra candidates to try when the
--                                 first is visible (0 = stock)
--    zc_lootfast_max        1500  cache size cap
--    zc_lootfast_slice      40    points validated per build tick
--    zc_lootfast_headroom   64    clearance required above a point
--    zc_lootfast_zoff       16    extra Z added at spawn time
--  Commands: zc_lootfast_stats, zc_lootfast_rebuild, zc_lootfast_show
--  Serverside only = hotloadable.
-- ============================================================
if not SERVER then return end

ZCLOOTFAST = ZCLOOTFAST or {}
local L = ZCLOOTFAST

L.points   = L.points or {}
L.building = false
L.stats    = L.stats or { cycles = 0, fast = 0, stock = 0, visible = 0, us = 0, peak = 0 }

local cv_on       = CreateConVar("zc_lootfast", "1", FCVAR_ARCHIVE, "Use precomputed loot spawn points instead of the 17-trace random walk", 0, 1)
local cv_radius   = CreateConVar("zc_lootfast_radius", "3000", FCVAR_ARCHIVE, "Max distance from the chosen player for a loot point (0 = anywhere on the map)", 0, 32768)
local cv_mindist  = CreateConVar("zc_lootfast_mindist", "250", FCVAR_ARCHIVE, "Minimum distance from the chosen player", 0, 8192)
local cv_alive    = CreateConVar("zc_lootfast_alive", "1", FCVAR_ARCHIVE, "Prefer a living player as the anchor for loot placement", 0, 1)
local cv_retries  = CreateConVar("zc_lootfast_retries", "0", FCVAR_ARCHIVE, "Extra candidate points to try when the first is visible to a player (0 = stock behaviour)", 0, 8)
local cv_max      = CreateConVar("zc_lootfast_max", "1500", FCVAR_ARCHIVE, "Maximum cached spawn points", 64, 8000)
local cv_slice    = CreateConVar("zc_lootfast_slice", "40", FCVAR_ARCHIVE, "Candidate points validated per build tick", 5, 400)
local cv_headroom = CreateConVar("zc_lootfast_headroom", "64", FCVAR_ARCHIVE, "Clearance required above a cached point", 16, 256)
local cv_zoff     = CreateConVar("zc_lootfast_zoff", "16", FCVAR_ARCHIVE, "Extra Z height added to a cached point when loot spawns", 0, 128)

local SysTime      = SysTime
local math_random  = math.random
local util_TraceLine = util.TraceLine
local vector_up    = vector_up

-- ------------------------------------------------------------
--  CACHE BUILD
-- ------------------------------------------------------------
local MASK_GROUND = bit.bor(MASK_SOLID, MASK_WATER)

local BAD_TEX = {
	["**studio**"] = true,
	["**empty**"] = true,
	["TOOLS/TOOLSNODRAW"] = true,
	["tools/toolsnodraw"] = true,
	["TOOLS/TOOLSSKYBOX"] = true,
	["**displacement**"] = false, -- displacements are legitimate ground
}

local trDown = { mask = MASK_GROUND }
local trUp   = { mask = MASK_SOLID, mins = vector_origin, maxs = vector_origin }

-- exactly MakeRandomSpawns' validation, plus a taller headroom check so
-- prop_physics loot boxes actually fit where we say they do
local function validate(pos, headroom)
	trDown.start  = pos + vector_up * 8
	trDown.endpos = pos - vector_up * 256
	local tr = util_TraceLine(trDown)

	if not tr.Hit then return end
	if tr.HitSky or tr.StartedSolid then return end
	if BAD_TEX[tr.HitTexture] then return end
	if tr.MatType == MAT_SLOSH then return end
	if tr.HitNormal.z < 0.7 then return end -- too steep to rest loot on

	trUp.start  = tr.HitPos
	trUp.endpos = tr.HitPos + vector_up * headroom
	local tr2 = util_TraceLine(trUp)
	if tr2.Hit or tr2.StartedSolid then return end

	return tr.HitPos + vector_up * 16
end

local function gatherCandidates()
	local seen, out = {}, {}

	local function add(v)
		if not isvector(v) then return end
		-- one point per 128-unit cell: keeps navmesh density from swamping the pool
		local key = math.floor(v.x / 128) .. "|" .. math.floor(v.y / 128) .. "|" .. math.floor(v.z / 128)
		if seen[key] then return end
		seen[key] = true
		out[#out + 1] = Vector(v)
	end

	-- 1. the gamemode's own saved jitter points (free, already ground-validated)
	local ok, pts = false, nil
	if zb and zb.GetMapPoints then ok, pts = pcall(zb.GetMapPoints, "RandomSpawns") end
	if ok and istable(pts) then
		for _, p in pairs(pts) do
			if isvector(p) then add(p)
			elseif istable(p) then
				local v = p.pos
				if isvector(v) then add(v)
				elseif istable(v) and v.x and v.y and v.z then add(Vector(v.x, v.y, v.z)) end
			end
		end
	end

	-- 2. map info_* entities
	for _, e in ipairs(ents.FindByClass("info_*")) do
		if IsValid(e) then add(e:GetPos()) end
	end

	-- 3. navmesh area centres - the best loot spots on any map that has one
	if navmesh.IsLoaded() then
		for _, a in ipairs(navmesh.GetAllNavAreas()) do
			if a and a:IsValid() and not a:IsUnderwater() then add(a:GetCenter()) end
		end
	end

	return out
end

local function build(reason)
	if L.building then return end
	L.building = true

	local t0 = SysTime()
	local cand = gatherCandidates()
	local gatherMS = (SysTime() - t0) * 1000

	-- shuffle so a partial build (cap hit) is still spread over the whole map
	for i = #cand, 2, -1 do
		local j = math_random(i)
		cand[i], cand[j] = cand[j], cand[i]
	end

	local out, idx = {}, 1
	local startedAt = SysTime()
	local validMS = 0

	timer.Remove("zc_lootfast_build")
	timer.Create("zc_lootfast_build", 0.05, 0, function()
		local slice    = cv_slice:GetInt()
		local cap      = cv_max:GetInt()
		local headroom = cv_headroom:GetFloat()
		local ts       = SysTime()

		for _ = 1, slice do
			if idx > #cand or #out >= cap then
				validMS = validMS + (SysTime() - ts) * 1000
				timer.Remove("zc_lootfast_build")
				L.points   = out
				L.building = false
				L.builtAt  = CurTime()
				L.buildMS  = gatherMS + validMS
				L.buildWall = SysTime() - startedAt
				print(string.format("[LootFast] %s: %d spawn points cached from %d candidates (%.1fms of work spread over %.1fs)",
					reason or "build", #out, #cand, L.buildMS, L.buildWall))
				return
			end

			local p = validate(cand[idx], headroom)
			idx = idx + 1
			if p then out[#out + 1] = p end
		end

		validMS = validMS + (SysTime() - ts) * 1000
	end)
end

-- ------------------------------------------------------------
--  POINT SELECTION - reservoir sample, no per-cycle allocations
-- ------------------------------------------------------------
local function pickNear(origin, minD, maxD)
	local pts = L.points
	local n = #pts
	if n == 0 then return nil end

	if maxD <= 0 then return pts[math_random(n)] end -- radius 0 = whole map

	local minSqr, maxSqr = minD * minD, maxD * maxD
	local hits, chosen = 0, nil
	for i = 1, n do
		local p = pts[i]
		local d = origin:DistToSqr(p)
		if d >= minSqr and d <= maxSqr then
			hits = hits + 1
			if math_random(hits) == 1 then chosen = p end
		end
	end
	return chosen, hits
end

local function pickAnchor()
	local plys = player.GetAll()
	if #plys == 0 then return nil end

	if cv_alive:GetBool() then
		local n, chosen = 0, nil
		for i = 1, #plys do
			local p = plys[i]
			if IsValid(p) and p:Alive() and not p:IsBot() then
				n = n + 1
				if math_random(n) == 1 then chosen = p end
			end
		end
		if chosen then return chosen end
	end

	return plys[math_random(#plys)]
end

-- ------------------------------------------------------------
--  THE LOOT TAIL - literal copy of sv_lootspawn.lua:645-709
-- ------------------------------------------------------------
local vec_dist = Vector(500, 500, 500)

local function visibleToAnyone(spawnPos)
	for _, ply in ipairs(ents.FindInBox(spawnPos - vec_dist, spawnPos + vec_dist)) do
		if not ply:IsPlayer() then continue end
		if not ply:Alive() then continue end
		local tr = util_TraceLine({
			start = spawnPos,
			endpos = ply:EyePos(),
			mask = MASK_VISIBLE
		})
		if IsValid(tr.Entity) and tr.Entity == ply then return true end
	end
	return false
end

local function placeLoot(spawnPos, curRound)
	if (math_random(2) == 1) and not curRound.noBoxes then
		local huy = ents.Create("prop_physics")
		huy:SetPos(spawnPos)

		local randprop
		for model, tbl in RandomPairs(math_random(6) == 1 and hg.props or hg.loot_boxes) do
			if not istable(tbl) or not tbl[3] then randprop = model break end
		end
		if not util.IsValidProp(randprop) then huy:Remove() return end
		huy:SetModel(randprop)

		local tr = {}
		tr.start = spawnPos
		tr.endpos = spawnPos
		tr.collisiongroup = COLLISION_GROUP_WORLD
		local trace = util.TraceEntity(tr, huy)

		if not trace.Hit then
			huy:Spawn()
		else
			huy:Remove()
		end
		return
	end

	local entName, AmmoCount = hg.GenerateLoot()
	if not entName or entName == "" then return end

	local huy = ents.Create(entName)
	if not IsValid(huy) then return end
	huy.IsSpawned = true
	huy:SetPos(spawnPos)
	huy:Spawn()
	huy.init = true

	if AmmoCount then
		huy.AmmoCount = AmmoCount
	end
end

-- ------------------------------------------------------------
--  THE REPLACEMENT HOOK
-- ------------------------------------------------------------
local function fastSpawnBoxes()
	if not zb or zb.ROUND_STATE ~= 1 then return end
	if not CurrentRound then return end
	local curRound = CurrentRound()
	if not istable(curRound) or not curRound.LootSpawn then return end

	local t0 = SysTime()
	L.stats.cycles = L.stats.cycles + 1

	local function done()
		local us = (SysTime() - t0) * 1000000
		L.stats.us = L.stats.us + us
		if us > L.stats.peak then L.stats.peak = us end
	end

	local ply = pickAnchor()
	if not IsValid(ply) then done() return end

	local zoff = vector_up * cv_zoff:GetFloat()
	local minD = cv_mindist:GetFloat()
	local maxD = cv_radius:GetFloat()

	local tries = 1 + cv_retries:GetInt()
	for attempt = 1, tries do
		local pos = pickNear(ply:GetPos(), minD, maxD)

		-- widen twice before giving up on the cache: a player alone in a
		-- corner of a big map should still get loot
		if not pos and maxD > 0 then pos = pickNear(ply:GetPos(), minD, maxD * 2) end
		if not pos and maxD > 0 then pos = pickNear(ply:GetPos(), 0, 0) end

		if not pos then
			-- cache empty or still building: hand the cycle to stock, unchanged
			L.stats.stock = L.stats.stock + 1
			if L.orig then L.orig() end
			done()
			return
		end

		local spawnPos = pos + zoff

		if not curRound.noBoxes and visibleToAnyone(spawnPos) then
			L.stats.visible = L.stats.visible + 1
			if attempt == tries then done() return end
		else
			L.stats.fast = L.stats.fast + 1
			placeLoot(spawnPos, curRound)
			done()
			return
		end
	end

	done()
end

-- ------------------------------------------------------------
--  INSTALL / REVERT (self-healing, same pattern as zc_orgsched)
-- ------------------------------------------------------------
local myClosure = function() fastSpawnBoxes() end -- fresh per file load

local function currentHook()
	local t = hook.GetTable()
	t = t and t["Boxes Think"]
	t = t and t["SpawnBoxes"]
	-- ULib stores {fn, priority} in some builds - unwrap defensively
	if istable(t) then return t.fn or t[1] end
	return t
end

local function install()
	local cur = currentHook()
	if cur == nil then return false end -- gamemode hook not registered yet
	if cur ~= L.mine then L.orig = cur end -- capture whatever genuinely runs now
	L.mine = myClosure
	hook.Add("Boxes Think", "SpawnBoxes", myClosure)
	print("[LootFast] installed - loot now placed from cached points (zc_lootfast 0 reverts)")
	if #L.points == 0 and not L.building then build("install") end
	return true
end

local function uninstall()
	if currentHook() ~= L.mine then L.mine = nil return end
	if L.orig then
		hook.Add("Boxes Think", "SpawnBoxes", L.orig)
		print("[LootFast] reverted to the stock random-walk loot placement")
	end
	L.mine = nil
end

timer.Create("zc_lootfast_sync", 1, 0, function()
	if cv_on:GetBool() then
		if currentHook() ~= L.mine or L.mine ~= myClosure then install() end
	else
		uninstall()
	end
end)

-- rebuild after the gamemode has finished writing its own RandomSpawns
-- (its addboxs hook fires at PostCleanupMap + 0.5s)
hook.Add("PostCleanupMap", "zc_lootfast_rebuild", function()
	timer.Simple(3, function()
		L.points = {}
		build("PostCleanupMap")
	end)
end)

hook.Add("InitPostEntity", "zc_lootfast_init", function()
	timer.Simple(5, function() build("InitPostEntity") end)
end)

-- hotload: the map is already running, so build right now
if game.GetMap() and #L.points == 0 then
	timer.Simple(1, function() if #L.points == 0 then build("hotload") end end)
end

-- ------------------------------------------------------------
--  COMMANDS
-- ------------------------------------------------------------
concommand.Add("zc_lootfast_stats", function(ply)
	if IsValid(ply) and not ply:IsAdmin() then return end
	local function say(s)
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, s) else print(s) end
	end

	local s = L.stats
	say("=== zc_lootfast (" .. (cv_on:GetBool() and "ACTIVE" or "OFF - stock walk") .. ") ===")
	say("cached points : " .. #L.points .. (L.building and "  [BUILDING]" or "")
		.. (L.buildMS and string.format("  (built in %.1fms of work over %.1fs)", L.buildMS, L.buildWall or 0) or ""))
	say("installed     : " .. (currentHook() == L.mine and "yes" or "NO - stock hook is live"))
	say("radius        : " .. cv_radius:GetInt() .. "  (min " .. cv_mindist:GetInt() .. ")")
	say("cycles        : " .. s.cycles .. "  | placed " .. s.fast .. "  | abandoned-visible " .. s.visible .. "  | fell back to stock " .. s.stock)
	if s.cycles > 0 then
		say(string.format("cost          : %.2fms avg, %.2fms peak   (stock measured 8.6ms)", s.us / s.cycles / 1000, s.peak / 1000))
	end
end, nil, "Admin: print loot spawn point cache stats.")

concommand.Add("zc_lootfast_rebuild", function(ply)
	if IsValid(ply) and not ply:IsAdmin() then return end
	L.points = {}
	L.building = false
	build("manual")
	local msg = "[LootFast] rebuilding point cache..."
	if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
end, nil, "Admin: rebuild the loot spawn point cache for this map.")

concommand.Add("zc_lootfast_show", function(ply)
	if IsValid(ply) and not ply:IsAdmin() then return end
	-- renders only for clients running `developer 1`
	local n = 0
	for i = 1, #L.points do
		local p = L.points[i]
		if not IsValid(ply) or p:DistToSqr(ply:GetPos()) < 4194304 then -- 2048 units
			debugoverlay.Cross(p, 8, 15, Color(255, 200, 0), true)
			n = n + 1
		end
	end
	local msg = "[LootFast] drew " .. n .. " points for 15s (needs `developer 1` clientside)"
	if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
end, nil, "Admin: draw nearby cached loot points (needs developer 1).")

print("[LootFast] loaded - replaces the 17-trace loot walk once the gamemode hook exists (1s sync)")
