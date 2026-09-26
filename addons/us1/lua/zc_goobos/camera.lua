if not CLIENT then return end
local A = ZCGoobApps
if A.Camera then
    -- Autorefresh: finish a clip that is still being written and hand the mouse back before the old table is dropped.
    if A.Camera.Shutdown then A.Camera.Shutdown() elseif A.Camera.Close then A.Camera.Close() end
end
local C = {mode = "world", zoom = 1, pan = Angle(0, 0, 0), orbit = Angle(0, 0, 0),
    grid = true, delay = 0, filter = 1, exposure = 0, serial = 0, nextFrame = 0, galleryRevision = 0,
    hideHud = false, freeze = false, captureMode = "photo", framing = false}
A.Camera = C
C.Directory = "goobos/photos"
C.Width, C.Height = 1920, 1080
C.PreviewWidth, C.PreviewHeight = 1024, 576
C.MaxPhotos, C.MaxBytes = 100, 512 * 1024 * 1024
-- Video (tester-locked): silent 24 fps JPEG frame sequences kept in memory while recording, written to
-- data/goobos/videos/<id>.dat (+ .json, .thumb.jpg) in small time-budgeted steps after Stop.
C.VideoDirectory = "goobos/videos"
C.VideoWidth, C.VideoHeight, C.VideoFPS, C.VideoQuality = 640, 360, 24, 60
C.VideoMaxSeconds, C.VideoMaxClips, C.VideoMaxBytes = 20, 20, 256 * 1024 * 1024
-- PROVISIONAL(2026-09-26, 48 MB in-memory ceiling and 12% capture share are first guesses until a live client measures render.Capture, ratify-by: 2026-10-10)
C.VideoMemoryCap, C.VideoCaptureShare = 48 * 1024 * 1024, 0.12
C.VideoMagic = "GOOBVID1"
-- Framing refresh cap: every frame up to ~75 Hz (a 144 Hz client renders the viewfinder every other frame).
C.LiveInterval = 1 / 75

-- Tester lock for framing mode and video, LIFTED for everyone by the owner 2026-09-26 ("push any tester-client-only
-- features ... to everyone"). Default "*"; a SteamID64 list still restricts it. Created on the server by the GoobOS autorun when the lead
-- adds it there; this client-side creation keeps GetConVar valid (and the owner-only default) either way.
local testerVar = GetConVar("zc_goobos_camera_tester")
    or CreateConVar("zc_goobos_camera_tester", "*", FCVAR_REPLICATED, "SteamID64(s) that get camera framing + video; * = everyone")
local testerCache = {at = -1}
function C.Tester()
    local now = RealTime()
    if now - testerCache.at < 1 then return testerCache.value end
    testerCache.at = now
    local value = false
    local p = LocalPlayer()
    local list = testerVar and testerVar:GetString() or ""
    -- the pre-lift owner-only default still lives on in a convar created by the previous load: treat it as "*"
    if list == "*" or list == "" or list == "76561198011536179" then value = true
    elseif IsValid(p) and p.SteamID64 then
        local id = p:SteamID64() or ""
        for token in string.gmatch(list, "[^,%s]+") do if token == id then value = true break end end
    end
    testerCache.value = value
    return value
end
function C.ResetTesterCache() testerCache.at = -1 end
-- Gallery thumbnails (mockup 07: a 3-column thumbnail grid). A 320 x 180 JPEG is written beside each
-- photo as "<photo>.thumb.jpg" (C.ValidName still matches only the photo itself), so the gallery and
-- the last-photo button never load a full 1920 x 1080 texture. Photos taken before thumbnails
-- existed get one generated on first view, at most C.LegacyThumbCap per session, because that one
-- step has to load the full photo as a texture once.
C.ThumbWidth, C.ThumbHeight, C.LegacyThumbCap = 320, 180, 8
C.thumbQueue, C.thumbQueued, C.thumbFailed, C.thumbMats = {}, {}, {}, {}
C.legacyThumbs, C.thumbRevision = 0, 0
C.Filters = {
    {name = "Natural"},
    {name = "Mono", color = 0},
    {name = "Warm", color = 0.9, red = 0.035, blue = -0.018},
    {name = "Cool", color = 0.85, red = -0.015, blue = 0.035}
}

function C.Note(text)
    C.message = text
    C.messageUntil = RealTime() + 5
end

function C.ReplayActive()
    local owner = ZCKillcamView
    if owner and isfunction(owner.ObserverState) then
        local state = owner.ObserverState()
        return state and state.playing and true or false
    end
    return false
end

-- US1 HUD rule: every HUD overlay hides while ZCKillcamView.State() ~= nil (a life replay can run while alive).
function C.KillcamOwnsScreen()
    local owner = ZCKillcamView
    if owner and isfunction(owner.State) then
        local ok, state = pcall(owner.State)
        if ok and state ~= nil then return true end
    end
    return C.ReplayActive()
end

function C.Blocked()
    local p = LocalPlayer()
    if not IsValid(p) then return "Waiting for your player…" end
    if ZCKillcamView and not isfunction(ZCKillcamView.ObserverState) then return "Camera is waiting for the replay integration update." end
    if C.ReplayActive() then return "Finish the replay to use Camera." end
    if g_VR and g_VR.active then return "Camera framing is unavailable in VR." end
    if p:Alive() then
        local org = p.organism
        if org and (org.otrub or (org.brain or 0) > 0.05) then return "Camera unavailable while unconscious." end
        if IsValid(follow) or (hg.GetCurrentCharacter and hg.GetCurrentCharacter(p) ~= p) then
            return "Camera unavailable while ragdolled."
        end
    end
end

function C.Active()
    local phone = C.phone
    return IsValid(C.root) and IsValid(phone) and phone:GetActive() and phone.phonePage == "camera"
end

function C.Cancel()
    C.pending = nil
    C.deadline = nil
end

function C.Close()
    C.Cancel()
    if C.framing then C.ExitFraming() end
    if C.rec then C.StopRecording("Camera closed. Saving your clip…") end
    if IsValid(C.fullscreen) then C.fullscreen:Remove() end
    C.fullscreen = nil
    C.root = nil
    C.phone = nil
    C.validFrame = nil
    C.gallery = nil
    C.galleryDetail = nil
end

function C.Context()
    local p = LocalPlayer()
    if not IsValid(p) then return "invalid" end
    local spect = p:GetNWEntity("spect")
    return tostring(p) .. ":" .. tostring(p:Alive()) .. ":" .. tostring(p:GetObserverMode()) .. ":"
        .. tostring(p:GetNWInt("viewmode", 0)) .. ":" .. tostring(spect) .. ":" .. tostring(GetViewEntity())
        .. ":" .. tostring(zb and zb.ROUND_START) .. ":" .. game.GetMap()
end

function C.SetMode(mode)
    C.Cancel()
    C.mode = mode == "selfie" and IsValid(LocalPlayer()) and LocalPlayer():Alive() and "selfie" or "world"
    C.pan = Angle(0, 0, 0)
    C.orbit = Angle(0, 0, 0)
    C.validFrame = nil
end

function C.Zoom(delta)
    C.Cancel()
    C.zoomTarget = nil
    C.zoom = math.Clamp(C.zoom + delta * 0.15, 1, 3)
end

-- Framing zoom: one wheel notch = x1.15 (geometric, so every notch feels the same), eased toward per frame.
function C.ZoomStep(direction)
    local from = C.zoomTarget or C.zoom
    C.zoomTarget = math.Clamp(direction > 0 and from * 1.15 or from / 1.15, 1, 3)
end

function C.StepZoom(dt)
    local target = C.zoomTarget
    if not target then return end
    local diff = target - C.zoom
    if math.abs(diff) < 0.002 then C.zoom = target; C.zoomTarget = nil; return end
    C.zoom = C.zoom + diff * (1 - math.exp(-(dt or FrameTime()) * 14))
end

function C.Flip()
    if not IsValid(LocalPlayer()) or not LocalPlayer():Alive() then
        C.Note("Spectators use the front camera."); return
    end
    C.SetMode(C.mode == "selfie" and "world" or "selfie")
end

function C.CanPan()
    local p = LocalPlayer()
    return IsValid(p) and (p:Alive() or p:GetNWInt("viewmode", 0) == 3 or p:GetObserverMode() == OBS_MODE_ROAMING)
end

function C.Pan(dx, dy)
    if C.Blocked() then return end
    local a = C.mode == "selfie" and C.orbit or C.pan
    if C.mode ~= "selfie" and not C.CanPan() then return end
    local yawLimit = C.mode == "selfie" and 40 or 90
    a.y = math.Clamp(a.y - dx * 0.18, -yawLimit, yawLimit)
    a.p = math.Clamp(a.p + dy * 0.18, -35, 35)
end

-- Use the view the game already resolved, without invoking CalcView again.
function C.MakeView(base, w, h)
    local p = LocalPlayer()
    if not IsValid(p) or not istable(base) or not isvector(base.origin) or not isangle(base.angles) then
        return nil, "Waiting for the game camera…"
    end
    local origin = Vector(base.origin.x, base.origin.y, base.origin.z)
    local angles = Angle(base.angles.p, base.angles.y, base.angles.r)
    if C.mode == "selfie" and p:Alive() then
        local eye = p:EyePos()
        local aim = p:EyeAngles()
        -- Framing: mouse pitch swings the arm too (look down -> the phone drops), so the face stays in shot.
        local pitch = -C.orbit.p + (C.framing and aim.p * 0.5 or 0)
        local orbit = Angle(math.Clamp(pitch, -30, 30), aim.y + C.orbit.y, 0)
        local wanted = eye + orbit:Forward() * 56 + Vector(0, 0, 4)
        local trace = util.TraceHull({start = eye, endpos = wanted, filter = p,
            mins = Vector(-4, -4, -4), maxs = Vector(4, 4, 4), mask = MASK_SOLID})
        if trace.StartSolid or trace.AllSolid then return nil, "Move away from the wall for a selfie." end
        origin = trace.Hit and trace.HitPos + trace.HitNormal * 3 or wanted
        if origin:DistToSqr(eye) < 18 * 18 then return nil, "Not enough room for a selfie." end
        angles = (eye - Vector(0, 0, 8) - origin):Angle()
    elseif C.CanPan() then
        angles = Angle(math.Clamp(angles.p + C.pan.p, -89, 89), angles.y + C.pan.y, angles.r)
    end
    return {origin = origin, angles = angles, fov = math.deg(2 * math.atan(math.tan(math.rad(75 / 2)) / C.zoom)),
        x = 0, y = 0, w = w, h = h, aspect = w / h, znear = math.max(2, tonumber(base.znear) or 2),
        zfar = base.zfar, drawhud = false, drawviewmodel = false, drawmonitors = false,
        drawviewer = C.mode == "selfie" or (not p:Alive() and base.drawviewer == true), dopostprocess = true}
end

function C.ValidName(name)
    return isstring(name) and #name < 70 and name:match("^photo_%d+_%d+%.jpg$") ~= nil
end

function C.Photos()
    local found = file.Find(C.Directory .. "/photo_*.jpg", "DATA") or {}
    local photos, bytes = {}, 0
    for _, name in ipairs(found) do
        if C.ValidName(name) then
            local size = math.max(0, file.Size(C.Directory .. "/" .. name, "DATA") or 0)
            photos[#photos + 1] = {name = name, bytes = size, time = file.Time(C.Directory .. "/" .. name, "DATA") or 0}
            bytes = bytes + size
        end
    end
    table.sort(photos, function(a, b)
        if a.time == b.time then return a.name > b.name end
        return a.time > b.time
    end)
    return photos, bytes
end

function C.Save(jpeg, meta)
    if not isstring(jpeg) or #jpeg < 4 or jpeg:sub(1, 2) ~= string.char(255, 216) then
        return false, "Photo capture failed. Try again outside the pause menu."
    end
    if #jpeg > 12 * 1024 * 1024 then return false, "Photo is too large to save." end
    local photos, used = C.Photos()
    if #photos >= C.MaxPhotos or used + #jpeg > C.MaxBytes then return false, "Gallery full. Delete a photo to make room." end
    file.CreateDir(C.Directory)
    local name
    for _ = 1, 1000 do
        C.serial = C.serial + 1
        local candidate = "photo_" .. os.time() .. "_" .. string.format("%06d", C.serial) .. ".jpg"
        if not file.Exists(C.Directory .. "/" .. candidate, "DATA") then name = candidate; break end
    end
    if not name then return false, "Could not allocate a photo filename." end
    local path = C.Directory .. "/" .. name
    file.Write(path, jpeg)
    if file.Size(path, "DATA") ~= #jpeg then
        if file.Exists(path, "DATA") then file.Delete(path) end
        return false, "Could not save photo. Check available disk space."
    end
    -- Metadata is optional; the successfully written photo remains usable if it fails.
    pcall(file.Write, path .. ".json", util.TableToJSON(meta or {}))
    C.galleryRevision = C.galleryRevision + 1
    C.lastPhoto = name
    C.lastKind = "photo"
    return true, name
end

function C.ThumbPath(name)
    return C.Directory .. "/" .. name .. ".thumb.jpg"
end

-- Thumbnail material for a photo, or nil (queued / unavailable). Cached per name: Paint-safe.
function C.Thumb(name)
    local mat = C.thumbMats[name]
    if mat ~= nil then return mat or nil end
    if not C.ValidName(name) then C.thumbMats[name] = false; return nil end
    local path = C.ThumbPath(name)
    if file.Exists(path, "DATA") then
        mat = Material("../data/" .. path, "smooth")
        C.thumbMats[name] = (mat and not mat:IsError()) and mat or false
        return C.thumbMats[name] or nil
    end
    if not C.thumbQueued[name] and not C.thumbFailed[name] and C.legacyThumbs < C.LegacyThumbCap then
        C.thumbQueued[name] = true
        C.thumbQueue[#C.thumbQueue + 1] = name
    end
    -- Cache the miss so Paint never hits the disk every frame; writeThumb() clears it again.
    C.thumbMats[name] = false
    return nil
end

-- Draw `texture` (u1/v1 = used part) scaled into the thumbnail RT and return it as a JPEG string.
function C.ThumbJPEG(texture, u1, v1)
    if not C.thumbTarget then C.thumbTarget = GetRenderTarget("goobos_camera_thumb_v1", 512, 256) end
    if not C.thumbMaterial then
        C.thumbMaterial = CreateMaterial("goobos_camera_thumbsrc_v1", "UnlitGeneric", {
            ["$vertexcolor"] = "1", ["$vertexalpha"] = "1", ["$ignorez"] = "1"})
    end
    C.thumbMaterial:SetTexture("$basetexture", texture)
    local pushed, started = false, false
    local ok, data = pcall(function()
        render.PushRenderTarget(C.thumbTarget, 0, 0, C.ThumbWidth, C.ThumbHeight); pushed = true
        render.Clear(0, 0, 0, 255, true, true)
        cam.Start2D(); started = true
        surface.SetMaterial(C.thumbMaterial)
        surface.SetDrawColor(255, 255, 255, 255)
        surface.DrawTexturedRectUV(0, 0, C.ThumbWidth, C.ThumbHeight, 0, 0, u1 or 1, v1 or 1)
        cam.End2D(); started = false
        return render.Capture({format = "jpeg", quality = 82, x = 0, y = 0, w = C.ThumbWidth, h = C.ThumbHeight, alpha = false})
    end)
    if started then cam.End2D() end
    if pushed then render.PopRenderTarget() end
    return ok and isstring(data) and #data > 4 and data or nil
end

local function writeThumb(name, jpeg)
    if not isstring(jpeg) or jpeg:sub(1, 2) ~= string.char(255, 216) then return false end
    local ok = pcall(file.Write, C.ThumbPath(name), jpeg)
    if ok then
        C.thumbMats[name] = nil
        C.thumbRevision = C.thumbRevision + 1
    end
    return ok
end
C.WriteThumb = writeThumb

-- Legacy photos: one thumbnail per frame, only for photos the gallery asked for.
hook.Add("PostRender", "GoobOS.Camera.Thumbs", function()
    local name = C.thumbQueue[1]
    if not name then return end
    table.remove(C.thumbQueue, 1)
    C.thumbQueued[name] = nil
    if C.legacyThumbs >= C.LegacyThumbCap then return end
    C.legacyThumbs = C.legacyThumbs + 1
    local mat = Material("../data/" .. C.Directory .. "/" .. name, "smooth")
    local texture = mat and not mat:IsError() and mat:GetTexture("$basetexture")
    if not texture or not writeThumb(name, C.ThumbJPEG(texture, 1, 1)) then C.thumbFailed[name] = true end
end)

function C.Delete(name)
    if not C.ValidName(name) then return false end
    local path = C.Directory .. "/" .. name
    file.Delete(path)
    if file.Exists(path, "DATA") then return false end
    file.Delete(path .. ".json")
    if file.Exists(C.ThumbPath(name), "DATA") then file.Delete(C.ThumbPath(name)) end
    C.thumbMats[name] = nil
    C.galleryRevision = C.galleryRevision + 1
    return true
end

-- The viewfinder shows a usable frame: a fresh live render, or the frame Photo mode is holding.
function C.FrameLive()
    if C.freeze then return C.frozenAt ~= nil end
    return C.validFrame ~= nil and RealTime() - C.validFrame < 0.5
end

function C.Shutter()
    if not C.Active() or C.gallery or C.rendering or C.pending then return false end
    if C.deadline then C.Cancel(); C.Note("Timer canceled."); return false end
    local reason = C.Blocked()
    if reason then C.Note(reason); return false end
    if not C.FrameLive() then C.Note("Wait for the live viewfinder."); return false end
    if RealTime() < (C.cooldown or 0) then return false end
    C.shotContext = C.Context()
    C.deadline = RealTime() + C.delay
    return true
end

-- Primary action: the shutter in Photo, start/stop in Video. Non-testers are always in Photo.
function C.Trigger()
    if C.captureMode == "video" and C.Tester() then
        if C.rec then C.StopRecording() else C.StartRecording() end
        return
    end
    return C.Shutter()
end

function C.SetCaptureMode(mode)
    if not C.Tester() then C.captureMode = "photo"; return end
    if C.rec then C.Note("Stop recording first."); return end
    C.Cancel()
    C.captureMode = mode == "video" and "video" or "photo"
    if C.captureMode == "video" then C.freeze = false end
end

function C.ToggleCaptureMode()
    C.SetCaptureMode(C.captureMode == "video" and "photo" or "video")
end

local function resources(photo)
    local key = photo and "photoTarget" or "previewTarget"
    if not C[key] then
        local size = photo and 2048 or 1024
        -- No dots: GMod treats render target names as paths and discards the
        -- "extension", so the old "GoobOS.Camera.<key>.v1" name never resolved.
        C[key] = GetRenderTarget("goobos_camera_" .. string.lower(key) .. "_v2", size, size)
    end
    if not photo and not C.material then
        -- Bind the texture object, not its name; a same-name CreateMaterial
        -- returns the cached material, so this also repairs an existing one.
        C.material = CreateMaterial("goobos_camera_preview_v2", "UnlitGeneric", {
            ["$vertexcolor"] = "1", ["$vertexalpha"] = "1", ["$ignorez"] = "1"})
        C.material:SetTexture("$basetexture", C[key])
    end
    return C[key]
end

-- Framing and recording (testers) run the viewfinder at video size every frame; everything else is unchanged.
function C.LiveCadence()
    return (C.framing or C.rec ~= nil) and C.Tester()
end

function C.PreviewSize()
    if C.LiveCadence() then return C.VideoWidth, C.VideoHeight end
    return C.PreviewWidth, C.PreviewHeight
end

local SOI = string.char(255, 216)

-- One video frame from the preview RT that is still pushed. Captures sit on a 1/24 s grid; the running
-- capture cost widens the grid so render.Capture never takes more than VideoCaptureShare of wall time.
-- Skipped grid slots are dropped frames, and every kept frame carries its real timestamp.
local function captureVideoFrame(target, w, h)
    local rec = C.rec
    local now = RealTime()
    if now < rec.nextAt then return end
    local started = SysTime()
    local jpeg = render.Capture({format = "jpeg", quality = C.VideoQuality, x = 0, y = 0, w = w, h = h, alpha = false})
    local cost = SysTime() - started
    rec.cost = rec.captures == 0 and cost or rec.cost * 0.8 + cost * 0.2
    rec.maxCost = math.max(rec.maxCost, cost)
    rec.captures = rec.captures + 1
    local interval = math.max(1 / C.VideoFPS, rec.cost / C.VideoCaptureShare)
    rec.nextAt = math.max(rec.nextAt + interval, now)
    if not isstring(jpeg) or #jpeg < 4 or jpeg:sub(1, 2) ~= SOI then rec.failed = rec.failed + 1; return end
    local index = #rec.frames + 1
    rec.frames[index] = jpeg
    rec.times[index] = math.floor((now - rec.started) * 1000 + 0.5)
    rec.bytes = rec.bytes + #jpeg
    if index == 1 then rec.thumb = C.ThumbJPEG(target, w / target:Width(), h / target:Height()) end
    if rec.bytes >= rec.limit then C.StopRecording("Clip reached its size limit. Saving…") end
end

-- Save a captured photo JPEG (plus the thumbnail staged in C.pendingThumb); shared by live and held captures.
function C.FinishPhoto(jpeg, w, h)
    local success, saved, value = pcall(C.Save, jpeg, {version = 1, time = os.time(), map = game.GetMap(), mode = C.mode,
        width = w, height = h, zoom = C.zoom, filter = C.Filters[C.filter].name, exposure = C.exposure})
    if not success then saved = false; value = "Could not save photo. Check available disk space." end
    if saved and C.pendingThumb then C.WriteThumb(value, C.pendingThumb) end
    C.pendingThumb = nil
    C.Note(saved and "Photo saved to your gallery." or value)
    if saved then
        C.flash = RealTime()
        surface.PlaySound("buttons/button15.wav")
    end
    C.cooldown = RealTime() + 0.75
    return saved
end

-- photo: false = preview, true = full-size capture, "hold" = full-size render kept in the photo RT (Photo mode).
function C.Render(base, photo)
    local full = photo and true or false
    local w, h
    if full then w, h = C.Width, C.Height else w, h = C.PreviewSize() end
    local view, reason = C.MakeView(base, w, h)
    if not view then C.problem = reason; C.validFrame = nil; return false end
    local pushed, started2D = false, false
    -- Selfie head: the zcity render files treat the local player as third person while this flag is up.
    local flagOwner = C.mode == "selfie" and istable(hg) and hg or nil
    C.rendering = true
    local ok, result = xpcall(function()
        local target = resources(full)
        render.PushRenderTarget(target, 0, 0, w, h); pushed = true
        render.Clear(0, 0, 0, 255, true, true)
        if flagOwner then flagOwner.camSelfieRender = true end
        render.RenderView(view)
        if flagOwner then flagOwner.camSelfieRender = nil end
        local filter = C.Filters[C.filter]
        if filter and (filter.color or C.exposure ~= 0) then
            cam.Start2D(); started2D = true
            DrawColorModify({["$pp_colour_addr"] = filter.red or 0, ["$pp_colour_addg"] = 0,
                ["$pp_colour_addb"] = filter.blue or 0, ["$pp_colour_brightness"] = C.exposure,
                ["$pp_colour_contrast"] = 1, ["$pp_colour_colour"] = filter.color or 1,
                ["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0})
            cam.End2D(); started2D = false
        end
        if photo == true then
            local jpeg = render.Capture({format = "jpeg", quality = 92, x = 0, y = 0, w = w, h = h, alpha = false})
            C.pendingThumb = C.ThumbJPEG(target, w / target:Width(), h / target:Height())
            return jpeg
        end
        if not full and C.rec then captureVideoFrame(target, w, h) end
        return true
    end, debug.traceback)
    if flagOwner then flagOwner.camSelfieRender = nil end
    if started2D then cam.End2D() end
    if pushed then render.PopRenderTarget() end
    C.rendering = false
    if not ok then
        C.problem = "Camera could not render. Close and reopen it."
        C.validFrame = nil
        C.Cancel()
        C.failed = true
        if C.rec then C.StopRecording() end
        ErrorNoHalt("[GoobOS Camera] " .. tostring(result) .. "\n")
        return false
    end
    C.problem = nil
    if not full then C.validFrame = RealTime(); C.frameW, C.frameH = w, h; return true end
    if photo == "hold" then return true end
    return C.FinishPhoto(result, w, h)
end

-- Photo mode shutter: save the full-size frame held in the photo RT when Photo mode was switched on,
-- so the saved photo is exactly the moment the viewfinder is showing.
function C.CaptureHeld()
    local target = C.photoTarget
    if not target or not C.frozenAt then return false end
    local w, h = C.Width, C.Height
    local pushed = false
    local ok, jpeg = pcall(function()
        render.PushRenderTarget(target, 0, 0, w, h); pushed = true
        local data = render.Capture({format = "jpeg", quality = 92, x = 0, y = 0, w = w, h = h, alpha = false})
        C.pendingThumb = C.ThumbJPEG(target, w / target:Width(), h / target:Height())
        return data
    end)
    if pushed then render.PopRenderTarget() end
    return C.FinishPhoto(ok and jpeg or nil, w, h)
end

-- ---------------------------------------------------------------------------------------------------
-- Video clips
-- ---------------------------------------------------------------------------------------------------
function C.ValidClip(id)
    return isstring(id) and #id < 60 and id:match("^clip_%d+_%d+$") ~= nil
end

function C.ClipPath(id, suffix) return C.VideoDirectory .. "/" .. id .. (suffix or ".dat") end

function C.Videos()
    local found = file.Find(C.VideoDirectory .. "/clip_*.dat", "DATA") or {}
    local clips, bytes = {}, 0
    for _, name in ipairs(found) do
        local id = name:match("^(.-)%.dat$")
        if C.ValidClip(id) then
            local size = math.max(0, file.Size(C.ClipPath(id), "DATA") or 0)
                + math.max(0, file.Size(C.ClipPath(id, ".thumb.jpg"), "DATA") or 0)
            local meta = util.JSONToTable(file.Read(C.ClipPath(id, ".json"), "DATA") or "") or {}
            clips[#clips + 1] = {id = id, kind = "video", bytes = size, time = file.Time(C.ClipPath(id), "DATA") or 0,
                duration = tonumber(meta.duration) or 0, frames = tonumber(meta.count) or 0}
            bytes = bytes + size
        end
    end
    table.sort(clips, function(a, b)
        if a.time == b.time then return a.id > b.id end
        return a.time > b.time
    end)
    return clips, bytes
end

function C.ClipThumb(id)
    local key = "clip:" .. tostring(id)
    local mat = C.thumbMats[key]
    if mat ~= nil then return mat or nil end
    mat = C.ValidClip(id) and file.Exists(C.ClipPath(id, ".thumb.jpg"), "DATA")
        and Material("../data/" .. C.ClipPath(id, ".thumb.jpg"), "smooth") or nil
    C.thumbMats[key] = (mat and not mat:IsError()) and mat or false
    return C.thumbMats[key] or nil
end

function C.DeleteClip(id)
    if not C.ValidClip(id) then return false end
    if C.saving and C.saving.id == id then return false end
    file.Delete(C.ClipPath(id))
    if file.Exists(C.ClipPath(id), "DATA") then return false end
    file.Delete(C.ClipPath(id, ".json"))
    file.Delete(C.ClipPath(id, ".thumb.jpg"))
    C.thumbMats["clip:" .. id] = nil
    if C.lastClip == id then C.lastClip = nil; C.lastKind = "photo" end
    C.galleryRevision = C.galleryRevision + 1
    return true
end

function C.StartRecording()
    if C.rec then return false end
    if C.saving then C.Note("Still saving the last clip…"); return false end
    if not C.Tester() or not C.Active() or IsValid(C.gallery) then return false end
    local reason = C.Blocked()
    if reason then C.Note(reason); return false end
    if C.KillcamOwnsScreen() then C.Note("Finish the replay to use Camera."); return false end
    local clips, used = C.Videos()
    if #clips >= C.VideoMaxClips or used >= C.VideoMaxBytes - 1024 * 1024 then
        C.Note("Clip storage is full. Delete a clip to make room.")
        return false
    end
    C.Cancel()
    C.freeze = false
    local now = RealTime()
    C.rec = {frames = {}, times = {}, bytes = 0, started = now, nextAt = now, cost = 0, maxCost = 0, captures = 0,
        failed = 0, limit = math.min(C.VideoMemoryCap, C.VideoMaxBytes - used), context = C.Context(),
        mode = C.mode, filter = C.Filters[C.filter] and C.Filters[C.filter].name or "Natural"}
    C.nextFrame = 0
    surface.PlaySound("buttons/blip1.wav")
    return true
end

-- Stop and queue the clip for writing (C.PumpSave). Frames stay in memory until they are on disk.
function C.StopRecording(note)
    local rec = C.rec
    if not rec then return false end
    C.rec = nil
    rec.stopped = RealTime()
    if #rec.frames < 2 then
        C.Note("Clip too short. Nothing was saved.")
        return false
    end
    C.saving = {rec = rec, index = 0}
    C.Note(note or "Saving your clip…")
    surface.PlaySound("buttons/blip1.wav")
    return true
end

local function failSave(s, text)
    if s.handle then pcall(s.handle.Close, s.handle) end
    if s.path and file.Exists(s.path, "DATA") then file.Delete(s.path) end
    C.saving = nil
    C.Note(text)
end

-- Write the queued clip in steps of at most `budget` seconds: header, then length-prefixed frames
-- (u32 ms timestamp, u32 byte count, JPEG bytes), then the .json sidecar and the thumbnail.
function C.PumpSave(budget)
    local s = C.saving
    if not s then return end
    local rec = s.rec
    local deadline = SysTime() + (budget or 0.002)
    if not s.handle then
        file.CreateDir(C.VideoDirectory)
        for _ = 1, 1000 do
            C.serial = C.serial + 1
            local id = "clip_" .. os.time() .. "_" .. string.format("%06d", C.serial)
            if not file.Exists(C.ClipPath(id), "DATA") then s.id = id; break end
        end
        if not s.id then return failSave(s, "Could not allocate a clip filename.") end
        s.path = C.ClipPath(s.id)
        s.handle = file.Open(s.path, "wb", "DATA")
        if not s.handle then return failSave(s, "Could not save clip. Check available disk space.") end
        s.handle:Write(C.VideoMagic)
        s.handle:WriteULong(#rec.frames)
        s.expected = #C.VideoMagic + 4
    end
    while s.index < #rec.frames do
        s.index = s.index + 1
        local frame = rec.frames[s.index]
        s.handle:WriteULong(rec.times[s.index])
        s.handle:WriteULong(#frame)
        s.handle:Write(frame)
        s.expected = s.expected + 8 + #frame
        rec.frames[s.index] = false -- release the memory as soon as it is on disk
        if SysTime() >= deadline and s.index < #rec.frames then return end
    end
    s.handle:Close()
    s.handle = nil
    if file.Size(s.path, "DATA") ~= s.expected then return failSave(s, "Could not save clip. Check available disk space.") end
    local count = #rec.frames
    local duration = (rec.times[count] or 0) / 1000
    local expectedFrames = math.max(count, math.floor(duration * C.VideoFPS) + 1)
    pcall(file.Write, C.ClipPath(s.id, ".json"), util.TableToJSON({version = 1, fps = C.VideoFPS, count = count,
        duration = duration, width = C.VideoWidth, height = C.VideoHeight, dropped = expectedFrames - count,
        capture_ms_avg = math.floor(rec.cost * 100000) / 100, capture_ms_max = math.floor(rec.maxCost * 100000) / 100,
        time = os.time(), map = game.GetMap(), mode = rec.mode, filter = rec.filter}))
    if isstring(rec.thumb) and rec.thumb:sub(1, 2) == SOI then pcall(file.Write, C.ClipPath(s.id, ".thumb.jpg"), rec.thumb) end
    C.thumbMats["clip:" .. s.id] = nil
    C.lastClip = s.id
    C.lastKind = "clip"
    C.galleryRevision = C.galleryRevision + 1
    C.saving = nil
    C.Note(string.format("Clip saved to your gallery · %.1f s", duration))
end

-- ---------------------------------------------------------------------------------------------------
-- Framing mode (tester-locked): the phone stays open but hands mouse + keyboard back to the game, so
-- mouse-look, WASD, crouch, sprint and jump all work while a HUD viewfinder shows the shot.
-- ---------------------------------------------------------------------------------------------------
C.FramingDebounce = 0.3

local function setAppInput(enabled)
    local phone, fullscreen = C.phone, C.fullscreen
    if enabled and not (IsValid(phone) and phone:GetActive()) then return end
    if IsValid(phone) then
        phone:SetMouseInputEnabled(enabled)
        phone:SetKeyboardInputEnabled(enabled)
    end
    if IsValid(fullscreen) then
        fullscreen:SetVisible(enabled)
        fullscreen:SetMouseInputEnabled(enabled)
        fullscreen:SetKeyboardInputEnabled(enabled)
    end
    if enabled then
        local top = IsValid(fullscreen) and fullscreen or phone
        top:MakePopup()
        local focus = IsValid(fullscreen) and fullscreen or C.root
        if IsValid(focus) then focus:RequestFocus() end
    else
        -- Same release ZChat's own close path does (cl_zchat.lua SetActive(false)), minus closing the phone.
        gui.EnableScreenClicker(false)
    end
end

function C.EnterFraming()
    if C.framing then return true end
    if not C.Tester() or not C.Active() or IsValid(C.gallery) then return false end
    if RealTime() - (C.framingChangedAt or -10) < C.FramingDebounce then return false end
    local media = A.Media
    if media and IsValid(media.Panel) and media.Panel:IsVisible() then return false end
    if C.KillcamOwnsScreen() then C.Note("Finish the replay to use Camera."); return false end
    local reason = C.Blocked()
    if reason then C.Note(reason); return false end
    C.Cancel()
    C.freeze = false
    C.pan, C.orbit = Angle(0, 0, 0), Angle(0, 0, 0)
    C.framing = true
    C.framingChangedAt = RealTime()
    C.framingContext = C.Context()
    C.nextFrame = 0
    setAppInput(false)
    return true
end

function C.ExitFraming(note)
    if not C.framing then return false end
    C.framing = false
    C.framingChangedAt = RealTime()
    C.framingContext = nil
    setAppInput(true)
    if note then C.Note(note) end
    return true
end

-- Every frame while framing: leave on anything that means "not now". Returns the exit reason (tests).
function C.FramingGuard()
    if not C.framing then return nil end
    local why
    if not C.Active() then why = "closed"
    elseif C.KillcamOwnsScreen() then why = "replay"
    elseif C.Blocked() then why = "blocked"
    elseif C.Context() ~= C.framingContext then why = "context"
    elseif IsValid(C.gallery) then why = "gallery"
    elseif gui.IsGameUIVisible() then
        -- Esc opens the game menu in GMod; while framing it means "back to the phone", like Esc in the app.
        gui.HideGameUI()
        why = "escape"
    end
    -- Deliberately no "cursor became visible" exit: a vote or menu popup takes the mouse while it is up and
    -- framing simply resumes when it closes (and a wrong guess about vgui cursor state cannot kill framing).
    if not why then return nil end
    local note = (why == "blocked" and C.Blocked()) or (why == "replay" and "Camera paused for the replay.") or nil
    C.ExitFraming(note)
    return why
end

-- Recording limits, checked every frame (also while the phone is in cursor mode).
function C.RecordingGuard()
    local rec = C.rec
    if not rec then return nil end
    if RealTime() - rec.started >= C.VideoMaxSeconds then
        C.StopRecording("20 second limit reached. Saving your clip…"); return "limit"
    end
    if not C.Active() or C.Blocked() or C.KillcamOwnsScreen() or IsValid(C.gallery) or C.Context() ~= rec.context then
        C.StopRecording("Recording stopped. Saving your clip…"); return "stopped"
    end
    return nil
end

-- Framing binds. PlayerBindPress fires once per press (wiki: "The third argument will always be true"),
-- so there is no edge state to track; returning true keeps the bind away from weapons and the selector.
local FRAMING_SWALLOW = {["+attack"] = true, ["+attack2"] = true, ["+reload"] = true, ["+use"] = true,
    invprev = true, invnext = true, lastinv = true, ["impulse 100"] = true, ["+showscores"] = true,
    ["+zoom"] = true, ["+menu_context"] = true}
function C.FramingBind(bind)
    if not C.framing then return nil end
    local b = string.lower(tostring(bind or "")):match("^%s*(.-)%s*$")
    if b == "+attack" then C.Trigger()
    elseif b == "+attack2" or b == "+showscores" then C.ExitFraming()
    elseif b == "+reload" then C.ToggleCaptureMode()
    elseif b == "impulse 100" then C.Flip()
    elseif b == "invprev" then C.ZoomStep(1)
    elseif b == "invnext" then C.ZoomStep(-1)
    elseif not (FRAMING_SWALLOW[b] or b:match("^slot%d+$")) then return nil end
    return true
end
function C.Shutdown()
    C.Close()
    if C.saving then C.PumpSave(math.huge) end
end

-- PostRender never takes over the main world view. Rendering is entirely offscreen.
hook.Add("PostRender", "GoobOS.Camera.Viewfinder", function()
    if C.rendering or not C.Active() or C.gallery or C.failed then return end
    local reason = C.Blocked()
    if gui.IsGameUIVisible() or not system.HasFocus() then reason = "Camera paused." end
    if reason then C.problem = reason; C.validFrame = nil; C.Cancel(); return end
    local context = C.Context()
    if context ~= C.context then
        C.context = context; C.Cancel(); C.validFrame = nil; C.pan = Angle(0, 0, 0)
        C.frozenAt = nil; C.holdPending = C.freeze or nil
        if not LocalPlayer():Alive() then C.SetMode("world") end
    end
    local now = RealTime()
    C.StepZoom()
    if C.deadline and now >= C.deadline then C.deadline = nil; C.pending = true end
    -- Photo mode (freeze): on the frame it is switched on, render the preview AND a full-size frame into the
    -- photo RT, then stop refreshing. The shutter saves that held frame, so the photo is what the viewfinder shows.
    if C.freeze ~= (C.freezeSeen or false) then
        C.freezeSeen = C.freeze
        C.frozenAt = nil
        C.holdPending = C.freeze or nil
    end
    if not C.pending and not C.holdPending and now < C.nextFrame then return end
    C.nextFrame = now + (C.LiveCadence() and C.LiveInterval or (IsValid(C.fullscreen) and 1 / 30 or 1 / 15))
    local base = viewOverride
    if not istable(base) or not isvector(base.origin) or not isangle(base.angles) then base = render.GetViewSetup() end
    local photo = C.pending and C.shotContext == context
    C.pending = nil
    if C.holdPending then
        C.holdPending = nil
        if C.Render(base, false) and C.Render(base, "hold") then C.frozenAt = now end
    elseif not C.freeze then
        C.Render(base, false)
    end
    if photo and not C.Blocked() then
        if C.freeze then C.CaptureHeld()
        elseif C.validFrame then C.Render(base, true) end
    end
end)

-- Framing exits, recording limits and the clip writer run every frame, even with the phone in cursor mode.
hook.Add("Think", "GoobOS.Camera.Framing", function()
    C.FramingGuard()
    C.RecordingGuard()
    if C.saving then C.PumpSave() end
end)

hook.Add("PlayerBindPress", "GoobOS.Camera.Framing", function(_, bind)
    return C.FramingBind(bind)
end, HOOK_HIGH) -- ULib priority: ahead of the weapon selector's wheel/slot handling; vanilla ignores it

-- Framing zoom narrows the shot, not the eye: scale mouse-look by 1/zoom so aiming the viewfinder stays steady.
hook.Add("hg_AdjustMouseSensitivity", "GoobOS.Camera.Framing", function()
    if C.framing and C.mode ~= "selfie" and C.zoom > 1.01 then return 1 / C.zoom end
end)

-- Prevent shutter/drag keys from leaking into weapons or spectator target cycling.
local STRIP_APP = {IN_ATTACK, IN_ATTACK2, IN_RELOAD, IN_USE, IN_JUMP}
local STRIP_FRAMING = {IN_ATTACK, IN_ATTACK2, IN_RELOAD, IN_USE} -- framing keeps jump: movement belongs to the player
hook.Add("CreateMove", "GoobOS.Camera.Input", function(cmd)
    if not C.Active() or C.ReplayActive() then return end
    for _, key in ipairs(C.framing and STRIP_FRAMING or STRIP_APP) do cmd:RemoveKey(key) end
end)
