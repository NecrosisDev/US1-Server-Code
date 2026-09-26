-- In-body ballistics v2: shadow logger (server-only, sv_ prefix). Runs beside v1 while
-- hg_ballistics_v2 is 1 -- appends one JSON line per bullet/buckshot hit comparing v1's
-- outcome against v2's, self-disables if v2 ever gets expensive, and reports aggregates
-- through the hg_ballistics_v2_stats console command. Never calls an organ function,
-- never touches dmgInfo, never fires a bullet -- sv_input.lua's onBox callback (live mode
-- only) is the only thing in this feature that does that.
hg = hg or {}
hg.organism = hg.organism or {}
hg.organism.BallisticsV2 = hg.organism.BallisticsV2 or {}
local V2 = hg.organism.BallisticsV2
V2.Shadow = V2.Shadow or {}
local Shadow = V2.Shadow

local DIR = "zc_ballistics_v2"
local FILE_NAME = DIR .. "/shadow.jsonl"
local FILE_PREV = DIR .. "/shadow_prev.jsonl"
local ROTATE_SIZE = 5 * 1024 * 1024 -- 5 MB
local FLUSH_EVERY = 20
local SIZE_CHECK_EVERY = 200
local BUDGET_WINDOW = 200
local BUDGET_AVG_MS = 0.5
local BUDGET_SINGLE_MS = 2

Shadow.disabledReason = Shadow.disabledReason or nil
Shadow.handle = Shadow.handle or nil
Shadow.rows = Shadow.rows or 0
Shadow.errors = Shadow.errors or 0
Shadow.lastError = Shadow.lastError or nil
Shadow.rowsSinceFlush = Shadow.rowsSinceFlush or 0
Shadow.rowsSinceSizeCheck = Shadow.rowsSinceSizeCheck or 0
Shadow.costWindow = Shadow.costWindow or {}
Shadow.costWindowN = Shadow.costWindowN or 0
Shadow.costWindowHead = Shadow.costWindowHead or 1
Shadow.costAvgUs = Shadow.costAvgUs or 0
Shadow.costMaxUs = Shadow.costMaxUs or 0

-- per-map aggregates, keyed by ammo type
Shadow.stats = Shadow.stats or {
	agreeOrgans = 0,
	agreeTotal = 0,
	deflections = 0,
	byAmmo = {}, -- [ammo] = {lodges=0, v1exits=0, v2exits=0, shots=0, fragments=0, retained=0}
}

local function ammoRow(ammo)
	local t = Shadow.stats.byAmmo[ammo]
	if not t then
		t = {lodges = 0, v1exits = 0, v2exits = 0, shots = 0, fragments = 0, retained = 0}
		Shadow.stats.byAmmo[ammo] = t
	end
	return t
end

local function openHandle()
	if Shadow.handle then return Shadow.handle end
	file.CreateDir(DIR)
	local h = file.Open(FILE_NAME, "ab", "DATA")
	Shadow.handle = h
	return h
end

function Shadow.Flush()
	if not Shadow.handle then return end
	Shadow.handle:Flush()
	Shadow.rowsSinceFlush = 0
end

local function rotateIfNeeded()
	Shadow.rowsSinceSizeCheck = Shadow.rowsSinceSizeCheck + 1
	if Shadow.rowsSinceSizeCheck < SIZE_CHECK_EVERY then return end
	Shadow.rowsSinceSizeCheck = 0
	local sz = file.Size(FILE_NAME, "DATA")
	if not sz or sz <= ROTATE_SIZE then return end
	if Shadow.handle then
		Shadow.handle:Close()
		Shadow.handle = nil
	end
	if file.Exists(FILE_PREV, "DATA") then file.Delete(FILE_PREV) end
	file.Rename(FILE_NAME, FILE_PREV)
	openHandle()
end

-- Auto-disable guard. Cost is measured by the caller (sv_input.lua) around V2.Trace only.
function Shadow.Budget()
	if Shadow.disabledReason then return false end
	return true
end

local function recordCost(costMs)
	local costUs = costMs * 1000
	local win, n, head = Shadow.costWindow, Shadow.costWindowN, Shadow.costWindowHead
	win[head] = costUs
	Shadow.costWindowHead = (head % BUDGET_WINDOW) + 1
	if n < BUDGET_WINDOW then Shadow.costWindowN = n + 1 end
	n = Shadow.costWindowN

	local sum, mx = 0, 0
	for i = 1, n do
		local v = win[i]
		sum = sum + v
		if v > mx then mx = v end
	end
	Shadow.costAvgUs = sum / n
	Shadow.costMaxUs = mx

	if costMs > BUDGET_SINGLE_MS then
		Shadow.disabledReason = string.format("single sample %.3f ms > %.1f ms", costMs, BUDGET_SINGLE_MS)
	elseif n >= BUDGET_WINDOW and (Shadow.costAvgUs / 1000) > BUDGET_AVG_MS then
		Shadow.disabledReason = string.format("avg %.3f ms > %.1f ms over %d samples", Shadow.costAvgUs / 1000, BUDGET_AVG_MS, n)
	end
	if Shadow.disabledReason and not Shadow.disabledPrinted then
		Shadow.disabledPrinted = true
		print("[hg_ballistics_v2] shadow auto-disabled: " .. Shadow.disabledReason)
	end
end

-- v1 = {organs, exit, dist}; v2 = the raw V2.Trace result or nil on error; ctx = {wep, ammo,
-- pen, maxpen, v0, pellet, cost, err}. Errors are counted here, never raised to the caller.
function Shadow.Record(v1, v2, ctx)
	ctx = ctx or {}
	recordCost(ctx.cost or 0)

	local ammo = ctx.ammo or "?"
	local row = ammoRow(ammo)
	row.shots = row.shots + 1
	if v1 and v1.exit then row.v1exits = row.v1exits + 1 end

	local v2out = nil
	if ctx.err then
		Shadow.errors = Shadow.errors + 1
		Shadow.lastError = ctx.err
	elseif v2 then
		local hits = {}
		local organSet = {}
		for i = 1, #v2.hits do
			local h = v2.hits[i]
			hits[#hits + 1] = {
				organ = h.organ,
				e = math.floor((h.e or 0) * 100 + 0.5) / 100,
				ricochet = h.ricochet == true,
				dep = math.floor((h.dep or 0) * 100 + 0.5) / 100,
				share = h.share and (math.floor(h.share * 100 + 0.5) / 100) or nil,
				frag = h.frag,
			}
			if h.organ then organSet[h.organ] = true end
		end
		-- The main round's own lodge (frag == nil) is always lodges[1] when reason == "lodged"
		-- (core: appendLodge runs for the main round before any fragment) -- no need to hunt
		-- the last segment's box for it.
		local lodgedIn = "flesh"
		if v2.reason == "lodged" and v2.lodges and v2.lodges[1] then
			lodgedIn = v2.lodges[1].organ or "flesh"
		end
		v2out = {
			hits = hits,
			reason = v2.reason,
			e = v2.e,
			deflects = v2.deflects,
			lodgedIn = lodgedIn,
			construction = ctx.construction,
			dep = math.floor((1 - (v2.e or 0)) * 100 + 0.5) / 100,
			fragments = v2.fragments or 0,
			lodges = v2.lodges and #v2.lodges or 0,
			expanded = v2.expanded == true,
		}
		if v2.reason == "lodged" then row.lodges = row.lodges + 1 end
		if v2.reason == "exited" then row.v2exits = row.v2exits + 1 end
		if (v2.fragments or 0) > 0 then row.fragments = row.fragments + 1 end
		if v2.lodges and #v2.lodges > 0 then row.retained = row.retained + 1 end
		Shadow.stats.deflections = Shadow.stats.deflections + (v2.deflects or 0)

		Shadow.stats.agreeTotal = Shadow.stats.agreeTotal + 1
		local v1set = {}
		if v1 and v1.organs then
			for i = 1, #v1.organs do v1set[v1.organs[i]] = true end
		end
		local match = true
		for k in pairs(v1set) do if not organSet[k] then match = false break end end
		if match then for k in pairs(organSet) do if not v1set[k] then match = false break end end end
		if match then Shadow.stats.agreeOrgans = Shadow.stats.agreeOrgans + 1 end
	end

	local h = openHandle()
	if not h then return end

	local ok = pcall(function()
		local encoded = util.TableToJSON({
			t = os.time(),
			map = game.GetMap(),
			wep = ctx.wep,
			ammo = ammo,
			pen = ctx.pen,
			maxpen = ctx.maxpen,
			v0 = ctx.v0,
			v0src = ctx.v0 and "bullet" or "fallback",
			pellet = ctx.pellet == true,
			v1 = v1,
			v2 = v2out,
			armored = v2 and v2.armored or nil,
			cost_us = (ctx.cost or 0) * 1000,
		})
		if encoded then
			h:Write(encoded)
			h:Write("\n")
		end
	end)
	if not ok then return end

	Shadow.rows = Shadow.rows + 1
	Shadow.rowsSinceFlush = Shadow.rowsSinceFlush + 1
	if Shadow.rowsSinceFlush >= FLUSH_EVERY then Shadow.Flush() end
	rotateIfNeeded()
end

hook.Add("ShutDown", "hg_ballistics_v2_shadow_flush", function()
	if Shadow.handle then
		Shadow.handle:Flush()
	end
end)

concommand.Add("hg_ballistics_v2_stats", function(ply)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	local s = Shadow.stats
	local agreePct = (s.agreeTotal > 0) and (s.agreeOrgans / s.agreeTotal * 100) or 0
	print(string.format("[hg_ballistics_v2] rows=%d errors=%d lastError=%s", Shadow.rows, Shadow.errors, tostring(Shadow.lastError)))
	print(string.format("[hg_ballistics_v2] organ-set agreement: %.1f%% (%d/%d)", agreePct, s.agreeOrgans, s.agreeTotal))
	print(string.format("[hg_ballistics_v2] deflections: %d", s.deflections))
	print(string.format("[hg_ballistics_v2] cost avg=%.1f us max=%.1f us", Shadow.costAvgUs, Shadow.costMaxUs))
	print(string.format("[hg_ballistics_v2] disabled=%s reason=%s", tostring(Shadow.disabledReason ~= nil), tostring(Shadow.disabledReason)))
	for ammo, row in pairs(s.byAmmo) do
		local lodgeRate = (row.shots > 0) and (row.lodges / row.shots * 100) or 0
		local v1ExitRate = (row.shots > 0) and (row.v1exits / row.shots * 100) or 0
		local v2ExitRate = (row.shots > 0) and (row.v2exits / row.shots * 100) or 0
		local fragRate = (row.shots > 0) and (row.fragments / row.shots * 100) or 0
		local retainedRate = (row.shots > 0) and (row.retained / row.shots * 100) or 0
		print(string.format("[hg_ballistics_v2]  ammo=%s shots=%d lodge=%.1f%% v1exit=%.1f%% v2exit=%.1f%% frag=%.1f%% retained=%.1f%%", ammo, row.shots, lodgeRate, v1ExitRate, v2ExitRate, fragRate, retainedRate))
	end
end, nil, "In-body ballistics v2: shadow-mode aggregate stats")
