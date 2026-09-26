-- In-body ballistics v2 (shared).
-- A bullet that hits a body walks the organ hitboxes as a physical round: it spends a
-- budget of inches-of-flesh per unit of tissue crossed, deflects off bone at grazing
-- angles, lodges when the budget is spent or exits with what is left. Its construction
-- (opts.profile, see V2.Profiles) scales bone resistance, can make it open up after an
-- inch of tissue, and can throw fragments off a bone or plate that walk on by themselves.
-- Loaded on server (sv_input.lua: shadow + live), client (hg_show_hitbox preview) and in
-- the offline harness (tests/test_ballistics_v2.py). Pure Lua + Vector/Angle only; it never
-- reads or writes an organism and never calls a damage function itself - sv_input's
-- callbacks do that in live mode:
--   opts.onBox(event) ARMOR rows only, at entry, during the walk (main round only). A
--                     numeric return f absorbs f * budget at once (v1 protec semantics).
--   opts.onHit(hit)   once per non-armor hit (organ, bone, vessel, lung, dense - ricochet
--                     and fragment hits included) AFTER the whole walk (main round and
--                     fragments), in res.hits order = entry order, with hit.eOut/dep final.
hg = hg or {}
hg.organism = hg.organism or {}
hg.organism.BallisticsV2 = hg.organism.BallisticsV2 or {}
local V2 = hg.organism.BallisticsV2
V2.Version = "20260923.v2b"

local math_sqrt, math_acos, math_deg, math_rad = math.sqrt, math.acos, math.deg, math.rad
local math_sin, math_cos = math.sin, math.cos
local math_max, math_min, math_abs, math_floor = math.max, math.min, math.abs, math.floor
local math_huge = math.huge
local string_find = string.find
local table_sort = table.sort
local Vector = Vector

-- PROVISIONAL(2026-09-23, uncalibrated first guesses - the shadow log decides, ratify-by: 2026-10-07)
-- Resistance is budget spent per inch of travel inside that tissue.
V2.Tissue = {
	air = 0,
	flesh = 1.0,
	organ = 1.0,
	lung = 0.5,
	dense = 1.2,
	vessel = 1.0,
	boneBase = 1,      -- bone = boneBase + boneScale * hardness * (1 - broken)
	boneScale = 14,
	armorPerInch = 20, -- only without an onBox callback (shadow, client preview)
	deflectCost = 0.5, -- fraction of the bone's per-inch resistance a glancing blow costs
	grazeBase = 55,    -- deflect when the angle to the face normal exceeds grazeBase + grazeEnergy * e
	grazeEnergy = 25,
	maxDeflects = 2,
	-- PROVISIONAL(2026-09-23, floor on the reflection blend so a deflected round always
	-- leaves the face: k = 0.3 + 0.5 * hardness is below 0.5 for hardness < 0.4 (spine) and
	-- would point the new heading back into the bone, ratify-by: 2026-10-07)
	deflectBlendMin = 0.55,
	-- PROVISIONAL(2026-09-23, expansion - after expandAfter inches of non-air tissue every resistance is x(1 + expandDrag * profile.expand), ratify-by: 2026-10-07)
	expandAfter = 1.0,
	expandDrag = 1.5,
	-- PROVISIONAL(2026-09-23, fragmentation - main round only, bone/plate entry above fragMinE energy; fragShare of the budget splits evenly into the fragments, ratify-by: 2026-10-07)
	fragMinE = 0.5,
	fragShare = 0.4,
	-- PROVISIONAL(2026-09-23, fragment heading - fragAngleMin + rng * fragAngleSpan degrees off the round's heading, ratify-by: 2026-10-07)
	fragAngleMin = 20,
	fragAngleSpan = 25,
	-- PROVISIONAL(2026-09-23, damage share of one hit = dmgDirect * eIn + dmgDeposit * min(1, dep / depNorm), clamped 0..1, ratify-by: 2026-10-07)
	dmgDirect = 0.35,
	dmgDeposit = 0.65,
	depNorm = 0.25,
	-- PROVISIONAL(2026-09-23, severity of the internal wound a retained round keeps open, x0.4 for a fragment - read by sv_input, ratify-by: 2026-10-07)
	retainedBleed = 0.6,
}
V2.MaxLegs = 6
V2.MaxEvents = 256 -- 2 per box crossed per leg; a loop guard, not a cost cap
V2.BudgetCap = 50 -- v1 parity: math.Clamp(|dir|, 0, 50) in sv_hitboxorgans.lua

-- PROVISIONAL(2026-09-23, bullet construction profiles - uncalibrated first guesses, the shadow log decides, ratify-by: 2026-10-07)
-- expand 0..1: how far it opens up (Tissue.expandDrag); fragChance / fragMax: chance of
-- fragmenting on a bone/plate entry and the most fragments; boneMul: x bone resistance.
V2.Profiles = {
	fmj       = {expand = 0,    fragChance = 0.15, fragMax = 2, boneMul = 1.0},
	ap        = {expand = 0,    fragChance = 0.05, fragMax = 1, boneMul = 0.6},
	sp        = {expand = 0.5,  fragChance = 0.35, fragMax = 2, boneMul = 1.1},
	jhp       = {expand = 1.0,  fragChance = 0.5,  fragMax = 2, boneMul = 1.3},
	frangible = {expand = 1.0,  fragChance = 1.0,  fragMax = 3, boneMul = 1.5},
	shot      = {expand = 0,    fragChance = 0,    fragMax = 0, boneMul = 1.2},
	flechette = {expand = 0,    fragChance = 0,    fragMax = 0, boneMul = 0.7},
	slug      = {expand = 0.3,  fragChance = 0.2,  fragMax = 2, boneMul = 1.0},
	blunt     = {expand = 0,    fragChance = 0,    fragMax = 0, boneMul = 1.0},
}
-- opts.profile absent: round-1 physics (no expansion, no fragments, bone x1). Callers that
-- want a construction pass V2.ResolveProfile(...), which defaults to fmj.
local NO_PROFILE = {expand = 0, fragChance = 0, fragMax = 0, boneMul = 1}
local PROFILE_KEYS = {"expand", "fragChance", "fragMax", "boneMul"}

-- organ row name -> organism key holding that bone's break fraction (sv_bone.lua callers)
V2.BoneKey = {
	skull = "skull", jaw = "jaw", chest = "chest", pelvis = "pelvis",
	spine1 = "spine1", spine2 = "spine2", spine3 = "spine3",
	rarmup = "rarm", rarmdown = "rarm", larmup = "larm", larmdown = "larm",
	rlegup = "rleg", rlegdown = "rleg", llegup = "lleg", llegdown = "lleg",
}

local REASON_CODE = {lodged = 1, exited = 2, maxpen = 3, limit = 3, boundary = 4}
local COMPAT_POINTS = 20

-- Tissue class of an organ row. Order matters: armor rows carry hardness 1 as well.
-- Returns class, resistance per inch (bone: unbroken), hardness.
function V2.Classify(row)
	local T = V2.Tissue
	if type(row) ~= "table" then return "flesh", T.flesh, 0 end
	local name = row[1]
	local hardness = row[2]
	if type(hardness) ~= "number" then hardness = 0 end
	if row[7] == true then return "armor", T.armorPerInch, hardness end
	if hardness >= 0.2 then return "bone", T.boneBase + T.boneScale * hardness, hardness end
	if type(name) ~= "string" then return "flesh", T.flesh, 0 end
	-- "arter" catches both the "arteria" neck rows and the "*artery" limb rows
	if string_find(name, "arter", 1, true) then return "vessel", T.vessel, hardness end
	if name == "lungsL" or name == "lungsR" then return "lung", T.lung, hardness end
	-- organs_20260925: the solid abdominal organs walk as dense tissue like the liver
	if name == "heart" or name == "liver" or name == "spleen" or name == "kidneyL" or name == "kidneyR" then return "dense", T.dense, hardness end
	return "organ", T.organ, hardness
end

-- ballistics = an ammo type's BulletSettings.Ballistics table or nil. Returns a new table
-- {construction, expand, fragChance, fragMax, boneMul}: the construction's profile (unknown
-- or missing construction -> fmj) with any numeric field of `ballistics` overriding it.
function V2.ResolveProfile(ballistics)
	local P = V2.Profiles
	local b = (type(ballistics) == "table") and ballistics or nil
	local c = b and b.construction
	if type(c) ~= "string" or type(P[c]) ~= "table" then c = "fmj" end
	local base = P[c]
	local out = {construction = c}
	for k = 1, #PROFILE_KEYS do
		local key = PROFILE_KEYS[k]
		local v = b and b[key]
		if type(v) == "number" and v == v then
			out[key] = v
		else
			out[key] = base[key]
		end
	end
	return out
end

-- Damage share (0..1 of the shot's damage) for one hit: part from the energy the round
-- arrived with, part from the fraction of its budget it left in that box. Pure.
function V2.DamageShare(eIn, dep)
	local T = V2.Tissue
	eIn = tonumber(eIn) or 0
	dep = tonumber(dep) or 0
	local s = T.dmgDirect * eIn + T.dmgDeposit * math_min(1, dep / T.depNorm)
	if s ~= s or s < 0 then return 0 end
	if s > 1 then return 1 end
	return s
end

-- Box axes and bounds as plain numbers, cached on the box table (string key; numeric
-- slots 1..7 are untouched). Source local frame: X = Forward, Y = LEFT = -Right, Z = Up.
-- Layout: 1-3 F, 4-6 L, 7-9 U, 10-12 origin, 13-15 mins, 16-18 maxs.
-- Axes straight from the angle (Source AngleVectors), no Forward/Right/Up Vectors.
local function boxAxes(box)
	local ax = box.v2ax
	if ax then return ax end
	local ang, o, mins, maxs = box[2], box[1], box[3], box[4]
	local p, y, r = math_rad(ang.p), math_rad(ang.y), math_rad(ang.r)
	local sp, cp = math_sin(p), math_cos(p)
	local sy, cy = math_sin(y), math_cos(y)
	local sr, cr = math_sin(r), math_cos(r)
	ax = {
		cp * cy, cp * sy, -sp,
		sr * sp * cy - cr * sy, sr * sp * sy + cr * cy, sr * cp,
		cr * sp * cy + sr * sy, cr * sp * sy - sr * cy, cr * cp,
		o.x, o.y, o.z,
		mins.x, mins.y, mins.z,
		maxs.x, maxs.y, maxs.z,
	}
	box.v2ax = ax
	return ax
end
V2.BoxAxes = boxAxes

-- Slab test. Returns tEnter, tExit and the world-space outward normal of the face the
-- ray enters through, or nil when the ray misses, the box is zero-thickness, or the whole
-- intersection lies behind the origin. tEnter may be negative (origin inside the box).
function V2.RayOBB(ox, oy, oz, dx, dy, dz, box)
	local ax = boxAxes(box)
	local px, py, pz = ox - ax[10], oy - ax[11], oz - ax[12]
	local tEnter, tExit = -math_huge, math_huge
	local nAxis, nSign = 1, -1
	for a = 0, 2 do
		local k = a * 3
		local lo, hi = ax[13 + a], ax[16 + a]
		if hi - lo <= 1e-6 then return nil end
		local ex, ey, ez = ax[k + 1], ax[k + 2], ax[k + 3]
		local p = px * ex + py * ey + pz * ez
		local d = dx * ex + dy * ey + dz * ez
		if d > -1e-9 and d < 1e-9 then
			if p < lo or p > hi then return nil end
		else
			local t1, t2 = (lo - p) / d, (hi - p) / d
			local sign = -1 -- entering through the lo face: outward normal is -axis
			if t1 > t2 then
				t1, t2 = t2, t1
				sign = 1
			end
			if t1 > tEnter then
				tEnter = t1
				nAxis = k + 1
				nSign = sign
			end
			if t2 < tExit then tExit = t2 end
			if tEnter > tExit then return nil end
		end
	end
	if tExit <= 0 then return nil end
	return tEnter, tExit, nSign * ax[nAxis], nSign * ax[nAxis + 1], nSign * ax[nAxis + 2]
end

-- ORGAN SHAPES (organs2_20260925). An organ row may carry `shape` = "ellipsoid" | "capsule" (anything else: the box).
-- The shape fills the row's box: an ellipsoid has the box's half-extents as semi-axes; a capsule runs along the box's
-- longest axis with radius = the larger of the two short half-extents, its caps inside the box's ends. Every test
-- returns what V2.RayOBB returns - tEnter, tExit, and the world-space outward normal where the ray enters - so the
-- walk, its deflection angle and its lodge lookup are unchanged. V2.TagShapes copies each row's shape onto its box once
-- per ShootMatrix result (box.v2shape, false = a box) so the walk never looks the row up again.
function V2.TagShapes(boxs, organs)
	if type(boxs) ~= "table" or type(organs) ~= "table" then return end
	for i = 1, #boxs do
		local b = boxs[i]
		if b.v2shape == nil then
			local rows = b[6] ~= nil and organs[b[6]]
			local row = rows and rows[b[7]]
			local s = type(row) == "table" and row.shape
			b.v2shape = (s == "ellipsoid" or s == "capsule") and s or false
		end
	end
end
-- local coordinates of a point / direction in the box frame, relative to the box centre
local function toLocal(ax, px, py, pz)
	return px * ax[1] + py * ax[2] + pz * ax[3] - (ax[13] + ax[16]) / 2,
		px * ax[4] + py * ax[5] + pz * ax[6] - (ax[14] + ax[17]) / 2,
		px * ax[7] + py * ax[8] + pz * ax[9] - (ax[15] + ax[18]) / 2
end
local function toWorldDir(ax, n1, n2, n3, dx, dy, dz)
	local wx = n1 * ax[1] + n2 * ax[4] + n3 * ax[7]
	local wy = n1 * ax[2] + n2 * ax[5] + n3 * ax[8]
	local wz = n1 * ax[3] + n2 * ax[6] + n3 * ax[9]
	local l = math_sqrt(wx * wx + wy * wy + wz * wz)
	if l < 1e-9 then return -dx, -dy, -dz end
	return wx / l, wy / l, wz / l
end
function V2.RayEllipsoid(ox, oy, oz, dx, dy, dz, box)
	local ax = boxAxes(box)
	local sx, sy, sz = (ax[16] - ax[13]) / 2, (ax[17] - ax[14]) / 2, (ax[18] - ax[15]) / 2
	if sx <= 1e-6 or sy <= 1e-6 or sz <= 1e-6 then return nil end
	local lx, ly, lz = toLocal(ax, ox - ax[10], oy - ax[11], oz - ax[12])
	local ex = (dx * ax[1] + dy * ax[2] + dz * ax[3]) / sx
	local ey = (dx * ax[4] + dy * ax[5] + dz * ax[6]) / sy
	local ez = (dx * ax[7] + dy * ax[8] + dz * ax[9]) / sz
	lx, ly, lz = lx / sx, ly / sy, lz / sz
	local a = ex * ex + ey * ey + ez * ez
	if a < 1e-12 then return nil end
	local b = lx * ex + ly * ey + lz * ez
	local c = lx * lx + ly * ly + lz * lz - 1
	local disc = b * b - a * c
	if disc <= 0 then return nil end
	local r = math_sqrt(disc)
	local t0, t1 = (-b - r) / a, (-b + r) / a
	if t1 <= 0 then return nil end
	-- outward normal: the gradient of the unit-sphere form, back through the scale
	local ux, uy, uz = lx + ex * t0, ly + ey * t0, lz + ez * t0
	local nx, ny, nz = toWorldDir(ax, ux / sx, uy / sy, uz / sz, dx, dy, dz)
	return t0, t1, nx, ny, nz
end
function V2.RayCapsule(ox, oy, oz, dx, dy, dz, box)
	local ax = boxAxes(box)
	local hx, hy, hz = (ax[16] - ax[13]) / 2, (ax[17] - ax[14]) / 2, (ax[18] - ax[15]) / 2
	if hx <= 1e-6 or hy <= 1e-6 or hz <= 1e-6 then return nil end
	local l1, l2, l3 = toLocal(ax, ox - ax[10], oy - ax[11], oz - ax[12])
	local e1 = dx * ax[1] + dy * ax[2] + dz * ax[3]
	local e2 = dx * ax[4] + dy * ax[5] + dz * ax[6]
	local e3 = dx * ax[7] + dy * ax[8] + dz * ax[9]
	-- long axis first: a = along it, b / c = across
	local k, la, lb, lc, ea, eb, ec, ha, r
	if hx >= hy and hx >= hz then k, la, lb, lc, ea, eb, ec, ha, r = 1, l1, l2, l3, e1, e2, e3, hx, math_max(hy, hz)
	elseif hy >= hz then k, la, lb, lc, ea, eb, ec, ha, r = 2, l2, l1, l3, e2, e1, e3, hy, math_max(hx, hz)
	else k, la, lb, lc, ea, eb, ec, ha, r = 3, l3, l1, l2, e3, e1, e2, hz, math_max(hx, hy) end
	local h = math_max(ha - r, 0)
	local t0, t1, na, nb, nc = math_huge, -math_huge, 0, 0, 0
	-- the side: a cylinder of radius r about the long axis, clipped to |along| <= h
	local qa = eb * eb + ec * ec
	if h > 0 and qa > 1e-12 then
		local qb = lb * eb + lc * ec
		local qc = lb * lb + lc * lc - r * r
		local disc = qb * qb - qa * qc
		if disc > 0 then
			local s = math_sqrt(disc)
			local c0, c1 = (-qb - s) / qa, (-qb + s) / qa
			local u0, u1 = -math_huge, math_huge
			if ea > 1e-12 or ea < -1e-12 then
				u0, u1 = (-h - la) / ea, (h - la) / ea
				if u0 > u1 then u0, u1 = u1, u0 end
			elseif la < -h or la > h then
				u0 = nil
			end
			if u0 then
				local a0, a1 = math_max(c0, u0), math_min(c1, u1)
				if a0 < a1 then
					if a0 < t0 then t0, na, nb, nc = a0, 0, lb + eb * a0, lc + ec * a0 end
					if a1 > t1 then t1 = a1 end
				end
			end
		end
	end
	-- the caps: spheres of radius r at along = -h and +h (one sphere when h is 0); the direction is unit, so a = 1
	for cap = -1, (h > 0) and 1 or -1, 2 do
		local sa = la - cap * h
		local qb = sa * ea + lb * eb + lc * ec
		local qc = sa * sa + lb * lb + lc * lc - r * r
		local disc = qb * qb - qc
		if disc > 0 then
			local s = math_sqrt(disc)
			local c0, c1 = -qb - s, -qb + s
			if c0 < t0 then t0, na, nb, nc = c0, sa + ea * c0, lb + eb * c0, lc + ec * c0 end
			if c1 > t1 then t1 = c1 end
		end
	end
	if t1 <= 0 or t0 >= t1 then return nil end
	local n1, n2, n3
	if k == 1 then n1, n2, n3 = na, nb, nc elseif k == 2 then n1, n2, n3 = nb, na, nc else n1, n2, n3 = nb, nc, na end
	local nx, ny, nz = toWorldDir(ax, n1, n2, n3, dx, dy, dz)
	return t0, t1, nx, ny, nz
end
-- A bounding-sphere reject first (performance, owner 2026-09-25: "are we going to kill performance?"): most rays miss
-- most of the ~60 shapes on a body, and a miss costs one dot product here instead of the exact test. The sphere is the
-- box's circumsphere, so it never rejects a real hit. Cached on the axes table like the rest of the box frame.
function V2.RayShape(ox, oy, oz, dx, dy, dz, box)
	local ax = boxAxes(box)
	local R2 = ax.r2
	if not R2 then
		local hx, hy, hz = (ax[16] - ax[13]) / 2, (ax[17] - ax[14]) / 2, (ax[18] - ax[15]) / 2
		local cx, cy, cz = (ax[13] + ax[16]) / 2, (ax[14] + ax[17]) / 2, (ax[15] + ax[18]) / 2
		ax.cwx = ax[10] + cx * ax[1] + cy * ax[4] + cz * ax[7]
		ax.cwy = ax[11] + cx * ax[2] + cy * ax[5] + cz * ax[8]
		ax.cwz = ax[12] + cx * ax[3] + cy * ax[6] + cz * ax[9]
		R2 = hx * hx + hy * hy + hz * hz + 1e-6
		ax.r2 = R2
	end
	local px, py, pz = ax.cwx - ox, ax.cwy - oy, ax.cwz - oz
	local along = px * dx + py * dy + pz * dz
	local d2 = px * px + py * py + pz * pz
	if d2 - along * along > R2 then return nil end -- the line passes outside the sphere
	if along < 0 and d2 > R2 then return nil end -- the sphere is behind a start point outside it
	local s = box.v2shape
	if s == "ellipsoid" then return V2.RayEllipsoid(ox, oy, oz, dx, dy, dz, box) end
	if s == "capsule" then return V2.RayCapsule(ox, oy, oz, dx, dy, dz, box) end
	return V2.RayOBB(ox, oy, oz, dx, dy, dz, box)
end
-- Is a world point inside the box's shape? (the killcam overlay's lodge / fragment marks, gates)
function V2.PointInShape(box, x, y, z)
	local ax = boxAxes(box)
	local l1, l2, l3 = toLocal(ax, x - ax[10], y - ax[11], z - ax[12])
	local hx, hy, hz = (ax[16] - ax[13]) / 2, (ax[17] - ax[14]) / 2, (ax[18] - ax[15]) / 2
	local s = box.v2shape
	if s == "ellipsoid" then
		if hx <= 0 or hy <= 0 or hz <= 0 then return false end
		return (l1 / hx) ^ 2 + (l2 / hy) ^ 2 + (l3 / hz) ^ 2 <= 1
	end
	if s == "capsule" then
		local la, lb, lc, ha, r
		if hx >= hy and hx >= hz then la, lb, lc, ha, r = l1, l2, l3, hx, math_max(hy, hz)
		elseif hy >= hz then la, lb, lc, ha, r = l2, l1, l3, hy, math_max(hx, hz)
		else la, lb, lc, ha, r = l3, l1, l2, hz, math_max(hx, hy) end
		local h = math_max(ha - r, 0)
		local a = math_max(-h, math_min(h, la))
		return (la - a) ^ 2 + lb * lb + lc * lc <= r * r
	end
	return math_abs(l1) <= hx and math_abs(l2) <= hy and math_abs(l3) <= hz
end

local function vec(x, y, z) return Vector(x, y, z) end

-- Scratch tables of one walk, reused across calls instead of allocated per call. A set is
-- checked out of the pool for the whole walk, so a callback that re-enters V2.Trace finds
-- it taken and gets a fresh set (the reentrancy guard); a set lost to an erroring callback
-- is simply replaced. The main round's set also carries the per-trace context (W).
local scratchPool = {}

local function newScratch()
	local sc = {
		nMax = 0,
		inside = {}, bClass = {}, bR = {}, bRow = {}, nxs = {}, nys = {}, nzs = {},
		startIn = {}, seen = {}, openHit = {}, openDrawn = {},
		evT = {}, evBox = {}, evEnter = {}, order = {},
	}
	local evT, evEnter = sc.evT, sc.evEnter
	sc.sortEvents = function(a, b)
		local ta, tb = evT[a], evT[b]
		if ta == tb then return evEnter[a] and not evEnter[b] end
		return ta < tb
	end
	return sc
end

-- Only inside and openHit carry state from one walk into the next; every other per-box
-- and per-event array is written before it is read inside a walk (seen: every leg for
-- every box; startIn/nxs/nys/nzs: when the box has a crossing this leg; bClass/bR/bRow:
-- at entry, read only while inside; evT/evBox/evEnter/order: 1..n each leg). Clearing
-- those too measured +17 us per call on the perf body for no behavioural difference.
local function clearScratch(sc)
	local inside, openHit = sc.inside, sc.openHit
	for i = 1, sc.nMax do
		inside[i], openHit[i] = nil, nil
	end
	sc.nMax = 0
end

local function acquireScratch()
	local n = #scratchPool
	local sc = scratchPool[n]
	if sc then
		scratchPool[n] = nil
		clearScratch(sc)
	else
		sc = newScratch()
	end
	return sc
end

local function releaseScratch(sc)
	-- a pooled set must not pin the caller's body, organism or callbacks
	sc.boxs, sc.organs, sc.org, sc.rng, sc.onBox, sc.fragList = nil, nil, nil, nil, nil, nil
	scratchPool[#scratchPool + 1] = sc
end

-- Tissue the round is currently in. Organ rows describe the body more precisely than
-- the coarse model hitboxes, so any organ row beats the flesh of the hitbox enclosing it
-- (a lung inside the chest hitbox costs lung, not flesh); among overlapping organ rows
-- the highest resistance wins (brain inside skull costs skull); an exact tie keeps the
-- lowest box index, so the answer never depends on table iteration order.
local function current(sc)
	local bR, bRow, bClass = sc.bR, sc.bRow, sc.bClass
	local class, R, which, tier = "air", 0, nil, -1
	for i in pairs(sc.inside) do
		local t = bRow[i] and 1 or 0
		local r = bR[i]
		if t > tier or (t == tier and r > R) then
			tier, R, class, which = t, r, bClass[i], i
		elseif t == tier and r == R and i < which then
			class, which = bClass[i], i
		end
	end
	return class, R, which
end

-- dep = eIn - eOut, less any budget handed to fragments while the round was inside the
-- box (a fragmenting rib inside a lung: the fragments' share left the round, it was not
-- deposited in the lung). (Hits are built with eOut = 0, dep = 0 placeholders so the
-- table is sized once.)
local function closeHit(h, eOut, drawn)
	h.eOut = eOut
	h.dep = h.eIn - eOut - drawn
end

-- Fragmentation check on a plain bone/plate entry by the main round. Draws every random
-- number the fragments need now (chance, count, then theta/phi per fragment) and queues
-- them on W; they are walked after the main round. Returns the main round's new budget.
local function spawnFragments(W, res, px, py, pz, dx, dy, dz, B, budget, i, travelled)
	if W.fragmented or W.fragMax <= 0 then return B end
	local T = V2.Tissue
	local e = B / budget
	if e <= T.fragMinE then return B end
	local rng = W.rng
	if rng() >= W.fragChance then return B end
	W.fragmented = true
	local fragMax = W.fragMax
	local n = math_min(1 + math_floor(rng() * fragMax), fragMax)
	local fragB = T.fragShare * B / n
	-- perpendicular basis: cross the heading with the least-aligned world axis
	local adx, ady, adz = math_abs(dx), math_abs(dy), math_abs(dz)
	local wx, wy, wz = 0, 0, 1
	if adx <= ady and adx <= adz then
		wx, wz = 1, 0
	elseif ady <= adz then
		wy, wz = 1, 0
	end
	local p1x, p1y, p1z = dy * wz - dz * wy, dz * wx - dx * wz, dx * wy - dy * wx
	local pl = math_sqrt(p1x * p1x + p1y * p1y + p1z * p1z)
	p1x, p1y, p1z = p1x / pl, p1y / pl, p1z / pl
	local p2x, p2y, p2z = dy * p1z - dz * p1y, dz * p1x - dx * p1z, dx * p1y - dy * p1x
	local list = {}
	for k = 1, n do
		local theta = math_rad(T.fragAngleMin + rng() * T.fragAngleSpan)
		local phi = math_rad(rng() * 360)
		local cphi, sphi = math_cos(phi), math_sin(phi)
		-- rotation axis u (perpendicular to d); rotating d about u by theta:
		-- d' = d cos(theta) + (u x d) sin(theta)
		local ux, uy, uz = cphi * p1x + sphi * p2x, cphi * p1y + sphi * p2y, cphi * p1z + sphi * p2z
		local cxx, cxy, cxz = uy * dz - uz * dy, uz * dx - ux * dz, ux * dy - uy * dx
		local ct, st = math_cos(theta), math_sin(theta)
		local fx, fy, fz = dx * ct + cxx * st, dy * ct + cxy * st, dz * ct + cxz * st
		local fl = math_sqrt(fx * fx + fy * fy + fz * fz)
		list[k] = {fx / fl, fy / fl, fz / fl}
	end
	W.fragList, W.fragN, W.fragB, W.fragBox = list, n, fragB, i
	W.fragX, W.fragY, W.fragZ, W.fragTravelled = px, py, pz, travelled
	res.fragments = n
	local events = res.events
	events[#events + 1] = {kind = "fragment", pos = vec(px, py, pz), box = i, e = e, n = n, fragB = fragB}
	return B * (1 - T.fragShare)
end

-- Bone name for a retained round: the stop box's own bone when it is an organ row, else
-- the bone of the nearest organ row behind the stop point along the last segment, else nil
-- (flesh of a model hitbox: sv_input resolves the bone from the hitbox index).
local function lodgeBone(boxs, nBox, stopBox, seg, x, y, z, dx, dy, dz)
	local box = stopBox and boxs[stopBox]
	if box and box[6] ~= nil then return box[6] end
	if not seg then return nil end
	local a = seg.a
	local sx, sy, sz = a.x - x, a.y - y, a.z - z
	local L = math_sqrt(sx * sx + sy * sy + sz * sz)
	local best, bone = math_huge, nil
	for j = 1, nBox do
		local bj = boxs[j]
		if bj[6] ~= nil then
			local tin = V2.RayShape(x, y, z, -dx, -dy, -dz, bj)
			if tin then
				if tin < 0 then tin = 0 end
				if tin <= L + 1e-6 and tin < best then best, bone = tin, bj[6] end
			end
		end
	end
	return bone
end

local function appendLodge(res, W, x, y, z, dx, dy, dz, stopBox, seg, fragK)
	local boxs, organs = W.boxs, W.organs
	local organ = "flesh"
	local box = stopBox and boxs[stopBox]
	if box and organs and box[6] ~= nil then
		local rows = organs[box[6]]
		local row = rows and rows[box[7]]
		if type(row) == "table" and type(row[1]) == "string" then organ = row[1] end
	end
	local lodges = res.lodges
	lodges[#lodges + 1] = {
		pos = vec(x, y, z), box = stopBox, organ = organ,
		bone = lodgeBone(boxs, W.nBox, stopBox, seg, x, y, z, dx, dy, dz), frag = fragK, e = 0,
	}
end

-- One walk: the main round (fragK nil) or fragment fragK, with its own scratch set sc.
-- W = per-trace context (the main round's scratch set). budget = the walk's starting
-- budget (B0 for the main round, fragB for a fragment); every e this walk reports is
-- B / budget. Returns reason, B, lx, ly, lz, dx, dy, dz, entered, deflects, stopBox.
local function walk(sc, res, W, ox, oy, oz, dx, dy, dz, B, budget, fragK, startBox, travelled)
	local T = V2.Tissue
	local boxs, organs, nBox, org = W.boxs, W.organs, W.nBox, W.org
	local rng, onBox, maxpen = W.rng, W.onBox, W.maxpen
	local cx, cy, cz, endDisSqr = W.cx, W.cy, W.cz, W.endDisSqr
	local boneMul = W.boneMul
	local isFrag = fragK ~= nil
	local expMul = 1
	if not isFrag then expMul = W.expMul end
	local share = nil
	if isFrag then share = budget / W.B0 end
	local hits, events, segments, points = res.hits, res.events, res.segments, res.points
	local inputHole, outputHole, hitBoxs = res.inputHole, res.outputHole, res.hitBoxs
	local inside, bClass, bR, bRow = sc.inside, sc.bClass, sc.bR, sc.bRow
	local nxs, nys, nzs = sc.nxs, sc.nys, sc.nzs
	local startIn, seen, openHit, openDrawn = sc.startIn, sc.seen, sc.openHit, sc.openDrawn
	local evT, evBox, evEnter, order, sortEvents = sc.evT, sc.evBox, sc.evEnter, sc.order, sc.sortEvents
	if nBox > sc.nMax then sc.nMax = nBox end

	local insideCount = 0
	local entered = false     -- has this walk entered any box yet
	local legs, nEvents, deflects = 0, 0, 0
	local skipBox = nil
	local reason, stopBox = nil, nil
	local lx, ly, lz = ox, oy, oz -- last position
	local nonAir, expanded = 0, false
	local drawn = 0 -- budget (fraction of `budget`) handed to fragments so far

	while not reason do
		legs = legs + 1
		if legs > V2.MaxLegs then
			reason = "limit"
			break
		end

		-- gather this leg's boundary crossings
		local n = 0
		for i = 1, nBox do
			seen[i] = nil
			if i ~= skipBox then
				local tin, tout, nx, ny, nz = V2.RayShape(ox, oy, oz, dx, dy, dz, boxs[i])
				if tin then
					local wasInside = inside[i]
					-- a fragment starts on the face of the box that spawned it: entered at t = 0
					if tin < 0 or (i == startBox and legs == 1) then tin = 0 end
					if tout - tin > 1e-6 or (wasInside and tout > 0) then
						seen[i] = true
						startIn[i] = (tin <= 0)
						if not wasInside then
							n = n + 1
							evT[n], evBox[n], evEnter[n] = tin, i, true
						end
						n = n + 1
						evT[n], evBox[n], evEnter[n] = tout, i, false
						nxs[i], nys[i], nzs[i] = nx, ny, nz
					end
				end
			end
		end
		-- a box we were inside that the new heading no longer crosses (numerical): drop it
		for i in pairs(inside) do
			if not seen[i] then
				inside[i] = nil
				insideCount = insideCount - 1
				local h = openHit[i]
				if h then
					closeHit(h, B / budget, drawn - openDrawn[i])
					openHit[i] = nil
				end
			end
		end
		for k = #order, n + 1, -1 do order[k] = nil end
		for k = 1, n do order[k] = k end
		if n > 1 then table_sort(order, sortEvents) end

		local tPrev = 0
		local legEnded = false
		for k = 1, n do
			local idx = order[k]
			local t, i, isEnter = evT[idx], evBox[idx], evEnter[idx]
			nEvents = nEvents + 1
			if nEvents > V2.MaxEvents then
				reason = "limit"
				break
			end

			-- 1. spend the interval [tPrev, t]
			local len = t - tPrev
			if len > 1e-9 then
				local class, R, which = current(sc)
				local eIn = B / budget
				local stopAt = nil
				if entered then
					if maxpen > 0 and travelled + len >= maxpen then
						len = math_max(maxpen - travelled, 0)
						stopAt = "maxpen"
					end
					if R > 0 then
						-- l1: the part spent at the current rate; an expanding round that
						-- crosses expandAfter inches of tissue inside this interval opens up
						-- there and pays the rest at the expanded rate
						local l1, rate = len, R
						if expanded then
							rate = R * expMul
						elseif expMul > 1 and nonAir + len > T.expandAfter then
							l1 = T.expandAfter - nonAir
						end
						local cost = rate * l1
						if cost > B then
							len = B / rate
							B = 0
							stopAt = "lodged"
						else
							B = B - cost
							if l1 < len then
								expanded = true
								res.expanded = true
								local te = tPrev + l1
								events[#events + 1] = {kind = "expand", pos = vec(ox + dx * te, oy + dy * te, oz + dz * te), box = which, e = B / budget}
								rate = R * expMul
								local cost2 = rate * (len - l1)
								if cost2 > B then
									len = l1 + B / rate
									B = 0
									stopAt = "lodged"
								else
									B = B - cost2
								end
							end
						end
						nonAir = nonAir + len
					end
					travelled = travelled + len
				end
				local ax1, ay1, az1 = ox + dx * tPrev, oy + dy * tPrev, oz + dz * tPrev
				local bx1, by1, bz1 = ox + dx * (tPrev + len), oy + dy * (tPrev + len), oz + dz * (tPrev + len)
				segments[#segments + 1] = {
					a = vec(ax1, ay1, az1), b = vec(bx1, by1, bz1),
					class = class, box = which, eIn = eIn, eOut = B / budget, frag = fragK,
				}
				lx, ly, lz = bx1, by1, bz1
				if stopAt then
					reason = stopAt
					stopBox = which
					events[#events + 1] = {kind = (stopAt == "lodged") and "lodge" or "maxpen", pos = vec(lx, ly, lz), box = which, e = B / budget, frag = fragK}
					if not isFrag then points[#points + 1] = vec(lx, ly, lz) end
					break
				end
			end
			tPrev = t
			local px, py, pz = ox + dx * t, oy + dy * t, oz + dz * t
			lx, ly, lz = px, py, pz

			-- 2. apply the crossing
			if isEnter then
				local box = boxs[i]
				local row = nil
				if organs and box[6] ~= nil then
					local bone = organs[box[6]]
					row = bone and bone[box[7]] or nil
				end
				local class, R, hardness
				if row == nil then
					class, R, hardness = "flesh", T.flesh, 0
				else
					class, R, hardness = V2.Classify(row)
					if class == "bone" and org then
						local key = V2.BoneKey[row[1]]
						local broken = key and org[key]
						if type(broken) == "number" then
							if broken < 0 then broken = 0 elseif broken > 1 then broken = 1 end
							R = T.boneBase + T.boneScale * hardness * (1 - broken)
						end
					end
				end
				local e = B / budget
				local deflected = false

				-- deflection: main round, bone rows, entered from outside, on the entry face
				if class == "bone" and not isFrag and not startIn[i] and deflects < T.maxDeflects then
					local nx, ny, nz = nxs[i], nys[i], nzs[i]
					local dn = dx * nx + dy * ny + dz * nz
					local cosv = math_abs(dn)
					if cosv > 1 then cosv = 1 end
					local theta = math_deg(math_acos(cosv))
					if theta > T.grazeBase + T.grazeEnergy * e and rng() < math_min(1, 2 * hardness) then
						deflected = true
						deflects = deflects + 1
						local h = {box = i, organ = row[1], bone = box[6], class = "bone", pos = vec(px, py, pz), e = e, eIn = e, eOut = 0, dep = 0, dir = vec(dx, dy, dz), ricochet = true}
						hits[#hits + 1] = h
						hitBoxs[i] = true
						-- the glancing blow costs the bone's own rate: no boneMul, no expansion
						B = B - T.deflectCost * R
						local kb = math_max(0.3 + 0.5 * hardness, T.deflectBlendMin)
						-- r = d - 2(d.n)n ; d' = d + (r - d) * k = d - 2k(d.n)n
						local ndx, ndy, ndz = dx - 2 * kb * dn * nx, dy - 2 * kb * dn * ny, dz - 2 * kb * dn * nz
						local nl = math_sqrt(ndx * ndx + ndy * ndy + ndz * ndz)
						if nl > 1e-9 then dx, dy, dz = ndx / nl, ndy / nl, ndz / nl end
						if B <= 0 then B = 0 end
						closeHit(h, B / budget, 0)
						events[#events + 1] = {kind = "deflect", pos = vec(px, py, pz), box = i, e = B / budget}
						points[#points + 1] = vec(px, py, pz)
						if B <= 0 then
							reason = "lodged"
							stopBox = i
							events[#events + 1] = {kind = "lodge", pos = vec(px, py, pz), box = i, e = 0}
						else
							ox, oy, oz = px, py, pz
							skipBox = i
							legEnded = true
						end
					end
				end

				if deflected then break end

				-- plain entry
				inside[i] = true
				insideCount = insideCount + 1
				if class == "armor" and isFrag then
					-- the plate already took its toll from the main round: fragments cross it as flesh
					class, R = "flesh", T.flesh
				end
				if class == "bone" then R = R * boneMul end
				bClass[i], bR[i], bRow[i] = class, R, (row ~= nil)
				if insideCount == 1 then
					entered = true
					if not isFrag then
						inputHole[#inputHole + 1] = vec(px, py, pz)
						events[#events + 1] = {kind = "entry", pos = vec(px, py, pz), box = i, e = e}
						points[#points + 1] = vec(px, py, pz)
					end
				end
				if class == "bone" and not isFrag then
					local Bs = B
					B = spawnFragments(W, res, px, py, pz, dx, dy, dz, B, budget, i, travelled)
					drawn = drawn + (Bs - B) / budget
				end
				if class ~= "flesh" then
					local eHit = B / budget
					local h = {box = i, organ = row[1], bone = box[6], class = class, pos = vec(px, py, pz), e = eHit, eIn = eHit, eOut = 0, dep = 0, dir = vec(dx, dy, dz), ricochet = false, frag = fragK, share = share}
					hits[#hits + 1] = h
					openHit[i], openDrawn[i] = h, drawn
					hitBoxs[i] = true
					if class == "armor" then
						res.armored = true
						events[#events + 1] = {kind = "armor", pos = vec(px, py, pz), box = i, e = eHit}
						if onBox then
							local f = onBox({box = i, row = row, class = class, pos = vec(px, py, pz), dir = vec(dx, dy, dz), e = eHit, ricochet = false})
							if type(f) == "number" then
								if f < 0 then f = 0 elseif f > 1 then f = 1 end
								B = B - f * B
								-- the plate's stopping power was applied at once (v1 protec semantics);
								-- crossing its thickness now costs flesh, not armorPerInch
								bR[i] = T.flesh
								if B <= 1e-9 then
									B = 0
									reason = "lodged"
									stopBox = i
									events[#events + 1] = {kind = "lodge", pos = vec(px, py, pz), box = i, e = 0}
									points[#points + 1] = vec(px, py, pz)
									break
								end
							end
						end
						-- spall off the plate: judged on what is left after the plate's toll
						local Bs = B
						B = spawnFragments(W, res, px, py, pz, dx, dy, dz, B, budget, i, travelled)
						drawn = drawn + (Bs - B) / budget
					end
					if not isFrag then points[#points + 1] = vec(px, py, pz) end
				end
			else
				if inside[i] then
					inside[i] = nil
					insideCount = insideCount - 1
					local h = openHit[i]
					if h then
						closeHit(h, B / budget, drawn - openDrawn[i])
						openHit[i] = nil
					end
					if insideCount == 0 and not isFrag then
						outputHole[#outputHole + 1] = vec(px, py, pz)
						events[#events + 1] = {kind = "exit", pos = vec(px, py, pz), box = i, e = B / budget}
						points[#points + 1] = vec(px, py, pz)
					end
				end
			end

			if endDisSqr then
				local ddx, ddy, ddz = px - cx, py - cy, pz - cz
				if ddx * ddx + ddy * ddy + ddz * ddz > endDisSqr then
					reason = "boundary"
					break
				end
			end
		end

		if not reason and not legEnded then
			reason = (insideCount == 0) and "exited" or "limit"
		end
	end

	-- boxes still open when the walk ended: lodged -> 0, maxpen/boundary/limit -> e now
	local eEnd = B / budget
	for i in pairs(inside) do
		local h = openHit[i]
		if h then
			closeHit(h, eEnd, drawn - openDrawn[i])
			openHit[i] = nil
		end
	end
	return reason, B, lx, ly, lz, dx, dy, dz, entered, deflects, stopBox
end

-- opts: { rng = function() -> 0..1 (default math.random),
--         maxpen = number (0 = no cap; v1 parity),
--         org = victim organism table or nil (read-only, bone integrity),
--         profile = V2.ResolveProfile(...) result or nil (nil: no expansion/fragments, bone x1),
--         onBox = function(event) -> absorbFraction|nil (armor rows only, at entry),
--         onHit = function(hit) (every non-armor hit, after the whole walk, entry order) }
-- result (all always present): v = 2, reason = "lodged"|"exited"|"maxpen"|"boundary"|"limit",
--   B0, Bend, e = Bend / B0, deflects, armored, expanded, fragments (count),
--   hits = { {box, organ, bone, class, pos, e (= eIn), eIn, eOut, dep (= eIn - eOut, less any
--             budget handed to fragments while inside the box), dir,
--             ricochet, frag = k|nil, share = fragB / B0|nil}, ... } (entry order; fragment
--             hits after the main round's; a fragment's e/eIn/eOut/dep are of its own budget),
--   events = { {kind = "entry"|"deflect"|"lodge"|"maxpen"|"exit"|"armor"|"expand"|"fragment",
--             pos, box, e, frag = k|nil, (fragment:) n, fragB}, ... },
--   segments = { {a, b, class, box, eIn, eOut, frag = k|nil}, ... },
--   lodges = { {pos, box, organ, bone, frag = k|nil, e = 0}, ... } (main round when lodged,
--             then each lodged fragment), hitBoxs, inputHole, outputHole, lastPos, outDir,
--   points. Holes, points, lastPos and outDir belong to the main round only.
function V2.Trace(startPos, dirNormal, B0, boxs, organs, center, endDis, opts)
	opts = opts or {}
	local T = V2.Tissue

	local res = {
		v = 2, reason = "exited", B0 = 0, Bend = 0, e = 0, deflects = 0,
		hits = {}, events = {}, segments = {}, hitBoxs = {}, inputHole = {}, outputHole = {},
		lastPos = nil, outDir = nil, armored = false, points = {},
		lodges = {}, fragments = 0, expanded = false,
	}
	local hits, events, points = res.hits, res.events, res.points
	local inputHole, outputHole = res.inputHole, res.outputHole

	local sx, sy, sz = startPos.x, startPos.y, startPos.z
	local dx, dy, dz = dirNormal.x, dirNormal.y, dirNormal.z
	local dl = math_sqrt(dx * dx + dy * dy + dz * dz)
	B0 = tonumber(B0) or 0
	if B0 ~= B0 or B0 < 0 then B0 = 0 end
	if B0 > V2.BudgetCap then B0 = V2.BudgetCap end
	res.B0 = B0

	if dl ~= dl or dl < 1e-6 then
		res.reason = "limit"
		res.lastPos, res.outDir = vec(sx, sy, sz), vec(0, 0, 0)
		inputHole[1], points[1] = vec(sx, sy, sz), vec(sx, sy, sz)
		return res
	end
	dx, dy, dz = dx / dl, dy / dl, dz / dl

	if B0 <= 0 then
		res.reason = "lodged"
		res.lastPos, res.outDir = vec(sx, sy, sz), vec(dx, dy, dz)
		inputHole[1], points[1] = vec(sx, sy, sz), vec(sx, sy, sz)
		events[1] = {kind = "lodge", pos = vec(sx, sy, sz), e = 0}
		res.lodges[1] = {pos = vec(sx, sy, sz), box = nil, organ = "flesh", bone = nil, frag = nil, e = 0}
		return res
	end

	local nBox = (type(boxs) == "table") and #boxs or 0
	V2.TagShapes(boxs, organs) -- organs2: which boxes are ellipsoids / capsules (once per ShootMatrix result)
	local prof = opts.profile
	if type(prof) ~= "table" then prof = NO_PROFILE end

	-- the main round's scratch set doubles as the per-trace context W
	local sc = acquireScratch()
	sc.boxs, sc.organs, sc.nBox, sc.org = boxs, organs, nBox, opts.org
	sc.rng = opts.rng or math.random
	sc.onBox = opts.onBox
	sc.maxpen = tonumber(opts.maxpen) or 0
	if center and endDis then
		sc.cx, sc.cy, sc.cz, sc.endDisSqr = center.x, center.y, center.z, endDis * endDis
	else
		sc.cx, sc.cy, sc.cz, sc.endDisSqr = nil, nil, nil, nil
	end
	sc.boneMul = tonumber(prof.boneMul) or 1
	sc.expMul = 1 + T.expandDrag * (tonumber(prof.expand) or 0)
	sc.fragChance = tonumber(prof.fragChance) or 0
	sc.fragMax = math_floor(tonumber(prof.fragMax) or 0)
	sc.B0 = B0
	sc.fragmented, sc.fragN, sc.fragList = false, 0, nil

	points[1] = vec(sx, sy, sz)
	local reason, B, lx, ly, lz, odx, ody, odz, entered, deflects, stopBox =
		walk(sc, res, sc, sx, sy, sz, dx, dy, dz, B0, B0, nil, nil, 0)

	if not entered then
		-- v1 parity (sv_hitboxorgans.lua:140-146): nothing hit -> both holes at the start
		inputHole[1] = vec(sx, sy, sz)
		outputHole[1] = vec(sx, sy, sz)
		lx, ly, lz = sx, sy, sz
	end

	local p = points[#points]
	if not p or p.x ~= lx or p.y ~= ly or p.z ~= lz then points[#points + 1] = vec(lx, ly, lz) end
	res.reason = reason or "limit"
	res.Bend = B
	res.e = B / B0
	res.deflects = deflects
	res.lastPos = vec(lx, ly, lz)
	res.outDir = vec(odx, ody, odz)
	local segments = res.segments
	if res.reason == "lodged" then
		appendLodge(res, sc, lx, ly, lz, odx, ody, odz, stopBox, segments[#segments], nil)
	end

	-- fragments: walked after the main round, each on its own budget, sharing one scratch set
	local nFrag = sc.fragN
	if nFrag > 0 then
		local fsc = acquireScratch()
		local list = sc.fragList
		for k = 1, nFrag do
			if k > 1 then clearScratch(fsc) end
			local d = list[k]
			local fReason, _, flx, fly, flz, fdx, fdy, fdz, _, _, fStop =
				walk(fsc, res, sc, sc.fragX, sc.fragY, sc.fragZ, d[1], d[2], d[3], sc.fragB, sc.fragB, k, sc.fragBox, sc.fragTravelled)
			-- an exited fragment is simply dropped: no hole, no world bullet
			if fReason == "lodged" then
				appendLodge(res, sc, flx, fly, flz, fdx, fdy, fdz, fStop, segments[#segments], k)
			end
		end
		releaseScratch(fsc)
	end
	releaseScratch(sc)

	local onHit = opts.onHit
	if onHit then
		for k = 1, #hits do
			local h = hits[k]
			if h.class ~= "armor" then onHit(h) end
		end
	end
	return res
end

-- v1-shaped traceResult for existing readers (killcam K.CopyPenetration wants v == 1,
-- an integer reason 1..5 and 1..20 points). The full v2 result rides along as .v2.
function V2.Compat(result)
	local r = REASON_CODE[result.reason] or 5
	if result.reason == "exited" and #result.hits == 0 then r = 5 end
	local pts = result.points or {}
	local n = #pts
	local out = {}
	if n <= COMPAT_POINTS then
		for i = 1, n do out[i] = pts[i] end
	else
		out[1] = pts[1]
		for k = 2, COMPAT_POINTS - 1 do
			out[k] = pts[1 + math_floor((k - 1) * (n - 1) / (COMPAT_POINTS - 1) + 0.5)]
		end
		out[COMPAT_POINTS] = pts[n]
	end
	if #out == 0 and result.lastPos then out[1] = result.lastPos end
	return {v = 1, reason = r, points = out, v2 = result}
end
