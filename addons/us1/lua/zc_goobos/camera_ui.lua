if not CLIENT then return end
local A, C = ZCGoobApps, ZCGoobApps.Camera
local T = A.Theme
local K = A.Kit
local white = Color(252, 249, 249)
-- Hoisted: the viewfinder Paint used to allocate these every frame.
local VIEW_BG = Color(14, 11, 11)
local CHIP_BG = Color(14, 11, 11, 220)
local CORNER_SIDES = {-1, 1}
local FRAMING_SHADE = Color(0, 0, 0, 150)
local REC_RED = Color(226, 58, 52)

-- "● REC 0:07" chip centred on (x, y); shared by the in-app viewfinder and the framing HUD.
function C.PaintRec(x, y)
    local rec = C.rec
    if not rec then return end
    local elapsed = math.max(0, RealTime() - rec.started)
    local label = string.format("REC  %d:%02d / 0:%02d", math.floor(elapsed / 60), math.floor(elapsed % 60), C.VideoMaxSeconds)
    local font = K.Font(12, 700)
    surface.SetFont(font)
    local tw = surface.GetTextSize(label) + 34
    draw.RoundedBox(4, x - tw / 2, y - 11, tw, 22, CHIP_BG)
    if (RealTime() * 2) % 2 < 1.4 then draw.RoundedBox(4, x - tw / 2 + 9, y - 4, 8, 8, REC_RED) end
    K.Text(label, 12, 700, x - tw / 2 + 24, y, T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

-- Rail-vs-chip-strip breakpoint (mockups/07_camera.html: "labelled tool rail at >= 520 px body width;
-- stacked with a horizontal chip strip below 520 px"). Distinct from A.PREVIEW_STACK_BREAKPOINT (360,
-- preview.lua/shop.lua/wardrobe.lua) which stacks a different pair of columns for a different app.
local RAIL_BREAKPOINT = 520
local RAIL_WIDTH = 150

-- Swatch tints for the Filter rail (mockups/07_camera.html cam-swatch .sw gradients, midpoint colour).
-- Keyed by C.Filters[].name so an unknown/new filter degrades to a plain card tile instead of erroring.
local FILTER_SWATCH = {
    Natural = Color(107, 102, 96),
    Mono = Color(122, 122, 122),
    Warm = Color(138, 106, 58),
    Cool = Color(58, 106, 138)
}

-- Every clickable control Camera builds must disable native keyboard input and hand focus back to
-- root/fullscreen afterwards, or GMod's default DButton Space/Enter handling fights the Space/Tab/G/R
-- hotkey capture below (hook.Add("Think", "GoobOS.Camera.Keys", ...)). The live file only had to guard
-- one button flavour; this rework adds several more (stepper, chips, swatches, toggles), so the guard
-- is now a shared helper instead of being repeated inline.
local function refocus()
    local focus = IsValid(C.fullscreen) and C.fullscreen or C.root
    if IsValid(focus) and not IsValid(C.gallery) then focus:RequestFocus() end
end

local function noKeys(panel)
    panel:SetKeyboardInputEnabled(false)
    return panel
end

local function button(parent, text, click, color)
    local b = A.Button(parent, text, function()
        click()
        refocus()
    end, color)
    b:SetKeyboardInputEnabled(false)
    return b
end

local function caption(text, x, y, color, align)
    K.Text(text, 13, 500, x, y, color or white, align or TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

function C.FrameRect(w, h)
    local width = math.min(w, h * 16 / 9)
    local height = width * 9 / 16
    return (w - width) / 2, (h - height) / 2, width, height
end

-- kit candidate: Stepper -- a labelled "- value +" control (mockups/07_camera.html .cam-stepper /
-- .cam-zoom). Kept local per KIT_API.md (no kit.lua edits); flagged in the reply.
local function stepper(parent, textFn, onMinus, onPlus, width)
    local p = K.Panel(parent)
    p:SetTall(24)
    if width then p:SetWide(width) end
    p:SetMouseInputEnabled(true)
    p.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.ink, 140)) end
    local minus = noKeys(vgui.Create("DButton", p))
    minus:SetText("")
    minus.DoClick = function() onMinus(); refocus() end
    minus.Paint = function(s, w, h)
        if K.Hover(s) > 0.01 then draw.RoundedBox(3, 0, 0, w, h, K.Alpha(T.main, 45 * s.GoobHover)) end
        K.Text("-", 13, 700, w / 2, h / 2, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    local plus = noKeys(vgui.Create("DButton", p))
    plus:SetText("")
    plus.DoClick = function() onPlus(); refocus() end
    plus.Paint = function(s, w, h)
        if K.Hover(s) > 0.01 then draw.RoundedBox(3, 0, 0, w, h, K.Alpha(T.main, 45 * s.GoobHover)) end
        K.Text("+", 13, 700, w / 2, h / 2, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    local label = K.Panel(p)
    label.Paint = function(_, w, h) K.Text(textFn(), 12, 600, w / 2, h / 2, T.accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
    p.PerformLayout = function(_, w, h)
        minus:SetPos(0, 0); minus:SetSize(24, h)
        plus:SetPos(w - 24, 0); plus:SetSize(24, h)
        label:SetPos(24, 0); label:SetSize(math.max(0, w - 48), h)
    end
    return p
end

-- A compact rounded pill toggled by a single click, used for the < 520 px control strip
-- (mockups/07_camera.html .cam-chipflat). Not a kit addition: it is a plain styled DButton.
local function chip(parent, textFn, onFn, onFn2)
    local b = noKeys(vgui.Create("DButton", parent))
    b:SetText("")
    b.DoClick = function() onFn(); refocus() end
    b.Paint = function(s, w, h)
        local on = onFn2 and onFn2()
        local hover = K.Hover(s)
        draw.RoundedBox(h / 2, 0, 0, w, h, on and K.Alpha(T.main, 70) or K.Alpha(T.ink, 140))
        if hover > 0.01 then draw.RoundedBox(h / 2, 0, 0, w, h, K.Alpha(T.white, 14 * hover)) end
        K.Text(K.Fit(textFn(), K.Font(11, 600), w - 12), 11, 600, w / 2, h / 2, on and T.text or T.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    return b
end

local function viewfinder(parent)
    local p = vgui.Create("DPanel", parent)
    p:SetCursor("crosshair")
    p:SetKeyboardInputEnabled(true)
    p.Paint = function(_, w, h)
        draw.RoundedBox(0, 0, 0, w, h, VIEW_BG)
        local reason = C.Blocked() or C.problem
        local x, y, fw, fh = C.FrameRect(w, h)
        if C.material and C.previewTarget and C.FrameLive() and not reason then
            surface.SetMaterial(C.material)
            surface.SetDrawColor(255, 255, 255)
            surface.DrawTexturedRectUV(x, y, fw, fh, 0, 0, (C.frameW or C.PreviewWidth) / C.previewTarget:Width(), (C.frameH or C.PreviewHeight) / C.previewTarget:Height())
            if C.grid and not C.hideHud then
                surface.SetDrawColor(255, 255, 255, 55)
                for i = 1, 2 do
                    surface.DrawLine(x + fw * i / 3, y, x + fw * i / 3, y + fh)
                    surface.DrawLine(x, y + fh * i / 3, x + fw, y + fh * i / 3)
                end
            end
            if not C.hideHud then
                -- Small focus corners belong to the UI, never the saved JPEG.
                local cx, cy, arm = x + fw / 2, y + fh / 2, 12
                surface.SetDrawColor(255, 255, 255, 170)
                for _, direction in ipairs(CORNER_SIDES) do
                    surface.DrawLine(cx + direction * 22, cy - 22, cx + direction * (22 - arm), cy - 22)
                    surface.DrawLine(cx + direction * 22, cy + 22, cx + direction * (22 - arm), cy + 22)
                    surface.DrawLine(cx + direction * 22, cy - 22, cx + direction * 22, cy - 22 + arm)
                    surface.DrawLine(cx + direction * 22, cy + 22, cx + direction * 22, cy + 22 - arm)
                end
            end
        else
            caption(reason or "Opening camera…", w / 2, h / 2, T.muted, TEXT_ALIGN_CENTER)
        end
        if not C.hideHud then
            local mode = IsValid(LocalPlayer()) and not LocalPlayer():Alive() and "SPECTATOR" or (C.mode == "selfie" and "SELFIE" or "FRONT")
            draw.RoundedBox(3, 8, 8, 96, 24, CHIP_BG)
            caption(mode, 16, 20)
            draw.RoundedBox(3, w - 62, 8, 54, 24, CHIP_BG)
            caption(string.format("%.1f×", C.zoom), w - 35, 20, T.accent, TEXT_ALIGN_CENTER)
        end
        if C.freeze then
            local label = K.Font(11, 700)
            surface.SetFont(label)
            local lw = surface.GetTextSize("PHOTO MODE") + 20
            draw.RoundedBox(3, w / 2 - lw / 2, 8, lw, 22, K.Alpha(T.main, 200))
            K.Text("PHOTO MODE", 11, 700, w / 2, 19, T.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        if C.deadline then
            draw.SimpleText(math.max(1, math.ceil(C.deadline - RealTime())), "GoobMetric", w / 2, h / 2, white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        if C.rec then C.PaintRec(w / 2, 20) end
        if C.framing then
            draw.RoundedBox(0, 0, 0, w, h, FRAMING_SHADE)
            caption("Framing · aim with your mouse · RMB or Tab for the cursor", w / 2, h / 2, T.text, TEXT_ALIGN_CENTER)
        end
        if C.flash and RealTime() - C.flash < 0.18 then
            surface.SetDrawColor(255, 255, 255, 100 * (1 - (RealTime() - C.flash) / 0.18))
            surface.DrawRect(x, y, fw, fh)
        end
    end
    p.OnMouseWheeled = function(_, delta) C.Zoom(delta); return true end
    p.OnMousePressed = function(s, button)
        s:RequestFocus()
        if button == MOUSE_LEFT then s.shutterDown = true end
        if button == MOUSE_RIGHT then
            s.dragging = true
            s.lastX, s.lastY = gui.MousePos()
            s:MouseCapture(true)
            s:SetCursor("sizeall")
        end
    end
    p.OnCursorMoved = function(s)
        if not s.dragging then return end
        local x, y = gui.MousePos()
        C.Pan(x - s.lastX, y - s.lastY)
        s.lastX, s.lastY = x, y
    end
    p.OnMouseReleased = function(s, button)
        if button == MOUSE_LEFT then
            local clicked = s.shutterDown; s.shutterDown = false
            if clicked then C.Trigger() end
            return
        end
        if button ~= MOUSE_RIGHT then return end
        s.dragging = false; s:MouseCapture(false); s:SetCursor("crosshair")
    end
    p.OnRemove = function(s) s:MouseCapture(false) end
    -- Framing entry (testers): its own child button, so it never doubles as a shutter click.
    local frame = noKeys(vgui.Create("DButton", p))
    frame:SetText("")
    frame.DoClick = function() C.EnterFraming() end
    frame.Paint = function(s, w, h)
        draw.RoundedBox(h / 2, 0, 0, w, h, CHIP_BG)
        if K.Hover(s) > 0.01 then draw.RoundedBox(h / 2, 0, 0, w, h, K.Alpha(T.white, 22 * s.GoobHover)) end
        K.Text("Frame shot  ·  Tab", 11, 600, w / 2, h / 2, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    frame:SetTooltip("Hand mouse and movement back to the game and aim with a live viewfinder")
    frame.Think = function(s)
        local show = C.Tester() and not C.framing and not C.freeze and not C.hideHud
        if s:IsVisible() ~= show then s:SetVisible(show) end
        local pw, ph = p:GetWide(), p:GetTall()
        if s.GoobW ~= pw or s.GoobH ~= ph then
            s.GoobW, s.GoobH = pw, ph
            s:SetSize(132, 24); s:SetPos(pw / 2 - 66, ph - 34)
        end
    end
    return p
end

local function flip() C.Flip() end

-- Bottom bar: last-photo thumbnail -> gallery, 64 px shutter, flip, zoom stepper.
local function bottomBar(parent, onGallery)
    local bar = K.Panel(parent)
    bar:SetTall(76)

    local thumb = noKeys(vgui.Create("DButton", bar))
    thumb:SetText("")
    thumb.DoClick = function() onGallery() end
    thumb.Paint = function(s, w, h)
        K.Card(0, 0, w, h, T.card, K.Alpha(T.edge, 160))
        if s.Material then
            surface.SetMaterial(s.Material)
            surface.SetDrawColor(255, 255, 255)
            surface.DrawTexturedRect(2, 2, w - 4, h - 4)
        else
            K.Glyph("camera", w / 2, h / 2, 16, T.muted)
        end
    end
    -- Last photo as its small thumbnail (camera.lua C.Thumb), never the full-size photo texture.
    if not C.lastPhoto and C.Photos then
        local photos = C.Photos()
        C.lastPhoto = photos[1] and photos[1].name or nil
    end
    thumb.Think = function(s)
        local kind = C.lastKind == "clip" and C.lastClip and "clip" or "photo"
        local key = kind .. ":" .. tostring(kind == "clip" and C.lastClip or C.lastPhoto)
        if s.LastKey == key and s.ThumbRevision == C.thumbRevision and s.Material then return end
        s.LastKey, s.ThumbRevision = key, C.thumbRevision
        if kind == "clip" then s.Material = C.ClipThumb(C.lastClip)
        else s.Material = C.lastPhoto and C.Thumb and C.Thumb(C.lastPhoto) or nil end
    end

    local shot = button(bar, "", function() C.Trigger() end, T.accent)
    shot:Dock(NODOCK)
    shot.Paint = function(s, w, h)
        draw.RoundedBox(h / 2, 0, 0, w, h, s:IsHovered() and T.hover or T.card)
        draw.RoundedBox(h / 2, 3, 3, w - 6, h - 6, T.text)
        if C.captureMode ~= "video" then
            draw.RoundedBox(h / 2 - 4, 7, 7, w - 14, h - 14, T.accent)
        elseif C.rec then
            draw.RoundedBox(4, w / 2 - 12, h / 2 - 12, 24, 24, REC_RED) -- stop
        else
            draw.RoundedBox(h / 2 - 4, 7, 7, w - 14, h - 14, REC_RED) -- record
        end
    end
    shot:SetTooltip("Take photo · Space · or click the viewfinder")

    local flipBtn = noKeys(vgui.Create("DButton", bar))
    flipBtn:SetText("")
    flipBtn.DoClick = function()
        flip()
        refocus()
    end
    flipBtn.Paint = function(s, w, h)
        draw.RoundedBox(h / 2, 0, 0, w, h, s:IsHovered() and T.hover or T.card)
        K.Text(C.mode == "selfie" and "Front" or "Self", 10, 600, w / 2, h / 2, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    flipBtn:SetTooltip("Front / selfie · Tab")
    flipBtn.Think = function(s) s:SetEnabled(IsValid(LocalPlayer()) and LocalPlayer():Alive()) end

    local zoom = stepper(bar, function() return string.format("%.1f×", C.zoom) end, function() C.Zoom(-1) end, function() C.Zoom(1) end, 96)

    local modeBtn = chip(bar, function()
        if C.rec then return "Recording" end
        return C.captureMode == "video" and "Video  ·  R" or "Photo  ·  R"
    end, function() C.ToggleCaptureMode() end, function() return C.captureMode == "video" end)
    modeBtn:SetTooltip("Switch between photos and video clips · R")
    modeBtn.Think = function(s)
        local show = C.Tester()
        if s:IsVisible() ~= show then s:SetVisible(show) end
    end

    bar.PerformLayout = function(_, w, h)
        thumb:SetPos(0, h / 2 - 17); thumb:SetSize(34, 34)
        modeBtn:SetPos(42, h / 2 - 13); modeBtn:SetSize(math.max(60, math.min(96, w / 2 - 32 - 50)), 26)
        shot:SetPos(w / 2 - 32, h / 2 - 32); shot:SetSize(64, 64)
        flipBtn:SetPos(w - 34, h / 2 - 17); flipBtn:SetSize(34, 34)
        zoom:SetPos(w - 34 - 8 - 96, h / 2 - 12)
    end
    shot.Think = function(s)
        s:SetEnabled((C.rec ~= nil) or (not C.Blocked() and C.FrameLive() and not C.pending))
        if not C.Tester() then
            s:SetTooltip(C.deadline and "Cancel countdown · Space" or "Take photo · Space · click viewfinder")
        elseif C.captureMode == "video" then
            s:SetTooltip(C.rec and "Stop recording · click viewfinder" or "Record a clip (up to 20 s) · click viewfinder")
        else
            s:SetTooltip(C.deadline and "Cancel countdown" or "Take photo · click viewfinder")
        end
    end
    return bar
end

-- Labelled tool rail (>= RAIL_BREAKPOINT px). Positions are computed once per height change
-- (KIT_API.md layout rule: multi-column/-row layouts poll from Think, not PerformLayout).
local function rail(parent)
    local p = K.Panel(parent)
    p:SetWide(RAIL_WIDTH)

    local filterHead = K.Panel(p)
    filterHead.Paint = function(_, w) K.Text("FILTER", 10, 700, 0, 0, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP) end
    local swatches = {}
    for index, f in ipairs(C.Filters) do
        local b = noKeys(vgui.Create("DButton", p))
        b:SetText("")
        b.DoClick = function() C.Cancel(); C.filter = index; refocus() end
        b.Paint = function(s, w, h)
            local on = C.filter == index
            local sw = h - 13
            draw.RoundedBox(3, 0, 0, w, sw, FILTER_SWATCH[f.name] or T.card)
            if on then
                surface.SetDrawColor(T.main)
                surface.DrawOutlinedRect(0, 0, w, sw, 2)
            elseif K.Hover(s) > 0.01 then
                draw.RoundedBox(3, 0, 0, w, sw, K.Alpha(T.white, 20 * s.GoobHover))
            end
            K.Text(K.Fit(f.name, K.Font(9, 500), w), 9, 500, w / 2, sw + 5, T.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
        swatches[index] = b
    end

    local timerHead = K.Panel(p)
    timerHead.Paint = function(_, w) K.Text("TIMER", 10, 700, 0, 0, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP) end
    local timerSeg = K.Segmented(p, {"Off", "3s", "10s"}, C.delay == 3 and 2 or (C.delay == 10 and 3 or 1), function(index)
        C.Cancel(); C.delay = index == 2 and 3 or (index == 3 and 10 or 0)
        refocus()
    end)
    for _, b in ipairs(timerSeg.Buttons) do noKeys(b) end

    local exposure = stepper(p, function() return string.format("%+.2f", C.exposure) end, function()
        C.Cancel(); C.exposure = math.Clamp(C.exposure - 0.04, -0.24, 0.24)
    end, function()
        C.Cancel(); C.exposure = math.Clamp(C.exposure + 0.04, -0.24, 0.24)
    end)
    local exposureLabel = K.Panel(p)
    exposureLabel.Paint = function(_, w, h) K.Text("EXPOSURE", 10, 700, 0, h / 2, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end

    local function toggleRow(label, get, set)
        local row = K.Panel(p)
        local text = K.Panel(row)
        text.Paint = function(_, w, h) K.Text(label, 13, 500, 0, h / 2, T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
        local toggle = noKeys(K.Toggle(row, get(), function(v) set(v); refocus() end))
        row.PerformLayout = function(_, w, h)
            text:SetPos(0, 0); text:SetSize(w - 38, h)
            toggle:SetPos(w - 38, h / 2 - 11)
        end
        row.Think = function() toggle:SetValue(get()) end
        return row
    end
    local gridRow = toggleRow("Grid", function() return C.grid end, function(v) C.grid = v end)
    local hideHudRow = toggleRow("Hide HUD", function() return C.hideHud end, function(v) C.hideHud = v end)
    -- C3 (freeze/"photo mode"): the mockup shows the resulting PHOTO MODE chip but not a source
    -- control for it (07_camera.html notes: "no such chip exists in source today"); this toggle is
    -- the control chosen to drive it. Logged per CLAUDE.md scope-discipline: spec-uncovered choice.
    local freezeRow = toggleRow("Photo mode", function() return C.freeze end, function(v) C.freeze = v end)

    p.Think = function(s)
        local w, h = s:GetWide(), s:GetTall()
        if w == s.GoobW and h == s.GoobH then return end
        s.GoobW, s.GoobH = w, h
        local swatchW = math.floor((w - 3 * 5) / 4)
        local y = 0
        filterHead:SetPos(0, y); filterHead:SetSize(w, 14); y = y + 16
        for index, b in ipairs(swatches) do b:SetPos((index - 1) * (swatchW + 5), y); b:SetSize(swatchW, 44) end
        y = y + 44 + 10
        timerHead:SetPos(0, y); timerHead:SetSize(w, 14); y = y + 16
        timerSeg:SetPos(0, y); timerSeg:SetSize(w, 30); y = y + 30 + 10
        exposureLabel:SetPos(0, y); exposureLabel:SetSize(70, 24)
        exposure:SetPos(70, y); exposure:SetSize(w - 70, 24); y = y + 24 + 8
        gridRow:SetPos(0, y); gridRow:SetSize(w, 22); y = y + 22 + 6
        hideHudRow:SetPos(0, y); hideHudRow:SetSize(w, 22); y = y + 22 + 6
        freezeRow:SetPos(0, y); freezeRow:SetSize(w, 22); y = y + 22
        s:SetTall(y)
    end
    return p
end

-- Horizontal (wrapping) control strip below RAIL_BREAKPOINT. Chips wrap onto more than one row via
-- K.GridLayout (called from surfaceLayout, the single layout authority for this panel -- see its
-- comment) rather than scrolling: every control stays reachable without inventing a horizontal-scroll
-- widget (07_camera.html's single-row strip with overflow:hidden is a static mockup, not a runtime
-- constraint). Returns the strip panel with its chip buttons on .Chips for surfaceLayout to lay out.
local function chipStrip(parent)
    local grid = K.Panel(parent)
    local chips = {}
    local function add(...) chips[#chips + 1] = chip(grid, ...) end
    for index, f in ipairs(C.Filters) do
        add(function() return f.name end, function() C.Cancel(); C.filter = index end, function() return C.filter == index end)
    end
    add(function() return C.delay == 0 and "Timer off" or "Timer " .. C.delay .. "s" end, function()
        C.Cancel(); C.delay = C.delay == 0 and 3 or (C.delay == 3 and 10 or 0)
    end, function() return C.delay ~= 0 end)
    add(function() return string.format("Exp %+.2f", C.exposure) end, function()
        C.Cancel(); C.exposure = C.exposure == 0 and 0.08 or C.exposure > 0 and -0.08 or 0
    end, function() return C.exposure ~= 0 end)
    add(function() return C.grid and "Grid on" or "Grid off" end, function() C.grid = not C.grid end, function() return C.grid end)
    add(function() return "Hide HUD" end, function() C.hideHud = not C.hideHud end, function() return C.hideHud end)
    add(function() return "Photo mode" end, function() C.freeze = not C.freeze end, function() return C.freeze end)
    grid.Chips = chips
    return grid
end

-- Shared responsive surface: viewfinder + rail (>= RAIL_BREAKPOINT px body width) or viewfinder +
-- wrapping chip strip (below), one-line key hint, bottom bar. Used by both the phone-body build() and
-- Fullscreen(). Both `rail` and `strip` are built up front and toggled with SetVisible rather than
-- created on demand, so only one panel (this Think) ever positions them -- K.Grid's own self-sizing
-- Think would otherwise race this one for the strip's height (KIT_API.md layout rule).
-- Returns a layout(w, h) function rather than assigning `parent.Think` itself: build() also needs
-- its own Think on the same panel (to size it from its docked width -- see the "stage" panel below),
-- and a second direct assignment to `.Think` would silently clobber the first instead of composing.
local function surfaceLayout(view, railPanel, stripPanel, hint, bar)
    local lastW, lastH
    return function(w, h)
        if w == lastW and h == lastH then return end
        lastW, lastH = w, h
        local barH, hintH = 76, 16
        if w >= RAIL_BREAKPOINT then
            local contentH = math.max(60, h - barH - hintH - 8)
            local railW = RAIL_WIDTH
            view:SetPos(0, 0); view:SetSize(math.max(1, w - railW - 8), contentH)
            railPanel:SetPos(w - railW, 0); railPanel:SetSize(railW, contentH)
            railPanel:SetVisible(true); stripPanel:SetVisible(false)
            hint:SetPos(0, contentH + 4); hint:SetSize(w, hintH)
        else
            local stripH = K.GridLayout(stripPanel.Chips, w, 74, 26, 6, 6, 99)
            local viewH = math.max(60, h - barH - hintH - stripH - 8 - 6)
            view:SetPos(0, 0); view:SetSize(w, viewH)
            stripPanel:SetPos(0, viewH + 6); stripPanel:SetSize(w, stripH)
            railPanel:SetVisible(false); stripPanel:SetVisible(true)
            hint:SetPos(0, viewH + 6 + stripH + 4); hint:SetSize(w, hintH)
        end
        bar:SetPos(0, h - barH); bar:SetSize(w, barH)
    end
end

function C.Gallery(parent)
    C.Cancel()
    if IsValid(C.gallery) then return end
    local sheet, shade = K.Sheet(parent, parent:GetTall(), false)
    -- K.Sheet returns a (content, backdrop) pair, unlike the old A.Sheet() single panel this replaces.
    -- C.gallery must track `shade`: HandleKey's Esc path and C.Shutter's guard both do
    -- IsValid(C.gallery) / C.gallery:Remove() expecting ONE call to fully close the overlay. Tracking
    -- `sheet` instead would remove only the content and strand the non-dismissable dark backdrop
    -- on screen with no way to close it (dismissable=false below; the Back button lives in `sheet`).
    C.gallery = shade
    shade.OnRemove = function() C.gallery = nil; C.validFrame = nil end

    local head = K.Panel(sheet)
    head:Dock(TOP)
    head:SetTall(58)
    button(head, "‹  Back to Camera", function() shade:Close() end, T.accent):Dock(TOP)
    A.Status(head, "Saved on this computer · 1920 × 1080 JPEG")

    local scroll = A.Scroll(sheet)
    local function openDetail(photo)
        local reallyDelete = function()
            if C.Delete(photo.name) then C.rebuildGallery() else C.Note("Photo could not be deleted.") end
        end
        local function deletePrompt()
            K.Modal(sheet, "Delete this photo?", "This removes the saved photo from this computer.", {
                {"Delete", reallyDelete, danger = true},
                {"Cancel"}
            })
        end
        local function post()
            local feed = ZCGoobFeed and ZCGoobFeed.Client
            if feed and feed.ComposePhoto then feed.ComposePhoto(photo.name) else C.Note("CityLeak is not available yet.") end
        end
        local function copyLocation()
            SetClipboardText("garrysmod/data/" .. C.Directory .. "/" .. photo.name)
            C.Note("Photo location copied.")
        end
        local function openFullscreen()
            local media = ZCGoobApps.Media
            if not (media and media.Open) then C.Note("Media viewer is not available yet."); return end
            -- The viewer's action row (was empty): each action closes the viewer first, so the confirm
            -- dialog / CityLeak composer opens in the phone underneath instead of behind the popup.
            local function closeThen(fn) return function() if media.Close then media.Close() end; fn() end end
            media.Open({
                kind = "photo", path = C.Directory .. "/" .. photo.name,
                title = os.date("%b %d · %H:%M:%S", photo.time),
                author = (IsValid(LocalPlayer()) and LocalPlayer().Nick and LocalPlayer():Nick()) or "You",
                time = os.date("%H:%M", photo.time),
                actions = {
                    {label = "Delete", fn = closeThen(deletePrompt), danger = true},
                    {label = "Post to CityLeak", fn = closeThen(post)},
                    {label = "Close", fn = function() if media.Close then media.Close() end end}
                }
            })
        end
        K.Modal(sheet, os.date("%b %d · %H:%M:%S", photo.time), photo.name, {
            {"Post to CityLeak", post},
            {"Copy photo location", copyLocation},
            {"Open fullscreen", openFullscreen},
            {"Delete photo", deletePrompt, danger = true}
        })
    end

    local function openClip(clip)
        local media = ZCGoobApps.Media
        local function remove()
            K.Modal(sheet, "Delete this clip?", "This removes the saved clip from this computer.", {
                {"Delete", function()
                    if C.DeleteClip(clip.id) then C.rebuildGallery() else C.Note("Clip could not be deleted.") end
                end, danger = true},
                {"Cancel"}
            })
        end
        local function play()
            if not (media and media.Open) then C.Note("Media viewer is not available yet."); return end
            media.Open({
                kind = "video", path = C.ClipPath(clip.id), duration = clip.duration,
                title = os.date("%b %d · %H:%M:%S", clip.time),
                author = (IsValid(LocalPlayer()) and LocalPlayer().Nick and LocalPlayer():Nick()) or "You",
                time = os.date("%H:%M", clip.time),
                actions = {
                    {label = "Delete", fn = function() media.Close(); remove() end, danger = true},
                    {label = "Close", fn = function() media.Close() end}
                }
            })
        end
        K.Modal(sheet, os.date("%b %d · %H:%M:%S", clip.time), string.format("Video clip · %.1f s · saved on this computer", clip.duration or 0), {
            {"Play", play},
            {"Delete clip", remove, danger = true}
        })
    end

    -- kit candidate: a fixed-column, aspect-locked Grid (K.Grid picks its own column count from
    -- minTile; this keeps exactly 3 columns and 16:9 tiles, matching the gallery mockup).
    local function photoGrid(host, columns, aspect, gap)
        local grid = K.Panel(host)
        grid:Dock(TOP)
        grid.Tiles = {}
        grid.Think = function(s)
            local w = s:GetWide()
            if w <= 0 then return end
            local tileW = math.floor((w - (columns - 1) * gap) / columns)
            local tileH = math.floor(tileW * aspect)
            local signature = w .. ":" .. #s.Tiles
            if signature ~= s.GoobLayout then
                s.GoobLayout = signature
                for i, tile in ipairs(s.Tiles) do
                    local col, row = (i - 1) % columns, math.floor((i - 1) / columns)
                    tile:SetPos(col * (tileW + gap), row * (tileH + gap))
                    tile:SetSize(tileW, tileH)
                end
                local rows = math.ceil(#s.Tiles / columns)
                s:SetTall(rows > 0 and rows * tileH + (rows - 1) * gap or 0)
            end
        end
        function grid:AddTile(photo)
            local tile = noKeys(vgui.Create("DButton", self))
            tile:SetText("")
            local clip = photo.kind == "video"
            tile.DoClick = function() if clip then openClip(photo) else openDetail(photo) end end
            local stamp = os.date("%H:%M", photo.time)
            tile.Paint = function(s, w, h)
                K.Card(0, 0, w, h, T.card)
                -- Thumbnail (mockup 07 gallery); a camera glyph while it is generated or if it cannot be.
                local thumb
                if clip then thumb = C.ClipThumb(photo.id) else thumb = C.Thumb and C.Thumb(photo.name) end
                if thumb then
                    surface.SetMaterial(thumb)
                    surface.SetDrawColor(255, 255, 255, 255)
                    surface.DrawTexturedRect(1, 1, w - 2, h - 2)
                else
                    K.Glyph("camera", w / 2, h / 2 - 4, 16, K.Alpha(T.muted, 130))
                end
                if K.Hover(s) > 0.01 then draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.white, 16 * s.GoobHover)) end
                draw.RoundedBox(3, 4, h - 19, 38, 15, CHIP_BG)
                K.Text(stamp, 10, 600, 23, h - 11, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                if clip then
                    -- Play badge + length, so a clip reads as a clip at a glance.
                    local r = math.min(16, h / 4)
                    draw.RoundedBox(r, w / 2 - r, h / 2 - r, r * 2, r * 2, CHIP_BG)
                    K.Glyph("play", w / 2 + 1, h / 2, r, T.text)
                    draw.RoundedBox(3, w - 42, h - 19, 38, 15, CHIP_BG)
                    K.Text(string.format("%d:%02d", math.floor((photo.duration or 0) / 60), math.floor((photo.duration or 0) % 60)), 10, 600, w - 23, h - 11, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
            end
            self.Tiles[#self.Tiles + 1] = tile
            self.GoobLayout = nil
            return tile
        end
        return grid
    end

    local function dayLabel(time)
        local today, ts = os.date("*t"), os.date("*t", time)
        local function midnight(t) return os.time({year = t.year, month = t.month, day = t.day, hour = 0}) end
        local delta = math.floor((midnight(today) - midnight(ts)) / 86400)
        if delta == 0 then return "Today" end
        if delta == 1 then return "Yesterday" end
        return os.date("%b %d", time)
    end

    function C.rebuildGallery()
        if not IsValid(scroll) then return end
        scroll:Clear()
        local photos = C.Photos()
        -- Clips join the same day-grouped grid (newest first). Only testers can record, so for everyone
        -- else this list is empty and the gallery is unchanged.
        local clips = C.Videos and C.Videos() or {}
        if #clips > 0 then
            for _, clip in ipairs(clips) do photos[#photos + 1] = clip end
            table.sort(photos, function(a, b)
                if a.time == b.time then return (a.name or a.id) > (b.name or b.id) end
                return a.time > b.time
            end)
        end
        if #photos == 0 then
            K.EmptyState(scroll, "camera", "No photos yet", "Your first photo belongs here. Take one with the shutter.")
            return
        end
        local currentDay, currentGrid
        for _, photo in ipairs(photos) do
            local label = dayLabel(photo.time)
            if label ~= currentDay then
                currentDay = label
                local dayHead = K.Panel(scroll)
                dayHead:Dock(TOP)
                dayHead:SetTall(22)
                dayHead:DockMargin(0, 10, 0, 4)
                dayHead.Paint = function(_, w, h) K.Text(string.upper(label), 10, 700, 0, h / 2, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
                currentGrid = photoGrid(scroll, 3, 9 / 16, 8)
                currentGrid:DockMargin(0, 0, 8, 0)
            end
            currentGrid:AddTile(photo)
        end
    end
    C.rebuildGallery()
end

function C.Fullscreen()
    if IsValid(C.fullscreen) or not C.Active() then return end
    local p = vgui.Create("DPanel")
    C.fullscreen = p
    p:SetSize(ScrW(), ScrH()); p:SetPos(0, 0)
    p:SetZPos(32700); p:MakePopup()
    p.Paint = function(_, w, h)
        draw.RoundedBox(0, 0, 0, w, h, T.bg)
        if C.message and RealTime() < (C.messageUntil or 0) then caption(C.message, w / 2, h - 18, T.accent, TEXT_ALIGN_CENTER) end
    end
    local close = function() if IsValid(p) then p:Remove() end end
    local host = K.Panel(p)
    host:DockMargin(20, 58, 20, 20)
    host:Dock(FILL)
    local view = viewfinder(host)
    local railPanel = rail(host)
    local stripPanel = chipStrip(host)
    local hint = A.Label(host, "", "GoobSmall", T.muted)
    local bar = bottomBar(host, function() C.Gallery(p) end)
    for _, w in ipairs({view, railPanel, stripPanel, hint, bar}) do w:Dock(NODOCK) end
    local layout = surfaceLayout(view, railPanel, stripPanel, hint, bar)
    host.Think = function(s) layout(s:GetWide(), s:GetTall()) end
    local back = button(p, "‹  Phone", close)
    back:Dock(NODOCK)
    p.PerformLayout = function(_, w, h)
        back:SetPos(20, 12); back:SetSize(100, 34)
    end
    p.Think = function(s)
        if not C.Active() or C.ReplayActive() then close(); return end
        if s:GetWide() ~= ScrW() or s:GetTall() ~= ScrH() then s:SetSize(ScrW(), ScrH()) end
        hint:SetText(C.KeyHint())
    end
    p.OnRemove = function()
        C.fullscreen = nil; C.Cancel()
        if IsValid(C.gallery) then C.gallery:Remove() end
        if IsValid(C.root) then C.root:RequestFocus() end
    end
end

-- One-line key hint for the app surfaces. Testers get the framing keymap, which mirrors framing mode:
-- Tab toggles framing, F flips, R switches Photo/Video, click shoots, wheel zooms (Space is jump there).
function C.KeyHint()
    if C.Tester() then
        return C.CanPan() and "Tab: frame shot · Click: shoot · Wheel: zoom · F: flip · R: photo/video · Right-drag: pan · Backspace: reset"
            or "Tab: frame shot · Click: shoot · Wheel: zoom · R: photo/video · Esc: phone"
    end
    return C.CanPan() and "Right-drag: frame · Wheel: zoom · Space: shoot · Tab: flip · R: reset · Esc: phone" or "Following spectator view · Wheel: zoom · Space: shoot · Esc: phone"
end

local function resetFraming()
    C.Cancel(); C.pan = Angle(0, 0, 0); C.orbit = Angle(0, 0, 0); C.zoom = 1; C.zoomTarget = nil; C.exposure = 0
end

function C.HandleKey(key)
    if key == KEY_ESCAPE then
        C.Cancel()
        -- Photo detail/delete-confirm are K.Modal sheets now (openDetail(), C.Gallery above), not the
        -- old nested C.galleryDetail sheet, so there is nothing to unwind between gallery and camera:
        -- Esc closes the topmost of gallery/fullscreen/phone. A K.Modal only closes via its own
        -- buttons or a click on its shade (K.Sheet's default dismissable behaviour).
        if IsValid(C.gallery) then C.gallery:Remove()
        elseif IsValid(C.fullscreen) then C.fullscreen:Remove()
        elseif IsValid(C.phone) then C.phone:SetPhonePage("home") end
        if gui.IsGameUIVisible() then gui.HideGameUI() end
        return
    end
    if IsValid(C.gallery) then return end
    if C.Tester() then
        if key == KEY_TAB then C.EnterFraming()
        elseif key == KEY_F then flip()
        elseif key == KEY_R then C.ToggleCaptureMode()
        elseif key == KEY_G then C.grid = not C.grid
        elseif key == KEY_BACKSPACE then resetFraming() end
        return
    end
    if key == KEY_SPACE then C.Shutter()
    elseif key == KEY_TAB then flip()
    elseif key == KEY_G then C.grid = not C.grid
    elseif key == KEY_R then resetFraming() end
end

local keys = {KEY_SPACE, KEY_TAB, KEY_G, KEY_R, KEY_ESCAPE, KEY_F, KEY_BACKSPACE}
local down = {}
local previouslyFocused = false
hook.Add("Think", "GoobOS.Camera.Keys", function()
    local active = C.Active() and system.HasFocus() and not C.ReplayActive()
    -- Capture only keys while our own app or framing panel owns keyboard focus.
    local focused = active and (C.root:HasHierarchicalFocus() or (IsValid(C.fullscreen) and C.fullscreen:HasHierarchicalFocus()))
    -- Framing owns the keyboard through binds; the key that ended framing must not also act in the app.
    if C.framing or RealTime() - (C.framingChangedAt or -10) < C.FramingDebounce then focused = false; active = false end
    for _, key in ipairs(keys) do
        local pressed = input.IsKeyDown(key)
        local escapeHandoff = active and key == KEY_ESCAPE and previouslyFocused and gui.IsGameUIVisible()
        if (focused or escapeHandoff) and pressed and not down[key] then C.HandleKey(key) end
        down[key] = pressed
    end
    previouslyFocused = focused and true or false
end)

-- Framing HUD: a phone-shaped live viewfinder, bottom-right, larger than the in-app one, redrawn every
-- frame from the preview RT (camera.lua renders it every frame while framing). Hidden while the killcam
-- owns the screen (US1 HUD rule: ZCKillcamView.State() ~= nil) and while the game menu is up.
local HUD_BEZEL = Color(14, 11, 11, 235)
function C.FramingRect(sw, sh)
    local vw = math.floor(math.Clamp(sw * 0.34, 360, 720))
    local vh = math.floor(vw * 9 / 16)
    local pad, hintH = 8, 26
    local w, h = vw + pad * 2, vh + pad * 2 + hintH
    return sw - w - 24, sh - h - 24, w, h, vw, vh, pad
end

function C.PaintFramingHUD(sw, sh)
    if not C.framing or C.KillcamOwnsScreen() or gui.IsGameUIVisible() then return false end
    local x, y, w, h, vw, vh, pad = C.FramingRect(sw, sh)
    draw.RoundedBox(12, x, y, w, h, HUD_BEZEL)
    local vx, vy = x + pad, y + pad
    local reason = C.Blocked() or C.problem
    if C.material and C.previewTarget and C.FrameLive() and not reason then
        surface.SetMaterial(C.material)
        surface.SetDrawColor(255, 255, 255)
        surface.DrawTexturedRectUV(vx, vy, vw, vh, 0, 0, (C.frameW or C.VideoWidth) / C.previewTarget:Width(), (C.frameH or C.VideoHeight) / C.previewTarget:Height())
        if C.grid then
            surface.SetDrawColor(255, 255, 255, 55)
            for i = 1, 2 do
                surface.DrawLine(vx + vw * i / 3, vy, vx + vw * i / 3, vy + vh)
                surface.DrawLine(vx, vy + vh * i / 3, vx + vw, vy + vh * i / 3)
            end
        end
    else
        draw.RoundedBox(0, vx, vy, vw, vh, VIEW_BG)
        caption(reason or "Opening camera…", vx + vw / 2, vy + vh / 2, T.muted, TEXT_ALIGN_CENTER)
    end
    local modeLabel = (C.mode == "selfie" and "SELFIE" or "FRONT") .. "  ·  " .. (C.captureMode == "video" and "VIDEO" or "PHOTO")
    draw.RoundedBox(3, vx + 8, vy + 8, 128, 24, CHIP_BG)
    caption(modeLabel, vx + 16, vy + 20)
    draw.RoundedBox(3, vx + vw - 62, vy + 8, 54, 24, CHIP_BG)
    caption(string.format("%.1f×", C.zoom), vx + vw - 35, vy + 20, T.accent, TEXT_ALIGN_CENTER)
    if C.rec then C.PaintRec(vx + vw / 2, vy + 20) end
    if C.deadline then
        draw.SimpleText(math.max(1, math.ceil(C.deadline - RealTime())), "GoobMetric", vx + vw / 2, vy + vh / 2, white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    if C.flash and RealTime() - C.flash < 0.18 then
        surface.SetDrawColor(255, 255, 255, 100 * (1 - (RealTime() - C.flash) / 0.18))
        surface.DrawRect(vx, vy, vw, vh)
    end
    local hintY = vy + vh + (h - pad * 2 - vh) / 2 + pad / 2
    local text
    if C.message and RealTime() < (C.messageUntil or 0) then text = C.message
    else
        local primary = C.captureMode ~= "video" and "LMB shoot" or (C.rec and "LMB stop" or "LMB record")
        text = primary .. "  ·  Wheel zoom  ·  R photo/video  ·  F flip  ·  RMB / Tab cursor"
    end
    K.Text(K.Fit(text, K.Font(12, 600), vw - 8), 12, 600, x + w / 2, hintY, C.message and RealTime() < (C.messageUntil or 0) and T.accent or T.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    return true
end

hook.Add("HUDPaint", "GoobOS.Camera.FramingHUD", function()
    if not C.framing then return end
    C.PaintFramingHUD(ScrW(), ScrH())
end)

local function build(root, phone)
    C.Close()
    C.root, C.phone = root, phone
    C.failed = false; C.problem = nil; C.context = C.Context(); C.nextFrame = 0
    if not IsValid(LocalPlayer()) or not LocalPlayer():Alive() then C.SetMode("world") end
    root:SetKeyboardInputEnabled(true)
    root:RequestFocus()
    root.OnRemove = function() if C.root == root then C.Close() end end

    local stage = K.Panel(root)
    stage:Dock(TOP)
    stage:DockMargin(0, 0, 8, 8)
    local view = viewfinder(stage)
    local railPanel = rail(stage)
    local stripPanel = chipStrip(stage)
    local hint = A.Label(stage, "", "GoobSmall", T.muted)
    local bar = bottomBar(stage, function() C.Gallery(root) end)
    for _, w in ipairs({view, railPanel, stripPanel, hint, bar}) do w:Dock(NODOCK) end
    local layout = surfaceLayout(view, railPanel, stripPanel, hint, bar)
    -- `stage` is Dock(TOP) with no fixed height of its own: size it from its own (docked) width
    -- first, then lay out its children against the height that resolves to.
    stage.Think = function(s)
        local w = s:GetWide()
        local h = math.max(300, w * 0.68)
        if s:GetTall() ~= h then s:SetTall(h) end
        layout(w, h)
    end

    button(root, "Expand viewfinder", C.Fullscreen, T.accent)
    local message = A.Status(root, "Photos save to your local gallery.")
    message.Think = function(s)
        s:SetText(C.message and RealTime() < (C.messageUntil or 0) and C.message or (C.Tester() and "Photos and clips save to your local gallery." or "Photos save to your local gallery."))
    end
end

A.Register("camera", "Camera", "Frame it. Keep it.", "icon16/camera.png", T.gold, build)
