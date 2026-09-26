-- luajit tests/lua/test_deathpanel.lua <repo root>: the death panel's damage timeline data (zc_goobos/deathbody.lua,
-- UI cohesion U1 2026-09-26). Loads the body view on the GMod stubs without any 3D call, then checks DB.Damage, DB.At,
-- DB.Top, DB.Cause and DB.Contributions on a fake life.
local root = arg[1] or "."
dofile(root .. "/tests/lua/gmod_stub.lua")
ZCGoobApps = {Theme = {bg = Color(29, 26, 26), card = Color(38, 35, 35), text = Color(225, 225, 225), muted = Color(165, 165, 165),
    accent = Color(192, 0, 0), main = Color(150, 0, 0), green = Color(119, 218, 181), gold = Color(247, 199, 115),
    red = Color(255, 143, 159), line = Color(90, 20, 20)}}
dofile(root .. "/addons/us1/lua/zc_goobos/kit.lua")

-- Any 3D entry point touched while the file loads fails the test.
local function trap(name) return setmetatable({}, {__index = function(_, k) error("3D call at load: " .. name .. "." .. tostring(k), 2) end}) end
cam, render = trap("cam"), trap("render")
function ClientsideModel() error("ClientsideModel at load", 2) end
dofile(root .. "/addons/us1/lua/zc_goobos/deathbody.lua")
local DB = ZCGoobApps.DeathBody
assert(istable(DB) and isfunction(DB.Damage) and isfunction(DB.Paint) and isfunction(DB.Release), "deathbody loaded")

local function eq(a, b, msg) if a ~= b then error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end
local function near(a, b, msg) if math.abs(a - b) > 1e-6 then error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local HEART = {bone = "ValveBiped.Bip01_Spine2", key = 7, name = "heart", label = "Heart", class = "dense", dep = 0.6}
local LUNG = {bone = "ValveBiped.Bip01_Spine2", key = 5, name = "lungsR", label = "Right lung", class = "lung", dep = 0.4}
local LIVER = {bone = "ValveBiped.Bip01_Spine", key = 1, name = "liver", label = "Liver", class = "dense"}
local VEST = {bone = "ValveBiped.Bip01_Spine2", key = 1, name = "vest1", label = "Armored vest", class = "armor", dep = 0.9}

-- Two instances by the same attacker whose clips overlap (the second clip's pre-roll holds the first one's hit), one
-- hit with the new e.organs list, one with the older e.penetration.organs, one with no list (hit group fallback), a
-- shotgun hit, a hit on someone else, a corpse hit after the death, and malformed rows.
local actors = {{role = "killer", name = "Rex"}, {role = "victim", name = "Me"}, {role = "bystander"}}
local seq = {instances = {
    {attacker = "Rex", wep = "weapon_akm", dmg = 50, hits = 2, ago = 10, clip = {pov = 1, target = 2, actors = actors,
        weapons = {{3, "weapon_akm"}}, events = {
            {-2, 1, 1, 0, 0, 0, 3},                                                       -- a shot 0.02 s before the hit
            {0, 2, 1, 2, 30, 2, 3, 1, organs = {HEART, LUNG, VEST}},                      -- t = 20
            {150, 2, 1, 2, 20, 3, 3, 1, penetration = {v = 1, organs = {LIVER}}},        -- t = 21.5
            {160, 2, 1, 3, 99, 1, 3, 1},                                                  -- hits a bystander
            {170, 2, 2, 1, 99, 1, 3, 1},                                                  -- the victim hits back
        }}},
    {attacker = "Rex", wep = "weapon_akm", dmg = 40, hits = 2, ago = 3, clip = {pov = 1, target = 2, actors = actors,
        weapons = {{3, "weapon_akm"}, {4, "weapon_remington870"}}, events = {
            {-700, 2, 1, 2, 30, 2, 3, 1, organs = {HEART, LUNG, VEST}},                   -- the first instance's hit again
            {0, 2, 1, 2, 25, 1, 4, 1},                                                    -- t = 27, no organs: head region
            {100, 2, 1, 2, 15, 6, 4, 1},                                                  -- t = 28, left leg region
            {500, 2, 1, 2, 70, 1, 4, 1},                                                  -- after the death: a corpse hit
            "junk", {nil, 2}, {math.huge, 2, 1, 2, 5, 1},
        }}},
    "not an instance", {ago = 1}, {ago = 2, clip = {events = "no"}},
}}
local span = 30
local dmg = DB.Damage(seq, span)
eq(#dmg.events, 4, "four hits on the victim, the overlap counted once, the corpse and others' hits dropped")
local times = {}
for i, ev in ipairs(dmg.events) do times[i] = ev.t end
near(times[1], 20, "t = span - (ago - cs / 100)"); near(times[2], 21.5, "second hit"); near(times[3], 27, "third"); near(times[4], 28, "fourth")
eq(dmg.events[1].shot, true, "a shot just before the hit marks it as a gunshot")
eq(dmg.events[3].weapon, "weapon_remington870", "weapon resolved through clip.weapons")
near(dmg.total, 30 + 20 + 25 + 15, "total damage")

-- per-organ totals sum to each hit's damage; armour takes none; recorded deposits split the hit (0.6 / 0.4)
local heart = dmg.byOrgan["ValveBiped.Bip01_Spine2|7"]
local lung = dmg.byOrgan["ValveBiped.Bip01_Spine2|5"]
local liver = dmg.byOrgan["ValveBiped.Bip01_Spine|1"]
assert(heart and lung and liver, "organ entries keyed bone|key")
eq(dmg.byOrgan["ValveBiped.Bip01_Spine2|1"], nil, "armour is not the body")
near(heart.total, 18, "heart share"); near(lung.total, 12, "lung share"); near(liver.total, 20, "a lone organ takes the whole hit")
eq(heart.label, "Heart", "label kept")
-- hit group fallback for clips without a crossed-organ list
local head = dmg.byOrgan["ValveBiped.Bip01_Head1|*"]
local leg = dmg.byOrgan["ValveBiped.Bip01_L_Thigh|*"]
assert(head and head.region and leg and leg.region, "hit group regions")
near(head.total, 25, "head region"); near(leg.total, 15, "leg region")
eq(dmg.regionOf["ValveBiped.Bip01_L_Calf"], leg, "a region covers all of its bones")
eq(dmg.events[3].region, "Head", "the event names its region")
local sum = 0
for _, entry in pairs(dmg.byOrgan) do sum = sum + entry.total end
near(sum, dmg.total, "organ totals add up to the hits")
eq(dmg.order[1], head, "order: largest total first"); eq(dmg.order[2], liver, "then the liver")
near(dmg.peak, 25, "peak = the largest organ total")

-- cumulative totals are monotonic in time and end at the totals
local prev, prevSum = {}, -1
for t = 0, span + 1, 0.25 do
    local cum, total = DB.At(dmg, t, {})
    assert(total >= prevSum, "cumulative damage never falls")
    for key, v in pairs(cum) do assert(v >= (prev[key] or 0) - 1e-9, "organ " .. key .. " never falls") prev[key] = v end
    prevSum = total
end
local cum, total = DB.At(dmg, nil, {})
near(total, dmg.total, "nil = at the death")
for key, entry in pairs(dmg.byOrgan) do near(cum[key], entry.total, "cumulative ends at the total for " .. key) end
local early = DB.At(dmg, 21, {})
near(early[heart.key], 18, "the heart is hit at 20"); near(early[liver.key], 0, "the liver not yet")
-- the most damaged organs up to a time
local top = DB.Top(dmg, 21, 5, {})
eq(#top, 2, "two organs hit by t = 21"); eq(top[1].entry, heart, "heart first")
top = DB.Top(dmg, nil, 2, top)
eq(#top, 2, "top n is capped"); eq(top[1].entry, head, "the head region leads at the death")

-- deposits that do not add up to 1 are normalised; missing deposits share what is left
local odd = DB.Damage({instances = {{attacker = "A", ago = 1, clip = {pov = 1, target = 2, actors = actors, events = {
    {0, 2, 1, 2, 10, 2, 0, 1, organs = {{bone = "B", key = 1, name = "a", dep = 0.2}, {bone = "B", key = 2, name = "b"}, {bone = "B", key = "x", name = "c", dep = "bad"}}},
    {10, 2, 1, 2, 8, 2, 0, 1, organs = {{bone = "B", key = 1, name = "a", dep = 0.1}, {bone = "B", key = 2, name = "b", dep = 0.1}}},
}}}}}, 5)
local osum = 0
for _, entry in pairs(odd.byOrgan) do osum = osum + entry.total end
near(osum, 18, "shares always add up to the hit")
near(odd.byOrgan["B|2"].total, 10 * 0.4 + 4, "missing deposits share the rest")

-- a victim found by role when clip.target is missing; no killer index = every hit on the victim
local byRole = DB.Damage({instances = {{attacker = "A", ago = 2, clip = {actors = {{role = "victim"}, {role = "bystander"}}, events = {{0, 2, 2, 1, 7, 7, 0}}}}}})
eq(#byRole.events, 1, "victim by role"); near(byRole.span, 2, "span defaults to the longest engagement")
near(byRole.byOrgan["ValveBiped.Bip01_R_Thigh|*"].total, 7, "right leg region")

-- malformed or missing input never errors
for _, bad in ipairs({nil, 5, "x", {}, {instances = "x"}, {instances = {{clip = {target = 2, events = {{0, 2, 1, 2, 0 / 0, "x", {}, organs = {1, "x", {bone = 5}, {key = {}}}}}}}}}}) do
    local ok, out = pcall(DB.Damage, bad, 0 / 0)
    assert(ok, "DB.Damage survives malformed input: " .. tostring(out))
    assert(istable(out.events) and istable(out.byOrgan), "always the full shape")
    assert(pcall(DB.At, out, 0 / 0, {}), "DB.At survives")
    assert(pcall(DB.Top, out, nil, 3, {}), "DB.Top survives")
end
assert(pcall(DB.At, nil, 1), "DB.At(nil)"); assert(pcall(DB.Top, nil, 1, 3), "DB.Top(nil)")

-- cause of death
local me = {sid = "7656"}
eq(DB.Cause({injuries = {{ago = 41.2, sid = "1", harm = 3, kind = "bullet"}}, condition = {blood = 900}}, dmg, nil, me), "Bled out 41 s after the last hit", "bleed-out")
eq(DB.Cause({injuries = {{ago = 12, sid = "1", harm = 3}}, condition = {blood = 4800}}, dmg, nil, me), "Died 12 s after the last hit", "late, not bled")
eq(DB.Cause({injuries = {{ago = 0.2, sid = "1", harm = 3, kind = "bullet"}}, selfInflicted = true}, dmg, nil, me), "Shot", "the engine's self attacker is not a suicide")
eq(DB.Cause({injuries = {{ago = 0.1, sid = "7656", harm = 3, kind = "explosion"}}}, dmg, nil, me), "Self-inflicted", "your own grenade")
eq(DB.Cause({injuries = {{ago = 0.1, sid = "1", harm = 3, kind = "explosion"}}}, dmg, nil, me), "Explosion", "someone's grenade")
eq(DB.Cause({injuries = {{ago = 0.1, name = "Environment", sid = "", harm = 3, kind = "fall"}}}, nil, nil, me), "Fall", "fall")
eq(DB.Cause({selfInflicted = true, injuries = {}}, nil, nil, me), "Self-inflicted", "no hits at all, killed by yourself")
eq(DB.Cause(nil, dmg, {weapon = "weapon_hands_sh", ago = 0.5}, me), "Blunt force", "fists, from the weapon")
local lastShot = DB.Damage({instances = {{attacker = "A", ago = 1, clip = {pov = 1, target = 2, actors = actors, events = {{100, 2, 1, 2, 9, 2, 0, 1, ballistic = 1}}}}}}, 5)
eq(DB.Cause(nil, lastShot, nil, me), "Shot", "the clip's last hit was a bullet")
for _, bad in ipairs({nil, 5, {injuries = "x"}, {injuries = {5, {ago = "x"}}, condition = "x"}}) do
    assert(pcall(DB.Cause, bad, bad, bad, bad), "DB.Cause survives malformed input")
end

-- harm contributions and vitals
local parts, all = DB.Contributions({injuries = {{sid = "1", name = "Rex", harm = 6}, {sid = "2", name = "Ann", harm = 3}, {sid = "1", name = "Rex", harm = 6},
    {sid = "", name = "Environment", harm = 1}, {sid = "3", name = "Bo", harm = 4}, {harm = 0 / 0}}}, 3)
eq(#parts, 3, "top three"); eq(parts[1].name, "Rex", "largest first"); near(all, 20, "total harm")
near(parts[1].share, 0.6, "share of the total"); eq(parts[3].name, "Ann", "third")
eq(#DB.Contributions(nil, 3), 0, "no debrief, no contributions")
local vitals = DB.Vitals({condition = {blood = 2140, pulse = 0, pain = 83}})
eq(vitals.blood, 2140, "blood"); eq(vitals.pulse, 0, "pulse"); eq(DB.Vitals({condition = {}}), nil, "no vitals")
print("deathpanel ok")
