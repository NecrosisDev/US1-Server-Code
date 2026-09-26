-- GoobOS notifications (Phase 3): iOS-style push cards (top centre, stack of 3) and compact banners, on the kit.
-- Server switch zc_goobos_notify (replicated, created in lua/autorun/zc_goobos_apps.lua), default 0 = today's
-- surfaces unchanged. With 1:
--   * ULX votes: the GoobOS vote card replaces ZChat's vote card and the base HUD option box. Number keys keep
--     working through the same base PlayerOption binding ULX already uses (only while the vote is open).
--   * Private/group messages: ZCChatThreads.Notify (the in-frame "New message" strip) becomes a push card.
--   * ZChat system banners (joins, leaves, server lines) become GoobOS banners; the chat keeps its own history.
--   * CityLeak reactions/replies to your post arrive from the server as pushes (net GoobOS.Notify, sv_feed.lua).
--   * Round start/end banners.
-- Vote-manager state (net zc_vm_state, {kind,title,endsAt,queued}) feeds the "queued" pill on the vote card.
if not CLIENT then return end
local A = ZCGoobApps
if not A then return end
local N = A.Notify or {}
A.Notify = N
N.Version = "20260926.notify3"
N.Stack, N.Banners, N.VMState, N.Wraps = N.Stack or {}, N.Banners or {}, N.VMState or {}, N.Wraps or {}
-- Recent pushes for the home-screen tray (mockup 00: CityLeak reactions etc. with a time). Votes and
-- private-message pushes stay out: votes expire, and unread threads already feed the tray directly.
N.History, N.HistorySerial = N.History or {}, N.HistorySerial or 0
local MAX_HISTORY = 12
local T = A.Theme
local DWELL, ENTER, EXIT, MAX_PUSH, MAX_BANNER, BANNER_DWELL = 4, 0.28, 0.22, 3, 3, 3.5
local LANE_Y, BANNER_H, OPTION_H = 16, 34, 30
local BANNER_LINE = 16 -- extra height per wrapped banner line (13 px font)

function N.Enabled()
    local cv = GetConVar("zc_goobos_notify")
    return cv ~= nil and cv:GetBool() and A.Kit ~= nil
end

-- UI cohesion U3.3 (2026-09-26): the one vote hint on every GoobOS vote surface - the number keys as one keycap and
-- the verb ("1–6 Vote"), plus "Click a tile" where a click casts too - drawn with the kit's hint row (K.Scaler hints).
-- This card and the round-end panel, side card and compact mode vote (roundend.lua) all draw this list. Read-only.
function N.VoteKeys(n)
    n = math.floor(tonumber(n) or 0)
    if n <= 1 then return "1" end
    if n >= 10 then return "1–9, 0" end -- ULX: key 0 is option 10
    return "1–" .. n
end
local voteHintCache = {}
function N.VoteHints(n, clicks)
    local keys = N.VoteKeys(n)
    local key = keys .. (clicks and "+click" or "")
    local hints = voteHintCache[key]
    if not hints then
        hints = {{keys, "Vote"}}
        if clicks then hints[2] = {nil, "Click a tile"} end
        voteHintCache[key] = hints
    end
    return hints
end

local function optionRows(entry)
    local n = math.min(#entry.options, 10)
    return math.max(1, math.ceil(n / math.min(n, 4)))
end

local function cardHeight(entry)
    if entry.options then return A.Kit.NoticeHeight + optionRows(entry) * (OPTION_H + 6) + 34 end -- + the bar and a keycap row
    return A.Kit.NoticeHeight
end

local function remember(entry)
    if entry.kind == "vote" or (isstring(entry.key) and string.sub(entry.key, 1, 3) == "pm:") then return end
    N.HistorySerial = N.HistorySerial + 1
    table.insert(N.History, 1, {id = N.HistorySerial, app = entry.app, glyph = entry.glyph, title = entry.title, body = entry.body,
        at = RealTime(), onClick = entry.onClick})
    while #N.History > MAX_HISTORY do table.remove(N.History) end
end

-- entry = {app, glyph, title, body, duration?, key?, onClick?, options? (vote), endsAt?, initials?}
function N.Push(entry)
    if not istable(entry) then return end
    -- The tray keeps the entry even when push cards are switched off: it is the phone's own list.
    remember(entry)
    if not N.Enabled() then return end
    local now = RealTime()
    entry.born, entry.duration = now, entry.duration or DWELL
    entry.time = entry.time or "now"
    if entry.key then
        for i = #N.Stack, 1, -1 do
            if N.Stack[i].key == entry.key then table.remove(N.Stack, i) end
        end
    end
    table.insert(N.Stack, 1, entry)
    local live = 0
    for _, e in ipairs(N.Stack) do
        if not e.leaving then
            live = live + 1
            if live > MAX_PUSH then e.leaving = now end
        end
    end
    N.Ensure()
    return entry
end

function N.Dismiss(entry)
    if entry and not entry.leaving then entry.leaving = RealTime() end
end

function N.Banner(text, glyph)
    if not N.Enabled() then return end
    text = string.Trim(tostring(text or ""))
    if text == "" then return end
    table.insert(N.Banners, 1, {text = text, glyph = glyph or "bell", born = RealTime()})
    while #N.Banners > MAX_BANNER do table.remove(N.Banners) end
    N.Ensure()
end

-- Drawing ----------------------------------------------------------------------------------------

local function paintVoteExtras(K, entry, x, y, w)
    local options = entry.options
    local total, cols = math.min(#options, 10), math.min(#options, 4)
    local gap = 6
    local each = math.floor((w - 20 - (cols - 1) * gap) / cols)
    local font = K.Font(13, 600)
    entry.hits = entry.hits or {}
    for i = 1, total do
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        local bx = x + 10 + col * (each + gap)
        local by = y + K.NoticeHeight - 4 + row * (OPTION_H + 6)
        local chosen = entry.voted == i
        draw.RoundedBox(4, bx, by, each, OPTION_H, chosen and T.main or T.card)
        draw.SimpleText(K.Fit((i == 10 and 0 or i) .. " · " .. tostring(options[i]), font, each - 10), font, bx + each / 2, by + OPTION_H / 2, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        entry.hits[i] = {bx - x, by - y, each, OPTION_H}
    end
    local left = math.max(0, (entry.endsAt or CurTime()) - CurTime())
    local span = math.max(1, entry.duration or 1)
    local barY = y + K.NoticeHeight - 4 + optionRows(entry) * (OPTION_H + 6) + 2
    draw.RoundedBox(2, x + 10, barY, w - 20, 4, K.Alpha(T.ink, 235))
    draw.RoundedBox(2, x + 10, barY, math.max(4, (w - 20) * math.Clamp(left / span, 0, 1)), 4, T.accent)
    local queued
    for _, e in ipairs(N.VMState) do
        if e.queued then queued = "Queued: " .. tostring(e.title) break end
    end
    -- U3.3: the vote hint as keycap + verb (N.VoteHints); once voted, the choice (and the queue) as a plain line
    local rowY = barY + 8
    if entry.voted then
        local line = "You voted " .. tostring(options[entry.voted]) .. (queued and ("  ·  " .. queued) or "")
        draw.SimpleText(K.Fit(line, K.Font(11, 600), w - 20), K.Font(11, 600), x + w / 2, rowY + 10, T.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        return
    end
    local S = N.Scaler or K.Scaler(1)
    N.Scaler = S
    local hints = N.VoteHints(#options)
    if queued then
        local room = w - 20 - S.hintWidth(hints) - S.u(16)
        hints = {hints[1], {nil, S.fit(queued, 11, 500, math.max(40, room))}}
    end
    S.hints(hints, x + w / 2, rowY, TEXT_ALIGN_CENTER)
end

local function paintLane(panel, w)
    local K = A.Kit
    if not K then return end
    local now = RealTime()
    local y = 0
    -- Push stack: front card full, up to two older cards peek below it, narrower and dimmer.
    local visible = {}
    for _, e in ipairs(N.Stack) do
        if not e.leaving then visible[#visible + 1] = e end
    end
    local front = visible[1]
    panel.Front, panel.FrontY, panel.FrontH = nil, 0, 0
    if front then
        local fh = cardHeight(front)
        for depth = math.min(#visible, MAX_PUSH), 2, -1 do
            local inset = (depth - 1) * 10
            surface.SetAlphaMultiplier(depth == 2 and 0.6 or 0.35)
            K.Card(inset, (depth - 1) * 9 + fh - 20, w - inset * 2, 20, T.glassHi, K.Alpha(T.edge, 160))
        end
        local p = K.EaseOut(K.Progress(front.born, ENTER))
        local offset = math.floor((1 - p) * -(fh + LANE_Y))
        surface.SetAlphaMultiplier(p)
        K.Notice(0, offset, w, front, panel.HoverFront and 1 or 0)
        if front.options then
            K.Card(0, offset + K.NoticeHeight - 8, w, fh - K.NoticeHeight + 8, T.glassHi)
            paintVoteExtras(K, front, 0, offset, w)
        end
        panel.Front, panel.FrontY, panel.FrontH = front, offset, fh
        y = fh + (math.min(#visible, MAX_PUSH) - 1) * 9 + 8
    end
    -- Leaving cards slide up and fade.
    for _, e in ipairs(N.Stack) do
        if e.leaving then
            local t = K.Progress(e.leaving, EXIT)
            surface.SetAlphaMultiplier(1 - t)
            K.Notice(0, math.floor(-t * (cardHeight(e) + LANE_Y)), w, e, 0)
        end
    end
    -- Banners: compact pills under the push stack.
    for _, b in ipairs(N.Banners) do
        local age = now - b.born
        local a = math.min(K.EaseOut(K.Progress(b.born, 0.2)), math.Clamp((BANNER_DWELL - age) / 0.25, 0, 1))
        surface.SetAlphaMultiplier(a)
        local font = K.Font(13, 600)
        -- wrapped onto up to four lines instead of cut to one (owner 2026-09-24 late: ULX announcements)
        if b.wrapW ~= w then
            b.wrapW, b.lines, b.textW = w, K.Wrap(b.text, font, w - 70, 4), 0
            surface.SetFont(font)
            for _, line in ipairs(b.lines) do b.textW = math.max(b.textW, (surface.GetTextSize(line))) end
        end
        local lines = b.lines
        local bh = BANNER_H + (#lines - 1) * BANNER_LINE
        local bw = math.min(w, b.textW + 52)
        local bx = math.floor((w - bw) / 2)
        K.Card(bx, y, bw, bh, T.glassHi, K.Alpha(T.edge, 160))
        K.Dot(bx + 14, y + bh / 2 - 4, 8, b.glyph == "leave" and T.muted or T.green)
        local ty = y + bh / 2 - (#lines - 1) * BANNER_LINE / 2
        for i, line in ipairs(lines) do
            draw.SimpleText(line, font, bx + 32, ty + (i - 1) * BANNER_LINE, T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        y = y + bh + 6
    end
    surface.SetAlphaMultiplier(1)
    panel.ContentH = y
end

function N.Ensure()
    if IsValid(N.Panel) then return N.Panel end
    local panel = vgui.Create("DPanel")
    panel:SetMouseInputEnabled(true)
    panel:SetKeyboardInputEnabled(false)
    panel:SetDrawOnTop(true)
    panel.Paint = paintLane
    panel.OnMousePressed = function(s, code)
        local front = s.Front
        if not front then return end
        local mx, my = s:CursorPos()
        my = my - s.FrontY
        if my < 0 or my > s.FrontH then return end
        if code ~= MOUSE_LEFT then return N.Dismiss(front) end
        if front.options and front.hits and not front.voted then
            for i, r in ipairs(front.hits) do
                if mx >= r[1] and mx <= r[1] + r[3] and my >= r[2] and my <= r[2] + r[4] then
                    if front.onVote then front.onVote(i) end
                    return
                end
            end
        end
        if front.onClick then pcall(front.onClick, front) end
        N.Dismiss(front)
    end
    N.Panel = panel
    return panel
end

-- Lifecycle: one Think hook. Expires entries, positions the lane, hides it under the game menu.
local nextPoll = 0
hook.Add("Think", "GoobOS.Notify", function()
    local panel = N.Panel
    if not IsValid(panel) then return end
    local now = RealTime()
    for i = #N.Stack, 1, -1 do
        local e = N.Stack[i]
        if e.leaving then
            if now - e.leaving >= EXIT then table.remove(N.Stack, i) end
        elseif now - e.born >= e.duration and not panel:IsHovered() then
            e.leaving = now
        end
    end
    for i = #N.Banners, 1, -1 do
        if now - N.Banners[i].born >= BANNER_DWELL then table.remove(N.Banners, i) end
    end
    local show = (#N.Stack > 0 or #N.Banners > 0) and not gui.IsGameUIVisible()
    if panel:IsVisible() ~= show then panel:SetVisible(show) end
    if not show then return end
    -- Only a live push card takes clicks; a banner-only lane lets clicks through to menus beneath it.
    local clickable = panel.Front ~= nil
    if panel.GoobClickable ~= clickable then
        panel.GoobClickable = clickable
        panel:SetMouseInputEnabled(clickable)
    end
    if now >= nextPoll then
        nextPoll = now + 0.1
        local w = math.min(420, ScrW() - 32)
        local h = math.max(1, panel.ContentH or 200) + 4
        panel:SetSize(w, h)
        panel:SetPos(math.floor((ScrW() - w) / 2), LANE_Y)
    end
    panel.HoverFront = panel:IsHovered()
end)

-- Sources ------------------------------------------------------------------------------------------

-- ULX votes (hook fired by addons/ulx/lua/ulx/cl_lib.lua right after AddPlayerOption).
hook.Add("ZC_ULXVoteStarted", "GoobOS.Notify.ULXVote", function(title, timeout, options)
    if not N.Enabled() then return end
    options = istable(options) and options or {}
    title, timeout = tostring(title or "Vote"), tonumber(timeout) or 20
    local entry
    local function vote(id)
        if not options[id] or (entry and entry.voted) then return end
        RunConsoleCommand("ulx_vote", id)
        if entry then
            entry.voted = id
            entry.duration = math.min(entry.duration, RealTime() - entry.born + 1.5)
        end
        return true
    end
    -- Same option name, same input rule as ULX's own callback, but no HUD box: the card draws instead.
    local me = LocalPlayer()
    if IsValid(me) and me.AddPlayerOption then
        me:AddPlayerOption(title, timeout, function(id)
            if id == 0 then id = 10 end
            return vote(id)
        end, function() end)
    end
    timer.Simple(0, function()
        if hg and IsValid(hg.ZCChatVotePush) then
            hg.ZCChatVotePush:Remove()
            hg.ZCChatVotePush = nil
        end
    end)
    entry = N.Push({kind = "vote", key = "ulx", app = "Vote", glyph = "check", title = title,
        body = #options .. " options · " .. A.Kit.Clock(timeout), options = options,
        endsAt = CurTime() + timeout, duration = timeout})
    if entry then
        entry.onVote = function(id)
            if vote(id) and IsValid(me) and me.AddPlayerOption then
                me:AddPlayerOption(title, 0, function() end, function() end) -- clears the key binding once voted by click
            end
        end
    end
end)

net.Receive("zc_vm_state", function()
    local list = net.ReadTable()
    N.VMState = istable(list) and list or {}
end)

-- Server pushes (CityLeak reactions / replies to your post).
net.Receive("GoobOS.Notify", function()
    local app, title, body = net.ReadString(), net.ReadString(), net.ReadString()
    if app == "feed" then
        N.Push({app = "CityLeak", glyph = "news", title = title, body = body, onClick = function() A.Launch("feed") end})
    end
end)

-- Round start / end banners from the round state everyone already has.
-- U3.1 (UI cohesion 2026-09-26): one announcement per round end. With the GoobOS panels on, the round-end winner card
-- (roundend.lua) announces the result at this same ROUND_STATE 1 -> 3 edge, so the "round over" banner would say it a
-- second time. Its phase may not be set yet when this poll runs first, hence P.Enabled() - the gate it enters on.
function N.RoundEndOwned()
    local P, RE = A.Panels, A.RoundEnd
    if not (istable(RE) and istable(P) and isfunction(P.Enabled)) then return false end
    return RE.Phase == "winner" or RE.Phase == "panel" or P.Enabled() == true
end
local lastRound
local function roundBanner()
    if not istable(zb) then return end
    local state = zb.ROUND_STATE
    if state == lastRound then return end
    local previous = lastRound
    lastRound = state
    if previous == nil or not N.Enabled() then return end
    local mode = zb.CROUND and (string.gsub(string.gsub(tostring(zb.CROUND), "_", " "), "^%l", string.upper)) or "Round"
    if state == 1 then N.Banner(mode .. " · round started", "round")
    elseif state == 3 and previous == 1 and not N.RoundEndOwned() then N.Banner(mode .. " · round over", "round") end
end
timer.Create("GoobOS.Notify.Round", 0.5, 0, roundBanner)

-- Wraps (identity-checked; re-installed if another load replaces the function).
local function installWraps()
    local threads = ZCChatThreads
    if istable(threads) and isfunction(threads.Notify) and threads.Notify ~= N.Wraps.notify then
        local original = threads.Notify
        N.Wraps.notifyOriginal = original
        N.Wraps.notify = function(chat, s)
            if not N.Enabled() or not istable(s) then return original(chat, s) end
            if ZCPhoneSettings and ZCPhoneSettings.Get and ZCPhoneSettings.Get("private") == 0 then return end
            if (s.notified or -10) + 3 > RealTime() then return end
            s.notified = RealTime()
            local group = ZCChatGroupUI and ZCChatGroupUI.IsGroup and ZCChatGroupUI.IsGroup(s.key)
            local unread = tonumber(s.unread) or 1
            local rows = istable(s.entries) and s.entries or {}
            local last = rows[#rows]
            local preview = A.MessageRowText and IsValid(last) and A.MessageRowText(last) or ""
            local name = tostring(s.name or "Message")
            N.Push({key = "pm:" .. tostring(s.key), app = group and "Group chat" or "Messages", glyph = group and "chat" or "mail",
                initials = not group and string.upper(string.sub(name, 1, (utf8.offset(name, 2) or 2) - 1)) or nil,
                title = name, body = unread > 1 and unread .. " new messages" or (preview ~= "" and preview or "New message"),
                onClick = function()
                    if A.OpenMessageThread and A.OpenMessageThread(chat, s.key) then return end
                    if IsValid(chat) and threads.Open then threads.Open(chat, s.key, s.name) end
                end})
        end
        threads.Notify = N.Wraps.notify
    end
    local control = vgui.GetControlTable and vgui.GetControlTable("zChatbox")
    if istable(control) and isfunction(control.ShowSystemBanner) and control.ShowSystemBanner ~= N.Wraps.banner then
        local original = control.ShowSystemBanner
        N.Wraps.bannerOriginal = original
        N.Wraps.banner = function(self, elements)
            if not N.Enabled() or not istable(elements) then return original(self, elements) end
            if self.bannerMuted then return end
            local parts = {}
            for _, value in ipairs(elements) do
                if isstring(value) or isnumber(value) then parts[#parts + 1] = tostring(value) end
                if type(value) == "Player" and IsValid(value) then parts[#parts + 1] = value:Nick() end
            end
            local message = string.Trim(table.concat(parts))
            if message == "" then return end
            if ZCChatThreads and ZCChatThreads.PlayNotification then ZCChatThreads.PlayNotification("main") end
            local lower = string.lower(message)
            N.Banner(message, (string.find(lower, "left", 1, true) or string.find(lower, "disconnect", 1, true)) and "leave" or "join")
        end
        control.ShowSystemBanner = N.Wraps.banner
    end
end
hook.Add("InitPostEntity", "GoobOS.Notify.Wraps", installWraps)
timer.Create("GoobOS.Notify.Wraps", 2, 0, installWraps)
installWraps()
