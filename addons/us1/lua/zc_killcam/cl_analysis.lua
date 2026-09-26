-- Z-City killcam, phase 3: turns a clip into answers. Pure Lua on purpose (no engine calls),
-- so the same code is tested headlessly. The viewer draws what this file concludes:
-- who acted first, whether the victim was a threat, and a plain-language timeline.
ZCKillcamView = ZCKillcamView or {}
local V = ZCKillcamView

local SHOT, HIT, DEATH = 1, 2, 3
local F_ALIVE, F_RAGDOLL = 1, 4
local AIM_CONE, AIM_RANGE, AIM_HOLD = 7, 2500, 5 -- degrees, units, consecutive 0.1 s samples
local HITGROUPS
function V.HitGroupName(id) return HITGROUPS[id] or "" end
HITGROUPS = {[1] = "head", [2] = "chest", [3] = "stomach", [4] = "left arm", [5] = "right arm", [6] = "left leg", [7] = "right leg"}

local floor, abs, sqrt, deg, atan2 = math.floor, math.abs, math.sqrt, math.deg, math.atan2 or math.atan
local function angdiff(a, b) return (a - b + 180) % 360 - 180 end
local function hasFlag(flags, bit) return floor(flags / bit) % 2 == 1 end
V.HasFlag = hasFlag

-- Interpolated state of one actor at `cs` (centiseconds from the death). nil when the actor is not in the clip then.
function V.EyeAt(a, b, f)
    if not (a[13] and b[13]) or a[13] == 0 or b[13] == 0 then return end -- 0: the recorder did not know it
    return (a[11] + (b[11] - a[11]) * f) / 10, (a[12] + (b[12] - a[12]) * f) / 10, (a[13] + (b[13] - a[13]) * f) / 10
end
-- The two rows around `cs` and the blend between them. Shared so a caller that wants both the state and the pose pays
-- for one binary search, not two: pose() runs this per ghost per frame.
local function findRows(s, cs)
    local n = #s
    if n == 0 or cs < s[1][1] or cs > s[n][1] then return end
    local lo, hi = 1, n
    while hi - lo > 1 do
        local mid = floor((lo + hi) / 2)
        if s[mid][1] <= cs then lo = mid else hi = mid end
    end
    local a, b = s[lo], s[hi]
    local f = b[1] > a[1] and (cs - a[1]) / (b[1] - a[1]) or 0
    if f < 0 then f = 0 elseif f > 1 then f = 1 end
    return a, b, f
end
local function find(actor, cs) return findRows(actor.s, cs) end
V.RowsAt = find
-- Optional custom body-facing track; mode 0 explicitly returns to native posing.
function V.AnimationAt(actor, cs)
    if not actor.anim then return end
    local a, b, f = findRows(actor.anim, cs)
    if not a then return end
    local from = f < 1 and a or b
    local mode = from[3]
    if mode == 0 or mode == 4 then return nil, mode end
    local yaw = from[2] / 100
    if a[3] == b[3] then yaw = a[2] / 100 + angdiff(b[2] / 100, a[2] / 100) * f end
    return yaw, mode
end
-- Index immutable sample rows once, so seeking does not depend on which frame was drawn first.
local function weaponRuns(actor)
    if actor._weaponRows == actor.s then return actor._weaponRuns, actor._reloadRuns end
    local weapons, reloads, activeWeapon, activeReload = {}, {}, nil, nil
    for _, row in ipairs(actor.s) do
        local t, weapon = row[1], row[8]
        if not activeWeapon or activeWeapon[3] ~= weapon then
            if activeWeapon then activeWeapon[2] = t end
            -- The first sample does not prove an equip happened there: allow earlier events in the clip.
            activeWeapon = {#weapons == 0 and -math.huge or t, math.huge, weapon}
            weapons[#weapons + 1] = activeWeapon
        end
        if activeReload and (activeReload[3] ~= weapon or not hasFlag(row[7], 32)) then
            activeReload[2] = t; activeReload = nil
        end
        if not activeReload and hasFlag(row[7], 32) then
            activeReload = {t, math.huge, weapon}
            reloads[#reloads + 1] = activeReload
        end
    end
    actor._weaponRows, actor._weaponRuns, actor._reloadRuns = actor.s, weapons, reloads
    return weapons, reloads
end
local function runAt(runs, cs)
    local lo, hi = 1, #runs
    if hi == 0 or cs < runs[1][1] then return end
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if runs[mid][1] <= cs then lo = mid else hi = mid - 1 end
    end
    local run = runs[lo]
    if cs < run[2] then return run end
end
function V.WeaponWindow(actor, cs)
    if not find(actor, cs) then return end
    local weapons = weaponRuns(actor)
    local run = runAt(weapons, cs)
    if run then return run[3], run[1], run[2] end
end
function V.ReloadAt(actor, cs)
    if not find(actor, cs) then return end
    local _, reloads = weaponRuns(actor)
    local run = runAt(reloads, cs)
    if run then return run[1], run[3] end
end
function V.StateAt(actor, cs)
    local a, b, f = find(actor, cs)
    if not a then return end
    local from = f < 1 and a or b
    local ya, yb, pa, pb = a[5] + (a[14] or 0) / 100, b[5] + (b[14] or 0) / 100, a[6] + (a[15] or 0) / 100, b[6] + (b[15] or 0) / 100 -- whole degrees + hundredths
    -- Straight lines between samples, on purpose. At 30 Hz two samples are 33 ms apart, so the worst case - a body in
    -- free fall - is off by g*dt^2/8 = 0.08 units at the midpoint. A cubic through the recorded velocities would be
    -- exact and is not worth the arithmetic per ghost per frame.
    return a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f, a[4] + (b[4] - a[4]) * f,
        ya + angdiff(yb, ya) * f, pa + (pb - pa) * f, from[7], from[8], from[9],
        (a[10] or 64) + ((b[10] or 64) - (a[10] or 64)) * f, -- eye height, for the attacker's-view replay
        V.EyeAt(a, b, f) -- the gamemode's real first-person eye, when the clip has it: x, y, z from the actor's position
end

-- What the body was doing: the recorded velocity, and the sequence the server itself was playing. Clips cut before
-- 2026-09-22 have none of it, and answer nil so the caller can fall back to differencing positions.
--   vx, vy, vz  units per second
--   seq         sequence index on the actor's OWN model, so only usable on a ghost wearing that model; nil if unknown
--   cyc         0..1 through that sequence. Custom tracks distinguish forward loops, one-shots and reversed entry;
--               legacy tracks infer wrapping only across large cycle discontinuities.
function V.MotionAt(actor, cs)
    local a, b, f = find(actor, cs)
    if not a or a[16] == nil then return end
    local seq = (f < 1 and a or b)[19]
    local ca, cb = (a[20] or 0) / 1000, (b[20] or 0) / 1000
    local _, ma = V.AnimationAt(actor, a[1])
    local _, mb = V.AnimationAt(actor, b[1])
    local cycle = f < 1 and ca or cb
    if f > 0 and f < 1 and a[19] == b[19] and ma == mb then
        local delta = cb - ca
        if ma == 2 then
            if delta < 0 then delta = delta + 1 end
        elseif (ma == 1 or ma == 4) and delta < 0 then
            delta = 0 -- the same one-shot restarted; hold until its new sample, never run it backwards
        elseif ma ~= 1 and ma ~= 3 and ma ~= 4 then
            -- Legacy recordings have no direction metadata. Only a large
            -- discontinuity is a wrap; a small decrease can be reverse playback.
            if delta < -0.5 then delta = delta + 1 elseif delta > 0.5 then delta = delta - 1 end
        end
        cycle = ca + delta * f
        if ma == 1 or ma == 3 or ma == 4 then cycle = math.max(0, math.min(1, cycle))
        elseif cycle < 0 or cycle > 1 then cycle = cycle % 1 end
    end
    -- Do not modulo exact endpoints: a completed one-shot must retain frame 1.
    return a[16] + (b[16] - a[16]) * f, a[17] + (b[17] - a[17]) * f, a[18] + (b[18] - a[18]) * f,
        (seq and seq >= 0) and seq or nil, cycle
end

-- Optional numeric sidecar: grip/carry state is discrete; position/aim blend
-- only within the same carry mode. A release or seek never keeps a stale hand.
function V.HandsAt(actor, cs)
    local rows = actor.hands
    if not rows or #rows == 0 or cs < rows[1][1] then return 0, 0 end
    local lo, hi = 1, #rows
    while lo < hi do
        local mid = floor((lo + hi + 1) / 2)
        if rows[mid][1] <= cs then lo = mid else hi = mid - 1 end
    end
    local a, b = rows[lo], rows[lo + 1] or rows[lo]
    local f = a[3] == b[3] and b[1] > a[1] and math.Clamp((cs - a[1]) / (b[1] - a[1]), 0, 1) or 0
    return a[2], a[3], (a[4] + (b[4] - a[4]) * f) / 10,
        (a[5] + (b[5] - a[5]) * f) / 10, (a[6] + (b[6] - a[6]) * f) / 10,
        (a[7] + (b[7] - a[7]) * f) / 100, a[8] / 100 + angdiff(b[8] / 100, a[8] / 100) * f
end

-- The recorded pose parameters at `cs`, written into the caller's table (no allocation on the draw path) and indexed
-- the way the model indexes them, which is why the ghost may only apply them while it wears the recorded model.
-- Returns how many were written; 0 when the clip has none.
function V.PoseAt(actor, cs, out)
    local a, b, f = find(actor, cs)
    if not a then return 0 end
    local n = 0
    for k = 21, #a do
        local bv = b[k]
        if bv == nil then break end
        n = n + 1
        out[n] = (a[k] + (bv - a[k]) * f) / 100
    end
    return n
end

-- The two recorded ragdoll frames around `cs` and the blend between them. nil when the actor has none then.
function V.RagAt(actor, cs)
    local f = actor.rag and actor.rag.f
    if not f or #f == 0 or cs < f[1][1] - 20 then return end
    local lo, hi = 1, #f
    if cs >= f[hi][1] then return f[hi], f[hi], 0 end
    if cs <= f[1][1] then return f[1], f[1], 0 end
    while hi - lo > 1 do
        local mid = floor((lo + hi) / 2)
        if f[mid][1] <= cs then lo = mid else hi = mid end
    end
    local a, b = f[lo], f[hi]
    return a, b, b[1] > a[1] and (cs - a[1]) / (b[1] - a[1]) or 0
end

local function pretty(class) return class and (string.gsub(class, "^weapon_", "")) or "nothing" end
function V.Unarmed(clip, wep)
    local class = clip.weaponName[wep]
    return not class or string.find(class, "hand", 1, true) ~= nil or string.find(class, "fist", 1, true) ~= nil
end

-- Normalises a decoded clip in place: labels, weapon lookup, who the victim and killer are.
function V.Prepare(clip)
    clip.weaponName = {}
    for k, w in pairs(clip.weapons or {}) do
        if type(w) == "table" then clip.weaponName[tonumber(w[1])] = w[2] else clip.weaponName[tonumber(k)] = w end -- v1 clips used a dictionary
    end
    local anon = 0
    for i, actor in ipairs(clip.actors) do
        actor.named = actor.role ~= "bystander"
        if actor.named then actor.label = actor.name or actor.role else anon = anon + 1 actor.label = "Bystander " .. anon end
        if actor.role == "victim" then clip.victim = i elseif actor.role == "killer" then clip.killer = i end
    end
    clip.pre = clip.pre or 8
    clip.first, clip.last = -clip.pre * 100, (clip.len - clip.pre) * 100
    return clip
end

local function label(clip, i) local a = clip.actors[i] return a and a.label or "someone outside the clip" end

-- Who `actor` is pointing their view at, if anyone: nearest actor inside a narrow cone on the same floor.
local function aimedAt(clip, i, cs)
    local x, y, z, yaw, _, flags, wep = V.StateAt(clip.actors[i], cs)
    if not x or not hasFlag(flags, F_ALIVE) or hasFlag(flags, F_RAGDOLL) or V.Unarmed(clip, wep) then return end
    local best, bestDist
    for j, other in ipairs(clip.actors) do
        if j ~= i then
            local ox, oy, oz, _, _, oflags = V.StateAt(other, cs)
            if ox and hasFlag(oflags, F_ALIVE) and abs(oz - z) < 150 then
                local dx, dy = ox - x, oy - y
                local dist = sqrt(dx * dx + dy * dy)
                if dist > 1 and dist < AIM_RANGE and abs(angdiff(deg(atan2(dy, dx)), yaw)) < AIM_CONE and (not bestDist or dist < bestDist) then
                    best, bestDist = j, dist
                end
            end
        end
    end
    return best
end
V.AimedAt = aimedAt

-- Sustained aim: {a = actor, b = target, from = cs, to = cs}. A flick across someone is not "aiming at" them.
function V.AimRuns(clip)
    local runs = {}
    for i, actor in ipairs(clip.actors) do
        if actor.named then
            local target, from, count
            local function close(cs) if target and count >= AIM_HOLD then runs[#runs + 1] = {a = i, b = target, from = from, to = cs} end end
            for cs = clip.first, clip.last, 10 do
                local now = aimedAt(clip, i, cs)
                if now ~= target then close(cs) target, from, count = now, cs, 0 end
                if now then count = count + 1 end
            end
            close(clip.last)
        end
    end
    return runs
end

local function distance(clip, a, b, cs)
    if not clip.actors[a] or not clip.actors[b] then return end
    local x, y, z = V.StateAt(clip.actors[a], cs)
    local ox, oy, oz = V.StateAt(clip.actors[b], cs)
    if not x or not ox then return end
    return sqrt((ox - x) ^ 2 + (oy - y) ^ 2 + (oz - z) ^ 2)
end

-- The readable timeline: {cs, text, kind, a, b}. kind: "shot" "hit" "death" "draw" "aim" "down".
function V.BuildLog(clip, runs)
    local log = {}
    local function add(cs, kind, a, b, text) log[#log + 1] = {cs = cs, kind = kind, a = a, b = b, text = text, n = #log} end
    for i, actor in ipairs(clip.actors) do
        if actor.named then
            local wep, down, loading
            for k, row in ipairs(actor.s) do
                local reloading = hasFlag(row[7], 32)
                if reloading and not loading and k > 1 then add(row[1], "draw", i, nil, actor.label .. " started reloading") end
                loading = reloading
                if row[8] ~= wep then
                    local armed = not V.Unarmed(clip, row[8])
                    if k == 1 then
                        if armed then add(row[1], "draw", i, nil, actor.label .. " is already holding " .. pretty(clip.weaponName[row[8]])) end
                    elseif armed then add(row[1], "draw", i, nil, actor.label .. " drew " .. pretty(clip.weaponName[row[8]]))
                    elseif wep and not V.Unarmed(clip, wep) then add(row[1], "draw", i, nil, actor.label .. " put the weapon away") end
                    wep = row[8]
                end
                local isDown = hasFlag(row[7], F_RAGDOLL) and hasFlag(row[7], F_ALIVE)
                if isDown and not down and k > 1 then add(row[1], "down", i, nil, actor.label .. " went down") end
                down = isDown
            end
        end
    end
    for _, run in ipairs(runs or V.AimRuns(clip)) do
        add(run.from, "aim", run.a, run.b, string.format("%s aimed at %s for %.1fs", label(clip, run.a), label(clip, run.b), (run.to - run.from) / 100))
    end
    local lastShot = {}
    for _, e in ipairs(clip.events) do
        local cs, kind, a, b = e[1], e[2], e[3], e[4]
        if kind == SHOT then
            local prev = lastShot[a]
            if prev and cs - prev.till <= 100 then
                prev.count, prev.till = prev.count + 1, cs
                prev.text = string.format("%s fired %s x%d", label(clip, a), prev.wep, prev.count)
            else
                add(cs, "shot", a, nil, label(clip, a) .. " fired " .. pretty(clip.weaponName[e[7]]))
                local entry = log[#log]
                entry.count, entry.till, entry.wep = 1, cs, pretty(clip.weaponName[e[7]])
                lastShot[a] = entry
            end
        elseif kind == HIT then
            local dist = distance(clip, a, b, cs)
            add(cs, "hit", a, b, string.format("%s hit %s: %s, %s dmg%s, %s", label(clip, a), label(clip, b), HITGROUPS[e[6]] or "body",
                tostring(e[5]), dist and string.format(", %du away", dist) or "", e[8] == 1 and "clear view" or "THROUGH COVER"))
        elseif kind == DEATH then
            add(cs, "death", b, a, label(clip, b) .. " died" .. (a > 0 and (" (last hit by " .. label(clip, a) .. ")") or ""))
        end
    end
    table.sort(log, function(p, q) if p.cs ~= q.cs then return p.cs < q.cs end return p.n < q.n end)
    return log
end

local function stamp(cs) return string.format("%+.1fs", cs / 100) end

-- The facts a reviewer asks first. tone: "bad" counts against the killer, "good" for them, nil neutral.
function V.Findings(clip, runs)
    local out = {}
    local function add(name, value, tone) out[#out + 1] = {name = name, value = value, tone = tone} end
    local vi, ki = clip.victim, clip.killer
    if not vi or not ki then return out end
    local victim, killer = clip.actors[vi].label, clip.actors[ki].label
    local firstShot, firstHit, victimShot, victimHit
    local dealt, taken, covered, hits = 0, 0, 0, 0
    for _, e in ipairs(clip.events) do
        local cs, kind, a, b = e[1], e[2], e[3], e[4]
        if cs <= 0 then
            if kind == SHOT then
                firstShot = firstShot or e
                if a == vi then victimShot = victimShot or e end
            elseif kind == HIT then
                if a == ki and b == vi then
                    firstHit = firstHit or e
                    dealt, hits = dealt + e[5], hits + 1
                    if e[8] ~= 1 then covered = covered + 1 end
                elseif a == vi and b == ki then
                    victimHit = victimHit or e
                    taken = taken + e[5]
                end
            end
        end
    end
    local mark = firstHit and firstHit[1] or 0
    add("First shot", firstShot and (label(clip, firstShot[3]) .. " at " .. stamp(firstShot[1])) or "no shots recorded")
    if victimHit and victimHit[1] < mark then
        add("Victim hurt killer first", string.format("yes, %s dmg at %s", tostring(victimHit[5]), stamp(victimHit[1])), "good")
    elseif victimShot and victimShot[1] < mark then
        add("Victim fired first", "yes, at " .. stamp(victimShot[1]), "good")
    else
        add("Victim attacked killer first", "no", "bad")
    end
    local _, _, _, vyaw, _, _, vwep = V.StateAt(clip.actors[vi], mark)
    if vwep then
        local unarmed = V.Unarmed(clip, vwep)
        add("Victim at first hit", unarmed and "unarmed" or ("holding " .. pretty(clip.weaponName[vwep])), unarmed and "bad" or nil)
    end
    local threatened
    for _, run in ipairs(runs or V.AimRuns(clip)) do
        if run.a == vi and run.b == ki and run.from < mark then threatened = run break end
    end
    add("Victim aimed at killer before it", threatened and string.format("yes, from %s for %.1fs", stamp(threatened.from), (threatened.to - threatened.from) / 100) or "no", threatened and "good" or nil)
    if firstHit then
        local kx, ky = V.StateAt(clip.actors[ki], mark)
        local vx, vy = V.StateAt(clip.actors[vi], mark)
        if kx and vx and vyaw then
            local off = abs(angdiff(deg(atan2(ky - vy, kx - vx)), vyaw))
            add("Victim was facing", off < 60 and "the killer" or (off > 120 and "away (hit from behind)" or "side-on"), off > 120 and "bad" or nil)
        end
        local dist = distance(clip, ki, vi, mark)
        add("First hit", string.format("%s%s, %s", stamp(mark), dist and string.format(" from %du", dist) or "", firstHit[8] == 1 and "clear view" or "through cover"))
        if clip.pov then -- one instance from a life sequence: there is no death in it
            add("This burst", string.format("%d hits, %s dmg", hits, tostring(floor(dealt * 10) / 10)))
        else
            add("First hit to death", string.format("%.1fs, %d hits, %s dmg", -mark / 100, hits, tostring(floor(dealt * 10) / 10)))
        end
        if covered > 0 then add("Hits without line of sight", covered .. " of " .. hits, "bad") end
    else
        add("First hit", "outside this clip (older than " .. clip.pre .. "s)")
    end
    if taken > 0 then add("Damage " .. victim .. " dealt to " .. killer, tostring(floor(taken * 10) / 10)) end
    return out
end
