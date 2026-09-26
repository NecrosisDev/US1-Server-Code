if not CLIENT then return end
ZCGoobApps = ZCGoobApps or {}
local A, T = ZCGoobApps, ZCGoobApps.Theme
A.PreviewVersion = "20260924.preview2"

-- Shared 3D for Wardrobe + Shop: the player-preview widget (BRIEF Stage A) and the model icon cache.
--
-- One DModelPanel wraps one ClientsideModel (panel.Entity). A.ApplyPreview (wardrobe.lua) only calls
-- panel:SetModel() when the model string changes, so widget:SetBase() re-skins the SAME entity.
-- widget:Fit(item) previews a hg.PointShop / hg.Accessories item WORN on that base through the same
-- DrawAccesories(...) call the appearance editor uses (pointshop items are generated 1:1 from
-- hg.Accessories with the same key, so item.ID is an hg.Accessories key).
--
-- Polish pass 2026-09-24: the camera frames the model from the panel's real aspect (a stacked, wide
-- preview used to show the midriff only), widget:Focus(region) zooms to the part being picked (the
-- original ZCity appearance editor zoomed to Head/Face/Torso/Legs/Boots the same way), and the
-- mockup's "Fitting: ..." chip and "Drag to rotate" hint are painted by the widget itself.
local IDLE_DEG_PER_SEC = 12
local IDLE_RESUME_DELAY = 2.5
local DRAG_DEG_PER_PX = 0.5
local PREVIEW_FOV = 30

-- PROVISIONAL(2026-09-23, no explicit breakpoint constant exists in
-- apps.lua's Layout(); picked from A.Open's own "minimum" phone math --
-- phone_preferences.lua's ResetLayout smallest default width is 384px and
-- the app host strips ~40px of padding/margins from that, so ~360px of body
-- content is roughly where a phone stops being able to show two usable
-- columns. ratify-by: 2026-10-07 -- owner should confirm on the
-- smallest-size screenshot in REPORT_A.md; this may need to move.)
A.PREVIEW_STACK_BREAKPOINT = 360

-- Framing regions in model units (player models stand ~72 u tall at the origin, facing +X).
-- z = look-at height, h = height that must fit, w = width that must fit.
local REGIONS = {
    all = {z = 37, h = 80, w = 38},
    head = {z = 65, h = 22, w = 22},
    face = {z = 64, h = 16, w = 18},
    torso = {z = 48, h = 36, w = 32},
    legs = {z = 22, h = 46, w = 30},
    boots = {z = 7, h = 20, w = 26},
    hands = {z = 38, h = 34, w = 46}
}
A.PreviewRegions = REGIONS
local PLACEMENT_REGION = {head = "head", ears = "head", face = "face", torso = "torso", spine = "torso"}
function A.PreviewRegionFor(placement) return PLACEMENT_REGION[placement] or "all" end

local function clearAccessories(ent)
    for _, m in pairs(ent.modelAccess or {}) do
        if IsValid(m) then m:Remove() end
    end
    ent.modelAccess = {}
end

local function spring(current, target, rate)
    local K = A.Kit
    if K then return K.Spring(current, target, rate) end
    return target
end

-- Model icon cache -----------------------------------------------------------------------------
-- Moved here from shop.lua so Shop tiles, Wardrobe's accessory grid and model portraits share one
-- cache (BRIEF A2: "render each item once to a cached material ... never per-frame model renders in
-- a grid"). Two faults made every shop icon a "?":
--   1. util.IsValidModel() returns false CLIENTSIDE for any model the server never precached
--      (wiki util.IsValidModel), and accessories are clientside-only models. Existence is now
--      checked with file.Exists(path, "GAME"), which searches mounted workshop content.
--   2. The bake ran from a panel Think, outside any render hook. It now runs from PostRender, the
--      hook camera.lua already renders its viewfinder RT from on the live server.
-- One reused bake entity, one 128 px render target + material per icon (created once per session),
-- at most one bake per frame, and only for icons something actually asked to draw.
local ICON_SIZE = 128
local ICON_BG = Color(47, 43, 43)
local Icons = A.Icons or {}
A.Icons = Icons
Icons.mats = Icons.mats or {} -- key -> IMaterial, or false when the model is missing/failed
Icons.queue = Icons.queue or {}
Icons.queued = Icons.queued or {}
-- A "model not found" miss is retried (workshop content can still be mounting when the phone first
-- opens): after 15 s, up to 3 times, instead of staying a placeholder for the whole session.
Icons.retryAt, Icons.retries = Icons.retryAt or {}, Icons.retries or {}

local function iconName(key)
    -- RT names are paths ("." ends the name) and are cached many-to-one after sanitising, so a CRC
    -- of the raw key keeps every icon distinct.
    local raw = tostring(key)
    return "goobos_icon2_" .. string.gsub(string.lower(raw), "[^%w_]", "_") .. "_" .. util.CRC(raw)
end

--- Icon spec for a hg.PointShop item (fields as sh_pointshop.lua CreateItem sets them).
function A.ItemIconSpec(item)
    if not istable(item) then return nil end
    local acc = hg and hg.Accessories and hg.Accessories[item.ID]
    return {
        mdl = item.MDL,
        skin = item.SKIN,
        bodygroups = item.BODYGROUP,
        submats = item.DATA,
        lookAt = item.VPos,
        fov = item.FOV,
        tint = acc and acc.bSetColor and acc.vecColorOveride or nil
    }
end

--- Icon spec for an hg.Accessories entry (same framing the original appearance editor's icons used).
function A.AccessoryIconSpec(data)
    if not istable(data) then return nil end
    return {
        mdl = data.model,
        skin = data.skin,
        bodygroups = data.bodygroups,
        submats = data.SubMat and {[0] = data.SubMat} or nil,
        lookAt = data.vpos,
        fov = 15,
        tint = data.bSetColor and data.vecColorOveride or nil
    }
end

--- Returns the icon material for `key`, nil while it is queued/baking, false if it cannot be made.
function Icons.Get(key, spec)
    local mat = Icons.mats[key]
    if mat == false and Icons.retryAt[key] and RealTime() >= Icons.retryAt[key] then
        Icons.retryAt[key] = nil
        Icons.mats[key] = nil
        mat = nil
    end
    if mat ~= nil then return mat end
    if not spec then return false end
    if not Icons.queued[key] then
        Icons.queued[key] = true
        Icons.queue[#Icons.queue + 1] = {key = key, spec = spec}
    end
    return nil
end

--- Paint helper: the baked icon, or a glyph plate while it bakes (or when the model is missing).
function Icons.Draw(key, spec, x, y, size, glyph)
    local mat = Icons.Get(key, spec)
    if mat then
        surface.SetMaterial(mat)
        surface.SetDrawColor(255, 255, 255, 255)
        surface.DrawTexturedRect(x, y, size, size)
        return true
    end
    draw.RoundedBox(4, x, y, size, size, T.hover)
    local K = A.Kit
    if K then K.Glyph(glyph or "hanger", x + size / 2, y + size / 2, math.floor(size * 0.36), mat == false and K.Alpha(T.muted, 110) or T.muted) end
    return false
end

local function modelExists(mdl)
    return isstring(mdl) and mdl ~= "" and string.sub(mdl, 1, 7) == "models/" and file.Exists(mdl, "GAME")
end

local function bakeEntity(mdl)
    if not IsValid(Icons.ent) then
        Icons.ent = ClientsideModel(mdl, RENDERGROUP_OTHER)
        if not IsValid(Icons.ent) then return nil end
        Icons.ent:SetNoDraw(true)
        Icons.ent:SetIK(false)
    end
    local ent = Icons.ent
    if ent:GetModel() ~= mdl then ent:SetModel(mdl) end
    ent:SetSubMaterial()
    for i = 0, (ent:GetNumBodyGroups() or 1) - 1 do ent:SetBodygroup(i, 0) end
    ent:SetPos(vector_origin)
    ent:SetAngles(angle_zero)
    return ent
end

-- Camera for an item icon: the original tuned framing (camera at 50,50,50 looking at the item's
-- vpos, FOV 15 -- what the old pointshop and appearance-editor icons used) unless the look-at point
-- sits outside the mesh, in which case frame the mesh's bounds instead.
local function itemCamera(ent, spec)
    local lookAt = isvector(spec.lookAt) and spec.lookAt or Vector(0, 0, 0)
    local fov = math.Clamp(tonumber(spec.fov) or 15, 5, 90)
    local mins, maxs = ent:GetModelBounds()
    if mins and maxs then
        local inside = lookAt.x >= mins.x - 2 and lookAt.x <= maxs.x + 2 and lookAt.y >= mins.y - 2 and lookAt.y <= maxs.y + 2 and lookAt.z >= mins.z - 2 and lookAt.z <= maxs.z + 2
        if not inside then
            lookAt = (mins + maxs) * 0.5
            fov = 30
            local radius = math.max((maxs - mins):Length() * 0.5, 2)
            local dir = Vector(1, 1, 0.8)
            dir:Normalize()
            return lookAt + dir * (radius / math.tan(math.rad(fov / 2)) * 1.08), lookAt, fov
        end
    end
    return Vector(50, 50, 50), lookAt, fov
end

-- Camera for a player-model portrait: head and shoulders from the front, slightly off-axis.
local function portraitCamera(ent)
    local seq = ent:LookupSequence("idle_all_01")
    if seq and seq >= 0 then
        ent:ResetSequence(seq)
        ent:SetCycle(0)
    end
    ent.GetPlayerColor = function() return Vector(0.55, 0.55, 0.58) end
    ent:SetupBones()
    local head = ent:LookupBone("ValveBiped.Bip01_Head1")
    local pos = head and ent:GetBonePosition(head)
    local lookAt = (isvector(pos) and pos or Vector(0, 0, 64)) - Vector(0, 0, 3)
    return lookAt + Vector(40, 13, 3), lookAt, 32
end

local function bakeIcon(job)
    local spec = job.spec
    if not modelExists(spec.mdl) then return false end
    local ent = bakeEntity(spec.mdl)
    if not ent then return false end
    local skin = spec.skin
    if isfunction(skin) then
        local ok, value = pcall(skin, ent)
        skin = ok and value or 0
    end
    ent:SetSkin(tonumber(skin) or 0)
    local groups = spec.bodygroups
    if isnumber(groups) then groups = tostring(groups) end
    if isstring(groups) and groups ~= "" then ent:SetBodyGroups(groups) end
    for index, mat in pairs(istable(spec.submats) and spec.submats or {}) do
        if isnumber(index) and isstring(mat) then ent:SetSubMaterial(index, mat) end
    end

    local camPos, lookAt, fov
    if spec.portrait then
        camPos, lookAt, fov = portraitCamera(ent)
    else
        ent.GetPlayerColor = nil
        ent:SetupBones()
        camPos, lookAt, fov = itemCamera(ent, spec)
    end

    local name = iconName(job.key)
    local rt = GetRenderTargetEx(name, ICON_SIZE, ICON_SIZE, RT_SIZE_NO_CHANGE, MATERIAL_RT_DEPTH_SHARED, 0, 0, IMAGE_FORMAT_BGRA8888)
    if not rt then return false end
    local pushed, started, suppressed = false, false, false
    local ok = xpcall(function()
        render.PushRenderTarget(rt, 0, 0, ICON_SIZE, ICON_SIZE)
        pushed = true
        render.Clear(ICON_BG.r, ICON_BG.g, ICON_BG.b, 255, true, true)
        cam.Start3D(camPos, (lookAt - camPos):Angle(), fov, 0, 0, ICON_SIZE, ICON_SIZE, 1, 4096)
        started = true
        render.SuppressEngineLighting(true)
        suppressed = true
        render.ResetModelLighting(0.42, 0.42, 0.45)
        render.SetModelLighting(BOX_TOP, 1, 1, 1)
        render.SetModelLighting(BOX_FRONT, 0.85, 0.85, 0.88)
        render.SetModelLighting(BOX_RIGHT, 0.6, 0.6, 0.62)
        render.SetBlend(1)
        local tint = spec.tint
        if istable(tint) or isvector(tint) then
            render.SetColorModulation(tonumber(tint[1] or tint.x) or 1, tonumber(tint[2] or tint.y) or 1, tonumber(tint[3] or tint.z) or 1)
        else
            render.SetColorModulation(1, 1, 1)
        end
        ent:DrawModel()
    end, debug.traceback)
    render.SetColorModulation(1, 1, 1)
    if suppressed then render.SuppressEngineLighting(false) end
    if started then cam.End3D() end
    if pushed then render.PopRenderTarget() end
    if not ok then return false end

    local mat = CreateMaterial(name .. "_mat", "UnlitGeneric", {
        ["$basetexture"] = rt:GetName(),
        ["$vertexcolor"] = "1",
        ["$vertexalpha"] = "1",
        ["$nolod"] = "1"
    })
    -- A same-name CreateMaterial returns the cached material; bind the texture object explicitly
    -- (camera.lua's fix for the same trap).
    mat:SetTexture("$basetexture", rt)
    return mat
end

hook.Add("PostRender", "GoobOS.IconBake", function()
    if #Icons.queue == 0 then return end
    local job = table.remove(Icons.queue, 1)
    Icons.queued[job.key] = nil
    local ok, result = pcall(bakeIcon, job)
    if not ok then ErrorNoHalt("[GoobOS] icon bake failed for " .. tostring(job.key) .. ": " .. tostring(result) .. "\n") end
    Icons.mats[job.key] = ok and result or false
    if ok and result == false and (Icons.retries[job.key] or 0) < 3 then
        Icons.retries[job.key] = (Icons.retries[job.key] or 0) + 1
        Icons.retryAt[job.key] = RealTime() + 15
    end
end)

-- Preview widget -------------------------------------------------------------------------------

--- Build a reusable player-preview widget. Caller positions/sizes it.
--- widget:SetBase(draft)   full appearance draft via wardrobe.lua's A.ApplyPreview.
--- widget:Fit(item)        preview a pointshop/accessory item worn on the base (nil clears).
--- widget:Focus(region)    frame "all" (default), "head", "face", "torso", "legs", "boots", "hands".
--- widget:SetChip(text)    top-left label ("Fitting: Black fedora"); nil hides it.
function A.CreatePreviewWidget(parent)
    local widget = vgui.Create("DPanel", parent)
    local K = A.Kit
    widget.Paint = function(_, w, h)
        if K then
            K.Card(0, 0, w, h, T.cardGlass, K.Alpha(T.edge, 160))
            -- Faint red floor glow under the model (mockup 04).
            for i = 0, 5 do
                surface.SetDrawColor(T.main.r, T.main.g, T.main.b, 4 + i * 3)
                surface.DrawRect(1, h - 1 - (6 - i) * 10, w - 2, 10)
            end
        else
            draw.RoundedBox(0, 0, 0, w, h, T.card)
        end
    end

    local model = vgui.Create("DModelPanel", widget)
    model:Dock(FILL)
    model:DockMargin(1, 1, 1, 1)
    model:SetFOV(PREVIEW_FOV)
    model:SetCamPos(Vector(150, 0, 50))
    model:SetLookAt(Vector(0, 0, 37))
    model:SetAmbientLight(Color(176, 173, 173))
    model:SetDirectionalLight(BOX_FRONT, T.text)
    model:SetDirectionalLight(BOX_TOP, Color(200, 196, 196))
    model:SetAnimated(false)
    model:SetMouseInputEnabled(true)
    model:SetCursor("sizewe")
    widget.ModelPanel = model

    -- A model that never lands (bad model string, failed load) would otherwise leave a blank card
    -- indistinguishable from a layout bug.
    local basePaint = model.Paint
    model.Paint = function(s, w, h)
        local ent = s.Entity
        if not IsValid(ent) or not isstring(ent:GetModel()) or ent:GetModel() == "" then
            if K then
                K.Glyph("hanger", w / 2, h / 2 - 12, 28, T.muted)
                K.Text("No preview available", 13, 500, w / 2, h / 2 + 10, T.muted, TEXT_ALIGN_CENTER)
            else
                draw.SimpleText("No preview available", "GoobSmall", w / 2, h / 2, T.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            return true
        end
        if basePaint then return basePaint(s, w, h) end
    end

    local S = {
        yaw = 20,
        dragging = false,
        resumeAt = 0,
        draft = nil,
        fitId = nil,
        region = "all",
        z = REGIONS.all.z,
        fh = REGIONS.all.h,
        fw = REGIONS.all.w
    }
    widget.PreviewState = S

    model.LayoutEntity = function(_, ent) ent:SetAngles(Angle(0, S.yaw, 0)) end

    -- Worn attachments plus the fitted item; a fitted item replaces a worn one in the same slot.
    model.PostDrawModel = function(_, ent)
        if not DrawAccesories then return end
        local fitInfo = S.fitId and hg.Accessories and hg.Accessories[S.fitId]
        for _, id in ipairs((S.draft and S.draft.AAttachments) or {}) do
            if id ~= S.fitId then
                local info = hg.Accessories and hg.Accessories[id]
                if info and info.model and not (fitInfo and info.placement == fitInfo.placement) then
                    DrawAccesories(ent, ent, id, info, false, true)
                end
            end
        end
        if fitInfo and fitInfo.model then
            DrawAccesories(ent, ent, S.fitId, fitInfo, false, true)
        end
    end

    -- Camera: DModelPanel's FOV is horizontal over the panel's real aspect, so the distance that fits
    -- the region's height grows with a wide panel and its width with a tall one.
    local tanHalf = math.tan(math.rad(PREVIEW_FOV / 2))
    local camPos, lookAt = Vector(150, 0, 50), Vector(0, 0, 37)
    model.Think = function(s)
        if not S.dragging and RealTime() >= S.resumeAt then
            S.yaw = (S.yaw + IDLE_DEG_PER_SEC * FrameTime()) % 360
        end
        local w, h = s:GetWide(), s:GetTall()
        if w <= 1 or h <= 1 then return end
        local r = REGIONS[S.region] or REGIONS.all
        S.z, S.fh, S.fw = spring(S.z, r.z, 8), spring(S.fh, r.h, 8), spring(S.fw, r.w, 8)
        local dist = math.max(S.fh * 0.5 * (w / h), S.fw * 0.5) / tanHalf
        lookAt.z = S.z
        camPos.x, camPos.y, camPos.z = dist * 0.995, 0, S.z + dist * 0.1
        s:SetCamPos(camPos)
        s:SetLookAt(lookAt)
    end

    model.OnMousePressed = function(s, code)
        if code ~= MOUSE_LEFT then return end
        S.dragging = true
        S.lastX = select(1, input.GetCursorPos())
        s:MouseCapture(true)
    end

    model.OnMouseReleased = function(s, code)
        if code ~= MOUSE_LEFT then return end
        S.dragging = false
        S.resumeAt = RealTime() + IDLE_RESUME_DELAY
        s:MouseCapture(false)
    end

    model.OnCursorMoved = function()
        if not S.dragging then return end
        local x = select(1, input.GetCursorPos())
        S.yaw = (S.yaw + (x - (S.lastX or x)) * DRAG_DEG_PER_PX) % 360
        S.lastX = x
    end

    -- Chain DModelPanel's own OnRemove: it removes s.Entity. Dropping the chain leaked one player model
    -- per app open/close.
    local previousRemove = model.OnRemove
    model.OnRemove = function(s)
        if IsValid(s.Entity) then clearAccessories(s.Entity) end
        if previousRemove then previousRemove(s) end
    end

    -- Chip + hint painted over the model (mockup 04: "Fitting: <item>" top-left, "Drag to rotate"
    -- bottom-centre; the hint hides while dragging).
    widget.PaintOver = function(_, w, h)
        if not K then return end
        if S.chip then
            local font = K.Font(11, 600)
            local text = K.Fit(S.chip, font, math.max(40, w - 44))
            surface.SetFont(font)
            local cw = surface.GetTextSize(text) + 26
            draw.RoundedBox(4, 8, 8, cw, 22, K.Alpha(T.glassHi, 235))
            K.Dot(9, 16, 6, T.accent)
            draw.SimpleText(text, font, 21, 19, T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        if not S.dragging and h >= 90 then
            local label = w >= 200 and "Drag to rotate" or "Drag"
            local font = K.Font(11, 500)
            surface.SetFont(font)
            local lw = surface.GetTextSize(label) + 30
            local x, y = math.floor((w - lw) / 2), h - 30
            draw.RoundedBox(10, x, y, lw, 20, K.Alpha(T.ink, 190))
            surface.SetDrawColor(T.muted)
            surface.DrawOutlinedRect(x + 9, y + 6, 8, 8, 1)
            draw.SimpleText(label, font, x + 22, y + 10, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end

    -- A hover-driven Fit() can walk through many items; release the fit-only accessory's cached
    -- ClientsideModel when it stops being fit (unless the base draft wears it too).
    local function releaseFit(id)
        local ent = model.Entity
        if not id or not IsValid(ent) then return end
        if S.draft and table.HasValue(S.draft.AAttachments or {}, id) then return end
        local m = ent.modelAccess and ent.modelAccess[id]
        if IsValid(m) then m:Remove() end
        if ent.modelAccess then ent.modelAccess[id] = nil end
    end

    function widget:SetBase(draft)
        local previousFit = S.fitId
        S.draft = draft
        S.fitId = nil
        releaseFit(previousFit)
        if not draft then return end
        A.ApplyPreview(model, draft)
    end

    function widget:Fit(item)
        local id = item and item.ID or nil
        if id == S.fitId then return end
        local previousFit = S.fitId
        S.fitId = id
        releaseFit(previousFit)
    end

    function widget:Focus(region)
        S.region = REGIONS[region] and region or "all"
    end

    function widget:SetChip(text)
        S.chip = text and text ~= "" and tostring(text) or nil
    end

    function widget:GetModelPanel() return model end

    return widget
end
