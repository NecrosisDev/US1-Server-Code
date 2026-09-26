-- GoobOS Messages app (BRIEF Stage D1): a VIEW over the existing PM/group chat transport --
-- zc_chat_media/threads.lua (global ZCChatThreads) and groups.lua (global ZCChatGroupUI), both read
-- in full for this file. No new net messages: every read/select/send/mute/directory action below
-- calls an existing ZCChatThreads.* or ZCChatGroupUI.* function exactly as the classic ZChat tab
-- strip already does. Client only; no server file.
if not CLIENT then return end
local A = ZCGoobApps
if not A or not A.Register then return end
local K = A.Kit
if not K then return end
local Theme = A.Theme

-- Kit candidates: "bell" already exists in K.Glyphs; these three don't, so they're added the same
-- way donate.lua adds "heart" -- mutating the shared registry from an app file, not editing kit.lua.
if K.Glyphs then
    if not K.Glyphs.send then K.Glyphs.send = {{"c", 22, 2, 15, 22, 11, 13, 2, 9}, {"l", 22, 2, 11, 13}} end
    if not K.Glyphs.plus then K.Glyphs.plus = {{"l", 12, 4, 12, 20}, {"l", 4, 12, 20, 12}} end
    if not K.Glyphs.chevronleft then K.Glyphs.chevronleft = {{"l", 15, 4, 8, 12, 15, 20}} end
end

-- Bubble colours: cl_zchat.lua:45-46 ZC_BUBBLE_OWN/ZC_BUBBLE_PEER, hoisted to file scope (never
-- allocated inside Paint).
local BUBBLE_OWN = Color(111, 32, 36)
local BUBBLE_PEER = Color(48, 46, 49)
local LIST_BREAKPOINT = 560 -- BRIEF D1: two panes at/above this body width; list-only below it.
local LIST_W = 280
local AVATAR_SIZE = 40
local ROW_HEIGHT = 58
local BUBBLE_FONT, BUBBLE_LINE_H = 13, 17
local HUES = {Theme.main, Theme.accent, Theme.gold, Theme.green, Theme.red}

local function hue(name)
    local text, sum = tostring(name or ""), 0
    for i = 1, #text do sum = sum + string.byte(text, i) end
    return HUES[(sum % #HUES) + 1]
end

local function initials(name)
    name = tostring(name or "")
    local a, b = name:match("^(%S)%S*%s*(%S?)")
    return string.upper((a or "?") .. (b or ""))
end

local function paintInitials(x, y, size, name)
    draw.RoundedBox(4, x, y, size, size, hue(name))
    K.Text(initials(name), math.floor(size * 0.42), 700, x + size / 2, y + size / 2, Theme.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- Every non-main row's elements are built as {colour, speaker-or-name, colour, ": " .. text}
-- (threads.lua:286, groups.lua:201); row.ZCSourceElements is that same table, read-only here.
local function rowText(row)
    local elements = row.ZCSourceElements
    local raw = elements and elements[4]
    if not isstring(raw) then return "" end
    if raw:sub(1, 2) == ": " then return raw:sub(3) end
    return raw
end
-- Shared with the home tray and PM push cards (last line as the preview, mockups 00 and 09).
A.MessageRowText = rowText

-- Open the Messages app on one conversation (home tray card, PM push card). Returns false when the
-- phone cannot show it, so callers fall back to ZChat's own thread tab.
function A.OpenMessageThread(phone, key)
    if not IsValid(phone) or not phone.SetPhonePage or not A.Registry.messages then return false end
    if not (phone.ZCThreads and phone.ZCThreads[key]) then return false end
    A.State.messagesOpen = key
    if phone.GetActive and not phone:GetActive() then phone:SetActive(true) end
    phone:SetPhonePage("messages")
    return phone.phonePage == "messages"
end

local function relativeTime(arrived)
    if not arrived then return "" end
    local age = math.max(0, RealTime() - arrived)
    if age < 60 then return "now" end
    if age < 3600 then return math.floor(age / 60) .. "m" end
    if age < 86400 then return math.floor(age / 3600) .. "h" end
    if age < 172800 then return "Yesterday" end
    return math.floor(age / 86400) .. "d"
end

-- cl_zchat.lua:1064 uses this same os.time()-minus-RealTime()-delta trick to date-stamp a row.
local function approxEpoch(arrived)
    return os.time() - math.max(0, math.floor(RealTime() - (arrived or RealTime())))
end

local function dayLabel(epoch)
    local d, now = os.date("*t", epoch), os.date("*t")
    if d.year == now.year and d.yday == now.yday then return "Today" end
    local y = os.date("*t", os.time() - 86400)
    if d.year == y.year and d.yday == y.yday then return "Yesterday" end
    return os.date("%b %d", epoch)
end

local function utf8Chars(text)
    local chars, count = {}, utf8.len(text) or #text
    for i = 1, count do
        local a = utf8.offset(text, i)
        local b = utf8.offset(text, i + 1)
        chars[i] = (a and b) and text:sub(a, b - 1) or (a and text:sub(a)) or ""
    end
    return chars
end

-- Greedy word wrap, cached per (font, width, text) like K.Fit -- safe to call from Paint. Kit
-- candidate: every future chat-shaped surface needs this, not just Messages.
local wrapCache, wrapCount = {}, 0
local function wrapText(text, font, maxWidth)
    text = tostring(text or "")
    local key = font .. "|" .. math.floor(maxWidth) .. "|" .. text
    local hit = wrapCache[key]
    if hit then return hit end
    if wrapCount >= 256 then wrapCache, wrapCount = {}, 0 end
    surface.SetFont(font)
    local lines, line = {}, ""
    for word in text:gmatch("%S+") do
        local candidate = line == "" and word or (line .. " " .. word)
        if surface.GetTextSize(candidate) <= maxWidth then
            line = candidate
        else
            if line ~= "" then lines[#lines + 1] = line end
            if surface.GetTextSize(word) <= maxWidth then
                line = word
            else
                local part = ""
                for _, ch in ipairs(utf8Chars(word)) do
                    local candidate2 = part .. ch
                    if surface.GetTextSize(candidate2) > maxWidth and part ~= "" then
                        lines[#lines + 1] = part
                        part = ch
                    else
                        part = candidate2
                    end
                end
                line = part
            end
        end
    end
    lines[#lines + 1] = line
    wrapCache[key] = lines
    wrapCount = wrapCount + 1
    return lines
end

-- Bubble/day/system block layout for one thread at one width, cached until the entry count or
-- width changes (BRIEF: "paint bubbles in one panel with cached wrapped lines").
local layoutCache = {}
local function buildLayout(phone, key, width)
    local threads = phone.ZCThreads
    local s = threads and threads[key]
    if not s then return {blocks = {}, total = 0} end
    local sig = key .. "|" .. #s.entries .. "|" .. width
    local cached = layoutCache[key]
    if cached and cached.sig == sig then return cached end
    local isGroup = ZCChatGroupUI and ZCChatGroupUI.IsGroup(key)
    local font = K.Font(BUBBLE_FONT, 500)
    local maxBubble = math.max(90, math.floor(width * 0.78) - 18)
    local blocks, y = {}, 0
    local lastDay, lastSender = nil, nil
    local function push(block, height, gap)
        block.y, block.h = y + gap, height
        blocks[#blocks + 1] = block
        y = block.y + height
    end
    for _, row in ipairs(s.entries) do
        if IsValid(row) then
            local arrived = row.ZCArrived or RealTime()
            local epoch = approxEpoch(arrived)
            local dayKey = os.date("%Y-%m-%d", epoch)
            if dayKey ~= lastDay then
                push({kind = "day", label = dayLabel(epoch) .. "  " .. os.date("%H:%M", epoch)}, 22, lastDay and 14 or 0)
                lastDay, lastSender = dayKey, nil
            end
            local text = rowText(row)
            if row.ZCCensored then
                -- No membership-change signal reaches a group thread in the read transport, so the
                -- only "system line" this view can show is the existing spectator/moderation
                -- placeholder text (threads.lua:276, groups.lua:198 already replace `text` with it).
                push({kind = "system", label = text ~= "" and text or "Message hidden"}, 20, 10)
                lastSender = nil
            else
                local senderKey = row.ZCSenderSteam or row.ZCSenderName or "?"
                local grouped = senderKey == lastSender
                local showSender = isGroup and not row.ZCOwn and not grouped
                local lines = wrapText(text, font, maxBubble)
                surface.SetFont(font)
                local widest = 0
                for _, line in ipairs(lines) do widest = math.max(widest, surface.GetTextSize(line)) end
                local h = 12 + #lines * BUBBLE_LINE_H + (showSender and 14 or 0)
                push({kind = "bubble", own = row.ZCOwn, sender = row.ZCSenderName, showSender = showSender,
                    lines = lines, w = math.min(maxBubble, widest) + 18}, h, grouped and 3 or 10)
                lastSender = senderKey
            end
        end
    end
    local result = {sig = sig, blocks = blocks, total = y}
    layoutCache[key] = result
    return result
end

local function paintBlock(block, w, top, bottom, h)
    if top > h or bottom < 0 then return end
    if block.kind == "day" then
        K.Text(block.label, 11, 600, w / 2, top + 4, Theme.muted, TEXT_ALIGN_CENTER)
    elseif block.kind == "system" then
        K.Text(K.Fit(block.label, K.Font(11, 500), w - 20), 11, 500, w / 2, top + 4, Theme.muted, TEXT_ALIGN_CENTER)
    else
        local bx = block.own and math.max(4, w - block.w - 4) or 4
        local by = top
        if block.showSender then
            K.Text(K.Fit(block.sender or "", K.Font(11, 600), block.w), 11, 600, bx + 3, by, Theme.muted)
            by = by + 14
        end
        draw.RoundedBox(4, bx, by, block.w, block.h - (block.showSender and 14 or 0), block.own and BUBBLE_OWN or BUBBLE_PEER)
        local ty = by + 6
        for _, line in ipairs(block.lines) do
            K.Text(line, BUBBLE_FONT, 500, bx + 9, ty, Theme.white)
            ty = ty + BUBBLE_LINE_H
        end
    end
end

local function groupInitials(key, fallback)
    local meta = ZCChatGroupUI and ZCChatGroupUI.meta and ZCChatGroupUI.meta[key]
    local names, me = {}, IsValid(LocalPlayer()) and LocalPlayer():SteamID64()
    if meta and meta.members then
        for _, member in ipairs(meta.members) do
            if member.id ~= me then names[#names + 1] = member.name end
            if #names >= 2 then break end
        end
    end
    if #names == 0 then names = {fallback, fallback} end
    if #names == 1 then names[2] = names[1] end
    return names
end

local function build(body, phone)
    local state = {query = "", selectedKey = nil, view = "list", composeText = "", syncedGroups = {}, NextPoll = 0}
    local rows = {}
    local openThread, sendCurrent, refreshList

    local listPane = K.Panel(body)
    local threadPane = K.Panel(body)

    -- ---- Thread pane (built first: the list's row click needs openThread) --------------------
    local header = K.Panel(threadPane)
    local backBtn = vgui.Create("DButton", header)
    backBtn:SetText("")
    backBtn.DoClick = function() state.view = "list" end
    backBtn.Paint = function(s, w, h) K.Glyph("chevronleft", w / 2, h / 2, 14, Theme.accent) end

    local headerAvatar = K.Avatar(header, 30, Theme.card)

    local muteBtn = vgui.Create("DButton", header)
    muteBtn:SetText("")
    muteBtn.DoClick = function()
        if state.selectedKey and ZCChatThreads then
            ZCChatThreads.SetSoundMuted(state.selectedKey, not ZCChatThreads.SoundMuted(state.selectedKey))
        end
    end
    muteBtn.Paint = function(s, w, h)
        local muted = state.selectedKey and ZCChatThreads and ZCChatThreads.SoundMuted(state.selectedKey)
        K.Glyph("bell", w / 2, h / 2, 15, muted and Theme.muted or Theme.text)
    end

    header.Paint = function(s, w)
        local key = state.selectedKey
        local thread = key and phone.ZCThreads and phone.ZCThreads[key]
        local x = s.TitleX or 0
        if not thread then
            K.Text("Messages", 15, 600, x, 10, Theme.text)
            return
        end
        local isGroup = ZCChatGroupUI and ZCChatGroupUI.IsGroup(key)
        if isGroup then
            draw.RoundedBox(4, s.AvatarX or 0, 4, 30, 30, Theme.main)
            K.Text("#", 16, 700, (s.AvatarX or 0) + 15, 19, Theme.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        K.Text(K.Fit(thread.name or key, K.Font(14, 600), w - x - 40), 14, 600, x, 4, Theme.text)
        local subtitle
        if isGroup then
            local meta = ZCChatGroupUI.meta and ZCChatGroupUI.meta[key]
            subtitle = (meta and meta.members) and ("Group · " .. #meta.members .. " members") or "Group · loading…"
        else
            subtitle = (ZCChatThreads and IsValid(ZCChatThreads.Player(key))) and "Online" or "Offline"
        end
        K.Text(subtitle, 11, 500, x, 22, Theme.muted)
    end
    header.Think = function(s)
        local w, narrow = s:GetWide(), s:GetWide() < LIST_BREAKPOINT
        backBtn:SetVisible(narrow)
        local x = 0
        if narrow then backBtn:SetPos(0, 4); backBtn:SetSize(24, 32); x = 28 end
        s.AvatarX = x
        local key = state.selectedKey
        local isGroup = key and ZCChatGroupUI and ZCChatGroupUI.IsGroup(key)
        headerAvatar:SetVisible(key ~= nil and not isGroup)
        headerAvatar:SetPos(x, 4); headerAvatar:SetSize(30, 30)
        s.TitleX = x + 38
        muteBtn:SetPos(w - 32, 4); muteBtn:SetSize(28, 28)
        if s.LastKey ~= key then
            s.LastKey = key
            if key and not isGroup then
                local ply = ZCChatThreads and ZCChatThreads.Player(key)
                if ply then headerAvatar:SetPlayer(ply) else headerAvatar:SetSteamID(key) end
            end
        end
    end

    local bodyScroll = K.Panel(threadPane)
    bodyScroll:SetMouseInputEnabled(true)
    bodyScroll.OnMouseWheeled = function(s, delta)
        s.Target = math.Clamp((s.Target or 0) - delta * 48, 0, s.MaxOffset or 0)
        return true
    end
    bodyScroll.Think = function(s)
        local w, h = s:GetWide(), s:GetTall()
        if w <= 0 or h <= 0 or not state.selectedKey then s.Layout = nil; return end
        local layout = buildLayout(phone, state.selectedKey, w)
        local maxOffset = math.max(0, layout.total - h)
        local atBottom = (s.Target or maxOffset) >= (s.MaxOffset or maxOffset) - 4
        if s.ForceBottom or atBottom then s.Target = maxOffset end
        s.ForceBottom = nil
        s.Target = math.Clamp(s.Target or maxOffset, 0, maxOffset)
        s.Offset = K.Spring(s.Offset or maxOffset, s.Target, 16)
        s.MaxOffset, s.Layout = maxOffset, layout
    end
    bodyScroll.Paint = function(s, w, h)
        local layout = s.Layout
        if not layout then return end
        local offset = s.Offset or 0
        for _, block in ipairs(layout.blocks) do
            paintBlock(block, w, block.y - offset, block.y + block.h - offset, h)
        end
    end

    local composeRow = K.Panel(threadPane)
    local composeEntry = vgui.Create("DTextEntry", composeRow)
    composeEntry:SetFont(K.Font(13, 500))
    composeEntry:SetUpdateOnType(true)
    composeEntry.OnValueChange = function(_, v) state.composeText = v end
    composeEntry.OnEnter = function() sendCurrent() end
    composeEntry.Paint = function(s, w, h)
        draw.RoundedBox(4, 0, 0, w, h, Theme.card)
        if s:HasFocus() then
            surface.SetDrawColor(Theme.main)
            surface.DrawOutlinedRect(1, 1, w - 2, h - 2)
        end
        if s:GetValue() == "" and not s:HasFocus() then
            local key = state.selectedKey
            local thread = key and phone.ZCThreads and phone.ZCThreads[key]
            K.Text(thread and ("Message " .. (thread.name or "")) or "Message", 13, 500, 10, h / 2, Theme.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        else
            s:DrawTextEntryText(Theme.text, Theme.accent, Theme.text)
        end
    end
    if ZCChatAssist then ZCChatAssist.Attach(composeEntry, false) end
    local sendBtn = vgui.Create("DButton", composeRow)
    sendBtn:SetText("")
    sendBtn.DoClick = function() sendCurrent() end
    sendBtn.Paint = function(s, w, h)
        draw.RoundedBox(4, 0, 0, w, h, Theme.main)
        K.Glyph("send", w / 2, h / 2, 14, Theme.white)
    end
    composeRow.Think = function(s)
        local w, h = s:GetWide(), s:GetTall()
        composeEntry:SetPos(0, (h - 32) / 2); composeEntry:SetSize(math.max(1, w - 40), 32)
        sendBtn:SetPos(w - 34, (h - 32) / 2); sendBtn:SetSize(34, 32)
    end

    local threadEmpty
    threadPane.Think = function(s)
        local w, h = s:GetWide(), s:GetTall()
        local hasThread = state.selectedKey and phone.ZCThreads and phone.ZCThreads[state.selectedKey] ~= nil
        header:SetVisible(hasThread); bodyScroll:SetVisible(hasThread); composeRow:SetVisible(hasThread)
        if hasThread then
            if IsValid(threadEmpty) then threadEmpty:SetVisible(false) end
            header:SetPos(0, 0); header:SetSize(w, 40)
            composeRow:SetPos(0, h - 40); composeRow:SetSize(w, 40)
            bodyScroll:SetPos(0, 44); bodyScroll:SetSize(w, math.max(1, h - 88))
        else
            if not IsValid(threadEmpty) then
                threadEmpty = K.EmptyState(threadPane, "mail", "Select a conversation", "Pick someone from the list to see your messages.")
            end
            threadEmpty:SetVisible(true)
        end
    end

    openThread = function(key)
        if not phone.ZCThreads or not phone.ZCThreads[key] then return end
        if ZCChatThreads then ZCChatThreads.Select(phone, key, true) end
        state.selectedKey, state.view, state.NextPoll = key, "thread", 0
        if IsValid(bodyScroll) then bodyScroll.ForceBottom = true end
    end
    sendCurrent = function()
        local key, text = state.selectedKey, state.composeText or ""
        if not key or not phone.ZCThreads or not phone.ZCThreads[key] or not text:find("%S") then return end
        if ZCChatThreads then
            ZCChatThreads.Select(phone, key, true)
            ZCChatThreads.Send(phone, text)
        end
        state.composeText = ""
        composeEntry:SetText("")
        if IsValid(bodyScroll) then bodyScroll.ForceBottom = true end
    end

    -- ---- Conversation list pane ---------------------------------------------------------------
    local searchRow = K.Panel(listPane)
    local search = vgui.Create("DTextEntry", searchRow)
    search:SetFont(K.Font(13, 500))
    search:SetUpdateOnType(true)
    search.Paint = function(s, w, h)
        draw.RoundedBox(4, 0, 0, w, h, Theme.card)
        if s:HasFocus() then
            surface.SetDrawColor(Theme.main)
            surface.DrawOutlinedRect(1, 1, w - 2, h - 2)
        end
        if s:GetValue() == "" and not s:HasFocus() then
            K.Text("Search", 13, 500, 10, h / 2, Theme.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        else
            s:DrawTextEntryText(Theme.text, Theme.accent, Theme.text)
        end
    end
    search.OnValueChange = function(_, v) state.query = v; state.NextPoll = 0 end

    local newButton = vgui.Create("DButton", searchRow)
    newButton:SetText("")
    newButton:SetTooltip("New message")
    newButton.DoClick = function() if ZCChatThreads then ZCChatThreads.Directory(phone, true) end end
    newButton.Paint = function(s, w, h)
        local hover = K.Hover(s)
        draw.RoundedBox(4, 0, 0, w, h, hover > 0.01 and K.Alpha(Theme.card, 255) or Theme.card)
        K.Glyph("plus", w / 2, h / 2, 15, Theme.text)
    end
    searchRow.Think = function(s)
        local w, h = s:GetWide(), s:GetTall()
        search:SetPos(0, 0); search:SetSize(math.max(1, w - 38), h)
        newButton:SetPos(w - 32, 0); newButton:SetSize(32, h)
    end

    local listArea = K.Panel(listPane)
    local emptyPanel
    local function ensureEmpty(kind)
        if IsValid(emptyPanel) and emptyPanel.Kind == kind then return end
        if IsValid(emptyPanel) then emptyPanel:Remove() end
        if kind == "none" then
            emptyPanel = K.EmptyState(listArea, "mail", "No conversations yet", "Message a player from the directory to start one.",
                "Start a conversation", function() if ZCChatThreads then ZCChatThreads.Directory(phone, true) end end)
        else
            emptyPanel = K.EmptyState(listArea, "mail", "No matches", "Try another name.")
        end
        emptyPanel.Kind = kind
    end

    local list = K.List(listArea, {
        rowHeight = ROW_HEIGHT,
        gap = 2,
        count = function() return #rows end,
        build = function(row)
            row:SetMouseInputEnabled(true)
            local avatar = K.Avatar(row, AVATAR_SIZE, Theme.card)
            avatar:SetPos(0, (ROW_HEIGHT - AVATAR_SIZE) / 2)
            row.Avatar = avatar
            row.OnMousePressed = function(s)
                local data = rows[s.GoobIndex]
                if data then openThread(data.key) end
            end
            row.Paint = function(s, w, h)
                local data = rows[s.GoobIndex]
                if not data then return end
                if data.key == state.selectedKey then
                    draw.RoundedBox(4, 0, 0, w, h, K.Alpha(Theme.main, 60))
                    surface.SetDrawColor(Theme.main)
                    surface.DrawRect(0, 2, 2, h - 4)
                elseif K.Hover(s) > 0.01 then
                    draw.RoundedBox(4, 0, 0, w, h, K.Alpha(Theme.white, 14 * s.GoobHover))
                end
                local left = AVATAR_SIZE + 10
                local timeText = relativeTime(data.last)
                local timeFont = K.Font(11, 500)
                surface.SetFont(timeFont)
                local timeW = data.last and (surface.GetTextSize(timeText) + 6) or 0
                K.Text(K.Fit(data.name, K.Font(13, 600), w - left - timeW - 8), 13, 600, left, 7, Theme.text)
                if data.last then K.Text(timeText, 11, 500, w - 6, 8, Theme.muted, TEXT_ALIGN_RIGHT) end
                if data.muted then
                    K.Glyph("bell", left + 6, 30, 11, Theme.muted)
                    K.Text(K.Fit("Muted", K.Font(12, 500), w - left - 20), 12, 500, left + 16, 24, Theme.muted)
                else
                    local room = w - left - ((data.unread or 0) > 0 and 30 or 6)
                    K.Text(K.Fit(data.preview or "", K.Font(12, 500), room), 12, 500, left, 24, Theme.muted)
                end
            end
            row.PaintOver = function(s, w, h)
                local data = rows[s.GoobIndex]
                if not data then return end
                local ay = (ROW_HEIGHT - AVATAR_SIZE) / 2
                if data.isGroup then
                    paintInitials(0, ay + 10, 24, data.names[1])
                    paintInitials(12, ay, 24, data.names[2])
                elseif data.online then
                    K.Dot(AVATAR_SIZE - 8, ay + AVATAR_SIZE - 8, 9, Theme.green)
                end
                if (data.unread or 0) > 0 then K.Badge(w - 6, (ROW_HEIGHT - 18) / 2, data.unread) end
            end
        end,
        fill = function(row, index)
            local data = rows[index]
            if not data then return end
            row.Avatar:SetVisible(not data.isGroup)
            if not data.isGroup then
                local ply = ZCChatThreads and ZCChatThreads.Player(data.key)
                if ply then row.Avatar:SetPlayer(ply) else row.Avatar:SetSteamID(data.key) end
            end
        end,
    })
    listArea.Think = function(s)
        local w, h = s:GetWide(), s:GetTall()
        list:SetPos(0, 0); list:SetSize(w, h)
    end

    refreshList = function()
        local threads, order = phone.ZCThreads, phone.ZCThreadOrder
        local out = {}
        if istable(threads) and istable(order) then
            for _, key in ipairs(order) do
                local s = key ~= "main" and threads[key]
                if s and (state.query == "" or A.Matches(s.name or key, state.query)) then
                    local isGroup = ZCChatGroupUI and ZCChatGroupUI.IsGroup(key)
                    local entries = s.entries or {}
                    local lastRow = entries[#entries]
                    out[#out + 1] = {
                        key = key, name = s.name or key, isGroup = isGroup,
                        unread = tonumber(s.unread) or 0,
                        muted = ZCChatThreads and ZCChatThreads.SoundMuted(key),
                        last = s.last,
                        preview = IsValid(lastRow) and rowText(lastRow) or "",
                        online = not isGroup and ZCChatThreads and IsValid(ZCChatThreads.Player(key)),
                        names = isGroup and groupInitials(key, s.name or key) or nil,
                    }
                    if isGroup and not state.syncedGroups[key] and ZCChatGroupUI and ZCChatGroupUI.Request
                        and not (ZCChatGroupUI.meta and ZCChatGroupUI.meta[key]) then
                        local id = tonumber(key:sub(7))
                        if id then state.syncedGroups[key] = true; ZCChatGroupUI.Request({op = "sync", group = id}) end
                    end
                end
            end
        end
        table.sort(out, function(a, b) return (a.last or 0) > (b.last or 0) end)
        rows = out
        list:Refresh()
        local hasAny = #rows > 0
        list:SetVisible(hasAny)
        if hasAny then
            if IsValid(emptyPanel) then emptyPanel:SetVisible(false) end
        else
            ensureEmpty(state.query == "" and "none" or "search")
            emptyPanel:SetVisible(true)
        end
    end

    listPane.Think = function(s)
        local w, h = s:GetWide(), s:GetTall()
        searchRow:SetPos(0, 0); searchRow:SetSize(w, 32)
        listArea:SetPos(0, 38); listArea:SetSize(w, math.max(1, h - 38))
        local now = RealTime()
        if now < (state.NextPoll or 0) then return end
        state.NextPoll = now + 0.25
        local sig = {state.query}
        local order = phone.ZCThreadOrder
        if istable(order) then
            for _, key in ipairs(order) do
                local t = phone.ZCThreads[key]
                sig[#sig + 1] = key .. ":" .. tostring(t and t.unread) .. ":" .. tostring(t and t.name) .. ":" .. tostring(t and t.last)
            end
        end
        sig = table.concat(sig, "|")
        if sig ~= state.ListSignature then
            state.ListSignature = sig
            refreshList()
        end
    end

    -- ---- Two panes at >=560, list-only below it (BRIEF D1) ------------------------------------
    body.Think = function(s)
        local w, h = s:GetWide(), s:GetTall()
        if w <= 0 or h <= 0 then return end
        local narrow = w < LIST_BREAKPOINT
        local showList = (not narrow) or state.view == "list"
        local showThread = (not narrow) or state.view == "thread"
        listPane:SetVisible(showList)
        threadPane:SetVisible(showThread)
        if narrow then
            if showList then listPane:SetPos(0, 0); listPane:SetSize(w, h) end
            if showThread then threadPane:SetPos(0, 0); threadPane:SetSize(w, h) end
        else
            listPane:SetPos(0, 0); listPane:SetSize(LIST_W, h)
            threadPane:SetPos(LIST_W + 10, 0); threadPane:SetSize(math.max(1, w - LIST_W - 10), h)
        end
        if showThread and state.selectedKey and phone.ZCThreads and phone.ZCThreads[state.selectedKey] then
            phone.ZCThreads[state.selectedKey].unread = 0
        end
    end

    refreshList()
    local wanted = A.State.messagesOpen
    A.State.messagesOpen = nil
    if wanted and phone.ZCThreads and phone.ZCThreads[wanted] then
        openThread(wanted)
    elseif rows[1] then
        state.selectedKey = rows[1].key
        if ZCChatThreads then ZCChatThreads.Select(phone, rows[1].key, true) end
        if IsValid(bodyScroll) then bodyScroll.ForceBottom = true end
    end
end

A.Register("messages", "Messages", "Private and group chats", "icon16/email.png", Theme.accent, build)
