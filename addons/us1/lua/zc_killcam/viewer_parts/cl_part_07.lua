return string.sub([========[x    if e ~= ahead or weight < 0.3 then return end
    if e.zcEyeYaw == nil then
        local _, _, _, yw, pt = V.StateAt(actor, e[1])
        e.zcEyeYaw, e.zcEyePitch = yw or false, pt
    end
    if not e.zcEyeYaw then return end
    local _, _, _, yawNow, pitchNow = V.StateAt(actor, cs)
    if not yawNow then return end
    local _, barrel = muzzleOf(g.zcGun, g.zcWeapon)
    if not barrel then return end
    local errY = math.AngleDifference(e[12] / 100 + math.AngleDifference(yawNow, e.zcEyeYaw), barrel.y)
    local errP = math.AngleDifference(e[13] / 100 + (pitchNow - e.zcEyePitch), barrel.p)
    g.zcFixY = math.Clamp((g.zcFixY or 0) + errY / weight * 0.5, -15, 15)
    g.zcFixP = math.Clamp((g.zcFixP or 0) + errP / weight * 0.5, -15, 15)
end

V.NamesCV = CreateClientConVar("zc_killcam_names", "1", true, false, "Show recorded Steam names above replay bodies")
function V.ReplayNameAnchor(actor, ghost)
    if not actor or not isstring(actor.steam) or actor.steam == "" or not IsValid(ghost) then return end
    local body = IsValid(ghost.zcRag) and ghost.zcRag or ghost
    if body:GetNoDraw() then return end
    local bone = body:LookupBone("ValveBiped.Bip01_Head1")
    local m = bone and body:GetBoneMatrix(bone)
    local pos = m and m:GetTranslation() or body:GetPos() + Vector(0, 0, body == ghost and 72 or 18)
    return pos + Vector(0, 0, 12), string.gsub(actor.steam, "[%c]", " ")
end
function V.DrawReplayNames()
    if not L or not V.NamesCV:GetBool() then return end
    local view, shown = render.GetViewSetup(true), 0
    for i, g in pairs(L.ghosts or {}) do
        if i ~= L.clip.pov or V.BulletWeight(L.bullet) > 0.5 then
            local pos, name = V.ReplayNameAnchor(L.clip.actors[i], g)
            if pos and pos:DistToSqr(view.origin) < 1500 ^ 2 then
                local tr = util.TraceLine({start=view.origin, endpos=pos, mask=MASK_SOLID_BRUSHONLY})
                if not tr.Hit and not tr.StartSolid then
                    local scale = 0.08 * math.Clamp(pos:Distance(view.origin) / 300, 1, 3)
                    cam.Start3D2D(pos, Angle(0, view.angles.y - 90, 90), scale)
                    surface.SetFont("ZCKC.LifeBody")
                    local tw, th = surface.GetTextSize(name)
                    surface.SetDrawColor(8, 12, 18, 205) surface.DrawRect(-tw / 2 - 9, -th / 2 - 4, tw + 18, th + 8)
                    draw.SimpleText(name, "ZCKC.LifeBody", 0, 0, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    cam.End3D2D()
                    shown = shown + 1
                    if shown >= 32 then break end
                end
            end
        end
    end
end

local beamMat, glowMat = Material("sprites/rollermine_shock"), Material("sprites/light_glow02_add_noz")
V.BulletGlow = Material("sprites/light_glow02_add") -- flight respects walls; only the wound diagnostic ignores depth
hook.Add("PostDrawOpaqueRenderables", "ZCKillcam.Life", function(_, sky)
    if sky or not L or L.over or L.waiting then return end
    if V.SceneDepth == 0 and V.UISide() then return end -- postround_20260925: a side card's live world gets none of the replay
    local clip, cs = L.clip, L.cs
    for _, g in pairs(L.ghosts or {}) do
        if IsValid(g) and (g.zcAtts or g.zcAccess or (g.zcWeapon and g.zcWeapon.WorldModelExchange)) then -- accessories alone are reason enough: zcAtts is set ONLY when the gun has attachments
            local ok, err = pcall(drawDress, g)
            if not ok and not L.dressErr then L.dressErr = true print("[Killcam] attachments: " .. tostring(err)) end
        end
    end
    for i, g in pairs(L.ghosts or {}) do
        if IsValid(g) and g.zcFamily == "gun" and g.zcWeapon and IsValid(g.zcGun) and not g.zcGun:GetNoDraw() and clip.actors[i] then
            local ok, err = pcall(aimFix, g, clip.actors[i], i, clip, g.zcPoseCs or cs)
            if not ok and not L.fixErr then L.fixErr = true print("[Killcam] barrel line: " .. tostring(err)) end
        end
    end
    if V.SceneDepth > 0 and not L.goreErr then
        local ok, err = pcall(V.Gore.Draw, L)
        if not ok then L.goreErr = true V.Gore.Clear() print("[Killcam] gore effects disabled for clip: " .. tostring(err)) end
    end
    V.DrawReplayNames()
    -- What really happened to each bullet (events [9..13], recorder rec21): a shot leaves the MUZZLE along the GUN - not the
    -- eye along the view - and a hit lands where the damage did. Shots flash a tracer along the true line; a hit's red line
    -- runs from that shot's true source to the true landing point. Clips without the fields keep the old eye-to-chest line.
    local o = clip.origin
    -- While the killing round is being flown, ITS two lines are withheld: both are drawn the instant they happen, and
    -- either one would put the whole trajectory on screen before the round has crossed it.
    local b = L.bullet
    local flying = b and not b.done and b.at ~= nil
    local events = clip.events
    for n = V.EvFrom(clip, cs - 50), #events do -- replay_v1 P3: from event 1 for a death clip, as before
        local e = events[n]
        if clip.round and e[1] > cs then break end -- a round clip is long and sorted; a death clip is scanned whole, as always
        local age = cs - e[1]
        local mine = flying and (e == b.shot or e == b.hit) -- withheld: the round itself is drawn below instead
        if not mine and e[2] == 1 and e[9] and age >= 0 and age <= 12 then
            local from = Vector(o[1] + e[9] / 10, o[2] + e[10] / 10, o[3] + e[11] / 10)
            if not e.zcEnd then
                local dir = Angle(e[13] / 100, e[12] / 100, 0):Forward()
                e.zcEnd = util.TraceLine({start = from, endpos = from + dir * 12000, mask = MASK_SHOT, filter = player.GetAll()}).HitPos
            end
            render.DrawLine(from, e.zcEnd, Color(255, 225, 140, 255 - age * 18), true)
        elseif not mine and e[2] == 2 and age >= 0 and age <= 50 and clip.actors[e[3]] and clip.actors[e[4]] then
            local ax, ay, az, _, _, _, _, _, eye = V.StateAt(clip.actors[e[3]], e[1])
            local bx, by, bz = V.StateAt(clip.actors[e[4]], e[1])
            if ax and bx then
                local from, to = Vector(o[1] + ax, o[2] + ay, o[3] + az + (eye or 64) - 6), Vector(o[1] + bx, o[2] + by, o[3] + bz + 40)
                if e[9] then to = V.HitPoint(clip, e) end -- A1
                for k = n - 1, math.max(n - 12, 1), -1 do -- the shot this hit came from: the same shooter's latest, no older than 30 cs
                    local s = clip.events[k]
                    if s[2] == 1 and s[3] == e[3] then
                        if s[9] and e[1] - s[1] <= 30 then from = Vector(o[1] + s[9] / 10, o[2] + s[10] / 10, o[3] + s[11] / 10) end
                        break
                    end
                end
                render.DrawLine(from, to, Color(255, 70, 60), true)
            end
        end
    end
    -- The round. Only the track it has ALREADY crossed is drawn - drawing the rest would hand over the ending - and the
    -- round itself stays small: it reads because it is slow and the camera is on it, not because it is big.
    if flying then
        if V.ShotVisual and V.ShotVisual.Draw(L,b) then return end
        if b.cinematic and V.Cinema then V.Cinema.DrawWorld(L, b) end
        if not b.cinematic and b.body and b.body.recorded and V.Penetration then V.Penetration.Draw(b,V.BulletWeight(b)) end
        local fade = V.BulletWeight(b)
        local tail = b.at - b.dir * math.min(24, b.span * b.p)
        render.SetMaterial(beamMat)
        render.DrawBeam(b.from, b.at, 1, 0, 1, Color(255, 185, 90, 65 * fade))
        render.DrawBeam(tail, b.at, 3, 0, 1, Color(255, 195, 110, 180 * fade))
        render.DrawBeam(tail, b.at, 0.7, 0, 1, Color(255, 248, 219, 255 * fade))
        render.SetMaterial(V.BulletGlow)
        render.DrawSprite(b.at, 5, 5, Color(255, 228, 170, 210 * fade))
        if b.landed then
            local pulse = 1 - V.BulletEase((b.t - BULLET_FLY) / 0.25)
            render.DrawSprite(b.to, 5 + 15 * pulse, 5 + 15 * pulse, Color(255, 210, 155, 170 * fade))
            if b.body and not b.body.recorded then
                -- Deliberate diagnostic overlay, bounded to this recorded wound segment. Normal
                -- depth-tested flight above; only this body inspection can show through the body.
                local finish = LerpVector(b.bodyP, b.body.first, b.body.last)
                -- wound_fx: a faint red wisp and soft glows, not a neon line between two wire spheres
                if V.Wound then V.Wound.Wisp(b.body.first, finish, b.t, 0.4, b.side, b.up, 0.5, 0.9, 0.3, V.Wound.Red, 120 * fade) end
                render.SetMaterial(V.BulletGlow)
                render.DrawSprite(b.body.first, 2.4, 2.4, Color(255, 200, 170, 180 * fade))
                render.DrawSprite(finish, 2.8, 2.8, Color(255, 110, 90, 180 * fade))
            end
        end
    end
end)

-- Lasers and weapon lights, as SWEP:DrawLaser draws them (homigrad_base/sh_attachment.lua:437): from the fitted underbarrel
-- unit, offsetPos / offsetAng along it. Numbers are the game's. The beam stops at the map and at props, not at other ghosts.
local lampMat = Material("effects/flashlight/soft") -- beamMat and glowMat are hoisted above the draw pass, which also uses them
local clearCol = Color(0, 0, 0, 0)
local BODY_MINS, BODY_MAXS = Vector(-10, -10, 0), Vector(10, 10, 70)
local function dropLamp(g)
    if g.zcLamp and g.zcLamp:IsValid() then g.zcLamp:Remove() end
    g.zcLamp = nil
end
local function beams(g, filter)
    local data, mode = g.zcLaserData, g.zcBeam or 0
    if not data or mode == 0 or not g.zcLaserPos then dropLamp(g) return end
    local pos, ang = LocalToWorld(data.offsetPos or vector_origin, data.offsetAng or angle_zero, g.zcLaserPos, g.zcLaserAng)
    local fwd = ang:Forward()
    local view = render.GetViewSetup(true)
    local clear = not util.TraceLine({start = pos + fwd * 10, endpos = view.origin, filter = filter, mask = MASK_VISIBLE}).Hit
    if mode >= 2 and data.supportFlashlight and (not data.nvgFlashlight or LocalPlayer().NVGEnabled) then
        local lamp = g.zcLamp
        if not (lamp and lamp:IsValid()) then lamp = ProjectedTexture() g.zcLamp = lamp end
        if lamp and lamp:IsValid() and not scoping then
            lamp:SetTexture((data.mat or lampMat):GetTexture("$basetexture"))
            lamp:SetFarZ(data.farZ or 1500)
            lamp:SetHorizontalFOV(data.size or 50)
            lamp:SetVerticalFOV(data.size or 50)
            lamp:SetConstantAttenuation(data.brightness2 or 1)
            lamp:SetLinearAttenuation(data.brightness or 50)
            lamp:SetPos(pos + fwd * 10)
            lamp:SetAngles(ang)
            lamp:Update()
        end
        local deg = math.min(fwd:Dot(view.angles:Forward()), 0)
        if deg < 0 and clear then
            render.SetMaterial(glowMat)
            render.DrawSprite(pos + fwd * 0.5, 200 * deg, 20 * deg, color_white)
            render.DrawSprite(pos + fwd * 0.5, 50 * deg, 150 * deg, color_white)
        end
    else
        dropLamp(g)
    end
    if mode % 2 == 1 and data.color then
        local tr = util.TraceLine({start = pos, endpos = pos + fwd * 10000, filter = filter, mask = MASK_SHOT})
        local hitPos, best = tr.HitPos, tr.Fraction
        for _, o in pairs(L.ghosts) do -- replay bodies are client models no trace can see: a box each
            if o ~= g and IsValid(o) and not o:GetNoDraw() then
                local at, _, frac = util.IntersectRayWithOBB(pos, fwd * 10000, o:GetPos(), o:GetAngles(), BODY_MINS, BODY_MAXS)
                if at and frac and frac < best then hitPos, best = at, frac end
            end
        end
        render.SetMaterial(beamMat)
        render.DrawBeam(pos, hitPos, 5, 0, 800, ColorAlpha(data.color, 20))
        local mine = g.zcPov -- the game enlarges the dot for the player holding it
        local distance = math.max(pos:Distance(hitPos) / 300, 0.2)
        render.SetStencilWriteMask(0xFF)
        render.SetStencilTestMask(0xFF)
        render.SetStencilReferenceValue(0)
        render.SetStencilCompareFunction(STENCIL_ALWAYS)
        render.SetStencilPassOperation(STENCIL_KEEP)
        render.SetStencilFailOperation(STENCIL_KEEP)
        render.SetStencilZFailOperation(STENCIL_KEEP)
        render.ClearStencil()
        render.SetStencilEnable(true)
        render.SetStencilReferenceValue(1)
        render.SetStencilCompareFunction(STENCIL_NOTEQUAL)
        render.SetStencilPassOperation(STENCIL_REPLACE)
        render.SetColorMaterial()
        render.DrawSphere(hitPos, math.min(5 * (data.laserSize or 1) * distance, 20), 20, 20, clearCol)
        render.SetStencilCompareFunction(STENCIL_EQUAL)
        render.SetMaterial(glowMat)
        if mine then distance = distance * 1.5 end
        local div = distance / (mine and 6 or 2.5) * (data.laserSize ~= nil and (data.laserSize / 10) or 1)
        local size = math.min(5 * (data.laserSize or 1) * distance, mine and 120 or 30)
        render.DrawSprite(hitPos, size, size, Color(data.color.r / div, data.color.g / div, data.color.b / div))
        render.SetStencilEnable(false)
        local deg = -(math.ease.InBack(-fwd:Dot(view.angles:Forward()) - 0.355) * 40)
        if deg < 0 and clear then
            local far = math.max(math.min(pos:Distance(view.origin) / 200, 3), 1)
            render.SetMaterial(glowMat)
            render.DrawSprite(pos + fwd * 3, 125 * deg * far, 55 * deg * far, data.color)
            render.DrawSprite(pos + fwd * 3, 55 * deg * far, 125 * deg * far, data.color)
        end
    end
end

-- The holographic reticle, for the eyes the replay looks through.
hook.Add("PostDrawTranslucentRenderables", "ZCKillcam.LifeOptic", function(_, sky)
    if sky or not L or L.over or L.waiting or not L.ghosts then return end
    if V.SceneDepth == 0 and V.UISide() then return end -- postround_20260925: replay beams stay in the replay's pass
    local filter
    for _, b in pairs(L.ghosts) do
        if IsValid(b) and (b.zcLamp or (b.zcBeam or 0) > 0) then
            if not IsValid(b.zcGun) or b.zcGun:GetNoDraw() then b.zcBeam = 0 end
            filter = filter or player.GetAll() -- the living are not in the replay: nothing stops on them
            local ok, err = pcall(beams, b, filter)
            render.SetStencilEnable(false)
            if not ok and not L.beamErr then L.beamErr = true print("[Killcam] laser / light: " .. tostring(err)) end
        end
    end
    local g = L.ghosts[L.clip.pov or 0]
    if not IsValid(g) or not g.zcAtts or not g.zcMuzzle or not IsValid(g.zcGun) or g.zcGun:GetNoDraw() then return end
    for _, a in ipairs(g.zcAtts) do
        if IsValid(a.glass) and IsValid(a.model) and not a.merged then
            local ok, err = pcall(reticle, a, g.zcMuzzle)
            render.SetBlend(1)
            render.SetStencilEnable(false) -- whatever happened in there
            if not ok and not L.dressErr then L.dressErr = true print("[Killcam] reticle: " .. tostring(err)) end
        end
    end
end)

local YOU_HALO = Color(90, 170, 255) -- hoisted: this runs every frame, and a Color per frame is garbage per frame
hook.Add("PreDrawHalos", "ZCKillcam.Life", function()
    if not L or L.over or L.waiting then return end
    if V.SceneDepth == 0 and V.UISide() then return end -- postround_20260925: no replay halo in a side card's live world
    local g = L.ghosts[L.clip.target or 0]
    if not IsValid(g) then return end
    -- Halo whichever body is ON SCREEN. While the victim is down the ghost is hidden and its ragdoll is drawn in
    -- its place (poseRagdoll), so reading GetNoDraw off the ghost alone made the "this is you" marker wink out at
    -- exactly the moment it matters most: the death the whole clip was cut around. Same root cause as the
    -- accessories going with the ghost - the ghost is not always the body.
    local rag = g.zcRag
    local body = (IsValid(rag) and not rag:GetNoDraw()) and rag or g
    if not body:GetNoDraw() then halo.Add({body}, YOU_HALO, 1, 1, 2, true, true) end
end)

----------------------------------------------------------------- overlay
-- Styled after the gamemode's own HUD and menus (read from its source 2026-09-21): its font choice
-- (hg_font, Bahnschrift by default) at ScreenScale sizes, white text, near-black translucent panels
-- and the dark red outline its forgiveness menu uses. No rounded corners anywhere, as there.
local function face()
    local cv = GetConVar("hg_font")
    local name = cv and cv:GetString() or ""
    return name ~= "" and name or "Bahnschrift"
end
local function fonts()
    V.FontGen = (V.FontGen or 0) + 1 -- P7: cached text measurements are stamped with this and redone when it moves
    surface.CreateFont("ZCKC.LifeTitle", {font = face(), size = ScreenScale(16), weight = 400, antialias = true})
    surface.CreateFont("ZCKC.LifeHead", {font = face(), size = ScreenScale(10), weight = 400, antialias = true})
    surface.CreateFont("ZCKC.LifeBody", {font = face(), size = ScreenScale(7), weight = 400, antialias = true})
    surface.CreateFont("ZCKC.LifeSmall", {font = face(), size = ScreenScale(6), weight = 400, antialias = true})
end
fonts()
hook.Add("OnScreenSizeChanged", "ZCKillcam.LifeFonts", fonts)
cvars.AddChangeCallback("hg_font", fonts, "ZCKillcam.LifeFonts")

-- P6 2026-09-24: the ZCity tokens (work/loader/goobos_rework/mockups: --muted, --text, --down, --green, --warn, --glass, --main)
local DIM, TEXT, RED, BLUE, GREEN, AMBER = Color(165, 165, 165), Color(225, 225, 225), Color(194, 58, 61), Color(70, 130, 180), Color(119, 218, 181), Color(215, 153, 74)
local PANEL, EDGE = Color(20, 17, 17, 214), Color(150, 0, 0, 235)
V.TagFill = V.TagFill or Color(20, 17, 17, 250)
-- P7 2026-09-24: key-hint rows, built once instead of every frame. keyRow caches each hint's measured widths on it.
V.Hints = V.Hints or {
    wait = {{"Q", "Skip"}, {"N", "Turn killcams off"}},
    over = {{"V", "Save replay"}, {"B", "Review top-down"}, {"Q", "Back to spectating"}, {"N", "Turn killcams off"}},
    overSaved = {{"V", "Saved"}, {"B", "Review top-down"}, {"Q", "Back to spectating"}, {"N", "Turn killcams off"}},
    skip = {{"Space", "Skip"}},
    highlight = {{"Space", "Skip"}, {"N", "Turn killcams off"}},
    -- playing: [1 + (report offered and 1 or 0) + (saved and 2 or 0)]
    play = {
        {{"V", "Save"}, {"Space", "Next hit"}, {"B", "Top-down"}, {"Q", "Back to spectating"}},
        {{"G", "Report this hit"}, {"V", "Save"}, {"Space", "Next hit"}, {"B", "Top-down"}, {"Q", "Back to spectating"}},
        {{"V", "Saved"}, {"Space", "Next hit"}, {"B", "Top-down"}, {"Q", "Back to spectating"}},
        {{"G", "Report this hit"}, {"V", "Saved"}, {"Space", "Next hit"}, {"B", "Top-down"}, {"Q", "Back to spectating"}},
    },
}
-- "0.25x slow motion", formatted only when the shown value changes (it eases every frame)
function V.RateText(rate)
    local r = (rate or 1) < 0.95 and math.floor(rate * 100 + 0.5) or 0
    if V.RateFor ~= r then V.RateFor, V.RateString = r, r > 0 and string.format("%.2fx slow motion", r / 100) or "" end
    return V.RateString
end
V.DimFill = V.DimFill or Color(20, 17, 17, 200)
V.UISounds = V.UISounds or CreateClientConVar("zc_killcam_ui_sounds", "1", true, false, "Soft sound cues when a killcam card or end card comes up", 0, 1)
function V.Ease(t) t = math.Clamp(t or 0, 0, 1) return t * t * (3 - 2 * t) end -- smoothstep, for every fade
V.LifeStyle = {panel = PANEL, edge = EDGE, text = TEXT, dim = DIM, red = RED}

local function panel(x, y, w, h, edge) -- P6: rounded glass card, the edge as a left accent (mockup cards)
    draw.RoundedBox(4, x, y, w, h, PANEL)
    if edge then draw.RoundedBoxEx(4, x, y, 3, h, edge, true, false, true, false) end
end

-- A tag in an outlined box; returns its width. align: 0 left, 1 centre, 2 right of x.
local function tagBox(text, x, y, colour, align)
    surface.SetFont("ZCKC.LifeSmall")
    local tw, th = surface.GetTextSize(text)
    local bw = tw + 16
    local bx = align == 1 and x - bw / 2 or (align == 2 and x - bw or x)
    draw.RoundedBox(4, bx, y, bw, th + 6, colour) -- P6: rounded pill, 1 px coloured rim
    draw.RoundedBox(4, bx + 1, y + 1, bw - 2, th + 4, V.TagFill)
    draw.SimpleText(text, "ZCKC.LifeSmall", bx + 8, y + 3, colour)
    return bw
end

-- Key hints as keycaps: {{"G", "Report this hit"}, ...}. centre = lay the row out around x.
local function keyRow(hints, x, y, centre)
    surface.SetFont("ZCKC.LifeSmall")
    if V.KeyGen ~= V.FontGen then V.KeyGen, V.KeyTh = V.FontGen, select(2, surface.GetTextSize("G")) end
    local th = V.KeyTh
    local gap, total = 18, 0
    for _, hint in ipairs(hints) do
        if hint.gen ~= V.FontGen then -- P7: measured once per font generation, not every frame
            hint.gen, hint.kw, hint.lw = V.FontGen, surface.GetTextSize(hint[1]) + 10, surface.GetTextSize(hint[2])
        end
        total = total + hint.kw + 6 + hint.lw + gap
    end
    if centre then x = x - (total - gap) / 2 end
    for _, hint in ipairs(hints) do
        draw.RoundedBox(4, x, y, hint.kw, th + 4, DIM) draw.RoundedBox(4, x + 1, y + 1, hint.kw - 2, th + 2, V.TagFill) -- P6: rounded keycap
        draw.SimpleText(hint[1], "ZCKC.LifeSmall", x + hint.kw / 2, y + 2, TEXT, TEXT_ALIGN_CENTER)
        draw.SimpleText(hint[2], "ZCKC.LifeSmall", x + hint.kw + 6, y + 2, DIM)
        x = x + hint.kw + 6 + hint.lw + gap
    end
end

local function weaponName(class) return (string.gsub(class or "unknown weapon", "^weapon_", "")) end

local function drawWaiting(w, seq)
    local ease = V.Ease((RealTime() - L.shownAt) / 0.2) -- P6: 0.4 s linear -> 0.2 s eased
    surface.SetAlphaMultiplier(ease)
    if L.waitGen ~= V.FontGen then -- P7: formatted and measured once
        L.waitGen = V.FontGen
        L.waitText = string.format("Your death replay is starting (%d moment%s)", #seq.instances, #seq.instances == 1 and "" or "s")
        surface.SetFont("ZCKC.LifeBody")
        L.waitW, L.waitH = surface.GetTextSize(L.waitText)
    end
    local text, tw, th = L.waitText, L.waitW, L.waitH
    local pw = math.max(tw + 40, ScreenScale(150))
    local x, y = w / 2 - pw / 2, ScreenScale(8)
    panel(x, y, pw, th * 2 + 26, EDGE)
    draw.SimpleText(text, "ZCKC.LifeBody", w / 2, y + 8, TEXT, TEXT_ALIGN_CENTER)
    keyRow(V.Hints.wait, w / 2, y + th + 14, true)
    tagBox("BETA", x + pw, y + th * 2 + 30, DIM, 2) -- the offer can be skipped, so the notice has to live here too
    surface.SetAlphaMultiplier(1)
end

local function drawOver(w, h, seq)
    local reported = 0
    for _ in pairs(L.reported or {}) do reported = reported + 1 end
    if L.overFor ~= reported then -- P7: the summary is rebuilt only when a report lands, not every frame
        L.overFor = reported
        local hits, dmg, who, attackers = 0, 0, {}, 0
        for _, it in ipairs(seq.instances) do
            hits, dmg = hits + (it.hits or 0), dmg + (tonumber(it.dmg) or 0)
            if not who[it.attacker or "?"] then who[it.attacker or "?"] = true attackers = attackers + 1 end
        end
        L.overLine = string.format("%d hit%s   ·   %d attacker%s   ·   %d damage", hits, hits == 1 and "" or "s", attackers, attackers == 1 and "" or "s", dmg)
            .. (reported > 0 and string.format("   ·   %d reported", reported) or "")
    end
    local y = h * 0.4
    tagBox("BETA", w / 2, y - ScreenScale(11), DIM, 1)
    draw.SimpleText("That was every hit you took this life", "ZCKC.LifeHead", w / 2, y, TEXT, TEXT_ALIGN_CENTER)
    local _, hh = surface.GetTextSize("A")
    draw.SimpleText(L.overLine, "ZCKC.LifeBody", w / 2, y + hh + 6, DIM, TEXT_ALIGN_CENTER)
    keyRow(L.saved and V.Hints.overSaved or V.Hints.over, w / 2, y + hh * 2 + 22, true)
    local bw = ScreenScale(70)
    local left = math.Clamp(1 - (RealTime() - L.overAt) / 8, 0, 1)
    surface.SetDrawColor(60, 60, 60, 255) surface.DrawRect(w / 2 - bw / 2, y + hh * 3 + 34, bw, 2)
    surface.SetDrawColor(TEXT) surface.DrawRect(w / 2 - bw / 2, y + hh * 3 + 34, bw * left, 2)
    draw.SimpleText("Returning to spectating", "ZCKC.LifeSmall", w / 2, y + hh * 3 + 42, DIM, TEXT_ALIGN_CENTER)
end

-- The round highlight: who, with what, how many - and a strip with a red mark at every kill.
local function drawHighlight(w, h, seq)
    local inst = L.inst
    if V.Cinema and V.Cinema.Enabled:GetBool() then return V.Cinema.DrawHighlight(w, h, L, weaponName(inst.wep)) end
    local pad, top, bottom = ScreenScale(10), ScreenScale(24), ScreenScale(22)
    surface.SetDrawColor(PANEL) surface.DrawRect(0, 0, w, top) surface.DrawRect(0, h - bottom, w, bottom)
    surface.SetDrawColor(EDGE) surface.DrawRect(0, top, w, 2) surface.DrawRect(0, h - bottom - 2, w, 2)
    draw.SimpleText("HIGHLIGHT OF THE ROUND", "ZCKC.LifeSmall", pad, ScreenScale(3), DIM)
    if L.hlGen ~= V.FontGen or L.hlFor ~= inst then -- P7: names, widths and the kill tag built once per instance
        L.hlGen, L.hlFor = V.FontGen, inst
        local kills = tonumber(seq.kills) or 1
        L.hlStar, L.hlWep = tostring(seq.star or inst.attacker), weaponName(inst.wep)
        L.hlKills = kills == 1 and ((seq.heads or 0) > 0 and "HEADSHOT KILL" or "1 KILL") or kills .. " KILLS"
        surface.SetFont("ZCKC.LifeHead")
        L.hlStarW = surface.GetTextSize(L.hlStar)
    end
    draw.SimpleText(L.hlStar, "ZCKC.LifeHead", pad, ScreenScale(9), TEXT)
    draw.SimpleText(L.hlWep, "ZCKC.LifeBody", pad + L.hlStarW + 14, ScreenScale(12), DIM)
    local killW = tagBox(L.hlKills, w - pad, ScreenScale(4), RED, 2)
    tagBox("BETA", w - pad - killW - 6, ScreenScale(4), DIM, 2)
    draw.SimpleText(V.RateText(L.rate), "ZCKC.LifeSmall", w - pad, ScreenScale(15), DIM, TEXT_ALIGN_RIGHT)
    local span = math.max(L.clip.last - L.clip.first, 1)
    local sx, sy, sw = pad, h - bottom + ScreenScale(5), w - pad * 2
    surface.SetDrawColor(60, 60, 60, 255) surface.DrawRect(sx, sy, sw, 3)
    surface.SetDrawColor(TEXT) surface.DrawRect(sx, sy, sw * math.Clamp((L.cs - L.clip.first) / span, 0, 1), 3)
    surface.SetDrawColor(RED)
    for _, e in ipairs(L.clip.events) do
        if e[2] == 3 and e[3] == L.clip.pov then surface.DrawRect(sx + sw * math.Clamp((e[1] - L.clip.first) / span, 0, 1) - 1, sy - 3, 2, 9) end -- 3 = death
    end
    keyRow(V.Hints.highlight, pad, h - ScreenScale(10))
end

function V.DrawBulletHUD(w, h)
    if V.Ballistics and V.Ballistics.Draw(w, h, L) then return end
    local b = L and L.bullet
    if b and b.cinematic and V.Cinema then return V.Cinema.DrawHUD(w, h, L) end
    local alpha = V.BulletWeight(b)
    if alpha <= 0 then return end
    local bw, bh = math.min(ScreenScale(116), w - 32), ScreenScale(24)
    local x, y = (w - bw) / 2, h - ScreenScale(66)
    surface.SetDrawColor(9, 15, 22, 210 * alpha) surface.DrawRect(x, y, bw, bh)
    surface.SetDrawColor(80, 199, 231, 210 * alpha) surface.DrawRect(x, y, 2, bh)
    local title = b.landed and (b.body and "RECORDED WOUND TRACE" or "IMPACT") or "BULLET TIME"
    local detail = b.landed and (b.body and "Simulation entry to trace end" or "Recorded impact point") or "Following the recorded shot"
    draw.SimpleText(title, "ZCKC.LifeSmall", w / 2, y + ScreenScale(3), Color(229, 239, 247, 255 * alpha), TEXT_ALIGN_CENTER)
    draw.SimpleText(detail, "ZCKC.LifeSmall", w / 2, y + ScreenScale(12), Color(151, 185, 201, 255 * alpha), TEXT_ALIGN_CENTER)
    surface.SetDrawColor(90, 211, 239, 230 * alpha)
    surface.DrawRect(x, y + bh - 2, bw * (b.landed and (b.body and b.bodyP or 1) or b.p), 2)
end

local function drawPlaying(w, h, seq)
    if L.highlight then return drawHighlight(w, h, seq) end
    local inst = L.inst
    local pad, top, bottom = ScreenScale(10), ScreenScale(24), ScreenScale(34)
    surface.SetDrawColor(PANEL) surface.DrawRect(0, 0, w, top) surface.DrawRect(0, h - bottom, w, bottom)
    surface.SetDrawColor(EDGE) surface.DrawRect(0, top, w, 2) surface.DrawRect(0, h - bottom - 2, w, 2)
    if L.hudFor ~= L.index or L.hudGen ~= V.FontGen then -- P7: built once per hit, not every frame
        L.hudFor, L.hudGen = L.index, V.FontGen
        L.hudTop = string.format("Hit %d of %d   ·   %.0fs before your death", L.index, #seq.instances, inst.ago or 0)
        L.hudWho = string.format("Through %s's eyes", tostring(inst.attacker))
        L.hudWep = string.format("%s   ·   %d hit%s, %s dmg", weaponName(inst.wep), inst.hits or 0, inst.hits == 1 and "" or "s", tostring(inst.dmg or 0))
        surface.SetFont("ZCKC.LifeHead")
        L.hudWhoW = surface.GetTextSize(L.hudWho)
    end
    draw.SimpleText(L.hudTop, "ZCKC.LifeSmall", pad, ScreenScale(3), DIM)
    draw.SimpleText(L.hudWho, "ZCKC.LifeHead", pad, ScreenScale(9), TEXT)
    draw.SimpleText(L.hudWep, "ZCKC.LifeBody", pad + L.hudWhoW + 14, ScreenScale(12), DIM)
    local tagW = tagBox(TAGS[inst.tag] or "", w - pad, ScreenScale(4), inst.reportable and RED or AMBER, 2)
    tagBox("BETA", w - pad - tagW - 6, ScreenScale(4), DIM, 2) -- quiet, but always there while a killcam is on screen
    draw.SimpleText(V.RateText(L.rate), "ZCKC.LifeSmall", w - pad, ScreenScale(15), DIM, TEXT_ALIGN_RIGHT)
    if not L.clip.pov then draw.SimpleText("The attacker left before this could be captured from their side", "ZCKC.LifeSmall", w / 2, top + 8, AMBER, TEXT_ALIGN_CENTER) end
    -- the strip is the progress bar: one cell per hit, the playing one fills as it runs
    local n = #seq.instances
    local cell = math.min((w - pad * 2) / n, ScreenScale(90))
    local frac = math.Clamp((L.cs - L.clip.first) / (L.clip.last - L.clip.first), 0, 1)
    local sy = h - bottom + ScreenScale(4)
    for i, it in ipairs(seq.instances) do
        local x = pad + (i - 1) * cell
        local done = L.reported and L.reported[i]
        surface.SetDrawColor(60, 60, 60, 255) surface.DrawRect(x, sy, cell - 6, 3)
        if i < L.index then surface.SetDrawColor(done and GREEN or DIM) surface.DrawRect(x, sy, cell - 6, 3)
        elseif i == L.index then
            surface.SetDrawColor(TEXT) surface.DrawRect(x, sy, (cell - 6) * frac, 3)
            surface.SetDrawColor(RED) surface.DrawRect(x + (cell - 6) * ((0 - L.clip.first) / (L.clip.last - L.clip.first)), sy - 3, 2, 9) -- the hit
        end
        if not it.zcName then it.zcName, it.zcDmg = tostring(it.attacker), tostring(it.dmg or 0) .. " dmg" end -- P7: once per hit
        local status = done and "reported" or (i == L.index and "playing" or (not it.reportable and "can't report" or it.zcDmg))
        draw.SimpleText(it.zcName, "ZCKC.LifeSmall", x, sy + 6, i == L.index and TEXT or DIM)
        draw.SimpleText(status, "ZCKC.LifeSmall", x, sy + 6 + ScreenScale(6), done and GREEN or DIM)
    end
    local offer = inst.reportable and not (L.reported and L.reported[L.index])
    keyRow(V.Hints.play[1 + (offer and 1 or 0) + (L.saved and 2 or 0)], pad, h - ScreenScale(10)) -- P7: constant rows
    if (L.hitFlash or 0) > 0 then -- you were hit: red at the edges and the number
        local a = L.hitFlash
        surface.SetDrawColor(155, 0, 0, 90 * a)
        surface.DrawRect(0, top + 2, ScreenScale(8), h - top - bottom - 4) surface.DrawRect(w - ScreenScale(8), top + 2, ScreenScale(8), h - top - bottom - 4)
        draw.SimpleTextOutlined(string.format("-%s  %s", tostring(L.hitDmg or "?"), V.HitGroupName and V.HitGroupName(L.hitGroup) or ""), "ZCKC.LifeHead", w / 2, h * 0.62 - (1 - a) * 24, Color(255, 90, 90, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 200 * a))
    end
end

local function drawCard(w, h, seq)
    local card = L.card or (V.Presentation and V.Presentation.Active(L) and L.curtainTo == 0 and not L.leaving and L.index)
    local it = card and seq.instances[card]
    if not it or L.pending then return end -- only once the scene behind it has been switched
    if L.highlight and V.Cinema and V.Cinema.Enabled:GetBool() then return V.Cinema.DrawCard(w, h, L, weaponName(it.wep)) end
    surface.SetAlphaMultiplier(math.Clamp((L.curtain - 0.5) * 2, 0, 1))
    local y = h * 0.4
    if L.highlight then
        if L.cardFor ~= it then -- P7: the card's lines are built once per card
            local kills = tonumber(seq.kills) or 1
            L.cardFor, L.cardName = it, tostring(seq.star or it.attacker)
            L.cardLine = string.format("%s   ·   %d kill%s   ·   %s", weaponName(it.wep), kills, kills == 1 and "" or "s", table.concat(seq.victims or {}, ", "))
        end
        draw.SimpleText("HIGHLIGHT OF THE ROUND", "ZCKC.LifeSmall", w / 2, y, DIM, TEXT_ALIGN_CENTER)
        surface.SetDrawColor(EDGE) surface.DrawRect(w / 2 - ScreenScale(12), y + ScreenScale(8), ScreenScale(24), 2)
        draw.SimpleText(L.cardName, "ZCKC.LifeTitle", w / 2, y + ScreenScale(11), TEXT, TEXT_ALIGN_CENTER)
        draw.SimpleText(L.cardLine, "ZCKC.LifeBody", w / 2, y + ScreenScale(29), DIM, TEXT_ALIGN_CENTER)
        keyRow(V.Hints.skip, w / 2, h - ScreenScale(24), true)
        surface.SetAlphaMultiplier(1)
        return
    end
    if L.cardFor ~= it then -- P7: built once per card. `card`, not L.card: under the presentation director L.card is
        -- nil while its card shows, and string.format("%d", nil) threw inside the overlay's pcall every frame
        L.cardFor, L.cardName = it, tostring(it.attacker)
        L.cardTop = string.format("HIT %d OF %d", card, #seq.instances)
        L.cardLine = string.format("%s   ·   %s damage   ·   %.0fs before your death", weaponName(it.wep), tostring(it.dmg or 0), it.ago or 0)
        L.cardTag = (TAGS[it.tag] or "") .. (it.reportable and "   ·   reportable" or "")
    end
    draw.SimpleText(L.cardTop, "ZCKC.LifeSmall", w / 2, y, DIM, TEXT_ALIGN_CENTER)
    surface.SetDrawColor(EDGE) surface.DrawRect(w / 2 - ScreenScale(12), y + ScreenScale(8), ScreenScale(24), 2)
    draw.SimpleText(L.cardName, "ZCKC.LifeTitle", w / 2, y + ScreenScale(11), TEXT, TEXT_ALIGN_CENTER)
    draw.SimpleText(L.cardLine, "ZCKC.LifeBody", w / 2, y + ScreenScale(29), DIM, TEXT_ALIGN_CENTER)
    tagBox(L.cardTag, w / 2, y + ScreenScale(39), it.reportable and RED or AMBER, 1)
    keyRow(V.Hints.skip, w / 2, h - ScreenScale(24), true)
    surface.SetAlphaMultiplier(1)
end

function drawOverlay()
    if not L or L.round then return end -- replay_v1 P3: the round viewer paints its own HUD (cl_part_09)
    local w, h = ScrW(), ScrH()
    local seq = L.seq
    L.shownAt = L.shownAt or RealTime()
    if L.over then
        -- P6: the end card sits on a dimmed view of the live spectator camera (was opaque black, up to 8 s)
        if L.highlight then surface.SetDrawColor(0, 0, 0, 255 * V.Ease(L.curtain)) else surface.SetDrawColor(V.DimFill) end
        surface.DrawRect(0, 0, w, h)
        if not L.highlight then drawOver(w, h, seq) end
    elseif L.waiting then
        if not L.highlight then
            surface.SetDrawColor(0, 0, 0, 255) surface.DrawRect(0, 0, w, h)
            drawWaiting(w, seq)
        end
    else
        drawPlaying(w, h, seq)
        V.DrawBulletHUD(w, h)
    end
    if not L.over and (L.curtain or 0) > 0 then
        -- P6: eased; full black only while the scene is being switched under it, then a card sits on an 82% dim of the
        -- new instance's first frame instead of on black
        surface.SetDrawColor(0, 0, 0, 255 * V.Ease(L.curtain) * ((L.card and not L.pending) and 0.82 or 1)) surface.DrawRect(0, 0, w, h)
        drawCard(w, h, seq)
    end
    if L.note and RealTime() < (L.noteUntil or 0) then
        draw.SimpleTextOutlined(L.note, "ZCKC.LifeBody", w / 2, ScreenScale(34), GREEN, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
    end
end

hook.Add("HUDPaint", "ZCKillcam.Life", function()
    if V.UIActive() or V.UISide() then return end -- P3 seam: the panel draws everything; a side card never dims the world
    if deathPending then
        -- P6 2026-09-24: was opaque black until the replay arrived (up to 5 s). Now the live view dims in over 0.2 s
        -- and a pill says what is coming. The gamemode HUD stays hidden, as before.
        local a = V.Ease((RealTime() - (deathPendingUntil - 5)) / 0.2)
        surface.SetDrawColor(20, 17, 17, 200 * a) surface.DrawRect(0, 0, ScrW(), ScrH())
        surface.SetAlphaMultiplier(a)
        tagBox("REPLAY INCOMING", ScrW() / 2, ScreenScale(12), TEXT, 1)
        surface.SetAlphaMultiplier(1)
        return true
    end
    if not L then -- the fade back into spectating, after the replay has let go (never over a living player)
        local a = 1 - V.Ease((RealTime() - outroAt) / 0.2) -- P6: 0.45 s linear -> 0.2 s eased
        if a > 0 and IsValid(LocalPlayer()) and (outroLive or not LocalPlayer():Alive()) then surface.SetDrawColor(0, 0, 0, 255 * a) surface.DrawRect(0, 0, ScrW(), ScrH()) end
        return
    end
    -- While the replay owns the frame it draws the overlay itself (see RenderScene) and the gamemode's HUD is off.
    if L.ownsFrame and not L.over and not L.waiting then
        if not L.highlight then return true end
        return
    end
    drawOverlay()
    if not L.highlight then return true end
end)

----------------------------------------------------------------- arrival
local parts = {}
net.Receive("zckc_life", function()
    local id, status = net.ReadString(), net.ReadUInt(3)
    if status ~= 0 then return end
    local n, total, len = net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(16)
    local bucket = parts[id]
    if not bucket then
        bucket = {n = 0, t0 = SysTime()} -- M1: first chunk
        parts[id] = bucket -- NOT `parts = {[id] = bucket}`: that dropped every other transfer still in flight, and at
        -- round end a death sequence and the highlight are in flight together, so one of the two never completed.
        -- A finished blob clears its own bucket below; an abandoned one is a single sequence, on a client that is leaving.
    end
    if not bucket[n] then bucket[n] = net.ReadData(len) bucket.n = bucket.n + 1 end
    if bucket.n < total then return end
    parts[id] = nil
    local lat = {xfer = SysTime() - bucket.t0, at = SysTime()} -- M1: the client's spans, reported by V.LifeLat
    local raw = V.Unpack(table.concat(bucket, "", 1, total))
    local seq = raw and util.JSONToTable(raw)
    lat.decode = SysTime() - lat.at
    if not seq or not seq.instances or #seq.instances == 0 then return end
    if seq.map ~= game.GetMap() then
        if seq.kind ~= "highlight" then V.LifeDrop(3, id) end -- P1: counted
        return
    end
    if seq.kind == "highlight" then -- everyone, alive or dead; whatever was playing gives way to it
        deathPending, deathPendingUntil = false, 0
        -- A highlight can land on somebody in the MIDDLE of their own death replay: K.Busy only tracks whether a blob
        -- is still streaming, not whether a replay is playing, so a player who died a few seconds before the round
        -- ended is watching one when this arrives. Dropping it and waiting out `startAt` handed the screen back to
        -- LIVE play for those 0.2 s - CalcView and RenderScene both stand down while L.waiting - so the sequence was
        -- 3D replay, hard cut, a flash of the live game, then the highlight fading in over it.
        -- Holding the curtain across the handover makes it one fade instead. Only for someone who actually had a
        -- replay on screen: for everyone else, which is most of the server most rounds, this changes nothing.
        local held = L ~= nil and not L.waiting
        if V.LifeUnfinished(L) then V.LifeDrop(4, L.id) end -- P1: the highlight took the screen from an unfinished replay
        stop(true)
        local play = tonumber(seq.play) or 15
        if play ~= play or play > 60 then play = 15 end -- a play time the server got wrong must not become a long stare at a black screen
        local startAt = RealTime() + 0.2
        L = {id = id, seq = seq, reported = {}, waiting = true, highlight = true, startAt = startAt,
            deadline = RealTime() + play + 4, wall = RealTime() + play + WALL}
        if held then
            -- curtainTo as well as curtain: curtain() eases toward curtainTo, and `cardUntil` is what stops it
            -- deciding the card is over and fading straight back out to the live view it was hiding.
            L.curtain, L.curtainTo, L.curtainTime, L.cardUntil = 1, 1, 0.2, startAt
        end
        return
    end
    if LocalPlayer():Alive() then V.LifeDrop(1, id) return end -- P1: arrived after the respawn - counted, and saved server side when persisting
    if V.LifeUnfinished(L) then V.LifeDrop(4, L.id) end -- P1: a newer sequence replaces one still unfinished
    stop(true)
    -- Offered first, started after the forgiveness window: see the header.
    -- A death replay is stepped through by hand and has no play time to bound it, so its wall is generous: it exists
    -- to catch a jammed state machine, not to cut anyone's replay short.
    deathPending, deathPendingUntil = false, 0
    pcall(endMenu, false)
    V.ObserverLife = {id=id, seq=seq, round=zb and zb.ROUND_START, readyAt=RealTime()}
    L = {id = id, seq = seq, reported = {}, waiting = true, startAt = RealTime(), lat = lat,
        wall = RealTime() + 60 * #seq.instances + WALL}
end)

----------------------------------------------------------------- self check
-- `zc_killcam_selfcheck`, run WHILE a killcam is playing. Everything this session changed on the client is
-- unverifiable offline - no harness can load this file, and no test can say whether a hat sits on a corpse
-- properly. What a test CAN do is ask the running client whether the invariants behind those visuals hold, which
-- turns "does it look right" into one command and a pasteable answer. It reads state and changes nothing.
local function checkLines()
    local out = {}
    local function add(ok, text) out[#out + 1] = (ok and "  ok   " or "  BAD  ") .. text end
    if not L then
        out[1] = "  no killcam is playing - run this during one (die, then run it while the replay is up)"
        return out
    end
    add(true, string.format("state: %s%s, cs %.0f, instance %s/%s", L.highlight and "highlight" or "killcam",
        L.waiting and " (waiting)" or (L.over and " (ended)" or ""), L.cs or -1,
        tostring(L.index), tostring(L.seq and #L.seq.instances)))

    -- accessories must follow whichever body is on screen, not the ghost that may be hidden under a ragdoll
    local worn, shown, stray = 0, 0, 0
    for _, g in pairs(L.ghosts or {}) do
        if IsValid(g) and g.zcAccess then
            local rag = g.zcRag
            local host = (IsValid(rag) and not rag:GetNoDraw()) and rag or g
            for _, a in ipairs(g.zcAccess) do
                if IsValid(a) then
                    worn = worn + 1
                    if not a:GetNoDraw() then shown = shown + 1 end
                    if a.zcHost ~= host then stray = stray + 1 end
                end
            end
        end
    end
    add(stray == 0, string.format("accessories: %d worn, %d drawn, %d on the wrong body", worn, shown, stray))
    if worn > 0 and shown == 0 then add(false, "  every accessory is hidden - drawDress is not running for these ghosts") end

    -- the victim marker has to be on the body that is actually visible
    local you = L.ghosts and L.clip and L.ghosts[L.clip.target or 0]
    if IsValid(you) then
        local rag = you.zcRag
        local body = (IsValid(rag) and not rag:GetNoDraw()) and rag or you
        add(not body:GetNoDraw(), "victim outline: target body is " .. (body:GetNoDraw() and "HIDDEN (no halo will draw)" or "visible"))
    else
        add(true, "victim outline: no target ghost in this clip")
    end

    -- input lock and voice, which must both be on for a killcam and both OFF for a highlight
    local want = immersed()
    add((heldAngles ~= nil) == want, string.format("input lock: %s (expected %s for a %s)",
        heldAngles ~= nil and "on" or "off", want and "on" or "off", L.highlight and "highlight" or "killcam"))
    add(watchSaid == want or watchOff, string.format("voice cut: claimed %s, expected %s%s",
        tostring(watchSaid), tostring(want), watchOff and " (reporting disabled - this client predates zckc_watch)" or ""))

    -- the bullet cam, and WHY it is not running when it is not
    local b = L.bullet
    if b == false then
        add(true, "bullet cam: no killing round in this clip (melee, point blank, or shots not recorded) - correct fallback")
    elseif b == nil then
        add(true, "bullet cam: not looked for yet (the clip has not reached the shot)")
    elseif b.done then
        add(true, "bullet cam: finished")
    else
        add(true, string.format("bullet cam: flying, %.0f units of flight, %.0f%% across", b.span or 0, (b.p or 0) * 100))
    end

    -- Body-state parity (2026-09-22). These are the lines that say whether the replay is animating from what the
    -- server RECORDED or from what the viewer guessed, which is the difference the owner is being asked to judge by
    -- eye. Reported as numbers so the answer can be pasted rather than described.
    local actor = L.clip and L.clip.actors and L.clip.actors[L.clip.pov or 0]
    local ghost = L.ghosts and L.clip and L.ghosts[L.clip.pov or 0]
    if not actor then
        add(true, "body state: no point-of-view actor in this clip yet")
    else
        local vx, vy, vz, seq, cyc = nil, nil, nil, nil, nil
        if V.MotionAt then vx, vy, vz, seq, cyc = V.MotionAt(actor, L.cs) end
        if not vx then
            add(false, "body state: this clip carries NONE - it was cut before 2026-09-22, or sv_clips/cl_analysis did not deploy together. The replay is deriving velocity from positions, as it always did")
        else
]========], 2)