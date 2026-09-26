-- Nav repair (2026-09-26 owner ask): make bots cope with badly generated
-- navmeshes. Everything here lives in memory and in data/zc_bots/nav/ --
-- the map's own .nav file is never written.
--
--   Scan      Once per map (and again only when the mesh changes), in the
--             background at a few dozen traces per tick:
--               * ladders   nav ladders become routes (foot -> top and back);
--                           A* never used them before.
--               * doors     areas either side of a door that was closed when
--                           the mesh was built get linked through it.
--               * checks    every native connection gets a standing-hull
--                           test; ones through a wall or up a ledge taller
--                           than a player can climb are dropped.
--               * gaps      unlinked areas separated by a small gap or a
--                           step are linked; short drops become one-way.
--   Humans    Every half second each human's nav area is sampled. A walk
--             from one area straight into another the mesh does not link
--             (and a hull can make) becomes a bot route after two sightings,
--             and a connection the scan dropped is restored if people walk
--             it. So maps fix themselves a little every round.
--   Memory    Links, dropped connections and the stuck-spot penalties bots
--             learn (sv_nav.lua PenalizeArea/PenalizeEdge) are saved per map
--             and reloaded, instead of relearned from zero every map load.
--   Report    zc_bots_nav_report: disconnected pockets, spawns bots cannot
--             reach, top stuck spots and dropped connections, each with a
--             setpos line to go look (and fix it in nav_edit if wanted).

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}
local D = hg.botdriver
D.navrepair = D.navrepair or {}
local NR = D.navrepair

local cv_repair = ConVarExists("zc_bots_nav_repair") and GetConVar("zc_bots_nav_repair")
	or CreateConVar("zc_bots_nav_repair", "1", FCVAR_ARCHIVE,
		"Scan the navmesh for missing/broken links (ladders, doors, gaps, walls) and remember them per map", 0, 1)
local cv_learn = ConVarExists("zc_bots_nav_learn_humans") and GetConVar("zc_bots_nav_learn_humans")
	or CreateConVar("zc_bots_nav_learn_humans", "1", FCVAR_ARCHIVE,
		"Bots learn routes the navmesh is missing from where human players actually walk", 0, 1)

local SCAN_VERSION = 1
local KIND_COST = { ladder = 150, door = 40, gap = 30, drop = 20, human = 0 }
local LINK_GAP = 24          -- max xy gap bridged by a scanned link
local LINK_MIN_SPAN = 30     -- shared edge must fit a player
local STEP = 18
local DROP_MAX = 120
local RISE_MAX = 72          -- taller than this is not a walk/step/hop
local TRACES_PER_SLICE = 60
local SLICE_INTERVAL = 0.1
local MAX_SCAN_LINKS = 6000
local HUMAN_CONFIRM = 2
local HUMAN_SAMPLE = 0.5
local SAVE_EVERY = 300
local DOOR_CLASSES = { prop_door_rotating = true, func_door = true, func_door_rotating = true }
local SPAWN_PREFIXES = { "info_player_", "gmod_player_start" }
local POINT_GROUPS = { "RandomSpawns", "HMCD_TDM_T", "HMCD_TDM_CT" }
local up = Vector(0, 0, 1)

local links, bad = D.navLinks, D.navBadEdges
NR.state = NR.state or { counts = {}, badCounts = {}, humanSeen = {} }
local S = NR.state

local function mapFile() return "zc_bots/nav/" .. game.GetMap() .. ".json" end

----------------------------------------------------------------------
-- Links
----------------------------------------------------------------------

local function linked(a, b)
	if a:IsConnected(b) then return true end
	local row = links[a:GetID()]
	return row ~= nil and row[b:GetID()] ~= nil
end

local changed = false

local function addLink(from, to, kind, entry, via)
	if not IsValid(from) or not IsValid(to) or from == to or linked(from, to) then return false end
	local f, t = from:GetID(), to:GetID()
	links[f] = links[f] or {}
	links[f][t] = { kind = kind, cost = KIND_COST[kind] or 0, entry = entry, via = via }
	S.counts[kind] = (S.counts[kind] or 0) + 1
	changed, S.dirty = true, true
	return true
end
NR.AddLink = addLink

local function markBad(f, t, reason)
	bad[f] = bad[f] or {}
	if bad[f][t] then return end
	bad[f][t] = reason
	S.badCounts[reason] = (S.badCounts[reason] or 0) + 1
	changed, S.dirty = true, true
end

local function clearBad(f, t)
	local row = bad[f]
	if not row or not row[t] then return end
	S.badCounts[row[t]] = math.max((S.badCounts[row[t]] or 1) - 1, 0)
	row[t] = nil
	if next(row) == nil then bad[f] = nil end
	changed, S.dirty = true, true
end

local function flush()
	if changed then
		changed = false
		if D.NavLinksChanged then D.NavLinksChanged() end
	end
end

----------------------------------------------------------------------
-- Walk tests
----------------------------------------------------------------------

-- Doors, physics props, breakables, people: in the way now, not for good.
local function solidFor(ent)
	if not IsValid(ent) then return true end
	if ent:IsPlayer() or ent:IsNPC() or ent:IsWeapon() then return false end
	local class = ent:GetClass()
	if DOOR_CLASSES[class] or string.find(class, "door", 1, true) then return false end
	if string.StartWith(class, "prop_physics") or class == "prop_ragdoll" or class == "func_physbox"
		or string.StartWith(class, "func_breakable") then return false end
	return true
end

local hull = { mins = Vector(-13, -13, 0), maxs = Vector(13, 13, 36), mask = MASK_PLAYERSOLID, filter = solidFor }

-- true clear, false blocked, nil started inside something (unknown).
local function walkTrace(a, b, lift)
	hull.start = a + up * lift
	hull.endpos = b + up * lift
	local tr = util.TraceHull(hull)
	if tr.StartSolid then return nil, tr end
	return not tr.Hit, tr
end

----------------------------------------------------------------------
-- Scan
----------------------------------------------------------------------

local function linkLadder(ladder)
	local okB, bottom = pcall(ladder.GetBottom, ladder)
	local okT, top = pcall(ladder.GetTop, ladder)
	local okN, normal = pcall(ladder.GetNormal, ladder)
	if not (okB and okT and okN) or not isvector(bottom) or not isvector(top) or not isvector(normal) then return end
	normal = Vector(normal.x, normal.y, 0)
	if normal:LengthSqr() < 0.01 then return end
	normal:Normalize()
	local foot = bottom + normal * 24
	local bArea = ladder.GetBottomArea and ladder:GetBottomArea()
	if not IsValid(bArea) then bArea = navmesh.GetNearestNavArea(foot, false, 96, false, true) end
	if not IsValid(bArea) then return end
	foot.z = bArea:GetZ(foot)
	for _, getter in ipairs({ "GetTopForwardArea", "GetTopLeftArea", "GetTopRightArea", "GetTopBehindArea" }) do
		local tArea = ladder[getter] and ladder[getter](ladder)
		if IsValid(tArea) and tArea ~= bArea then
			local dismount = tArea:GetClosestPointOnArea(top - normal * 32)
			local lip = tArea:GetClosestPointOnArea(top)
			if dismount and lip then
				addLink(bArea, tArea, "ladder", dismount, { foot })
				addLink(tArea, bArea, "ladder", foot, { lip })
			end
		end
	end
end

local floorTrace = { mask = MASK_PLAYERSOLID_BRUSHONLY }

local function linkDoor(door)
	local c = door:WorldSpaceCenter()
	floorTrace.start, floorTrace.endpos, floorTrace.filter = c, c - up * 128, door
	local fl = util.TraceLine(floorTrace)
	if not fl.Hit then return 1 end
	local floor = fl.HitPos
	local traces = 1
	for _, axis in ipairs({ door:GetForward(), door:GetRight() }) do
		axis = Vector(axis.x, axis.y, 0)
		if axis:LengthSqr() > 0.01 then
			axis:Normalize()
			local p1, p2 = floor + axis * 56, floor - axis * 56
			local a1 = navmesh.GetNearestNavArea(p1, false, 80, false, true)
			local a2 = navmesh.GetNearestNavArea(p2, false, 80, false, true)
			if IsValid(a1) and IsValid(a2) and a1 ~= a2 and not linked(a1, a2) then
				local q1, q2 = Vector(p1.x, p1.y, a1:GetZ(p1)), Vector(p2.x, p2.y, a2:GetZ(p2))
				if math.abs(q1.z - q2.z) <= STEP then
					traces = traces + 1
					if walkTrace(q1, q2, 20) == true then
						addLink(a1, a2, "door", q2)
						addLink(a2, a1, "door", q1)
					end
				end
			end
		end
	end
	return traces
end

-- A native connection a player cannot actually walk.
local function checkEdge(a, b)
	local pB = D.NavPortalPoint(a, b, b:GetCenter())
	local pA = D.NavPortalPoint(b, a, a:GetCenter())
	if not pA or not pB then return 0 end
	local rise = pB.z - pA.z
	if rise > RISE_MAX then
		markBad(a:GetID(), b:GetID(), "ledge")
		return 0
	end
	local clear, tr = walkTrace(pA, pB, 20 + math.max(rise, 0))
	-- Only a wall-like hit (not a stair lip / ramp) well short of the far side.
	if clear == false and tr.Fraction < 0.8 and math.abs(tr.HitNormal.z) < 0.7 then
		markBad(a:GetID(), b:GetID(), "wall")
	end
	return 1
end

local function scanGaps(a, grid, cell, spend)
	local ra = D.NavAreaRect(a)
	local ca = a:GetCenter()
	local seen = {}
	for gx = math.floor((ra.x0 - LINK_GAP) / cell), math.floor((ra.x1 + LINK_GAP) / cell) do
		for gy = math.floor((ra.y0 - LINK_GAP) / cell), math.floor((ra.y1 + LINK_GAP) / cell) do
			for _, b in ipairs(grid[gx .. ":" .. gy] or {}) do
				if b ~= a and not seen[b] and IsValid(b) then
					seen[b] = true
					local rb = D.NavAreaRect(b)
					local ox = math.min(ra.x1, rb.x1) - math.max(ra.x0, rb.x0)
					local oy = math.min(ra.y1, rb.y1) - math.max(ra.y0, rb.y0)
					local near = (ox <= 0 and ox >= -LINK_GAP and oy >= LINK_MIN_SPAN)
						or (oy <= 0 and oy >= -LINK_GAP and ox >= LINK_MIN_SPAN)
					if near and math.abs(b:GetCenter().z - ca.z) <= DROP_MAX + 64 and not linked(a, b) then
						local pB = D.NavPortalPoint(a, b, b:GetCenter())
						local pA = D.NavPortalPoint(b, a, ca)
						if pA and pB then
							local rise = pB.z - pA.z
							if math.abs(rise) <= STEP then
								spend(1)
								if walkTrace(pA, pB, 20 + math.max(rise, 0)) == true then addLink(a, b, "gap", pB) end
							elseif rise < -STEP and rise >= -DROP_MAX then
								spend(2)
								local over = Vector(pB.x, pB.y, pA.z)
								if walkTrace(pA, over, 20) == true and walkTrace(over, pB, 20) == true then
									addLink(a, b, "drop", pB)
								end
							end
						end
					end
				end
			end
		end
	end
end

local function scanJob()
	local areas = navmesh.GetAllNavAreas() or {}
	local total = #areas
	local work = 0
	local function spend(n)
		work = work + n
		if work >= TRACES_PER_SLICE then
			work = 0
			flush()
			coroutine.yield()
		end
	end
	local function linksFull()
		local n = 0
		for _, c in pairs(S.counts) do n = n + c end
		return n >= MAX_SCAN_LINKS
	end

	S.scanStage = "ladders"
	local ladders = {}
	for i, area in ipairs(areas) do
		if IsValid(area) and area.GetLadders then
			for _, ladder in ipairs(area:GetLadders() or {}) do
				local id = IsValid(ladder) and ladder:GetID()
				if id and not ladders[id] then
					ladders[id] = true
					linkLadder(ladder)
				end
			end
		end
		if i % 200 == 0 then spend(TRACES_PER_SLICE) end
	end

	S.scanStage = "doors"
	for _, ent in ipairs(ents.GetAll()) do
		if IsValid(ent) and DOOR_CLASSES[ent:GetClass()] then spend(linkDoor(ent) * 2) end
	end

	S.scanStage = "checks"
	for i, a in ipairs(areas) do
		S.scanProgress = i / math.max(total, 1)
		if IsValid(a) then
			for _, b in ipairs(a:GetAdjacentAreas() or {}) do
				if IsValid(b) then spend(checkEdge(a, b)) end
			end
		end
	end

	S.scanStage = "gaps"
	local cell = 256
	local grid = {}
	for _, a in ipairs(areas) do
		if IsValid(a) then
			local r = D.NavAreaRect(a)
			for gx = math.floor(r.x0 / cell), math.floor(r.x1 / cell) do
				for gy = math.floor(r.y0 / cell), math.floor(r.y1 / cell) do
					local k = gx .. ":" .. gy
					grid[k] = grid[k] or {}
					grid[k][#grid[k] + 1] = a
				end
			end
		end
	end
	for i, a in ipairs(areas) do
		S.scanProgress = i / math.max(total, 1)
		if linksFull() then break end
		if IsValid(a) then scanGaps(a, grid, cell, spend) end
		spend(0.2)
	end

	flush()
	S.scanStage, S.scanned, S.scanProgress = "done", true, 1
	NR.Save()
	D.log.info("nav", string.format("nav repair scan done on %s: %d areas", game.GetMap(), total))
end

local job
local function startScan()
	if job or not cv_repair:GetBool() or not navmesh.IsLoaded() then return end
	job = coroutine.create(scanJob)
	S.scanStage = "starting"
end

timer.Create("zc_bots_navrepair_job", SLICE_INTERVAL, 0, function()
	if not job then return end
	if not cv_repair:GetBool() then return end
	local ok, err = coroutine.resume(job)
	if not ok then
		D.log.error("nav", "nav repair scan failed: " .. tostring(err))
		S.scanStage = "failed"
		job = nil
	elseif coroutine.status(job) == "dead" then
		job = nil
	end
end)

----------------------------------------------------------------------
-- Learn from humans
----------------------------------------------------------------------

local tracks = setmetatable({}, { __mode = "k" })

local function twoHopLinked(a, b)
	for _, mid in ipairs(D.NavAdjacent(a)) do
		if IsValid(mid) and (mid == b or linked(mid, b)) then return true end
	end
	return false
end

D.Every("navrepair_humans", HUMAN_SAMPLE, function()
	if not cv_learn:GetBool() or not cv_repair:GetBool() or not navmesh.IsLoaded() then return end
	local now = CurTime()
	for _, ply in ipairs(player.GetHumans()) do
		if ply:Alive() and ply:IsOnGround() and ply:GetMoveType() == MOVETYPE_WALK and not ply:InVehicle() then
			local pos = ply:GetPos()
			local area = navmesh.GetNavArea(pos + up * 10, 40)
			local prev = tracks[ply]
			if IsValid(area) then
				if prev and IsValid(prev.area) and prev.area ~= area and now - prev.at <= HUMAN_SAMPLE * 1.6
					and prev.pos:DistToSqr(pos) <= 260 * 260 then
					local a, b = prev.area, area
					local f, t = a:GetID(), b:GetID()
					if a:IsConnected(b) then
						-- People walk it: whatever the scan thought, it is walkable.
						if bad[f] and bad[f][t] then clearBad(f, t) flush() end
					elseif not linked(a, b) and not twoHopLinked(a, b) then
						local rise = pos.z - prev.pos.z
						if rise <= 24 and walkTrace(prev.pos, pos, 20 + math.max(rise, 0)) ~= false then
							local k = f .. ">" .. t
							S.humanSeen[k] = (S.humanSeen[k] or 0) + 1
							S.dirty = true
							if S.humanSeen[k] >= HUMAN_CONFIRM then
								S.humanSeen[k] = nil
								addLink(a, b, "human", b:GetClosestPointOnArea(pos) or pos)
								flush()
							end
						end
					end
				end
				tracks[ply] = { area = area, pos = pos, at = now }
			else
				tracks[ply] = nil
			end
		else
			tracks[ply] = nil
		end
	end
end)

----------------------------------------------------------------------
-- Save / load (per map; discarded if the mesh changes)
----------------------------------------------------------------------

local function vec(v) return v and { math.Round(v.x, 1), math.Round(v.y, 1), math.Round(v.z, 1) } or nil end
local function unvec(t) return istable(t) and Vector(t[1], t[2], t[3]) or nil end

function NR.Save()
	if not navmesh.IsLoaded() then return end
	local out = { v = SCAN_VERSION, areas = navmesh.GetNavAreaCount(), scanned = S.scanned == true,
		links = {}, bad = {}, human = S.humanSeen, pen = {} }
	for f, row in pairs(links) do
		for t, l in pairs(row) do
			local via
			if l.via then
				via = {}
				for i, p in ipairs(l.via) do via[i] = vec(p) end
			end
			out.links[#out.links + 1] = { f, t, l.kind, vec(l.entry), via }
		end
	end
	for f, row in pairs(bad) do
		for t, reason in pairs(row) do out.bad[#out.bad + 1] = { f, t, reason } end
	end
	local threshold = D.NAV_PENALTY_THRESHOLD or 10
	for k, p in pairs(D.navPenalties or {}) do
		if p >= threshold then out.pen[k] = math.Round(p, 1) end
	end
	file.CreateDir("zc_bots/nav")
	file.Write(mapFile(), util.TableToJSON(out))
	S.dirty = false
end

function NR.Load()
	for k in pairs(links) do links[k] = nil end
	for k in pairs(bad) do bad[k] = nil end
	S.counts, S.badCounts, S.humanSeen, S.scanned = {}, {}, {}, false
	local raw = file.Read(mapFile(), "DATA")
	local tbl = raw and util.JSONToTable(raw, false, true)
	if not istable(tbl) or tbl.areas ~= navmesh.GetNavAreaCount() then
		changed = true
		flush()
		return false -- no memory for this mesh (or the mesh changed)
	end
	for _, l in ipairs(tbl.links or {}) do
		local f, t = tonumber(l[1]), tonumber(l[2])
		local from, to = f and navmesh.GetNavAreaByID(f), t and navmesh.GetNavAreaByID(t)
		if IsValid(from) and IsValid(to) then
			local via
			if istable(l[5]) then
				via = {}
				for i, p in ipairs(l[5]) do via[i] = unvec(p) end
			end
			addLink(from, to, l[3], unvec(l[4]), via)
		end
	end
	for _, b in ipairs(tbl.bad or {}) do
		local f, t = tonumber(b[1]), tonumber(b[2])
		if f and t then markBad(f, t, b[3] or "wall") end
	end
	for k, n in pairs(tbl.human or {}) do S.humanSeen[tostring(k)] = tonumber(n) end
	D.navPenalties = D.navPenalties or {}
	for k, p in pairs(tbl.pen or {}) do
		-- Relearned stuck spots come back a bit softer, so a fixed spot heals.
		D.navPenalties[tostring(k)] = math.max(D.navPenalties[tostring(k)] or 0, (tonumber(p) or 0) * 0.6)
	end
	S.scanned = tbl.scanned == true and tbl.v == SCAN_VERSION
	flush()
	S.dirty = false
	return true
end

local function boot()
	if not navmesh.IsLoaded() then return end
	job = nil
	NR.Load()
	if not S.scanned then startScan() else S.scanStage = "done (saved)" end
end

hook.Add("InitPostEntity", "zc_bots_navrepair_boot", function() timer.Simple(5, boot) end)
if navmesh.IsLoaded() and CurTime() > 10 then timer.Simple(2, boot) end -- hot reload
hook.Add("ShutDown", "zc_bots_navrepair_save", function() if navmesh.IsLoaded() then NR.Save() end end)
D.Every("navrepair_save", SAVE_EVERY, function() if navmesh.IsLoaded() then NR.Save() end end)

----------------------------------------------------------------------
-- Report
----------------------------------------------------------------------

local function setpos(v) return string.format("setpos %.0f %.0f %.0f", v.x, v.y, v.z + 8) end

local function spawnPoints()
	local pts = {}
	for _, ent in ipairs(ents.GetAll()) do
		local class = ent:GetClass()
		for _, prefix in ipairs(SPAWN_PREFIXES) do
			if string.StartWith(class, prefix) then pts[#pts + 1] = { pos = ent:GetPos(), name = class } break end
		end
	end
	if zb and isfunction(zb.GetMapPoints) then
		for _, group in ipairs(POINT_GROUPS) do
			local ok, points = pcall(zb.GetMapPoints, group)
			if ok and istable(points) then
				for _, p in ipairs(points) do
					if istable(p) and isvector(p.pos) then pts[#pts + 1] = { pos = p.pos, name = group } end
				end
			end
		end
	end
	return pts
end

concommand.Add("zc_bots_nav_report", function(ply)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	local lines = {}
	local function out(line) lines[#lines + 1] = line end
	if not navmesh.IsLoaded() then
		out("[nav report] no navmesh loaded on " .. game.GetMap())
	else
		local areas = navmesh.GetAllNavAreas() or {}
		out(string.format("[nav report] %s  areas=%d  scan=%s%s", game.GetMap(), #areas, tostring(S.scanStage),
			(S.scanStage ~= "done" and S.scanProgress) and string.format(" %.0f%%", S.scanProgress * 100) or ""))
		local kinds = {}
		for k, n in pairs(S.counts) do kinds[#kinds + 1] = k .. "=" .. n end
		out("  added links: " .. (#kinds > 0 and table.concat(kinds, " ") or "none"))
		local reasons = {}
		for k, n in pairs(S.badCounts) do reasons[#reasons + 1] = k .. "=" .. n end
		out("  dropped connections: " .. (#reasons > 0 and table.concat(reasons, " ") or "none"))
		local pending = 0
		for _ in pairs(S.humanSeen) do pending = pending + 1 end
		out("  human routes waiting for a second sighting: " .. pending)

		-- Connected pockets (links counted both ways).
		local und = {}
		for _, a in ipairs(areas) do
			if IsValid(a) then
				local id = a:GetID()
				und[id] = und[id] or {}
				for _, b in ipairs(D.NavAdjacent(a)) do
					if IsValid(b) then
						local bid = b:GetID()
						und[id][bid] = true
						und[bid] = und[bid] or {}
						und[bid][id] = true
					end
				end
			end
		end
		local comp, sizes, firstArea = {}, {}, {}
		local n = 0
		for _, a in ipairs(areas) do
			local id = IsValid(a) and a:GetID()
			if id and not comp[id] then
				n = n + 1
				local stack, size = { id }, 0
				comp[id] = n
				firstArea[n] = a
				while #stack > 0 do
					local cur = table.remove(stack)
					size = size + 1
					for nb in pairs(und[cur] or {}) do
						if not comp[nb] then comp[nb] = n stack[#stack + 1] = nb end
					end
				end
				sizes[n] = size
			end
		end
		local main = 1
		for c, size in pairs(sizes) do if size > (sizes[main] or 0) then main = c end end
		out(string.format("  pockets: %d (largest %d areas)", n, sizes[main] or 0))
		local islands = {}
		for c, size in pairs(sizes) do if c ~= main then islands[#islands + 1] = { c = c, size = size } end end
		table.sort(islands, function(x, y) return x.size > y.size end)
		for i = 1, math.min(#islands, 10) do
			out(string.format("    cut-off pocket of %d areas: %s", islands[i].size, setpos(firstArea[islands[i].c]:GetCenter())))
		end

		local offMesh, cutOff = 0, 0
		for _, sp in ipairs(spawnPoints()) do
			local area = navmesh.GetNearestNavArea(sp.pos, false, 200, false, true)
			if not IsValid(area) then
				offMesh = offMesh + 1
				if offMesh <= 5 then out("    spawn off the mesh (" .. sp.name .. "): " .. setpos(sp.pos)) end
			elseif comp[area:GetID()] ~= main then
				cutOff = cutOff + 1
				if cutOff <= 5 then out("    spawn in a cut-off pocket (" .. sp.name .. "): " .. setpos(sp.pos)) end
			end
		end
		out(string.format("  spawns off the mesh: %d, in cut-off pockets: %d", offMesh, cutOff))

		local stuck = {}
		for k, p in pairs(D.navPenalties or {}) do
			local id = tonumber(k)
			if id and p > 0 then stuck[#stuck + 1] = { id = id, p = p } end
		end
		table.sort(stuck, function(x, y) return x.p > y.p end)
		out("  top stuck spots:")
		for i = 1, math.min(#stuck, 10) do
			local area = navmesh.GetNavAreaByID(stuck[i].id)
			if IsValid(area) then out(string.format("    penalty %.0f: %s", stuck[i].p, setpos(area:GetCenter()))) end
		end
		out("  some dropped connections:")
		local shown = 0
		for f, row in pairs(bad) do
			for t, reason in pairs(row) do
				local a, b = navmesh.GetNavAreaByID(f), navmesh.GetNavAreaByID(t)
				if IsValid(a) and IsValid(b) and shown < 10 then
					shown = shown + 1
					local p = D.NavPortalPoint(a, b, b:GetCenter()) or b:GetCenter()
					out(string.format("    %s (%d -> %d): %s", reason, f, t, setpos(p)))
				end
			end
		end
	end
	for _, line in ipairs(lines) do
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
	end
	file.CreateDir("zc_bots")
	file.Write("zc_bots/nav_report_" .. game.GetMap() .. ".txt", table.concat(lines, "\n") .. "\n")
end)

-- zc_bots_nav_rescan: forget this map's scan and run it again (links learned
-- from humans and stuck-spot memory are kept).
concommand.Add("zc_bots_nav_rescan", function(ply)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	if not navmesh.IsLoaded() then return end
	for f, row in pairs(links) do
		for t, l in pairs(row) do
			if l.kind ~= "human" then row[t] = nil S.counts[l.kind] = math.max((S.counts[l.kind] or 1) - 1, 0) end
		end
		if next(row) == nil then links[f] = nil end
	end
	for k in pairs(bad) do bad[k] = nil end
	S.badCounts, S.scanned = {}, false
	changed = true
	flush()
	job = nil
	startScan()
end)
