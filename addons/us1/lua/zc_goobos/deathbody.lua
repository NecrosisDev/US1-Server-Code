-- GoobOS death panel body view (UI cohesion U1, 2026-09-26): a translucent playermodel with its organs inside, tinted
-- by the damage each hit of this life did, up to the timeline's scrub time.
--
-- Two halves. The DATA half (DB.Damage, DB.At, DB.Top, DB.Cause, DB.Contributions, DB.Vitals) is pure Lua over what the
-- client already holds - the life sequence's clips and the observer debrief - so tests/lua/test_deathpanel.lua runs it
-- headless. The RENDER half (DB.Paint, DB.Release) draws a ClientsideModel inside a panel's rect; nothing in it runs at
-- load time.
if not CLIENT then return end
ZCGoobApps = ZCGoobApps or {}
local A = ZCGoobApps
local DB = A.DeathBody or {}
A.DeathBody = DB
DB.Version = "20260926.deathbody1"

-- Clip event kinds: sv_recorder.lua EV_SHOT / EV_HIT (the client compares the literals, cl_analysis.lua SHOT/HIT).
local SHOT, HIT = 1, 2
local MAX_ORGANS = 12 -- the recorder sends at most 12 crossed organs per hit
local DEDUPE_S = 0.08 -- two instances' clips overlap (8 s of pre-roll); `ago` is rounded to 0.1 s
local TISSUE = {flesh = true, organ = true, lung = true, dense = true, vessel = true, bone = true, armor = true}

-- Hit group -> the organ bones of that region, for clips cut before hits carried their crossed organs.
local REGIONS = {
    [1] = {"head", {"ValveBiped.Bip01_Head1"}},
    [2] = {"chest", {"ValveBiped.Bip01_Spine2"}},
    [3] = {"abdomen", {"ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Pelvis"}},
    [4] = {"left arm", {"ValveBiped.Bip01_L_UpperArm", "ValveBiped.Bip01_L_Forearm"}},
    [5] = {"right arm", {"ValveBiped.Bip01_R_UpperArm", "ValveBiped.Bip01_R_Forearm"}},
    [6] = {"left leg", {"ValveBiped.Bip01_L_Thigh", "ValveBiped.Bip01_L_Calf"}},
    [7] = {"right leg", {"ValveBiped.Bip01_R_Thigh", "ValveBiped.Bip01_R_Calf"}},
}
DB.Regions = REGIONS

local function finite(v) return type(v) == "number" and v == v and v > -math.huge and v < math.huge end
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
local function capital(s) return (string.gsub(s, "^%l", string.upper)) end
local function keyText(k)
    if finite(k) then return (k % 1 == 0) and string.format("%d", k) or tostring(k) end
    return isstring(k) and k or nil
end

-- clip.weapons is {{id, class}, ...} (v1 clips: a dictionary); V.Prepare leaves clip.weaponName when it has run.
local function weaponNames(clip)
    if istable(clip.weaponName) then return clip.weaponName end
    local names = {}
    if istable(clip.weapons) then
        for k, w in pairs(clip.weapons) do
            if istable(w) and isstring(w[2]) then names[tonumber(w[1]) or -1] = w[2]
            elseif isstring(w) then names[tonumber(k) or -1] = w end
        end
    end
    return names
end

local function actorIndex(clip, field, role)
    local i = tonumber(clip[field])
    if i then return i end
    if not istable(clip.actors) then return nil end
    for k, actor in ipairs(clip.actors) do
        if istable(actor) and actor.role == role then return k end
    end
    return nil
end

-- The crossed organs of one hit, type-checked: {bone, key, name, label, class, dep}. Armour is not the body.
local function organsOf(e)
    local list = e.organs
    if not istable(list) and istable(e.penetration) then list = e.penetration.organs end
    local out = {}
    if not istable(list) then return out end
    for n = 1, math.min(#list, MAX_ORGANS) do
        local o = list[n]
        local key = istable(o) and keyText(o.key)
        if key and isstring(o.bone) and o.bone ~= "" then
            local class = (isstring(o.class) and TISSUE[o.class]) and o.class or "organ"
            if class ~= "armor" then
                local name = isstring(o.name) and o.name ~= "" and o.name or "tissue"
                out[#out + 1] = {bone = o.bone, key = key, name = name, class = class,
                    label = isstring(o.label) and o.label ~= "" and o.label or capital(name),
                    dep = finite(o.dep) and clamp(o.dep, 0, 1) or nil}
            end
        end
    end
    return out
end

-- Each organ's share of one hit's damage: its recorded deposit (e.g. 0.42), shares without one split what the recorded
-- ones leave, and the result is normalised so a hit's shares always add up to the hit.
local function weights(rows)
    local known, missing = 0, 0
    for _, r in ipairs(rows) do if r.dep then known = known + r.dep else missing = missing + 1 end end
    local rest = missing > 0 and math.max(0, 1 - known) / missing or 0
    local sum = 0
    for _, r in ipairs(rows) do r.w = r.dep or rest sum = sum + r.w end
    for _, r in ipairs(rows) do r.w = sum > 0 and r.w / sum or 1 / #rows end
end

local function entryFor(out, key, spec)
    local entry = out.byOrgan[key]
    if entry then return entry end
    entry = {key = key, bone = spec.bone, bones = spec.bones, name = spec.name, label = spec.label, class = spec.class,
        region = spec.region == true, total = 0, steps = {}}
    out.byOrgan[key] = entry
    return entry
end

local function duplicate(out, inst, attacker, t, dmg, group)
    for _, ev in ipairs(out.events) do
        if ev.inst ~= inst and ev.attacker == attacker and ev.hitgroup == group and math.abs(ev.t - t) <= DEDUPE_S
            and math.abs(ev.dmg - dmg) < 0.05 then return true end
    end
    return false
end

local function collect(out, i, inst, span)
    local clip = inst.clip
    if not istable(clip) or not istable(clip.events) then return end
    local victim = actorIndex(clip, "target", "victim")
    if not victim then return end
    local killer = actorIndex(clip, "pov", "killer")
    local ago = finite(inst.ago) and inst.ago or 0
    local attacker = isstring(inst.attacker) and inst.attacker or "Someone"
    local names = weaponNames(clip)
    local shots = {}
    for _, e in ipairs(clip.events) do
        if istable(e) and e[2] == SHOT and finite(e[1]) and (not killer or e[3] == killer) then shots[#shots + 1] = e[1] end
    end
    for _, e in ipairs(clip.events) do
        if istable(e) and e[2] == HIT and e[4] == victim and (not killer or e[3] == killer) and finite(e[1]) then
            local before = ago - e[1] / 100 -- seconds before the death
            if before >= -0.05 then -- a hit on the corpse is not part of the life
                local t = clamp(span - before, 0, span)
                local dmg = finite(e[5]) and math.max(e[5], 0) or 0
                local group = finite(e[6]) and math.floor(e[6]) or nil
                if not duplicate(out, i, attacker, t, dmg, group) then
                    local shot = e.ballistic == 1 or istable(e.ballistics) or istable(e.penetration)
                    if not shot then
                        for _, at in ipairs(shots) do if at <= e[1] and e[1] - at <= 100 then shot = true break end end
                    end
                    local facts = istable(e.ballistics) and e.ballistics
                    local weapon = names[tonumber(e[7]) or -1]
                    out.events[#out.events + 1] = {t = t, inst = i, cs = e[1], attacker = attacker,
                        weapon = isstring(weapon) and weapon or (isstring(inst.wep) and inst.wep or nil), dmg = dmg,
                        hitgroup = group, shot = shot, range = facts and finite(facts.range) and facts.range or nil,
                        rows = organsOf(e), n = #out.events}
                end
            end
        end
    end
end

-- The damage of a whole life, from the clips alone:
--   events  = {{t (s into the life), inst, cs, attacker, weapon, dmg, hitgroup, shot, range, organs = {{entry, amount}}}}
--   byOrgan = {[bone .. "|" .. key] = {key, bone, name, label, class, total, steps = {{t, amount}, ...}}}; a hit with no
--             crossed-organ list tints its hit group's region instead: key = firstBone .. "|*", bones = {...}, region = true
--   order (entries by total, largest first), peak (the largest total), total (all damage), span
-- `span` is the life's length in seconds (the death is at t = span); without one the longest engagement is used.
function DB.Damage(seq, span)
    local out = {events = {}, byOrgan = {}, byName = {}, regionOf = {}, order = {}, total = 0, peak = 0, span = 1}
    local instances = istable(seq) and seq.instances
    if not istable(instances) then return out end
    if not finite(span) or span <= 0 then
        local most = 0
        for _, inst in ipairs(instances) do
            if istable(inst) and finite(inst.ago) then most = math.max(most, inst.ago) end
        end
        span = math.max(most, 1)
    end
    out.span = span
    for i, inst in ipairs(instances) do
        if istable(inst) then collect(out, i, inst, span) end
    end
    table.sort(out.events, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.n < b.n end)
    for _, ev in ipairs(out.events) do
        local rows, shares = ev.rows, {}
        if #rows > 0 then
            weights(rows)
            for _, r in ipairs(rows) do
                local entry = entryFor(out, r.bone .. "|" .. r.key, r)
                shares[#shares + 1] = {entry = entry, amount = ev.dmg * r.w}
                local byName = r.bone .. "|" .. r.name
                if not out.byName[byName] then out.byName[byName] = entry end
            end
        else
            local region = ev.hitgroup and REGIONS[ev.hitgroup]
            if region then
                local entry = entryFor(out, region[2][1] .. "|*", {bone = region[2][1], bones = region[2], name = region[1],
                    label = capital(region[1]), class = "flesh", region = true})
                for _, bone in ipairs(region[2]) do out.regionOf[bone] = entry end
                shares[1] = {entry = entry, amount = ev.dmg}
                ev.region = entry.label
            end
        end
        for _, share in ipairs(shares) do
            local steps = share.entry.steps
            steps[#steps + 1] = {ev.t, share.amount}
            share.entry.total = share.entry.total + share.amount
        end
        ev.organs, ev.rows = shares, nil
        out.total = out.total + ev.dmg
    end
    for _, entry in pairs(out.byOrgan) do
        out.order[#out.order + 1] = entry
        if entry.total > out.peak then out.peak = entry.total end
    end
    table.sort(out.order, function(a, b) if a.total ~= b.total then return a.total > b.total end return a.key < b.key end)
    return out
end

-- Cumulative damage per organ key at time t (seconds into the life; nil = the death), written into `out`.
-- Returns out and the damage of every hit up to t.
function DB.At(damage, t, out)
    out = out or {}
    for k in pairs(out) do out[k] = nil end
    if not istable(damage) or not istable(damage.byOrgan) or not istable(damage.events) then return out, 0 end
    if not finite(t) then t = math.huge end
    for key, entry in pairs(damage.byOrgan) do
        local v = 0
        for _, st in ipairs(entry.steps) do
            if st[1] > t then break end
            v = v + st[2]
        end
        out[key] = v
    end
    local sum = 0
    for _, ev in ipairs(damage.events) do
        if ev.t > t then break end
        sum = sum + ev.dmg
    end
    return out, sum
end

-- The n most damaged organs at time t: {{entry, amount}, ...} (reuses `out`; amounts above zero only).
local topCum = {}
function DB.Top(damage, t, n, out)
    out = out or {}
    local cum = DB.At(damage, t, topCum)
    local count = 0
    for _, entry in ipairs(istable(damage) and damage.order or {}) do
        local amount = cum[entry.key] or 0
        if amount > 0 then
            count = count + 1
            local row = out[count]
            if not row then row = {} out[count] = row end
            row.entry, row.amount = entry, amount
        end
    end
    for k = #out, count + 1, -1 do out[k] = nil end
    table.sort(out, function(a, b) if a.amount ~= b.amount then return a.amount > b.amount end return a.entry.key < b.entry.key end)
    for k = #out, (n or 5) + 1, -1 do out[k] = nil end
    return out
end

----------------------------------------------------------------------------------------------
-- The observer debrief (zc_observer/sv_observer.lua ZCObserverSnapshot): cause of death, final vitals, contributions.
----------------------------------------------------------------------------------------------
local BLEED_GAP = 3 -- seconds from the last hit to the death before it counts as "after the last hit"
local BLED_BELOW = 2900 -- mL: Z-City's own "I can't feel anything" line (organism sv_blood.lua); a full body is 5000
local KIND_CAUSE = {bullet = "Shot", slash = "Stabbed", blunt = "Blunt force", explosion = "Explosion", fall = "Fall",
    burn = "Burned", drown = "Drowned"}
local EXPLOSIVE = {"explos", "grenade", "rocket", "rpg", "c4", "bomb", "ied", "landmine", "claymore"}
local BLADE = {"knife", "machete", "bayonet", "dagger", "sword", "katana", "shiv", "hatchet", "axe", "cleaver", "blade"}
local BLUNT = {"hands", "fist", "punch", "crowbar", "bat", "pipe", "hammer", "wrench", "shovel", "baton", "club", "prop_", "brick", "sledge"}

local function matches(text, list)
    if not isstring(text) or text == "" then return false end
    text = string.lower(text)
    for _, word in ipairs(list) do if string.find(text, word, 1, true) then return true end end
    return false
end

-- One line saying how you died, from the debrief (snap, may be nil), the life's damage (DB.Damage), the ledger's
-- h2h.how (may be nil) and me = {sid = SteamID64}. Returns the line and a short kind ("bleed", "late", "self", ...).
-- Z-City's organism ends a life with Player:Kill(), so the ENGINE attacker is usually the victim: that alone never makes
-- a death self-inflicted while the life carries hits from someone else.
function DB.Cause(snap, damage, how, me)
    snap = istable(snap) and snap or nil
    me = istable(me) and me or {}
    local injuries = snap and istable(snap.injuries) and snap.injuries or {}
    local latest
    for _, hit in ipairs(injuries) do
        if istable(hit) and finite(hit.ago) and (not latest or hit.ago < latest.ago) then latest = hit end
    end
    local events = istable(damage) and istable(damage.events) and damage.events or {}
    local last = events[#events]
    local gap = latest and latest.ago or nil
    if not gap and istable(how) and finite(how.ago) and (how.ago > 0 or not last) then gap = how.ago end
    if not gap and last and finite(damage.span) then gap = math.max(0, damage.span - last.t) end
    local condition = snap and istable(snap.condition) and snap.condition
    local blood = condition and finite(condition.blood) and condition.blood or nil
    if gap and gap >= BLEED_GAP then
        local s = math.floor(gap + 0.5)
        if not blood or blood < BLED_BELOW then return string.format("Bled out %d s after the last hit", s), "bleed" end
        return string.format("Died %d s after the last hit", s), "late"
    end
    local others = #events > 0
    for _, hit in ipairs(injuries) do
        if istable(hit) and isstring(hit.sid) and hit.sid ~= "" and hit.sid ~= me.sid then others = true end
    end
    if latest and isstring(latest.sid) and latest.sid ~= "" and latest.sid == me.sid then return "Self-inflicted", "self" end
    if snap and snap.selfInflicted == true and not others and not latest then return "Self-inflicted", "self" end
    local kind = latest and isstring(latest.kind) and latest.kind or nil
    if kind and KIND_CAUSE[kind] then return KIND_CAUSE[kind], kind end
    local weapon = (istable(how) and isstring(how.weapon) and how.weapon ~= "" and how.weapon) or (last and last.weapon)
        or (latest and latest.weapon)
    if matches(weapon, EXPLOSIVE) or (snap and matches(snap.cause, EXPLOSIVE)) then return "Explosion", "explosion" end
    if last and last.shot then return "Shot", "bullet" end
    if matches(weapon, BLADE) then return "Stabbed", "slash" end
    if matches(weapon, BLUNT) then return "Blunt force", "blunt" end
    if not others and latest and latest.name == "Environment" then return "Fall", "fall" end
    return "Killed", "other"
end

-- Harm contributions: the n largest {name, harm, share} by attacker over the debrief's recent injuries, and the total.
function DB.Contributions(snap, n)
    local out, by, order, total = {}, {}, {}, 0
    local injuries = istable(snap) and istable(snap.injuries) and snap.injuries or {}
    for _, hit in ipairs(injuries) do
        if istable(hit) and finite(hit.harm) and hit.harm > 0 then
            local key = (isstring(hit.sid) and hit.sid ~= "") and hit.sid or tostring(hit.name or "?")
            local item = by[key]
            if not item then
                item = {name = isstring(hit.name) and hit.name ~= "" and hit.name or "Unknown", harm = 0}
                by[key] = item
                order[#order + 1] = item
            end
            item.harm, total = item.harm + hit.harm, total + hit.harm
        end
    end
    table.sort(order, function(a, b) if a.harm ~= b.harm then return a.harm > b.harm end return a.name < b.name end)
    for i = 1, math.min(n or 3, #order) do
        out[i] = {name = order[i].name, harm = order[i].harm, share = total > 0 and order[i].harm / total or 0}
    end
    return out, total
end

-- Final vitals {blood (mL), pulse, pain} or nil.
function DB.Vitals(snap)
    local c = istable(snap) and istable(snap.condition) and snap.condition
    if not c then return nil end
    local blood, pulse, pain = finite(c.blood) and c.blood or nil, finite(c.pulse) and c.pulse or nil, finite(c.pain) and c.pain or nil
    if not (blood or pulse or pain) then return nil end
    return {blood = blood, pulse = pulse, pain = pain}
end

----------------------------------------------------------------------------------------------
-- Render: one ClientsideModel of your own playermodel in its idle pose, drawn translucent inside a panel's rect with
-- its organ shapes (Z-City's hg.organism.DrawOrganShape) tinted by cumulative damage. Nothing here runs at load.
----------------------------------------------------------------------------------------------
local model, modelPath, boxes, retryAt = nil, nil, nil, 0
local tint, cumAt, cumFor, cumTime = nil, {}, nil, nil

function DB.Release()
    if IsValid(model) then model:Remove() end
    model, modelPath, boxes, cumFor, cumTime = nil, nil, nil, nil, nil
end

local function ensureModel(path)
    if IsValid(model) and modelPath == path then return model end
    DB.Release()
    if not isstring(path) or path == "" or RealTime() < retryAt then return nil end
    retryAt = RealTime() + 2
    if not util.IsValidModel(path) then return nil end
    local m = ClientsideModel(path, RENDERGROUP_OPAQUE)
    if not IsValid(m) then return nil end
    m:SetNoDraw(true)
    m:DrawShadow(false)
    m:SetIK(false)
    m:SetPos(vector_origin)
    m:SetAngles(angle_zero)
    local sequence = m:LookupSequence("idle_all_01")
    if not isnumber(sequence) or sequence < 0 then sequence = 0 end
    m:ResetSequence(sequence)
    m:SetCycle(0)
    m:SetPlaybackRate(0)
    m:InvalidateBoneCache()
    m:SetupBones()
    model, modelPath = m, path
    return m
end

-- The model's organ boxes, once per model (the pose never moves): {{box, key, byName, bone, class, depth}}.
local function organBoxes(m)
    if boxes ~= nil then return boxes end
    boxes = false
    local hgT = rawget(_G, "hg")
    local org = istable(hgT) and istable(hgT.organism) and hgT.organism
    if not org or not isfunction(org.GetHitBoxOrgans) or not isfunction(org.ShootMatrix) or not isfunction(org.DrawOrganShape) then return boxes end
    local organs = org.GetHitBoxOrgans(m:GetModel(), m)
    if not istable(organs) then return boxes end
    local list = org.ShootMatrix(m, organs)
    if not istable(list) then return boxes end
    local V2 = org.BallisticsV2
    if istable(V2) and isfunction(V2.TagShapes) then V2.TagShapes(list, organs) end
    local classify = istable(V2) and isfunction(V2.Classify) and V2.Classify
    local out = {}
    for _, box in ipairs(list) do
        local rows = box[6] ~= nil and organs[box[6]]
        local row = istable(rows) and rows[box[7]]
        if istable(row) and row[7] ~= true then
            out[#out + 1] = {box = box, bone = box[6], key = box[6] .. "|" .. tostring(box[7]),
                byName = box[6] .. "|" .. tostring(row[1]), class = classify and classify(row) or "organ", depth = 0}
        end
    end
    boxes = out
    return boxes
end

local function amountFor(damage, cum, b)
    local entry = damage.byOrgan[b.key] or damage.byName[b.byName] or damage.regionOf[b.bone]
    return entry and (cum[entry.key] or 0) or 0, entry
end

local function isHot(highlight, entry)
    if not entry or highlight == nil then return false end
    if istable(highlight) then return highlight[entry.key] == true end
    return highlight == entry.key
end

local function draw3D(m, x, y, w, h, damage, highlight, at)
    local T, K = A.Theme, A.Kit
    local reduced = K and K.Reduced and K.Reduced()
    local mins, maxs = m:OBBMins(), m:OBBMaxs()
    local center = (mins + maxs) * 0.5
    local halfH = (maxs.z - mins.z) * 0.54
    local halfW = math.max(maxs.x - mins.x, maxs.y - mins.y) * 0.55
    local fov = 30
    local tanH = math.tan(math.rad(fov / 2))
    local tanV = tanH * h / math.max(w, 1)
    local dist = math.max(halfH / tanV, halfW / tanH) + halfW
    local yaw = 215 + (reduced and 0 or math.sin(RealTime() * 0.2) * 14) -- 3/4 front, a very slow drift
    local ang = Angle(6, yaw, 0)
    local pos = center - ang:Forward() * dist
    cam.Start3D(pos, ang, fov, x, y, w, h, 1, dist * 4)
    DB.In3D = true
    render.ClearDepth()
    local list = organBoxes(m)
    if list and damage then
        if cumFor ~= damage or cumTime ~= at then DB.At(damage, at, cumAt) cumFor, cumTime = damage, at end
        local peak = damage.peak > 0 and damage.peak or 1
        for _, b in ipairs(list) do b.depth = (b.box[1] - pos):LengthSqr() end
        table.sort(list, function(p, q) return p.depth > q.depth end) -- back to front: translucent shapes blend in order
        tint = tint or Color(T.kill.r, T.kill.g, T.kill.b, T.kill.a)
        local pulse = reduced and 1 or (0.5 + 0.5 * math.sin(RealTime() * 6))
        local drawShape = rawget(_G, "hg").organism.DrawOrganShape
        for _, b in ipairs(list) do
            local amount, entry = amountFor(damage, cumAt, b)
            local f = clamp(amount / peak, 0, 1)
            local base = T.tissue[b.class] or T.tissue.organ
            tint.r, tint.g, tint.b = Lerp(f, base.r, T.kill.r), Lerp(f, base.g, T.kill.g), Lerp(f, base.b, T.kill.b)
            tint.a = 22 + 190 * f
            if isHot(highlight, entry) then
                tint.r, tint.g, tint.b = Lerp(0.35 * pulse, tint.r, T.white.r), Lerp(0.35 * pulse, tint.g, T.white.g), Lerp(0.35 * pulse, tint.b, T.white.b)
                tint.a = math.min(255, tint.a + 40 + 60 * pulse)
            end
            drawShape(b.box, tint, true)
        end
    end
    render.SuppressEngineLighting(true)
    render.ResetModelLighting(0.6, 0.6, 0.6)
    render.SetColorModulation(T.muted.r / 255, T.muted.g / 255, T.muted.b / 255)
    render.SetBlend(0.18)
    m:DrawModel()
end

-- Draw the body into panel-local (x, y, w, h). damage = DB.Damage(...); highlightKey = an organ key or a set of keys
-- ({[key] = true}) that pulses; at = the scrub time (nil = the death). Returns true when a frame was drawn. Every piece
-- of render state it touches is reset whatever happens inside.
function DB.Paint(panel, x, y, w, h, damage, highlightKey, at)
    if not IsValid(panel) or not w or not h or w < 16 or h < 16 then return false end
    local ply = LocalPlayer()
    local m = IsValid(ply) and ensureModel(ply:GetModel())
    if not m then return false end
    local sx, sy = panel:LocalToScreen(x, y)
    sx, sy, w, h = math.floor(sx), math.floor(sy), math.floor(w), math.floor(h)
    DB.In3D = false
    render.SetScissorRect(sx, sy, sx + w, sy + h, true)
    local ok, err = pcall(draw3D, m, sx, sy, w, h, damage, highlightKey, at)
    if DB.In3D then
        render.SetBlend(1)
        render.SetColorModulation(1, 1, 1)
        render.SuppressEngineLighting(false)
        cam.IgnoreZ(false)
        cam.End3D()
        DB.In3D = false
    end
    render.SetScissorRect(0, 0, 0, 0, false)
    if not ok then
        if not DB.ErrSaid then DB.ErrSaid = true print("[GoobOS] death panel body view: " .. tostring(err)) end
        return false
    end
    return true
end
