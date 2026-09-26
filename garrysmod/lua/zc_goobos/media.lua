-- GoobOS shared fullscreen media player (BRIEF Stage C2). Client only; no server file, no net.Receive.
-- Boot order (owner): loads after kit.lua, before camera.lua/camera_ui.lua and feed.lua/feed_ui.lua --
-- so this file must not read ZCGoobApps.Camera or ZCGoobFeed. Everything hangs off ZCGoobApps.Media
-- (no other globals), per KIT_API.md.
if not CLIENT then return end
ZCGoobApps = ZCGoobApps or {}
local A = ZCGoobApps
ZCGoobApps.Media = ZCGoobApps.Media or {}
local M = ZCGoobApps.Media

-- "Does nothing while the killcam viewer is playing" (spec). ZCKillcamView exposes no UIActive/State
-- fields directly -- checked against the mirror's zc_killcam/viewer_parts/*.lua -- but it does expose
-- ObserverState(), the same accessor camera.lua's own C.ReplayActive() already uses for this exact
-- question, so this reuses that proven surface instead of guessing at field names. Nil-safe throughout.
local function killcamPlaying()
    local view = ZCKillcamView
    if not (view and isfunction(view.ObserverState)) then return false end
    local state = view.ObserverState()
    return state and state.playing and true or false
end

-- Fitted media rect: 16:9, capped at 80% of screen width (07_camera.html notes: "capped at 80% of
-- screen width per the brief... a readability choice, not a source constraint" -- carried over here
-- for the same reason). No item in this app ever carries real width/height (see item shape in
-- KIT_API.md), so native-aspect photos degrade to 16:9; camera.lua is the only photo producer today
-- and it always captures 16:9, so this is not currently a visible approximation.
local TOP_BAR, BOTTOM_BAR, MARGIN = 64, 64, 12
local BACKDROP = Color(0, 0, 0, 215) -- hoisted: the player Paint used to allocate it every frame
local function mediaRect(w, h)
    local areaW, areaH = w * 0.8, math.max(1, h - TOP_BAR - BOTTOM_BAR - MARGIN * 2)
    local rw, rh = areaW, areaW * 9 / 16
    if rh > areaH then rh, rw = areaH, areaH * 16 / 9 end
    return (w - rw) / 2, TOP_BAR + MARGIN + (areaH - rh) / 2, rw, rh
end

local function noKeys(panel)
    panel:SetKeyboardInputEnabled(false)
    return panel
end

-- One persistent action button row, rebuilt (not recreated) per Open() -- item.actions differs per
-- item, but rebuilding a handful of DButtons on an explicit user action is not the per-frame
-- allocation the "cheap" requirement rules out (no RT, no material, no per-frame work).
local function rebuildActions(row, actions)
    local T, K = A.Theme, A.Kit
    row:Clear()
    row.Buttons = {}
    for _, spec in ipairs(actions or {}) do
        local b = noKeys(vgui.Create("DButton", row))
        b:SetText("")
        b.DoClick = function() if spec.fn then spec.fn() end end
        b.Paint = function(s, w, h)
            local hover = K.Hover(s)
            draw.RoundedBox(4, 0, 0, w, h, T.card)
            if hover > 0.01 then draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.white, 14 * hover)) end
            K.Text(K.Fit(spec.label or "", K.Font(14, 600), w - 16), 14, 600, w / 2, h / 2, spec.danger and T.red or T.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        row.Buttons[#row.Buttons + 1] = b
    end
end

-- Lazily created once, then reused for every Open()/Close(): one popup panel, one persistent DHTML
-- (base64 fallback), and a Material() per current photo path (GMod caches Material() by path itself,
-- so re-asking for the same or a different data/ path on each Open() is a lookup, not a fresh GPU
-- resource -- the same pattern zc_chat_media/client.lua already uses for cached thumbnails/emoji).
local function ensurePanel()
    if IsValid(M.Panel) then return M.Panel end
    local T, K = A.Theme, A.Kit
    local p = vgui.Create("DPanel")
    M.Panel = p
    p:SetZPos(32750) -- above camera_ui.lua's own fullscreen popup (32700)
    p:SetVisible(false)
    p:SetKeyboardInputEnabled(true)
    p:SetMouseInputEnabled(true)

    local html = vgui.Create("DHTML", p)
    M.Html = html
    html:SetAllowLua(false)
    html:SetMouseInputEnabled(false) -- clicks fall through to p:OnMousePressed (click-outside-closes)
    html:SetVisible(false)

    local top = vgui.Create("DPanel", p)
    top:SetPaintBackground(false)
    top.Paint = function(_, w, h)
        local item = M.Item
        if not item then return end
        K.Text(K.Fit((item.author or "") .. " · " .. (item.time or "") .. " · " .. (item.kind == "clip" and "Clip" or (item.kind == "video" and "Video" or "Photo")), K.Font(15, 600), w - 90), 15, 600, 0, h / 2, T.white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local close = noKeys(vgui.Create("DButton", p))
    close:SetText("")
    close.DoClick = function() M.Close() end
    close.Paint = function(s, w, h)
        if K.Hover(s) > 0.01 then draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.white, 18 * s.GoobHover)) end
        K.Text("Esc  ×", 15, 600, w / 2, h / 2, T.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local actions = vgui.Create("DPanel", p)
    actions:SetPaintBackground(false)
    actions.Buttons = {}
    M.Actions = actions

    p.Paint = function(_, w, h)
        draw.RoundedBox(0, 0, 0, w, h, BACKDROP)
        local x, y, rw, rh = mediaRect(w, h)
        M.Rect = {x = x, y = y, w = rw, h = rh}
        if M.Mode == "material" and M.Material then
            surface.SetMaterial(M.Material)
            surface.SetDrawColor(255, 255, 255)
            surface.DrawTexturedRect(x, y, rw, rh)
        elseif M.Mode ~= "html" then
            draw.RoundedBox(4, x, y, rw, rh, T.card)
            K.Text("Photo unavailable.", 14, 600, x + rw / 2, y + rh / 2, T.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        local v = M.Video
        if v then
            -- Progress: loaded span, then the playhead; a status line while loading, paused or failed.
            local total = math.max(1, v.duration or 0, v.times[v.loaded] or 0)
            draw.RoundedBox(2, x, y + rh + 8, rw, 4, K.Alpha(T.white, 30))
            draw.RoundedBox(2, x, y + rh + 8, rw * math.Clamp((v.times[v.loaded] or 0) / total, 0, 1), 4, K.Alpha(T.white, 60))
            draw.RoundedBox(2, x, y + rh + 8, rw * math.Clamp(v.clock * 1000 / total, 0, 1), 4, T.accent)
            local state = v.failed or (v.paused and "Paused · click or Space to play") or ((v.buffering or v.loaded == 0) and "Loading clip…") or nil
            if state then K.Text(state, 13, 600, x + rw / 2, y + rh + 26, T.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
        end
    end
    p.PerformLayout = function(_, w, h)
        top:SetPos(40, 0); top:SetSize(w - 120, TOP_BAR)
        close:SetPos(w - 70, (TOP_BAR - 30) / 2); close:SetSize(60, 30)
        local x, y, rw, rh = mediaRect(w, h)
        if html:IsVisible() then html:SetPos(x, y); html:SetSize(rw, rh) end
        actions:SetPos((w - 360) / 2, h - BOTTOM_BAR + 8); actions:SetSize(360, 36)
        for i, b in ipairs(actions.Buttons) do
            local each = (360 - (#actions.Buttons - 1) * 8) / #actions.Buttons
            b:SetPos((i - 1) * (each + 8), 0); b:SetSize(each, 36)
        end
    end
    p.Think = function(s)
        if s:GetWide() ~= ScrW() or s:GetTall() ~= ScrH() then s:SetSize(ScrW(), ScrH()); s:InvalidateLayout() end
        if M.Video then M.StepVideo() end
        -- Defensive auto-close: Open() already refuses to start while the killcam replay owns the
        -- screen, but if it starts *while* a photo is already open, don't fight it for the screen.
        if killcamPlaying() then M.Close() end
    end
    p.OnMousePressed = function(s, keyCode)
        if keyCode ~= MOUSE_LEFT then return end
        local x, y = s:CursorPos()
        local r = M.Rect
        if not r or x < r.x or x > r.x + r.w or y < r.y or y > r.y + r.h then M.Close()
        elseif M.Video then M.Video.paused = not M.Video.paused end
    end
    p.OnKeyCodePressed = function(_, key)
        if key == KEY_ESCAPE then M.Close()
        elseif key == KEY_SPACE and M.Video then M.Video.paused = not M.Video.paused end
    end
    return p
end

local function closeVideo()
    local v = M.Video
    if not v then return end
    M.Video = nil
    if v.handle then pcall(v.handle.Close, v.handle) end
    -- Drop the frames the page holds (up to ~15 MB of data URLs).
    if IsValid(M.Html) then M.Html:SetHTML("") end
end

function M.Close()
    closeVideo()
    if not IsValid(M.Panel) then return end
    M.Panel:SetVisible(false)
    M.Item = nil
end

-- Video clips (camera.lua writes them): "GOOBVID1", u32 frame count, then per frame u32 ms, u32 bytes, JPEG.
-- Playback = the one reused DHTML <img>, its src swapped to the frame due at the current time. Frames stream
-- from disk into the page a few milliseconds per Think (no whole-file read, no hitch); the clock is Lua's,
-- so pause, loading stalls and looping are exact; there is no per-frame texture and no per-frame disk write.
M.VideoMagic = "GOOBVID1"
M.VideoLoadBudget = 0.003
M.VideoMaxFrameBytes = 4 * 1024 * 1024
M.VIDEO_PAGE = [[<!doctype html><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'unsafe-inline'"><style>html,body{margin:0;height:100%;background:#080c13;overflow:hidden}img{width:100%;height:100%;object-fit:contain}</style><img id="v" alt=""><script>var F=[];function A(i,d){F[i]="data:image/jpeg;base64,"+d}function S(i){var f=F[i];if(f){document.getElementById("v").src=f}}</script>]]

local function toBase64(data)
    return (string.gsub(util.Base64Encode(data, true) or "", "[\r\n]", ""))
end

-- Load a budgeted batch of frames into the page, then advance the clock and show the frame that is due.
function M.StepVideo(dt)
    local v = M.Video
    if not v or not IsValid(M.Html) then return end
    local now = RealTime()
    dt = dt or math.min(0.25, now - (v.last or now))
    v.last = now
    -- Scripts sent right after SetHTML can land before the page exists; start streaming once it has settled.
    if v.handle and now >= v.readyAt and not M.Html:IsLoading() then
        local deadline = SysTime() + M.VideoLoadBudget
        repeat
            local ms, len = v.handle:ReadULong(), v.handle:ReadULong()
            local data = len and len > 0 and len <= M.VideoMaxFrameBytes and v.handle:Read(len) or nil
            if not ms or not data or #data ~= len then
                pcall(v.handle.Close, v.handle); v.handle = nil
                if v.loaded == 0 then v.failed = "This clip could not be read." end
                v.count = v.loaded
                break
            end
            v.loaded = v.loaded + 1
            v.times[v.loaded] = ms
            M.Html:QueueJavascript("A(" .. (v.loaded - 1) .. ",\"" .. toBase64(data) .. "\")")
            if v.loaded >= v.count then pcall(v.handle.Close, v.handle); v.handle = nil end
        until not v.handle or SysTime() >= deadline
    end
    if v.loaded == 0 or v.failed then return end
    local complete = v.handle == nil
    v.buffering = not complete and v.clock * 1000 > v.times[v.loaded]
    if not v.paused and not v.buffering then v.clock = v.clock + dt end
    if complete and v.clock * 1000 >= v.times[v.loaded] + 1000 / 24 then v.clock = 0; v.index = 0 end
    local index = math.max(1, v.index)
    while index < v.loaded and v.times[index + 1] <= v.clock * 1000 do index = index + 1 end
    if index ~= v.shown then
        v.shown, v.index = index, index
        M.Html:QueueJavascript("S(" .. (index - 1) .. ")")
    end
end

local function openVideo(item)
    if not isstring(item.path) or not item.path:match("^goobos/videos/clip_%d+_%d+%.dat$") then return false end
    local handle = file.Open(item.path, "rb", "DATA")
    if not handle then return false end
    local magic = handle:Read(#M.VideoMagic)
    local count = magic == M.VideoMagic and handle:ReadULong() or nil
    if not count or count < 1 or count > 24 * 60 then handle:Close(); return false end
    closeVideo()
    M.Video = {handle = handle, count = count, loaded = 0, times = {}, clock = 0, index = 0, shown = -1,
        duration = tonumber(item.duration) and item.duration * 1000 or nil, readyAt = RealTime() + 0.25}
    M.Mode = "html"
    M.Material = nil
    M.Html:SetHTML(M.VIDEO_PAGE)
    M.Html:SetVisible(true)
    return true
end

-- item = {kind = "photo", path = "goobos/photos/<file>.jpg" (DATA) or base64 = "<jpeg b64>",
--   title, author, time, actions = {{label, fn, danger}}}
-- or {kind = "clip", id = "<killcam clip id>", title, ...}
function M.Open(item)
    if not istable(item) or not isstring(item.kind) then return end
    if killcamPlaying() then return end
    if item.kind == "clip" then
        if not isstring(item.id) or item.id == "" then return end
        -- Exactly what the killcam records menu does (cl_part_03.lua:100-230, cl_part_02.lua:583):
        -- open the viewer, then ask it for this clip. Its own net.Receive("zckc_clip") (already
        -- registered by that file) decodes and plays it -- this file adds no net.Receive of its own.
        RunConsoleCommand("zc_killcam")
        net.Start("zckc_clip")
        net.WriteString(item.id)
        net.SendToServer()
        return
    end
    if item.kind == "video" then
        local p = ensurePanel()
        if not openVideo(item) then return end
        M.Item = item
        rebuildActions(M.Actions, item.actions)
        p:SetSize(ScrW(), ScrH()); p:SetPos(0, 0)
        p:SetVisible(true)
        p:InvalidateLayout()
        p:MakePopup()
        return
    end
    if item.kind ~= "photo" then return end
    if not (isstring(item.path) or isstring(item.base64)) then return end
    local p = ensurePanel()
    closeVideo()
    M.Item = item

    -- Photos from disk go through the same single reused DHTML as base64 photos: a Material() per path would keep a
    -- full-size GPU texture per photo ever opened (camera_ui.lua deliberately avoided that; same reason here).
    local b64 = item.base64
    if isstring(item.path) then
        local size = file.Size(item.path, "DATA") or -1
        local jpg = size >= 4 and size <= 12 * 1024 * 1024 and file.Read(item.path, "DATA") or nil
        if not jpg or #jpg ~= size then return end
        b64 = util.Base64Encode(jpg)
    end
    M.Mode = "html"
    M.Material = nil
    M.Html:SetHTML('<!doctype html><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; img-src data:; style-src \'unsafe-inline\'"><style>html,body{margin:0;height:100%;background:#080c13;overflow:hidden}img{width:100%;height:100%;object-fit:contain}</style><img alt="Photo" src="data:image/jpeg;base64,' .. b64 .. '">')
    M.Html:SetVisible(true)

    rebuildActions(M.Actions, item.actions)
    p:SetSize(ScrW(), ScrH()); p:SetPos(0, 0)
    p:SetVisible(true)
    p:InvalidateLayout()
    p:MakePopup()
end
