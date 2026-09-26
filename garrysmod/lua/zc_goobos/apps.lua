if not CLIENT then return end
ZCGoobApps = ZCGoobApps or {}
local A = ZCGoobApps
A.Version = "20260922.apps1"
-- Keep registrations across autorefresh: only re-included app files register again.
A.Registry = A.Registry or {}
A.State = A.State or {}
-- Palette follows the ZCity pause menu skin (hg.VGUI): neutral dark panels,
-- MainColor Color(150, 0, 0) for fills/outlines, its selection red Color(192, 0, 0) for text.
-- Filled in place so already-loaded apps holding a reference to A.Theme repaint on autorefresh.
A.Theme = A.Theme or {}
for k, v in pairs({
    bg = Color(29, 26, 26),
    card = Color(38, 35, 35),
    hover = Color(48, 28, 30),
    text = Color(225, 225, 225),
    muted = Color(165, 165, 165),
    accent = Color(192, 0, 0),
    main = Color(150, 0, 0),
    green = Color(119, 218, 181),
    gold = Color(247, 199, 115),
    red = Color(255, 143, 159),
    line = Color(90, 20, 20)
}) do A.Theme[k] = v end

local T = A.Theme
local goobGradientL = surface.GetTextureID("vgui/gradient-l")
for name, spec in pairs({
    Title = {24, 700},
    Body = {15, 500},
    Small = {13, 500},
    Metric = {30, 600}
}) do
    surface.CreateFont("Goob" .. name, {
        font = (spec[1] >= 24) and "Bahnschrift" or "Roboto",
        size = spec[1],
        weight = spec[2],
        antialias = true,
        extended = true
    })
end

function A.Label(parent, text, font, color, height)
    local p = vgui.Create("DLabel", parent)
    p:Dock(TOP)
    p:DockMargin(0, 0, 0, 6)
    p:SetTall(height or 22)
    p:SetFont(font or "GoobBody")
    p:SetTextColor(color or T.text)
    p:SetText(tostring(text or ""))
    p:SetWrap(true)
    p:SetAutoStretchVertical(true)
    return p
end

function A.Button(parent, text, click, accent)
    local b = vgui.Create("DButton", parent)
    b:Dock(TOP)
    b:DockMargin(0, 0, 0, 7)
    b:SetTall(36)
    b:SetText(text)
    b:SetFont("GoobBody")
    b:SetTextColor(accent or T.text)
    b.Paint = function(s, w, h)
        draw.RoundedBox(4, 0, 0, w, h, T.card)
        if s:IsHovered() then
            surface.SetDrawColor(T.main.r, T.main.g, T.main.b, 90)
            surface.SetTexture(goobGradientL)
            surface.DrawTexturedRect(0, 0, w, h)
            surface.SetDrawColor(T.main)
            surface.DrawRect(0, 0, 2, h)
        end
        if s:HasFocus() then
            surface.SetDrawColor(T.main)
            surface.DrawOutlinedRect(1, 1, w - 2, h - 2)
        end
    end

    b.DoClick = click or function() end
    return b
end

function A.Entry(parent, placeholder, value, onChange)
    local p = vgui.Create("DTextEntry", parent)
    p:Dock(TOP)
    p:DockMargin(0, 0, 0, 9)
    p:SetTall(36)
    p:SetFont("GoobBody")
    p:SetPlaceholderText(placeholder)
    p:SetText(value or "")
    p:SetUpdateOnType(true)
    p.Paint = function(s, w, h)
        draw.RoundedBox(4, 0, 0, w, h, T.card)
        if s:HasFocus() then
            surface.SetDrawColor(T.main)
            surface.DrawOutlinedRect(1, 1, w - 2, h - 2)
        end

        if s:GetValue() == "" and not s:HasFocus() then
            draw.SimpleText(placeholder, "GoobBody", 7, h / 2, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        else
            s:DrawTextEntryText(T.text, T.accent, T.text)
        end
    end

    p.OnValueChange = function(_, v) if onChange then onChange(v) end end
    return p
end

function A.Scroll(parent)
    local p = vgui.Create("DScrollPanel", parent)
    p:Dock(FILL)
    local bar = p:GetVBar()
    bar:SetWide(5)
    bar:SetHideButtons(true)
    bar.Paint = function() end
    bar.btnGrip.Paint = function(_, w, h) draw.RoundedBox(3, 0, 0, w, h, T.line) end
    return p
end

function A.Card(parent)
    local p = vgui.Create("DPanel", parent)
    p:Dock(TOP)
    p:DockMargin(0, 0, 8, 9)
    p:DockPadding(12, 10, 12, 10)
    p:SetTall(80)
    p.Paint = function(_, w, h) draw.RoundedBox(0, 0, 0, w, h, T.card) end
    p.PerformLayout = function(s) s:SizeToChildren(false, true) end
    return p
end

function A.Status(parent, text, color)
    return A.Label(parent, text, "GoobSmall", color or T.muted, 32)
end

function A.Sheet(parent)
    local sheet = vgui.Create("DPanel", parent)
    sheet:SetPos(0, 0)
    sheet:SetSize(parent:GetWide(), parent:GetTall())
    sheet:SetZPos(900)
    sheet:SetMouseInputEnabled(true)
    sheet:SetKeyboardInputEnabled(true)
    sheet:RequestFocus()
    sheet:DockPadding(12, 12, 12, 12)
    sheet.Paint = function(_, w, h) draw.RoundedBox(0, 0, 0, w, h, T.bg) end
    sheet.Think = function(s)
        if s:GetWide() ~= parent:GetWide() or s:GetTall() ~= parent:GetTall() then s:SetSize(parent:GetWide(), parent:GetTall()) end
    end
    return sheet
end

function A.Confirm(parent, title, detail, accept)
    if IsValid(parent.GoobConfirm) then parent.GoobConfirm:Remove() end
    local shade = A.Sheet(parent)
    parent.GoobConfirm = shade
    local scroll = A.Scroll(shade)
    A.Label(scroll, title, "GoobTitle")
    A.Status(scroll, detail)
    A.Button(scroll, "Confirm", function()
        shade:Remove()
        if IsValid(parent) then accept() end
    end, T.accent)

    A.Button(scroll, "Cancel", function() shade:Remove() end)
    return shade
end

function A.SortedRows(source, name)
    local rows = {}
    for id, value in pairs(source or {}) do
        rows[#rows + 1] = {
            id = id,
            data = value
        }
    end

    table.sort(rows, function(a, b)
        local x, y = string.lower(tostring(name(a.data, a.id))), string.lower(tostring(name(b.data, b.id)))
        if x == y then return tostring(a.id) < tostring(b.id) end
        return x < y
    end)
    return rows
end

function A.Matches(text, query)
    return string.find(string.lower(tostring(text)), string.lower(tostring(query or "")), 1, true) ~= nil
end

function A.Register(id, title, subtitle, icon, color, build)
    A.Registry[id] = {
        id = id,
        title = title,
        subtitle = subtitle,
        icon = Material(icon, "smooth"),
        color = color,
        build = build
    }
end

function A.Launch(id)
    local phone = hg and hg.chat
    if not IsValid(phone) or not phone.SetPhonePage or phone.GoobAppsVersion ~= A.Version then return false end
    if id ~= "home" and id ~= "chat" and not A.Registry[id] then return false end
    if not phone:GetActive() then phone:SetActive(true) end
    phone:SetPhonePage(id)
    return phone.phonePage == id
end

-- Legacy launcher: used only when kit.lua is missing on this client (A.BuildHome falls back to it).
local function legacyBuildHome(phone, parent)
    if parent.GoobLegacyPaint then parent.Paint = parent.GoobLegacyPaint end
    local plate = Color(T.main.r, T.main.g, T.main.b, 70) -- cached: was allocated every frame per tile
    local scroll = A.Scroll(parent)
    scroll:Dock(NODOCK)
    phone.goobLauncher = scroll
    local grid = vgui.Create("DIconLayout", scroll)
    grid:Dock(TOP)
    grid:SetSpaceX(8)
    grid:SetSpaceY(8)
    phone.goobGrid = grid
    for _, id in ipairs({"chat", "camera", "feed", "arcade", "shop", "wardrobe", "progress", "voice", "settings"}) do
        local app = A.Registry[id]
        if id == "chat" then
            app = {
                title = "Chat",
                subtitle = "Your conversations",
                icon = Material("icon16/comments.png"),
                color = T.accent
            }
        end

        if app then
            local b = grid:Add("DButton")
            b:SetText("")
            b:SetSize(100, 104)
            b.DoClick = function() phone:SetPhonePage(id) end
            b:SetTooltip(app.title .. " — " .. app.subtitle)
            b.Paint = function(s, w, h)
                draw.RoundedBox(0, 0, 0, w, h, T.card)
                if s:IsHovered() then
                    surface.SetDrawColor(T.main.r, T.main.g, T.main.b, 90)
                    surface.SetTexture(goobGradientL)
                    surface.DrawTexturedRect(0, 0, w, h)
                    surface.SetDrawColor(T.main)
                    surface.DrawOutlinedRect(0, 0, w, h)
                end
                draw.RoundedBox(0, w / 2 - 26, 12, 52, 52, plate)
                surface.SetMaterial(app.icon)
                surface.SetDrawColor(255, 90, 90)
                surface.DrawTexturedRect(w / 2 - 13, 25, 26, 26)
                draw.SimpleText(app.title, "GoobBody", w / 2, 83, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                if id == "chat" and (phone.phoneUnread or 0) > 0 then
                    draw.RoundedBox(0, w - 46, 10, 36, 22, T.red)
                    draw.SimpleText(math.min(phone.phoneUnread, 99), "GoobSmall", w - 28, 21, T.bg, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
                if id == "voice" and A.Voice and A.Voice.Ready() then
                    local live = false
                    for _, row in ipairs(A.Voice.rows) do
                        if A.Voice.Visible(row) then live = true; break end
                    end
                    if live then draw.RoundedBox(4, w - 20, 12, 8, 8, T.green) end
                end
            end
        end
    end
end

-- Homescreen on the kit (Phase 1, mockups/00_homescreen.html): wallpaper glow, status row with live
-- chips, notification tray fed by unread private/group threads, and an icon grid with red badges.
-- Below 220 px of home height the grid becomes one sideways-paged row (owner decision 2026-09-24).
-- Falls back to the legacy launcher above when the kit is missing (kit.lua not delivered yet).
A.HomeOrder = {"chat", "messages", "camera", "feed", "arcade", "shop", "wardrobe", "progress", "voice", "settings", "donate", "replays"}
A.HomeGlyphs = {chat = "chat", messages = "mail", camera = "camera", feed = "news", arcade = "gamepad", shop = "bag", wardrobe = "shirt", progress = "trophy", voice = "mic", settings = "cog", replays = "replay", donate = "heart", afterlife = "ghost"}
local HOME_FOREIGN_TITLES = {afterlife = "Afterlife"}
local HOME_TILE_W, HOME_TILE_H, HOME_COMPACT_W, HOME_COMPACT_H = 78, 88, 70, 80

local function homeApps()
    local list, seen, extra = {}, {}, {}
    for _, id in ipairs(A.HomeOrder) do
        if id == "chat" or A.Registry[id] then
            list[#list + 1] = id
            seen[id] = true
        end
    end
    for id in pairs(A.Registry) do
        if not seen[id] then extra[#extra + 1] = id end
    end
    table.sort(extra)
    for _, id in ipairs(extra) do list[#list + 1] = id end
    return list
end

local function openHomeApp(phone, id)
    if id == "chat" and IsValid(phone.chatApp) and phone.chatApp.DoClick then
        phone.chatApp:DoClick() -- ZChat's own entry: also reopens the last thread
    else
        phone:SetPhonePage(id)
    end
end

local function openThread(phone, key)
    if A.OpenMessageThread and A.OpenMessageThread(phone, key) then return end
    phone:SetPhonePage("chat")
    if ZCChatThreads and ZCChatThreads.Select and phone.ZCThreads and phone.ZCThreads[key] then ZCChatThreads.Select(phone, key) end
end

local function relativeTime(at)
    if not at then return "" end
    local age = math.max(0, RealTime() - at)
    if age < 60 then return "now" end
    if age < 3600 then return math.floor(age / 60) .. "m" end
    return math.floor(age / 3600) .. "h"
end

-- Tray entries (mockup 00): unread private/group threads (last line as the body) plus recent pushes
-- notify.lua keeps (CityLeak reactions/replies), newest first, each with a relative time. The main
-- channel only feeds the Chat badge. Also returns the thread unread total and unread CityLeak count.
local function homeEntries(phone)
    local entries, total, feed = {}, 0, 0
    local threads = phone.ZCThreads
    if istable(threads) then
        local order = istable(phone.ZCThreadOrder) and phone.ZCThreadOrder or table.GetKeys(threads)
        for _, key in ipairs(order) do
            local s = threads[key]
            local unread = key ~= "main" and istable(s) and not s.closed and tonumber(s.unread) or 0
            if unread > 0 then
                total = total + unread
                local group = ZCChatGroupUI and ZCChatGroupUI.IsGroup and ZCChatGroupUI.IsGroup(key)
                local rows = istable(s.entries) and s.entries or {}
                local last = rows[#rows]
                local preview = A.MessageRowText and IsValid(last) and A.MessageRowText(last) or ""
                entries[#entries + 1] = {
                    key = key,
                    app = group and "Group chat" or "Messages",
                    glyph = group and "chat" or "mail",
                    title = tostring(s.name or key),
                    body = (unread == 1 and preview ~= "") and preview or (unread == 1 and "1 new message" or unread .. " new messages"),
                    at = s.last
                }
            end
        end
    end
    local history = A.Notify and A.Notify.History
    if istable(history) then
        for _, h in ipairs(history) do
            if not h.read then
                if h.app == "CityLeak" then feed = feed + 1 end
                entries[#entries + 1] = {key = "n" .. h.id, app = h.app, glyph = h.glyph, title = tostring(h.title or ""), body = tostring(h.body or ""), at = h.at, history = h}
            end
        end
    end
    table.sort(entries, function(a, b) return (a.at or 0) > (b.at or 0) end)
    for _, entry in ipairs(entries) do entry.time = relativeTime(entry.at) end
    return entries, total, feed
end

local function roundChip(narrow)
    if not istable(zb) or not zb.CROUND then return nil end
    local name = (string.gsub(string.gsub(tostring(zb.CROUND), "_", " "), "^%l", string.upper))
    local left
    if zb.ROUND_STATE == 1 and zb.ROUND_START and (tonumber(zb.ROUND_TIME) or 0) > 0 then
        left = string.FormattedTime(math.max(zb.ROUND_START + zb.ROUND_TIME - CurTime(), 0), "%02i:%02i")
    end
    if narrow then return left or name end
    return left and name .. " · " .. left or name
end

local function homeChips(home)
    local chips = {}
    local narrow = not home.Wide
    chips[#chips + 1] = narrow and player.GetCount() .. "/" .. game.MaxPlayers() or player.GetCount() .. " / " .. game.MaxPlayers() .. " players"
    local round = roundChip(narrow)
    if round then chips[#chips + 1] = round end
    local me = LocalPlayer()
    if not narrow and IsValid(me) then chips[#chips + 1] = me:Ping() .. " ms" end
    return chips
end

local function paintHomeTile(tile, w)
    local K = A.Kit
    if not K then return end
    local phone = tile.GoobPhone
    local hover = K.Hover(tile)
    local lift = 0
    if IsValid(phone) and not K.Reduced() then
        local t = (CurTime() - (phone.phonePageChanged or 0) - (tile.GoobOrder or 0) * 0.018) / 0.22
        lift = math.floor((1 - K.EaseOut(t)) * 6)
    end
    if hover > 0.01 then
        draw.RoundedBox(4, 0, 0, w, tile:GetTall(), K.Alpha(T.main, 55 * hover))
        surface.SetDrawColor(T.main.r, T.main.g, T.main.b, 255 * hover)
        surface.DrawRect(4, 0, w - 8, 2)
    end
    local size = tile.GoobCompact and 52 or 56
    local x, y = math.floor((w - size) / 2), 8 + lift
    K.Plate(x, y, size, tile.GoobGlyph, tile.GoobIcon)
    if tile.GoobBadge then K.Badge(x + size + 6, y - 6, tile.GoobBadge(phone)) end
    if tile.GoobDot and tile.GoobDot() then K.Dot(x + size - 10, y + size - 10, 9, T.green) end
    local font = K.Font(13, 500)
    draw.SimpleText(K.Fit(tile.GoobTitle, font, w - 6), font, w / 2, y + size + 5, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
end

local function paintHomeWallpaper(_, w)
    -- The phone frame already paints the translucent glass; this adds a faint red glow from the top.
    for i = 0, 9 do
        surface.SetDrawColor(T.main.r, T.main.g, T.main.b, 20 - i * 2)
        surface.DrawRect(1, i * 14, w - 2, 14)
    end
end

-- Tray cards are reused buttons; `home.Tray.Expanded` shows every entry that fits.
function A.LayoutTray(home)
    local K, tray = A.Kit, home.Tray
    local entries = home.Entries or {}
    local w, h = tray:GetWide(), tray:GetTall()
    local head = (tray.Expanded or home.Wide) and 24 or 0
    local step = K.NoticeHeight + 7
    local room = math.max(1, math.floor((h - head + 7) / step))
    local shown = tray.Expanded and math.min(#entries, room) or math.min(#entries, home.Wide and math.max(1, math.min(room - 1, 2)) or 1)
    tray.Cards = tray.Cards or {}
    for i = 1, math.max(shown, #tray.Cards) do
        local card = tray.Cards[i]
        if i <= shown then
            if not IsValid(card) then
                card = vgui.Create("DButton", tray)
                card:SetText("")
                card.Paint = function(s, cw) if s.Entry then K.Notice(0, 0, cw, s.Entry, K.Hover(s)) end end
                card.DoClick = function(s)
                    local phone = home.GoobPhone
                    local entry = s.Entry
                    if not entry or not IsValid(phone) then return end
                    home.TrayOpen = false
                    if entry.history then
                        entry.history.read = true
                        if entry.history.onClick then pcall(entry.history.onClick) end
                        home.Signature = nil
                    else
                        openThread(phone, entry.key)
                    end
                end
                tray.Cards[i] = card
            end
            card.Entry = entries[i]
            card:SetTooltip("Open " .. entries[i].title)
            card:SetPos(0, head + (i - 1) * step)
            card:SetSize(w, K.NoticeHeight)
            card:SetVisible(true)
        elseif IsValid(card) then
            card:SetVisible(false)
            card.Entry = nil
        end
    end
    local more = tray.More
    if not IsValid(more) then
        more = vgui.Create("DButton", tray)
        more:SetText("")
        more.Paint = function(s, mw, mh)
            local hover = K.Hover(s)
            draw.RoundedBox(4, 0, 0, mw, mh, K.Alpha(T.card, 150 + 80 * hover))
            K.Text(s.Label or "", 11, 600, mw / 2, mh / 2, T.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        more.DoClick = function()
            home.TrayOpen = true
            A.LayoutHome(home.GoobPhone)
        end
        tray.More = more
    end
    local hidden = #entries - shown
    more:SetVisible(hidden > 0 and not tray.Expanded)
    more.Label = hidden .. " more"
    more:SetPos(8, head + shown * step - 3)
    more:SetSize(math.max(1, w - 16), 17)
    tray.Overflow = tray.Expanded and hidden or 0
end

function A.LayoutHome(phone, w, h)
    local K, home = A.Kit, IsValid(phone) and phone.goobLauncher
    if not K or not IsValid(home) or not home.GoobKit then return end
    w = w or phone:GetWide()
    h = (h or phone:GetTall()) - 44
    home:SetPos(0, 0)
    home:SetSize(math.max(1, w), math.max(1, h))
    local entries = home.Entries or {}
    local compact, wide = h < 220, w >= 620 and h >= 220
    local padX, padY = 18, compact and 10 or 16
    local status, tray, view, grid = home.Status, home.Tray, home.View, home.Grid
    home.Compact, home.Wide = compact, wide
    status.Compact, status.Narrow = compact, not wide
    if home.TrayOpen and #entries == 0 then home.TrayOpen = false end
    if home.TrayOpen then
        status:SetVisible(false)
        view:SetVisible(false)
        tray:SetVisible(true)
        tray.Expanded = true
        tray:SetPos(padX, padY)
        tray:SetSize(math.max(1, w - padX * 2), math.max(1, h - padY * 2))
        A.LayoutTray(home)
        return
    end
    status:SetVisible(true)
    view:SetVisible(true)
    tray.Expanded = false
    local innerW = w - padX * 2
    local trayW = wide and #entries > 0 and 272 or 0
    local leftW = trayW > 0 and innerW - trayW - 18 or innerW
    local statusH = compact and 22 or (wide and 38 or 32) + 22
    status:SetPos(padX, padY)
    status:SetSize(math.max(1, leftW), statusH)
    local y = padY + statusH + (compact and 8 or 14)
    if compact or #entries == 0 then
        tray:SetVisible(false)
    elseif wide then
        tray:SetVisible(true)
        tray:SetPos(w - padX - trayW, padY)
        tray:SetSize(trayW, math.max(1, h - padY * 2))
        A.LayoutTray(home)
    else
        local trayH = K.NoticeHeight + (#entries > 1 and 22 or 0)
        tray:SetVisible(true)
        tray:SetPos(padX, y)
        tray:SetSize(math.max(1, innerW), trayH)
        A.LayoutTray(home)
        y = y + trayH + 10
    end
    local viewH = math.max(1, h - y - (compact and 4 or 12))
    view:SetPos(padX, y)
    view:SetSize(math.max(1, leftW), viewH)
    local tiles = {}
    for _, child in ipairs(grid:GetChildren()) do
        if IsValid(child) then
            if not child.GoobTile then
                -- Tiles other modules add (the Afterlife observer app) get the kit look; their click stays theirs.
                local id = child.ZCAppID
                child.GoobTile, child.GoobPhone = true, phone
                child.GoobTitle = HOME_FOREIGN_TITLES[id] or tostring(id or "App")
                child.GoobGlyph = A.HomeGlyphs[id] or "grid"
                child:Dock(NODOCK)
                child.Paint = paintHomeTile
            end
            tiles[#tiles + 1] = child
            child.GoobOrder = #tiles
            child.GoobCompact = compact
        end
    end
    if compact then
        local step = HOME_COMPACT_W + 10
        for i, tile in ipairs(tiles) do
            tile:SetPos((i - 1) * step, 0)
            tile:SetSize(HOME_COMPACT_W, HOME_COMPACT_H)
        end
        grid:SetSize(math.max(1, #tiles * step - 10), HOME_COMPACT_H)
        home.PageSize = math.max(1, math.floor((leftW + 10) / step))
        home.Pages = math.max(1, math.ceil(#tiles / home.PageSize))
        home.Page = math.Clamp(home.Page or 1, 1, home.Pages)
        home.ContentH = 0
    else
        local height = K.GridLayout(tiles, leftW, HOME_TILE_W, HOME_TILE_H, 6, 10, 7)
        if height > viewH then height = K.GridLayout(tiles, leftW - 8, HOME_TILE_W, HOME_TILE_H, 6, 10, 7) end
        grid:SetSize(math.max(1, leftW), math.max(1, height))
        home.ContentH, home.Pages, home.Page = height, 1, 1
    end
end

function A.BuildHome(phone, parent)
    if IsValid(phone.chatApp) then phone.chatApp:SetVisible(false) end
    if IsValid(phone.goobLauncher) then phone.goobLauncher:Remove() end
    local K = A.Kit
    if not K then return legacyBuildHome(phone, parent) end
    parent.GoobLegacyPaint = parent.GoobLegacyPaint or parent.Paint
    parent.Paint = paintHomeWallpaper
    local home = K.Panel(parent)
    home.GoobKit, home.GoobPhone = true, phone
    home.Entries, home.ThreadUnread, home.Chips = {}, 0, {}
    phone.goobLauncher = home

    local status = K.Panel(home)
    status:SetMouseInputEnabled(true)
    home.Status = status
    status.Paint = function(s, w, h)
        if s.Compact then
            local line = (phone.phoneClock or "") .. "  ·  " .. (home.ShortDate or "") .. "  ·  " .. (home.Chips[1] or "")
            K.Text(K.Fit(line, K.Font(12, 500), w - 70), 12, 500, 0, h / 2, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            if #home.Entries > 0 then
                local label = #home.Entries .. " new"
                local font = K.Font(11, 600)
                surface.SetFont(font)
                local pw = surface.GetTextSize(label) + 16
                s.PillX = w - pw
                draw.RoundedBox(4, w - pw, 1, pw, h - 2, T.badge)
                draw.SimpleText(label, font, w - pw / 2, h / 2, T.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            else
                s.PillX = nil
            end
            return
        end
        local clock = s.Narrow and 32 or 38
        K.Text(phone.phoneClock or "", clock, 300, 0, 0, T.text)
        K.Text(s.Narrow and home.ShortDate or phone.phoneDate or "", 13, 500, 1, clock + 4, T.muted)
        local font = K.Font(12, 500)
        surface.SetFont(font)
        local x = w
        for i = #home.Chips, 1, -1 do
            local text = home.Chips[i]
            local cw = surface.GetTextSize(text) + 18
            if x - cw < 150 then break end
            x = x - cw
            draw.RoundedBox(4, x, h - 22, cw, 22, T.cardGlass)
            draw.SimpleText(text, font, x + cw / 2, h - 11, T.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            x = x - 6
        end
    end
    status.OnMousePressed = function(s, code)
        if code == MOUSE_LEFT and s.Compact and s.PillX and s:CursorPos() >= s.PillX then
            home.TrayOpen = true
            A.LayoutHome(phone)
        end
    end

    local tray = K.Panel(home)
    tray:SetMouseInputEnabled(true)
    home.Tray = tray
    tray.Paint = function(s, w)
        if s.Expanded then
            K.Text("‹  All notifications", 15, 600, 0, 2, T.accent)
            if (s.Overflow or 0) > 0 then K.Text(s.Overflow .. " more in Chat", 11, 600, w, 6, T.muted, TEXT_ALIGN_RIGHT) end
        elseif home.Wide then
            K.Text("NOTIFICATIONS", 11, 600, 0, 4, T.muted)
        end
    end
    tray.OnMousePressed = function(s, code)
        local _, y = s:CursorPos()
        if code == MOUSE_LEFT and s.Expanded and y < 24 then
            home.TrayOpen = false
            A.LayoutHome(phone)
        end
    end

    local view = K.Panel(home)
    view:SetMouseInputEnabled(true)
    home.View = view
    local grid = K.Panel(view)
    home.Grid = grid
    phone.goobGrid = grid
    grid.Layout = function() A.LayoutHome(phone) end -- the observer calls goobGrid:Layout() after adding its tile
    view.OnMouseWheeled = function(_, delta)
        if home.Compact then
            home.Page = math.Clamp((home.Page or 1) - delta, 1, home.Pages or 1)
        else
            home.ScrollTarget = (home.ScrollTarget or 0) - delta * (HOME_TILE_H + 10) / 2
        end
        return true
    end
    view.OnMousePressed = function(s, code)
        if code ~= MOUSE_LEFT or not home.Compact or (home.Pages or 1) < 2 then return end
        local x = s:CursorPos()
        home.Page = x < s:GetWide() / 2 and math.max(1, home.Page - 1) or math.min(home.Pages, home.Page + 1)
    end
    view.Think = function(s)
        if home.Compact then
            local target = -((home.Page or 1) - 1) * (home.PageSize or 1) * (HOME_COMPACT_W + 10)
            home.X = K.Spring(home.X or 0, target, 14)
            grid:SetPos(math.floor(home.X), 0)
            home.Scroll, home.ScrollTarget = 0, 0
        else
            local maxScroll = math.max(0, (home.ContentH or 0) - s:GetTall())
            home.ScrollTarget = math.Clamp(home.ScrollTarget or 0, 0, maxScroll)
            home.Scroll = K.Spring(home.Scroll or 0, home.ScrollTarget, 16)
            home.MaxScroll, home.X = maxScroll, 0
            grid:SetPos(0, -math.floor(home.Scroll))
        end
    end
    view.PaintOver = function(s, w, h)
        if home.Compact then
            local pages = home.Pages or 1
            if pages < 2 then return end
            local x = math.floor(w / 2 - (pages * 10 + 2) / 2)
            for i = 1, pages do
                local on = i == home.Page
                draw.RoundedBox(2, x, h - 6, on and 12 or 5, 5, on and T.accent or T.line)
                x = x + (on and 17 or 10)
            end
        elseif (home.MaxScroll or 0) > 0 then
            local grip = math.max(24, h * h / (h + home.MaxScroll))
            draw.RoundedBox(2, w - 4, (h - grip) * home.Scroll / home.MaxScroll, 4, grip, T.line)
        end
    end

    for index, id in ipairs(homeApps()) do
        local app = A.Registry[id] or {title = "Chat", subtitle = "Your conversations"}
        local tile = vgui.Create("DButton", grid)
        tile:SetText("")
        tile.GoobTile, tile.GoobPhone, tile.GoobOrder = true, phone, index
        tile.GoobTitle, tile.GoobGlyph, tile.GoobIcon = app.title, A.HomeGlyphs[id], app.icon
        tile:SetTooltip(app.title .. " — " .. (app.subtitle or ""))
        tile.DoClick = function() openHomeApp(phone, id) end
        tile.Paint = paintHomeTile
        -- Badges (mockup 00): Chat = lines that arrived off the chat page, Messages = unread private and
        -- group threads, CityLeak = unread reactions/replies to your posts.
        if id == "chat" then
            tile.GoobBadge = function(p) return IsValid(p) and p.phoneUnread or 0 end
        elseif id == "messages" then
            tile.GoobBadge = function() return home.ThreadUnread or 0 end
        elseif id == "feed" then
            tile.GoobBadge = function() return home.FeedUnread or 0 end
        elseif id == "voice" then
            tile.GoobDot = function() return home.VoiceLive end
        end
    end

    -- Data refresh: 4 Hz for unread/voice, 1 Hz for clock/chips; relayout only when something moved.
    home.Think = function(s)
        if s.PageSeen ~= phone.phonePageChanged then
            -- Coming back to Home always shows the launcher, never a tray left expanded earlier.
            s.PageSeen = phone.phonePageChanged
            if s.TrayOpen then
                s.TrayOpen = false
                A.LayoutHome(phone)
            end
        end
        local now = RealTime()
        if now < (s.NextPoll or 0) then return end
        s.NextPoll = now + 0.25
        local entries, unread, feed = homeEntries(phone)
        s.ThreadUnread, s.FeedUnread = unread, feed
        local live = false
        if A.Voice and A.Voice.Ready and A.Voice.Ready() then
            for _, row in ipairs(A.Voice.rows or {}) do
                if A.Voice.Visible(row) then
                    live = true
                    break
                end
            end
        end
        s.VoiceLive = live
        if now >= (s.NextSecond or 0) then
            s.NextSecond = now + 1
            s.ShortDate = os.date("%a, %b %d")
            s.Chips = homeChips(s)
        end
        local parts = {phone:GetWide(), phone:GetTall(), #grid:GetChildren(), s.TrayOpen and 1 or 0}
        for _, entry in ipairs(entries) do parts[#parts + 1] = entry.key .. "=" .. entry.body .. "@" .. entry.time end
        local signature = table.concat(parts, "|")
        s.Entries = entries
        if signature ~= s.Signature then
            s.Signature = signature
            A.LayoutHome(phone)
        end
    end
    A.LayoutHome(phone)
    home:Think()
end

function A.Open(phone, id)
    if IsValid(phone.appHost) then phone.appHost:Remove() end
    phone.appHost = nil
    local app = A.Registry[id]
    if not app then return end
    if id == "feed" and A.Notify and istable(A.Notify.History) then
        -- Opening CityLeak reads its reaction/reply entries (tray + badge).
        for _, h in ipairs(A.Notify.History) do
            if h.app == "CityLeak" then h.read = true end
        end
    end
    local minimum = math.min(520, math.floor(ScrH() * 0.65))
    if phone:GetTall() < minimum then
        if not phone.goobGeometry then
            phone.goobGeometry = {
                w = phone:GetWide(),
                h = phone:GetTall(),
                x = phone:GetX(),
                y = phone:GetY(),
                grown = minimum
            }
        end

        local bottom = phone:GetY() + phone:GetTall()
        phone:SetTall(minimum)
        phone:SetY(math.max(8, bottom - minimum))
    end

    local host = vgui.Create("DPanel", phone)
    phone.appHost = host
    host.GoobApp = id
    host:SetKeyboardInputEnabled(true)
    host:RequestFocus()
    host:DockPadding(12, 10, 12, 10)
    host.Paint = function() end -- transparent: the phone frame's translucent glass (cl_zchat.lua:36) shows through
    local back = A.Button(host, "‹  " .. app.title, function() phone:SetPhonePage("home") end, T.accent)
    back:SetTall(32)
    local body = vgui.Create("DPanel", host)
    body:Dock(FILL)
    body.Paint = function() end
    local ok, err = xpcall(function() app.build(body, phone) end, debug.traceback)
    if not ok then
        if body.OnRemove then pcall(body.OnRemove, body) end
        body:Clear()
        A.Status(body, "This app could not open. Your saved data is unchanged.", T.red)
        ErrorNoHalt("[GoobOS " .. id .. "] " .. tostring(err) .. "\n")
    end

    A.Layout(phone, phone:GetWide(), phone:GetTall())
end

function A.Layout(phone, w, h)
    if IsValid(phone.appHost) then
        phone.appHost:SetPos(8, 44)
        phone.appHost:SetSize(math.max(1, w - 16), math.max(1, h - 52))
    end

    if IsValid(phone.goobLauncher) and phone.goobLauncher.GoobKit then
        A.LayoutHome(phone, w, h)
    elseif IsValid(phone.goobLauncher) then
        local y = h - 44 >= 242 and 112 or 12
        phone.goobLauncher:SetPos(20, y)
        phone.goobLauncher:SetSize(math.max(1, w - 40), math.max(1, h - 44 - y - 12))
        if IsValid(phone.goobGrid) then
            local columns = math.max(2, math.floor((w - 45) / 108))
            local size = math.floor((w - 45 - (columns - 1) * 8) / columns)
            for _, tile in ipairs(phone.goobGrid:GetChildren()) do
                tile:SetSize(size, 104)
            end

            phone.goobGrid:InvalidateLayout(true)
        end
    end
end

function A.Sync(phone)
    local isApp = A.Registry[phone.phonePage] ~= nil and phone:GetActive()
    if not isApp and phone.goobGeometry then
        local g = phone.goobGeometry
        phone.goobGeometry = nil
        if phone:GetTall() == g.grown and phone:GetWide() == g.w then
            phone:SetSize(g.w, g.h)
            phone:SetPos(g.x, g.y)
        end
    end

    if not IsValid(phone.appHost) then return end
    if not phone:GetActive() or phone.phonePage ~= phone.appHost.GoobApp then
        phone.appHost:Remove()
        phone.appHost = nil
        return
    end

    phone.appHost:SetVisible(true)
end

-- The kit normally loads right after this file (autorun files array); ZChat can include apps.lua first.
if not A.Kit and file.Exists("zc_goobos/kit.lua", "LUA") then include("zc_goobos/kit.lua") end

concommand.Add("goobos", function(_, _, args) A.Launch(args[1] or "home") end)
