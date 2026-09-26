-- luajit tests/lua/test_share.lua <repo root>: UI cohesion U2 sharing, client side. share.lua's link parser, availability
-- rules and the Post / Copy actions (the server round trip on a fake net, CityLeak's request stubbed), and links.lua
-- making "!clip" / "!replay" clickable in chat while the tester lock keeps the app links to the tester.
local root = arg[1] or "."
dofile(root .. "/tests/lua/gmod_stub.lua")
local function eq(a, b, msg) if a ~= b then error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

string.Trim = string.Trim or function(s) return (string.gsub(tostring(s), "^%s*(.-)%s*$", "%1")) end
function CreateConVar(name, default) return CreateClientConVar(name, default) end
local function setVar(name, value) (STUB.convars[name] or CreateConVar(name, value)).value = tostring(value) end
util = {NetworkStringToID = function() return 1 end}
local clipboard
function SetClipboardText(text) clipboard = text end
local sent = {}
net = {Receivers = {}}
function net.Receive(name, fn) net.Receivers[name] = fn end
local out
function net.Start(name) out = {name = name} end
function net.WriteString(v) out[#out + 1] = v end
function net.WriteBool(v) out[#out + 1] = v end
function net.WriteUInt(v) out[#out + 1] = v end
function net.SendToServer() sent[#sent + 1] = out end
local inbox, at = {}, 1
local function read() local v = inbox[at] at = at + 1 return v end
net.ReadString, net.ReadBool, net.ReadUInt = read, read, read
local function reply(...) inbox, at = {...}, 1 net.Receivers.zckc_share() end

ZCGoobApps = {Theme = {}, State = {}}
CreateConVar("zc_goobos_share", "1")
dofile(root .. "/addons/us1/lua/zc_goobos/share.lua")
local Sh = ZCGoobApps.Share

-- the parser (chat and CityLeak share it) ----------------------------------------------------------------------
local link = Sh.FindLink("gg !clip 1758900000_9001 lol")
eq(link and link.kind, "clip", "clip link"); eq(link.id, "1758900000_9001", "clip id")
link = Sh.FindLink("look !replay 1758900000_3 1:05")
eq(link and link.kind, "round", "round link"); eq(link.round, "1758900000_3", "round id"); eq(link.at, 65, "m:ss -> seconds"); eq(link.time, "1:05", "time text")
eq(Sh.FindLink("x!clip 1_2"), nil, "glued to a word on the left")
eq(Sh.FindLink("!clip 1_2x"), nil, "glued to a word on the right")
eq(Sh.FindLink("!replay 1_2 1:75"), nil, "not a time")
eq(Sh.FindLink("!replay 1_2"), nil, "a round link needs its time")
eq(Sh.FindLink("!!clip 1_2"), nil, "a second ! is not a link")
eq(Sh.FindLink("SEE !CLIP 12_3").id, "12_3", "case-insensitive")
eq(Sh.FindLink("!clip " .. string.rep("1", 30) .. "_1"), nil, "ids are at most 24 bytes")
local e
link, e = Sh.MatchLink("!clip 5_6 and more", 1)
eq(e, 9, "MatchLink returns where the token ends")
eq(Sh.LinkLabel({kind = "round", at = 65, time = "1:05"}), "Replays › Round at 1:05", "round label")
assert(Sh.LinkLabel({kind = "clip", id = "1758900000_9001"}):find("^Replays › Clip %d"), "clip label reads as a Replays page")
eq(Sh.ClipLink("1_2"), "!clip 1_2", "clip link text"); eq(Sh.RoundLink("7_8", 125), "!replay 7_8 2:05", "round link text")

-- availability ---------------------------------------------------------------------------------------------------
local ok, why = Sh.Available({kind = "clip", clip = "1_2"})
eq(ok, true, "a clip")
ok, why = Sh.Available({kind = "clip", clip = "1_2", party = false})
eq(ok, false, "not a party and not shared"); eq(why, "Only players in this clip can share it.", "why")
eq((Sh.Available({kind = "clip", clip = "1_2", party = false, shared = true})), true, "someone else's shared clip: its link can be passed on")
eq((Sh.Available({kind = "round", round = "1_2", at = -1})), false, "a negative time")
eq((Sh.Available({kind = "life", seq = "../x"})), false, "a bad id")
setVar("zc_goobos_share", 0)
ok, why = Sh.Available({kind = "clip", clip = "1_2"})
eq(ok, false, "sharing off"); eq(why, "Sharing is turned off on this server.", "why")
setVar("zc_goobos_share", 1)
ok, why = Sh.CanPost({kind = "clip", clip = "1_2"})
eq(ok, false, "CityLeak not loaded: no post"); assert(why:find("copy the link", 1, true), "but the link still works")

-- CityLeak's client, stubbed: one request in flight, done / fail callbacks (feed.lua C.Request)
local requests = {}
local C = {blocked = false, busy = false}
function C.Available() return true end
function C.Busy() return C.busy end
function C.Nonce() return string.rep("a", 32) end
function C.Request(data, done, fail) requests[#requests + 1] = {data = data, done = done, fail = fail} return true end
ZCGoobFeed = {Client = C}

-- round moment: posted as its link in the text, no clip; the caption shares CityLeak's 1200 bytes with it -------
local st = {spec = {kind = "round", round = "1758900000_3", at = 65}, caption = "  what a play  "}
eq(Sh.PostBody(st.spec, st.caption), "what a play !replay 1758900000_3 1:05", "caption then link")
eq(Sh.PostBody(st.spec, ""), "!replay 1758900000_3 1:05", "link alone")
eq(#Sh.PostBody(st.spec, string.rep("x", 5000)), Sh.CaptionMax, "never over CityLeak's limit")
Sh.Post(st)
eq(requests[1].data.op, "publish", "publish"); eq(requests[1].data.clip, nil, "no clip column for a round")
requests[1].done({kind = "published", id = 42})
eq(st.result, "Posted to CityLeak", "result line"); eq(st.posted, 42, "remembers the post")
Sh.Copy(st)
eq(clipboard, "!replay 1758900000_3 1:05", "round link copied"); eq(st.result, "Link copied: !replay 1758900000_3 1:05", "result line")
eq(#sent, 0, "a round link needs no server round trip")

-- a stored clip: Copy registers the link first; the server's refusal is shown as it is -------------------------
st = {spec = {kind = "clip", clip = "1758900000_9001"}, caption = ""}
Sh.Copy(st)
eq(sent[1].name, "zckc_share", "asks the server"); eq(sent[1][1], "clip", "kind"); eq(sent[1][2], "1758900000_9001", "id"); eq(sent[1][3], true, "as a link")
eq(st.busy, "Sharing…", "busy while it waits")
reply("1758900000_9001", "", 1, "You are not a party to that clip.")
eq(st.busy, nil, "done waiting"); eq(st.result, "You are not a party to that clip.", "the server's words"); eq(st.tone, "bad", "shown as a refusal")
Sh.Copy(st)
reply("1758900000_9001", "1758900000_9001", 0, "")
eq(clipboard, "!clip 1758900000_9001", "copied"); eq(st.result, "Link copied: !clip 1758900000_9001", "result line")
-- someone else's already-shared clip: copied as is
st = {spec = {kind = "clip", clip = "9_9", shared = true, party = false}, caption = ""}
local before = #sent
Sh.Copy(st)
eq(#sent, before, "no round trip for a clip that is already public"); eq(clipboard, "!clip 9_9", "copied")
eq(Sh.Post(st), false, "but it cannot be posted by a non-party")

-- a death sequence: saved first, then posted under the id the server names ---------------------------------------
requests = {}
st = {spec = {kind = "life", seq = "1759000000_9001"}, caption = "rip"}
Sh.Post(st)
local ask = sent[#sent]
eq(ask[1], "life", "life"); eq(ask[3], false, "posting is not a chat link")
eq(st.busy, "Saving your replay…", "says it is saving")
reply("1759000000_9001", "1759000000_9001", 0, "")
eq(requests[1].data.clip, "1759000000_9001", "posts the saved clip"); eq(requests[1].data.body, "rip", "with the caption")
requests[1].fail("Please wait a minute before posting again.")
eq(st.result, "Please wait a minute before posting again.", "CityLeak's refusal"); eq(st.busy, nil, "not stuck busy")
-- no answer: the sheet gives up on its own
Sh.Copy(st)
STUB.SetTime(100)
STUB.hooks["Think/GoobOS.Share.Wait"]()
eq(st.result, "The server did not answer. Try again.", "timeout")
-- a reply for some other id is ignored
Sh.Copy(st)
reply("1_1", "1_1", 0, "")
assert(st.busy, "still waiting for its own id")

-- links.lua: clip and round links for everyone; app links stay locked to the tester ------------------------------
dofile(root .. "/addons/us1/lua/zc_goobos/links.lua")
local L = ZCGoobLinks
eq(L.Allowed(LocalPlayer()), false, "the tester lock is on (zc_goob_links 1)")
local row = {text = "gg !clip 1758900000_9001 and !replay 1758900000_3 1:05, also !settings"}
local markup = L.RenderRow(row, row.text)
eq(#row.ZCGoobLinks, 2, "two share links, no app link")
eq(row.ZCGoobLinks[1].share.kind, "clip", "first is the clip"); eq(row.ZCGoobLinks[2].share.kind, "round", "then the round")
assert(markup:find("<color=88,166,255>Replays › Clip", 1, true), "the clip reads as a link")
assert(markup:find("<color=88,166,254>Replays › Round at 1:05</color>", 1, true), "each link has its own blue")
assert(markup:find("also !settings", 1, true), "the app word stays plain text while locked")
row = {text = "!replay"}
eq(L.RenderRow(row, row.text), "!replay", "the bare app word is not a share link")
setVar("zc_goob_links", 2)
row = {text = "!replay 5_6 0:42 or !replay"}
markup = L.RenderRow(row, row.text)
eq(#row.ZCGoobLinks, 2, "a round link, then the app link")
eq(row.ZCGoobLinks[2].id, "replays", "the bare word still opens the app")
setVar("zc_goobos_share", 0)
setVar("zc_goob_links", 1)
row = {text = "!clip 1_2"}
eq(L.RenderRow(row, row.text), "!clip 1_2", "sharing off: plain text")
setVar("zc_goobos_share", 1)
print("share ok")
