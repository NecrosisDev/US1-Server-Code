-- luajit tests/lua/test_kit.lua <repo root>: the GoobOS kit's shared painters (UI cohesion 2026-09-26).
local root = arg[1] or "."
dofile(root .. "/tests/lua/gmod_stub.lua")
-- apps.lua's live palette (the kit only adds tokens on top of it)
ZCGoobApps = {Theme = {bg = Color(29, 26, 26), card = Color(38, 35, 35), text = Color(225, 225, 225), muted = Color(165, 165, 165),
    accent = Color(192, 0, 0), main = Color(150, 0, 0), green = Color(119, 218, 181), gold = Color(247, 199, 115),
    red = Color(255, 143, 159), line = Color(90, 20, 20)}}
dofile(root .. "/addons/us1/lua/zc_goobos/kit.lua")
local K, T = ZCGoobApps.Kit, ZCGoobApps.Theme
local function eq(a, b, msg) if a ~= b then error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

-- one font per size/weight, named once, in the hg_font face
local a, b = K.Font(14, 600), K.Font(14, 600)
eq(a, b, "K.Font is cached")
eq(STUB.fonts[a].font, "Bahnschrift", "default face")
CreateClientConVar("hg_font", "Roboto")
K.RebuildFonts()
eq(STUB.fonts[a].font, "Roboto", "hg_font rebuilds every kit font")

-- tokens every surface reads
for _, key in ipairs({"kill", "death", "amber", "healthy", "chip", "inset", "dim", "data", "edge", "glass"}) do
    assert(istable(T[key]), "theme token " .. key)
end
for _, class in ipairs({"flesh", "organ", "lung", "dense", "vessel", "bone", "armor"}) do assert(T.tissue[class], "tissue " .. class) end
eq(T.radius.card, 4, "card radius")

-- clock and initials
eq(K.Clock(8), "0:08", "clock"); eq(K.Clock(754.9), "12:34", "clock minutes"); eq(K.Clock(-3), "0:00", "clock floor")
eq(K.Clock(nil), nil, "clock nil")
eq(K.Initial("zed"), "Z", "initial"); eq(K.Initial(""), "?", "initial empty")

-- scaler: sizes follow the unit
local S = K.Scaler(1.5)
eq(S.u(10), 15, "u scales")
S.U = 1
eq(S.u(10), 10, "unit is live")
-- a hint row's measured width equals what it draws, at any unit
for _, unit in ipairs({0.62, 1, 1.5}) do
    S.U = unit
    local hints = {{"Space", "Next"}, {"Q", "Spectate"}, {nil, "plain"}}
    local w = S.hintWidth(hints)
    local drawn, spans = S.hints(hints, 100, 0, TEXT_ALIGN_LEFT)
    eq(drawn, w, "hint width at unit " .. unit)
    eq(#spans, 3, "one span per hint")
    local last = spans[3]
    assert(math.abs((last[1] + last[2]) - (100 + w)) <= 1, "spans end where the row ends at unit " .. unit)
end
-- centred rows are centred
S.U = 1
local w = S.hintWidth({{"G", "Report"}})
local _, spans = S.hints({{"G", "Report"}}, 500, 0, TEXT_ALIGN_CENTER)
eq(spans[1][1], 500 - w / 2, "centred start")
print("kit ok")
