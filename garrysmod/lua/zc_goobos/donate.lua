-- GoobOS Donate app: links to the owner's Patreon through the Steam overlay. Client only; no net, no server file.
if not CLIENT then return end
local A = ZCGoobApps
if not A or not A.Register then return end
local T = A.Theme
local URL = "https://www.patreon.com/NecrosisDev"
local LINE = "Keep Goob's ZCity running. Donations go to hosting and development."

-- Heart glyph for the home tile and the page header (24-unit grid, closed polyline).
if A.Kit and A.Kit.Glyphs and not A.Kit.Glyphs.heart then
    A.Kit.Glyphs.heart = {{"c", 12, 20, 4.5, 12.5, 3.6, 9.5, 4.4, 6.6, 6.8, 4.8, 9.6, 4.8, 12, 7, 14.4, 4.8, 17.2, 4.8, 19.6, 6.6, 20.4, 9.5, 19.5, 12.5}}
end
A.HomeGlyphs = A.HomeGlyphs or {}
A.HomeGlyphs.donate = A.HomeGlyphs.donate or "heart"

local function openPatreon() gui.OpenURL(URL) end

local function build(body)
    local K = A.Kit
    if not K then
        A.Label(body, LINE)
        A.Button(body, "Open Patreon", openPatreon, T.accent)
        A.Button(body, "Copy link", function() SetClipboardText(URL) end)
        A.Status(body, URL)
        return
    end
    local card = K.Panel(body)
    card:Dock(FILL)
    card:DockPadding(16, 16, 16, 16)
    local head = K.Panel(card)
    head:Dock(TOP)
    head:SetTall(48)
    head.Paint = function(_, w)
        K.Plate(0, 0, 48, "heart")
        K.Text(K.Fit("Support Goob's ZCity", K.Font(20, 700), w - 62), 20, 700, 62, 3, T.text)
        K.Text("Patreon · NecrosisDev", 13, 500, 62, 28, T.muted)
    end
    local text = vgui.Create("DLabel", card)
    text:Dock(TOP)
    text:DockMargin(0, 12, 0, 0)
    text:SetFont(K.Font(15, 500))
    text:SetTextColor(T.text)
    text:SetText(LINE)
    text:SetWrap(true)
    text:SetAutoStretchVertical(true)

    local open = vgui.Create("DButton", card)
    open:Dock(TOP)
    open:DockMargin(0, 16, 0, 0)
    open:SetTall(44)
    open:SetText("")
    open:SetTooltip("Opens Patreon in the Steam overlay")
    open.DoClick = openPatreon
    open.Paint = function(s, w, h)
        local hover = K.Hover(s)
        draw.RoundedBox(4, 0, 0, w, h, T.main)
        if hover > 0.01 then draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.white, 22 * hover)) end
        K.Glyph("heart", w / 2 - 62, h / 2, 18, T.white)
        K.Text("Open Patreon", 16, 700, w / 2 + 10, h / 2, T.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local copy = vgui.Create("DButton", card)
    copy:Dock(TOP)
    copy:DockMargin(0, 8, 0, 0)
    copy:SetTall(34)
    copy:SetText("")
    copy.CopiedUntil = 0
    copy.DoClick = function(s)
        SetClipboardText(URL)
        s.CopiedUntil = RealTime() + 2
    end
    copy.Paint = function(s, w, h)
        local hover = K.Hover(s)
        draw.RoundedBox(4, 0, 0, w, h, T.card)
        if hover > 0.01 then draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.main, 50 * hover)) end
        local copied = RealTime() < s.CopiedUntil
        K.Text(copied and "Link copied" or "Copy link", 14, 600, w / 2, h / 2, copied and T.green or T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local link = K.Panel(card)
    link:Dock(TOP)
    link:DockMargin(0, 10, 0, 0)
    link:SetTall(18)
    link.Paint = function(_, w, h)
        K.Text(K.Fit(URL, K.Font(13, 500), w), 13, 500, w / 2, h / 2, T.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- Card background ends under the link line instead of filling the whole app body.
    card.Paint = function(_, w)
        local bottom = link:GetY() + link:GetTall() + 16
        K.Card(0, 0, w, bottom, T.cardGlass, K.Alpha(T.edge, 180))
    end
end

A.Register("donate", "Donate", "Support the server", "icon16/heart.png", T.accent, build)
