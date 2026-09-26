-- luajit tests/lua/test_deathpanel_panel.lua <repo root>: the death panel end to end on stubs (UI cohesion U1,
-- 2026-09-26). Loads panels.lua, deathbody.lua and deathpanel.lua with a fake killcam life replay, drives the Think hook
-- through the replay phases and the keys, paints every panel, and checks: each fact is drawn once, one hint row, the
-- two-press N, S share, the scrubber following the replay, and that the body view's 3D render state never leaks.
local root = arg[1] or "."
dofile(root .. "/tests/lua/gmod_stub.lua")
ZCGoobApps = {Theme = {bg = Color(29, 26, 26), card = Color(38, 35, 35), text = Color(225, 225, 225), muted = Color(165, 165, 165),
    accent = Color(192, 0, 0), main = Color(150, 0, 0), green = Color(119, 218, 181), gold = Color(247, 199, 115),
    red = Color(255, 143, 159), line = Color(90, 20, 20)}}
local A = ZCGoobApps
local function eq(a, b, msg) if a ~= b then error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

-- Vectors and angles, enough for the camera maths and the organ sort.
local VM = {}
VM.__index = VM
function Vector(x, y, z) return setmetatable({x = x or 0, y = y or 0, z = z or 0}, VM) end
VM.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
VM.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
VM.__mul = function(a, b) if type(a) == "number" then a, b = b, a end return Vector(a.x * b, a.y * b, a.z * b) end
function VM:LengthSqr() return self.x * self.x + self.y * self.y + self.z * self.z end
local AM = {}
AM.__index = AM
function Angle(p, y, r) return setmetatable({p = p or 0, y = y or 0, r = r or 0}, AM) end
function AM:Forward()
    local p, y = math.rad(self.p), math.rad(self.y)
    return Vector(math.cos(p) * math.cos(y), math.cos(p) * math.sin(y), -math.sin(p))
end
vector_origin, angle_zero = Vector(), Angle()

-- 3D state bookkeeping: every Start3D ends, the scissor is switched off, blend/lighting are reset.
local R = {depth3D = 0, scissor = false, blend = 1, suppressed = false, starts = 0, organs = 0}
cam = {Start3D = function() R.depth3D = R.depth3D + 1 R.starts = R.starts + 1 end, End3D = function() R.depth3D = R.depth3D - 1 end,
    IgnoreZ = function() end}
render = {SetScissorRect = function(_, _, _, _, on) R.scissor = on end, ClearDepth = function() end,
    SuppressEngineLighting = function(on) R.suppressed = on end, ResetModelLighting = function() end,
    SetColorModulation = function() end, SetBlend = function(b) R.blend = b end}
util = {IsValidModel = function() return true end}
RENDERGROUP_OPAQUE = 1
local removed = 0
function ClientsideModel(path)
    local m = {valid = true, path = path}
    function m:GetModel() return self.path end
    function m:Remove() self.valid = false removed = removed + 1 end
    for _, k in ipairs({"SetNoDraw", "DrawShadow", "SetIK", "SetPos", "SetAngles", "ResetSequence", "SetCycle", "SetPlaybackRate", "InvalidateBoneCache", "SetupBones", "DrawModel"}) do m[k] = function() end end
    function m:LookupSequence() return -1 end
    function m:OBBMins() return Vector(-16, -16, 0) end
    function m:OBBMaxs() return Vector(16, 16, 72) end
    return m
end
local failDraw = false
hg = {organism = {
    GetHitBoxOrgans = function() return {["ValveBiped.Bip01_Spine2"] = {{"vest1", 1, nil, nil, nil, nil, true}, {"heart"}, {"lungsR"}},
        ["ValveBiped.Bip01_Head1"] = {{"brain"}}} end,
    ShootMatrix = function() return {{Vector(0, 0, 50), Angle()}, {Vector(1, 0, 50), Angle(), nil, nil, nil, "ValveBiped.Bip01_Spine2", 1},
        {Vector(2, 0, 50), Angle(), nil, nil, nil, "ValveBiped.Bip01_Spine2", 2}, {Vector(3, 0, 50), Angle(), nil, nil, nil, "ValveBiped.Bip01_Spine2", 3},
        {Vector(0, 0, 66), Angle(), nil, nil, nil, "ValveBiped.Bip01_Head1", 1}} end,
    DrawOrganShape = function(_, col) if failDraw then error("organ draw failed") end R.organs = R.organs + 1 R.lastAlpha = col.a end,
    BallisticsV2 = {TagShapes = function() end, Classify = function(row) return row[1] == "heart" and "dense" or (row[1] == "lungsR" and "lung" or "organ") end},
}}

-- VGUI: a panel tree that records geometry; painted by walking it.
local PM = {}
PM.__index = PM
local roots = {}
local function newPanel(class, parent)
    local p = setmetatable({class = class, parent = parent, x = 0, y = 0, w = 64, h = 24, visible = true, children = {}, valid = true}, PM)
    if parent then parent.children[#parent.children + 1] = p else roots[#roots + 1] = p end
    return p
end
for _, k in ipairs({"SetText", "SetCursor", "Dock", "DockMargin", "SetMouseInputEnabled", "SetKeyboardInputEnabled", "SetDrawOnTop", "SetZPos",
    "InvalidateLayout", "SetPlayer", "SetSteamID", "MouseCapture"}) do PM[k] = function() end end
function PM:SetTall(h) self.h = h end
function PM:SetWide(w) self.w = w end
function PM:SetSize(w, h) self.w, self.h = w, h end
function PM:SetPos(x, y) self.x, self.y = x, y end
function PM:GetWide() return self.w end
function PM:GetTall() return self.h end
function PM:GetX() return self.x end
function PM:SetVisible(v) self.visible = v and true or false end
function PM:IsVisible() return self.visible end
function PM:SetAlpha(a) self.alpha = a end
function PM:Remove() self.valid = false end
function PM:IsValid() return self.valid end
function PM:GetChildren() return self.children end
function PM:IsHovered() return self.hovered == true end
function PM:CursorPos() return self.cx or -1000, self.cy or -1000 end
function PM:LocalToScreen(x, y)
    local p = self
    while p do x, y = x + p.x, y + p.y p = p.parent end
    return x, y
end
vgui = {Create = newPanel, GetKeyboardFocus = function() return nil end}
gui = {EnableScreenClicker = function(on) STUB.clicker = on end, IsConsoleVisible = function() return false end, IsGameUIVisible = function() return false end}
local keys = {}
input = {IsKeyDown = function(code) return keys[code] == true end, IsMouseDown = function() return false end, LookupKeyBinding = function() return nil end}
KEY_SPACE, KEY_G, KEY_V, KEY_Q, KEY_F, KEY_S, KEY_N, KEY_LEFT, KEY_RIGHT, KEY_1 = 65, 17, 32, 27, 16, 29, 24, 89, 91, 2
MOUSE_LEFT = 107
draw.RoundedBoxEx = function(...) STUB.calls[#STUB.calls + 1] = {"RoundedBoxEx", ...} end
cookie = {GetString = function() return "" end, Set = function() end, Delete = function() end}
hook.GetTable = function() return {} end
net.Receivers = {}
util.JSONToTable = function() return nil end
local me = {valid = true}
function me:Nick() return "Me" end
function me:Alive() return self.alive == true end
function me:SteamID64() return "7656" end
function me:IsBot() return false end
function me:GetModel() return "models/player/kleiner.mdl" end
function LocalPlayer() return me end
CreateClientConVar("zc_goobos_panels", "1")
CreateClientConVar("zc_killcam_ui", "1")
local calls = {}
local function rec(name) return function(...) calls[#calls + 1] = {name, ...} return true end end

-- The killcam's life replay seam (cl_part_06.lua V.State and friends), holding a two-instance life.
local actors = {{role = "killer", name = "Rex"}, {role = "victim", name = "Me"}}
local seq = {instances = {
    {attacker = "Rex", wep = "weapon_akm", dmg = 50, hits = 2, ago = 10, tag = "ivi", reportable = true, clip = {pov = 1, target = 2, actors = actors,
        weapons = {{3, "weapon_akm"}}, events = {
            {0, 2, 1, 2, 30, 2, 3, 1, ballistic = 1, organs = {{bone = "ValveBiped.Bip01_Spine2", key = 2, name = "heart", label = "Heart", class = "dense", dep = 0.7},
                {bone = "ValveBiped.Bip01_Spine2", key = 3, name = "lungsR", label = "Right lung", class = "lung", dep = 0.3}}},
            {150, 2, 1, 2, 20, 1, 3, 1},
        }}},
    {attacker = "Rex", wep = "weapon_akm", dmg = 40, hits = 1, ago = 2, tag = "ivi", reportable = true, clip = {pov = 1, target = 2, actors = actors,
        weapons = {{3, "weapon_akm"}}, events = {{0, 2, 1, 2, 40, 2, 3, 1, ballistic = 1, organs = {{bone = "ValveBiped.Bip01_Spine2", key = 2, name = "heart", label = "Heart", class = "dense"}}}}}},
}}
local state = {kind = "life", phase = "waiting", id = "life-42", seq = seq, h2h = {
    victim = {life = {alive = 30, kills = 1, dealt = 12, taken = 90, hits = 3, points = {combat = 5, heals = 0, zp = 2}}},
    killer = {name = "Rex", life = {alive = 100, kills = 2, dealt = 90, taken = 12, hits = 3}},
    traded = {victimToKiller = {dmg = 12, hits = 1}, killerToVictim = {dmg = 90, hits = 3}},
    how = {weapon = "weapon_akm", hitgroup = 2, by = "Rex", ago = 0.4}}, index = 1, count = 2, rate = 1, saved = false, reported = {}}
ZCKillcamView = {State = function()
        state.inst = seq.instances[state.index or 0]
        return state
    end,
    RenderInset = function() return true end, Play = rec("Play"), Next = rec("Next"), Skip = rec("Skip"), Save = rec("Save"), Report = rec("Report"),
    HitGroups = {[1] = "head", [2] = "chest", [3] = "abdomen"}, HitGroupBones = {["ValveBiped.Bip01_Spine2"] = "chest", ["ValveBiped.Bip01_Neck1"] = "neck"}}
local asked = 0
ZCObserver = {Revision = 1, Request = function() asked = asked + 1 end}

dofile(root .. "/addons/us1/lua/zc_goobos/kit.lua")
dofile(root .. "/addons/us1/lua/zc_goobos/panels.lua")
dofile(root .. "/addons/us1/lua/zc_goobos/deathbody.lua")
dofile(root .. "/addons/us1/lua/zc_goobos/deathpanel.lua")
local DP, T = A.DeathPanel, A.Theme
local think = STUB.hooks["Think/GoobOS.DeathPanel.Think"]
assert(isfunction(think), "the panel's Think hook")

local function paintTree(p)
    if not p.visible or not p.valid then return end
    if p.Think then p:Think() end
    if p.PerformLayout then p:PerformLayout(p.w, p.h) end
    if p.Paint then p:Paint(p.w, p.h) end
    for _, c in ipairs(p.children) do paintTree(c) end
end
local texts
local function frame(t)
    STUB.SetTime(t)
    think()
    STUB.calls = {}
    if IsValid(DP.root) then paintTree(DP.root) end
    texts = {}
    for _, c in ipairs(STUB.calls) do if c[1] == "SimpleText" then texts[#texts + 1] = tostring(c[2]) end end
    assert(R.depth3D == 0 and not R.scissor and R.blend == 1 and not R.suppressed, "render state never leaks")
end
local function count(pattern)
    local n = 0
    for _, s in ipairs(texts) do if string.find(s, pattern, 1, true) then n = n + 1 end end
    return n
end
local function press(code, t) keys[code] = true frame(t) keys[code] = nil frame(t + 0.01) end

-- waiting: the panel opens, asks for the debrief once, says how you died once
frame(1)
assert(DP.Open, "the panel opened")
eq(asked, 1, "debrief asked for on open")
frame(3)
eq(asked, 2, "asked once more while it has not arrived")
eq(count("Rex killed you"), 1, "one header line")
eq(count("BETA"), 1, "one BETA chip")
for _, gone in ipairs({"HOW IT HAPPENED", "Killed by", "Hold Space to skip", "Space to skip", "You dealt", "DEALT TO", "Hover a mark", "disable killcams"}) do
    eq(count(gone), 0, "no more \"" .. gone .. "\"")
end
eq(count("Next"), 1, "the hint row, once"); eq(count("Spectate"), 1, "the Q button, once")
assert(DP.HowLine and DP.HowLine:find("akm", 1, true) and DP.HowLine:find("Chest", 1, true) and DP.HowLine:find("10.0 s", 1, true), "the header line: " .. tostring(DP.HowLine))
eq(#DP.Damage.events, 3, "three hits on the timeline")
eq(DP.ScrubT, 30, "the scrub rests on the death while waiting")
assert(R.starts > 0 and R.organs > 0, "the body view drew the model and its organs")
eq(count("YOUR BODY"), 1, "the body card"); eq(count("DAMAGE TIMELINE"), 1, "the timeline card")
eq(count("Heart"), 1, "the organ list")
eq(count("CAUSE OF DEATH"), 1, "the clip alone gives a cause (its last hit was a bullet)")
eq(count("HARM CONTRIBUTIONS"), 0, "no contributions before the debrief")

-- the debrief arrives: a cause line, vitals and contributions
ZCObserver.Snapshot = {injuries = {{ago = 0.4, sid = "9", name = "Rex", harm = 8, kind = "bullet"}, {ago = 9, sid = "9", name = "Rex", harm = 4}},
    condition = {blood = 3100, pulse = 40, pain = 60}, selfInflicted = true}
ZCObserver.Revision = 2
frame(4)
eq(count("CAUSE OF DEATH"), 1, "the cause card")
eq(count("Shot"), 1, "the cause line: shot (the engine's self attacker is ignored)")
eq(count("3100 mL"), 1, "blood"); eq(count("40 bpm"), 1, "pulse")
eq(count("HARM CONTRIBUTIONS"), 1, "contributions"); eq(count("100%"), 1, "one contributor")

-- playing: the scrub follows the playing hit
state.phase, state.index, state.cs, state.first, state.last = "playing", 1, 50, -800, 300
frame(5)
eq(DP.ScrubT, 30 - (10 - 0.5), "scrub = span - (ago - cs / 100)")
eq(count("ATTACKER VIEW"), 1, "inset chips")
eq(count("Rex killed you"), 1, "still one header line")

-- hovering a hit mark: one tooltip, its organs highlighted
local tl = DP.tradeCard
local mark = DP.Marks[1]
tl.hovered, tl.cx, tl.cy = true, mark.x, 60
frame(6)
assert(DP.HoverKeys and DP.HoverKeys["ValveBiped.Bip01_Spine2|2"], "hovered hit lights its organs")
eq(count("-10.0 s · Rex · akm · 30 dmg · Heart, Right lung"), 1, "one tooltip line")
tl.hovered = false

-- keys: right arrow steps to the next mark and holds it while the same hit plays; N twice; S share; Q spectate
press(KEY_RIGHT, 7)
eq(DP.ScrubT, DP.Marks[2].t, "right arrow steps to the next mark")
press(KEY_N, 8)
eq(DP.Note, "Press N again to turn killcams off", "first N only arms")
local turnedOff = false
for _, c in ipairs(STUB.calls) do if c[1] == "RunConsoleCommand" then turnedOff = true end end
eq(turnedOff, false, "nothing ran yet")
STUB.calls = {}
keys[KEY_N] = true STUB.SetTime(8.5) think()
local ran
for _, c in ipairs(STUB.calls) do if c[1] == "RunConsoleCommand" and c[2] == "zc_killcam_show" then ran = c[3] end end
keys[KEY_N] = nil frame(8.6)
eq(ran, "0", "second N within 2 s turns killcams off")
eq(DP.Note, "Killcams off · Settings › Replays & killcam turns them back on", "the confirmation")
press(KEY_S, 9)
eq(DP.Note, "Sharing is not available yet", "no share sheet yet")
local shared
A.Share = {Open = function(spec) shared = spec end}
press(KEY_S, 10)
assert(shared and shared.kind == "life" and shared.seq == "life-42" and shared.title == "Rex killed you · akm", "share spec")
state.index = 2
frame(11)
eq(DP.ScrubManual, nil, "a new hit playing releases the scrub")

-- the verdict: the verdict word only; Space closes; Q spectates
state.phase = "over"
frame(12)
eq(count("KILLING BLOW"), 1, "verdict caption")
eq(count("HEART"), 1, "the verdict is the most damaged organ")
eq(count("Rex killed you"), 1, "the verdict does not repeat the header")
eq(count("Close"), 1, "Space closes on the verdict")
calls = {}
press(KEY_Q, 13)
eq(calls[1] and calls[1][1], "Skip", "Q spectates on the verdict too")

-- a failing organ draw never leaks render state
failDraw = true
frame(14)
failDraw = false

-- respawn: the panel closes and the model is released
me.alive = true
frame(15)
eq(DP.Open, false, "closed on respawn")
eq(removed, 1, "the body model is removed with the panel")
print("deathpanel panel ok")
