if not CLIENT then return end
local A, F, T = ZCGoobApps, ZCGoobFeed, ZCGoobApps.Theme
local K = A.Kit
local C = F.Client
-- CityLeak keeps its own paper/ink wordmark as a brand accent on the masthead only (mockups/06_cityleak.html
-- "What changed vs live"); every card/list/pill surface below it reads kit tokens (T.cardGlass etc.), not
-- feed_ui.lua's old dedicated brand.card/hover/line palette.
local brand = {paper = Color(243, 243, 240), ink = Color(17, 18, 20)}
local PAD = 10
local REACT_H, REPLY_H, HEADER_H, KC_H = 26, 18, 34, 24
-- Hoisted out of Paint (KIT_API: no Color() allocation inside Paint/Think).
local EVENT_CARD_FILL = Color(38, 35, 35, 150)
local CLIP_MEDIA_FILL = Color(26, 17, 19, 220)

-- Word-wrap a string to `width` px in `font`, returning an array of lines (kit candidate: this and K.Fit
-- overlap; K.Fit only ellipsises a single line). Drawing uses the SAME function that measured the height,
-- so a card's measured height and its painted content can never drift apart.
local function wrapLines(text, font, width, maxLines)
    text = tostring(text or "")
    if text == "" then return {} end
    surface.SetFont(font)
    local lines, line = {}, ""
    for word in text:gmatch("%S+") do
        local candidate = line == "" and word or (line .. " " .. word)
        if surface.GetTextSize(candidate) > width and line ~= "" then
            lines[#lines + 1] = line
            line = word
            if maxLines and #lines >= maxLines then return lines end
        else
            line = candidate
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
end

local function agoText(ts)
    local delta = math.max(0, os.time() - (tonumber(ts) or os.time()))
    if delta < 60 then return "now" end
    if delta < 3600 then return math.floor(delta / 60) .. "m" end
    if delta < 86400 then return math.floor(delta / 3600) .. "h" end
    return os.date("%b %d", ts)
end

-- One offline <img>, CSP-locked to a data: URI (feed.lua/feed_ui.lua's existing pattern). `full` docks FILL
-- (the full-photo sheet); otherwise it docks TOP at a fixed height for a card thumbnail.
local function photoHTML(encoded, cover)
    return '<!doctype html><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; img-src data:; style-src \'unsafe-inline\'"><style>html,body{margin:0;height:100%;background:#080c13;overflow:hidden}img{width:100%;height:100%;object-fit:'
        .. (cover and "cover" or "contain") .. '}</style><img alt="CityLeak photo" src="data:image/jpeg;base64,' .. (encoded or "") .. '">'
end
local function image(parent, encoded, full)
    local panel = vgui.Create("DHTML", parent)
    if full then panel:Dock(FILL) else panel:Dock(TOP); panel:SetTall(160) end
    panel:SetAllowLua(false)
    panel:SetMouseInputEnabled(false)
    panel:SetHTML(photoHTML(encoded))
    return panel
end
-- Undocked DHTML for a pooled feed row's thumbnail: the row Paints its own absolute layout each
-- frame, so a Dock(TOP)/Dock(FILL) child would fight that positioning on the next PerformLayout.
local function rawImagePanel(parent)
    local panel = vgui.Create("DHTML", parent)
    panel:SetAllowLua(false)
    panel:SetMouseInputEnabled(false)
    panel:SetHTML(photoHTML(nil, true))
    return panel
end

-- Reaction glyphs: kit candidate. K.Glyphs has no Like/Love/Laugh/Wow icon (only donate.lua's "heart"),
-- so each pill uses a small solid dot in the reaction's colour plus its label -- consistent with K.Dot's
-- existing look, cheaper than four new 24-unit glyph paths under this change's time budget.
local REACT_COLOR = {}
local function reactColors() REACT_COLOR[1], REACT_COLOR[2], REACT_COLOR[3], REACT_COLOR[4] = T.red, T.main, T.gold, T.green return REACT_COLOR end
-- Polish pass: each pill now carries its reaction's glyph (mockup 06 pills), from the kit set.
local REACT_GLYPH = {"like", "heart", "smile", "wow"}
local SCROLL_GUTTER = 8 -- rows always leave room for the list's scrollbar, so measured == painted width
local RAIL_MIN, RAIL_W = 640, 190

-- One reaction pill; returns its width. Shared by feed cards and the thread view.
local function reactionPill(i, count, selected, x, y)
    local label = tostring(count)
    local font = K.Font(11, 600)
    surface.SetFont(font)
    local pw = math.max(40, surface.GetTextSize(label) + 32)
    draw.RoundedBox(12, x, y, pw, REACT_H, selected and K.Alpha(T.main, 60) or K.Alpha(T.ink, 130))
    if selected then
        surface.SetDrawColor(K.Alpha(T.accent, 200))
        surface.DrawOutlinedRect(x + 2, y + 1, pw - 4, REACT_H - 2, 1)
    end
    if not K.Glyph(REACT_GLYPH[i] or "heart", x + 13, y + REACT_H / 2, 12, reactColors()[i]) then K.Dot(x + 8, y + REACT_H / 2 - 3, 6, reactColors()[i]) end
    draw.SimpleText(label, font, x + 23, y + REACT_H / 2, selected and T.text or T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    return pw
end

function C.ComposePhoto(name)
    if C.Busy() then C.Note("Wait for the current CityLeak action before choosing another photo."); return false end
    C.draft.photoName, C.draft.jpeg, C.draft.thumb, C.draft.nonce = name, nil, nil, nil
    C.view = "compose"
    return A.Launch("feed")
end

-- Small kit-styled button: T.main primary / T.card secondary, K.Hover wash, K.Font text (KIT_API: no
-- surface.CreateFont, no per-Paint Color()). Docks TOP like the app's old chrome() buttons did.
-- UI cohesion (2026-09-26): the shared K.Button; this wrapper keeps the file's call sites.
local function kitButton(parent, text, callback, primary, danger)
    return K.Button(parent, {label = text, click = callback, size = 15,
        kind = danger and "danger" or (primary and "primary" or "secondary"),
        enabled = function() return not C.Busy() and C.Available() and not C.blocked end})
end

local function build(root, phone)
    C.root, C.view = root, C.view or "feed"
    C.Purge = function() if IsValid(root) and IsValid(phone) then phone:SetPhonePage("home") end end
    C.changed = true
    C.feedItems = C.feedItems or {}
    local generation = 0
    local render, load
    local content
    local metricsCache = {}
    -- The virtualised feed list, kept alive across data-only refreshes (auto-load-near-bottom,
    -- pull-to-refresh) so its scroll Offset/Pool survive; only a real view change tears it down.
    local feedList

    local function getMetrics(post, width)
        local key = tostring(post.id) .. "@" .. tostring(post.kind or "post") .. "@" .. math.floor(width)
        local hit = metricsCache[key]
        if hit then return hit end
        local w = math.max(20, width - PAD * 2)
        local m
        if post.kind == "event" then
            local lines = wrapLines(post.body or "", K.Font(12, 500), w)
            m = {w = w, lines = lines, h = PAD * 2 + 18 + #lines * 16 + 4}
        else
            local lines = post.body ~= "" and wrapLines(post.body, K.Font(13, 500), w, 6) or {}
            local mediaH = (post.photo or post.kind == "clip") and math.min(110, math.floor(w * 9 / 16)) or 0
            local kcH = post.kind == "clip" and KC_H or 0
            local h = PAD * 2 + HEADER_H + (#lines > 0 and (#lines * 16 + 6) or 0) + (mediaH > 0 and (mediaH + 8) or 0)
                + (kcH > 0 and (kcH + 6) or 0) + REACT_H + 6 + REPLY_H + 4
            m = {w = w, lines = lines, mediaH = mediaH, kcH = kcH, h = h}
        end
        metricsCache[key] = m
        return m
    end

    -- ------------------------------------------------------------------------------------------
    -- Shared actions (navigate/report/remove/showPhoto/watch). Nested in build() so pooled feed
    -- rows and the thread/profile screens all reach the SAME generation/render/load closures.
    -- ------------------------------------------------------------------------------------------
    local function navigate(view, id)
        C.view = view; C.before, C.commentBefore, C.feedItems, C.autoLoading, C.replyTo = nil, nil, {}, false, nil
        if view == "profile" then C.author = id else C.postID = id end
        generation = generation + 1; render(); load()
    end
    local function showPhoto(post)
        if IsValid(C.photoSheet) then C.photoSheet:Remove() end
        local sheet, shade = K.Sheet(root, math.floor(root:GetTall() * 0.9))
        C.photoSheet = shade
        local head = K.Panel(sheet); head:Dock(TOP); head:SetTall(28)
        head.Paint = function(_, w) K.Text(post.name .. " · " .. os.date("%b %d · %H:%M", post.created), 13, 600, 0, 4, T.text) end
        kitButton(sheet, "Close", function() shade:Close() end)
        shade.OnRemove = function()
            if C.photoSheet == shade then C.photoSheet = nil end
            if C.ForgetPhoto then C.ForgetPhoto(post.id) end -- the download keeps going in the background
        end
        local body = K.Panel(sheet); body:Dock(FILL)
        A.Status(body, "Loading photo…")
        C.Photo(post.id, function(bytes) if IsValid(body) then body:Clear(); image(body, util.Base64Encode(bytes), true) end end)
    end
    local function report(kind, id)
        local sheet, shade = K.Sheet(root, 220)
        local head = K.Panel(sheet); head:Dock(TOP); head:SetTall(24)
        head.Paint = function(_, w) K.Text("Report " .. kind, 16, 700, 0, 2, T.gold) end
        A.Status(sheet, "Tell staff what needs attention. Reports are private to staff.")
        local reason = ""
        A.Entry(sheet, "Reason · up to 300 bytes", "", function(value) reason = value end)
        kitButton(sheet, "Send report", function()
            if not F.Text(reason, 300, false) then C.Note("Add a short reason first."); return end
            C.Request({op = "report", kind = kind, id = id, reason = reason}, function() if IsValid(shade) then shade:Close() end; C.Note("Report sent to staff.") end)
        end, true)
        kitButton(sheet, "Cancel", function() shade:Close() end)
    end
    local function remove(kind, id)
        K.Modal(root, "Remove this " .. kind .. "?", "It disappears from CityLeak. Removing a post also removes its comments and reactions.", {
            {"Cancel"},
            {"Remove", function()
                C.Request({op = "remove", kind = kind, id = id}, function()
                    C.cache[id] = nil
                    if kind == "post" then C.view = "feed"; C.before, C.feedItems = nil, {} end
                    C.Note("Removed."); load()
                end)
            end, danger = true}
        })
    end
    local function overflow(kind, id, mine)
        local sheet, shade = K.Sheet(root, mine and 160 or 110)
        local head = K.Panel(sheet); head:Dock(TOP); head:SetTall(24)
        head.Paint = function(_, w) K.Text(kind == "post" and "Post options" or "Comment options", 15, 700, 0, 2, T.text) end
        kitButton(sheet, "Report " .. kind, function() shade:Close(); report(kind, id) end)
        if mine then kitButton(sheet, "Remove " .. kind, function() shade:Close(); remove(kind, id) end, false, true) end
    end
    local function watchClip(clipID) return A.Media and A.Media.OpenClip and A.Media.OpenClip(clipID) end

    -- ------------------------------------------------------------------------------------------
    -- Masthead + tabs
    -- ------------------------------------------------------------------------------------------
    local masthead = K.Panel(root); masthead:Dock(TOP); masthead:SetTall(44); masthead:DockMargin(0, 0, 0, 6)
    masthead:SetMouseInputEnabled(true)
    masthead.Paint = function(_, w, h)
        local cityFont = K.Font(20, 700)
        surface.SetFont(cityFont)
        local cityWidth = surface.GetTextSize("City")
        K.Text("City", 20, 700, 0, 0, T.text)
        local leakWidth = select(1, surface.GetTextSize("Leak")) + 10
        draw.RoundedBox(2, cityWidth + 4, 0, leakWidth, 22, brand.paper)
        K.Text("Leak", 20, 700, cityWidth + 9, 1, brand.ink)
        surface.SetDrawColor(T.red); surface.DrawRect(0, 24, 130, 2)
        K.Text("Your city. As it happens.", 10, 600, 0, 30, T.muted)
        -- refresh (vector glyph: the font has no U+21BB, which drew as a box)
        draw.RoundedBox(4, w - 28, 2, 26, 26, T.card)
        K.Glyph("refresh", w - 15, 15, 15, T.muted)
    end
    masthead.OnMousePressed = function(s, code)
        if code ~= MOUSE_LEFT then return end
        local mx = select(1, s:CursorPos())
        if mx >= s:GetWide() - 30 and not C.Busy() then C.before, C.feedItems = nil, {}; load() end
    end
    local tabLabels = {"Latest", "Events", "Create", "My profile"}
    local tabViews = {"feed", "feed", "compose", "profile"}
    local tabFeedKind = {"posts", "events"}
    C.feedTab = C.feedTab or "posts"
    local tabsSelected = 1
    for i, v in ipairs(tabViews) do
        if v == "feed" then if C.view == "feed" and C.feedTab == tabFeedKind[i] then tabsSelected = i end
        elseif C.view == v then tabsSelected = i end
    end
    local tabs = K.Tabs(root, tabLabels, tabsSelected, function(index)
        local v = tabViews[index]
        C.view, C.author, C.before, C.commentBefore, C.feedItems, C.autoLoading, C.replyTo = v, nil, nil, nil, {}, false, nil
        C.feedTab = tabFeedKind[index] or C.feedTab
        generation = generation + 1
        render(); if v ~= "compose" then load() end
    end)
    tabs:Dock(TOP); tabs:DockMargin(0, 0, 0, 4)
    local status = A.Status(root, "")
    status:DockMargin(0, 0, 0, 2)
    content = K.Panel(root); content:Dock(FILL)

    -- ------------------------------------------------------------------------------------------
    -- Feed card row: pooled by the virtualised list, redrawn per post via s.Post. Interactive
    -- regions are recorded into s.Zones each Paint and hit-tested in one OnMousePressed (fewer
    -- child panels to pool/reposition than one DButton per click target).
    -- ------------------------------------------------------------------------------------------
    local function buildFeedRow(row)
        row:SetMouseInputEnabled(true)
        row.Zones = {}
        row.Avatar = K.Avatar(row, 30)
        row.Avatar:SetPos(PAD, PAD)
        row.OnMousePressed = function(s, code)
            if code ~= MOUSE_LEFT then return end
            local mx, my = s:CursorPos()
            for _, z in ipairs(s.Zones) do
                if mx >= z.x and mx <= z.x + z.w and my >= z.y and my <= z.y + z.h then z.action(); return end
            end
        end
        row.Paint = function(s, w, h)
            local post = s.Post
            if not post then K.Card(0, 0, w, h, T.cardGlass); return end
            -- Click zones (and their closures) are rebuilt only when the post, width or own reaction
            -- changes -- they used to be reallocated every frame for every visible card.
            local zones
            if s.ZonePost ~= post or s.ZoneW ~= w or s.ZoneMine ~= post.mine then
                zones = {}
                s.Zones, s.ZonePost, s.ZoneW, s.ZoneMine = zones, post, w, post.mine
            end
            if post.kind == "event" then
                K.Card(0, 0, w, h, EVENT_CARD_FILL, K.Alpha(T.main, 200))
                local m = getMetrics(post, w)
                K.Text("ROUND EVENT", 11, 700, PAD, PAD, T.gold)
                local y = PAD + 18
                for _, line in ipairs(m.lines) do K.Text(line, 12, 500, PAD, y, T.text); y = y + 16 end
                if C.admin then
                    K.Text("...", 15, 700, w - 6, PAD, T.muted, TEXT_ALIGN_RIGHT)
                    if zones then zones[#zones + 1] = {x = w - 30, y = 0, w = 30, h = HEADER_H, action = function() overflow("post", post.id, C.admin) end} end
                end
                return
            end
            K.Card(0, 0, w, h, T.cardGlass, K.Alpha(T.edge, 140))
            local m = getMetrics(post, w)
            -- name / time / overflow (avatar is a real child, positioned once in buildFeedRow)
            if zones then zones[#zones + 1] = {x = 0, y = 0, w = w - 30, h = HEADER_H, action = function() navigate("profile", post.author) end} end
            K.Text(K.Fit(post.name, K.Font(13, 600), w - 110), 13, 600, 40, PAD, T.text)
            K.Text(agoText(post.created), 11, 500, w - 34, PAD + 2, T.muted, TEXT_ALIGN_RIGHT)
            K.Text("...", 15, 700, w - 6, PAD, T.muted, TEXT_ALIGN_RIGHT)
            if zones then
                zones[#zones + 1] = {x = w - 30, y = 0, w = 30, h = HEADER_H, action = function()
                    overflow("post", post.id, post.author == LocalPlayer():SteamID64() or C.admin)
                end}
            end
            local y = PAD + HEADER_H
            for _, line in ipairs(m.lines) do K.Text(line, 13, 500, PAD, y, T.text); y = y + 16 end
            if #m.lines > 0 then y = y + 6 end
            if m.mediaH > 0 then
                if post.kind == "clip" then
                    K.Card(PAD, y, m.w, m.mediaH, CLIP_MEDIA_FILL)
                    K.Text("KILLCAM CLIP", 10, 600, PAD + 8, y + m.mediaH - 20, K.Alpha(T.white, 190))
                else
                    if not s.Thumb then s.Thumb = rawImagePanel(s) end
                    if s.ThumbFor ~= post.id and post.thumb and post.thumb ~= "" then
                        s.Thumb:SetHTML(photoHTML(post.thumb, true))
                        s.ThumbFor = post.id
                    end
                    s.Thumb:SetVisible(true); s.Thumb:SetPos(PAD, y); s.Thumb:SetSize(m.w, m.mediaH)
                    if zones then zones[#zones + 1] = {x = PAD, y = y, w = m.w, h = m.mediaH, action = function() showPhoto(post) end} end
                end
                y = y + m.mediaH + 8
            elseif s.Thumb then s.Thumb:SetVisible(false) end
            if m.kcH > 0 then
                K.Text("KILLCAM", 10, 600, PAD, y + 4, T.red)
                local watchW = 60
                draw.RoundedBox(4, w - PAD - watchW, y, watchW, m.kcH, T.main)
                K.Text("Watch", 12, 600, w - PAD - watchW / 2, y + m.kcH / 2, T.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                if zones then zones[#zones + 1] = {x = w - PAD - watchW, y = y, w = watchW, h = m.kcH, action = function() watchClip(post.clip) end} end
                y = y + m.kcH + 6
            end
            -- reaction pills
            local px = PAD
            local reactions = post.reactions or {}
            for i in ipairs(F.Reactions) do
                local selected = post.mine == i
                local pw = reactionPill(i, reactions[i] or 0, selected, px, y)
                if zones then
                    zones[#zones + 1] = {x = px, y = y, w = pw, h = REACT_H, action = function()
                        C.Request({op = "react", id = post.id, reaction = selected and 0 or i}, function(result)
                            if result.kind == "post" and result.post then
                                for idx, item in ipairs(C.feedItems) do
                                    if item.id == result.post.id then C.feedItems[idx] = result.post; break end
                                end
                            end
                            render()
                        end)
                    end}
                end
                px = px + pw + 5
            end
            y = y + REACT_H + 6
            K.Text((post.comments or 0) .. " comments · Open conversation", 11, 500, PAD, y, T.muted)
            if zones then zones[#zones + 1] = {x = 0, y = y - 2, w = w, h = REPLY_H + 4, action = function() navigate("thread", post.id) end} end
        end
        return row
    end
    local function fillFeedRow(row, index)
        local post = C.feedItems[index]
        row.Post = post
        -- The system author ("system:city", feed_rules.lua) is not a real SteamID64: the round-event
        -- card has no avatar/header at all (buildFeedRow's Paint returns before drawing one).
        local showAvatar = post and post.kind ~= "event" and post.author
        row.Avatar:SetVisible(showAvatar and true or false)
        if showAvatar then row.Avatar:SetSteamID(post.author) end
        if row.Thumb and (not post or post.kind == "event" or (not post.photo and post.kind ~= "clip")) then row.Thumb:SetVisible(false) end
    end

    -- ------------------------------------------------------------------------------------------
    -- Variable-height virtualised list (kit candidate: K.List only supports a fixed rowHeight).
    -- spec = {gap, count(), height(i), build(row), fill(row,i), onPull, onNearBottom}. Pull-to-refresh
    -- is a wheel-up gesture at the very top of the list (no drag physics), matching the mockup note.
    -- ------------------------------------------------------------------------------------------
    local function variableList(parent, spec)
        local list = K.Panel(parent)
        list:SetMouseInputEnabled(true)
        list.Pool, list.Offset, list.Target = {}, 0, 0
        local gap = spec.gap or 8
        function list:Refresh() self.Dirty = true end
        list.OnMouseWheeled = function(s, delta)
            if delta > 0 and s.Offset <= 1 and spec.onPull and RealTime() >= (s.PullLock or 0) then
                s.PullLock = RealTime() + 2
                spec.onPull()
            end
            s.Target = s.Target - delta * 56
            return true
        end
        list.Think = function(s)
            local count, h, w = spec.count(), s:GetTall(), s:GetWide()
            local tops, total = {}, 0
            for i = 1, count do tops[i] = total; total = total + spec.height(i) + gap end
            if count > 0 then total = total - gap end
            local maxOffset = math.max(0, total - h)
            s.Target = math.Clamp(s.Target, 0, maxOffset)
            s.Offset = K.Spring(s.Offset, s.Target, 16)
            s.MaxOffset = maxOffset
            if spec.onNearBottom and maxOffset > 0 and s.Offset >= maxOffset - 60 then spec.onNearBottom() end
            local first = 1
            for i = 1, count do if tops[i] + spec.height(i) >= s.Offset then first = i; break end end
            local rowWidth = w - SCROLL_GUTTER
            local slot, y, i = 0, count > 0 and (tops[first] - s.Offset) or 0, first
            while i <= count and y < h do
                slot = slot + 1
                local row = s.Pool[slot]
                if not row then row = K.Panel(s); spec.build(row); s.Pool[slot] = row end
                row:SetVisible(true)
                row:SetPos(0, math.floor(y))
                local rh = spec.height(i)
                if row:GetWide() ~= rowWidth or row:GetTall() ~= rh then row:SetSize(rowWidth, rh) end
                if row.GoobIndex ~= i or s.Dirty then row.GoobIndex = i; spec.fill(row, i) end
                y = y + rh + gap
                i = i + 1
            end
            for j = slot + 1, #s.Pool do
                if s.Pool[j]:IsVisible() then s.Pool[j]:SetVisible(false); s.Pool[j].GoobIndex = nil end
            end
            s.Dirty = false
        end
        list.Paint = function(s, w, h)
            if (s.MaxOffset or 0) <= 0 then return end
            local grip = math.max(24, h * h / (h + s.MaxOffset))
            draw.RoundedBox(2, w - 4, (h - grip) * s.Offset / s.MaxOffset, 4, grip, T.line)
        end
        return list
    end

    -- ------------------------------------------------------------------------------------------
    -- Screens
    -- ------------------------------------------------------------------------------------------
    local function compose()
        local scroll = A.Scroll(content)
        local title = K.Panel(scroll); title:Dock(TOP); title:SetTall(28)
        title.Paint = function(_, w) K.Text("Post to CityLeak", 18, 700, 0, 2, T.text) end
        A.Status(scroll, "Public to this server. Your name and profile appear beside the post. Photos stay local until you publish.")
        local draft = C.draft
        local entry = A.Entry(scroll, "Write a caption or text post…", draft.body or "", function(value) draft.body = value; draft.nonce = nil end)
        entry:SetMultiline(true); entry:SetTall(100)
        local count = A.Status(scroll, "")
        count.Think = function(s) s:SetText(#(draft.body or "") .. " / 1200 bytes"); entry:SetEnabled(not C.Busy()) end
        if draft.jpeg then
            image(scroll, util.Base64Encode(draft.thumb))
            A.Status(scroll, "Photo ready · " .. math.ceil(#draft.jpeg / 1024) .. " KiB · original stays in your gallery")
            kitButton(scroll, "Remove attached photo", function() draft.jpeg, draft.thumb, draft.photoName, draft.nonce = nil, nil, nil, nil; render() end)
        elseif draft.photoName then
            kitButton(scroll, "Prepare selected photo", function()
                C.PreparePhoto(root, draft.photoName, function() if IsValid(root) then render() end end)
            end)
        end
        kitButton(scroll, "Choose from Camera gallery", function()
            local sheet = K.Sheet(root, math.floor(root:GetTall() * 0.8))
            local head = K.Panel(sheet); head:Dock(TOP); head:SetTall(24)
            head.Paint = function() K.Text("Choose a photo", 15, 700, 0, 2, T.text) end
            local list = A.Scroll(sheet)
            local photos = A.Camera.Photos()
            -- Thumbnail grid (the camera's own 320 x 180 thumbnails) instead of a list of timestamps.
            local grid = K.Grid(list, 104, 72, 6, 6)
            grid:Dock(TOP)
            for _, photo in ipairs(photos) do
                local tile = vgui.Create("DButton", grid)
                tile:SetText("")
                tile:SetTooltip(os.date("%b %d · %H:%M:%S", photo.time))
                tile.GoobLabel = "photo:" .. photo.name
                local stamp = os.date("%b %d %H:%M", photo.time)
                tile.Paint = function(s, w, h)
                    K.Card(0, 0, w, h, T.card)
                    local thumb = A.Camera.Thumb and A.Camera.Thumb(photo.name)
                    if thumb then
                        surface.SetMaterial(thumb)
                        surface.SetDrawColor(255, 255, 255, 255)
                        surface.DrawTexturedRect(1, 1, w - 2, h - 2)
                    else
                        K.Glyph("camera", w / 2, h / 2 - 6, 16, T.muted)
                    end
                    if K.Hover(s) > 0.01 then draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.white, 16 * s.GoobHover)) end
                    draw.RoundedBox(3, 3, h - 17, w - 6, 14, K.Alpha(T.ink, 190))
                    K.Text(K.Fit(stamp, K.Font(10, 600), w - 10), 10, 600, w / 2, h - 10, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
                tile.DoClick = function()
                    C.PreparePhoto(sheet, photo.name, function() if IsValid(sheet) then sheet:GetParent():Close() end; if IsValid(root) then render() end end)
                end
            end
            if #photos == 0 then A.Status(list, "Your gallery is empty. Open Camera to take a photo.") end
        end)
        kitButton(scroll, "Open Camera", function() A.Launch("camera") end)
        kitButton(scroll, "Publish post", function()
            if not F.Text(draft.body or "", 1200, draft.jpeg ~= nil) then C.Note("Add a photo or write a post first."); return end
            if draft.photoName and not draft.jpeg then C.Note("Prepare the selected photo before publishing."); return end
            K.Modal(root, "Publish to CityLeak?", "Other players can view, react and comment. You can remove your post later.", {
                {"Cancel"},
                {"Publish", function()
                    C.Publish(function(result) if IsValid(root) then C.view, C.postID = "thread", result.id; load() end end)
                end, primary = true}
            })
        end, true)
    end

    local function profile()
        local p = C.profile
        local scroll = A.Scroll(content)
        if not p or p.author ~= (C.author or LocalPlayer():SteamID64()) then A.Status(scroll, "Loading profile…"); return end
        local card = K.Panel(scroll); card:Dock(TOP); card:SetTall(58); card:DockMargin(0, 0, 0, 10)
        local av = K.Avatar(card, 44); av:SetPos(0, 0); av:SetSteamID(p.author)
        card.Paint = function(_, w, h)
            K.Card(0, 0, w, h, T.cardGlass)
            K.Text(K.Fit(p.name, K.Font(17, 700), w - 58), 17, 700, 52, 6, T.text)
            K.Text(p.playtime and A.Duration(p.playtime) .. " played" or "Playtime unavailable", 12, 500, 52, 30, T.green)
        end
        A.Status(scroll, p.posts .. " posts · " .. p.comments .. " comments · " .. p.reactions .. " reactions received")
        A.Status(scroll, p.updated and "Server stats updated " .. os.date("%b %d · %H:%M", p.updated) or "No saved stat snapshot yet.")
        local ahead = K.Panel(scroll); ahead:Dock(TOP); ahead:SetTall(20); ahead:DockMargin(0, 4, 0, 4)
        ahead.Paint = function(_, w) K.Text("ACHIEVEMENT SHOWCASE", 11, 600, 0, 2, T.gold) end
        A.Status(scroll, p.completed and (p.completed .. " / " .. p.available .. " completed") or "Achievement data is not loaded yet.")
        for _, achievement in ipairs(p.achievements or {}) do
            local row = K.Panel(scroll); row:Dock(TOP); row:SetTall(20)
            row.Paint = function(_, w)
                K.Glyph("star", 7, 10, 12, T.gold)
                K.Text(K.Fit(achievement.name, K.Font(13, 500), w - 20), 13, 500, 18, 2, T.gold)
            end
        end
        if p.completed and p.completed > #(p.achievements or {}) then A.Status(scroll, "Showing the first 24 completed achievements.") end
        kitButton(scroll, "View posts", function()
            C.view, C.author, C.before, C.feedItems, C.page, C.feedTab = "feed", p.author, nil, {}, nil, "posts"
            render(); load()
        end)
    end

    local function reports()
        local scroll = A.Scroll(content)
        local head = K.Panel(scroll); head:Dock(TOP); head:SetTall(26)
        head.Paint = function(_, w) K.Text("STAFF REPORTS", 18, 700, 0, 2, T.gold) end
        for _, row in ipairs(C.reports or {}) do
            local card = K.Panel(scroll); card:Dock(TOP); card:DockMargin(0, 0, 0, 8)
            card:DockPadding(10, 10, 10, 10)
            card.Paint = function(_, w, h) K.Card(0, 0, w, h, T.cardGlass) end
            local head2 = K.Panel(card); head2:Dock(TOP); head2:SetTall(18)
            head2.Paint = function(_, w) K.Text("Report #" .. row.id .. " · " .. row.kind .. " #" .. row.target, 13, 700, 0, 0, T.gold) end
            A.Label(card, row.reason, K.Font(14, 500))
            if row.item then
                A.Status(card, row.item.name .. " · " .. row.item.author)
                A.Label(card, row.item.body or "", K.Font(14, 500))
                kitButton(card, "Open conversation", function() navigate("thread", row.kind == "post" and row.target or tonumber(row.item.post)) end)
            end
            kitButton(card, "Remove reported item", function() remove(row.kind, row.target) end, false, true)
            kitButton(card, "Dismiss report", function() C.Request({op = "dismiss", id = row.id}, function() load() end) end)
            card.PerformLayout = function(s) s:SizeToChildren(false, true) end
        end
        if #(C.reports or {}) == 0 then A.Status(scroll, "No open reports.") end
    end

    -- One-level threaded comments: group each fetched page under its top-level comment (ascending,
    -- chat order) with its replies indented directly beneath; a reply whose parent fell off this page
    -- (behind "Older comments") renders un-indented rather than being dropped.
    local function thread()
        local threadData = C.thread
        if not threadData or threadData.post.id ~= C.postID then A.Status(content, "Loading conversation…"); return end
        local outer = K.Panel(content); outer:Dock(FILL)
        local post = threadData.post

        -- Reply bar first: BOTTOM-docked children must be laid out before a FILL-docked sibling
        -- (apps.lua's own A.Open follows the same "reserve first, fill last" Dock order).
        local bar = K.Panel(outer); bar:Dock(BOTTOM); bar:SetTall(40); bar:DockMargin(0, 6, 0, 0)
        local draft = C.comments or {}; C.comments = draft
        local nonces = C.commentNonces or {}; C.commentNonces = nonces
        local postID = threadData.post.id
        local entry = A.Entry(bar, C.replyTo and "Reply…" or "Add a comment…", draft[postID] or "", function(v) draft[postID] = v; nonces[postID] = nil end)
        entry:SetTall(36); entry:SetWide(1)
        local sendBtn = vgui.Create("DButton", bar); sendBtn:SetText(""); sendBtn:SetTall(36); sendBtn:SetWide(56); sendBtn.GoobLabel = "Send"
        sendBtn.Paint = function(s, w, h)
            draw.RoundedBox(4, 0, 0, w, h, T.main)
            K.Text("Send", 13, 600, w / 2, h / 2, T.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        sendBtn.DoClick = function()
            local sendBody = F.Text(draft[postID] or "", 500, false)
            if not sendBody then C.Note("Comments need 1–500 bytes of text."); return end
            nonces[postID] = nonces[postID] or C.Nonce()
            local parent = C.replyTo
            C.Request({op = "comment", id = postID, body = sendBody, nonce = nonces[postID], parent = parent}, function()
                if F.Text(draft[postID] or "", 500, false) == sendBody then draft[postID], nonces[postID] = nil, nil end
                C.commentBefore, C.replyTo = nil, nil
                load()
            end)
        end
        bar.PerformLayout = function(s, w) entry:SetPos(0, 0); entry:SetWide(w - 62); sendBtn:SetPos(w - 56, 0) end

        if C.replyTo then
            local replyBar = K.Panel(outer); replyBar:Dock(BOTTOM); replyBar:SetTall(20); replyBar:DockMargin(0, 4, 0, 0)
            replyBar:SetMouseInputEnabled(true)
            local targetName = "a comment"
            for _, c in ipairs(threadData.comments or {}) do if c.id == C.replyTo then targetName = c.name; break end end
            replyBar.Paint = function(_, w, h)
                K.Text("Replying to " .. targetName, 11, 500, 0, h / 2 - 6, T.muted)
                K.Text("Cancel", 11, 600, w - 42, h / 2 - 6, T.red)
            end
            replyBar.OnMousePressed = function(_, code) if code == MOUSE_LEFT then C.replyTo = nil; render() end end
        end

        local scroll = A.Scroll(outer)
        local card = K.Panel(scroll); card:Dock(TOP); card:DockMargin(0, 0, 0, 8); card:DockPadding(PAD, PAD, PAD, PAD)
        card.Paint = function(_, w, h) K.Card(0, 0, w, h, T.cardGlass, K.Alpha(T.edge, 140)) end
        card.PerformLayout = function(s) s:SizeToChildren(false, true) end
        local header = K.Panel(card); header:Dock(TOP); header:SetTall(34)
        local av = K.Avatar(header, 30); av:SetPos(0, 0); av:SetSteamID(post.author)
        local nameBtn = vgui.Create("DButton", header); nameBtn:SetText(""); nameBtn:SetPos(40, 4); nameBtn:SetSize(200, 20); nameBtn.GoobLabel = "profile:" .. post.author
        nameBtn.Paint = function(_, w, h) K.Text(post.name, 13, 600, 0, 3, T.text) end
        nameBtn.DoClick = function() navigate("profile", post.author) end
        A.Status(card, os.date("%b %d · %H:%M", post.created) .. " · #" .. post.id)
        if post.body ~= "" then A.Label(card, post.body, K.Font(14, 500)) end
        if post.photo then image(card, post.thumb) end
        local reacts = K.Panel(card); reacts:Dock(TOP); reacts:SetTall(REACT_H); reacts:DockMargin(0, 4, 0, 4)
        reacts:SetMouseInputEnabled(true)
        reacts.Paint = function(s, w)
            local px = 0
            local zones = s.ZoneW ~= w and {} or nil
            if zones then s.Zones, s.ZoneW = zones, w end
            for i in ipairs(F.Reactions) do
                local pw = reactionPill(i, (post.reactions or {})[i] or 0, post.mine == i, px, 0)
                if zones then zones[#zones + 1] = {x = px, y = 0, w = pw, h = REACT_H, i = i} end
                px = px + pw + 5
            end
        end
        reacts.OnMousePressed = function(s, cd)
            if cd ~= MOUSE_LEFT then return end
            local mx = s:CursorPos()
            for _, z in ipairs(s.Zones or {}) do
                if mx >= z.x and mx <= z.x + z.w then
                    C.Request({op = "react", id = post.id, reaction = post.mine == z.i and 0 or z.i}, function(result)
                        if result.kind == "post" and result.post and C.thread and C.thread.post.id == result.post.id then
                            C.thread.post = result.post
                        end
                        render()
                    end)
                    return
                end
            end
        end
        kitButton(card, "···  Post options", function() overflow("post", post.id, post.author == LocalPlayer():SteamID64() or C.admin) end)

        local tops, byParent, orphans = {}, {}, {}
        for _, c in ipairs(threadData.comments or {}) do
            if not c.parent then tops[#tops + 1] = c
            else
                byParent[c.parent] = byParent[c.parent] or {}
                table.insert(byParent[c.parent], c)
            end
        end
        table.sort(tops, function(a, b) return a.id < b.id end)
        local seenParents = {}
        for _, c in ipairs(tops) do seenParents[c.id] = true end
        for parent, list in pairs(byParent) do
            if not seenParents[parent] then for _, c in ipairs(list) do orphans[#orphans + 1] = c end end
        end
        table.sort(orphans, function(a, b) return a.id < b.id end)

        local function commentRow(parent, c, indent)
            local row = K.Panel(parent); row:Dock(TOP); row:DockMargin(indent, 0, 0, 8)
            row:DockPadding(0, 0, 0, 0)
            local av2 = K.Avatar(row, 26); av2:SetPos(0, 0); av2:SetSteamID(c.author)
            local nb = vgui.Create("DButton", row); nb:SetText(""); nb:SetPos(34, 0); nb:SetSize(160, 16); nb.GoobLabel = "profile:" .. c.author
            nb.Paint = function(_, w) K.Text(c.name, 11, 600, 0, 1, T.muted) end
            nb.DoClick = function() navigate("profile", c.author) end
            local body = K.Panel(row); body:SetPos(34, 17)
            local bodyWide = math.max(20, (parent:GetWide() or 320) - 34 - indent)
            local lines = wrapLines(c.body, K.Font(12, 500), bodyWide)
            body.Paint = function(_, w)
                local y = 0
                for _, line in ipairs(lines) do K.Text(line, 12, 500, 0, y, T.text); y = y + 15 end
            end
            body:SetSize(bodyWide, #lines * 15)
            local meta = vgui.Create("DButton", row); meta:SetText(""); meta:SetPos(34, 17 + #lines * 15 + 2); meta:SetSize(200, 14); meta.GoobLabel = "reply:" .. c.id
            local canReply = indent == 0
            meta.Paint = function(_, w) K.Text(agoText(c.created) .. (canReply and " · Reply" or ""), 11, 500, 0, 0, T.muted) end
            meta.DoClick = function()
                if not canReply then return end
                C.replyTo = C.replyTo == c.id and nil or c.id
                render()
            end
            local moreBtn = vgui.Create("DButton", row); moreBtn:SetText(""); moreBtn:SetPos(200, 0); moreBtn:SetSize(20, 16); moreBtn.GoobLabel = "overflow:comment:" .. c.id
            moreBtn.Paint = function(_, w, h) K.Text("···", 13, 700, w / 2, h / 2, T.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
            moreBtn.DoClick = function() overflow("comment", c.id, c.author == LocalPlayer():SteamID64() or C.admin) end
            row:SetTall(17 + #lines * 15 + 16)
            return row
        end

        for _, c in ipairs(tops) do
            commentRow(scroll, c, 0)
            for _, reply in ipairs(byParent[c.id] or {}) do commentRow(scroll, reply, 40) end
        end
        for _, c in ipairs(orphans) do commentRow(scroll, c, 0) end
        if threadData.more then kitButton(scroll, "Older comments", function() C.commentBefore = threadData.comments[#threadData.comments].id; load() end) end
        if C.commentBefore then kitButton(scroll, "Newest comments", function() C.commentBefore = nil; load() end) end
    end

    render = function()
        if not IsValid(root) then return end
        -- Data-only refresh while already showing a populated feed list (auto-load-near-bottom,
        -- pull-to-refresh, a reaction/comment count changing): refresh the EXISTING list in place
        -- instead of rebuilding, so its scroll Offset and pooled rows survive.
        if C.view == "feed" and not C.blocked and C.Available() and IsValid(feedList) and C.page and #C.feedItems > 0 then
            feedList:Refresh()
            return
        end
        content:Clear()
        content.Think, content.RailW, content.RailH = nil, nil, nil
        feedList = nil
        if C.blocked or not C.Available() then A.Status(content, "CityLeak is waiting for its server or world-isolation integration."); return end
        if C.view == "compose" then compose()
        elseif C.view == "profile" then profile()
        elseif C.view == "thread" then thread()
        elseif C.view == "reports" then reports()
        else
            -- Docked TOP before the FILL-docked list/empty-state below it (Dock order matters: a TOP
            -- sibling added after a FILL sibling gets no remaining space -- see thread()'s reply bar).
            if C.admin then kitButton(content, "Staff reports", function() C.view = "reports"; load() end) end
            if not C.page then A.Status(content, "Loading CityLeak…")
            elseif #C.feedItems == 0 then
                if C.feedTab == "events" then
                    K.EmptyState(content, "empty", "No round events yet", "Round summaries will appear here once posted.")
                else
                    K.EmptyState(content, "empty", "Nothing leaked yet", "Be the first to post something from the city.", "Create a post", function()
                        C.view = "compose"; render()
                    end)
                end
            else
                -- Wide phones get the mockup's side rail (you + this round); the list keeps the rest.
                local listHost = K.Panel(content)
                listHost:Dock(FILL)
                local rail = K.Panel(content)
                rail:SetVisible(false)
                local me = LocalPlayer()
                local myID = IsValid(me) and me:SteamID64() or nil
                local railAvatar = K.Avatar(rail, 30)
                railAvatar:SetPos(10, 28)
                if myID then railAvatar:SetSteamID(myID) end
                local myProfile = vgui.Create("DButton", rail)
                myProfile:SetText("")
                myProfile.GoobLabel = "rail:profile"
                myProfile.DoClick = function() if myID then navigate("profile", myID) end end
                myProfile.Paint = function(s, w, h)
                    if K.Hover(s) > 0.01 then draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.white, 10 * s.GoobHover)) end
                end
                local newPost = kitButton(rail, "Create a post", function() C.view = "compose"; generation = generation + 1; render() end, true)
                newPost:Dock(NODOCK)
                rail.Paint = function(_, w, h)
                    K.Card(0, 0, w, 76, T.cardGlass, K.Alpha(T.edge, 140))
                    K.Text("YOU", 11, 700, 10, 8, T.muted)
                    K.Text(K.Fit(IsValid(me) and me:Nick() or "You", K.Font(13, 600), w - 60), 13, 600, 48, 30, T.text)
                    local p = C.profile
                    local stats = (p and p.author == myID) and (p.posts .. " posts · " .. p.comments .. " comments") or "My profile ›"
                    K.Text(K.Fit(stats, K.Font(11, 500), w - 60), 11, 500, 48, 48, T.muted)
                    local y = 88
                    K.Card(0, y, w, h - y - 46, T.cardGlass, K.Alpha(T.edge, 140))
                    K.Text("THIS ROUND", 11, 700, 10, y + 8, T.muted)
                    local ty, shown = y + 28, 0
                    local font = K.Font(12, 500)
                    for _, post in ipairs(C.feedItems) do
                        if post.kind == "event" and shown < 4 and ty < h - 70 then
                            shown = shown + 1
                            for _, line in ipairs(K.Wrap(post.body or "", font, w - 20, 2)) do
                                draw.SimpleText(line, font, 10, ty, T.text)
                                ty = ty + 15
                            end
                            ty = ty + 6
                        end
                    end
                    if shown == 0 then K.Text(K.Fit("Round events appear here.", font, w - 20), 12, 500, 10, ty, T.muted) end
                end
                content.Think = function(s)
                    local w, h = s:GetWide(), s:GetTall()
                    local wide = w >= RAIL_MIN
                    if s.RailW == w and s.RailH == h then return end
                    s.RailW, s.RailH = w, h
                    rail:SetVisible(wide)
                    listHost:Dock(NODOCK)
                    listHost:SetPos(0, 0)
                    listHost:SetSize(wide and w - RAIL_W - 10 or w, h)
                    if wide then
                        rail:SetPos(w - RAIL_W, 0); rail:SetSize(RAIL_W, h)
                        myProfile:SetPos(0, 0); myProfile:SetSize(RAIL_W, 76)
                        newPost:SetPos(0, h - 38); newPost:SetSize(RAIL_W, 36)
                    end
                end
                feedList = variableList(listHost, {
                    gap = 8,
                    count = function() return #C.feedItems end,
                    height = function(i) local post = C.feedItems[i]; return post and getMetrics(post, listHost:GetWide() - SCROLL_GUTTER).h or 60 end,
                    build = buildFeedRow,
                    fill = fillFeedRow,
                    onPull = function()
                        if C.Busy() then return end
                        C.before = nil
                        C.Note("Refreshing…")
                        load()
                    end,
                    onNearBottom = function()
                        if C.Busy() or C.autoLoading or not (C.page and C.page.more) then return end
                        C.autoLoading = true
                        C.before = C.feedItems[#C.feedItems] and C.feedItems[#C.feedItems].id
                        load()
                    end
                })
                feedList:Dock(FILL)
            end
        end
    end
    load = function()
        if not IsValid(root) then return end
        local mine = generation
        local data = {op = C.view == "thread" and "thread" or C.view == "profile" and "profile" or C.view == "reports" and "reports" or "feed",
            author = C.author, id = C.postID, before = C.view == "thread" and C.commentBefore or C.before,
            tab = C.view == "feed" and C.feedTab or nil}
        C.Request(data, function(result)
            if not IsValid(root) or generation ~= mine then return end
            C.autoLoading = false
            if result.kind == "feed" then
                C.admin = result.admin
                if C.before and #C.feedItems > 0 then
                    for _, post in ipairs(result.posts) do C.feedItems[#C.feedItems + 1] = post end
                else
                    C.feedItems = result.posts
                    -- A replace (fresh load, tab switch or pull-to-refresh), not a near-bottom append:
                    -- snap the list back to the top rather than leaving it at a now-stale scroll offset.
                    if IsValid(feedList) then feedList.Offset, feedList.Target = 0, 0 end
                end
                C.page = result
            elseif result.kind == "thread" then C.thread = result
            elseif result.kind == "profile" then C.profile = result.profile
            elseif result.kind == "reports" then C.reports = result.reports end
            C.message = nil; render()
        end)
    end
    root.Think = function()
        status:SetText(C.Busy() and (C.message or "Connecting…") or C.message or "Public posts · server profiles · pull down at the top to refresh")
        if C.changed then C.changed = false; if C.blocked then render() end end
    end
    root.OnRemove = function() generation = generation + 1; if C.root == root then C.root, C.Purge = nil, nil end end
    render()
    if C.view ~= "compose" then load()
    elseif C.draft.photoName and not C.draft.jpeg and not C.Busy() then
        C.PreparePhoto(root, C.draft.photoName, function() if IsValid(root) then render() end end)
    end
end
A.Register("feed", "CityLeak", "Your city. As it happens.", "icon16/pictures.png", T.red, build)
