-- GoobOS share sheet (UI cohesion U2, 2026-09-26): post a killcam clip or a round-replay moment to CityLeak, or copy
-- a chat link for it. ZCGoobApps.Share.Open(spec) is the one entry point (death panel, killcam, Replays, CityLeak).
--
-- spec = {kind = "clip", clip = "<stored clip id>"}             a clip on the server (Replays, a CityLeak card)
--      | {kind = "life", seq = "<held death sequence id>"}       the death replay you just watched: SAVED first
--      | {kind = "round", round = "<round id>", at = <seconds>}  a moment of a full round replay
--   + title   short human title ("Killed by Bob", "Highlight · gm_construct")
--   + party   false when the caller knows the player is NOT a party to the clip (someone else's shared clip)
--   + shared  true when the clip is already public (on a live CityLeak post): its link is copied as is
--   + parent  optional panel to open the sheet in; default: the open phone app, else a full-screen card
--
-- Where things go: "Post to CityLeak" publishes through CityLeak's own request (feed.lua C.Request, op "publish" with
-- `clip`; the server checks the poster is a party). A round moment has no clip: it is posted as its "!replay" link in
-- the post text (no schema change). "Copy chat link" puts "!clip <id>" / "!replay <round> <m:ss>" on the clipboard;
-- links.lua makes both clickable in chat for everyone, and feed_ui.lua gives posts that carry one a Watch button. A
-- chat link to a clip is registered on the server first (zckc_share), so friends who were not in it can open it.
if not CLIENT then return end
ZCGoobApps = ZCGoobApps or {}
ZCGoobApps.Share = ZCGoobApps.Share or {}
local A = ZCGoobApps
local Sh = A.Share

Sh.CaptionMax = 1200 -- CityLeak's post limit, in bytes (sv_feed_store.lua F.Publish)
Sh.Wait = 8 -- seconds a zckc_share request may take before the sheet gives up on it

local function validId(id) return isstring(id) and #id <= 24 and string.match(id, "^%d+_%d+$") ~= nil end
Sh.ValidId = validId

function Sh.Enabled()
    local cv = GetConVar("zc_goobos_share")
    return cv ~= nil and cv:GetBool()
end
-- The server half of chat-link sharing and life saves (zc_killcam/sv_net.lua); absent on a server that predates it.
local function serverShares() return util.NetworkStringToID("zckc_share") ~= 0 end

-- "m:ss" for a round time in seconds (the kit's clock when it is loaded, the same format either way).
function Sh.Clock(seconds)
    local K = A.Kit
    if K and K.Clock then return K.Clock(seconds) or "0:00" end
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end
function Sh.ClipLink(id) return "!clip " .. id end
function Sh.RoundLink(round, at) return "!replay " .. round .. " " .. Sh.Clock(at) end

----------------------------------------------------------------- chat / post links
-- The one parser for "!clip <id>" and "!replay <round> <m:ss>", shared by chat (links.lua) and CityLeak (feed_ui.lua).
-- `text` must already be lower-cased by the caller when it wants "!CLIP" to count; byte `i` is the "!". Returns the
-- link and the byte it ends on, or nil. The token must not be glued to a word on its right.
function Sh.MatchLink(text, i)
    if not isstring(text) then return nil end
    local _, e, id = string.find(text, "^!clip +(%d+_%d+)", i)
    if e and #id <= 24 and not string.find(string.sub(text, e + 1, e + 1), "[%w_]") then
        return {kind = "clip", id = id}, e
    end
    local _, e2, round, m, s = string.find(text, "^!replay +(%d+_%d+) +(%d%d?%d?):([0-5]%d)", i)
    if e2 and #round <= 24 and not string.find(string.sub(text, e2 + 1, e2 + 1), "[%w_:]") then
        return {kind = "round", round = round, at = tonumber(m) * 60 + tonumber(s), time = m .. ":" .. s}, e2
    end
    return nil
end
-- The first share link anywhere in `text` (a CityLeak post body), or nil. "!" glued to a word or another "!" is not one.
function Sh.FindLink(text)
    if not isstring(text) or not string.find(text, "!", 1, true) then return nil end
    local lower, from = string.lower(text), 1
    while true do
        local s = string.find(lower, "!", from, true)
        if not s then return nil end
        if not string.find(s > 1 and string.sub(lower, s - 1, s - 1) or "", "[%w_!]") then
            local link = Sh.MatchLink(lower, s)
            if link then return link end
        end
        from = s + 1
    end
end
-- What a link reads as in chat: the "App › Page" form of links.lua ("Replays › Clip 26 Sep 14:05").
function Sh.LinkLabel(link)
    if not istable(link) then return "" end
    if link.kind == "round" then return "Replays › Round at " .. (link.time or Sh.Clock(link.at)) end
    local born = tonumber(string.match(link.id or "", "^(%d+)_"))
    if not born or born < 1000000000 then return "Replays › Clip" end
    local when = os.date("%Y%m%d", born) == os.date("%Y%m%d") and os.date("%H:%M", born) or os.date("%d %b %H:%M", born)
    return "Replays › Clip " .. when
end

local function notify(title, body)
    if A.Notify and isfunction(A.Notify.Push) then A.Notify.Push({app = "Replays", glyph = "play", title = title, body = body}) end
end
-- Opens what a link points at: a clip in the one clip player (media.lua), a round moment in the round replay
-- (viewer bundle cl_part_09.lua, the same V.OpenRound the `zc_replay <round> <m:ss>` command runs).
function Sh.OpenLink(link)
    if not istable(link) then return false end
    if link.kind == "clip" then
        local M = A.Media
        return istable(M) and isfunction(M.OpenClip) and M.OpenClip(link.id) or false
    end
    if link.kind ~= "round" or not validId(link.round) then return false end
    local V = rawget(_G, "ZCKillcamView")
    local commands = concommand.GetTable and concommand.GetTable() or {}
    if not (istable(V) and isfunction(V.OpenRound)) and not commands["zc_replay"] then
        notify("Round replays are still loading", "Try again in a moment.")
        return false
    end
    local phone = hg and hg.chat
    if IsValid(phone) and phone.GetActive and phone:GetActive() then phone:SetActive(false) end
    if istable(V) and isfunction(V.OpenRound) then
        if V.OpenRound(link.round, math.max(0, math.floor(tonumber(link.at) or 0)) * 100) == false then
            notify("That round replay did not open", "Not while you are alive in a live round or a killcam is on screen.")
            return false
        end
        return true
    end
    RunConsoleCommand("zc_replay", link.round, Sh.Clock(link.at))
    return true
end

----------------------------------------------------------------- availability
-- ok, reason: can this spec be shared at all (the sheet still opens to say why not).
function Sh.Available(spec)
    if not istable(spec) then return false, "Nothing to share." end
    if not Sh.Enabled() then return false, "Sharing is turned off on this server." end
    if spec.kind == "clip" then
        if not validId(spec.clip) then return false, "That clip cannot be shared." end
        if spec.party == false and not spec.shared then return false, "Only players in this clip can share it." end
        if not spec.shared and not serverShares() then return false, "Sharing is not available on this server yet." end
    elseif spec.kind == "life" then
        if not validId(spec.seq) then return false, "This replay cannot be shared." end
        if not serverShares() then return false, "Sharing is not available on this server yet." end
    elseif spec.kind == "round" then
        if not validId(spec.round) or not isnumber(spec.at) or spec.at < 0 then return false, "That round moment cannot be shared." end
    else
        return false, "Nothing to share."
    end
    return true
end
local function feedClient()
    local F = rawget(_G, "ZCGoobFeed")
    return istable(F) and istable(F.Client) and F.Client or nil
end
-- ok, reason: can it go to CityLeak right now (on top of Sh.Available).
function Sh.CanPost(spec)
    local ok, why = Sh.Available(spec)
    if not ok then return false, why end
    if spec.kind == "clip" and spec.party == false then return false, "Only players in this clip can post it. Copy its link instead." end
    local C = feedClient()
    if not C or not C.Available() or C.blocked then return false, "CityLeak is unavailable right now. You can still copy the link." end
    return true
end
-- The longest caption that still fits CityLeak's limit (a round moment's link rides in the same text).
function Sh.CaptionLimit(spec)
    if istable(spec) and spec.kind == "round" and validId(spec.round) then return Sh.CaptionMax - #Sh.RoundLink(spec.round, spec.at) - 1 end
    return Sh.CaptionMax
end
-- Cuts `text` to at most `max` bytes without splitting a UTF-8 character.
function Sh.Cut(text, max)
    text = tostring(text or "")
    if #text <= max then return text end
    local cut = max
    while cut > 0 do
        local b = string.byte(text, cut + 1)
        if not b or b < 128 or b >= 192 then break end -- the next byte starts a character: cutting here is clean
        cut = cut - 1
    end
    return string.sub(text, 1, cut)
end
-- The post text for a spec and a caption.
function Sh.PostBody(spec, caption)
    caption = string.Trim(Sh.Cut(caption, Sh.CaptionLimit(spec)))
    if spec.kind ~= "round" then return caption end
    local link = Sh.RoundLink(spec.round, spec.at)
    return caption ~= "" and (caption .. " " .. link) or link
end

----------------------------------------------------------------- server round trip (zckc_share, sv_net.lua)
-- One request at a time. done(clip, code, text): code 0 = ok and `clip` is the id to share; anything else is a
-- refusal and `text` says why (7 = no answer in time, a client-side code).
function Sh.Ask(kind, id, link, done)
    local p = Sh.Pending
    if p and RealTime() - p.sent < Sh.Wait then return false end
    Sh.Pending = {id = id, done = done, sent = RealTime()}
    net.Start("zckc_share")
    net.WriteString(kind)
    net.WriteString(id)
    net.WriteBool(link == true)
    net.SendToServer()
    return true
end
net.Receive("zckc_share", function()
    local id, clip, code, text = net.ReadString(), net.ReadString(), net.ReadUInt(3), net.ReadString()
    local p = Sh.Pending
    if not p or p.id ~= id then return end
    Sh.Pending = nil
    if code == 0 and not validId(clip) then code, text = 2, "That clip has expired." end
    p.done(clip, code, text)
end)
hook.Add("Think", "GoobOS.Share.Wait", function()
    local p = Sh.Pending
    if p and RealTime() - p.sent > Sh.Wait then
        Sh.Pending = nil
        p.done("", 7, "The server did not answer. Try again.")
    end
end)

----------------------------------------------------------------- actions (shared by the sheet and tests)
local function result(st, text, tone)
    st.result, st.tone = text, tone or "info"
end
-- Finds the clip id to publish or link: a stored clip as is, a death sequence saved first, a chat link registered.
local function resolveClip(st, link, done)
    local spec = st.spec
    if spec.kind == "clip" and (spec.shared or not link) then return done(spec.clip) end
    local id = spec.kind == "life" and spec.seq or spec.clip
    st.busy = spec.kind == "life" and "Saving your replay…" or "Sharing…"
    if not Sh.Ask(spec.kind, id, link, function(clip, code, text)
        st.busy = nil
        if code ~= 0 then return result(st, text ~= "" and text or "The server refused to share it.", "bad") end
        if spec.kind == "life" then st.saved = clip end
        done(clip)
    end) then
        st.busy = nil
        result(st, "Still sharing something else. Try again in a moment.", "bad")
    end
end
local function publish(st, body, clip)
    local C = feedClient()
    if not C then return result(st, "CityLeak is unavailable right now.", "bad") end
    if st.nonceFor ~= body .. "|" .. tostring(clip) then st.nonce, st.nonceFor = C.Nonce(), body .. "|" .. tostring(clip) end
    st.busy = "Posting to CityLeak…"
    local sent = C.Request({op = "publish", body = body, nonce = st.nonce, bytes = 0, clip = clip}, function(res)
        st.busy = nil
        st.posted = tonumber(res and res.id)
        result(st, "Posted to CityLeak", "good")
    end, function(err)
        st.busy = nil
        result(st, tostring(err or "CityLeak refused the post."), "bad")
    end)
    if not sent then
        st.busy = nil
        result(st, C.Busy() and "CityLeak is busy. Try again in a moment." or (C.message or "CityLeak is unavailable right now."), "bad")
    end
end
function Sh.Post(st)
    if st.busy then return false end
    local spec = st.spec
    local ok, why = Sh.CanPost(spec)
    if not ok then result(st, why, "bad") return false end
    local C = feedClient()
    if C.Busy() then result(st, "CityLeak is busy. Try again in a moment.", "bad") return false end
    local body = Sh.PostBody(spec, st.caption)
    if spec.kind == "round" then publish(st, body, nil) return true end
    resolveClip(st, false, function(clip) publish(st, body, clip) end)
    return true
end
function Sh.Copy(st)
    if st.busy then return false end
    local spec = st.spec
    local ok, why = Sh.Available(spec)
    if not ok then result(st, why, "bad") return false end
    local function copy(link)
        SetClipboardText(link)
        result(st, "Link copied: " .. link, "good")
    end
    if spec.kind == "round" then copy(Sh.RoundLink(spec.round, spec.at)) return true end
    resolveClip(st, true, function(clip) copy(Sh.ClipLink(clip)) end)
    return true
end

----------------------------------------------------------------- the sheet
local function phoneHost()
    local phone = hg and hg.chat
    if not (IsValid(phone) and phone.GetActive and phone:GetActive()) then return nil end
    local host = phone.appHost
    return IsValid(host) and host:IsVisible() and host or nil
end

-- A centred card over a dimmed screen, for the full-screen callers (death panel, killcam): K.Sheet needs a parent.
local function fullscreenHost(height)
    local K, T = A.Kit, A.Theme
    local host = vgui.Create("EditablePanel")
    host:SetPos(0, 0)
    host:SetSize(ScrW(), ScrH())
    host:SetZPos(32760) -- above the media player (32750)
    host.Paint = function(_, w, h) draw.RoundedBox(0, 0, 0, w, h, K.Alpha(T.ink, 170)) end
    local box = K.Panel(host)
    local function place(w, h)
        local bw = math.min(520, w - 32)
        box:SetSize(bw, height)
        box:SetPos(math.floor((w - bw) / 2), math.floor((h - height) / 2))
    end
    place(ScrW(), ScrH())
    host.PerformLayout = function(_, w, h) place(w, h) end
    host.Think = function(s)
        if s:GetWide() ~= ScrW() or s:GetTall() ~= ScrH() then s:SetSize(ScrW(), ScrH()) end
    end
    host:MakePopup()
    host:SetKeyboardInputEnabled(true)
    return host, box
end

local KIND_LINE = {clip = "Killcam clip", life = "Your death replay · it is saved to Replays when you share it"}
local HEIGHT = 262

function Sh.Close()
    local st = Sh.Current
    Sh.Current = nil
    if st and st.close then st.close() end
end
-- Esc: Z-City replaces the game menu (its OnPauseMenuShow opens ZMainMenu and returns false), so the game UI never
-- shows and asks OnShowZCityPause first. A sheet on its own full-screen card closes and the menu stays shut. A sheet
-- inside the phone leaves Esc to ZChat (it closes the phone, and the sheet with it) - the viewer's rule for chat too.
hook.Add("OnShowZCityPause", "GoobOS.Share.Esc", function()
    local st = Sh.Current
    if not st or not st.fullscreen then return end
    Sh.Close()
    return false
end)

-- Opens the share sheet. Returns the sheet state (st.result is the one result line), or nil when the kit is missing.
function Sh.Open(spec)
    local K, T = A.Kit, A.Theme
    if not (K and K.Sheet and K.Button) or not istable(spec) then return nil end
    Sh.Close()
    local st = {spec = spec, caption = ""}
    Sh.Current = st
    local ok, why = Sh.Available(spec)
    local postOk, postWhy = Sh.CanPost(spec)
    if not ok then result(st, why, "bad")
    elseif not postOk then result(st, postWhy, "info")
    elseif spec.kind == "round" then result(st, "Players who were in that round can open this moment.", "info") end

    local parent = IsValid(spec.parent) and spec.parent or phoneHost()
    local host, box
    if not parent then host, box = fullscreenHost(HEIGHT) parent = box end
    local sheet, shade = K.Sheet(parent, HEIGHT, host == nil)
    st.fullscreen = host ~= nil
    st.close = function()
        if IsValid(shade) then shade:Close() end
        if IsValid(host) then host:Remove() end
    end
    shade.OnRemove = function()
        if Sh.Current == st then Sh.Current = nil end
        if IsValid(host) then host:Remove() end
    end
    -- Without Z-City's menu (OnShowZCityPause above), Esc opens the game menu: close the sheet and put the menu away.
    local menuUp = gui.IsGameUIVisible and gui.IsGameUIVisible() or false
    local think = shade.Think
    shade.Think = function(s)
        think(s)
        local up = gui.IsGameUIVisible and gui.IsGameUIVisible() or false
        if up and not menuUp and not (gui.IsConsoleVisible and gui.IsConsoleVisible()) then
            gui.HideGameUI()
            st.close()
            return
        end
        menuUp = up
    end

    local head = K.Panel(sheet)
    head:Dock(TOP)
    head:SetTall(42)
    local what = spec.kind == "round" and ("Round moment at " .. Sh.Clock(spec.at)) or KIND_LINE[spec.kind] or ""
    head.Paint = function(_, w)
        K.Text(K.Fit("Share · " .. tostring(spec.title or what), K.Font(16, 700), w), 16, 700, 0, 0, T.text)
        K.Text(K.Fit(what, K.Font(12, 500), w), 12, 500, 0, 22, T.muted)
    end

    local limit = Sh.CaptionLimit(spec)
    local entry = A.Entry(sheet, "Add a caption (optional)", "", function(value) st.caption = value end)
    entry.AllowInput = function(s, char) return #s:GetValue() + #(char or "") > limit end
    entry.OnEnter = function() Sh.Post(st) end
    local baseKey = entry.OnKeyCodeTyped
    entry.OnKeyCodeTyped = function(s, code)
        if code == KEY_ESCAPE then st.close() return true end
        if baseKey then return baseKey(s, code) end
    end
    st.entry = entry

    local idle = function() return not st.busy end
    K.Button(sheet, {label = function() return st.posted and "Open the post in CityLeak" or "Post to CityLeak" end, kind = "primary", key = "Enter",
        enabled = function() return idle() and (st.posted ~= nil or (Sh.CanPost(spec))) end,
        click = function()
            if not st.posted then return Sh.Post(st) end
            local C = feedClient()
            if C then C.view, C.postID, C.feedItems = "thread", st.posted, {} end
            st.close()
            if not A.Launch("feed") then notify("Posted to CityLeak", "Open CityLeak on your phone to see it.") end
        end})
    K.Button(sheet, {label = "Copy chat link", glyph = "chat", enabled = function() return idle() and (Sh.Available(spec)) end, click = function() Sh.Copy(st) end})
    K.Button(sheet, {label = function() return (st.posted or st.tone == "good") and "Close" or "Cancel" end, kind = "quiet", key = "Esc", click = function() st.close() end})

    local line = K.Panel(sheet)
    line:Dock(TOP)
    line:SetTall(22)
    line.Paint = function(_, w, h)
        local text = st.busy or st.result
        local color = st.busy and T.muted or (st.tone == "good" and T.green) or (st.tone == "bad" and T.red) or T.muted
        local count = #(st.caption or "") > 0 and (#st.caption .. " / " .. limit) or nil
        local room = w - (count and 80 or 0)
        if text then K.Text(K.Fit(text, K.Font(13, 600), room), 13, 600, 0, h / 2, color, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
        if count then K.Text(count, 11, 500, w, h / 2, #st.caption > limit and T.red or T.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end
    end
    entry:RequestFocus()
    return st
end
