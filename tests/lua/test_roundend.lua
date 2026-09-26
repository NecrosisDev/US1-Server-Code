-- luajit tests/lua/test_roundend.lua <repo root>: round end and notifications (UI cohesion U3, 2026-09-26) - one
-- announcement per round end, the header's words, the next reel part's caption, the one vote hint, the recap's lines.
local root = arg[1] or "."
dofile(root .. "/tests/lua/gmod_stub.lua")
local function eq(a, b, msg) if a ~= b then error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

-- what these two files touch at load time beyond the shared stubs
local timers = {}
timer.Create = function(name, _, _, fn) timers[name] = fn end
net.Receivers = {}
vgui = {}
gui = {EnableScreenClicker = function() end}
string.Trim = string.Trim or function(s) return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", "")) end
function GetGlobalBool(_, default) return default end
game = {GetMap = function() return "gm_construct" end}

ZCGoobApps = {State = {}, Theme = {bg = Color(29, 26, 26), card = Color(38, 35, 35), text = Color(225, 225, 225), muted = Color(165, 165, 165),
    accent = Color(192, 0, 0), main = Color(150, 0, 0), green = Color(119, 218, 181), gold = Color(247, 199, 115),
    red = Color(255, 143, 159), line = Color(90, 20, 20)}}
local A = ZCGoobApps
dofile(root .. "/addons/us1/lua/zc_goobos/kit.lua")
dofile(root .. "/addons/us1/lua/zc_goobos/notify.lua")
-- the panels coordinator, reduced to what roundend.lua calls
local panelsOn, replay = true, nil
A.Panels = {Enabled = function() return panelsOn end, Unit = function() return 1 end, Claim = function() end, SetKeys = function() end,
    Release = function() end, ChatDock = function() end, RightGutter = function() return 260 end, Replay = function() return replay end,
    Call = function() return false end, Track = function() end}
dofile(root .. "/addons/us1/lua/zc_goobos/roundend.lua")
local N, RE = A.Notify, A.RoundEnd
assert(istable(RE) and RE.Scaler, "roundend.lua loaded on the stubs")

-- one vote hint: keycap + verb, en dash, the same list in both files
eq(N.VoteKeys(1), "1", "one option"); eq(N.VoteKeys(6), "1–6", "en dash"); eq(N.VoteKeys(10), "1–9, 0", "ULX key 0")
local h = N.VoteHints(6, true)
eq(#h, 2, "keys + click"); eq(h[1][1], "1–6", "keycap"); eq(h[1][2], "Vote", "verb"); eq(h[2][1], nil, "no keycap for a click"); eq(h[2][2], "Click a tile", "click hint")
eq(#N.VoteHints(6), 1, "no click hint where clicks do nothing")
eq(RE.VoteHints(4, true), N.VoteHints(4, true), "roundend draws notify's list")
assert(N.VoteHints(3) == N.VoteHints(3), "cached: no table per frame")

-- the header: mode / map / what's next; the result only for a player whose winner card never showed it; never "Round over"
local title, isResult, caption = RE.HeaderText({winner = "Traitors win", told = true, mode = "Homicide", map = "Construct"})
eq(title, "Homicide", "told: the mode is the title"); eq(isResult, false, "told: no result"); eq(caption, "CONSTRUCT", "told: map caption")
title, isResult, caption = RE.HeaderText({winner = "Traitors win", told = false, mode = "Homicide", map = "Construct"})
eq(title, "Traitors win", "missed: the result"); eq(isResult, true, "missed: gold"); eq(caption, "HOMICIDE   ·   CONSTRUCT", "missed: mode in the caption")
title = RE.HeaderText({told = false, mode = "Homicide", map = "Construct"})
eq(title, "Homicide", "no result yet: never 'Round over'")
title, _, caption = RE.HeaderText({mode = "", map = "Construct"})
eq(title, "Construct", "no mode: the map"); eq(caption, "", "the map once")
_, _, caption = RE.HeaderText({told = true, mode = "Homicide", map = "Construct", final = true})
eq(caption, "CONSTRUCT   ·   LAST ROUND", "final")
_, _, caption = RE.HeaderText({told = true, mode = "Homicide", map = "Construct", final = true, extended = true, voteOpen = true})
eq(caption, "CONSTRUCT", "extended: the pill says it while the ballot is open")
_, _, caption = RE.HeaderText({told = true, mode = "Homicide", map = "Construct", final = true, extended = true})
eq(caption, "CONSTRUCT   ·   MAP EXTENDED", "extended: the caption once the ballot closed")

-- the winner card tells the result once it has shown it for a second
RE.Phase, RE.WinnerBorn, RE.Summary = "winner", 0, {winner = "Traitors", mode = "Homicide", duration = 125}
local winnerPaint = STUB.hooks["HUDPaint/GoobOS.RoundEnd.Winner"]
STUB.SetTime(0.2) winnerPaint()
eq(RE.WinnerTold(), false, "not yet told")
STUB.SetTime(1.4) winnerPaint()
eq(RE.WinnerTold(), true, "told after a second on screen")
RE.Phase = nil

-- the next reel part's caption (or nothing) replaces the fixed "UP NEXT | Runner-Up"
local seq = {reel = 2, scope = "round", instances = {{star = "Ann", kills = 1, caps = {}}, {star = "Bob", kills = 2, round = 4, caps = {"DOUBLE"}, wep = "weapon_ak47"}}}
eq(RE.NextCaption({seq = seq, index = 1}), "Round 4  ·  Bob  ·  DOUBLE  ·  ak47", "next part's caption")
eq(RE.NextCaption({seq = seq, index = 2}), nil, "no part after the last")
eq(RE.NextCaption({seq = {instances = {{star = "Ann"}, {kills = 1}}}, index = 1}), nil, "a part that does not say who: nothing")
eq(RE.NextCaption(nil), nil, "no replay")

-- the recap's lines: the Settings page by its name; Replays only when its index lists round highlights
CreateClientConVar("zc_killcam_show", "0")
eq(RE.NoHighlightReason(), "Killcams are off for you · Settings › Replays & killcam", "killcams off")
STUB.convars.zc_killcam_show.value = "1"
eq(RE.ReplaysLine(), nil, "Replays never opened: no promise")
A.State.replays = {rows = {mine = {{tag = "life"}}, highlights = {}}}
eq(RE.ReplaysLine(), nil, "no round highlights listed: no promise")
A.State.replays.rows.highlights = {{kind = "highlight", tag = "highlight"}}
eq(RE.ReplaysLine(), "Find it in Replays › Highlights", "listed: the promise resolves")

-- the compact mode vote: "MODE VOTE" and the keycap hint, not "PRESS A NUMBER"
RE.ModeVote = {active = true, endsAt = 20, length = 20, startedAt = 0, locked = {}, tally = {0, 0, 0},
    options = {{label = "Homicide"}, {label = "TDM"}, {label = "Riot", again = true}}}
STUB.calls = {}
STUB.SetTime(0)
STUB.hooks["HUDPaint/GoobOS.RoundEnd.ModeVote"]()
local drawn = {}
for _, c in ipairs(STUB.calls) do if c[1] == "SimpleText" then drawn[tostring(c[2])] = true end end
assert(drawn["MODE VOTE"] and drawn["1–3"] and drawn["Vote"], "mode vote title and keycap hint")
for s in pairs(drawn) do assert(not string.find(s, "PRESS", 1, true) and not string.find(s, "Press", 1, true), "no old hint: " .. s) end
assert(drawn["0:20"], "timer via K.Clock")

-- one announcement: the "round over" banner stays quiet while the round-end panel owns the round end
CreateClientConVar("zc_goobos_notify", "1")
N.Ensure = function() end
local roundPoll = timers["GoobOS.Notify.Round"]
zb = {ROUND_STATE = 1, CROUND = "homicide"}
roundPoll() -- first read
zb.ROUND_STATE = 3 roundPoll()
eq(#N.Banners, 0, "panels on: no round-over banner")
zb.ROUND_STATE = 1 roundPoll()
eq(N.Banners[1].text, "Homicide · round started", "round start banner kept")
panelsOn = false
zb.ROUND_STATE = 3 roundPoll()
eq(N.Banners[1].text, "Homicide · round over", "panels off: the banner is the announcement")
panelsOn = true

-- Smoke paint: the full panel (mode vote, pre-vote, roster), the final ballot, the side card and the end stamp all
-- paint on the stubs without an error and without the retired strings.
local methods = {IsValid = function() return true end, SetVisible = function(s, v) s.visible = v end, IsVisible = function(s) return s.visible end,
    LocalToScreen = function(_, x, y) return x, y end, CursorPos = function() return -1, -1 end, GetPos = function() return 0, 0 end,
    GetValue = function() return "" end, HasFocus = function() return false end}
-- Derma methods (upper case) are no-ops unless listed; the panel's own fields (hits, hitPool) stay plain
vgui.Create = function()
    return setmetatable({}, {__index = function(_, k) return methods[k] or (string.match(k, "^%u") and function() end or nil) end})
end
draw.RoundedBoxEx = function(...) STUB.calls[#STUB.calls + 1] = {"RoundedBoxEx", ...} end
render = {SetScissorRect = function() end}
player = {Iterator = function() return ipairs({}) end, GetCount = function() return 0 end}
TEAM_SPECTATOR = 1002
A.Panels.RenderInset = function() return false end
local function paintedText()
    local out = {}
    for _, c in ipairs(STUB.calls) do if c[1] == "SimpleText" then out[#out + 1] = tostring(c[2]) end end
    return table.concat(out, "\n")
end
local function noRetired(s, where)
    for _, old in ipairs({"Round over", "ROUND OVER", "ZCITY US1", "Runner-Up", "Press ", "PRESS A NUMBER", "Saved in Replays", "Settings > Gameplay", "number keys"}) do
        assert(not string.find(s, old, 1, true), where .. ": still draws " .. old)
    end
end
-- the winner card hands over to the panel after its beat
zb = {ROUND_STATE = 3, Roundscount = 5, END_TIME = 30}
RE.Summary = {winner = "Traitors", mode = "Homicide", duration = 125, totalKills = 3, totalHeals = 1, survivors = {"Ann"},
    top = {{name = "Ann", zp = 10, combat = 5, kills = 2, heals = 0}, {name = "Bob", zp = 3, combat = 1, kills = 1, heals = 1}, {name = "Cy", zp = 1, combat = 0, kills = 0, heals = 0}}}
RE.Phase, RE.WinnerBorn, RE.WinnerToldFrom, RE.WinnerToldTo = "winner", 0, nil, nil
STUB.SetTime(0.5) winnerPaint()
STUB.SetTime(2) winnerPaint()
STUB.SetTime(3.5) winnerPaint()
eq(RE.Phase, "panel", "the card handed over")
assert(RE.Panel, "the panel exists")
RE.Prevote = {ranked = {{map = "gm_flatgrass", count = 2}}, yourVote = "gm_flatgrass", canChange = true, pool = {"gm_flatgrass", "gm_bigcity"}}
STUB.calls = {}
RE.Panel.Paint(RE.Panel, 1920, 1080)
local s = paintedText()
noRetired(s, "full panel")
assert(string.find(s, "Homicide", 1, true), "header title: the mode")
assert(not string.find(s, "Traitors win", 1, true), "the winner card told it: the header does not repeat it")
assert(string.find(s, "CONSTRUCT", 1, true), "header caption: the map")
assert(string.find(s, "Next round   ·   0:26", 1, true), "what's next, K.Clock")
assert(string.find(s, "YOURS", 1, true), "S.chip in the pre-vote")
-- the killcam-off recap line names the Settings page
CreateClientConVar("zc_killcam_show", "0")
STUB.calls = {}
STUB.SetTime(20)
RE.Panel.Paint(RE.Panel, 1920, 1080)
assert(string.find(paintedText(), "Killcams are off for you · Settings › Replays & killcam", 1, true), "recap reason")
STUB.convars.zc_killcam_show.value = "1"
-- the end stamp: what played, no stamp box, the real next part (none after the last one)
replay = {kind = "highlight", phase = "over", seq = seq, index = 2, count = 2, rate = 0.35}
RE.SawReplay, RE.LastHighlight = true, {star = "Bob", beat = "DOUBLE", round = 4}
STUB.calls = {}
RE.Panel.Paint(RE.Panel, 1920, 1080)
s = paintedText()
noRetired(s, "stamp")
assert(string.find(s, "ROUND 4 HIGHLIGHT", 1, true), "stamp drawn")
assert(not string.find(s, "Up next", 1, true), "last part: nothing next")
assert(string.find(s, "0.35x", 1, true), "rate chip %.2gx")
replay.index = 1
STUB.calls = {}
RE.Panel.Paint(RE.Panel, 1920, 1080)
assert(string.find(paintedText(), "Up next  ·  Round 4  ·  Bob", 1, true), "the next part's caption")
replay = nil
-- the final intermission: the ballot with its hint row (clicks work in the full panel)
RE.ModeVote.active = false
RE.MapVote = {active = true, maps = {"gm_flatgrass", "gm_bigcity"}, finish = 60, length = 40, allowExtend = true, allowRandom = false}
STUB.calls = {}
RE.Panel.Paint(RE.Panel, 1920, 1080)
s = paintedText()
noRetired(s, "final ballot")
assert(string.find(s, "1–3", 1, true) and string.find(s, "Click a tile", 1, true), "ballot hint: keycap + click")
assert(string.find(s, "LAST ROUND", 1, true), "final caption")
SolidMapVote = {RerollButtonState = function() return "REROLL", true, "Reroll the maps" end}
STUB.calls = {}
RE.Panel.Paint(RE.Panel, 1920, 1080)
s = paintedText()
assert(string.find(s, "REROLL", 1, true) and string.find(s, "1–3", 1, true) and string.find(s, "Click a tile", 1, true), "ballot hint beside the reroll button")
SolidMapVote = nil
-- the side card (always-side convar): plate, the mode as its title, the ballot's hint without a click
STUB.convars.zc_goobos_roundend_side.value = "1"
STUB.calls = {}
RE.Panel.Paint(RE.Panel, 1920, 1080)
s = paintedText()
noRetired(s, "side card")
assert(string.find(s, "HOMICIDE", 1, true), "side title: the mode")
assert(string.find(s, "1–3", 1, true) and not string.find(s, "Click a tile", 1, true), "side ballot hint: keys only")
-- a player whose winner card never told the result gets it in the side title, in gold
RE.WinnerToldFrom = nil
STUB.calls = {}
RE.Panel.Paint(RE.Panel, 1920, 1080)
assert(string.find(paintedText(), "TRAITORS WIN", 1, true), "untold: the result")
print("roundend ok")
