-- luajit tests/lua/test_round_map.lua <repo root>: a round tape recorded on another map is refused before any 3D
-- playback starts (owner choice A, 2026-09-26). R.Start is lifted out of cl_part_09.lua and run on stubs.
local root = arg[1] or "."
dofile(root .. "/tests/lua/gmod_stub.lua")
local function eq(a, b, msg) if a ~= b then error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local src = assert(io.open(root .. "/addons/us1/lua/zc_killcam/viewer_parts/cl_part_09.lua")):read("*a")
local body = assert(string.match(src, "\n(function R%.Start%(rs%).-\nend)\n"), "R.Start found")
game = {GetMap = function() return "gm_b" end}
local started
local V = {Life = {State = function() return nil end, Set = function() started = true end, load = function() end}, Say = function() end}
local R = {}
function R.Fail(rs, title, text) rs.failed = {title = title, text = text} end
function R.OpensAt() return 0 end
function R.SetMode() end
function R.Close() end
assert(load("local V, R = ...\n" .. body))(V, R)

local function run(map)
    started = false
    local head = map and {map = map} or {}
    local rs = {rid = "1", chunks = {}, idx = {head = head, chunks = {{seq = 1, t0 = 0, t1 = 1}}, actors = {{}}, len = 100, index = {}, marks = {}}}
    pcall(R.Start, rs) -- the same-map path reaches the life player, which is stubbed only as far as the gate matters
    return rs
end
local rs = run("gm_a")
eq(rs.failed and rs.failed.title, "Recorded on gm_a", "other map refused")
eq(started, false, "nothing handed to the life player")
eq(run("gm_b").failed, nil, "same map plays")
eq(started, true, "same map reaches the life player")
eq(run(nil).failed, nil, "a head without a map plays")
print("ok test_round_map")
