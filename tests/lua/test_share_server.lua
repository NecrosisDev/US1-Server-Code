-- luajit tests/lua/test_share_server.lua <repo root>: UI cohesion U2 sharing, server side (zc_killcam/sv_net.lua) on a
-- type-checked fake net: zckc_index paging stays readable by the killcam viewer's old reader, a shared clip is
-- watchable by a non-party, zckc_share saves a held death sequence and records a chat link, the sweep keep-set.
-- The same captured reply is then read by the Replays app's reader (replays.lua Rp.ReadIndex / its wrap).
local root = arg[1] or "."
dofile(root .. "/tests/lua/gmod_stub.lua")
local function eq(a, b, msg) if a ~= b then error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

-- engine stubs the shared stub file does not carry ----------------------------------------------
string.Trim = string.Trim or function(s) return (string.gsub(tostring(s), "^%s*(.-)%s*$", "%1")) end
local json, jsonN = {}, 0
local function copy(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = copy(v) end return o end
util = {
    AddNetworkString = function() end,
    NetworkStringToID = function() return 1 end,
    TableToJSON = function(t) jsonN = jsonN + 1 local key = "json#" .. jsonN json[key] = copy(t) return key end,
    JSONToTable = function(s) return json[s] and copy(json[s]) or nil end,
}
local disk = {}
file = {
    Read = function(path) return disk[path] end,
    Write = function(path, data) disk[path] = data end,
    Exists = function(path) return disk[path] ~= nil end,
    Size = function(path) return disk[path] and #disk[path] or -1 end,
    CreateDir = function() end,
    Find = function() return {} end,
}
local convars = STUB.convars
function CreateConVar(name, default)
    local cv = CreateClientConVar(name, default)
    return cv
end
local function setVar(name, value) (convars[name] or CreateConVar(name, value)).value = tostring(value) end
local later = {}
timer.Simple = function(_, fn) later[#later + 1] = fn end
local function flush() while #later > 0 do table.remove(later, 1)() end end
ErrorNoHalt = function() end
os.time = os.time

-- fake net: every write is {kind, value, bits}; reads must ask for the same kind (and bit count) in order ----------
local wire = {out = nil, sent = {}, inbox = {}, pos = 1}
net = {Receivers = {}}
function net.Receive(name, fn) net.Receivers[string.lower(name)] = fn end
function net.Start(name) wire.out = {name = name, items = {}} end
local function writer(kind)
    return function(v, bits)
        if kind == "UInt" then assert(type(v) == "number" and v >= 0 and v < 2 ^ bits and v == math.floor(v), "WriteUInt(" .. tostring(v) .. ", " .. tostring(bits) .. ") does not fit") end
        if kind == "String" then assert(type(v) == "string", "WriteString of a " .. type(v)) end
        wire.out.items[#wire.out.items + 1] = {kind, v, bits}
    end
end
net.WriteString, net.WriteBool, net.WriteUInt, net.WriteData = writer("String"), writer("Bool"), writer("UInt"), writer("Data")
function net.Send(p) wire.sent[#wire.sent + 1] = {to = p, name = wire.out.name, items = wire.out.items} end
function net.SendToServer() wire.sent[#wire.sent + 1] = {name = wire.out.name, items = wire.out.items} end
local function reader(kind)
    return function(bits)
        local it = wire.inbox[wire.pos]
        if not it then return kind == "String" and "" or (kind == "Bool" and false or 0) end -- GMod reads past the end as zeros
        assert(it[1] == kind, "read " .. kind .. " at item " .. wire.pos .. " but the writer wrote " .. it[1])
        if kind == "UInt" then assert(it[3] == bits, "read UInt(" .. tostring(bits) .. ") at item " .. wire.pos .. " but the writer wrote UInt(" .. tostring(it[3]) .. ")") end
        wire.pos = wire.pos + 1
        return it[2]
    end
end
net.ReadString, net.ReadBool, net.ReadUInt, net.ReadData = reader("String"), reader("Bool"), reader("UInt"), reader("Data")
-- Whole bytes left, as the engine counts them: strings are NUL-terminated bytes, a Bool is one bit, UInt(n) n bits.
local function bitsOf(it)
    if it[1] == "String" then return (#it[2] + 1) * 8 end
    if it[1] == "Bool" then return 1 end
    if it[1] == "UInt" then return it[3] end
    return #it[2] * 8
end
function net.BytesLeft()
    local bits = 0
    for i = wire.pos, #wire.inbox do bits = bits + bitsOf(wire.inbox[i]) end
    return math.floor(bits / 8)
end
local function deliver(name, items, p)
    wire.inbox, wire.pos, wire.sent = items, 1, {}
    net.Receivers[string.lower(name)](0, p)
    return wire.sent
end
local function lastTo(name) for i = #wire.sent, 1, -1 do if wire.sent[i].name == name then return wire.sent[i] end end end

-- players and the killcam's storage (sv_clips.lua K.Index / K.AllIndex shapes) ------------------------------------
local function player(sid, opts)
    opts = opts or {}
    local p = {valid = true}
    function p:SteamID64() return sid end
    function p:IsAdmin() return opts.admin == true end
    function p:CheckGroup(g) return opts.operator == true and g == "operator" end
    function p:Alive() return opts.alive == true end
    function p:Nick() return "P" .. sid end
    function p:IsBot() return false end
    return p
end
ZCKillcam = {Root = "zc_killcam"}
local K = ZCKillcam
function K.Index(id) return util.JSONToTable(file.Read("zc_killcam/index/" .. id .. ".json", "DATA") or "") or {} end
local allIndex = {}
function K.AllIndex() return allIndex end
function K.TraitorRound() return false end
local function storeClip(id, owner) disk["zc_killcam/clips/" .. id .. ".dat"] = "blob:" .. id if owner then disk["zc_killcam/clips/" .. id .. ".meta.json"] = util.TableToJSON({owner = owner}) end end
local function setIndex(sid, ids)
    local list = {}
    for i, id in ipairs(ids) do list[i] = {clip = id, t = 1758900000 + i, map = "gm_test", tag = "life", role = "victim", other = "Bob", reported = i == 2} end
    disk["zc_killcam/index/" .. sid .. ".json"] = util.TableToJSON(list)
end
setVar("zc_killcam_flash", 2)
CreateConVar("zc_goobos_share", "1")
SERVER, CLIENT = true, false
dofile(root .. "/addons/us1/lua/zc_killcam/sv_net.lua")
assert(isfunction(K.IsClipParty) and isfunction(K.MayShare) and isfunction(K.SharedClip) and isfunction(K.SharedSet), "share exports")

-- K.PageRows -----------------------------------------------------------------------------------------------------
local src = {}
for i = 1, 70 do src[i] = i end
local page, nextAt, more = K.PageRows(#src, function(i) return src[i] end, function(v) return v % 2 == 0 and v or nil end, 0, 31)
eq(#page, 31, "a page holds 31 kept rows"); eq(page[1], 2, "first kept"); eq(nextAt, 62, "next = source position consumed"); eq(more, true, "more left")
page, nextAt, more = K.PageRows(#src, function(i) return src[i] end, function(v) return v % 2 == 0 and v or nil end, 62, 31)
eq(#page, 4, "rest"); eq(page[1], 64, "resumes after the consumed position"); eq(nextAt, 70, "end"); eq(more, false, "no more")

-- zckc_index: 40 rows of "mine" in two pages, old reader unaffected ------------------------------------------------
local me = player("76561198000000001")
local ids = {}
for i = 1, 40 do ids[i] = "17589" .. string.format("%05d", i) .. "_" .. (9000 + i) storeClip(ids[i], me:SteamID64()) end
setIndex(me:SteamID64(), ids)
STUB.SetTime(10)
local sent = deliver("zckc_index", {{"String", ""}}, me) -- exactly what the viewer's ask("zckc_index", "") sends
local reply = assert(lastTo("zckc_index"), "index reply")
-- the killcam viewer's reader (cl_part_03.lua): scope, locked, n, then 7 fields per row - and nothing after
wire.inbox, wire.pos = reply.items, 1
local scope, locked, n = net.ReadString(), net.ReadBool(), net.ReadUInt(5)
eq(scope, "mine", "scope"); eq(locked, false, "unlocked"); eq(n, 31, "first page is 31 rows")
for i = 1, n do
    local id, t, map, tag, role, other, reported = net.ReadString(), net.ReadUInt(32), net.ReadString(), net.ReadString(), net.ReadString(), net.ReadString(), net.ReadBool()
    eq(id, ids[i], "row " .. i .. " id"); eq(map, "gm_test", "map"); eq(tag, "life", "tag"); eq(reported, i == 2, "reported flag")
    assert(t > 0 and role == "victim" and other == "Bob", "row fields")
end
-- then the P1 trailer, then the U2 paging trailer
for _ = 1, n do net.ReadBool() net.ReadString() net.ReadString() end
eq(net.ReadUInt(16), 31, "next offset"); eq(net.ReadBool(), true, "more")
for _ = 1, n do eq(net.ReadUInt(32), 0, "no post on own rows") net.ReadBool() end
eq(net.BytesLeft(), 0, "nothing after the paging trailer")
-- page two, asked with the optional offset (and within the 1 s throttle it is dropped, as before)
sent = deliver("zckc_index", {{"String", ""}, {"UInt", 31, 16}}, me)
eq(lastTo("zckc_index"), nil, "throttled inside 1 s")
STUB.SetTime(12)
sent = deliver("zckc_index", {{"String", ""}, {"UInt", 31, 16}}, me)
reply = assert(lastTo("zckc_index"), "second page")
wire.inbox, wire.pos = reply.items, 1
net.ReadString() net.ReadBool()
eq(net.ReadUInt(5), 9, "the last 9 rows")
eq(net.ReadString(), ids[32], "page two starts at row 32")

-- zckc_clip: a non-party is refused until the clip is shared, then gets it; sharing off refuses again -------------
local clipId = "1758999999_9500"
storeClip(clipId, "76561198000000009")
local stranger = player("76561198000000002")
STUB.SetTime(20)
deliver("zckc_clip", {{"String", clipId}}, stranger)
local refused = assert(lastTo("zckc_clip"), "refusal")
eq(refused.items[2][2], K.Status.denied, "not a party: denied")
local posted = {}
ZCGoobFeed = {ClipPosted = function(id) return posted[id] == true end, SharedClipIds = function() local out = {} for id in pairs(posted) do out[#out + 1] = id end return out end}
posted[clipId] = true
STUB.SetTime(23)
deliver("zckc_clip", {{"String", clipId}}, stranger)
flush()
local got = assert(lastTo("zckc_clip"), "clip sent")
eq(got.items[2][2], K.Status.ok, "a shared clip is sent to a non-party")
setVar("zc_goobos_share", 0)
STUB.SetTime(26)
deliver("zckc_clip", {{"String", clipId}}, stranger)
eq(lastTo("zckc_clip").items[2][2], K.Status.denied, "sharing off: denied again")
setVar("zc_goobos_share", 1)
-- a live round still locks it for the living, shared or not
local alive = player("76561198000000003", {alive = true})
K.TraitorRound = function() return true end
STUB.SetTime(30)
deliver("zckc_clip", {{"String", clipId}}, alive)
eq(lastTo("zckc_clip").items[2][2], K.Status.locked, "alive in a live round: locked")
K.TraitorRound = function() return false end
-- no records access (zc_killcam_flash below 2) and nothing shared: silence, as before; shared: sent
setVar("zc_killcam_flash", 1)
local other = "1758999998_9501"
storeClip(other, "76561198000000009")
STUB.SetTime(40)
eq(#deliver("zckc_clip", {{"String", other}}, stranger), 0, "no access and not shared: no answer")
STUB.SetTime(43)
deliver("zckc_clip", {{"String", clipId}}, stranger)
flush()
eq(lastTo("zckc_clip").items[2][2], K.Status.ok, "no records access, but shared: sent")
setVar("zc_killcam_flash", 2)

-- K.MayShare / K.IsClipParty ------------------------------------------------------------------------------------
eq(K.IsClipParty(me, ids[1]), true, "own index row: party")
eq(K.IsClipParty(stranger, clipId), false, "posted by someone else: not a party")
eq(K.IsClipParty(player("76561198000000009"), clipId), true, "sidecar owner: party")
local ok, why = K.MayShare(stranger, clipId)
eq(ok, false, "stranger may not share"); eq(why, "You are not a party to that clip.", "the viewer's wording")
ok, why = K.MayShare(me, "1700000000_1")
eq(why, "That clip has expired.", "no file: expired")

-- zckc_share: a held death sequence is saved, then linked ---------------------------------------------------------
local seq = "1759000000_9001"
local sid = me:SteamID64()
K.LifeAllowed = function() return true end
K.Held = {[sid] = {id = seq, saved = false}}
K.Persist = function(owner, h)
    storeClip(h.id, owner)
    local list = K.Index(owner)
    table.insert(list, 1, {clip = h.id, t = 1759000000, map = "gm_test", tag = "life", role = "victim", other = "Eve"})
    disk["zc_killcam/index/" .. owner .. ".json"] = util.TableToJSON(list)
    h.saved = true
end
STUB.SetTime(50)
deliver("zckc_share", {{"String", "life"}, {"String", seq}, {"Bool", true}}, me)
local ans = assert(lastTo("zckc_share"), "share reply")
eq(ans.items[1][2], seq, "names the id asked about"); eq(ans.items[2][2], seq, "a saved sequence keeps its id"); eq(ans.items[3][2], K.ShareCode.ok, "ok")
eq(K.Held[sid].saved, true, "saved first")
eq(K.SharedClip(seq), true, "the chat link makes it watchable by anyone")
eq(K.SharedSet()[seq], true, "and keeps it out of the age sweep")
eq(K.SharedSet()[clipId], true, "a posted clip is kept too")
deliver("zckc_share", {{"String", "clip"}, {"String", ids[1]}, {"Bool", true}}, me)
eq(lastTo("zckc_share").items[3][2], K.ShareCode.slow, "one request a second per player")
STUB.SetTime(52)
deliver("zckc_share", {{"String", "clip"}, {"String", clipId}, {"Bool", true}}, stranger)
ans = lastTo("zckc_share")
eq(ans.items[3][2], K.ShareCode.denied, "a non-party cannot link someone else's clip"); eq(ans.items[4][2], "You are not a party to that clip.", "refusal text")
STUB.SetTime(53)
deliver("zckc_share", {{"String", "life"}, {"String", "1759000001_9002"}, {"Bool", false}}, player("76561198000000004"))
ans = lastTo("zckc_share")
eq(ans.items[3][2], K.ShareCode.gone, "a replay replaced before it was saved"); assert(ans.items[4][2]:find("replaced", 1, true), "says so")
setVar("zc_goobos_share", 0)
STUB.SetTime(54)
deliver("zckc_share", {{"String", "clip"}, {"String", ids[1]}, {"Bool", true}}, me)
eq(lastTo("zckc_share").items[3][2], K.ShareCode.off, "sharing off")
eq(K.SharedSet()[seq], true, "switching sharing off does not unprotect what was shared")
setVar("zc_goobos_share", 1)

-- the "shared" scope, read by the Replays app ---------------------------------------------------------------------
ZCGoobFeed.SharedClipPosts = function(offset, limit)
    local rows = {{id = 77, author = "76561198000000009", name = "Zed", body = "look at this\nnoob", created = 1759000100, clip = clipId},
        {id = 76, author = sid, name = "Me", body = "", created = 1759000050, clip = seq},
        {id = 75, author = sid, name = "Me", body = "gone", created = 1759000040, clip = "1700000000_2"}} -- file gone: skipped
    local out = {}
    for i = offset + 1, math.min(#rows, offset + limit) do out[#out + 1] = rows[i] end
    return out
end
STUB.SetTime(60)
deliver("zckc_index", {{"String", "shared"}, {"UInt", 0, 16}}, stranger)
reply = assert(lastTo("zckc_index"), "shared reply")

SERVER, CLIENT = false, true
local original = function() error("the wrap must consume a reply it is waiting on") end
net.Receivers = {zckc_index = original}
ZCGoobApps = {Theme = {main = Color(150, 0, 0), text = Color(225, 225, 225), muted = Color(165, 165, 165), accent = Color(192, 0, 0), gold = Color(247, 199, 115), green = Color(119, 218, 181)},
    State = {}, Register = function() end}
dofile(root .. "/addons/us1/lua/zc_goobos/replays.lua")
local Rp, S = ZCGoobApps.Replays, ZCGoobApps.State.replays
assert(Rp.Wraps.index and net.Receivers.zckc_index == Rp.Wraps.index, "the wrap is installed over the viewer's receiver")
S.pending, S.pendingAt = {scope = "shared", offset = 0}, RealTime()
wire.inbox, wire.pos = reply.items, 1
Rp.Wraps.index(0)
eq(#S.rows.shared, 2, "two live shared clips (the expired one skipped)")
local zed = S.rows.shared[1]
eq(zed.id, clipId, "newest post first"); eq(zed.post, 77, "post id from the trailer"); eq(zed.mine, false, "not the stranger's")
eq(zed._title, "look at this noob", "the caption is the title (control characters flattened)")
assert(zed._meta:find("Shared by Zed", 1, true), "meta names the poster")
eq(zed.party, false, "a stranger is not a party")
eq(S.more.shared, false, "one page")
-- the viewer's own replies still reach it when nothing is pending (a fresh wrap over a receiver that records it)
local reached = false
net.Receivers = {zckc_index = function() reached = true end}
Rp.Wraps.index = nil
dofile(root .. "/addons/us1/lua/zc_goobos/replays.lua")
S.pending = nil
net.Receivers.zckc_index(0)
eq(reached, true, "a reply nobody asked for goes to the viewer untouched")
print("share server ok")
