-- Bot navigation: A* over the engine navmesh, ported from Trauma's
-- lua/homigrad/botdriver/sv_nav.lua. navmesh.* and NAV_MESH_* are stock GMod
-- engine API (not project symbols) and are used unchanged.
--
-- Cut vs Trauma: disk persistence of learned nav penalties (LoadNavLearning /
-- SaveNavLearning / the zcity_nav_learning/<map>.json file) is dropped per
-- the porting brief ("drop nav-learning persistence"). The in-memory
-- reinforcement (PenalizeArea/PenalizeEdge/HealAreaAt, decayed on a timer)
-- is kept because sv_traverse and lib.FollowPath call it; it simply starts
-- clean every map load instead of surviving a restart.

hg = hg or {}
hg.botdriver = hg.botdriver or {}

local EXPANSION_CAP = 2000
local EDGE_MARGIN = 32
-- Path smoothing (2026-09-23): the corridor A* returns is a chain of area
-- centres/edge points, which reads as wall-hugging zig-zags through doorways
-- and rooms. A bounded greedy string-pull drops any waypoint the bot can walk
-- straight past (standing hull, world+props, same floor, ground under the
-- midpoint of the shortcut). Waypoints inside narrow areas (doorways) and on
-- JUMP/CROUCH areas are always kept, and flagged in the returned meta so the
-- follower goes through the middle without lane offset or corner cutting.
local SMOOTH_MAX_TRACES = 24
local SMOOTH_MAX_DZ = 40
local NARROW_AREA_SIZE = 80
local NAV_CACHE_TTL = 30
local WORKSPACE_POOL_LIMIT = 4

local navAreaList
local navAreaListAt = 0
local centerCache = {}
local adjacencyCache = {}
local areaKeyCache = {}
local edgeKeyCache = {}
local failCache = {}

function hg.botdriver.InvalidateNavCaches()
	navAreaList = nil
	navAreaListAt = 0
	centerCache = {}
	adjacencyCache = {}
	failCache = {}
	if hg.botdriver.ResetSearch then hg.botdriver.ResetSearch() end
end

hook.Add("PostCleanupMap", "zc_bots_nav_cache_cleanup", hg.botdriver.InvalidateNavCaches)

local function allNavAreas()
	local now = CurTime()
	if navAreaList and now - navAreaListAt < NAV_CACHE_TTL
		and (not navAreaList[1] or IsValid(navAreaList[1])) then
		return navAreaList
	end
	navAreaList = navmesh.GetAllNavAreas() or {}
	navAreaListAt = now
	return navAreaList
end

local function areaCenter(area)
	local id = area:GetID()
	local cached = centerCache[id]
	if cached and cached.area == area then return cached.center end
	local center = area:GetCenter()
	centerCache[id] = { area = area, center = center }
	return center
end

local function adjacentAreas(area)
	local id = area:GetID()
	local cached = adjacencyCache[id]
	if cached and cached.area == area then return cached.areas end
	local areas = area:GetAdjacentAreas() or {}
	adjacencyCache[id] = { area = area, areas = areas }
	return areas
end

local function areaKey(id)
	local key = areaKeyCache[id]
	if key then return key end
	key = tostring(id)
	areaKeyCache[id] = key
	return key
end

local cv_pathbudget = ConVarExists("zc_bots_path_budget") and GetConVar("zc_bots_path_budget")
	or CreateConVar("zc_bots_path_budget", "2", FCVAR_ARCHIVE,
		"Max bot pathfinding searches per server tick (excess defers to the next tick)", 1, 64)

local cv_learning = ConVarExists("zc_bots_nav_learning") and GetConVar("zc_bots_nav_learning")
	or CreateConVar("zc_bots_nav_learning", "1", FCVAR_ARCHIVE, "Enable in-memory nav penalty learning", 0, 1)

hg.botdriver.navPenalties = hg.botdriver.navPenalties or {}
local PENALTY_THRESHOLD = 10
local PENALTY_MAX = 1000

local function edgeKey(fromID, toID)
	local row = edgeKeyCache[fromID]
	if not row then
		row = {}
		edgeKeyCache[fromID] = row
	end
	local key = row[toID]
	if key then return key end
	key = "e:" .. fromID .. ">" .. toID
	row[toID] = key
	return key
end

local function bumpPenalty(key, amount)
	hg.botdriver.navPenalties[key] = math.min((hg.botdriver.navPenalties[key] or 0) + amount, PENALTY_MAX)
end

-- `amount` (added for sv_traverse.lua/sv_doors.lua's stuck/impassable-door
-- recovery): an escalated stuck or a confirmed-impassable door can bump the
-- penalty straight past PENALTY_THRESHOLD in one call instead of waiting on
-- repeated single-point bumps, so a route actually reroutes around a known
-- bad connection soon after the SECOND time it fails, not the tenth.
function hg.botdriver.PenalizeArea(areaID, amount)
	if not cv_learning:GetBool() or not areaID then return end
	bumpPenalty(areaKey(areaID), amount or 1)
end

function hg.botdriver.PenalizeEdge(fromID, toID, amount)
	if not cv_learning:GetBool() or not fromID or not toID then return end
	bumpPenalty(edgeKey(fromID, toID), amount or 1)
end

local function healKey(key, amount)
	local current = hg.botdriver.navPenalties[key]
	if not current or current <= 0 then return end
	current = current - amount
	if current <= 0 then hg.botdriver.navPenalties[key] = nil else hg.botdriver.navPenalties[key] = current end
end

function hg.botdriver.HealAreaAt(pos)
	if not cv_learning:GetBool() or not navmesh.IsLoaded() then return end
	local area = navmesh.GetNearestNavArea(pos)
	if not IsValid(area) then return end
	healKey(areaKey(area:GetID()), 0.05)
end

hg.botdriver.Every("nav_decay", 60, function()
	if not cv_learning:GetBool() then return end
	for key in pairs(hg.botdriver.navPenalties) do healKey(key, 0.2) end
end)

local budgetKey = -1
local budgetUsed = 0

local function refreshBudget()
	local t = CurTime()
	if t ~= budgetKey then
		budgetKey = t
		budgetUsed = 0
	end
end

function hg.botdriver.CanPath()
	refreshBudget()
	return budgetUsed < cv_pathbudget:GetInt()
end

function hg.botdriver.NotePath()
	refreshBudget()
	budgetUsed = budgetUsed + 1
end

local function insetFromEdge(area, point, margin)
	local center = areaCenter(area)
	local toCenter = center - point
	toCenter.z = 0
	local d = toCenter:Length()
	if d <= margin then return center end
	toCenter:Div(d)
	return point + toCenter * margin
end

local function heapSwap(heap, i, j)
	heap[i], heap[j] = heap[j], heap[i]
	heap[i].hi = i
	heap[j].hi = j
end

local function heapSiftUp(heap, i)
	while i > 1 do
		local p = math.floor(i * 0.5)
		if heap[p].f <= heap[i].f then break end
		heapSwap(heap, i, p)
		i = p
	end
end

local function heapSiftDown(heap, i)
	local n = #heap
	while true do
		local l, r, smallest = i + i, i + i + 1, i
		if l <= n and heap[l].f < heap[smallest].f then smallest = l end
		if r <= n and heap[r].f < heap[smallest].f then smallest = r end
		if smallest == i then break end
		heapSwap(heap, i, smallest)
		i = smallest
	end
end

local function heapPush(heap, node)
	local n = #heap + 1
	heap[n] = node
	node.hi = n
	heapSiftUp(heap, n)
end

local function heapPop(heap)
	local n = #heap
	local top = heap[1]
	heap[1] = heap[n]
	heap[n] = nil
	if n > 1 then
		heap[1].hi = 1
		heapSiftDown(heap, 1)
	end
	top.hi = nil
	return top
end

local workspacePool = {}

local function acquireWorkspace()
	local workspace = workspacePool[#workspacePool]
	if workspace then
		workspacePool[#workspacePool] = nil
	else
		workspace = { heap = {}, nodes = {}, closed = {}, corridor = {}, generation = 0 }
	end
	workspace.generation = workspace.generation + 1
	if workspace.generation >= 2000000000 then
		workspace.nodes = {}
		workspace.closed = {}
		workspace.generation = 1
	end
	return workspace
end

local function releaseWorkspace(workspace)
	local heap = workspace.heap
	for index = #heap, 1, -1 do
		local node = heap[index]
		if node then node.hi = nil end
		heap[index] = nil
	end
	local corridor = workspace.corridor
	for index = #corridor, 1, -1 do corridor[index] = nil end
	if #workspacePool < WORKSPACE_POOL_LIMIT then
		workspacePool[#workspacePool + 1] = workspace
	end
end

local function workspaceNode(workspace, area, id)
	local node = workspace.nodes[id]
	if not node then
		node = {}
		workspace.nodes[id] = node
	end
	if node.generation ~= workspace.generation then
		node.generation = workspace.generation
		node.area = area
		node.id = id
		node.g = math.huge
		node.f = math.huge
		node.parent = nil
		node.hi = nil
	end
	return node
end

local function resolveArea(pos)
	local area = navmesh.GetNearestNavArea(pos, false, 1200, true, true)
	if IsValid(area) then return area end
	return navmesh.GetNearestNavArea(pos, false, 600, true, false)
end

local FAIL_TTL = 3

local function failedUntilFor(startID, goalID)
	local row = failCache[startID]
	local record = row and row[goalID]
	return record and record.untilTime, record and record.status
end

local function clearFailedPair(startID, goalID)
	local row = failCache[startID]
	if not row then return end
	row[goalID] = nil
	if next(row) == nil then failCache[startID] = nil end
end

local function markFailedPair(startID, goalID, untilTime, status)
	local row = failCache[startID]
	if not row then
		row = {}
		failCache[startID] = row
	end
	row[goalID] = { untilTime = untilTime, status = status or "no-route" }
end

hg.botdriver.Every("nav_failcache_cleanup", 30, function()
	local now = CurTime()
	for startID, row in pairs(failCache) do
		for goalID, record in pairs(row) do
			if record.untilTime <= now then row[goalID] = nil end
		end
		if next(row) == nil then failCache[startID] = nil end
	end
end)

local sameAreaTrace = { mins = Vector(-14, -14, 0), maxs = Vector(14, 14, 36), mask = MASK_PLAYERSOLID_BRUSHONLY }

local function areaBlocked(area, startArea, goalArea, time, learningEnabled)
	local id = area:GetID()
	if area ~= startArea and area.IsBlocked and area:IsBlocked(-2, false) then return true end
	if learningEnabled then
		local penalty = hg.botdriver.navPenalties[areaKey(id)]
		if penalty and penalty >= PENALTY_THRESHOLD then
			return area ~= startArea and area ~= goalArea
		end
	end
	return false
end

local warnedNoNavmesh = false

local smoothTrace = { mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 72), mask = MASK_PLAYERSOLID }
local smoothGround = { mask = MASK_PLAYERSOLID }
local function smoothFilter(ent)
	if not IsValid(ent) then return false end
	if ent:IsPlayer() or ent:IsWeapon() then return false end
	if ent.IsNPC and ent:IsNPC() then return false end
	if ent.IsNextBot and ent:IsNextBot() then return false end
	if ent.IsRagdoll and ent:IsRagdoll() then return false end
	return true
end
smoothTrace.filter = smoothFilter
smoothGround.filter = smoothFilter

local function areaIsNarrow(area)
	if not IsValid(area) or not area.GetSizeX then return false end
	return math.min(area:GetSizeX(), area:GetSizeY()) < NARROW_AREA_SIZE
end

local function areaNeedsWaypoint(area)
	if not IsValid(area) then return true end
	if areaIsNarrow(area) then return true end
	if area.HasAttributes and (area:HasAttributes(NAV_MESH_CROUCH or 1) or area:HasAttributes(NAV_MESH_JUMP or 2)) then return true end
	return false
end

-- Can a standing player walk the straight segment a->b: hull clear and
-- ground under the midpoint (a corner cut must not cross a pit).
local function shortcutWalkable(a, b)
	if math.abs(a.z - b.z) > SMOOTH_MAX_DZ then return false end
	smoothTrace.start = a + vector_up * 2
	smoothTrace.endpos = b + vector_up * 2
	local tr = util.TraceHull(smoothTrace)
	if tr.Hit or tr.StartSolid then return false end
	local mid = (a + b) * 0.5
	smoothGround.start = mid + vector_up * 18
	smoothGround.endpos = mid - vector_up * 30
	return util.TraceLine(smoothGround).Hit
end

-- points[i] is the waypoint that enters corridor[i+1]; points[#points] is
-- the goal. Returns the smoothed points plus meta { path, narrow, areaIndex }.
local function smoothCorridor(fromPos, points, corridor, corridorCount)
	local out, narrow, areaIndex = {}, {}, {}
	local traces = 0
	local anchor = fromPos
	local n = #points
	local index = 1
	while index <= n do
		local keep = true
		if index < n and traces < SMOOTH_MAX_TRACES then
			local area = corridor[index + 1]
			if not areaNeedsWaypoint(area) then
				traces = traces + 2
				if shortcutWalkable(anchor, points[index + 1]) then keep = false end
			end
		end
		local area = corridor[index + 1]
		if keep then
			out[#out + 1] = points[index]
			anchor = points[index]
			narrow[#out] = areaIsNarrow(area) or nil
			if IsValid(area) then areaIndex[area:GetID()] = #out end
		elseif IsValid(area) then
			-- The dropped waypoint's area is passed while travelling to the
			-- next kept point: give it that index for reservation release.
			areaIndex[area:GetID()] = #out + 1
		end
		index = index + 1
	end
	if IsValid(corridor[1]) then
		local firstID = corridor[1]:GetID()
		areaIndex[firstID] = areaIndex[firstID] or 1
	end
	return out, { path = out, narrow = narrow, areaIndex = areaIndex, smoothedFrom = n }
end

local function findPathInner(fromPos, toPos, excluded, withAreas)
	if not navmesh.IsLoaded() then
		if not warnedNoNavmesh then
			warnedNoNavmesh = true
			hg.botdriver.log.warn("nav", "no navmesh on " .. game.GetMap() .. "; bots cannot path and will idle")
		end
		return nil, "no-navmesh", 0
	end

	local startArea = resolveArea(fromPos)
	local goalArea = resolveArea(toPos)
	if not IsValid(startArea) or not IsValid(goalArea) then return nil, "off-mesh", 0 end

	local startID = startArea:GetID()
	local goalID = goalArea:GetID()
	if excluded and excluded[goalID] then return nil, "reserved", 0 end
	local time = CurTime()
	local failedUntil, failedStatus = failedUntilFor(startID, goalID)
	if failedUntil and not excluded then
		if failedUntil > time then return nil, failedStatus, 0 end
		clearFailedPair(startID, goalID)
	end

	local learningEnabled = cv_learning:GetBool()
	if startArea == goalArea then
		sameAreaTrace.start = fromPos + vector_up * 18
		sameAreaTrace.endpos = toPos + vector_up * 18
		local tr = util.TraceHull(sameAreaTrace)
		if tr.Hit then
			return { insetFromEdge(startArea, areaCenter(startArea), EDGE_MARGIN), toPos }, "success", 0, withAreas and { startID } or nil
		end
		return { toPos }, "success", 0, withAreas and { startID } or nil
	end

	hg.botdriver.NotePath()
	local workspace = acquireWorkspace()
	local heap = workspace.heap
	local closed = workspace.closed
	local generation = workspace.generation
	local goalCenter = areaCenter(goalArea)

	local startNode = workspaceNode(workspace, startArea, startID)
	startNode.g = 0
	startNode.f = areaCenter(startArea):Distance(goalCenter)
	startNode.parent = nil
	heapPush(heap, startNode)

	local expansions = 0
	while #heap > 0 do
		expansions = expansions + 1
		if expansions > EXPANSION_CAP then
			if not excluded then markFailedPair(startID, goalID, CurTime() + FAIL_TTL, "budget") end
			releaseWorkspace(workspace)
			return nil, "budget", expansions
		end

		local node = heapPop(heap)
		local area = node.area
		if area == goalArea then
			local corridor = workspace.corridor
			local corridorCount = 0
			local walk = node
			while walk do
				corridorCount = corridorCount + 1
				corridor[corridorCount] = walk.area
				walk = walk.parent
			end
			for left = 1, math.floor(corridorCount * 0.5) do
				local right = corridorCount - left + 1
				corridor[left], corridor[right] = corridor[right], corridor[left]
			end

			local points = {}
			for index = 2, corridorCount do
				points[#points + 1] = areaCenter(corridor[index])
			end
			points[#points + 1] = toPos
			for index = 1, #points - 1 do
				local hopArea = corridor[index + 1]
				local refined = hopArea:GetClosestPointOnArea(points[index + 1]) or points[index]
				points[index] = insetFromEdge(hopArea, refined, EDGE_MARGIN)
			end

			local areaIDs
			if withAreas then
				areaIDs = {}
				for index = 1, corridorCount do areaIDs[index] = corridor[index]:GetID() end
			end
			local smoothed, meta = smoothCorridor(fromPos, points, corridor, corridorCount)
			releaseWorkspace(workspace)
			return smoothed, "success", expansions, areaIDs, meta
		end

		closed[node.id] = generation
		local fromCenter = areaCenter(area)
		for _, adjacent in ipairs(adjacentAreas(area)) do
			if IsValid(adjacent) then
				local adjacentID = adjacent:GetID()
				local edgePenalty = learningEnabled and hg.botdriver.navPenalties[edgeKey(node.id, adjacentID)] or nil
				local hardBlockedEdge = edgePenalty and edgePenalty >= PENALTY_THRESHOLD and adjacent ~= goalArea
				if not hardBlockedEdge and closed[adjacentID] ~= generation
					and not (excluded and excluded[adjacentID])
					and not areaBlocked(adjacent, startArea, goalArea, time, learningEnabled) then
					local adjacentCenter = areaCenter(adjacent)
					local g = node.g + fromCenter:Distance(adjacentCenter)
					if adjacent.HasAttributes then
						if adjacent:HasAttributes(NAV_MESH_CROUCH or 1) then g = g + 60 end
						if adjacent:HasAttributes(NAV_MESH_JUMP or 2) then g = g + 90 end
						if adjacent:HasAttributes(NAV_MESH_AVOID or 128) then g = g + 500 end
					end
					if adjacent.IsDamaging and adjacent:IsDamaging() then g = g + 1000 end
					if learningEnabled then
						local penalty = hg.botdriver.navPenalties[areaKey(adjacentID)]
						if penalty and penalty > 0 then g = g + penalty * 100 end
						if edgePenalty and edgePenalty > 0 then g = g + edgePenalty * 100 end
					end

					local seen = workspaceNode(workspace, adjacent, adjacentID)
					if g < seen.g then
						seen.g = g
						seen.f = g + adjacentCenter:Distance(goalCenter)
						seen.parent = node
						if seen.hi then heapSiftUp(heap, seen.hi) else heapPush(heap, seen) end
					end
				end
			end
		end
	end

	if not excluded then markFailedPair(startID, goalID, CurTime() + FAIL_TTL) end
	releaseWorkspace(workspace)
	return nil, excluded and "reserved" or "no-route", expansions
end

function hg.botdriver.FindPath(fromPos, toPos, excluded, withAreas)
	return findPathInner(fromPos, toPos, excluded, withAreas)
end

function hg.botdriver.RandomRoamPos(fromPos, maxDist)
	if not navmesh.IsLoaded() then return nil end
	maxDist = maxDist or 3000

	local startArea = resolveArea(fromPos)
	local minTravel = math.min(500, maxDist * 0.35)
	local nonTerminalCount, distantCount, fallbackCount = 0, 0, 0

	for _, area in ipairs(allNavAreas()) do
		if IsValid(area) and area ~= startArea and not area:IsUnderwater()
			and (not area.IsBlocked or not area:IsBlocked(-2, false)) then
			local distance = areaCenter(area):Distance(fromPos)
			if distance <= maxDist then
				fallbackCount = fallbackCount + 1
				if distance >= minTravel then
					distantCount = distantCount + 1
					local exits = 0
					for _, adjacent in ipairs(adjacentAreas(area)) do
						if IsValid(adjacent) then exits = exits + 1 end
					end
					if exits > 1 then nonTerminalCount = nonTerminalCount + 1 end
				end
			end
		end
	end

	local category, count
	if nonTerminalCount > 0 then
		category, count = "nonterminal", nonTerminalCount
	elseif distantCount > 0 then
		category, count = "distant", distantCount
	elseif fallbackCount > 0 then
		category, count = "fallback", fallbackCount
	else
		local center = IsValid(startArea) and areaCenter(startArea) or nil
		return center and Vector(center.x, center.y, center.z) or nil
	end

	local wanted = math.random(count)
	local seen = 0
	for _, area in ipairs(allNavAreas()) do
		if IsValid(area) and area ~= startArea and not area:IsUnderwater()
			and (not area.IsBlocked or not area:IsBlocked(-2, false)) then
			local center = areaCenter(area)
			local distance = center:Distance(fromPos)
			local match = distance <= maxDist
			if match and category ~= "fallback" then match = distance >= minTravel end
			if match and category == "nonterminal" then
				local exits = 0
				for _, adjacent in ipairs(adjacentAreas(area)) do
					if IsValid(adjacent) then exits = exits + 1 end
				end
				match = exits > 1
			end
			if match then
				seen = seen + 1
				if seen == wanted then return Vector(center.x, center.y, center.z) end
			end
		end
	end

	return nil
end

----------------------------------------------------------------------
-- Coverage search. This records physical visits, not "enemy-free rooms".
-- Friendly team modes share coverage/reservations; FFA and ambiguous-team
-- modes keep private memory. No enemy/player locations enter this planner.
----------------------------------------------------------------------
local searchBoards, searchBots = {}, setmetatable({}, { __mode = "k" })
local searchMode
local searchTick, searchWork = -1, 0
local SEARCH_SLICE, SEARCH_TICK_BUDGET = 48, 128
local SEARCH_LEASE, SEARCH_REVISIT = 2.5, 45

function hg.botdriver.UsesSharedSearch()
	local key = zb and (zb.CROUND_MAIN or zb.CROUND)
	return not hg.botdriver.IsFFA() and hg.botdriver.SquadPushModes and hg.botdriver.SquadPushModes[key] == true
end

local function releaseSearch(bot, state)
	if not state then return end
	for _, id in ipairs(state.reserved or {}) do
		local claim = state.board.claims[id]
		if claim and claim.bot == bot then state.board.claims[id] = nil end
	end
	state.reserved, state.path, state.goal, state.job = nil, nil, nil, nil
end

local function resetSearch()
	for bot, state in pairs(searchBots) do
		local brain = hg.botdriver.brains and hg.botdriver.brains[bot]
		if brain and state.path and brain.path == state.path then
			brain.path, brain.roamPath, brain.roamGoal = nil, nil, nil
		end
	end
	searchBoards, searchBots = {}, setmetatable({}, { __mode = "k" })
	searchMode = zb and (zb.CROUND_MAIN or zb.CROUND)
end
hg.botdriver.ResetSearch = resetSearch
hook.Add("ZB_PreRoundStart", "zc_bots_search_round", resetSearch)
hook.Add("ZB_EndRound", "zc_bots_search_end", resetSearch)
hook.Add("PostCleanupMap", "zc_bots_search_cleanup", resetSearch)
local function forgetSearcher(bot)
	releaseSearch(bot, searchBots[bot])
	searchBots[bot], searchBoards[bot] = nil, nil
end
hook.Add("PlayerDeath", "zc_bots_search_death", forgetSearcher)
hook.Add("PlayerSpawn", "zc_bots_search_spawn", forgetSearcher)
hook.Add("PlayerDisconnected", "zc_bots_search_leave", forgetSearcher)

local function searchState(bot)
	local mode = zb and (zb.CROUND_MAIN or zb.CROUND)
	if searchMode ~= mode then resetSearch() end
	local key = hg.botdriver.UsesSharedSearch() and ("team:" .. tostring(hg.botdriver.TeamOf(bot))) or bot
	local state = searchBots[bot]
	if state and state.key ~= key then releaseSearch(bot, state) state = nil end
	if not state then
		local board = searchBoards[key] or { visits = {}, claims = {} }
		searchBoards[key] = board
		state = { key = key, board = board, failed = {} }
		searchBots[bot] = state
	end
	return state
end

local function observeSearch(bot, state, now)
	local pos = bot:GetPos()
	local area = resolveArea(pos)
	if not IsValid(area) then return nil end
	-- Nearest-area projection can land across a wall or on another floor.
	-- Only count actual occupancy, never a waypoint or a distant projection.
	local point = area:GetClosestPointOnArea(pos)
	if not isvector(point) then return nil end
	local offset = point - pos
	if math.abs(offset.z) > 32 or offset.x * offset.x + offset.y * offset.y > 4 then return nil end
	local id = area:GetID()
	if state.lastArea ~= id then
		state.previousArea, state.lastArea = state.lastArea, id
	end
	-- Entering the edge of a large room is not a sweep of that area. Reach
	-- its representative interior point before retiring it from the frontier.
	if areaCenter(area):DistToSqr(pos) <= 160 * 160 then state.board.visits[id] = now end
	return area
end

function hg.botdriver.SearchVisited(bot, pos)
	if not navmesh.IsLoaded() then return false end
	local state = searchState(bot)
	observeSearch(bot, state, CurTime())
	local area = resolveArea(pos)
	return IsValid(area) and state.board.visits[area:GetID()] ~= nil
end

hg.botdriver.Every("search_observe", 0.5, function()
	if not hg.botdriver.Enabled() or not navmesh.IsLoaded() or not hg.botdriver.RoundAllowsCombat() then return end
	for _, bot in ipairs(player.GetBots()) do
		if bot.zcBot and bot:Alive() and not bot.zcBotBenched and not hg.botdriver.IsDowned(bot) then
			observeSearch(bot, searchState(bot), CurTime())
		end
	end
end)

local function claimedByOther(state, bot, id, now)
	local claim = state.board.claims[id]
	if not claim then return false end
	if claim.untilTime <= now or not IsValid(claim.bot) or not claim.bot:Alive() then
		state.board.claims[id] = nil
		return false
	end
	return claim.bot ~= bot
end

local function searchPassable(from, area, now)
	if not IsValid(area) or area:IsUnderwater() or (area.IsDamaging and area:IsDamaging()) then return false end
	if area.IsBlocked and area:IsBlocked(-2, false) then return false end
	if cv_learning:GetBool() then
		if (hg.botdriver.navPenalties[areaKey(area:GetID())] or 0) >= PENALTY_THRESHOLD then return false end
		if (hg.botdriver.navPenalties[edgeKey(from:GetID(), area:GetID())] or 0) >= PENALTY_THRESHOLD then return false end
	end
	return true
end

function hg.botdriver.SearchStep(bot, brain, now)
	if not navmesh.IsLoaded() then return false end -- retain no-nav fallback
	local state = searchState(bot)
	local area = observeSearch(bot, state, now)
	if not area then return true end
	if state.path then
		local visited = state.goal and state.board.visits[state.goal:GetID()]
		-- Give passed corridor segments back immediately, rather than keeping
		-- the whole route reserved until its distant endpoint is reached.
		if brain.path == state.path then
			for i = #(state.reserved or {}), 1, -1 do
				local id = state.reserved[i]
				if id ~= state.goal:GetID() and (state.areaOrder[id] or math.huge) <= (brain.pathIdx or 1) then
					local claim = state.board.claims[id]
					if claim and claim.bot == bot then state.board.claims[id] = nil end
					table.remove(state.reserved, i)
				end
			end
		end
		local reclaimed = false
		for _, id in ipairs(state.reserved or {}) do
			if claimedByOther(state, bot, id, now) then reclaimed = true break end
		end
		if brain.path == state.path and state.goal and visited == state.goalVisitAt
			and now < (state.routeUntil or 0) and not reclaimed then
			for _, id in ipairs(state.reserved or {}) do
				state.board.claims[id] = { bot = bot, untilTime = now + SEARCH_LEASE }
			end
			return true
		end
		local reached = visited ~= state.goalVisitAt
		if not reached and state.goal and (now >= (state.routeUntil or 0) or (brain.path == nil and brain.nextRepath == 0)) then
			state.failed[state.goal:GetID()] = now + 12
		end
		if brain.path == state.path then
			brain.path, brain.roamPath, brain.roamGoal = nil, nil, nil
			brain.forward, brain.side = 0, 0
		end
		releaseSearch(bot, state)
	end
	-- Search now owns the idle decision; a discarded combat/formation route
	-- must not keep driving movement while a new search job is budget-deferred.
	brain.path, brain.roamPath, brain.roamGoal = nil, nil, nil
	brain.forward, brain.side = 0, 0
	if now < (state.retryAt or 0) then return true end
	local startID = area:GetID()
	if not state.job or state.job.startID ~= startID then
		local node = {area = area, g = 0, f = 0}
		state.job = { startID = startID, heap = {}, nodes = {[startID] = node}, closed = {} }
		heapPush(state.job.heap, node)
	end
	local job = state.job
	if searchTick ~= now then searchTick, searchWork = now, 0 end
	local used = 0
	while #job.heap > 0 and used < SEARCH_SLICE and searchWork < SEARCH_TICK_BUDGET and not job.goal do
		local node = heapPop(job.heap)
		local current = node.area
		used, searchWork = used + 1, searchWork + 1
		local id = current:GetID()
		job.closed[id] = true
		local reserved = claimedByOther(state, bot, id, now)
		if reserved then job.reserved = true end
		local visited = state.board.visits[id]
		if (id ~= startID or not visited) and not reserved and now >= (state.failed[id] or 0) then
			if not visited then job.goal, job.goalSeen = current, nil break end
			if now - visited >= SEARCH_REVISIT and (not job.oldestTime or visited < job.oldestTime) then
				job.oldest, job.oldestTime = current, visited
			end
		end
		-- Reservations block expansion down an occupied branch, not just its
		-- endpoint. This prevents a second bot selecting the next tile behind it.
		if not reserved then
			for _, nextArea in ipairs(adjacentAreas(current)) do
				local nextID = IsValid(nextArea) and nextArea:GetID()
				if nextID and searchPassable(current, nextArea, now) and not job.closed[nextID] then
					-- Dijkstra by travel distance, not nav-area count: one huge
					-- polygon must not beat a nearby branch made of smaller tiles.
					local cost = node.g + areaCenter(current):Distance(areaCenter(nextArea))
					if state.board.visits[nextID] then cost = cost + 40 end
					if id == startID and nextID == state.previousArea then cost = cost + 80 end
					local nextNode = job.nodes[nextID] or {area = nextArea, g = math.huge}
					job.nodes[nextID] = nextNode
					if cost < nextNode.g then
						nextNode.g, nextNode.f = cost, cost + (nextID % 997) * 0.0001
						if nextNode.hi then heapSiftUp(job.heap, nextNode.hi) else heapPush(job.heap, nextNode) end
					end
				end
			end
		end
	end
	if not job.goal and #job.heap > 0 then return true end -- resume next decision
	if not job.goal and not job.reserved then job.goal, job.goalSeen = job.oldest, job.oldestTime end
	if not job.goal then state.job = nil state.retryAt = now + 0.75 return true end
	local goal = job.goal
	if state.board.visits[goal:GetID()] ~= job.goalSeen then state.job = nil return true end
	if claimedByOther(state, bot, goal:GetID(), now) then state.job = nil return true end
	if not hg.botdriver.CanPath() then return true end -- budget exhaustion is not a failed route
	local excluded
	for id in pairs(state.board.claims) do
		if id ~= startID and claimedByOther(state, bot, id, now) then
			excluded = excluded or {}
			excluded[id] = true
		end
	end
	local path, status, _, routeAreas, pathMeta = hg.botdriver.FindPath(bot:GetPos(), areaCenter(goal), excluded, true)
	if not path then
		if status ~= "reserved" then state.failed[goal:GetID()] = now + (status == "budget" and 1 or 20) end
		state.job = nil
		state.retryAt = now + 0.2
		return true
	end
	state.goal, state.path, state.job = goal, path, nil
	state.goalVisitAt = state.board.visits[goal:GetID()]
	local length, prev = 0, bot:GetPos()
	for _, point in ipairs(path) do length = length + point:Distance(prev) prev = point end
	state.routeUntil = now + math.Clamp(length / 180 + 8, 12, 90)
	state.reserved = {}
	state.areaOrder = {}
	-- Reserve the corridor A* actually selected, not the search discovery tree.
	for index, id in ipairs(routeAreas or { goal:GetID() }) do
		state.areaOrder[id] = (pathMeta and pathMeta.areaIndex and pathMeta.areaIndex[id]) or index
		if id ~= startID or id == goal:GetID() then
			state.reserved[#state.reserved + 1] = id
			state.board.claims[id] = { bot = bot, untilTime = now + SEARCH_LEASE }
		end
	end
	brain.path, brain.pathIdx, brain.pathGoal = path, 1, areaCenter(goal)
	brain.pathMeta = pathMeta
	brain.roamPath, brain.roamGoal = path, areaCenter(goal)
	brain.roamJog = (brain.personality and brain.personality.aggression or 0.5) > 0.6
	brain.roamPauseUntil = nil
	return true
end

-- Read-only diagnostics for later live validation; no new console/net input.
function hg.botdriver.SearchStatus(bot)
	local state = searchBots[bot]
	if not state then return { active = false } end
	local visited = 0
	for _ in pairs(state.board.visits) do visited = visited + 1 end
	return { active = state.path ~= nil, visited = visited,
		reserved = #(state.reserved or {}),
		goal = IsValid(state.goal) and state.goal:GetID() or nil,
		reason = state.path and (state.goalVisitAt and "stale-patrol" or "frontier") or "planning-or-waiting",
		workThisTick = searchWork, routeUntil = state.routeUntil, retryAt = state.retryAt }
end
