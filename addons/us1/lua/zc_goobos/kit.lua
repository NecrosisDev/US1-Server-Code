-- GoobOS kit: shared tokens, fonts, motion, painters and widgets for every GoobOS surface.
-- Everything hangs off ZCGoobApps.Kit (no other globals). Loaded after apps.lua by the files array
-- in lua/autorun/zc_goobos_apps.lua, and by apps.lua itself when ZChat includes apps.lua first.
-- Re-running this file only redefines functions; caches on the table survive.
-- Tokens and sizes: goobos_rework/mockups/tokens.md (sources cited there).
if not CLIENT then return end
ZCGoobApps = ZCGoobApps or {}
local A = ZCGoobApps
local K = A.Kit or {}
A.Kit = K
K.Version = "20260926.kit2"

-- Tokens. A.Theme keeps its live values (apps.lua); the kit only adds what the rework needs.
A.Theme = A.Theme or {}
local T = A.Theme
for key, value in pairs({
    glass = Color(20, 17, 17, 214), -- ZC_PANEL, cl_zchat.lua:36
    glassHi = Color(28, 25, 25, 235), -- phone bar fill, cl_zchat.lua:575
    edge = Color(83, 19, 23), -- ZC_FRAME_EDGE / observer dock edge
    cardGlass = Color(38, 35, 35, 200),
    hair = Color(150, 0, 0, 90), -- phone bar hairline, cl_zchat.lua:576
    badge = Color(192, 0, 0), -- owner decision 2026-09-24: unread badges in ZCity red
    ink = Color(16, 13, 13), -- ring behind badges and dots
    white = Color(255, 255, 255)
}) do
    if T[key] == nil then T[key] = value end
end

-- One reusable colour for alpha variants inside Paint: consumed immediately, never stored.
local scratch = Color(0, 0, 0)
function K.Alpha(color, alpha)
    scratch.r, scratch.g, scratch.b, scratch.a = color.r, color.g, color.b, alpha
    return scratch
end

-- Fonts: hg_font (ZCity's UI font convar, default Bahnschrift) at fixed pixel sizes, one font per size/weight.
K.Fonts = K.Fonts or {}
local function face()
    local cv = GetConVar("hg_font")
    local name = cv and cv:GetString() or ""
    return name ~= "" and name or "Bahnschrift"
end

local function makeFont(name, size, weight)
    surface.CreateFont(name, {font = face(), size = size, weight = weight, antialias = true, extended = true})
end

function K.Font(size, weight)
    size, weight = math.floor(size), math.floor(weight or 500)
    local key = size .. "." .. weight
    local name = K.Fonts[key]
    if name then return name end
    name = "GoobKit." .. key
    makeFont(name, size, weight)
    K.Fonts[key] = name
    return name
end

function K.RebuildFonts()
    for key, name in pairs(K.Fonts) do
        local size, weight = string.match(key, "^(%d+)%.(%d+)$")
        makeFont(name, tonumber(size), tonumber(weight))
    end
    K.FitCache, K.FitCount = {}, 0
end
cvars.AddChangeCallback("hg_font", function() K.RebuildFonts() end, "GoobKit.Fonts")

function K.Text(text, size, weight, x, y, color, alignX, alignY)
    return draw.SimpleText(text, K.Font(size, weight), x, y, color or T.text, alignX or TEXT_ALIGN_LEFT, alignY or TEXT_ALIGN_TOP)
end

-- Ellipsise to a pixel width. Cached per font/width/text: safe to call from Paint.
K.FitCache, K.FitCount = K.FitCache or {}, K.FitCount or 0
function K.Fit(text, font, width)
    text = tostring(text or "")
    local key = font .. "|" .. math.floor(width) .. "|" .. text
    local hit = K.FitCache[key]
    if hit then return hit end
    if K.FitCount >= 512 then K.FitCache, K.FitCount = {}, 0 end
    surface.SetFont(font)
    local result = text
    if surface.GetTextSize(text) > width then
        result = "…"
        local count = utf8.len(text) or #text
        for n = count - 1, 1, -1 do
            local cut = utf8.offset(text, n + 1)
            local head = cut and string.sub(text, 1, cut - 1) or string.sub(text, 1, n)
            if surface.GetTextSize(head .. "…") <= width then
                result = head .. "…"
                break
            end
        end
    end
    K.FitCache[key] = result
    K.FitCount = K.FitCount + 1
    return result
end

-- Word-wrap to a pixel width, at most maxLines (the last line ellipsised). Cached like K.Fit, so it is
-- safe to call from Paint; a word wider than the line is ellipsised rather than overflowing.
K.WrapCache, K.WrapCount = K.WrapCache or {}, K.WrapCount or 0
function K.Wrap(text, font, width, maxLines)
    text, width = tostring(text or ""), math.floor(width)
    local key = font .. "|" .. width .. "|" .. (maxLines or 0) .. "|" .. text
    local hit = K.WrapCache[key]
    if hit then return hit end
    if K.WrapCount >= 256 then K.WrapCache, K.WrapCount = {}, 0 end
    surface.SetFont(font)
    local lines, line = {}, ""
    for word in string.gmatch(text, "%S+") do
        local candidate = line == "" and word or line .. " " .. word
        if line == "" or surface.GetTextSize(candidate) <= width then
            line = candidate
        else
            lines[#lines + 1] = line
            line = word
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    if maxLines and #lines > maxLines then
        local rest = table.concat(lines, " ", maxLines)
        for i = #lines, maxLines + 1, -1 do lines[i] = nil end
        lines[maxLines] = rest
    end
    for i, l in ipairs(lines) do
        if surface.GetTextSize(l) > width then lines[i] = K.Fit(l, font, width) end
    end
    K.WrapCache[key] = lines
    K.WrapCount = K.WrapCount + 1
    return lines
end

-- Motion. Every duration collapses to instant under the phone's Reduce motion setting.
function K.Reduced()
    return ZCPhoneSettings and ZCPhoneSettings.ReducedMotion and ZCPhoneSettings.ReducedMotion() or false
end

function K.Ease(t)
    t = math.Clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end

function K.EaseOut(t)
    t = 1 - math.Clamp(t, 0, 1)
    return 1 - t * t * t
end

-- Fraction 0..1 of an animation that started at `start` (RealTime) and lasts `duration` seconds.
function K.Progress(start, duration)
    if K.Reduced() or not start or duration <= 0 then return 1 end
    return math.Clamp((RealTime() - start) / duration, 0, 1)
end

-- Frame-rate independent approach (the observer dock's easing): rate ~9 soft, ~16 snappy.
function K.Spring(current, target, rate)
    if K.Reduced() then return target end
    local value = Lerp(1 - math.exp(-FrameTime() * (rate or 12)), current, target)
    if math.abs(value - target) < 0.01 then return target end
    return value
end

-- Hover amount 0..1 kept on the panel.
function K.Hover(panel, rate)
    panel.GoobHover = K.Spring(panel.GoobHover or 0, panel:IsHovered() and 1 or 0, rate or 16)
    return panel.GoobHover
end

-- Painters --------------------------------------------------------------------------------------

-- Glass card: optional 1 px edge, radius 4.
function K.Card(x, y, w, h, fill, edge)
    if edge then
        draw.RoundedBox(4, x, y, w, h, edge)
        draw.RoundedBox(4, x + 1, y + 1, w - 2, h - 2, fill or T.cardGlass)
    else
        draw.RoundedBox(4, x, y, w, h, fill or T.cardGlass)
    end
end

-- Unread badge: ZCity-red pill, white count, dark ring so it reads over any plate. (x, y) = top-right corner.
function K.Badge(x, y, count)
    count = tonumber(count) or 0
    if count <= 0 then return end
    local label = count > 99 and "99+" or tostring(count)
    local font = K.Font(11, 700)
    surface.SetFont(font)
    local w = math.max(18, surface.GetTextSize(label) + 10)
    draw.RoundedBox(10, x - w - 2, y - 2, w + 4, 22, T.ink)
    draw.RoundedBox(9, x - w, y, w, 18, T.badge)
    draw.SimpleText(label, font, x - w / 2, y + 9, T.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

function K.Dot(x, y, size, color)
    draw.RoundedBox(math.floor((size + 4) / 2), x - 2, y - 2, size + 4, size + 4, T.ink)
    draw.RoundedBox(math.floor(size / 2), x, y, size, size, color or T.green)
end

-- Alive HUD (2026-09-25 HUD pass): the in-game HUD outside GoobOS draws with these, so every element shares one
-- scale, one font rule, one plate (glass fill, edge hairline, radius 4), one text shadow, one fade and one
-- bottom-centre layout. Mockup: work/loader/hud_audit_20260925/mockups/alive_hud.html.
function K.HudScale()
    return math.Clamp(math.min(ScrW() / 1920, ScrH() / 1080), 0.75, 1.5)
end

-- Font at a 1080p pixel size, scaled with the screen.
function K.HudFont(size, weight)
    return K.Font(math.max(10, math.floor(size * K.HudScale() + 0.5)), weight)
end

function K.HudPlate(x, y, w, h, alpha)
    alpha = alpha or 1
    x, y, w, h = math.floor(x), math.floor(y), math.floor(w), math.floor(h)
    draw.RoundedBox(4, x, y, w, h, K.Alpha(T.edge, 180 * alpha))
    draw.RoundedBox(4, x + 1, y + 1, w - 2, h - 2, K.Alpha(T.glass, T.glass.a * alpha))
end

-- Text over the world or a plate: whole pixels, one 1 px dark shadow. Returns draw.SimpleText's width, height.
local hudShadow, hudInk = Color(0, 0, 0), Color(0, 0, 0)
function K.HudText(text, font, x, y, color, alignX, alignY, alpha)
    color = color or T.text
    alpha = (alpha or 1) * (color.a or 255) / 255
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    hudShadow.a = 200 * alpha
    draw.SimpleText(text, font, x + 1, y + 1, hudShadow, alignX, alignY)
    hudInk.r, hudInk.g, hudInk.b, hudInk.a = color.r, color.g, color.b, 255 * alpha
    return draw.SimpleText(text, font, x, y, hudInk, alignX, alignY)
end

-- Keycap: label on an edge-coloured cap, (x, y) = top-left, height = size. Returns the cap width.
function K.HudKey(label, x, y, size, alpha)
    alpha = alpha or 1
    local font = K.Font(math.max(10, math.floor(size * 0.58)), 700)
    surface.SetFont(font)
    local w = math.max(size, surface.GetTextSize(label) + math.floor(size * 0.46))
    x, y = math.floor(x), math.floor(y)
    draw.RoundedBox(3, x, y, w, size, K.Alpha(T.edge, 200 * alpha))
    draw.SimpleText(label, font, x + math.floor(w / 2), y + math.floor(size / 2), K.Alpha(T.text, 255 * alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    return w
end

-- Eased visibility kept in `state` (any table): in 0.18 s, out 0.25 s by default, RealTime-based. Returns 0..1.
function K.HudFade(state, want, inTime, outTime)
    local now = RealTime()
    local dt = math.Clamp(now - (state.hudAt or now), 0, 0.1)
    state.hudAt = now
    local v = state.hudV or 0
    if K.Reduced() then
        v = want and 1 or 0
    elseif want then
        v = math.min(1, v + dt / (inTime or 0.18))
    else
        v = math.max(0, v - dt / (outTime or 0.25))
    end
    state.hudV = v
    return K.Ease(v)
end

-- Bottom-centre stack, centre lines at 1080p, scaled with the screen height. The stamina bar sits at 0.8 of the
-- height (owner, 2026-09-24); the others keep their distance from it at every resolution.
K.HudStack = {stamina = 864, giveup = 870, status = 910, grace = 956}
function K.HudY(slot)
    return math.floor(ScrH() * (K.HudStack[slot] or 540) / 1080 + 0.5)
end

-- UI cohesion pass (2026-09-26) -----------------------------------------------------------------
-- One theme for every surface (owner decision 2026-09-26: ZCity red; cyan only as a DATA accent - trajectories, organ
-- percentages, vitals - never as chrome). Tokens that five files used to copy by hand live here now.
for key, value in pairs({
    kill = Color(255, 90, 90), -- a kill mark / damage dealt to you
    death = Color(70, 150, 220), -- your death mark
    amber = Color(215, 153, 74), -- wounded / warning
    healthy = Color(119, 157, 135),
    chip = Color(10, 9, 9), -- chip and keycap backing
    inset = Color(20, 17, 17, 255), -- behind a replay render
    dim = Color(12, 10, 10, 215), -- over a replay render (loading, verdict)
    data = Color(108, 223, 243), -- data accent (forensics only)
}) do
    if T[key] == nil then T[key] = value end
end
T.radius = T.radius or {card = 4, chip = 3, pill = 8}
-- Tissue tints (the killcam's organ view, zc_killcam/viewer_parts/cl_part_02.lua D.Tissue): one table for the death
-- panel's body view, the bullet camera and the damage inspector.
T.tissue = T.tissue or {flesh = Color(196, 128, 116), organ = Color(206, 96, 86), lung = Color(236, 150, 162),
    dense = Color(150, 38, 38), vessel = Color(255, 52, 52), bone = Color(236, 226, 206), armor = Color(247, 199, 115)}

-- "m:ss" (0:08, 12:40). The one clock format on every GoobOS surface.
function K.Clock(seconds)
    seconds = tonumber(seconds)
    if not seconds then return nil end
    seconds = math.max(0, math.floor(seconds))
    return string.format("%i:%02i", math.floor(seconds / 60), seconds % 60)
end

-- First letter of a name, upper-case, UTF-8 safe ("?" for none): initials avatars.
function K.Initial(name)
    name = tostring(name or "")
    local cut = utf8.offset(name, 2)
    local first = cut and string.sub(name, 1, cut - 1) or name
    return first ~= "" and string.upper(first) or "?"
end

-- A painter set bound to one layout unit (P.Unit(): 1080p = 1). Full-screen panels set S.U once per layout pass and
-- paint in 1080p numbers; every size below goes through S.u. Replaces the u/font/text/fit/measure/chip/keycap copies
-- that deathpanel.lua and roundend.lua each carried.
function K.Scaler(unit)
    local S = {U = unit or 1}
    function S.u(n) return math.floor(n * S.U + 0.5) end
    function S.font(size, weight) return K.Font(math.max(8, S.u(size)), weight) end
    function S.text(str, size, weight, x, y, color, ax, ay)
        return draw.SimpleText(str, S.font(size, weight), x, y, color or T.text, ax or TEXT_ALIGN_LEFT, ay or TEXT_ALIGN_TOP)
    end
    function S.fit(str, size, weight, width) return K.Fit(str, S.font(size, weight), width) end
    function S.measure(str, size, weight)
        surface.SetFont(S.font(size, weight))
        return surface.GetTextSize(str)
    end
    -- Chip: small caps label on a dark pill, 20 units tall. align = TEXT_ALIGN_LEFT (x = left edge, default),
    -- _CENTER or _RIGHT. Returns the chip width.
    function S.chip(label, x, y, color, bg, align)
        local tw = S.measure(label, 10, 700) + S.u(14)
        local bx = align == TEXT_ALIGN_RIGHT and x - tw or (align == TEXT_ALIGN_CENTER and x - tw / 2 or x)
        draw.RoundedBox(T.radius.chip, bx, y, tw, S.u(20), bg or K.Alpha(T.chip, 200))
        S.text(label, 10, 700, bx + tw / 2, y + S.u(10), color or T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        return tw
    end
    -- Keycap, 20 units tall, (x, y) = top-left. Returns the cap width.
    function S.keycap(label, x, y, alpha)
        return K.HudKey(label, x, y, S.u(20), alpha)
    end
    -- One hint row: {{"Space", "Skip"}, {"Q", "Spectate"}, ...} as keycap + verb pairs. align: LEFT (x = left edge),
    -- CENTER or RIGHT. Returns the drawn width and a list of {x, w, index} spans for click zones.
    local function capWidth(label) -- mirrors K.HudKey's own sizing at height u(20)
        local size = S.u(20)
        surface.SetFont(K.Font(math.max(10, math.floor(size * 0.58)), 700))
        return math.max(size, surface.GetTextSize(label) + math.floor(size * 0.46))
    end
    function S.hintWidth(hints)
        local w, gap = 0, S.u(16)
        for i, h in ipairs(hints) do
            local cap = h[1] and (capWidth(h[1]) + S.u(6)) or 0
            w = w + cap + S.measure(h[2] or "", 11, 500) + (i < #hints and gap or 0)
        end
        return w
    end
    function S.hints(hints, x, y, align, alpha)
        local total = S.hintWidth(hints)
        if align == TEXT_ALIGN_CENTER then x = x - total / 2 elseif align == TEXT_ALIGN_RIGHT then x = x - total end
        local spans, gap = {}, S.u(16)
        for i, h in ipairs(hints) do
            local x0 = x
            if h[1] then x = x + S.keycap(h[1], x, y, alpha) + S.u(6) end
            S.text(h[2] or "", 11, 500, x, y + S.u(10), K.Alpha(h.color or T.muted, 255 * (alpha or 1)), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            x = x + S.measure(h[2] or "", 11, 500)
            spans[i] = {x0, x - x0, i}
            x = x + gap
        end
        return total, spans
    end
    return S
end

-- One button for every GoobOS surface. spec:
--   label    string or function() -> string (re-read every frame)
--   kind     "primary" (red fill) | "secondary" (card, default) | "ghost" (outline) | "quiet" (text) | "danger"
--   click    function(button)          enabled  function() -> bool (greyed + inert when false)
--   key      keycap label drawn at the left ("V", "Space")      glyph  K.Glyph name drawn at the left
--   sub      string or function: a right-aligned secondary value (arcade stakes)
--   selected function() -> bool (gold "on" state)                 align  TEXT_ALIGN_CENTER (default) or _LEFT
--   size     label font size (default 14)   scaler  a K.Scaler (full-screen panels) - sizes then scale with it
--   dock     false = free-positioned (caller sizes it); default docks TOP, 36 px tall, 7 px gap
function K.Button(parent, spec)
    spec = spec or {}
    local S = spec.scaler
    local function su(n) return S and S.u(n) or n end
    local function sf(size, weight) return S and S.font(size, weight) or K.Font(size, weight) end
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetCursor("hand")
    if spec.dock ~= false then
        b:Dock(TOP)
        b:DockMargin(0, 0, 0, 7)
        b:SetTall(36)
    end
    b.Spec = spec
    b.GoobLabel = isstring(spec.label) and spec.label or nil -- test/debug discoverability only
    function b:IsOn() return not self.Spec.enabled or self.Spec.enabled() end
    function b:LabelText()
        local l = self.Label or self.Spec.label
        return tostring((isfunction(l) and l() or l) or "")
    end
    b.DoClick = function(s)
        if not s:IsOn() then return end
        s.Flash = RealTime()
        if s.Spec.click then s.Spec.click(s) end
    end
    b.Paint = function(s, w, h)
        local sp = s.Spec
        local kind = sp.kind or "secondary"
        local on, hover, sel = s:IsOn(), K.Hover(s), sp.selected and sp.selected()
        local r = T.radius.card
        if kind == "primary" then
            draw.RoundedBox(r, 0, 0, w, h, on and T.main or K.Alpha(T.main, 70))
        elseif kind == "secondary" or kind == "danger" then
            draw.RoundedBox(r, 0, 0, w, h, sel and K.Alpha(T.gold, 40) or T.card)
        elseif kind == "ghost" then
            draw.RoundedBox(r, 0, 0, w, h, K.Alpha(T.ink, 90))
            surface.SetDrawColor(T.line)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
        end
        if on and hover > 0.01 then draw.RoundedBox(r, 0, 0, w, h, K.Alpha(T.white, (kind == "primary" and 20 or 13) * hover)) end
        local flash = s.Flash and 1 - K.Progress(s.Flash, 0.2) or 0
        if flash > 0 then draw.RoundedBox(r, 0, 0, w, h, K.Alpha(T.white, 40 * flash)) end
        local color = kind == "primary" and T.white or (kind == "danger" and T.red) or (kind == "quiet" and (hover > 0.5 and T.text or T.muted)) or T.text
        if sel then color = T.gold end
        if not on then color = T.muted end
        local size = sp.size or 14
        local fnt = sf(size, 600)
        local lx = su(10)
        if sp.key then lx = lx + K.HudKey(sp.key, lx, h / 2 - su(9), su(18), on and 1 or 0.5) + su(8)
        elseif sp.glyph then K.Glyph(sp.glyph, lx + su(8), h / 2, su(16), color) lx = lx + su(24) end
        local sub = isfunction(sp.sub) and sp.sub() or sp.sub
        local label = s:LabelText()
        if sub and w >= su(150) then
            draw.SimpleText(K.Fit(label, fnt, w - lx - su(80)), fnt, lx + su(4), h / 2, color, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(tostring(sub), sf(size - 1, 600), w - su(12), h / 2, on and (kind == "primary" and K.Alpha(T.white, 190) or T.gold) or T.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        elseif sp.align == TEXT_ALIGN_LEFT or sp.key or sp.glyph then
            local room = w - lx - su(10)
            if sp.align ~= TEXT_ALIGN_LEFT then
                surface.SetFont(fnt)
                local tw = math.min(surface.GetTextSize(label), room)
                draw.SimpleText(K.Fit(label, fnt, room), fnt, lx + (room - tw) / 2, h / 2, color, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            else
                draw.SimpleText(K.Fit(label, fnt, room), fnt, lx + su(4), h / 2, color, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
        else
            draw.SimpleText(K.Fit(label, fnt, w - su(16)), fnt, w / 2, h / 2, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    -- Natural width for free-positioned rows (never a fixed 140 px at any scale).
    function b:Measure()
        surface.SetFont(sf(self.Spec.size or 14, 600))
        local tw = surface.GetTextSize(self:LabelText())
        local extra = 0
        if self.Spec.key then
            surface.SetFont(K.Font(math.max(10, math.floor(su(18) * 0.58)), 700))
            extra = math.max(su(18), surface.GetTextSize(self.Spec.key) + math.floor(su(18) * 0.46)) + su(8)
        elseif self.Spec.glyph then extra = su(24) end
        return tw + su(32) + extra
    end
    return b
end

-- Line glyphs on a 24-unit grid (the mockups' icons). l = open polyline, c = closed polyline,
-- r = rectangle outline, o = ring, d = filled dot. Drawn ~2 px thick in the current colour.
K.Glyphs = {
    chat = {{"c", 4, 5, 20, 5, 20, 16, 8, 16, 4, 19}},
    mail = {{"r", 3, 5, 18, 14}, {"l", 3, 6, 12, 13, 21, 6}},
    camera = {{"r", 3, 7, 18, 12}, {"o", 12, 13, 3.4}, {"l", 8, 7, 9.4, 5, 14.6, 5, 16, 7}},
    grid = {{"r", 3.5, 3.5, 7, 7}, {"r", 13.5, 3.5, 7, 7}, {"r", 3.5, 13.5, 7, 7}, {"r", 13.5, 13.5, 7, 7}},
    dice = {{"r", 4, 4, 16, 16}, {"d", 9, 9, 1.2}, {"d", 15, 9, 1.2}, {"d", 9, 15, 1.2}, {"d", 15, 15, 1.2}, {"d", 12, 12, 1.2}},
    bag = {{"c", 6, 8, 18, 8, 17, 20, 7, 20}, {"l", 9, 8, 9, 6, 10, 4.2, 12, 3.4, 14, 4.2, 15, 6, 15, 8}},
    hanger = {{"c", 12, 7.6, 20, 12.5, 20, 14.3, 4, 14.3, 4, 12.5}, {"l", 12, 7.6, 12, 6.4, 13.6, 5.6, 14, 4.2, 13, 3.2, 11.4, 3.4, 10.6, 4.4}},
    bars = {{"l", 5, 19, 5, 11}, {"l", 11, 19, 11, 6}, {"l", 17, 19, 17, 14}, {"l", 4, 19.5, 20, 19.5}},
    mic = {{"r", 9, 3, 6, 10}, {"l", 5, 11, 5.6, 14, 7.6, 16.6, 10, 17.8, 12, 18, 14, 17.8, 16.4, 16.6, 18.4, 14, 19, 11}, {"l", 12, 18, 12, 21}},
    cog = {{"o", 12, 12, 3.2}, {"l", 12, 3.2, 12, 5.6}, {"l", 12, 18.4, 12, 20.8}, {"l", 3.2, 12, 5.6, 12}, {"l", 18.4, 12, 20.8, 12},
        {"l", 5.8, 5.8, 7.5, 7.5}, {"l", 16.5, 16.5, 18.2, 18.2}, {"l", 5.8, 18.2, 7.5, 16.5}, {"l", 16.5, 7.5, 18.2, 5.8}},
    play = {{"r", 3, 4, 18, 16}, {"c", 10, 8.5, 15.5, 12, 10, 15.5}},
    pulse = {{"l", 3, 13, 7, 13, 9, 8, 12, 17, 14, 11, 16, 13, 21, 13}},
    check = {{"l", 5, 12.5, 10, 17, 19, 7}},
    bell = {{"l", 6, 16, 6, 11, 7, 7.6, 9.4, 5.4, 12, 4.8, 14.6, 5.4, 17, 7.6, 18, 11, 18, 16}, {"l", 4.5, 16.5, 19.5, 16.5}, {"l", 10.5, 19, 13.5, 19}},
    empty = {{"r", 4, 5, 16, 14}, {"l", 4, 9, 20, 9}},
    -- Polish pass 2026-09-24: vector stand-ins for characters Bahnschrift does not contain (checked
    -- against the font's cmap: U+21BB, U+2605, U+2691, U+2660-2666 are missing and draw as boxes).
    star = {{"c", 12, 3, 14.6, 9.2, 21, 9.5, 16, 13.7, 17.6, 20.5, 12, 16.8, 6.4, 20.5, 8, 13.7, 3, 9.5, 9.4, 9.2}},
    flag = {{"l", 7, 21, 7, 3.5}, {"c", 7, 4, 18, 7.5, 7, 11}},
    diamond = {{"c", 12, 3, 19, 12, 12, 21, 5, 12}},
    spade = {{"c", 12, 3, 19, 11, 19.4, 14.5, 17, 16.6, 13.6, 15.6, 12, 13.8, 10.4, 15.6, 7, 16.6, 4.6, 14.5, 5, 11}, {"l", 12, 14, 12, 20}, {"l", 9, 20.5, 15, 20.5}},
    club = {{"o", 12, 7.2, 3.6}, {"o", 7.4, 13.6, 3.6}, {"o", 16.6, 13.6, 3.6}, {"l", 12, 12, 12, 20}, {"l", 9, 20.5, 15, 20.5}},
    smile = {{"o", 12, 12, 8.5}, {"d", 9, 10, 1}, {"d", 15, 10, 1}, {"l", 8.5, 14, 10, 16, 12, 16.8, 14, 16, 15.5, 14}},
    wow = {{"o", 12, 12, 8.5}, {"d", 9, 9.5, 1}, {"d", 15, 9.5, 1}, {"o", 12, 15, 2.4}},
    like = {{"c", 3.5, 11, 7.5, 11, 7.5, 20, 3.5, 20}, {"l", 7.5, 11, 11, 4, 13, 4.6, 13.4, 9, 19.2, 9, 20.4, 11, 18.8, 19.5, 7.5, 19.5}}
}
-- Heart (Love reaction, Donate tile) lives in the kit too; donate.lua only adds it when missing.
K.Glyphs.heart = K.Glyphs.heart or {{"c", 12, 20, 4.5, 12.5, 3.6, 9.5, 4.4, 6.6, 6.8, 4.8, 9.6, 4.8, 12, 7, 14.4, 4.8, 17.2, 4.8, 19.6, 6.6, 20.4, 9.5, 19.5, 12.5}}
-- Circular refresh arrow (was arcade.lua-only; CityLeak drew the missing U+21BB instead).
if not K.Glyphs.refresh then
    local arc, a0, a1, steps = {"l"}, -40, 250, 12
    for i = 0, steps do
        local a = math.rad(a0 + (a1 - a0) * i / steps)
        arc[#arc + 1] = 12 + math.cos(a) * 7.5
        arc[#arc + 1] = 12 + math.sin(a) * 7.5
    end
    local tipA = math.rad(a1)
    local tx, ty = 12 + math.cos(tipA) * 7.5, 12 + math.sin(tipA) * 7.5
    local nx, ny = math.cos(tipA + math.pi / 2), math.sin(tipA + math.pi / 2)
    K.Glyphs.refresh = {arc, {"l", tx - nx * 5 - math.cos(tipA) * 2, ty - ny * 5 - math.sin(tipA) * 2, tx, ty, tx - nx * 5 + math.cos(tipA) * 2, ty - ny * 5 + math.sin(tipA) * 2}}
end

local ringPoints = {}
local function unitRing()
    if #ringPoints == 0 then
        for i = 0, 23 do
            local a = i / 24 * math.pi * 2
            ringPoints[#ringPoints + 1] = {math.cos(a), math.sin(a)}
        end
    end
    return ringPoints
end

local function thickLine(x1, y1, x2, y2)
    surface.DrawLine(x1, y1, x2, y2)
    surface.DrawLine(x1 + 1, y1, x2 + 1, y2)
    surface.DrawLine(x1, y1 + 1, x2, y2 + 1)
end

-- Icons v2 (2026-09-25, fixed 09-25 after black squares): anti-aliased glyphs. Each glyph is authored on a 24-unit grid as shapes,
-- once per pixel size into a white coverage mask (signed-distance box filter, so every edge is smoothed and
-- strokes stay symmetric), baked into one render-target atlas and drawn tinted with a single textured quad.
-- zc_goob_icons: 0 = legacy line glyphs for everyone, 1 = v2 for zc_goob_icons_tester only, 2 = v2 for all.
-- Until a glyph is baked (first frame it is seen) the legacy renderer draws it, so nothing ever blinks out.
-- Shapes: {"s", x1,y1, ...} open stroke; {"a", cx,cy,r, deg0,deg1} arc stroke (0 = right, clockwise);
-- {"L", shape...} outline of the union; {"F", shape...} filled union; {"K", shape...} cut a gap out of what
-- is drawn so far. shape = {"rr", x,y,w,h,r} | {"ci", cx,cy,r} | {"pg", x1,y1, ...}. Optional w = stroke scale.
do
    local sqrt, floor, min, max, abs = math.sqrt, math.floor, math.min, math.max, math.abs
    local cos, sin, rad, pi = math.cos, math.sin, math.rad, math.pi
    local I = {}
    K.IconsV2 = I

    local function rr(x, y, w, h, r) return {"rr", x, y, w, h, r or 0} end
    local function ci(x, y, r) return {"ci", x, y, r} end
    local function pg(...) return {"pg", ...} end
    -- Points along an arc, appended to list (angles in degrees, clockwise on screen).
    local function arcPts(list, cx, cy, r, a0, a1, steps)
        for i = 0, steps do
            local a = rad(a0 + (a1 - a0) * i / steps)
            list[#list + 1] = cx + cos(a) * r
            list[#list + 1] = cy + sin(a) * r
        end
        return list
    end
    -- Filled arrow head at the end of an arc, pointing along the direction of travel.
    local function arcHead(cx, cy, r, a, dir, len, half)
        local ar = rad(a)
        local px, py = cx + cos(ar) * r, cy + sin(ar) * r
        local tx, ty = -sin(ar) * dir, cos(ar) * dir
        local nx, ny = cos(ar), sin(ar)
        return {"F", pg(px + tx * len, py + ty * len, px + nx * half, py + ny * half, px - nx * half, py - ny * half)}
    end
    local function heartPts(cx, cy, s)
        local list = {"pg"}
        for i = 0, 39 do
            local t = i / 40 * pi * 2
            local x = 16 * sin(t) ^ 3
            local y = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
            list[#list + 1] = cx + x * s
            list[#list + 1] = cy - y * s
        end
        return list
    end
    local function starPts(cx, cy, ro, ri)
        local list = {"pg"}
        for i = 0, 9 do
            local a = rad(-90 + i * 36)
            local r = i % 2 == 0 and ro or ri
            list[#list + 1] = cx + cos(a) * r
            list[#list + 1] = cy + sin(a) * r
        end
        return list
    end
    local function gearPts(cx, cy, rIn, rOut, teeth)
        local list, step = {"pg"}, 360 / teeth
        for i = 0, teeth - 1 do
            local c = -90 + i * step
            for _, p in ipairs({{-step * 0.3, rIn}, {-step * 0.17, rOut}, {step * 0.17, rOut}, {step * 0.3, rIn}}) do
                local a = rad(c + p[1])
                list[#list + 1] = cx + cos(a) * p[2]
                list[#list + 1] = cy + sin(a) * p[2]
            end
        end
        return list
    end

    local bell = arcPts({"pg", 4.5, 17.5, 6, 15.5, 6, 11}, 12, 11, 6, 180, 360, 10)
    bell[#bell + 1], bell[#bell + 2], bell[#bell + 3], bell[#bell + 4] = 18, 15.5, 19.5, 17.5
    local cup = arcPts({"pg", 6.5, 3.5, 17.5, 3.5, 17.5, 8.5}, 12, 8.5, 5.5, 0, 180, 10)
    local ghost = arcPts({"pg"}, 12, 10, 7, 180, 360, 12)
    for _, v in ipairs({19, 20.5, 16.7, 18.6, 14.3, 20.5, 12, 18.6, 9.7, 20.5, 7.3, 18.6, 5, 20.5}) do ghost[#ghost + 1] = v end
    local spade = heartPts(12, 11, 0.5)
    for i = 3, #spade, 2 do spade[i] = 22 - spade[i] end -- flip the heart upside down
    local club = {"F", ci(12, 7.5, 4), ci(7.3, 13.2, 4), ci(16.7, 13.2, 4), pg(10.2, 12, 13.8, 12, 15.5, 21, 8.5, 21)}

    I.Defs = {
        -- Home screen apps
        chat = {{"L", rr(2.5, 3, 13, 9.5, 3), pg(5, 10, 9, 10, 4.5, 16)}, {"K", rr(8.5, 8.5, 13, 9.5, 3), pg(15, 15, 19, 15, 19.5, 21.5)},
            {"L", rr(8.5, 8.5, 13, 9.5, 3), pg(15, 15, 19, 15, 19.5, 21.5)}},
        mail = {{"L", rr(2.5, 5, 19, 14, 2.5)}, {"s", 3.5, 6.5, 12, 13, 20.5, 6.5}},
        camera = {{"L", rr(2.5, 7, 19, 13, 2.5), pg(7.5, 8, 9.2, 4.5, 14.8, 4.5, 16.5, 8)}, {"L", ci(12, 13.4, 3.7)}, {"F", ci(18.2, 10.2, 1)}},
        news = {{"L", rr(4.5, 3.5, 16.5, 17, 2)}, {"s", 4.5, 8, 2.5, 8, 2.5, 18.5, 4.5, 20.5}, {"F", rr(8, 7, 5.5, 5, 1)},
            {"s", 16, 7.5, 17.5, 7.5}, {"s", 16, 11.5, 17.5, 11.5}, {"s", 8, 15.5, 17.5, 15.5}, {"s", 8, 18, 14, 18, w = 0.9}},
        gamepad = {{"L", rr(2.5, 6.5, 19, 9.5, 4.75), ci(6.8, 15.2, 3.6), ci(17.2, 15.2, 3.6)}, {"s", 5.6, 11.2, 9.8, 11.2}, {"s", 7.7, 9.1, 7.7, 13.3},
            {"F", ci(15.4, 10.2, 1.25)}, {"F", ci(17.9, 12.6, 1.25)}},
        bag = {{"L", pg(5.5, 8, 18.5, 8, 19.8, 20.5, 4.2, 20.5)}, {"a", 12, 8, 3.6, 180, 360}},
        shirt = {{"L", pg(9, 3.5, 4, 5.5, 1.8, 10.8, 5.8, 12.2, 5.8, 20.5, 18.2, 20.5, 18.2, 12.2, 22.2, 10.8, 20, 5.5, 15, 3.5, 13.8, 5.2, 12, 5.9, 10.2, 5.2)}},
        trophy = {{"L", cup}, {"a", 6.5, 7, 2.8, 90, 270}, {"a", 17.5, 7, 2.8, -90, 90}, {"s", 12, 14, 12, 18}, {"L", rr(7.5, 18, 9, 3, 1)}},
        mic = {{"L", rr(9, 2.5, 6, 11.5, 3)}, {"a", 12, 11, 6.2, 0, 180}, {"s", 12, 17.2, 12, 21}, {"s", 8.5, 21, 15.5, 21}},
        cog = {{"L", gearPts(12, 12, 7.2, 9.8, 8)}, {"L", ci(12, 12, 3)}},
        heart = {{"F", heartPts(12, 12.2, 0.53)}},
        replay = {{"a", 12, 12.5, 8.5, -45, 225}, arcHead(12, 12.5, 8.5, -45, -1, 6.5, 4.8), {"F", pg(9.8, 8.6, 16, 12.5, 9.8, 16.4)}},
        ghost = {{"L", ghost}, {"F", ci(9.5, 10.5, 1.4)}, {"F", ci(14.5, 10.5, 1.4)}},
        grid = {{"L", rr(3.5, 3.5, 7, 7, 1.8)}, {"L", rr(13.5, 3.5, 7, 7, 1.8)}, {"L", rr(3.5, 13.5, 7, 7, 1.8)}, {"L", rr(13.5, 13.5, 7, 7, 1.8)}},
        -- Shared symbols
        dice = {{"L", rr(3.5, 3.5, 17, 17, 4)}, {"F", ci(8.2, 8.2, 1.6)}, {"F", ci(12, 12, 1.6)}, {"F", ci(15.8, 15.8, 1.6)}},
        hanger = {{"a", 12, 5.6, 2.4, 170, 400}, {"s", 13.8, 7.2, 12, 9.4}, {"L", pg(12, 9.4, 21.5, 16, 21, 18, 3, 18, 2.5, 16)}},
        bars = {{"s", 6, 19.5, 6, 13, w = 1.35}, {"s", 12, 19.5, 12, 5, w = 1.35}, {"s", 18, 19.5, 18, 9.5, w = 1.35}},
        play = {{"L", ci(12, 12, 9.5)}, {"F", pg(9.8, 7.8, 16.6, 12, 9.8, 16.2)}},
        pulse = {{"s", 2.5, 12.5, 7, 12.5, 9.5, 6.5, 14, 18.5, 16.5, 10, 18, 12.5, 21.5, 12.5}},
        check = {{"s", 4.5, 12.5, 9.8, 17.5, 19.5, 6.5, w = 1.15}},
        bell = {{"L", bell}, {"a", 12, 19, 2.4, 0, 180}},
        empty = {{"L", pg(2.5, 13, 6, 4.5, 18, 4.5, 21.5, 13, 21.5, 19.5, 2.5, 19.5)}, {"s", 3, 13, 8.2, 13, 9.8, 15.8, 14.2, 15.8, 15.8, 13, 21, 13}},
        star = {{"F", starPts(12, 12.8, 10, 4.2)}},
        flag = {{"s", 6, 21, 6, 3}, {"F", pg(6, 3.2, 19, 7.8, 6, 12.6)}},
        diamond = {{"F", pg(12, 2.5, 19.2, 12, 12, 21.5, 4.8, 12)}},
        spade = {{"F", spade, pg(10.5, 15, 13.5, 15, 15.5, 21.5, 8.5, 21.5)}},
        club = {club},
        smile = {{"L", ci(12, 12, 9.5)}, {"F", ci(8.8, 9.6, 1.4)}, {"F", ci(15.2, 9.6, 1.4)}, {"a", 12, 12.2, 5, 25, 155}},
        wow = {{"L", ci(12, 12, 9.5)}, {"F", ci(8.8, 9.2, 1.4)}, {"F", ci(15.2, 9.2, 1.4)}, {"L", ci(12, 15.6, 2.4)}},
        like = {{"L", rr(2.5, 10.5, 4.5, 10, 1.2)}, {"L", pg(7, 10.5, 10.8, 3.6, 12.4, 3.4, 13.6, 4.8, 13, 9.5, 19.2, 9.5, 21, 11.6, 19.4, 19, 17.6, 20.5, 7, 20.5)}},
        refresh = {{"a", 12, 12, 8, -45, 225}, arcHead(12, 12, 8, 225, 1, 6.5, 4.8)},
        send = {{"L", pg(21.5, 2.5, 14.5, 21.5, 11, 13, 2.5, 9.5)}, {"s", 21.5, 2.5, 11, 13}},
        plus = {{"s", 12, 4.5, 12, 19.5}, {"s", 4.5, 12, 19.5, 12}},
        chevronleft = {{"s", 15, 4.5, 8, 12, 15, 19.5}},
        -- Arcade
        ["arcade.rock"] = {{"L", pg(2.5, 19, 4, 13, 7.5, 8.5, 11, 7, 13.5, 5, 17.5, 6, 20.5, 10.5, 21.5, 19)}, {"s", 13.5, 5, 13, 9.5, 15.5, 11.5, w = 0.85}, {"s", 2.5, 19, 21.5, 19}},
        ["arcade.paper"] = {{"L", pg(5.5, 2.5, 14.5, 2.5, 19, 7, 19, 21.5, 5.5, 21.5)}, {"s", 14.5, 2.5, 14.5, 7, 19, 7}, {"s", 8.8, 12, 15.5, 12, w = 0.85}, {"s", 8.8, 15.5, 15.5, 15.5, w = 0.85}},
        ["arcade.scissors"] = {{"L", ci(6, 6.5, 3)}, {"L", ci(6, 17.5, 3)}, {"s", 8.4, 8.2, 21, 17.2}, {"s", 8.4, 15.8, 21, 6.8}},
        ["arcade.grid"] = {{"s", 9, 3, 9, 21}, {"s", 15, 3, 15, 21}, {"s", 3, 9, 21, 9}, {"s", 3, 15, 21, 15}},
        ["arcade.minus"] = {{"s", 5.5, 12, 18.5, 12}},
        ["arcade.plus"] = {{"s", 12, 5.5, 12, 18.5}, {"s", 5.5, 12, 18.5, 12}}
    }
    -- Names that exist only in v2, drawn with their closest legacy glyph on the old path.
    I.Legacy = {news = "grid", gamepad = "dice", shirt = "hanger", trophy = "bars", replay = "play", ghost = "pulse"}

    -- Rasteriser -------------------------------------------------------------------------------------
    local function segDist(px, py, ax, ay, bx, by)
        local dx, dy = bx - ax, by - ay
        local l2 = dx * dx + dy * dy
        local t = l2 > 0 and max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / l2)) or 0
        local qx, qy = ax + dx * t - px, ay + dy * t - py
        return sqrt(qx * qx + qy * qy)
    end
    -- Signed distance (negative inside) of one shape, in grid units.
    local function shapeSD(s, px, py)
        local kind = s[1]
        if kind == "ci" then
            local dx, dy = px - s[2], py - s[3]
            return sqrt(dx * dx + dy * dy) - s[4]
        elseif kind == "rr" then
            local r = s[6]
            local hx, hy = s[4] / 2, s[5] / 2
            local qx, qy = abs(px - s[2] - hx) - hx + r, abs(py - s[3] - hy) - hy + r
            local ox, oy = max(qx, 0), max(qy, 0)
            return sqrt(ox * ox + oy * oy) + min(max(qx, qy), 0) - r
        end
        local n, best, inside = #s, math.huge, false
        local jx, jy = s[n - 1], s[n]
        for i = 2, n - 1, 2 do
            local ix, iy = s[i], s[i + 1]
            local d = segDist(px, py, jx, jy, ix, iy)
            if d < best then best = d end
            if (iy > py) ~= (jy > py) and px < (jx - ix) * (py - iy) / (jy - iy) + ix then inside = not inside end
            jx, jy = ix, iy
        end
        return inside and -best or best
    end
    local function unionSD(cmd, px, py)
        local d = math.huge
        for i = 2, #cmd do
            local v = shapeSD(cmd[i], px, py)
            if v < d then d = v end
        end
        return d
    end
    local function arcDist(cmd, px, py)
        local cx, cy, r, a0, a1 = cmd[2], cmd[3], cmd[4], cmd[5], cmd[6]
        local dx, dy = px - cx, py - cy
        local a = math.deg(math.atan2(dy, dx))
        local rel = (a - a0) % 360
        if rel <= (a1 - a0) then return abs(sqrt(dx * dx + dy * dy) - r) end
        local e0, e1 = rad(a0), rad(a1)
        return min(segDist(px, py, cx + cos(e0) * r, cy + sin(e0) * r, cx + cos(e0) * r, cy + sin(e0) * r),
            segDist(px, py, cx + cos(e1) * r, cy + sin(e1) * r, cx + cos(e1) * r, cy + sin(e1) * r))
    end

    -- Stroke width in pixels for a glyph drawn size px tall: 2 grid units at 24 px, never under 1.25 px.
    function I.StrokeWidth(size) return max(1.25, size / 12) end

    -- Hinting: move a straight horizontal/vertical stroke (and an outlined box's edges) so its centre sits
    -- where a stroke of the rounded pixel width renders crisp - a pixel centre for odd widths, an edge for
    -- even - instead of smearing across two half-lit pixels. Returns a per-size copy of the glyph.
    local function snap(v, u, odd)
        local p = v * u
        return (odd and floor(p) + 0.5 or floor(p + 0.5)) / u
    end
    local function hinted(def, size)
        local u = size / 24
        local out = {}
        for n, cmd in ipairs(def) do
            local odd = floor(I.StrokeWidth(size) * (cmd.w or 1) + 0.5) % 2 == 1
            local copy = {}
            for k, v in pairs(cmd) do copy[k] = v end
            if cmd[1] == "s" then
                for i = 2, #cmd - 3, 2 do
                    if cmd[i] == cmd[i + 2] then copy[i] = snap(cmd[i], u, odd); copy[i + 2] = copy[i] end
                    if cmd[i + 1] == cmd[i + 3] then copy[i + 1] = snap(cmd[i + 1], u, odd); copy[i + 3] = copy[i + 1] end
                end
            elseif cmd[1] == "L" and #cmd == 2 and cmd[2][1] == "rr" then
                local r = cmd[2]
                local x0, y0 = snap(r[2], u, odd), snap(r[3], u, odd)
                copy[2] = {"rr", x0, y0, snap(r[2] + r[4], u, odd) - x0, snap(r[3] + r[5], u, odd) - y0, r[6]}
            end
            out[n] = copy
        end
        return out
    end

    -- Coverage mask for glyph name at an integer pixel size: array [y * size + x + 1] of 0..1, or nil.
    function I.Coverage(name, size)
        local def = I.Defs[name]
        if not def then return nil end
        def = hinted(def, size)
        local u = size / 24
        local baseHalf = I.StrokeWidth(size) / 2 / u -- half stroke in grid units
        local aa = 0.5 / u -- half a pixel in grid units: the box-filter ramp
        local gap = I.StrokeWidth(size) * 0.9 / u
        local out = {}
        for y = 0, size - 1 do
            local gy = (y + 0.5) / u
            for x = 0, size - 1 do
                local gx = (x + 0.5) / u
                local cov = 0
                for _, cmd in ipairs(def) do
                    local kind, c = cmd[1], 0
                    local half = baseHalf * (cmd.w or 1)
                    if kind == "s" then
                        local d = math.huge
                        for i = 2, #cmd - 3, 2 do
                            local v = segDist(gx, gy, cmd[i], cmd[i + 1], cmd[i + 2], cmd[i + 3])
                            if v < d then d = v end
                        end
                        c = (half + aa - d) / (2 * aa)
                    elseif kind == "a" then
                        c = (half + aa - arcDist(cmd, gx, gy)) / (2 * aa)
                    elseif kind == "L" then
                        c = (half + aa - abs(unionSD(cmd, gx, gy))) / (2 * aa)
                    elseif kind == "F" then
                        c = (aa - unionSD(cmd, gx, gy)) / (2 * aa)
                    elseif kind == "K" then
                        local k = (aa - (unionSD(cmd, gx, gy) - gap)) / (2 * aa)
                        k = k < 0 and 0 or k > 1 and 1 or k
                        cov = cov * (1 - k)
                        c = 0
                    end
                    c = c < 0 and 0 or c > 1 and 1 or c
                    if c > cov then cov = c end
                end
                out[y * size + x + 1] = cov
            end
        end
        return out
    end

    -- Render path (client only; the harness above runs anywhere) -------------------------------------
    -- The atlas is OPAQUE: white-on-black coverage, drawn additively (black adds nothing). No alpha channel
    -- is involved anywhere - the first push relied on render-target alpha and drew black squares on US1.
    -- A self-test draws a known pattern through the whole path and reads it back before any icon is shown;
    -- on any mismatch v2 switches itself off for the session and the legacy glyphs draw.
    if CLIENT and GetRenderTargetEx then
        local modeVar = CreateConVar("zc_goob_icons", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "GoobOS icons v2: 0 legacy, 1 tester only, 2 everyone")
        local testerVar = CreateConVar("zc_goob_icons_tester", "76561198011536179", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "SteamID64 that sees GoobOS icons v2 while zc_goob_icons is 1")
        local ATLAS, PROBE = 1024, 16
        -- v3 names: a same-name GetRenderTargetEx/CreateMaterial returns the first push's alpha-based objects.
        local RT_NAME, MAT_NAME, PROBE_NAME = "goobos_icons_v3", "goobos_icons_v3_add", "goobos_icons_v3_probe"
        local atlas, mat, cells, queue, queued, shelfX, shelfY, shelfH, full = nil, nil, {}, {}, {}, 0, 0, 0, false
        local verdict, diag = nil, "not run"

        function I.Enabled()
            if verdict == false then return false end
            local mode = modeVar:GetInt()
            if mode >= 2 then return true end
            if mode ~= 1 then return false end
            local ply = LocalPlayer()
            return IsValid(ply) and ply:SteamID64() == testerVar:GetString()
        end

        local function reset()
            cells, queue, queued, shelfX, shelfY, shelfH, full = {}, {}, {}, 0, 0, 0, false
            atlas, verdict, diag = nil, nil, "not run"
        end
        I.Reset = reset

        -- Undo DrawTexturedRectUV's own half-texel shift, which it derives from the material's mapping size (wiki).
        local function uv(x, y, w, h)
            local du, dv = 0.5 / mat:GetMappingWidth(), 0.5 / mat:GetMappingHeight()
            return (x / ATLAS - du) / (1 - 2 * du), (y / ATLAS - dv) / (1 - 2 * dv),
                ((x + w) / ATLAS - du) / (1 - 2 * du), ((y + h) / ATLAS - dv) / (1 - 2 * dv)
        end

        -- Opaque grey rects only: no blending, no alpha writes.
        local function bakeCell(x0, y0, size, cov)
            render.PushRenderTarget(atlas)
            cam.Start2D()
            for y = 0, size - 1 do
                for x = 0, size - 1 do
                    local v = floor(cov[y * size + x + 1] * 255 + 0.5)
                    if v > 0 then
                        surface.SetDrawColor(v, v, v, 255)
                        surface.DrawRect(x0 + x, y0 + y, 1, 1)
                    end
                end
            end
            cam.End2D()
            render.PopRenderTarget()
        end

        -- Probe: atlas cell (0,0) holds an 8x8 pattern, columns 0-2 white and 3-7 black. It is drawn with the
        -- icon material onto a mid-grey probe target at (4,4) and read back: white must stay white, and the
        -- black columns and the untouched border must both leave the grey alone.
        local function selfTest()
            local pattern = {}
            for y = 0, 7 do
                for x = 0, 7 do pattern[y * 8 + x + 1] = x < 3 and 1 or 0 end
            end
            bakeCell(0, 0, 8, pattern)
            local probe = GetRenderTargetEx(PROBE_NAME, PROBE, PROBE, RT_SIZE_NO_CHANGE, MATERIAL_RT_DEPTH_NONE, 0, 0, IMAGE_FORMAT_BGRA8888)
            if not probe then return false, "no probe target" end
            render.PushRenderTarget(probe)
            render.Clear(128, 128, 128, 255, true, true)
            cam.Start2D()
            surface.SetMaterial(mat)
            surface.SetDrawColor(255, 255, 255, 255)
            local u0, v0, u1, v1 = uv(0, 0, 8, 8)
            surface.DrawTexturedRectUV(4, 4, 8, 8, u0, v0, u1, v1)
            cam.End2D()
            render.CapturePixels()
            local white = render.ReadPixel(5, 8)
            local edge = render.ReadPixel(7, 8)
            local black = render.ReadPixel(9, 8)
            local outside = render.ReadPixel(1, 1)
            render.PopRenderTarget()
            local text = string.format("white=%s edge=%s black=%s outside=%s", tostring(white), tostring(edge), tostring(black), tostring(outside))
            local function near(v, lo, hi) return tonumber(v) ~= nil and v >= lo and v <= hi end
            return near(white, 235, 255) and near(black, 110, 146) and near(outside, 110, 146), text
        end

        local function ensureAtlas()
            if atlas then return true end
            atlas = GetRenderTargetEx(RT_NAME, ATLAS, ATLAS, RT_SIZE_NO_CHANGE, MATERIAL_RT_DEPTH_NONE, 0, 0, IMAGE_FORMAT_BGRA8888)
            if not atlas then return false end
            mat = CreateMaterial(MAT_NAME, "UnlitGeneric", {
                ["$basetexture"] = atlas:GetName(),
                ["$additive"] = "1",
                ["$vertexcolor"] = "1",
                ["$nolod"] = "1"
            })
            mat:SetTexture("$basetexture", atlas) -- same-name CreateMaterial returns the cached one (camera.lua)
            render.PushRenderTarget(atlas)
            render.Clear(0, 0, 0, 255, true, true)
            render.PopRenderTarget()
            shelfX, shelfY, shelfH = 10, 0, 10 -- cell (0,0) is the probe pattern
            local ok, pass, text = pcall(selfTest)
            verdict, diag = ok and pass or false, ok and text or ("error: " .. tostring(pass))
            if not verdict then
                MsgC(Color(255, 143, 159), "[GoobOS] icons v2 self-test failed, using legacy glyphs (" .. diag .. ")\n")
            end
            return true
        end

        local function bake(job)
            local cov = I.Coverage(job.name, job.size)
            if not cov then return false end
            local size = job.size
            if shelfX + size + 2 > ATLAS then shelfX, shelfY, shelfH = 0, shelfY + shelfH, 0 end
            if shelfY + size + 2 > ATLAS then
                full = true
                return false
            end
            local x0, y0 = shelfX + 1, shelfY + 1
            shelfX, shelfH = shelfX + size + 2, max(shelfH, size + 2)
            bakeCell(x0, y0, size, cov)
            return {x = x0, y = y0}
        end

        hook.Add("PostRender", "GoobOS.IconsV2Bake", function()
            if #queue == 0 or not ensureAtlas() or not verdict then return end
            local started = SysTime()
            while #queue > 0 and SysTime() - started < 0.002 do
                local job = table.remove(queue, 1)
                local ok, cell = pcall(bake, job)
                if not ok then ErrorNoHalt("[GoobOS] icon bake failed for " .. tostring(job.name) .. ": " .. tostring(cell) .. "\n") end
                cells[job.key] = ok and cell or false
                queued[job.key] = nil
            end
        end)
        hook.Add("OnScreenSizeChanged", "GoobOS.IconsV2Rebake", reset)
        concommand.Add("zc_goob_icons_rebake", reset)
        concommand.Add("zc_goob_icons_diag", function()
            print("[GoobOS] icons v2: enabled=" .. tostring(I.Enabled()) .. " verdict=" .. tostring(verdict) .. " " .. diag)
        end)

        -- Draw glyph name centred on (cx, cy) at size px. Returns true when drawn, nil when the legacy path
        -- should draw it this frame (disabled, unknown, still baking, atlas full, or a dark colour: additive
        -- drawing can only lighten, so near-black glyphs keep the legacy renderer).
        function I.Draw(name, cx, cy, size, color)
            if not I.Defs[name] or verdict == false then return nil end
            color = color or T.white
            local a = (color.a or 255) / 255
            local r, g, b = color.r * a, color.g * a, color.b * a
            if r * 0.3 + g * 0.59 + b * 0.11 < 48 then return nil end
            local s = floor(size + 0.5)
            if s < 6 or s > 96 then return nil end
            local key = name .. "@" .. s
            local cell = cells[key]
            if cell == nil then
                if not queued[key] and not full then
                    queued[key] = true
                    queue[#queue + 1] = {key = key, name = name, size = s}
                end
                return nil
            end
            if not cell or not mat or not verdict then return nil end
            local u0, v0, u1, v1 = uv(cell.x, cell.y, s, s)
            surface.SetMaterial(mat)
            surface.SetDrawColor(r, g, b, 255) -- premultiplied: additive ignores alpha
            surface.DrawTexturedRectUV(floor(cx - s / 2 + 0.5), floor(cy - s / 2 + 0.5), s, s, u0, v0, u1, v1)
            return true
        end
    end
end

-- Draw glyph `name` centred on (cx, cy) inside a size x size box, in `color`. Returns false if unknown.
function K.Glyph(name, cx, cy, size, color)
    local v2 = K.IconsV2
    if v2 and v2.Draw and v2.Enabled() and v2.Draw(name, cx, cy, size, color) then return true end
    local glyph = K.Glyphs[name] or (v2 and v2.Legacy[name] and K.Glyphs[v2.Legacy[name]])
    if not glyph then return false end
    local u = size / 24
    local ox, oy = math.floor(cx - size / 2), math.floor(cy - size / 2)
    surface.SetDrawColor(color or T.white)
    for _, cmd in ipairs(glyph) do
        local kind = cmd[1]
        if kind == "l" or kind == "c" then
            local count = #cmd
            for i = 2, count - 3, 2 do
                thickLine(ox + cmd[i] * u, oy + cmd[i + 1] * u, ox + cmd[i + 2] * u, oy + cmd[i + 3] * u)
            end
            if kind == "c" then thickLine(ox + cmd[count - 1] * u, oy + cmd[count] * u, ox + cmd[2] * u, oy + cmd[3] * u) end
        elseif kind == "r" then
            surface.DrawOutlinedRect(math.floor(ox + cmd[2] * u), math.floor(oy + cmd[3] * u), math.ceil(cmd[4] * u), math.ceil(cmd[5] * u), 2)
        elseif kind == "o" then
            local points, r = unitRing(), cmd[4] * u
            local px, py = ox + cmd[2] * u, oy + cmd[3] * u
            for i = 1, #points do
                local p, q = points[i], points[i % #points + 1]
                thickLine(px + p[1] * r, py + p[2] * r, px + q[1] * r, py + q[2] * r)
            end
        elseif kind == "d" then
            local r = math.max(1, math.floor(cmd[4] * u))
            surface.DrawRect(math.floor(ox + cmd[2] * u - r), math.floor(oy + cmd[3] * u - r), r * 2, r * 2)
        end
    end
    return true
end

-- App icon plate: main-red square, radius 4, faint top sheen, glyph (or the app's material) in white.
local sheen = Color(255, 255, 255, 16)
function K.Plate(x, y, size, glyph, material)
    draw.RoundedBox(4, x, y, size, size, T.main)
    draw.RoundedBoxEx(4, x, y, size, math.floor(size / 2), sheen, true, true, false, false)
    if not K.Glyph(glyph, x + size / 2, y + size / 2, math.floor(size * 0.46), T.white) and material then
        local icon = math.floor(size * 0.46)
        surface.SetMaterial(material)
        surface.SetDrawColor(255, 255, 255)
        surface.DrawTexturedRect(x + (size - icon) / 2, y + (size - icon) / 2, icon, icon)
    end
end

-- iOS notification card (tray now, push lane in Phase 3). entry = {app, glyph, title, body, time}.
-- Height is fixed at K.NoticeHeight so lists can lay out without measuring text.
K.NoticeHeight = 72
function K.Notice(x, y, w, entry, hover)
    K.Card(x, y, w, K.NoticeHeight, T.glassHi, K.Alpha(T.edge, 180))
    if hover and hover > 0.01 then draw.RoundedBox(4, x + 1, y + 1, w - 2, K.NoticeHeight - 2, K.Alpha(T.main, 40 * hover)) end
    draw.RoundedBox(4, x + 10, y + 9, 20, 20, T.main)
    if entry.initials then
        -- Messages from a person show their initial instead of the app glyph (mockup 09 variant c).
        draw.SimpleText(entry.initials, K.Font(12, 700), x + 20, y + 19, T.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    else
        K.Glyph(entry.glyph or "bell", x + 20, y + 19, 12, T.white)
    end
    local small = K.Font(11, 600)
    local timeWidth = 0
    if entry.time and entry.time ~= "" then
        surface.SetFont(small)
        timeWidth = surface.GetTextSize(entry.time) + 8
        draw.SimpleText(entry.time, small, x + w - 10, y + 19, T.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
    draw.SimpleText(K.Fit(string.upper(entry.app or ""), small, w - 50 - timeWidth), small, x + 36, y + 19, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    local title, body = K.Font(14, 600), K.Font(13, 500)
    draw.SimpleText(K.Fit(entry.title, title, w - 20), title, x + 10, y + 35, T.text)
    draw.SimpleText(K.Fit(entry.body, body, w - 20), body, x + 10, y + 52, T.muted)
end

-- Widgets ---------------------------------------------------------------------------------------

local function blankPaint() end

-- A plain container that paints nothing (DPanel paints the Derma skin background by default).
function K.Panel(parent)
    local p = vgui.Create("DPanel", parent)
    p.Paint = blankPaint
    return p
end

-- Grid: lays out `children` left-to-right in rows. Returns content height and column count.
function K.GridLayout(children, width, minTile, tileHeight, gapX, gapY, maxColumns)
    local columns = math.Clamp(math.floor((width + gapX) / (minTile + gapX)), 1, maxColumns or 99)
    local tile = math.floor((width - (columns - 1) * gapX) / columns)
    local index = 0
    for _, child in ipairs(children) do
        if IsValid(child) and child:IsVisible() then
            local col, row = index % columns, math.floor(index / columns)
            child:SetPos(col * (tile + gapX), row * (tileHeight + gapY))
            child:SetSize(tile, tileHeight)
            index = index + 1
        end
    end
    local rows = math.ceil(index / columns)
    return rows > 0 and rows * tileHeight + (rows - 1) * gapY or 0, columns
end

-- Grid panel: re-lays its children when its width or child count changes (Think, not PerformLayout:
-- nested Dock(FILL) invalidation does not always cascade), and sizes its own height to fit.
function K.Grid(parent, minTile, tileHeight, gapX, gapY, maxColumns)
    local grid = K.Panel(parent)
    grid.Think = function(s)
        local children = s:GetChildren()
        local signature = s:GetWide() .. ":" .. #children
        if signature == s.GoobLayout then return end
        s.GoobLayout = signature
        local height = K.GridLayout(children, s:GetWide(), minTile, tileHeight, gapX or 8, gapY or 8, maxColumns)
        if s:GetTall() ~= height then s:SetTall(height) end
    end
    return grid
end

-- Virtualised list: only the rows on screen exist. spec = {rowHeight, gap, count(), build(row), fill(row, index)}.
-- build runs once per pooled row; fill runs when a row shows a different index or after list:Refresh().
function K.List(parent, spec)
    local list = K.Panel(parent)
    list:SetMouseInputEnabled(true)
    local step = spec.rowHeight + (spec.gap or 6)
    list.Pool, list.Offset, list.Target = {}, 0, 0
    function list:Refresh() self.Dirty = true end
    function list:ScrollTo(index) self.Target = math.max(0, (index - 1) * step) end
    list.OnMouseWheeled = function(s, delta)
        s.Target = s.Target - delta * step
        return true
    end
    list.Think = function(s)
        local count, h, w = spec.count(), s:GetTall(), s:GetWide()
        local maxOffset = math.max(0, count * step - (spec.gap or 6) - h)
        s.Target = math.Clamp(s.Target, 0, maxOffset)
        s.Offset = K.Spring(s.Offset, s.Target, 16)
        s.MaxOffset = maxOffset
        local first = math.floor(s.Offset / step) + 1
        local visible = math.ceil(h / step) + 1
        for slot = #s.Pool + 1, visible do
            local row = K.Panel(s)
            spec.build(row)
            s.Pool[slot] = row
        end
        local rowWidth = maxOffset > 0 and w - 8 or w
        for slot, row in ipairs(s.Pool) do
            local index = first + slot - 1
            if slot <= visible and index <= count then
                row:SetVisible(true)
                row:SetPos(0, math.floor((index - 1) * step - s.Offset))
                if row:GetWide() ~= rowWidth or row:GetTall() ~= spec.rowHeight then row:SetSize(rowWidth, spec.rowHeight) end
                if row.GoobIndex ~= index or s.Dirty then
                    row.GoobIndex = index
                    spec.fill(row, index)
                end
            elseif row:IsVisible() then
                row:SetVisible(false)
                row.GoobIndex = nil
            end
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

-- Toggle switch (38 x 22). onChange(value).
function K.Toggle(parent, value, onChange)
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetSize(38, 22)
    b.Value = value and true or false
    b.Knob = b.Value and 1 or 0
    function b:SetValue(v) self.Value = v and true or false end
    b.DoClick = function(s)
        s.Value = not s.Value
        if onChange then onChange(s.Value) end
    end
    b.Paint = function(s, w, h)
        s.Knob = K.Spring(s.Knob, s.Value and 1 or 0, 18)
        draw.RoundedBox(h / 2, 0, 0, w, h, s.Value and T.main or K.Alpha(T.muted, 70))
        draw.RoundedBox(8, 3 + s.Knob * (w - 22), 3, 16, 16, s.Value and T.white or T.muted)
    end
    return b
end

-- Segmented control: options = {"All", "Owned", ...}; onChange(index, label).
function K.Segmented(parent, options, selected, onChange)
    local p = vgui.Create("DPanel", parent)
    p:SetTall(32)
    p.Selected = selected or 1
    p.Buttons = {}
    p.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.ink, 150)) end
    for index, label in ipairs(options) do
        local b = vgui.Create("DButton", p)
        b:SetText("")
        b.DoClick = function()
            p.Selected = index
            if onChange then onChange(index, label) end
        end
        b.Paint = function(s, w, h)
            local on = p.Selected == index
            local hover = K.Hover(s)
            if on then
                draw.RoundedBox(3, 0, 0, w, h, T.card)
                surface.SetDrawColor(T.main)
                surface.DrawRect(4, h - 2, w - 8, 2)
            elseif hover > 0.01 then
                draw.RoundedBox(3, 0, 0, w, h, K.Alpha(T.main, 40 * hover))
            end
            local font = K.Font(13, on and 600 or 500)
            draw.SimpleText(K.Fit(label, font, w - 8), font, w / 2, h / 2, on and T.text or T.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        p.Buttons[index] = b
    end
    p.PerformLayout = function(s, w, h)
        local count = #s.Buttons
        local each = (w - 4 - (count - 1) * 2) / count
        for index, b in ipairs(s.Buttons) do
            b:SetPos(math.floor(2 + (index - 1) * (each + 2)), 2)
            b:SetSize(math.floor(each), h - 4)
        end
    end
    return p
end

-- Tabs: text tabs with an accent underline; natural widths, wheel scrolls when they overflow.
function K.Tabs(parent, options, selected, onChange)
    local p = vgui.Create("DPanel", parent)
    p:SetTall(32)
    p:SetMouseInputEnabled(true)
    p.Selected, p.Buttons, p.Scroll = selected or 1, {}, 0
    p.Paint = function(_, w, h)
        surface.SetDrawColor(T.hair)
        surface.DrawRect(0, h - 1, w, 1)
    end
    local font = K.Font(14, 500)
    for index, label in ipairs(options) do
        local b = vgui.Create("DButton", p)
        b:SetText("")
        surface.SetFont(font)
        b.TextWidth = surface.GetTextSize(label)
        b.DoClick = function()
            p.Selected = index
            if onChange then onChange(index, label) end
        end
        b.Paint = function(s, w, h)
            local on = p.Selected == index
            local hover = K.Hover(s)
            draw.SimpleText(label, font, w / 2, h / 2 - 1, on and T.text or K.Alpha(T.muted, 200 + 55 * hover), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            if on then
                surface.SetDrawColor(T.accent)
                surface.DrawRect(0, h - 2, w, 2)
            end
        end
        p.Buttons[index] = b
    end
    p.OnMouseWheeled = function(s, delta)
        s.Scroll = math.Clamp(s.Scroll - delta * 40, 0, math.max(0, (s.ContentWidth or 0) - s:GetWide()))
        s:InvalidateLayout()
        return true
    end
    p.PerformLayout = function(s, _, h)
        local x = -s.Scroll
        for _, b in ipairs(s.Buttons) do
            b:SetPos(x, 0)
            b:SetSize(b.TextWidth + 4, h)
            x = x + b.TextWidth + 22
        end
        s.ContentWidth = x + s.Scroll - 18
    end
    return p
end

-- Animated bar (6 px): bar:SetFraction(f) eases toward f.
function K.Bar(parent, fraction, color)
    local p = vgui.Create("DPanel", parent)
    p:SetTall(6)
    p.Target, p.Shown, p.Color = math.Clamp(fraction or 0, 0, 1), 0, color
    function p:SetFraction(f) self.Target = math.Clamp(tonumber(f) or 0, 0, 1) end
    p.Paint = function(s, w, h)
        s.Shown = K.Spring(s.Shown, s.Target, 9)
        draw.RoundedBox(h / 2, 0, 0, w, h, K.Alpha(T.ink, 235))
        if s.Shown > 0.001 then draw.RoundedBox(h / 2, 0, 0, math.max(h, w * s.Shown), h, s.Color or T.main) end
    end
    return p
end

-- Avatar: one AvatarImage per widget, reused when the player changes (never recreated per frame).
-- ring = team/state colour or nil.
function K.Avatar(parent, size, ring)
    local p = vgui.Create("DPanel", parent)
    p:SetSize(size, size)
    p.Ring = ring
    local image = vgui.Create("AvatarImage", p)
    image:SetMouseInputEnabled(false)
    image:SetPos(2, 2)
    image:SetSize(size - 4, size - 4)
    p.Image = image
    function p:SetPlayer(ply)
        if self.Target == ply then return end
        self.Target = ply
        self.Bot = not IsValid(ply) or ply:IsBot()
        self.Image:SetVisible(not self.Bot)
        if not self.Bot then self.Image:SetPlayer(ply, size > 64 and 128 or 64) end
    end
    function p:SetSteamID(id64)
        if self.Target == id64 then return end
        self.Target, self.Bot = id64, false
        self.Image:SetVisible(true)
        self.Image:SetSteamID(id64, size > 64 and 184 or 64) -- SetSteamID sizes: 32, 64, 184
    end
    p.Paint = function(s, w, h)
        draw.RoundedBox(4, 0, 0, w, h, s.Ring or T.card)
        if s.Bot then draw.RoundedBox(3, 2, 2, w - 4, h - 4, T.bg) end
    end
    p.PerformLayout = function(s, w, h) s.Image:SetSize(w - 4, h - 4) end
    return p
end

-- Empty state: centred glyph, title, body and an optional action button.
function K.EmptyState(parent, glyph, title, body, actionLabel, action)
    local p = K.Panel(parent)
    p:Dock(FILL)
    p.Paint = function(_, w, h)
        local cy = h / 2 - (actionLabel and 36 or 20)
        K.Glyph(glyph or "empty", w / 2, cy - 22, 28, T.muted)
        K.Text(title, 16, 600, w / 2, cy + 4, T.text, TEXT_ALIGN_CENTER)
        if body then K.Text(K.Fit(body, K.Font(13, 500), w - 40), 13, 500, w / 2, cy + 28, T.muted, TEXT_ALIGN_CENTER) end
    end
    if actionLabel then
        local b = vgui.Create("DButton", p)
        b:SetText("")
        b:SetSize(180, 34)
        b.DoClick = action or blankPaint
        b.Paint = function(s, w, h)
            draw.RoundedBox(4, 0, 0, w, h, T.main)
            if K.Hover(s) > 0.01 then draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.white, 18 * s.GoobHover)) end
            K.Text(actionLabel, 14, 600, w / 2, h / 2, T.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        p.PerformLayout = function(_, w, h) b:SetPos((w - 180) / 2, h / 2 + 12) end
    end
    return p
end

-- Sheet: slides up from the bottom of `parent` over a dim shade; click the shade to dismiss.
-- Returns (sheet, shade). Put content in `sheet` (padded 12). shade:Close() removes both.
function K.Sheet(parent, height, dismissable)
    local shade = K.Panel(parent)
    shade:SetZPos(900)
    shade:SetPos(0, 0)
    shade:SetSize(parent:GetWide(), parent:GetTall())
    shade.Born = RealTime()
    shade:SetMouseInputEnabled(true)
    local sheet = K.Panel(shade)
    sheet:DockPadding(12, 12, 12, 12)
    function shade:Close() if IsValid(self) then self:Remove() end end
    shade.OnMousePressed = function(s)
        if dismissable ~= false then s:Close() end
    end
    shade.Paint = function(s, w, h)
        draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.ink, 150 * K.Ease(K.Progress(s.Born, 0.18))))
    end
    sheet.Paint = function(_, w, h)
        draw.RoundedBoxEx(4, 0, 0, w, h, T.glassHi, true, true, false, false)
        surface.SetDrawColor(K.Alpha(T.edge, 180))
        surface.DrawRect(0, 0, w, 1)
    end
    shade.Think = function(s)
        local pw, ph = parent:GetWide(), parent:GetTall()
        if s:GetWide() ~= pw or s:GetTall() ~= ph then s:SetSize(pw, ph) end
        local sh = math.min(height or math.floor(ph * 0.6), ph)
        if sheet:GetWide() ~= pw or sheet:GetTall() ~= sh then sheet:SetSize(pw, sh) end
        sheet:SetPos(0, math.floor(ph - sh * K.EaseOut(K.Progress(s.Born, 0.22))))
    end
    shade:Think()
    return sheet, shade
end

-- Modal: a Sheet with a title, a body (wrapped, up to 3 lines) and buttons =
-- {{label, action, primary = bool, danger = bool}}. Two buttons sit side by side (Cancel | action, as
-- in the mockups' confirm sheets); one or three+ stack.
function K.Modal(parent, title, body, buttons)
    local count = #(buttons or {})
    local bodyFont = K.Font(13, 500)
    local width = math.max(80, ((IsValid(parent) and parent:GetWide()) or 400) - 24)
    local lines = body and K.Wrap(body, bodyFont, width, 3) or {}
    local headH = 32 + #lines * 17
    local pair = count == 2
    local sheet, shade = K.Sheet(parent, headH + (pair and 42 or count * 42) + 32)
    local head = K.Panel(sheet)
    head:Dock(TOP)
    head:SetTall(headH)
    head.Paint = function(_, w)
        K.Text(K.Fit(title, K.Font(18, 700), w), 18, 700, 0, 2, T.text)
        for i, line in ipairs(lines) do draw.SimpleText(line, bodyFont, 0, 28 + (i - 1) * 17, T.muted) end
    end
    local pairButtons = {}
    if pair then
        sheet.PerformLayout = function(_, w)
            local each = math.floor((w - 24 - 8) / 2)
            for i, b in ipairs(pairButtons) do
                b:SetPos(12 + (i - 1) * (each + 8), 12 + headH + 2)
                b:SetSize(each, 36)
            end
        end
    end
    for _, spec in ipairs(buttons or {}) do
        local b = vgui.Create("DButton", sheet)
        b:SetText("")
        if pair then
            pairButtons[#pairButtons + 1] = b
        else
            b:Dock(TOP)
            b:DockMargin(0, 0, 0, 6)
        end
        b:SetTall(36)
        b.DoClick = function()
            shade:Close()
            if spec[2] then spec[2]() end
        end
        b.Paint = function(s, w, h)
            local hover = K.Hover(s)
            draw.RoundedBox(4, 0, 0, w, h, spec.primary and T.main or T.card)
            if hover > 0.01 then draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.white, 14 * hover)) end
            K.Text(spec[1], 15, 600, w / 2, h / 2, spec.danger and T.red or T.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    return sheet, shade
end
