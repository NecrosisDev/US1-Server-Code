-- luajit tests/lua/test_share_ui.lua <repo root>: UI cohesion U2 smoke test of the panels themselves, on a small vgui
-- stub: the share sheet (full-screen card and inside the phone), the Replays app (list, Clips filter, Load more, the
-- detail view in the wide layout and as a sheet) and every Paint / Think they install, run once each.
local root = arg[1] or "."
dofile(root .. "/tests/lua/gmod_stub.lua")
local function eq(a, b, msg) if a ~= b then error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

string.Trim = string.Trim or function(s) return (string.gsub(tostring(s), "^%s*(.-)%s*$", "%1")) end
function CreateConVar(name, default) return CreateClientConVar(name, default) end
util = {NetworkStringToID = function() return 1 end}
local noop = function() end
setmetatable(surface, {__index = function() return noop end}) -- DrawLine, SetMaterial, ... draw nothing
draw.RoundedBoxEx = noop
gui = {IsGameUIVisible = function() return false end, IsConsoleVisible = function() return false end, HideGameUI = noop}
KEY_ESCAPE, MOUSE_LEFT, DOCK_TOP, TOP, FILL, NODOCK, BOTTOM, LEFT, RIGHT = 70, 107, 4, 4, 1, 0, 5, 2, 3
ErrorNoHalt = function(msg) error(msg, 2) end
function Material() return {} end
local clipboard
function SetClipboardText(t) clipboard = t end
net = {Receivers = {}, Receive = function(name, fn) net.Receivers[string.lower(name)] = fn end,
    Start = noop, WriteString = noop, WriteBool = noop, WriteUInt = noop, SendToServer = noop}

-- vgui: panels remember size, visibility, children and the callbacks the code installs ------------------------------
local created = {}
local Panel = {}
local META = {__index = Panel}
local NOOPS = {"Dock", "DockMargin", "DockPadding", "SetPos", "SetZPos", "SetMouseInputEnabled", "SetKeyboardInputEnabled",
    "MakePopup", "SetCursor", "RequestFocus", "SetFont", "SetPlaceholderText", "SetUpdateOnType", "SetTextColor", "SetWrap",
    "SetAutoStretchVertical", "SetMultiline", "SetEnabled", "InvalidateLayout", "SetPaintBackground", "SetHideButtons",
    "SizeToChildren", "MouseCapture", "SetSteamID", "SetPlayer", "SetCaretPos", "SetAllowLua", "SetHTML", "SetImage"}
for _, name in ipairs(NOOPS) do Panel[name] = noop end
function Panel:SetSize(w, h) self.w, self.h = w, h end
function Panel:GetWide() return self.w end
function Panel:GetTall() return self.h end
function Panel:SetWide(w) self.w = w end
function Panel:SetTall(h) self.h = h end
function Panel:IsVisible() return self.shown ~= false end
function Panel:SetVisible(v) self.shown = v end
function Panel:SetText(t) self.text = t end
function Panel:GetValue() return self.text or "" end
function Panel:SetTooltip(t) self.tooltip = t end
function Panel:GetChildren() return self.kids end
function Panel:GetParent() return self.parent end
function Panel:Clear() for _, c in ipairs(self.kids) do c:Remove() end self.kids = {} end
function Panel:Remove()
    if self.gone then return end
    self.gone = true
    for _, c in ipairs(self.kids) do c:Remove() end
    if self.OnRemove then self:OnRemove() end
end
function Panel:IsValid() return not self.gone end
function Panel:CursorPos() return 0, 0 end
function Panel:IsHovered() return false end
function Panel:HasFocus() return false end
function Panel:DrawTextEntryText() end
function Panel:GetVBar() return vgui.Create("DVScrollBar") end
vgui = {Create = function(class, parent)
    local p = setmetatable({class = class, parent = parent, kids = {}, w = 0, h = 0}, META)
    if class == "DVScrollBar" then p.btnGrip = setmetatable({class = "grip", kids = {}, w = 0, h = 0}, META) end
    if parent then parent.kids[#parent.kids + 1] = p end
    created[#created + 1] = p
    return p
end}
-- Runs every live panel's Think, then PerformLayout and Paint at its size (or a default), once.
local function frame(defaultW, defaultH)
    for _, p in ipairs(created) do if not p.gone and p.Think then p:Think() end end
    for _, p in ipairs(created) do
        if not p.gone then
            local w, h = p.w > 0 and p.w or defaultW, p.h > 0 and p.h or defaultH
            if p.PerformLayout then p:PerformLayout(w, h) end
            if p.Paint then p:Paint(w, h) end
        end
    end
end
local function find(pred) for _, p in ipairs(created) do if not p.gone and pred(p) then return p end end end
local function button(label) return find(function(p) return p.Spec and (isfunction(p.Spec.label) and p.Spec.label() or p.Spec.label) == label end) end

-- the GoobOS pieces the two files lean on ---------------------------------------------------------------------
ZCGoobApps = {Theme = {bg = Color(29, 26, 26), card = Color(38, 35, 35), text = Color(225, 225, 225), muted = Color(165, 165, 165),
    accent = Color(192, 0, 0), main = Color(150, 0, 0), green = Color(119, 218, 181), gold = Color(247, 199, 115),
    red = Color(255, 143, 159), line = Color(90, 20, 20)}, State = {}, Registry = {}}
local A = ZCGoobApps
dofile(root .. "/addons/us1/lua/zc_goobos/kit.lua")
function A.Register(id, _, _, _, _, build) A.Registry[id] = build end
function A.Scroll(parent) local p = vgui.Create("DScrollPanel", parent) p:Dock(FILL) return p end
function A.Status(parent, text) local p = vgui.Create("DLabel", parent) p:SetText(text) return p end
function A.Entry(parent, placeholder, value, onChange) local p = vgui.Create("DTextEntry", parent) p:SetText(value) p.OnValueChange = function(_, v) onChange(v) end return p end
local launched
function A.Launch(id) launched = id return true end
CreateConVar("zc_goobos_share", "1")
dofile(root .. "/addons/us1/lua/zc_goobos/share.lua")
local Sh = A.Share

-- the share sheet, full-screen (no phone) --------------------------------------------------------------------------
local st = Sh.Open({kind = "clip", clip = "1758900000_9001", title = "Killed by Bob"})
assert(st and Sh.Current == st, "the sheet opened")
eq(st.fullscreen, true, "no phone: its own full-screen card")
eq(st.result, "CityLeak is unavailable right now. You can still copy the link.", "CityLeak is not loaded: says so, Copy stays")
frame(520, 262)
local post, copy = button("Post to CityLeak"), button("Copy chat link")
assert(post and copy and button("Cancel"), "Post, Copy and Cancel")
eq(post:IsOn(), false, "Post is greyed without CityLeak"); eq(copy:IsOn(), true, "Copy is live")
st.entry:OnValueChange("so bad")
eq(st.caption, "so bad", "the caption follows the entry")
eq(st.entry:AllowInput(string.rep("x", 1)), false, "typing is allowed under the limit")
st.entry.text = string.rep("x", Sh.CaptionMax)
eq(st.entry:AllowInput("y"), true, "and blocked at CityLeak's limit")
copy:DoClick()
eq(st.busy, "Sharing…", "Copy asks the server first")
net.Receivers.zckc_share = net.Receivers.zckc_share -- (registered by share.lua)
local inbox = {"1758900000_9001", "1758900000_9001", 0, ""}
local at = 0
net.ReadString, net.ReadUInt = function() at = at + 1 return inbox[at] end, function() at = at + 1 return inbox[at] end
net.Receivers.zckc_share()
eq(clipboard, "!clip 1758900000_9001", "link copied"); eq(button("Close") ~= nil, true, "Cancel reads Close once it worked")
frame(520, 262)
-- Esc through Z-City's pause hook closes the full-screen sheet and keeps the menu shut
eq(STUB.hooks["OnShowZCityPause/GoobOS.Share.Esc"](), false, "Esc is taken")
eq(Sh.Current, nil, "closed"); eq(st.entry.gone, true, "its panels are gone")

-- inside the phone: the open app's host --------------------------------------------------------------------------
local phone = vgui.Create("DPanel")
phone:SetSize(400, 700)
phone.GetActive = function() return true end
phone.appHost = vgui.Create("DPanel", phone)
phone.appHost:SetSize(384, 640)
hg = {chat = phone}
local C = {blocked = false}
function C.Available() return true end
function C.Busy() return false end
function C.Nonce() return string.rep("b", 32) end
local req
function C.Request(data, done, fail) req = {data = data, done = done, fail = fail} return true end
ZCGoobFeed = {Client = C}
st = Sh.Open({kind = "round", round = "1758900000_3", at = 75, title = "Round 3"})
eq(st.fullscreen, false, "phone open: a sheet over the app")
eq(st.result, "Players who were in that round can open this moment.", "who can open it")
frame(384, 640)
st.entry:OnValueChange("clutch")
button("Post to CityLeak"):DoClick()
eq(req.data.body, "clutch !replay 1758900000_3 1:15", "posted as a round link")
req.done({kind = "published", id = 9})
frame(384, 640)
local open = button("Open the post in CityLeak")
assert(open, "after posting, Post opens the post")
open:DoClick()
eq(launched, "feed", "CityLeak opened"); eq(C.view, "thread", "on the post"); eq(C.postID, 9, "that post")
eq(STUB.hooks["OnShowZCityPause/GoobOS.Share.Esc"](), nil, "in the phone Esc stays ZChat's")

-- Replays: the list, Clips filter, Load more, the detail pane and the detail sheet ---------------------------------
net.Receivers.zckc_index = function() end -- the viewer's receiver, which the app wraps
dofile(root .. "/addons/us1/lua/zc_goobos/replays.lua")
local S = A.State.replays
local function row(id, t, extra)
    local r = {id = id, t = t, map = "gm_test", tag = "life", role = "victim", other = "Bob", reported = false, missed = false, kind = "", reason = "", post = 0, mine = false}
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end
local now = os.time()
S.rows.mine = {row("1_1", now, {reported = true}), row("1_2", now - 90000, {missed = true, reason = "respawned"})}
S.rows.highlights = {row("2_1", now - 50, {kind = "highlight", tag = "highlight", role = "highlight"})}
S.rows.shared = {row("3_1", now - 10, {kind = "shared", tag = "shared", role = "", other = "Zed: lol", post = 5})}
for scope, list in pairs({mine = S.rows.mine, highlights = S.rows.highlights, shared = S.rows.shared}) do
    for _, r in ipairs(list) do
        r.scope, r.shared = scope, r.kind == "shared"
        r.party = scope ~= "shared"
        r._title, r._meta = r.id, "meta"
    end
end
S.more.shared, S.next.shared = true, 31
local body = vgui.Create("DPanel")
body:SetSize(760, 560)
A.Registry.replays(body, phone)
local area = find(function(p) return p.parent == body and p.Think and p.kids[1] and p.kids[1].class == "DScrollPanel" end)
assert(area, "the list / detail area")
area:SetSize(760, 480)
S.filter, S.dirty = 4, true
frame(740, 480)
local more = button("Load more")
assert(more, "the Clips filter has more shared rows: Load more")
local rounds = button("Full rounds")
assert(rounds and not rounds:IsOn(), "Full rounds is always shown, greyed until the round list exists")
assert(rounds.tooltip and rounds.tooltip:find("not loaded", 1, true), "and says why")
S.selected = "3_1"
S.dirty = true
frame(740, 480)
assert(button("Watch") and button("Share") and button("Open the post in CityLeak"), "detail: Watch, Share, the post")
S.selected, S.dirty = "1_1", true
frame(740, 480)
assert(button("Report a hit"), "your own death: Report")
-- narrow layout: the detail opens as a sheet
area:SetSize(400, 480)
S.filter, S.dirty = 1, true
frame(400, 480)
for _, p in ipairs(created) do if not p.gone and p.DoClick and p.class == "DButton" and p.parent and p.parent.class == "DScrollPanel" and not p.Spec then p:DoClick() break end end
frame(400, 480)
-- Watch in Replays (CityLeak): the Clips filter, that clip, even before the shared list has it
assert(A.Replays.Show("4_4", {name = "Ann", body = "wow", created = now, post = 11, mine = true}), "Show launches Replays")
eq(S.filter, 4, "Clips"); eq(S.rows.focus[1].id, "4_4", "a row for it"); eq(S.rows.focus[1].party, true, "your own post: yours to share")
frame(400, 480)
eq(S.focus, nil, "its detail opened")

print("share ui ok")
