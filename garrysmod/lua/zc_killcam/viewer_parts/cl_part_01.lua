return string.sub([========[x-- Z-City killcam, phase 3: records menu and top-down incident viewer.
-- `zc_killcam` opens it (staff: `zc_killcam <steamid64>` opens someone else's records).
-- The server decides who may see what; this file only asks and draws.
if not CLIENT then return end
include("zc_killcam/cl_analysis.lua")
local V = ZCKillcamView

-- Replay entities are the only dynamic models admitted into a replay render pass.
-- Keep map-authored scenery. NoDraw is restored synchronously, even if RenderView throws.
V.SceneDepth = 0
V.SceneLightKeys = {"flashlight", "EZNVGlamp"}
function V.IsolatingScene()
    if V.SceneDepth > 0 then return true end
    -- postround_20260925: a side card (a living player's highlight) leaves the world view live, so outside the
    -- replay's own render pass nothing is isolated - their weapons, armor and clothes draw (cl_part_06 V.UISide).
    if V.UISide and V.UISide() then return false end
    -- Some native overlays run after RenderView returns. They still belong to the live body.
    local state = V.ObserverState and V.ObserverState()
    return state and state.playing == true or false
end
-- postround_20260925: every replay entity, so a side card can keep them out of the live world (V.HideReplayFromLive)
V.ReplayOwned = V.ReplayOwned or setmetatable({}, {__mode = "k"})
function V.OwnReplayEntity(ent)
    if IsValid(ent) then ent.zcReplayOwned = true V.ReplayOwned[ent] = true end
    return ent
end
function V.HideLiveEntity(ent)
    if not IsValid(ent) or ent.zcReplayOwned or ent:IsWorld() then return false end
    if ent:IsPlayer() or ent:IsNPC() or ent:IsWeapon() or ent:IsRagdoll() then return true end
    return not ent:CreatedByMap()
end
-- T1 (killcam_polish, 2026-09-25): owner: "a blinding bloom/blur during killcams and highlights", alive or dead. Every
-- replay RenderView sets dopostprocess = false, which (wiki, ViewData) also pauses HDR "brightness changes": the replay
-- is drawn at whatever tone-mapping scale the LIVE view had adapted to, and after a dark wait or a dark spot that is far
-- too bright. This sets the replay pass's scale and hands back the live one for V.WithReplayScene to restore.
-- zc_killcam_tonemap: 0 inherit the live view (as shipped), 1 clamp its extremes (default), 2 fixed neutral 1.
-- HDR only: an LDR map has no auto exposure. The print (zc_killcam_impact_print, at most every 10 s) shows the live scale.
-- PROVISIONAL(2026-09-25, clamp bounds 0.6-1.6 chosen by eye not measured; the print supplies the real range, ratify-by: 2026-10-09)
V.ToneMode = CreateClientConVar("zc_killcam_tonemap", "1", true, false, "Replay exposure: 0 inherit the live view, 1 clamp extremes, 2 fixed neutral")
function V.ReplayTone()
    local mode = V.ToneMode:GetInt()
    if mode <= 0 or not render.GetHDREnabled() then return nil end
    local live = render.GetToneMappingScaleLinear()
    local x = mode >= 2 and 1 or math.Clamp(live.x, 0.6, 1.6)
    if V.ImpactPrint and V.ImpactPrint:GetBool() and RealTime() - (V.ToneSaidAt or -math.huge) > 10 then
        V.ToneSaidAt = RealTime()
        MsgN(string.format("[Killcam] replay exposure: live tonemap %.2f %.2f %.2f -> %.2f (zc_killcam_tonemap %d)", live.x, live.y, live.z, x, mode))
    end
    if x == live.x then return nil end
    render.SetToneMappingScaleLinear(Vector(x, live.y, live.z))
    return live
end
function V.WithReplayScene(draw)
    local hidden, lights = {}, {}
    V.SceneDepth = V.SceneDepth + 1
    -- postround_20260925: replay bodies hidden from a side card's live view are shown for the replay's own pass
    local shown = V.SceneDepth == 1 and V.LiveHidden or nil
    if shown then for i = 1, #shown do if IsValid(shown[i]) then shown[i]:SetNoDraw(false) end end end
    local tone = V.SceneDepth == 1 and V.ReplayTone() or nil -- T1: the replay's own exposure; the live one is restored below
    local ok, err = pcall(function()
        for _, ent in ipairs(ents.GetAll()) do
            if V.HideLiveEntity(ent) then
                for _, key in ipairs(V.SceneLightKeys) do
                    local light = ent[key]
                    if IsValid(light) and light.GetBrightness and not lights[light] then
                        lights[light] = light:GetBrightness()
                        light:SetBrightness(0) light:Update()
                    end
                end
                if not ent:GetNoDraw() then
                    hidden[#hidden + 1] = ent
                    ent:SetNoDraw(true)
                end
            end
        end
        draw()
    end)
    for _, ent in ipairs(hidden) do if IsValid(ent) then ent:SetNoDraw(false) end end
    if tone then render.SetToneMappingScaleLinear(tone) end -- T1
    for light, brightness in pairs(lights) do
        if IsValid(light) then light:SetBrightness(brightness) light:Update() end
    end
    V.SceneDepth = math.max(0, V.SceneDepth - 1)
    if shown then
        -- hidden again for the rest of the frame; one the pass itself hid stays hidden and is not restored at PostRender
        local keep = {}
        for i = 1, #shown do
            local e = shown[i]
            if IsValid(e) and not e:GetNoDraw() then e:SetNoDraw(true) keep[#keep + 1] = e end
        end
        if V.LiveHidden == shown then V.LiveHidden = keep end
    end
    return ok, err
end


-- BEGIN CINEMATIC DIRECTOR: presentation consumes recorded facts; it never runs damage or live SWEP code.
do
    local C = {}
    V.Cinema = C
    C.Enabled = CreateClientConVar("zc_killcam_cinematic", "1", true, false, "Cinematic replay framing and impact analysis")
    C.Reduced = CreateClientConVar("zc_killcam_reduced_motion", "0", true, false, "Keep replay inspection camera steady and reduce decorative motion")
    C.Duration, C.Flight = 3.6, 1.25
    C.Amber, C.Cyan = Color(255, 192, 105), Color(108, 223, 243)
    C.White, C.Dim = Color(235, 243, 247), Color(147, 171, 183)
    C.Beam = Material("trails/laser")
    C.FontScale = 0
    function C.Fonts(h)
        local scale = math.Clamp(h / 1080, 0.65, 1.5)
        if C.FontScale == scale then return scale end
        C.FontScale = scale
        for name, spec in pairs({Hero = {48, 800}, Title = {26, 700}, Body = {18, 500}, Small = {13, 600}}) do
            surface.CreateFont("ZCKC.Cine" .. name, {font = "Tahoma", size = math.floor(spec[1] * scale), weight = spec[2]})
        end
        return scale
    end
    function C.Number(n, fallback)
        n = tonumber(n)
        if not n or n ~= n or math.abs(n) == math.huge then return fallback or 0 end
        return n
    end
    function C.Fit(text, font, width)
        text = tostring(text or "Unknown")
        surface.SetFont(font)
        if surface.GetTextSize(text) <= width then return text end
        -- Remove a whole UTF-8 character, not a trailing byte of a Steam name.
        while #text > 0 do
            local at = #text
            while at > 1 and text:byte(at) >= 128 and text:byte(at) < 192 do at = at - 1 end
            text = text:sub(1, at - 1)
            if surface.GetTextSize(text .. "...") <= width then return text .. "..." end
        end
        return ""
    end
    function C.Eligible(state)
        if not C.Enabled:GetBool() or not state then return false end
        -- New server advertises the complete reveal budget. Old highlight holds remain unchanged.
        return not state.highlight or (state.seq and state.seq.cinematic == 1)
    end
    function C.Beat(b)
        if b.t < C.Flight then return 1, math.Clamp(b.t / C.Flight, 0, 1) end
        if b.t < 1.65 then return 2, (b.t - C.Flight) / 0.4 end
        if b.t < 3.25 then return 3, (b.t - 1.65) / 1.6 end
        return 4, math.Clamp((b.t - 3.25) / 0.35, 0, 1)
    end
    function C.Envelope(b)
        if not b or not b.cinematic or not b.at or b.done then return 0 end
        return V.BulletWeight(b)
    end
    function C.Clearance(from, to)
        local tr = util.TraceHull({start = from, endpos = to, mins = Vector(-3, -3, -3), maxs = Vector(3, 3, 3), mask = MASK_SOLID_BRUSHONLY})
        return tr.StartSolid and 0 or (tr.Hit and math.Clamp(C.Number(tr.Fraction), 0, 1) or 1), tr
    end
    function C.Side(b)
        if b.cineSide then return b.cineSide end
        local scores = {}
        for _, side in ipairs({1, -1}) do
            local score = 1
            for _, fraction in ipairs({0.15, 0.6, 1}) do
                local point = LerpVector(fraction, b.from, b.to)
                local clearance = C.Clearance(point, point + b.side * (52 * side) + b.up * 14 - b.dir * 18)
                score = math.min(score, clearance)
            end
            scores[side] = score
        end
        b.cineSide = scores[-1] > scores[1] and -1 or 1
        return b.cineSide
    end
    function C.Camera(b)
        if not b.at then return end
        local side, near = b.side * C.Side(b), math.Clamp(b.span / 600, 0.45, 1)
        local settle = V.BulletEase((b.t - 1.08) / 0.55)
        local orbit = C.Reduced:GetBool() and 0 or V.BulletEase((b.t - 1.65) / 1.6) * 0.28
        local focus = b.body and LerpVector(0.2, b.body.first, b.body.last) or b.to
        if b.landed and b.body and b.body.recorded and V.Penetration then focus = V.Penetration.At(b.body,C.Reduced:GetBool() and 0.2 or (b.bodyP or 0)) end
        local natural = V.ShotVisual and V.ShotVisual.Active()
        local chase = b.at - b.dir * ((natural and 27 or 46) * near) + side * ((natural and 16 or 28) * near) + b.up * ((natural and 6 or 10) * near)
        local inspect = focus + side * (58 * math.cos(orbit)) - b.dir * (18 + 58 * math.sin(orbit)) + b.up * 13
        local rig = LerpVector(settle, chase, inspect)
        local _, tr = C.Clearance(b.at, rig)
        if tr.StartSolid then return end
        if tr.Hit then rig = tr.HitPos + tr.HitNormal * 3 end
        local lead = natural and b.at + b.dir * math.min(8, b.span * (1 - (b.p or 0))) or LerpVector(math.min((b.p or 0) + 0.3, 1), b.at, b.to)
        local look = LerpVector(settle, lead, focus)
        if look:DistToSqr(rig) < 16 then return end
        return rig, (look - rig):Angle()
    end
    function C.Fov(b)
        local natural = V.ShotVisual and V.ShotVisual.Active()
        return Lerp(V.BulletEase((b.t - 1.08) / 0.55), natural and 48 or 62, 48)
    end
    C.Bones = {"Pelvis", "Spine", "Spine1", "Spine2", "Spine4", "Neck1", "Head1",
        "L_Clavicle", "L_UpperArm", "L_Forearm", "L_Hand", "R_Clavicle", "R_UpperArm", "R_Forearm", "R_Hand",
        "L_Thigh", "L_Calf", "L_Foot", "R_Thigh", "R_Calf", "R_Foot"}
    C.Links = {{1,2},{2,3},{3,4},{4,5},{5,6},{6,7},{5,8},{8,9},{9,10},{10,11},
        {5,12},{12,13},{13,14},{14,15},{1,16},{16,17},{17,18},{1,19},{19,20},{20,21}}
    function C.Target(state, b)
        local target = b.hit and b.hit[4]
        local actor = state.clip and state.clip.actors and state.clip.actors[target]
        local ghost = state.ghosts and state.ghosts[target]
        if not actor or not IsValid(ghost) then return end
        local body = IsValid(ghost.zcRag) and not ghost.zcRag:GetNoDraw() and ghost.zcRag or ghost
        local model = body == ghost and actor.m or actor.rag and actor.rag.m
        if body:GetNoDraw() or not body.zcReplayOwned or not model or body:GetModel() ~= model then return end
        return body
    end
    function C.BeginCutaway(state)
        local b = state.bullet
        if not b or not b.landed or not b.body or C.Envelope(b) <= 0 then return end
        local body = C.Target(state, b)
        if not body or body.RenderOverride then return end -- respect another owner, even on a ghost
        local natural = V.ShotVisual and V.ShotVisual.Active()
        local reveal = V.BulletEase((b.t - C.Flight - (natural and 0.16 or 0)) / 0.35) * C.Envelope(b)
        if reveal <= 0 then return end
        local override = function(ent, flags)
            local blend = render.GetBlend()
            local red, green, blue = render.GetColorModulation()
            local ok, err = pcall(function()
                render.SetBlend(blend * (1 - reveal * (natural and 0.48 or 0.72)))
                render.SetColorModulation(red * (1 - reveal * (natural and 0 or 0.4)), green, blue)
                ent:DrawModel(flags)
            end)
            render.SetBlend(blend)
            render.SetColorModulation(red, green, blue)
            if not ok then error(err) end
        end
        body.RenderOverride = override
        return function()
            if IsValid(body) and body.RenderOverride == override then body.RenderOverride = nil end
        end
    end
    function C.Scan(state, b)
        local body = C.Target(state, b)
        if not body then return end
        -- Only the recorded victim's actual rig. Missing/custom bones are skipped, never substituted.
        local points = {}
        for i, name in ipairs(C.Bones) do
            local bone = body:LookupBone("ValveBiped.Bip01_" .. name)
            local matrix = bone and body:GetBoneMatrix(bone)
            local p = matrix and matrix:GetTranslation()
            if p and not (body.zcGoreHidden and body.zcGoreHidden[bone]) and p.x == p.x and p.y == p.y and p.z == p.z and p:DistToSqr(b.to) <= 160 * 160 then points[i] = p end
        end
        return points
    end
    function C.Ring(center, right, up, radius, colour)
        local last = center + right * radius
        for i = 1, 24 do
            local angle = i * math.pi / 12
            local point = center + right * (math.cos(angle) * radius) + up * (math.sin(angle) * radius)
            render.DrawLine(last, point, colour, false)
            last = point
        end
    end
    function C.DrawWorld(state, b)
        local alpha = C.Envelope(b)
        if alpha <= 0 then return end
        if b.landed and b.body and b.body.recorded and V.Penetration then V.Penetration.Draw(b,alpha) return end
        -- A small luminous round with a reached-path trail; no future impact markers in flight.
        render.SetMaterial(C.Beam)
        if not b.landed then
            local length = math.min(b.span * b.p, 54)
            for i = 1, 8 do
                local a = b.at - b.dir * (length * (i - 1) / 8)
                local z = b.at - b.dir * (length * (i - 0.5) / 8)
                render.DrawBeam(a, z, 0.65, 0, 1, Color(255, 221, 159, (145 - i * 12) * alpha))
            end
            return
        end
        local reveal = V.BulletEase((b.t - C.Flight) / 0.45) * alpha
        local points = C.Scan(state, b)
        if points then
            for _, link in ipairs(C.Links) do
                local a, z = points[link[1]], points[link[2]]
                if a and z and a:DistToSqr(z) < 64 * 64 then
                    render.DrawLine(a, z, Color(102, 212, 234, 105 * reveal), false)
                end
            end
            if points[7] then render.DrawWireframeSphere(points[7], 3.4, 12, 8, Color(123, 224, 241, 90 * reveal), true) end
        end
        local pulse = C.Reduced:GetBool() and 0 or V.BulletEase((b.t - C.Flight) / 0.65)
        C.Ring(b.to, b.side, b.up, 3 + 9 * pulse, Color(255, 199, 126, 160 * reveal * (1 - pulse * 0.6)))
        if b.body then
            local reached = LerpVector(b.bodyP, b.body.first, b.body.last)
            -- Diagnostic path is allowed through the recorded body; glow is explicitly labelled in HUD.
            render.DrawLine(b.body.first, reached, Color(240, 252, 255, 255 * reveal), false)
            C.Ring(reached, b.side, b.up, 2, Color(121, 229, 249, 180 * reveal))
        end
    end
    function C.Summary(state)
        if state.cineSummary and state.cineSummary.clip == state.clip then return state.cineSummary end
        local clip, marks = state.clip, {}
        for _, e in ipairs(clip.events or {}) do
            if e[2] == 3 and e[3] == clip.pov then
                local actor = clip.actors and clip.actors[e[4]]
                marks[#marks + 1] = {cs = e[1], name = actor and actor.steam or "Unknown player"}
                if #marks == 12 then break end
            end
        end
        local summary = {clip = clip, marks = marks}
        state.cineSummary = summary
        return summary
    end
    function C.Hero(state)
        local actor = state.clip and state.clip.actors and state.clip.actors[state.clip.pov]
        return actor and actor.steam or state.seq.star or state.inst.attacker or "Unknown player"
    end
    function C.Text(text, font, x, y, colour, align)
        draw.SimpleText(text, "ZCKC.Cine" .. font, x, y, colour, align or TEXT_ALIGN_LEFT)
    end
    function C.Rect(x, y, w, h, colour)
        surface.SetDrawColor(colour) surface.DrawRect(x, y, math.max(w, 0), math.max(h, 0))
    end
    function C.DrawHighlight(w, h, state, weapon)
        if V.Presentation and V.Presentation.Active(state) then return V.Presentation.Play(w,h,state,weapon) end
        local s = C.Fonts(h)
        local pad, top, bottom = 30 * s, 72 * s, 64 * s
        C.Rect(0, 0, w, top, Color(8, 13, 19, 240))
        C.Rect(0, h - bottom, w, bottom, Color(8, 13, 19, 240))
        C.Rect(pad, top - 1, 44 * s, 2, C.Cyan)
        C.Text("ROUND HIGHLIGHT", "Small", pad, 11 * s, C.Cyan)
        C.Text(C.Fit(C.Hero(state), "ZCKC.CineTitle", w * 0.43), "Title", pad, 29 * s, C.White)
        C.Text(C.Fit(weapon, "ZCKC.CineBody", w * 0.28), "Body", w - pad, 34 * s, C.Dim, TEXT_ALIGN_RIGHT)
        local kills = math.max(0, C.Number(state.seq.kills, 1))
        C.Text(string.format("%02d ELIMINATION%s  /  REPLAY BETA", kills, kills == 1 and "" or "S"), "Small", w - pad, 11 * s, C.Amber, TEXT_ALIGN_RIGHT)
        local x, y, width = pad, h - bottom + 16 * s, w - 2 * pad
        local first, span = state.clip.first, math.max(state.clip.last - state.clip.first, 1)
        local progress = math.Clamp((state.cs - first) / span, 0, 1)
        C.Rect(x, y, width, 2, Color(57, 73, 83))
        C.Rect(x, y, width * progress, 2, C.Cyan)
        local latest
        for _, mark in ipairs(C.Summary(state).marks) do
            local mx = x + width * math.Clamp((mark.cs - first) / span, 0, 1)
            local reached = state.cs >= mark.cs
            C.Rect(mx - 2 * s, y - 4 * s, 4 * s, 10 * s, reached and C.Amber or C.Dim)
            if reached then latest = mark end
        end
        C.Text("SPACE  SKIP     N  DISABLE", "Small", pad, h - 27 * s, C.Dim)
        if latest then
            C.Text(C.Fit("ELIMINATED  " .. latest.name, "ZCKC.CineSmall", width * 0.45), "Small", w - pad, h - 27 * s, C.Amber, TEXT_ALIGN_RIGHT)
        end
        if state.rate and state.rate < 0.95 and not (state.bullet and state.bullet.at) then
            C.Text(string.format("%.2fx", state.rate), "Small", w / 2, h - 27 * s, C.Cyan, TEXT_ALIGN_CENTER)
        end
    end
    function C.DrawCard(w, h, state, weapon)
        if V.Presentation and V.Presentation.Active(state) then return V.Presentation.Card(w,h,state,weapon) end
        local s = C.Fonts(h)
        local alpha = math.Clamp(((state.curtain or 0) - 0.5) * 2, 0, 1)
        local cx, y = w * 0.5, h * 0.38
        local function fade(c) return Color(c.r, c.g, c.b, 255 * alpha) end
        C.Rect(cx - 28 * s, y - 26 * s, 56 * s, 2, fade(C.Cyan))
        C.Text("THE DEFINING MOMENT", "Small", cx, y, fade(C.Cyan), TEXT_ALIGN_CENTER)
        C.Text(C.Fit(C.Hero(state), "ZCKC.CineHero", w * 0.8), "Hero", cx, y + 25 * s, fade(C.White), TEXT_ALIGN_CENTER)
        C.Text(C.Fit(weapon, "ZCKC.CineBody", w * 0.7), "Body", cx, y + 88 * s, fade(C.Dim), TEXT_ALIGN_CENTER)
        local kills, heads = math.max(0, C.Number(state.seq.kills, 1)), math.max(0, C.Number(state.seq.heads))
        C.Text(string.format("%02d ELIMINATIONS     /     %02d HEADSHOTS", kills, heads), "Small", cx, y + 124 * s, fade(C.Amber), TEXT_ALIGN_CENTER)
        C.Text("SPACE  SKIP", "Small", cx, h - 70 * s, fade(C.Dim), TEXT_ALIGN_CENTER)
    end
    function C.DrawMarker(w, h, b, alpha, s)
        -- Screen marker is informational; reject points behind/outside this replay view.
        if b.landed then
            local p = b.to:ToScreen()
            if p.visible and p.x > 24 * s and p.x < w - 24 * s and p.y > 80 * s and p.y < h - 80 * s then
                local r = 15 * s
                surface.SetDrawColor(Color(C.Amber.r, C.Amber.g, C.Amber.b, 255 * alpha))
                for _, sign in ipairs({-1, 1}) do
                    surface.DrawLine(p.x + sign * r, p.y - r, p.x + sign * r, p.y - r + 6 * s)
                    surface.DrawLine(p.x + sign * r, p.y + r, p.x + sign * r, p.y + r - 6 * s)
                    surface.DrawLine(p.x + sign * r, p.y - r, p.x + sign * (r - 6 * s), p.y - r)
                    surface.DrawLine(p.x + sign * r, p.y + r, p.x + sign * (r - 6 * s), p.y + r)
                end
            end
        end
    end
    function C.DrawHUD(w, h, state)
        local b = state.bullet
        local alpha = C.Envelope(b)
        if alpha <= 0 then return end
        local s, beat, progress = C.Fonts(h), C.Beat(b)
        local bw = math.min(326 * s, w * 0.34)
        local x, y, bh = w - 30 * s - bw, h * 0.58, 154 * s
        local function fade(c, a) return Color(c.r, c.g, c.b, (a or 255) * alpha) end
        C.Rect(x, y, bw, bh, fade(Color(8, 16, 23), 226))
        C.Rect(x, y, 2 * s, bh, fade(b.landed and C.Cyan or C.Amber))
        local titles = {"PROJECTILE TRACK", "CONTACT", b.body and "WOUND PATH" or "IMPACT ANALYSIS", "RESUMING"}
        C.Text(titles[beat], "Small", x + 17 * s, y + 13 * s, fade(C.Cyan))
        local group = b.landed and V.HitGroupName and V.HitGroupName(b.hit[6]) or ""
        C.Text(b.landed and (group ~= "" and group:upper() or "IMPACT") or "IN FLIGHT", "Title", x + 17 * s, y + 34 * s, fade(C.White))
        local v2 = b.landed and b.body and b.body.v2 and V.Penetration
        local detail = v2 and V.Penetration.Detail(b) or (b.landed and (b.body and "Recorded entry to trace end" or "Recorded contact point") or "Following the recorded shot")
        C.Text(C.Fit(detail, "ZCKC.CineSmall", bw - 34 * s), "Small", x + 17 * s, y + 72 * s, fade(C.Dim))
        local report = v2 and V.Penetration.Label(b,b) or (b.landed and string.format("%g DAMAGE  /  POSE OVERLAY", math.max(0, C.Number(b.hit[5]))) or "TRAJECTORY")
        C.Text(C.Fit(report, "ZCKC.CineSmall", bw - 34 * s), "Small", x + 17 * s, y + 96 * s, fade(C.Amber))
        local gap, sw = 5 * s, (bw - 34 * s - 15 * s) / 4
        for i = 1, 4 do
            local px = x + 17 * s + (i - 1) * (sw + gap)
            C.Rect(px, y + 126 * s, sw, 3 * s, fade(Color(46, 67, 80)))
            C.Rect(px, y + 126 * s, sw * (i < beat and 1 or i == beat and progress or 0), 3 * s, fade(C.Cyan))
        end
        C.DrawMarker(w, h, b, alpha, s)
    end
end
-- END CINEMATIC DIRECTOR
-- BEGIN BALLISTICS PANEL
do
    local B = {}
    V.Ballistics = B
    B.Enabled = CreateClientConVar("zc_killcam_shotinfo", "1", true, false, "Show recorded shot information in replays")
    function B.Number(n, minimum, maximum)
        return type(n) == "number" and n == n and n >= minimum and n <= maximum and n or nil
    end
    function B.Facts(b)
        local hit = b.hit and b.hit.ballistics
        local shot = b.shot and b.shot.ballistics
        hit = istable(hit) and hit.v == 1 and hit or {}
        shot = istable(shot) and shot.v == 1 and shot or {}
        local caliber = hit.caliber or shot.caliber
        if type(caliber) ~= "string" or #caliber == 0 or #caliber > 64 or caliber:find("[%c]") then caliber = nil end
        return {range = B.Number(hit.range, 0.001, 20000) or B.Number(b.span / 52.5, 0.001, 20000),
            muzzle = B.Number(hit.muzzle or shot.muzzle, 0.001, 10000),
            angle = B.Number(hit.angle, 0, 90), caliber = caliber,
            diameter = B.Number(hit.diameter or shot.diameter, 0.001, 100)}
    end
    function B.Select(state)
        if not state or not state.clip or not V.ShotRound then return end
        if state.ballisticsClip ~= state.clip then
            state.ballisticsClip = state.clip
            state.ballisticsRound = V.ShotRound(state.clip) or false
        end
        local b = state.ballisticsRound
        if not b or state.cs < b.cs then return end
        return b
    end
    function B.Draw(w, h, state)
        if not B.Enabled:GetBool() then return false end
        local b = B.Select(state)
        if not b then return false end
        if state.dialog or state.pending or state.curtainTo == 1 then return true end
        if V.Presentation and V.Presentation.Active(state) then return V.Presentation.Telemetry(w,h,state,b) end
        local C, facts = V.Cinema, B.Facts(b)
        local s = C.Fonts(h)
        local bw = math.min(414 * s, w * 0.48)
        local x, bh = w - 30 * s - bw, 272 * s
        local y = math.min(h * 0.49, h - 120 * s - bh)
        local active = state.bullet and state.bullet.at and not state.bullet.done and state.bullet or nil
        local contact = active and active.landed or (not active and state.cs >= b.hit[1])
        local beat, phase = 3, 1
        if active and active.cinematic then beat, phase = C.Beat(active) end
        local accent = contact and C.Cyan or C.Amber
        local title = contact and "IMPACT REPORT" or "SHOT TELEMETRY"
        C.Rect(x, y, bw, bh, Color(7, 14, 21, 235))
        C.Rect(x, y, bw, 1, Color(55, 81, 94, 220))
        C.Rect(x, y, 2 * s, bh, accent)
        C.Text(title, "Small", x + 18 * s, y + 15 * s, accent)
        C.Text("BALLISTICS", "Title", x + 18 * s, y + 35 * s, C.White)
        -- A restrained cartridge/flight motif, entirely code-drawn.
        C.Rect(x + bw - 75 * s, y + 42 * s, 35 * s, 2 * s, C.Dim)
        C.Rect(x + bw - 38 * s, y + 39 * s, 13 * s, 8 * s, accent)
        C.Rect(x + 18 * s, y + 72 * s, bw - 36 * s, 1, Color(45, 65, 77))
        local cell = (bw - 46 * s) / 2
        local left, right = x + 18 * s, x + 28 * s + cell
        local function metric(label, value, px, py, small)
            C.Text(label, "Small", px, py, C.Dim)
            local font = small and "Body" or "Title"
            C.Text(C.Fit(value, "ZCKC.Cine" .. font, cell), font, px, py + 19 * s, C.White)
        end
        metric("SHOT RANGE", facts.range and string.format("%.1f m", facts.range) or "Not recorded", left, y + 87 * s, not facts.range)
        metric("MUZZLE SPEED (NOMINAL)", facts.muzzle and string.format("%.0f m/s", facts.muzzle) or "Not recorded", right, y + 87 * s, not facts.muzzle)
        local angle = contact and facts.angle
        metric("IMPACT ANGLE", angle and string.format("%.1f deg", angle) or (contact and "Not recorded" or "Awaiting impact"), left, y + 151 * s, not angle)
        metric("CALIBER / LOAD", facts.caliber or (facts.diameter and string.format("%.2f mm diameter", facts.diameter)) or "Not recorded", right, y + 151 * s, true)
        C.Rect(x + 18 * s, y + 211 * s, bw - 36 * s, 1, Color(45, 65, 77))
        local detail = contact and string.format("%.0f DAMAGE", math.max(0, C.Number(b.hit[5]))) or (V.ShotVisual and V.ShotVisual.Active() and "GENERIC PROJECTILE / RECORDED LINE" or "RECORDED LAUNCH")
        if contact and b.body then detail = detail .. "  /  WOUND PATH" end
        if contact and V.Penetration then detail = V.Penetration.Label(b,active) end
        local traceInfo = contact and V.Penetration and V.Penetration.Detail(b)
        C.Text(C.Fit(traceInfo or "ANGLE: 0 HEAD-ON / 90 GRAZING", "ZCKC.CineSmall", bw - 36 * s), "Small", left, y + 222 * s, C.Dim)
        C.Text(C.Fit(detail, "ZCKC.CineSmall", bw - 36 * s), "Small", left, y + 243 * s, accent)
        if active and active.cinematic then
            C.DrawMarker(w, h, active, C.Envelope(active), s)
            local gap, width = 4 * s, (bw - 12 * s) / 4
            for i = 1, 4 do
                local px = x + (i - 1) * (width + gap)
                C.Rect(px, y + bh - 2 * s, width, 2 * s, Color(36, 54, 66))
                C.Rect(px, y + bh - 2 * s, width * (i < beat and 1 or i == beat and phase or 0), 2 * s, accent)
            end
        end
        return true
    end
end
-- END BALLISTICS PANEL
-- BEGIN REPLAY GORE: effects are functions of replay time, never live particle emitters or map decals.
do
    local G = {models = {}}
    V.Gore = G
    G.Enabled = CreateClientConVar("zc_killcam_gore", "1", true, false, "Replay recorded wounds and dismemberment")
    G.Roots = {"ValveBiped.Bip01_L_Forearm", "ValveBiped.Bip01_R_Forearm", "ValveBiped.Bip01_L_Calf", "ValveBiped.Bip01_R_Calf", "ValveBiped.Bip01_Head1"}
    G.GibModel = "models/props_junk/watermelon01_chunk02a.mdl"
    -- Native GoreCalc stump placements, indexed by the recorded model's female flag.
    G.Stumps = {
        [0] = {Vector(11,0,-1), Vector(11,0.5,0.5), Vector(17.5,0,0), Vector(17.5,0,0)},
        [1] = {Vector(11,0.5,-0.5), Vector(11,0.5,0.5), Vector(15.5,0,0), Vector(15.5,0,0)}
    }
    G.Blood = CreateMaterial("zckc_replay_blood", "UnlitGeneric", {['$basetexture'] = "vgui/white", ['$translucent'] = 1, ['$vertexcolor'] = 1, ['$vertexalpha'] = 1, ['$nocull'] = 1})
    local bloodTexture = Material("decals/blood1"):GetTexture("$basetexture")
    if bloodTexture then G.Blood:SetTexture("$basetexture", bloodTexture) end
    function G.Number(n, limit) return type(n) == "number" and n == n and math.abs(n) <= limit end
    function G.At(actor, cs)
        local data = actor and actor.gore
        if not istable(data) or data.v ~= 1 or not istable(data.f) or #data.f > 129 or not G.Number(cs, 1e9) then return end
        local frames, lo, hi, found = data.f, 1, #data.f, nil
        while lo <= hi do
            local mid = math.floor((lo + hi) / 2)
            if not istable(frames[mid]) or not G.Number(frames[mid][1], 1e9) then return end
            if frames[mid][1] <= cs then found = frames[mid] lo = mid + 1 else hi = mid - 1 end
        end
        if found and G.Number(found[2], 31) and found[2] >= 0 and found[2] % 1 == 0 and istable(found[4]) then return found end
    end
    function G.Restore(body)
        if not IsValid(body) or not body.zcReplayOwned then return end
        for bone, scale in pairs(body.zcGoreScales or {}) do body:ManipulateBoneScale(bone, scale) end
        body.zcGoreScales, body.zcGoreHidden, body.zcGoreFrame, body.zcGoreMask = nil, nil, nil, nil
    end
    function G.Apply(body, actor, cs)
        if not IsValid(body) or not body.zcReplayOwned then return end
        local row = G.Enabled:GetBool() and G.At(actor, cs)
        if row and row[3] ~= body:GetModel() then row = nil end
        local mask = row and row[2] or 0
        if body.zcGoreMask ~= mask then
            G.Restore(body)
            body.zcGoreScales, body.zcGoreHidden, body.zcGoreMask = {}, {}, mask
            local count = 0
            local function hide(bone)
                if not bone or bone < 0 or body.zcGoreHidden[bone] or count >= 128 then return end
                count = count + 1
                body.zcGoreHidden[bone] = true
                local scale = body:GetManipulateBoneScale(bone)
                body.zcGoreScales[bone] = Vector(scale.x, scale.y, scale.z)
                body:ManipulateBoneScale(bone, Vector(0.01, 0.01, 0.01))
                for _, child in ipairs(body:GetChildBones(bone) or {}) do hide(child) end
            end
            for i, root in ipairs(G.Roots) do if bit.band(mask, 2 ^ (i - 1)) ~= 0 then hide(body:LookupBone(root)) end end
        end
        body.zcGoreFrame = row
    end
    function G.Bones(body)
        if not body.zcReplayOwned then return end
        -- Enforce after replay IK/gesture callbacks so copied weapon matrices cannot regrow a severed hand.
        for bone in pairs(body.zcGoreHidden or {}) do
            local m = body:GetBoneMatrix(bone)
            if m then m:SetScale(Vector(0.01, 0.01, 0.01)) body:SetBoneMatrix(bone, m) end
        end
    end
    function G.Clear()
        for _, model in pairs(G.models) do if IsValid(model) then model:Remove() end end
        G.models, G.retry = {}, {}
    end
    function G.Model(key, path, loose)
        local model = G.models[key]
        if IsValid(model) then return model end
        G.retry = G.retry or {}
        if (G.retry[key] or 0) > RealTime() then return end
        G.retry[key] = RealTime() + 1
        -- P8: a thrown prop's model may never have been precached on this client; the file check is the honest test
        if not (util.IsValidModel(path) or (loose and file.Exists(path, "GAME"))) then return end
        model = V.OwnReplayEntity(ClientsideModel(path, RENDERGROUP_OPAQUE))
        if not IsValid(model) then return end
        model:SetNoDraw(true) model:DrawShadow(false)
        G.models[key] = model
        return model
    end
    function G.GibAt(track, cs)
        if not istable(track) or not istable(track.f) or #track.f == 0 or #track.f > 211 then return end
        -- P8: rows tagged k are thrown props / projectiles with their own model; untagged rows are gore gibs only
        if track.m ~= G.GibModel and not (isstring(track.k) and isstring(track.m) and #track.m < 200) then return end
        local f = track.f
        if not istable(f[1]) or not istable(f[#f]) or not G.Number(f[1][1], 1e9) or not G.Number(f[#f][1], 1e9) or not G.Number(cs, 1e9) then return end
        if cs < f[1][1] or cs > f[#f][1] then return end
        local lo, hi, i = 1, #f, 1
        while lo <= hi do
            local mid = math.floor((lo + hi) / 2)
            if not istable(f[mid]) or not G.Number(f[mid][1], 1e9) then return end
            if f[mid][1] <= cs then i = mid lo = mid + 1 else hi = mid - 1 end
        end
        local a, b = f[i], f[math.min(i + 1, #f)]
        if not istable(b) then return end
        for k = 1, 8 do if not G.Number(a[k], 1e9) or not G.Number(b[k], 1e9) then return end end
        return a, b, a == b and 0 or math.Clamp((cs - a[1]) / math.max(b[1] - a[1], 1), 0, 1)
    end
    function G.DrawGibs(state)
        for i = 1, math.min(#(state.clip.gibs or {}), 32) do
            local track = state.clip.gibs[i]
            local a, b, f = G.GibAt(track, state.cs)
            if a then
                local object = isstring(track.k) -- P8: a thrown prop or projectile, drawn with its real model
                local model = object and G.Model("obj" .. track.m, track.m, true) or G.Model("gib" .. i, G.GibModel)
                if IsValid(model) then
                    local o = state.clip.origin
                    model:SetPos(Vector(o[1] + Lerp(f,a[2],b[2])/10, o[2] + Lerp(f,a[3],b[3])/10, o[3] + Lerp(f,a[4],b[4])/10))
                    model:SetAngles(LerpAngle(f, Angle(a[5],a[6],a[7]), Angle(b[5],b[6],b[7])))
                    model:SetModelScale(math.Clamp(Lerp(f,a[8],b[8])/1000,0,10))
                    if not object then model:SetSubMaterial(0,"models/flesh") end
                    model:SetupBones() model:DrawModel()
                end
            end
        end
    end
    function G.WoundPoint(body, w, cs)
        if not istable(w) or type(w[1]) ~= "string" or #w[1] > 96 then return end
        for i = 2, 10 do if not G.Number(w[i], i == 9 and 1e9 or 10000) then return end end
        if w[9] > cs then return end
        local bone = body:LookupBone(w[1])
        if not bone or (body.zcGoreHidden and body.zcGoreHidden[bone]) then return end
        local matrix = body:GetBoneMatrix(bone)
        if not matrix then return end
        return LocalToWorld(Vector(w[2]/10,w[3]/10,w[4]/10), Angle(w[5],w[6],w[7]), matrix:GetTranslation(), matrix:GetAngles())
    end
    function G.DrawBody(body, cs, budget)
        local row = body.zcGoreFrame
        if not row then return budget end
        for i = 1, math.min(#row[4], 40) do
            if budget < 5 then break end
            local w = row[4][i]
            local pos, ang = G.WoundPoint(body, w, cs)
            if pos then
                render.SetMaterial(G.Blood)
                local size = math.Clamp(1.5 + math.sqrt(math.max(w[8],0)) * 0.3, 1.5, 7)
                render.DrawQuadEasy(pos + ang:Forward() * 0.03, ang:Forward(), size, size, Color(115,8,8,225), i * 37 % 360)
                budget = budget - 1
                if row[5] == 1 then
                    -- Short deterministic droplets follow recorded wound timing. No CurTime drift when paused.
                    for k = 1, 3 do
                        local age = ((cs - w[9]) / 100 + k * 0.137 + i * 0.031) % 0.55
                        local speed = w[10] == 2 and 90 or 12
                        local at = pos + ang:Forward() * (age * speed) + Vector(math.sin(i*7+k)*age*9, math.cos(i*3+k)*age*9, -150*age*age)
                        render.DrawSprite(at, 1.3, 1.3, Color(125,4,4,210*(1-age/0.55)))
                        budget = budget - 1
                    end
                end
            end
        end
        for i, root in ipairs(G.Roots) do
            if budget <= 0 then break end
            if bit.band(row[2], 2 ^ (i - 1)) ~= 0 then
                local bone = body:LookupBone(root)
                local m = bone and bone > 0 and body:GetBoneMatrix(bone - 1)
                local placements = G.Stumps[row[7]]
                local pos, ang
                if i == 5 and placements then
                    local att = body:GetAttachment(3)
                    if att then pos, ang = LocalToWorld(row[7] == 1 and Vector(-2,0,4) or Vector(0,0,5), angle_zero, att.Pos, att.Ang) end
                elseif m and placements then
                    pos, ang = LocalToWorld(placements[i], Angle(0,90,0), m:GetTranslation(), m:GetAngles())
                end
                if pos then
                    local model = G.Model(i == 5 and "head" or "stump", i == 5 and "models/gleb/zcity/headboom.mdl" or "models/grub_nugget_small.mdl")
                    if IsValid(model) then
                        model:SetPos(pos) model:SetAngles(ang) model:SetModelScale(i == 5 and 1 or 0.8)
                        if i ~= 5 then model:SetSubMaterial(0,"models/flesh") end
                        model:SetupBones() model:DrawModel() budget = budget - 1
                    end
                end
            end
        end
        return budget
    end
    function G.DrawBursts(actor, cs, origin, budget)
        local data = actor and actor.gore
        if not data or data.v ~= 1 or not data.f then return budget end
        for _, frame in ipairs(data.f) do
            local age = (cs - frame[1]) / 100
            if age >= 0 and age < 0.8 then
                for _, c in ipairs(frame[6] or {}) do
                    if budget < 12 then return budget end
                    if G.Number(c[2],1e8) and G.Number(c[3],1e8) and G.Number(c[4],1e8) then
                        local pos = Vector(origin[1]+c[2]/10,origin[2]+c[3]/10,origin[3]+c[4]/10)
                        render.SetMaterial(G.Blood)
                        for k = 1, 12 do
                            local dir = Vector(math.sin(k*13),math.cos(k*7),0.5+math.sin(k*3))
                            local at = pos + dir * (age*90) + Vector(0,0,-140*age*age)
                            render.DrawSprite(at,3,3,Color(135,6,6,220*(1-age/0.8)))
                        end
                        budget = budget - 12
                    end
                end
            end
        end
        return budget
    end
    function G.Draw(state)
        if not G.Enabled:GetBool() or not state or not state.clip then return end
        local budget = 192
        for i, ghost in pairs(state.ghosts or {}) do
            if IsValid(ghost) and ghost.zcReplayOwned then
                local body = IsValid(ghost.zcRag) and not ghost.zcRag:GetNoDraw() and ghost.zcRag or ghost
                if not body:GetNoDraw() and body.zcReplayOwned and body.zcGoreFrame then
                    budget = G.DrawBody(body, state.cs, budget)
                    budget = G.DrawBursts(state.clip.actors[i],state.cs,state.clip.origin,budget)
                end
            end
        end
        G.DrawGibs(state)
    end
end
-- END REPLAY GORE
-- BEGIN HIGHLIGHT PRESENTATION: one recorded timeline, no extra playback or render pass.
do
    local P = {}
    V.Presentation = P
    P.Enabled = CreateClientConVar("zc_killcam_highlight_style", "1", true, false, "Editorial highlight presentation")
    P.Ink, P.Paper, P.Muted = Color(8, 14, 20), Color(237, 242, 239), Color(143, 162, 170)
    P.Cyan, P.Amber, P.Edge = Color(118, 223, 212), Color(246, 183, 105), Color(47, 67, 75)
    function P.Active(state)
        return state and state.highlight == true and P.Enabled:GetBool() and V.Cinema.Enabled:GetBool()
    end
    function P.Ease(n) n = math.Clamp(n, 0, 1) return n * n * (3 - 2 * n) end
    function P.Tint(c, alpha) return Color(c.r, c.g, c.b, math.Clamp(alpha or 1, 0, 1) * (c.a or 255)) end
    function P.Fonts(h)
        local s = math.Clamp(h / 1080, 0.7, 1.5)
        if P.scale ~= s then
            P.scale = s
            for name, spec in pairs({Hero={76,800}, Number={56,700}, Title={30,700}, Value={25,700}, Body={18,500}, Small={14,600}, Micro={12,600}}) do
                surface.CreateFont("ZCKC.Reel" .. name, {font="Tahoma", size=math.floor(spec[1]*s), weight=spec[2]})
            end
        end
        return s
    end
    function P.Clean(value)
        return string.gsub(tostring(value or "Unknown player"), "[%c]", " ")
    end
    function P.Text(text, font, x, y, color, align, width)
        local full = "ZCKC.Reel" .. font
        text = P.Clean(text)
        if width then text = V.Cinema.Fit(text, full, math.max(width, 0)) end
        draw.SimpleText(text, full, x, y, color, align or TEXT_ALIGN_LEFT)
    end
    function P.Rect(x, y, w, h, color)
        surface.SetDrawColor(color) surface.DrawRect(x, y, math.max(0,w), math.max(0,h))
    end
    function P.Line(x, y, xx, yy, color)
        surface.SetDrawColor(color) surface.DrawLine(x, y, xx, yy)
    end
    function P.Diamond(x, y, r, color)
        P.Line(x-r,y,x,y-r,color) P.Line(x,y-r,x+r,y,color)
        P.Line(x+r,y,x,y+r,color) P.Line(x,y+r,x-r,y,color)
    end
    function P.Ring(x, y, r, fraction, color)
        for i=1,24 do
            local a, b = (i-1)/24*math.pi*2, math.min(i/24,fraction)*math.pi*2
            if a < fraction*math.pi*2 then
                P.Line(x+math.sin(a)*r,y-math.cos(a)*r,x+math.sin(b)*r,y-math.cos(b)*r,color)
            end
        end
    end
    function P.GetReplayData(state)
        local clip = state.clip
        if state.reelData and state.reelData.clip == clip then return state.reelData end
        local d = {clip=clip, marks={}, shots={}, count=0}
        local hits = {}
        for _, e in ipairs(clip.events or {}) do
            if type(e[1]) == "number" and e[1] == e[1] and math.abs(e[1]) < 1e9 and e[3] == clip.pov then
                if e[2] == 1 and #d.shots < 96 then d.shots[#d.shots+1] = e[1] end
                if e[2] == 2 then hits[e[4]] = e end
                if e[2] == 3 then
                    d.count = d.count+1
                    if #d.marks < 64 then
                        local actor, hit = clip.actors and clip.actors[e[4]], hits[e[4]]
                        local head = hit and hit.ballistic == 1 and hit[6] == 1 and hit[1] <= e[1] and e[1]-hit[1] <= 100
                        d.marks[#d.marks+1] = {cs=e[1], name=actor and actor.steam or "Unknown player", head=head==true}
                    end
                end
            end
        end
        table.sort(d.marks,function(a,b)return a.cs<b.cs end)
        d.round = V.ShotRound and V.ShotRound(clip) or nil
        d.facts = d.round and V.Ballistics.Facts(d.round) or {}
        state.reelData = d
        return d
    end
    function P.Bounds(state)
        local clip = state.clip
        local first, last = V.Cinema.Number(clip.first), V.Cinema.Number(clip.last)
        return first, math.max(last-first,1), last
    end
    function P.Clock(state)
        local b=state.bullet
        if b and b.at and not b.done and not b.landed and b.hit then
]========], 2)
