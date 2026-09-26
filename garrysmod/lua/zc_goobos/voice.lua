if not CLIENT then return end
local A = ZCGoobApps
local T = A.Theme
local enabled = CreateClientConVar("zc_goobos_voice", "1", true, false, "Use the GoobOS voice display", 0, 1)
local compact = CreateClientConVar("zc_goobos_voice_hud", "1", true, false, "Show the compact GoobOS voice display during play", 0, 1)
local lowerHUD = CreateClientConVar("zc_goobos_voice_lower", "1", true, false, "Place voice cards at the lower-right edge", 0, 1)
local electricity = CreateClientConVar("zc_goobos_voice_electricity", "0", true, false, "Show decorative electricity on voice indicators", 0, 1)
local function electricityEnabled() return electricity:GetBool() end
local V = {rows = {}, meters = {}, updated = -1, nextPoll = 0}
A.Voice = V -- No identity or audio history survives a reload.

-- === Frame governor (2026-09-25 perf pass) =======================================================================
-- Every voice hook calls frameBegin() first; it runs once per frame. Q is the effect density for this frame:
-- zc_goobos_voice_electricity (the orbs' decorative switch above) is checked by the orb code itself, never here, so
-- the superadmin border electricity in the column and the ESP tags works without it. zc_goobos_voice_fx 0 (Auto) gives
-- 1 at 120 fps easing to a quarter by 40 fps, so the electricity is the first thing to thin out on a slow client
-- while the rings, avatars and names never change; 1 = always full.
local fxCv = CreateClientConVar("zc_goobos_voice_fx", "0", true, false, "Electricity density while it is on: 0 auto (follows frame time), 1 full", 0, 1)
local Q, qFrame, frameAt, sparkCount = 1, 1 / 60, -1, 0
local FEATHER_FULL = {{2.2, 0.14}, {1.4, 0.3}, {0.6, 0.55}} -- {extra width, alpha fraction}, widest first
local FEATHER_MID = {{2.0, 0.16}, {0.8, 0.45}}
local FEATHER_LOW = {{1.2, 0.35}}
local FEATHER = FEATHER_FULL
local function frameBegin(now, dt)
    if frameAt == now then return end
    frameAt, sparkCount = now, 0
    qFrame = qFrame + (math.Clamp(dt, 0, 0.1) - qFrame) * 0.1
    if fxCv:GetInt() >= 1 then Q = 1
    else Q = math.Clamp(1 - (qFrame - 1 / 120) / (1 / 40 - 1 / 120) * 0.75, 0.25, 1) end
    FEATHER = Q >= 0.6 and FEATHER_FULL or (Q >= 0.3 and FEATHER_MID or FEATHER_LOW)
end
function V.Quality() return Q end
function V.FrameBegin(now, dt) frameBegin(now, dt) end

function V.Enabled()
    return enabled:GetBool() and hg and isfunction(hg.CanIdentifyVoicePanel)
end

function V.Ready()
    return V.Enabled() and V.updated >= 0 and RealTime() - V.updated < 0.5
end

-- Normalized engine amplitude; never synthesize a signal or change playback gain.
function V.Step(meter, raw, dt, now)
    raw = tonumber(raw) or 0
    if raw ~= raw then raw = 0 end
    raw = math.Clamp(raw, 0, 1)
    dt = math.Clamp(dt, 0, 0.25)
    local level = meter.level or 0
    level = level + (raw - level) * (1 - math.exp(-dt * (raw > level and 24 or 7)))
    meter.level = level
    meter.samples = meter.samples or {}
    meter.sampleHead = ((meter.sampleHead or 0) % 24) + 1
    meter.samples[meter.sampleHead] = raw
    if raw >= (meter.peak or 0) then
        meter.peak = raw
        meter.hold = now + 0.75
    elseif now > (meter.hold or 0) then
        meter.peak = math.max(level, (meter.peak or 0) - dt * 0.45)
    end
    return meter
end

-- Charge (owner 2026-09-25, replaces the column-only loud-talker charge of 2026-09-24): every client builds a charge
-- for every player it hears, whether or not a voice panel is on screen. It builds slowly whenever someone talks and
-- faster when they max out their level or keep talking for too long; silence drains it faster than normal talk
-- builds it, so short exchanges never fill it. At full charge this client reports the talker (zc_voice_charge); the
-- server checks its own speaking history, blocks their voice 3 s and broadcasts zc_voice_explode.
-- PROVISIONAL(2026-09-25, rates chosen to keep the owner's 2026-09-24 full-volume fill time of ~7.5 s; normal talk
-- alone fills in ~3 min of unbroken speech; the long-talk push starts at 20 s; ratify-by: 2026-10-09)
local CH = {base = 1 / 180, loud = 2 / 15, long = 1 / 20, drain = 1 / 60, gap = 2}
V.charge = V.charge or setmetatable({}, {__mode = "k"})
function V.StepCharge(p, talking, level, dt, now)
    local cs = V.charge[p]
    if not cs then
        if not talking then return end
        cs = {v = 0, spell = 0, quiet = 0}
        V.charge[p] = cs
    end
    cs.at = now
    local rate
    if (cs.mutedUntil or 0) > now then
        rate = -1
    elseif talking then
        cs.quiet = 0
        cs.spell = cs.spell + dt
        local loud = math.Clamp((level - 0.45) / 0.45, 0, 1) -- absolute engine level; ~0.9 and up is maxed out
        local long = math.Clamp((cs.spell - 20) / 40, 0, 1) -- one unbroken spell past 20 s, full push at 60 s
        rate = CH.base + loud * loud * CH.loud + long * CH.long
    else
        cs.quiet = cs.quiet + dt
        if cs.quiet > CH.gap then cs.spell = 0 end -- a pause longer than the gap ends the spell
        rate = -CH.drain
    end
    cs.v = math.Clamp(cs.v + rate * dt, 0, 1)
    if cs.v >= 1 and now - (cs.reported or -10) > 3 and IsValid(p) and util.NetworkStringToID("zc_voice_charge") ~= 0 then
        cs.reported = now
        net.Start("zc_voice_charge") net.WriteUInt(p:UserID(), 16) net.SendToServer()
    end
    if cs.v <= 0 and cs.spell <= 0 and (cs.mutedUntil or 0) <= now then V.charge[p] = nil end
end

local function staffRole()
    local p = LocalPlayer()
    return IsValid(p) and (p:IsAdmin() or (p.CheckGroup and p:CheckGroup("operator")))
end

local function staffAllowed()
    local cv = GetConVar("zc_micbox_enabled")
    return staffRole() and cv and cv:GetBool()
end

function V.Visible(row)
    if not V.Ready() then return false end
    if not row.ply then return true end
    if not IsValid(row.ply) then return false end
    if row.staff then return staffAllowed() and isfunction(hg.GetMicBoxSpeakers) end
    return hg.CanIdentifyVoicePanel(row.ply) == true
end

function V.Poll(now)
    if not V.Enabled() or not IsValid(LocalPlayer()) then
        V.rows = {}; V.meters = {}; V.updated = -1
        return
    end
    local dt = math.min(0.25, V.updated < 0 and 0.05 or now - V.updated)
    local me = LocalPlayer()
    local candidates, nextMeters, rows = {}, {}, {}
    local staff = staffAllowed() and isfunction(hg.GetMicBoxSpeakers) and hg.GetMicBoxSpeakers() or {}
    for _, p in ipairs(player.GetAll()) do
        if IsValid(p) and p:IsSpeaking() then candidates[p] = false end
    end
    for p in pairs(staff) do if IsValid(p) then candidates[p] = true end end
    local hidden, hiddenLevel = false, 0
    for p, fromStaff in pairs(candidates) do
        local muted = p:IsMuted() or (p.GetVoiceVolumeScale and p:GetVoiceVolumeScale() <= 0)
        local audible = not muted and p:IsSpeaking() and (p == LocalPlayer() or p:IsVoiceAudible())
        local raw = audible and p:VoiceVolume() or 0
        -- 2026-09-24 (owner: "I don't see my electricity"): the engine reports your OWN VoiceVolume() as 0 unless
        -- voice_loopback is on, so the local orb never had a level. While you transmit and the engine gives nothing,
        -- a speech-shaped envelope stands in (cadence from two slow sines); it is presentation only.
        if audible and p == LocalPlayer() and raw <= 0.001 then
            local c = math.abs(math.sin(now * 6.3)) * math.abs(math.sin(now * 2.1 + 0.7))
            raw = 0.28 + 0.42 * c
        end
        if p ~= me then V.StepCharge(p, audible, raw, dt, now) end
        if fromStaff or hg.CanIdentifyVoicePanel(p) then
            local meter = V.Step(V.meters[p] or {start = now}, raw, dt, now)
            if not audible then meter.level = 0; meter.peak = 0 end
            nextMeters[p] = meter
            rows[#rows + 1] = {ply = p, staff = fromStaff, meter = meter, audible = audible, muted = muted}
        elseif audible then
            hidden = true
            hiddenLevel = math.max(hiddenLevel, raw)
        end
    end
    if hidden then
        local meter = V.Step(V.meters.anonymous or {start = now}, hiddenLevel, dt, now)
        nextMeters.anonymous = meter
        rows[#rows + 1] = {meter = meter, audible = true} -- No player, name, avatar, count or per-speaker history.
    end
    for p, cs in pairs(V.charge) do -- players who stopped talking drain too
        if not IsValid(p) then V.charge[p] = nil elseif cs.at ~= now then V.StepCharge(p, false, 0, dt, now) end
    end
    table.sort(rows, function(a, b)
        if (a.ply == LocalPlayer()) ~= (b.ply == LocalPlayer()) then return a.ply == LocalPlayer() end
        if a.meter.start ~= b.meter.start then return a.meter.start < b.meter.start end
        return (a.ply and a.ply:UserID() or -1) < (b.ply and b.ply:UserID() or -1)
    end)
    V.rows = rows; V.meters = nextMeters; V.updated = now
end

hook.Add("Think", "GoobOS.Voice.Sample", function()
    local now = RealTime()
    if now < V.nextPoll then return end
    V.nextPoll = now + 0.05
    V.Poll(now)
    V.Duck(now)
end)

-- Voice volume (owner 2026-09-25). The heard volume of each player is composed in one place:
--   min(the listener's own setting, the serverwide limit from `ulx quiet` / !quiet) x the admin duck.
-- Several systems set a player's volume directly (the scoreboard slider, the gamemode's mute and spectator rules,
-- the ragdoll lip-sync every frame), so Player:SetVoiceVolumeScale is wrapped once: whatever they set is kept as the
-- player's base and the limit and duck are applied on top. Before this, the duck set the volume once and the next
-- write (every frame for a downed player) undid it.
-- Duck: while an admin or superadmin speaks, everyone else is scaled to zc_goobos_voice_duck (0.5) of that, back
-- 0.6 s after the admin stops. The limit is NWFloat "zc_voice_limit" (0..1) on the talker, set by the server.
local PLAYER = FindMetaTable and FindMetaTable("Player")
if PLAYER and PLAYER.SetVoiceVolumeScale then
    local rawSet = PLAYER.zcVoiceRawSet or PLAYER.SetVoiceVolumeScale
    PLAYER.zcVoiceRawSet = rawSet
    function PLAYER:SetVoiceVolumeScale(v)
        v = tonumber(v) or 1
        self.zcVoiceBase = v
        return rawSet(self, math.min(v, self.zcVoiceLimit or 1) * (self.zcVoiceDuck or 1))
    end
end
local duckCv = CreateClientConVar("zc_goobos_voice_duck", "0.5", true, false, "Scale other voices to this while an admin speaks (0 = off)", 0, 1)
local duckHold = 0
function V.Duck(now)
    local scale = duckCv:GetFloat()
    local me = LocalPlayer()
    local adminTalking = false
    if scale > 0 and scale < 1 then
        for _, p in ipairs(player.GetAll()) do
            if IsValid(p) and p ~= me and p:IsSpeaking() and p:IsAdmin() then adminTalking = true break end
        end
    end
    if adminTalking then duckHold = now + 0.6 end
    local active = adminTalking or now < duckHold
    local rawSet = PLAYER and PLAYER.zcVoiceRawSet
    if not rawSet then return end
    for _, p in ipairs(player.GetAll()) do
        if IsValid(p) and p ~= me then
            local duck = (active and not p:IsAdmin()) and scale or 1
            local limit = math.Clamp(p.GetNWFloat and p:GetNWFloat("zc_voice_limit", 1) or 1, 0, 1)
            if duck ~= (p.zcVoiceDuck or 1) or limit ~= (p.zcVoiceLimit or 1) then
                local base = p.zcVoiceBase or p:GetVoiceVolumeScale() -- nothing composed yet: the engine value is the base
                p.zcVoiceBase, p.zcVoiceDuck, p.zcVoiceLimit = base, duck, limit
                rawSet(p, math.min(base, limit) * duck)
            end
        end
    end
end

function V.Title(row)
    if not row.ply then return "Nearby voice" end
    if row.ply == LocalPlayer() then return "You" end
    if not IsValid(row.ply) then return "Nearby voice" end -- fading slot outlived a disconnect
    return row.ply:Nick()
end

function V.Status(row)
    if row.muted then return "Muted · no level" end
    if not row.audible then return "No audio · level unavailable" end
    if not row.ply then return "Identity hidden by game rules" end
    return row.staff and "Staff monitor · receiving" or (row.ply == LocalPlayer() and "Your microphone · transmitting" or "Receiving voice")
end

-- A segmented VU strip plus a held peak, in the same units as VoiceVolume().
function V.DrawMeter(meter, x, y, w, h, available)
    local count = math.max(4, math.min(32, math.floor(w / 7)))
    local gap = 2
    local width = (w - (count - 1) * gap) / count
    for i = 1, count do
        local color = T.line
        if available and i / count <= meter.level then
            color = i / count > 0.9 and T.red or (i / count > 0.7 and T.gold or T.green)
        end
        draw.RoundedBox(1, x + (i - 1) * (width + gap), y, width, h, color)
    end
    if available and meter.peak > 0 then
        surface.SetDrawColor(T.text)
        surface.DrawRect(x + math.Clamp(meter.peak * w, 0, w - 2), y - 2, 2, h + 4)
    end
end

local function fit(text, width, font)
    surface.SetFont(font or "GoobBody")
    if surface.GetTextSize(text) <= width then return text end
    local len = utf8.len(text) or #text
    while len > 0 do
        local short = utf8.sub(text, 1, len) .. "…"
        if surface.GetTextSize(short) <= width then return short end
        len = len - 1
    end
    return "…"
end

-- Compact overlay geometry; the in-app list keeps its separate layout.
local COMPACT_ROW_H = 64
local COMPACT_ROW_SPACING = 72
local COMPACT_AVATAR_SIZE = 40
local COMPACT_AVATAR_LEFT = 64 -- 12 pad + 40 avatar + 12 gap

local voicePanel,voiceEdge=Color(17,17,20,232),Color(83,27,32,210)
local waveQuiet,waveActive=Color(66,66,72,150),Color(137,186,165,240)
local function drawWave(meter,x,y,w,h,available)
    local step=w/24
    local samples=meter.samples
    local head=meter.sampleHead or 0
    for i=1,24 do
        local level=available and samples and samples[(head+i-1)%24+1] or 0
        -- Square-root display gain exposes quiet speech without altering playback.
        local height=math.max(2,math.sqrt(math.Clamp(level or 0,0,1))*h)
        draw.RoundedBox(1,x+(i-1)*step,y+(h-height)/2,math.max(1,step-2),height,height>2 and waveActive or waveQuiet)
    end
end

local function drawRow(row, x, y, w, small, avatar, avatarLeft)
    local meter = row.meter
    local h = small and COMPACT_ROW_H or 102
    if small then
        draw.RoundedBox(4,x,y,w,h,voiceEdge)
        draw.RoundedBox(4,x+1,y+1,w-2,h-2,voicePanel)
    else draw.RoundedBox(4,x,y,w,h,T.card) end
    local margin = avatarLeft or 66
    local left = x + (avatar and margin or 12)
    local title=V.Title(row)
    local titleWidth=w-(avatar and (margin+18) or 30)
    if row.cachedTitle~=title or row.cachedTitleWidth~=titleWidth then
        row.cachedTitle=title;row.cachedTitleWidth=titleWidth;row.fittedTitle=fit(title,titleWidth)
    end
    draw.SimpleText(row.fittedTitle,"GoobBody",left,y+10,T.text)
    if not small then draw.SimpleText(fit(V.Status(row), w - (left - x) - 14, "GoobSmall"), "GoobSmall", left, y + 32, T.muted) end
    local my = y + (small and 46 or 60)
    if small and row.audible then drawWave(meter,left,y+36,w-(left-x)-14,18,true)
    elseif not small then V.DrawMeter(meter,left,my,w-(left-x)-14,12,row.audible) end
    if not small then
        local text = row.audible and string.format("LEVEL %02d%%   /   PEAK %02d%%", math.floor(meter.level * 100), math.floor(meter.peak * 100)) or "LEVEL —   /   PEAK —"
        draw.SimpleText(fit(text, w - (left - x) - 14, "GoobSmall"), "GoobSmall", left, y + 82, T.muted)
    elseif not row.audible then
        draw.SimpleText(row.muted and "Muted" or "No audio", "GoobSmall", x + w - 14, y + 38, T.muted, TEXT_ALIGN_RIGHT)
    end
end

-- Unparented AvatarImage panels used purely for PaintManual(); the compact
-- overlay is drawn immediate-mode (no vgui row panels) so avatars must be
-- created once per speaking player and cached here, never per frame.
local compactAvatars = {}
local function releaseCompactAvatar(key)
    local panel = compactAvatars[key]
    if IsValid(panel) then panel:Remove() end
    compactAvatars[key] = nil
end
-- alpha is 0-255 (Panel:SetAlpha's own range); the caller also layers a flat
-- dark overlay at (1-alpha) afterwards, since PaintManual() outside the
-- normal vgui paint pass is not documented to honour panel alpha.
local function paintCompactAvatar(ply, x, y, size, alpha255)
    if not IsValid(ply) or ply:IsBot() then
        draw.RoundedBox(2, x, y, size, size, T.line) -- bots get a plain square, no fetch; fades via the caller's SetAlphaMultiplier
        return
    end
    local panel = compactAvatars[ply]
    if not IsValid(panel) then
        panel = vgui.Create("AvatarImage")
        panel:SetMouseInputEnabled(false)
        panel:SetKeyboardInputEnabled(false)
        panel:SetPaintedManually(true)
        panel.avatarSize = 0
        compactAvatars[ply] = panel
    end
    if panel.avatarSize ~= size then
        panel:SetSize(size, size)
        panel:SetPlayer(ply, size)
        panel.avatarSize = size
    end
    panel:SetPos(x, y)
    panel:SetAlpha(alpha255)
    panel:PaintManual()
end

-- Per-participant fade/slide state for the compact overlay, keyed the same
-- way as the row list (row.ply, or the string "anonymous" for the hidden
-- aggregate row). A slot survives its participant dropping out of V.rows
-- (stopped talking, or the scoreboard opened) so it can fade out in place
-- instead of popping; rows below Lerp toward their new target y each frame,
-- which reads as "moving up" once a fully-faded slot is pruned.
local ROW_FADE_IN, ROW_FADE_OUT = 0.28, 0.55 -- eased in the column hook (owner 2026-09-24 late: smoother)
local compactAnim = {}
local compactOrder = {}
local fadeOverlay = Color(T.bg.r, T.bg.g, T.bg.b, 0) -- mutated in place, never reallocated

-- === Orb primitives shared by the over-head, dock and monitor orbs ==============================================
local orbPlate = Color(T.ink.r, T.ink.g, T.ink.b, 255) -- solid fill, never translucent
local orbEdge = Color(0, 0, 0, 0)  -- mutated in place per draw (no allocation in HUDPaint)
local circleCache, orbPoly = {}, {}
-- Unit rings for polyline strokes (charge arc, feathered rings, flashes): cos/sin sampled once per segment count.
local unitRings = {}
local function unitRing(n)
    local ring = unitRings[n]
    if ring then return ring end
    ring = {}
    for i = 0, n do local a = i / n * math.pi * 2; ring[i + 1] = {x = math.cos(a), y = math.sin(a)} end
    unitRings[n] = ring
    return ring
end
local ringPts = {}
-- `count` points of an n-segment ring of radius r, starting at ring index `start` (0 = to the right, clockwise).
local function ringPath(cx, cy, r, n, count, start)
    local ring = unitRing(n)
    for i = 1, count do
        local u, v = ring[((start or 0) + i - 1) % n + 1], ringPts[i] or {}
        v.x, v.y = cx + u.x * r, cy + u.y * r
        ringPts[i] = v
    end
    return ringPts, count
end
local function circle(cx, cy, r, color)
    local key = math.max(1, math.floor(r * 4))
    local shape = circleCache[key]
    if not shape then
        shape = {}
        local n = 96
        for i = 0, n - 1 do
            local a = i / n * math.pi * 2
            shape[i + 1] = {x = math.cos(a) * (key / 4), y = math.sin(a) * (key / 4)}
        end
        circleCache[key] = shape
    end
    for i = 1, #shape do
        local v = orbPoly[i] or {}
        v.x, v.y = cx + shape[i].x, cy + shape[i].y
        orbPoly[i] = v
    end
    for i = #orbPoly, #shape + 1, -1 do orbPoly[i] = nil end
    draw.NoTexture()
    surface.SetDrawColor(color.r, color.g, color.b, color.a)
    surface.DrawPoly(orbPoly)
end
-- Circular mask for the avatar: the usual 2D stencil pattern (write 1 inside the circle, then draw only where == 1).
-- Screen-space transform of whatever model matrix is pushed (the column's 0.75 scale); identity elsewhere.
local matOX, matOY, matS = 0, 0, 1
local clearStencilRect = render and render.ClearStencilBufferRectangle
local function stencilCircleBegin(cx, cy, r)
    if clearStencilRect then
        -- clear only this orb's rectangle (screen pixels), not the whole buffer, once per avatar
        local x0, y0 = matOX + (cx - r - 2 - matOX) * matS, matOY + (cy - r - 2 - matOY) * matS
        local x1, y1 = matOX + (cx + r + 2 - matOX) * matS, matOY + (cy + r + 2 - matOY) * matS
        clearStencilRect(math.floor(x0), math.floor(y0), math.ceil(x1), math.ceil(y1), 0)
    else
        render.ClearStencil()
    end
    render.SetStencilEnable(true)
    render.SetStencilWriteMask(255)
    render.SetStencilTestMask(255)
    render.SetStencilReferenceValue(1)
    render.SetStencilCompareFunction(STENCIL_NEVER)
    render.SetStencilFailOperation(STENCIL_REPLACE)
    render.SetStencilPassOperation(STENCIL_KEEP)
    render.SetStencilZFailOperation(STENCIL_KEEP)
    circle(cx, cy, r, T.white)
    render.SetStencilCompareFunction(STENCIL_EQUAL)
    render.SetStencilFailOperation(STENCIL_KEEP)
end
local function stencilEnd() render.SetStencilEnable(false) end

local ELECTRIC_BLUE = Color(90, 175, 255)
local electric = T.accent
local electricMul = 1 -- 2 for staff (owner 2026-09-24: "drive staff electricity up 2x")
local function isStaffPlayer(ply)
    return IsValid(ply) and (ply:IsAdmin() or (ply.CheckGroup and ply:CheckGroup("operator"))) == true
end
-- per slot, refreshed every 2 s: the group lookup is not a per-frame question
local function slotStaff(slot, now)
    if now - (slot.staffAt or -10) >= 2 then
        slot.staffAt = now
        slot.isStaff = isStaffPlayer(slot.ply)
        slot.isSuper = IsValid(slot.ply) and slot.ply.IsSuperAdmin ~= nil and slot.ply:IsSuperAdmin() == true
        -- the tag is the player's own usergroup (owner 2026-09-24 late: "it says staff instead of my role")
        slot.role = (IsValid(slot.ply) and slot.ply.GetUserGroup) and string.upper(tostring(slot.ply:GetUserGroup() or "")) or ""
    end
    return slot.isStaff
end
local sparkGlow, sparkCore, sparkFlash = Color(0, 0, 0, 0), Color(255, 255, 255, 255), Color(255, 255, 255, 255)
local sparkSoft = Color(0, 0, 0, 0)
local glowMat = Material("sprites/light_glow02_add") -- additive: stacked glows brighten instead of muddying
local quad = {{x = 0, y = 0}, {x = 0, y = 0}, {x = 0, y = 0}, {x = 0, y = 0}}
-- A stroke of width w between two points (a quad, wound clockwise for DrawPoly). Lines here are strokes, not pixels.
-- Texture and colour are set ONCE per polyline by thickPolyline, not per segment (2026-09-25 perf pass).
local function thickLine(x1, y1, x2, y2, w)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then return end
    local nx, ny = -dy / len * w / 2, dx / len * w / 2
    quad[1].x, quad[1].y = x1 - nx, y1 - ny
    quad[2].x, quad[2].y = x2 - nx, y2 - ny
    quad[3].x, quad[3].y = x2 + nx, y2 + ny
    quad[4].x, quad[4].y = x1 + nx, y1 + ny
    surface.DrawPoly(quad)
end
local function thickPolyline(pts, n, w, color)
    n = math.min(n, pts.n or #pts)
    if n < 2 then return end
    draw.NoTexture()
    surface.SetDrawColor(color.r, color.g, color.b, color.a)
    for i = 1, n - 1 do thickLine(pts[i].x, pts[i].y, pts[i + 1].x, pts[i + 1].y, w) end
end
-- Glow sprites are queued and flushed in one textured batch (one SetMaterial per flush instead of one per dot).
-- Colours are copied at queue time because callers reuse mutable Color objects.
local dots, dotN = {}, 0
local function glowDot(x, y, size, color)
    dotN = dotN + 1
    local d = dots[dotN]
    if not d then d = {} dots[dotN] = d end
    d.x, d.y, d.s, d.r, d.g, d.b, d.a = x, y, size, color.r, color.g, color.b, color.a
end
local function flushDots()
    if dotN == 0 then return end
    surface.SetMaterial(glowMat)
    for i = 1, dotN do
        local d = dots[i]
        surface.SetDrawColor(d.r, d.g, d.b, d.a)
        surface.DrawTexturedRect(d.x - d.s / 2, d.y - d.s / 2, d.s, d.s)
    end
    dotN = 0
    draw.NoTexture()
end
-- One bolt drawn in four passes: wide soft glow, mid glow, white core, branches thinner; revealed from the ring
-- outward over its first third of life and flickering per frame, with additive glows at the root and the tips.
local function drawBolt(sp, fade, now)
    local flicker = 0.75 + 0.25 * math.sin(now * 90 + sp.ang * 7)
    local total = sp.pts.n
    local n = math.max(2, math.ceil(total * math.min(1, ((now - sp.born) / sp.life) / 0.3)))
    local detail = Q >= 0.6 and not sp.short -- feather pass and along-trunk bloom: gone on slow frames and on short border bolts
    sparkSoft.r, sparkSoft.g, sparkSoft.b, sparkSoft.a = electric.r, electric.g, electric.b, 55 * fade * flicker
    thickPolyline(sp.pts, n, 9, sparkSoft)
    sparkGlow.r, sparkGlow.g, sparkGlow.b, sparkGlow.a = electric.r + (255 - electric.r) * 0.35, electric.g + (255 - electric.g) * 0.35, electric.b + (255 - electric.b) * 0.35, 170 * fade * flicker
    thickPolyline(sp.pts, n, 3.2, sparkGlow)
    if detail then
        sparkCore.a = 110 * fade * flicker
        thickPolyline(sp.pts, n, 2.6, sparkCore) -- feather under the core: softens the 1-px stair-steps
    end
    sparkCore.a = 255 * fade * flicker
    thickPolyline(sp.pts, n, 1.4, sparkCore)
    if detail then for i = 2, n, 2 do glowDot(sp.pts[i].x, sp.pts[i].y, 14, sparkGlow) end end -- additive bloom along the trunk
    if n >= total then
        for j = 1, sp.nb do
            local br = sp.branches[j]
            thickPolyline(br, br.n, 3.5, sparkSoft)
            sparkGlow.a = 140 * fade * flicker
            thickPolyline(br, br.n, 1.6, sparkGlow)
            if detail then
                sparkCore.a = 210 * fade * flicker
                thickPolyline(br, br.n, 0.8, sparkCore)
            end
            glowDot(br[br.n].x, br[br.n].y, 8, sparkGlow)
        end
    end
    local tip = sp.pts[n]
    sparkFlash.a = 230 * fade * flicker
    glowDot(tip.x, tip.y, 10, sparkFlash)
    glowDot(sp.pts[1].x, sp.pts[1].y, 18, sparkGlow)
    glowDot(sp.pts[1].x, sp.pts[1].y, 7, sparkFlash)
end
-- Arcs that crawl around the ring while someone is loud: the border itself is electrified, not just sparking.
local arcPts = {}
local function drawRingArcs(cx, cy, radius, show, t)
    if not electricityEnabled() or show < 0.3 or Q < 0.3 then return end
    local strength = math.min(1, (show - 0.3) / 0.5)
    local count = show > 0.6 and 3 or 2
    local speed = 4 + show * 12
    for k = 1, count do
        local a0 = t * speed * (k % 2 == 0 and -1 or 1) + k * (math.pi * 2 / count)
        local span = 0.45 + strength * 0.5
        for i = 0, 7 do
            local a = a0 + span * i / 7
            local wob = (math.sin(t * 40 + i * 1.7 + k) * 1.2) * strength
            local v = arcPts[i + 1] or {}
            v.x, v.y = cx + math.cos(a) * (radius + wob), cy + math.sin(a) * (radius + wob)
            arcPts[i + 1] = v
        end
        sparkSoft.r, sparkSoft.g, sparkSoft.b, sparkSoft.a = electric.r, electric.g, electric.b, 70 * strength
        thickPolyline(arcPts, 8, 5, sparkSoft)
        sparkCore.a = 200 * strength
        thickPolyline(arcPts, 8, 1.4, sparkCore)
        glowDot(arcPts[8].x, arcPts[8].y, 9, sparkCore)
    end
end
-- Midpoint-displacement lightning: split the segment, push the midpoint sideways by a random amount that halves
-- with each level, and sometimes throw a shorter branch off the midpoint. depth 3 = 8 segments on the trunk.
-- Point lists carry their own count (.n) and are rebuilt IN PLACE: a bolt re-randomises every 35 ms for its whole
-- life, so nothing here allocates once the pools are warm (2026-09-25 perf pass).
local function addPt(list, x, y)
    local n = list.n + 1
    local v = list[n]
    if v then v.x, v.y = x, y else list[n] = {x = x, y = y} end
    list.n = n
end
local boltBudget = {n = 3}
local function fractal(out, x1, y1, x2, y2, depth, jitter, sp)
    if depth == 0 then addPt(out, x2, y2) return end
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.001 then len = 0.001 end
    local px, py = -dy / len, dx / len
    local off = (math.random() - 0.5) * 2 * jitter * len
    local mx, my = (x1 + x2) / 2 + px * off, (y1 + y2) / 2 + py * off
    fractal(out, x1, y1, mx, my, depth - 1, jitter, sp)
    if depth >= 2 and boltBudget.n > 0 and math.random() < 0.45 then
        boltBudget.n = boltBudget.n - 1
        local ang = math.atan2(dy, dx) + (math.random() < 0.5 and -1 or 1) * (0.5 + math.random() * 0.7)
        local blen = len * (0.35 + math.random() * 0.35)
        local nb = sp.nb + 1
        local branch = sp.branches[nb]
        if not branch then branch = {n = 0} sp.branches[nb] = branch end
        branch.n = 0
        sp.nb = nb
        addPt(branch, mx, my)
        fractal(branch, mx, my, mx + math.cos(ang) * blen, my + math.sin(ang) * blen, depth - 1, jitter, sp)
    end
    fractal(out, mx, my, x2, y2, depth - 1, jitter, sp)
end
-- (Re)generate a bolt's path from its stored endpoints: called at spawn and every few frames while it lives, so
-- the bolt writhes instead of freezing in one shape.
local function buildBolt(sp)
    sp.pts.n = 1
    sp.nb = 0
    boltBudget.n = 3
    if sp.ctrlX then
        -- a curved bolt: fractal jitter applied segment by segment along a quadratic curve through the control point
        local px, py = sp.x1, sp.y1
        for i = 1, 6 do
            local t = i / 6; local u = 1 - t
            local qx = u * u * sp.x1 + 2 * u * t * sp.ctrlX + t * t * sp.x2
            local qy = u * u * sp.y1 + 2 * u * t * sp.ctrlY + t * t * sp.y2
            fractal(sp.pts, px, py, qx, qy, 2, sp.jitter, sp)
            px, py = qx, qy
        end
        return
    end
    fractal(sp.pts, sp.x1, sp.y1, sp.x2, sp.y2, 3, sp.jitter, sp)
end
-- Spark and mote objects are pooled; a pruned one goes back for the next spawn. Lists are swap-removed.
local sparkPool, sparkPoolN, motePool, motePoolN = {}, 0, {}, 0
local function takeSpark()
    if sparkPoolN > 0 then
        local sp = sparkPool[sparkPoolN]
        sparkPool[sparkPoolN] = nil
        sparkPoolN = sparkPoolN - 1
        return sp
    end
    return {pts = {n = 0}, branches = {}, nb = 0}
end
local function dropSpark(list, i)
    local sp = list[i]
    local last = #list
    list[i] = list[last]
    list[last] = nil
    sp.ctrlX, sp.ctrlY, sp.electric = nil, nil, nil
    sparkPoolN = sparkPoolN + 1
    sparkPool[sparkPoolN] = sp
end
local function dropMote(list, i)
    local m = list[i]
    local last = #list
    list[i] = list[last]
    list[last] = nil
    motePoolN = motePoolN + 1
    motePool[motePoolN] = m
end
local SPARK_GLOBAL = 48 -- live sparks across every orb on screen (column, over-head, dock, monitor), scaled by Q
local function spawnSpark(slot, kind, cx, cy, rr, show, groundY, halfW)
    if not electricityEnabled() then return end
    local list = slot.sparks
    if #list >= math.floor(12 * electricMul * Q) or sparkCount >= SPARK_GLOBAL * Q then return end -- 20 -> 12 per orb (2026-09-25 perf pass)
    local ang = math.random() * math.pi * 2
    local dir = math.random() < 0.5 and -1 or 1
    local sp = takeSpark()
    sp.kind, sp.born, sp.ang, sp.cx, sp.cy, sp.rr, sp.short = kind, RealTime(), ang, cx, cy, rr, nil
    sp.pts.n = 0
    sp.nb = 0
    if kind == "lick" then
        sp.life = 0.14 + math.random() * 0.12
        local L = 4 + math.random() * 7
        for i = 0, 3 do
            local t = i / 3
            local aa, rad = ang + dir * 0.45 * t * t, rr + L * t
            addPt(sp.pts, cx + math.cos(aa) * rad, cy + math.sin(aa) * rad)
        end
    else
        sp.life = 0.07 + math.random() * 0.11
        local x2, y2
        if groundY and math.random() < 0.35 then
            -- a grounding arc: from the ring down into the shoulders, the way a charge finds the body
            x2, y2 = cx + (math.random() * 2 - 1) * halfW * 0.85, groundY + math.random() * 5
            ang = math.atan2(y2 - cy, x2 - cx)
            sp.jitter = 0.17
        else
            local L = (18 + math.random() * 26 + show * 16) * (0.7 + 0.3 * electricMul)
            local spread = (math.random() - 0.5) * 0.9 -- bolts leave the ring roughly radially, not dead straight
            x2, y2 = cx + math.cos(ang) * rr + math.cos(ang + spread) * L, cy + math.sin(ang) * rr + math.sin(ang + spread) * L
            sp.jitter = 0.22
        end
        sp.ang = ang
        sp.x1, sp.y1, sp.x2, sp.y2 = cx + math.cos(ang) * rr, cy + math.sin(ang) * rr, x2, y2
        addPt(sp.pts, sp.x1, sp.y1)
        sp.regen = RealTime()
        buildBolt(sp)
        -- motes thrown off the far end, and the ring flashes white where the bolt left it
        slot.motes = slot.motes or {}
        if Q >= 0.6 then
            for _ = 1, 3 do
                if #slot.motes >= 24 then break end
                local ma = math.random() * math.pi * 2
                local sp2 = 30 + math.random() * 60
                local m
                if motePoolN > 0 then m = motePool[motePoolN]; motePool[motePoolN] = nil; motePoolN = motePoolN - 1 else m = {} end
                m.x, m.y, m.vx, m.vy, m.born, m.life = x2, y2, math.cos(ma) * sp2, math.sin(ma) * sp2, RealTime(), 0.14 + math.random() * 0.14
                slot.motes[#slot.motes + 1] = m
            end
        end
        slot.ringFlash = RealTime()
    end
    list[#list + 1] = sp
    sparkCount = sparkCount + 1
end
local function drawPolyline(pts, color, ox, oy)
    surface.SetDrawColor(color.r, color.g, color.b, color.a)
    for i = 1, #pts - 1 do surface.DrawLine(pts[i].x + ox, pts[i].y + oy, pts[i + 1].x + ox, pts[i + 1].y + oy) end
end
local function drawSparks(slot, show, cx, cy, rr, reducedMotion, dt, groundY, halfW)
    if not electricityEnabled() then
        slot.sparks, slot.motes, slot.ringFlash, slot.sparkAcc = {}, nil, nil, 0
        return
    end
    slot.sparks = slot.sparks or {}
    local list = slot.sparks
    local now = RealTime()
    sparkCount = sparkCount + #list
    -- licks from ~15% of full level, bolts from ~40%; both rates climb with the level (VoiceVolume rarely
    -- exceeds ~0.6 for ordinary speech, and show = sqrt(level), so a raised voice does reach the bolt band)
    if not reducedMotion and show > 0.1 and Q > 0 then
        local lickRate = (show - 0.1) * 40 * electricMul * Q
        local boltRate = show > 0.3 and (show - 0.3) * 110 * electricMul * Q or 0
        slot.sparkAcc = (slot.sparkAcc or 0) + dt * (lickRate + boltRate)
        while slot.sparkAcc >= 1 do
            slot.sparkAcc = slot.sparkAcc - 1
            local bolt = boltRate > 0 and math.random() < boltRate / (lickRate + boltRate)
            spawnSpark(slot, bolt and "bolt" or "lick", cx, cy, rr, show, groundY, halfW)
        end
    end
    for i = #list, 1, -1 do
        local sp = list[i]
        local age = (now - sp.born) / sp.life
        if age >= 1 then
            dropSpark(list, i)
        else
            local fade = 1 - age
            if sp.kind == "bolt" then
                if now - sp.regen > 0.035 then sp.regen = now; buildBolt(sp) end
                drawBolt(sp, fade, now)
            else
                sparkGlow.r, sparkGlow.g, sparkGlow.b = electric.r + (255 - electric.r) * 0.4, electric.g + (255 - electric.g) * 0.4, electric.b + (255 - electric.b) * 0.4
                sparkGlow.a = 230 * fade
                thickPolyline(sp.pts, sp.pts.n, 1.6, sparkGlow)
                glowDot(sp.pts[sp.pts.n].x, sp.pts[sp.pts.n].y, 7, sparkGlow)
            end
        end
    end
    -- motes: tiny glowing embers drifting off bolt tips
    local motes = slot.motes
    if motes then
        for i = #motes, 1, -1 do
            local m = motes[i]
            local age = (now - m.born) / m.life
            if age >= 1 then
                dropMote(motes, i)
            else
                m.x, m.y = m.x + m.vx * dt, m.y + m.vy * dt
                sparkFlash.a = 255 * (1 - age)
                glowDot(m.x, m.y, 5 - 2 * age, sparkFlash)
            end
        end
    end
    -- ring flash: a white stroke around the whole ring for a few frames after a bolt leaves it
    local flashAge = slot.ringFlash and (now - slot.ringFlash) / 0.09 or 1
    if flashAge < 1 then
        local pts, n = ringPath(cx, cy, rr, 28, 29)
        sparkCore.a = 230 * (1 - flashAge)
        thickPolyline(pts, n, 1.6, sparkCore)
    end
end

-- === Voice column (owner 2026-09-24, built from the approved mockup; recoloured to the GoobOS theme) =============
-- One flat plate per speaker, flush against the right screen edge: the Steam avatar as a rounded square with a
-- level-driven ring, the name, and a 24-bar visualizer driven by the one engine level. GoobOS colours throughout
-- (T.bg plate, T.line hairline, T.accent voice, T.text/T.muted names); staff keep the established electric blue and
-- carry their usergroup as a tag; a hidden identity is an italic "Unknown voice" on a mosaic tile; a player you
-- muted is dim with a struck mic. Electricity lives on the plate BORDER of superadmins only (owner) and does not
-- depend on the decorative-electricity switch that gates the orbs. Sizes are the 1080p mockup values scaled by
-- ScrH/1080; no model matrix, so text is drawn at its true size. The charge/report/burst behaviour of the old orb
-- column is kept: the charge is a thin line along the plate's bottom edge, the burst a white flash.
local ROW_PLATE = Color(T.bg.r, T.bg.g, T.bg.b, 222)
local ROW_PLATE_SOLID = Color(T.bg.r, T.bg.g, T.bg.b, 255)
local ROW_HAIR = Color(T.line.r, T.line.g, T.line.b, 210)
local ROW_HDR = Color(T.muted.r, T.muted.g, T.muted.b, 170)
local MOSAIC_A, MOSAIC_B = Color(T.card.r + 14, T.card.g + 12, T.card.b + 12), T.card
local rowAcc, rowRing, rowHair = Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0) -- mutated per row, never reallocated
local G = {scrH = -1} -- column geometry for the current screen height (fonts are rebuilt with it)
local function layout()
    local h = ScrH()
    if G.scrH == h then return G end
    local s = h / 1080
    local function sc(v) return math.max(1, math.floor(v * s + 0.5)) end
    G.scrH, G.s = h, s
    G.W, G.H, G.PAD, G.AVA, G.GAP, G.R = sc(236), sc(44), sc(8), sc(32), sc(10), sc(8)
    G.NAME_Y, G.NAME_H, G.VIZ_H, G.BAR_W, G.BAR_GAP, G.BAR_MIN = sc(7), sc(15), sc(10), sc(4), sc(3), sc(2)
    G.ROW_GAP, G.EDGE, G.CHIP_H, G.CHIP_PAD, G.CHIP_R = sc(6), sc(8), sc(22), sc(11), sc(6)
    G.TAG_DY, G.TAG_SP, G.HDR_UP, G.HDR_SP, G.GLYPH = sc(4), 1.6 * s, sc(16), 2.2 * s, sc(12)
    surface.CreateFont("GoobVoiceName", {font = "Roboto", size = sc(14), weight = 600, antialias = true, extended = true})
    surface.CreateFont("GoobVoiceNameItalic", {font = "Roboto", size = sc(14), weight = 500, italic = true, antialias = true, extended = true})
    surface.CreateFont("GoobVoiceSmall", {font = "Roboto", size = sc(11), weight = 600, antialias = true, extended = true})
    surface.CreateFont("GoobVoiceTag", {font = "Roboto", size = sc(9), weight = 700, antialias = true, extended = true})
    return G
end
-- The visualizer: a speech-shaped envelope (middle bars tallest) and a slow per-bar wobble, so one scalar level
-- reads as a breathing spectrum instead of bars pumping in unison. Each bar's height is smoothed per frame (fast
-- up, slow down), which is what keeps the motion soft. Presentation only; the level is the engine's.
local BAR_N = 24
local barEnv, barFreq, barPhase = {}, {}, {}
for i = 1, BAR_N do
    local d = math.abs((i - 1) / (BAR_N - 1) - 0.42) * 1.7
    barEnv[i] = math.Clamp(d < 1 and 0.35 + 0.65 * (1 - d) ^ 1.4 or 0.35, 0.3, 1)
    barFreq[i] = 7 + ((i * 7) % 11) * 0.8
    barPhase[i] = i * 2.399
end
local function stepBars(slot, n, show, live, dt, now, reducedMotion)
    local bars = slot.bars
    if not bars then bars = {} slot.bars = bars end
    local up, down = 1 - math.exp(-dt * 28), 1 - math.exp(-dt * 9)
    for i = 1, n do
        local target = 0
        if live then
            local e = barEnv[math.floor((i - 1) / math.max(1, n - 1) * (BAR_N - 1) + 1.5)]
            local wob = reducedMotion and 0.8 or (0.6 + 0.4 * math.sin(now * barFreq[i] + barPhase[i]))
            target = show * e * wob
        end
        local h = bars[i] or 0
        bars[i] = h + (target - h) * (target > h and up or down)
    end
    return bars
end
-- The accent lifted toward white with the level (the old orbs' "hot" edge), into a reusable colour.
local function liftInto(c, base, hot, alpha)
    c.r, c.g, c.b, c.a = base.r + (255 - base.r) * hot, base.g + (255 - base.g) * hot, base.b + (255 - base.b) * hot, alpha
    return c
end
-- Letter-spaced caps (role tag, "N TALKING"): the engine has no tracking, so the glyphs are placed one by one.
local function spacedWidth(text, font, spacing)
    surface.SetFont(font)
    local total = -spacing
    for i = 1, #text do total = total + surface.GetTextSize(string.sub(text, i, i)) + spacing end
    return total
end
local function drawSpaced(text, font, x, y, color, spacing, align)
    local total = spacedWidth(text, font, spacing)
    if align == TEXT_ALIGN_RIGHT then x = x - total end
    for i = 1, #text do
        local ch = string.sub(text, i, i)
        draw.SimpleText(ch, font, x, y, color, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        x = x + surface.GetTextSize(ch) + spacing
    end
    return total
end
-- A rounded-rect path, clockwise from the top-left corner, closed (last point = first). Right corners square when
-- `roundRight` is false (the plate meets the screen edge there). Reused buffer; `n` points valid.
local rrPts = {}
local function rrArc(cx, cy, r, from, n)
    local ring = unitRing(32)
    for i = 0, 8 do
        n = n + 1
        local u, v = ring[from + i + 1], rrPts[n] or {}
        v.x, v.y = cx + u.x * r, cy + u.y * r
        rrPts[n] = v
    end
    return n
end
local function rrPoint(px, py, n)
    n = n + 1
    local v = rrPts[n] or {}
    v.x, v.y = px, py
    rrPts[n] = v
    return n
end
local function roundRectPath(x, y, w, h, r, roundRight)
    local n = rrArc(x + r, y + r, r, 16, 0)
    if roundRight then
        n = rrArc(x + w - r, y + r, r, 24, n)
        n = rrArc(x + w - r, y + h - r, r, 0, n)
    else
        n = rrPoint(x + w, y, n)
        n = rrPoint(x + w, y + h, n)
    end
    n = rrArc(x + r, y + h - r, r, 8, n)
    n = rrPoint(rrPts[1].x, rrPts[1].y, n)
    for i = #rrPts, n + 1, -1 do rrPts[i] = nil end
    rrPts.n = n
    return rrPts, n
end
-- Rounded-square mask for the avatar (same stencil pattern as the circle; the mask is a polygon, not a textured
-- box, because every rasterised texel of a textured corner would write the stencil, alpha or not).
local function stencilRectBegin(x, y, w, h, r)
    if clearStencilRect then
        clearStencilRect(math.floor(x - 1), math.floor(y - 1), math.ceil(x + w + 1), math.ceil(y + h + 1), 0)
    else
        render.ClearStencil()
    end
    render.SetStencilEnable(true)
    render.SetStencilWriteMask(255)
    render.SetStencilTestMask(255)
    render.SetStencilReferenceValue(1)
    render.SetStencilCompareFunction(STENCIL_NEVER)
    render.SetStencilFailOperation(STENCIL_REPLACE)
    render.SetStencilPassOperation(STENCIL_KEEP)
    render.SetStencilZFailOperation(STENCIL_KEEP)
    local pts = roundRectPath(x, y, w, h, r, true)
    draw.NoTexture()
    surface.SetDrawColor(255, 255, 255, 255)
    surface.DrawPoly(pts)
    render.SetStencilCompareFunction(STENCIL_EQUAL)
    render.SetStencilFailOperation(STENCIL_KEEP)
end
-- Rounding the avatar's corners without the stencil (2026-09-25 perf pass; owner: "optimize"): the picture is drawn as
-- a plain square, then each corner is covered with the plate colour through draw.RoundedBox's own quarter-disc
-- texture under an inverted blend (dst keeps where the disc is, plate colour comes through outside it, blended at
-- the texture's soft edge). 4 textured quads instead of a stencil clear, a 37-point mask polygon and a 36-quad
-- feather stroke per row per frame. The blend ignores the alpha multiplier, so it is exact only at full alpha: a row
-- mid-fade keeps the stencil mask (no feather). render.OverrideBlend is documented as unreliable on Linux clients,
-- and its 2D use is unverified in a real client: zc_goobos_voice_cornerblend 0 forces the stencil path.
local cornerBlendCv = CreateClientConVar("zc_goobos_voice_cornerblend", "1", true, false, "Voice avatars: 1 blend the corners (cheap), 0 stencil mask", 0, 1)
local cornerTex8, cornerTex16 = surface.GetTextureID("gui/corner8"), surface.GetTextureID("gui/corner16")
local function cornerBlendOK(alpha)
    return alpha >= 1 and render.OverrideBlend ~= nil and cornerBlendCv:GetBool() and not (system and system.IsLinux and system.IsLinux())
end
local function roundCorners(x, y, w, h, r, col)
    surface.SetTexture(r > 8 and cornerTex16 or cornerTex8)
    surface.SetDrawColor(col.r, col.g, col.b, 255)
    render.OverrideBlend(true, BLEND_ONE_MINUS_SRC_ALPHA, BLEND_SRC_ALPHA, BLENDFUNC_ADD)
    surface.DrawTexturedRectUV(x, y, r, r, 0, 0, 1, 1)
    surface.DrawTexturedRectUV(x + w - r, y, r, r, 1, 0, 0, 1)
    surface.DrawTexturedRectUV(x, y + h - r, r, r, 0, 1, 1, 0)
    surface.DrawTexturedRectUV(x + w - r, y + h - r, r, r, 1, 1, 0, 0)
    render.OverrideBlend(false)
    draw.NoTexture()
end
local function maskBegin(x, y, w, h, r, blend)
    if not blend then stencilRectBegin(x, y, w, h, r) end
end
local function maskEnd(x, y, w, h, r, blend, col)
    if blend then roundCorners(x, y, w, h, r, col) else stencilEnd() end
end
-- A point `d` pixels along a plate's border with its outward normal. `full` walks all four sides clockwise from the
-- top-left corner; otherwise the three free sides of an edge-flush plate, clockwise from the bottom-right corner
-- (bottom edge leftwards, up the left side, top edge rightwards) - the right edge is the screen edge.
local function edgePoint(x, y, W, H, R, d, full)
    local q = math.pi * R / 2
    if full then
        if d < W - 2 * R then return x + R + d, y, 0, -1 end
        d = d - (W - 2 * R)
        if d < q then
            local aa = -math.pi / 2 + d / R
            return x + W - R + math.cos(aa) * R, y + R + math.sin(aa) * R, math.cos(aa), math.sin(aa)
        end
        d = d - q
        if d < H - 2 * R then return x + W, y + R + d, 1, 0 end
        d = d - (H - 2 * R)
        if d < q then
            local aa = d / R
            return x + W - R + math.cos(aa) * R, y + H - R + math.sin(aa) * R, math.cos(aa), math.sin(aa)
        end
        d = d - q
        if d < W - 2 * R then return x + W - R - d, y + H, 0, 1 end
        d = d - (W - 2 * R)
    else
        if d < W - R then return x + W - d, y + H, 0, 1 end
        d = d - (W - R)
    end
    if d < q then
        local aa = math.pi / 2 + d / R
        return x + R + math.cos(aa) * R, y + H - R + math.sin(aa) * R, math.cos(aa), math.sin(aa)
    end
    d = d - q
    if d < H - 2 * R then return x, y + H - R - d, -1, 0 end
    d = d - (H - 2 * R)
    if d < q then
        local aa = math.pi + d / R
        return x + R + math.cos(aa) * R, y + R + math.sin(aa) * R, math.cos(aa), math.sin(aa)
    end
    d = d - q
    return x + R + d, y, 0, -1
end
local function edgeLength(W, H, R, full)
    if full then return 2 * (W - 2 * R) + 2 * (H - 2 * R) + 2 * math.pi * R end
    return 2 * (W - R) + math.pi * R + (H - 2 * R)
end
local function spawnEdgeBolt(slot, x, y, W, H, R, show, now, full)
    local list = slot.sparks
    if #list >= math.floor(12 * Q) or sparkCount >= SPARK_GLOBAL * Q then return end
    local sp = takeSpark()
    local px, py, nx, ny = edgePoint(x, y, W, H, R, math.random() * edgeLength(W, H, R, full), full)
    local ang = math.atan2(ny, nx) + (math.random() - 0.5) * 1.2
    local len = 10 + math.random() * 16 + show * 10
    sp.kind, sp.born, sp.life, sp.ang, sp.jitter, sp.short = "bolt", now, 0.07 + math.random() * 0.11, ang, 0.22, true
    sp.x1, sp.y1, sp.x2, sp.y2 = px, py, px + math.cos(ang) * len, py + math.sin(ang) * len
    sp.pts.n = 0
    sp.nb = 0
    addPt(sp.pts, px, py)
    sp.regen = now
    buildBolt(sp)
    list[#list + 1] = sp
    sparkCount = sparkCount + 1
end
-- Border electricity for a superadmin's plate: arcs crawling along the border (always at least a faint crawl, so a
-- superadmin's plate is visibly charged even between words) and short bolts leaving it, rate and count driven by
-- the level and thinned by the frame governor Q. Not gated by zc_goobos_voice_electricity (owner 2026-09-24 late:
-- "I don't see any sort of electricity"); that switch stays the orbs' decorative toggle.
local edgeArc = {}
local function drawEdgeElectricity(slot, x, y, W, H, R, show, dt, now, full)
    if Q <= 0 then
        slot.sparks, slot.sparkAcc = nil, 0
        return
    end
    electric, electricMul = ELECTRIC_BLUE, 2
    slot.sparks = slot.sparks or {}
    local list = slot.sparks
    sparkCount = sparkCount + #list
    local L = edgeLength(W, H, R, full)
    local strength = 0.3 + 0.7 * math.min(1, show / 0.6)
    local count = show > 0.5 and 3 or 2
    local speed = 50 + show * 170
    for k = 1, count do
        local d0 = (now * speed * (k % 2 == 0 and -1 or 1) + k * L / count) % L
        local span = 14 + strength * 16
        for i = 0, 7 do
            local px, py, nx, ny = edgePoint(x, y, W, H, R, (d0 + span * i / 7) % L, full)
            local wob = math.sin(now * 40 + i * 1.7 + k) * 1.2 * strength
            local v = edgeArc[i + 1] or {}
            v.x, v.y = px + nx * wob, py + ny * wob
            edgeArc[i + 1] = v
        end
        sparkSoft.r, sparkSoft.g, sparkSoft.b, sparkSoft.a = electric.r, electric.g, electric.b, 70 * strength
        thickPolyline(edgeArc, 8, 5, sparkSoft)
        sparkCore.a = 200 * strength
        thickPolyline(edgeArc, 8, 1.4, sparkCore)
        glowDot(edgeArc[8].x, edgeArc[8].y, 9, sparkCore)
    end
    if show > 0.2 then
        slot.sparkAcc = (slot.sparkAcc or 0) + dt * (show - 0.2) * 70 * Q
        while slot.sparkAcc >= 1 do
            slot.sparkAcc = slot.sparkAcc - 1
            spawnEdgeBolt(slot, x, y, W, H, R, show, now, full)
        end
    else
        slot.sparkAcc = 0
    end
    for i = #list, 1, -1 do
        local sp = list[i]
        local age = (now - sp.born) / sp.life
        if age >= 1 then
            dropSpark(list, i)
        else
            if now - sp.regen > 0.035 then sp.regen = now; buildBolt(sp) end
            drawBolt(sp, 1 - age, now)
        end
    end
end
-- The burst (zc_voice_explode): a white flash over the avatar and the plate; bolts as well on a superadmin plate.
local function drawBurst(slot, x, y, W, H, R, cx, cy, size, accent, super, now, full)
    -- as before, the flash follows the decorative switch - except on a superadmin plate, whose electricity never did
    if not electricityEnabled() and not super then slot.burst, slot.burstFired = nil, nil end
    if not slot.burst then return end
    local age = (now - slot.burst) / 0.6
    if age >= 1 then slot.burst, slot.burstFired = nil, nil return end
    if not slot.burstFired then
        slot.burstFired = true
        if super and Q > 0 then
            slot.sparks = slot.sparks or {}
            for _ = 1, 16 do spawnEdgeBolt(slot, x, y, W, H, R, 1, now, full) end
        end
    end
    sparkFlash.a = 255 * (1 - age)
    glowDot(cx, cy, size * (3 + 8 * age), sparkFlash)
    sparkGlow.r, sparkGlow.g, sparkGlow.b, sparkGlow.a = accent.r, accent.g, accent.b, 160 * (1 - age)
    glowDot(x + W / 2, y + H / 2, W * (0.8 + 0.8 * age), sparkGlow)
end
local function drawVoiceRow(slot, x, y, dt, now, reducedMotion)
    local row, g = slot.row, G
    local W, H, R, AV = g.W, g.H, g.R, g.AVA
    local ply = slot.ply
    local identified = ply ~= nil
    local muted = row.muted == true
    local audible = row.audible and not muted
    local staff = slotStaff(slot, now)
    local super = staff and slot.isSuper == true
    local meter = row.meter or {}
    local level = audible and math.Clamp(meter.level or 0, 0, 1) or 0
    -- per-speaker auto-gain (2026-09-24): measured against this speaker's own recent loudest moment
    slot.gain = math.max(0.12, (slot.gain or 0.3) * (1 - dt * 0.08), level)
    local show = math.sqrt(math.Clamp(level / slot.gain, 0, 1))
    slot.show = show
    local accent = muted and T.muted or (not identified and T.muted or (staff and ELECTRIC_BLUE or T.accent))
    local hot = audible and show * 0.35 or 0
    -- Charge: built in V.StepCharge for every heard speaker; the row only shows it.
    local cs = ply and V.charge[ply]
    local charge = cs and cs.v or 0
    -- plate: (superadmin glow), hairline, fill. Right corners square: the plate meets the screen edge.
    if super then
        liftInto(rowHair, ELECTRIC_BLUE, 0, 30 + 60 * show)
        draw.RoundedBoxEx(R + 3, x - 3, y - 3, W + 3, H + 6, rowHair, true, false, true, false)
        liftInto(rowHair, ELECTRIC_BLUE, hot, 110 + 100 * show)
        draw.RoundedBoxEx(R + 1, x - 1, y - 1, W + 1, H + 2, rowHair, true, false, true, false)
    else
        draw.RoundedBoxEx(R + 1, x - 1, y - 1, W + 1, H + 2, ROW_HAIR, true, false, true, false)
    end
    draw.RoundedBoxEx(R, x, y, W, H, ROW_PLATE, true, false, true, false)
    -- avatar: glow (loud), ring (level), a solid gap, then the masked picture
    local ax, ay = x + g.PAD, y + math.floor((H - AV) / 2)
    if audible and show > 0.02 then
        local glow = math.Clamp((show - 0.55) / 0.35, 0, 1)
        if glow > 0 and not reducedMotion and Q > 0 then
            liftInto(sparkGlow, accent, hot, glow * 80)
            glowDot(ax + AV / 2, ay + AV / 2, AV * 2.6, sparkGlow)
            flushDots()
        end
        liftInto(rowRing, accent, hot, 255 * math.min(0.95, 0.2 + 0.8 * show))
        draw.RoundedBox(R + 1, ax - 3, ay - 3, AV + 6, AV + 6, rowRing)
        draw.RoundedBox(R, ax - 1, ay - 1, AV + 2, AV + 2, ROW_PLATE_SOLID)
        slot.backed = now
    end
    local blend = cornerBlendOK(slot.alpha)
    -- the blended corners are painted in the opaque plate colour, so the tile always sits on the opaque backing
    -- square (the quiet-row plate is 222 alpha; review 2026-09-25)
    if blend and slot.backed ~= now then draw.RoundedBox(R, ax - 1, ay - 1, AV + 2, AV + 2, ROW_PLATE_SOLID) end
    if identified and IsValid(ply) and not ply:IsBot() then
        maskBegin(ax, ay, AV, AV, R - 1, blend)
        paintCompactAvatar(ply, ax, ay, AV, slot.alpha * 255)
        if slot.alpha < 1 then
            fadeOverlay.a = (1 - slot.alpha) * 255
            surface.SetDrawColor(fadeOverlay.r, fadeOverlay.g, fadeOverlay.b, fadeOverlay.a)
            surface.DrawRect(ax, ay, AV, AV)
        end
        maskEnd(ax, ay, AV, AV, R - 1, blend, ROW_PLATE_SOLID)
    elseif identified then
        draw.RoundedBox(R - 1, ax, ay, AV, AV, T.line) -- bots: a plain tile, no fetch
    else
        -- hidden identity: a mosaic tile, no picture, no name
        maskBegin(ax, ay, AV, AV, R - 1, blend)
        surface.SetDrawColor(MOSAIC_B.r, MOSAIC_B.g, MOSAIC_B.b, 255)
        surface.DrawRect(ax, ay, AV, AV)
        surface.SetDrawColor(MOSAIC_A.r, MOSAIC_A.g, MOSAIC_A.b, 255)
        local q = AV / 4
        for j = 0, 3 do
            for i = 0, 3 do
                if (i + j) % 2 == 0 then surface.DrawRect(ax + i * q, ay + j * q, q, q) end
            end
        end
        maskEnd(ax, ay, AV, AV, R - 1, blend, ROW_PLATE_SOLID)
    end
    -- name (single line, ellipsised), then the usergroup tag (staff) or the struck mic (muted) after it
    local tx = ax + AV + g.GAP
    local title = identified and V.Title(row) or "Unknown voice"
    local font = identified and "GoobVoiceName" or "GoobVoiceNameItalic"
    local tag = (not muted and staff and slot.role ~= "" and slot.role ~= "USER") and slot.role or nil
    if tag and slot.tagText ~= tag then slot.tagText, slot.tagW = tag, spacedWidth(tag, "GoobVoiceTag", g.TAG_SP) end
    local trailer = muted and (g.GLYPH + 6) or (tag and (slot.tagW + g.GAP) or 0)
    local titleWidth = W - g.PAD - AV - g.GAP - g.PAD - trailer
    -- cached on the slot, which outlives the row (V.Poll rebuilds every row 20 times a second)
    if slot.cachedTitle ~= title or slot.cachedTitleWidth ~= titleWidth then
        slot.cachedTitle, slot.cachedTitleWidth = title, titleWidth
        slot.fittedTitle = fit(title, titleWidth, font)
        surface.SetFont(font)
        slot.fittedTitleW = surface.GetTextSize(slot.fittedTitle)
    end
    local nameColor = (muted or not identified) and T.muted or T.text
    draw.SimpleText(slot.fittedTitle, font, tx, y + g.NAME_Y, nameColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    local nameW = slot.fittedTitleW or 0
    if muted then
        local K = A.Kit
        local gx, gy = tx + nameW + g.GLYPH, y + g.NAME_Y + g.NAME_H / 2
        if K and K.Glyph then K.Glyph("mic", gx, gy, g.GLYPH, T.muted) end
        surface.SetDrawColor(T.muted.r, T.muted.g, T.muted.b, 255)
        surface.DrawLine(gx - g.GLYPH / 2, gy - g.GLYPH / 2, gx + g.GLYPH / 2, gy + g.GLYPH / 2)
    elseif tag then
        drawSpaced(tag, "GoobVoiceTag", tx + nameW + g.GAP * 0.6, y + g.NAME_Y + g.TAG_DY, accent, g.TAG_SP)
    end
    -- visualizer: 24 smoothed bars growing up from a baseline; silent = a neat dotted baseline
    local bw, bg, minH, maxH = g.BAR_W, g.BAR_GAP, g.BAR_MIN, g.VIZ_H
    local base = y + H - g.PAD + 1
    local bars = stepBars(slot, BAR_N, show, audible and show > 0.01, dt, now, reducedMotion)
    liftInto(rowAcc, accent, hot, audible and 255 or 140)
    surface.SetDrawColor(rowAcc.r, rowAcc.g, rowAcc.b, rowAcc.a)
    for i = 1, BAR_N do
        local hgt = minH + (maxH - minH) * bars[i]
        surface.DrawRect(tx + (i - 1) * (bw + bg), base - hgt, bw, hgt)
    end
    -- charge: a line along the bottom edge, white until it is nearly full, then red
    if charge > 0.02 and audible then
        local c = charge > 0.85 and T.red or sparkCore
        surface.SetDrawColor(c.r, c.g, c.b, 120 + 135 * charge)
        surface.DrawRect(x + R, y + H - 2, (W - R) * charge, 2)
    end
    -- superadmin border electricity, then the burst
    if super then
        drawEdgeElectricity(slot, x, y, W, H, R, reducedMotion and 0 or show, dt, now, false)
    elseif slot.sparks then
        slot.sparks, slot.sparkAcc = nil, 0
    end
    drawBurst(slot, x, y, W, H, R, ax + AV / 2, ay + AV / 2, AV, accent, super, now, false)
    flushDots()
end

net.Receive("zc_voice_explode", function()
    local uid = net.ReadUInt(16)
    for _, slot in pairs(compactAnim) do
        if IsValid(slot.ply) and slot.ply:UserID() == uid then
            slot.burst, slot.burstFired = RealTime(), nil
        end
    end
    for p, cs in pairs(V.charge) do
        if IsValid(p) and p:UserID() == uid then cs.v, cs.spell, cs.mutedUntil = 0, 0, RealTime() + 3 end
    end
    if V.OverheadBurst then V.OverheadBurst(uid) end
end)

local function compactSlotLess(a, b)
    local you = LocalPlayer()
    local aYou, bYou = a.ply == you, b.ply == you
    if aYou ~= bYou then return aYou end
    if a.start ~= b.start then return a.start < b.start end
    return a.userid < b.userid
end

hook.Add("HUDPaint", "GoobOS.Voice.Compact", function()
    if not compact:GetBool() then return end
    -- Owner 2026-09-24: living players see no voice indicators at all; the column is for the dead and spectators.
    local me = LocalPlayer()
    if IsValid(me) and me:Alive() and me:Team() ~= TEAM_SPECTATOR then return end
    local hud = GetConVar("cl_drawhud")
    if hud and not hud:GetBool() then return end
    local phone = hg and hg.chat
    if IsValid(phone) and phone:GetActive() and phone.phonePage == "voice" then return end
    -- The scoreboard (addons/scoreboard, global ZCScoreboard) draws over the same screen area; check its own live
    -- frame handle rather than pop the rows, so voice fades out the same way it does when someone stops talking.
    local scoreboardOpen = ZCScoreboard ~= nil and IsValid(ZCScoreboard.Frame)

    local dt, now = FrameTime(), RealTime()
    frameBegin(now, dt)
    matOX, matOY, matS = 0, 0, 1
    local g = layout()
    local reducedMotion = ZCPhoneSettings and ZCPhoneSettings.ReducedMotion()
    local liveRows = {}
    if V.Ready() and not scoreboardOpen then
        for _, row in ipairs(V.rows) do if V.Visible(row) then liveRows[#liveRows + 1] = row end end
    end

    -- Sync animation slots against the current live rows: refresh survivors, create newcomers (sliding in from the
    -- edge), mark absentees for the slide-out.
    local liveKeys = {}
    for _, row in ipairs(liveRows) do
        local key = row.ply or "anonymous"
        liveKeys[key] = true
        local slot = compactAnim[key]
        if not slot then
            slot = {key = key, ply = row.ply, y = nil, alpha = 0, state = "in"}
            compactAnim[key] = slot
        end
        slot.row = row
        slot.staff = row.staff
        slot.start = row.meter and row.meter.start or 0
        slot.userid = (row.ply and IsValid(row.ply)) and row.ply:UserID() or -1
        if slot.state == "out" then slot.state = "in" end
    end
    for key, slot in pairs(compactAnim) do
        if not liveKeys[key] and slot.state ~= "out" then slot.state = "out" end
    end

    -- Order slots (fading-out ones included) by the same rule V.Poll sorts by, so a slot mid-fade keeps its spot.
    local count = 0
    for _, slot in pairs(compactAnim) do count = count + 1; compactOrder[count] = slot end
    for i = count + 1, #compactOrder do compactOrder[i] = nil end
    table.sort(compactOrder, compactSlotLess)

    -- Rows stack down the right edge from the anchor (58% down by default, under the moodle column;
    -- zc_goobos_voice_lower 0 puts them at 20%). Plates are flush with the right edge (owner 2026-09-25: no padding);
    -- the column stops g.EDGE above the bottom. At most 6 rows, the rest go into the "+N more" chip.
    -- Transitions (owner 2026-09-24 late: "smoother"): a row eases in from the edge (cubic out) and eases back out
    -- into it; rows below drift to their new spot; the header and chip take the column's strongest alpha.
    local right, bottom = ScrW(), ScrH() - g.EDGE
    local anchorY = lowerHUD:GetBool() and math.max(g.EDGE, math.floor(ScrH() * 0.58)) or math.floor(ScrH() * 0.2)
    local yCursor = anchorY
    local rendered, shown, colAlpha = 0, 0, 0
    for i = 1, count do
        local slot = compactOrder[i]
        if slot.state == "out" then
            slot.alpha = math.max(0, slot.alpha - dt / ROW_FADE_OUT)
        else
            slot.alpha = math.min(1, slot.alpha + dt / ROW_FADE_IN)
        end
        if reducedMotion then slot.alpha = slot.state == "out" and 0 or 1 end
        if slot.alpha <= 0 and slot.state == "out" then
            releaseCompactAvatar(slot.ply or slot.key)
            compactAnim[slot.key] = nil
        elseif V.Visible(slot.row) and not (ZCObserver and ZCObserver.DockShownPly == slot.ply) then -- the dock draws that one
            if yCursor + g.H <= bottom and rendered < 6 then
                rendered = rendered + 1
                if slot.state ~= "out" then shown = shown + 1 end
                slot.y = not reducedMotion and slot.y and Lerp(1 - math.exp(-dt * 7), slot.y, yCursor) or yCursor
                local a, slide = slot.alpha, 0
                if not reducedMotion then
                    local rest = 1 - slot.alpha
                    if slot.state == "in" then
                        a = 1 - rest * rest * rest -- cubic ease-out on the way in
                        slide = (1 - a) * g.W * 0.6
                    else
                        a = slot.alpha * slot.alpha -- eases away on the way out
                        slide = (1 - a) * g.W * 0.45
                    end
                end
                colAlpha = math.max(colAlpha, a)
                surface.SetAlphaMultiplier(a)
                drawVoiceRow(slot, right - g.W + slide, slot.y, dt, now, reducedMotion)
                surface.SetAlphaMultiplier(1)
                yCursor = yCursor + g.H + g.ROW_GAP
            end
        end
    end
    if rendered > 0 and colAlpha > 0 then
        surface.SetAlphaMultiplier(colAlpha)
        if #liveRows > 0 then
            drawSpaced(#liveRows .. " TALKING", "GoobVoiceTag", right - g.GAP, anchorY - g.HDR_UP, ROW_HDR, g.HDR_SP, TEXT_ALIGN_RIGHT)
        end
        local overflow = math.max(0, #liveRows - shown)
        if overflow > 0 and yCursor + g.CHIP_H <= ScrH() then
            local text = "+" .. overflow .. " more"
            surface.SetFont("GoobVoiceSmall")
            local tw = surface.GetTextSize(text)
            local cw = tw + g.CHIP_PAD * 2
            draw.RoundedBoxEx(g.CHIP_R + 1, right - cw - 1, yCursor - 1, cw + 1, g.CHIP_H + 2, ROW_HAIR, true, false, true, false)
            draw.RoundedBoxEx(g.CHIP_R, right - cw, yCursor, cw, g.CHIP_H, ROW_PLATE, true, false, true, false)
            draw.SimpleText(text, "GoobVoiceSmall", right - cw / 2, yCursor + g.CHIP_H / 2, T.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        surface.SetAlphaMultiplier(1)
    end
end)

-- === Spectator ESP tag voice + the observer dock orb ============================================================
-- Over-head orbs for living viewers are gone (owner 2026-09-24 late: spectators only, inside the ESP tag, off with
-- ALT). overheadAnim now holds the ESP tag slots (V.TagVoiceWidth / V.PaintTagVoice below); V.OverheadBurst
-- still bursts them. The spectated player's own entry is handed to the observer dock (V.PaintDockOrb).
local overheadAnim = {}
local dockAnim = {}
local orbShadow = Color(0, 0, 0, 90) -- soft disc under a bare orb so it separates from sky and light walls

-- rows by player, rebuilt whenever V.Poll (or anything else) swaps V.rows: the ESP asks per tag per frame
local byPly, byPlyOf = {}, nil
local function rowOf(ply)
    local rows = V.rows
    if byPlyOf ~= rows then
        byPly, byPlyOf = {}, rows
        for _, row in ipairs(rows) do if row.ply then byPly[row.ply] = row end end
    end
    return byPly[ply]
end

local function slotShow(slot, row, dt)
    local meter = row.meter or {}
    local level = row.audible and math.Clamp(meter.level or 0, 0, 1) or 0
    slot.gain = math.max(0.12, (slot.gain or 0.3) * (1 - dt * 0.08), level)
    return math.sqrt(math.Clamp(level / slot.gain, 0, 1))
end

-- The orb itself, without a plate: feathered ring, avatar or glyph, corona, sparks. `identified` decides whether
-- the avatar may be shown.
local function paintBareOrb(slot, cx, cy, r, show, identified, reducedMotion, dt)
    local row = slot.row
    local staff = slotStaff(slot, RealTime())
    electric = electricityEnabled() and staff and ELECTRIC_BLUE or T.accent
    electricMul = staff and 2 or 1
    local edge = row.audible and electric or T.line
    local hot = row.audible and electricityEnabled() and show * 0.65 or 0
    orbEdge.r, orbEdge.g, orbEdge.b = edge.r + (255 - edge.r) * hot, edge.g + (255 - edge.g) * hot, edge.b + (255 - edge.b) * hot
    orbEdge.a = row.audible and (120 + show * 135) or 110
    local ring = r + 2 + (reducedMotion and 0 or show * 3)
    slot.orbX, slot.orbY, slot.orbR, slot.show = cx, cy, ring, show
    circle(cx, cy + 1, ring + 2.5, orbShadow)
    local keepA = orbEdge.a
    for _, f in ipairs(FEATHER) do
        orbEdge.a = keepA * f[2]
        circle(cx, cy, ring + f[1], orbEdge)
    end
    orbEdge.a = keepA
    circle(cx, cy, ring, orbEdge)
    circle(cx, cy, r + 1, orbPlate)
    if not reducedMotion and row.audible and show > 0.25 and Q > 0 and electricityEnabled() then
        sparkGlow.r, sparkGlow.g, sparkGlow.b, sparkGlow.a = orbEdge.r, orbEdge.g, orbEdge.b, 30 + 110 * (show - 0.25)
        glowDot(cx, cy, ring * (3.2 + 0.6 * math.sin(RealTime() * 9)), sparkGlow)
    end
    flushDots() -- the corona stays UNDER the avatar
    if identified and IsValid(slot.ply) and not slot.ply:IsBot() then
        stencilCircleBegin(cx, cy, r)
        paintCompactAvatar(slot.ply, cx - r, cy - r, r * 2, 255)
        stencilEnd()
    else
        local K = A.Kit
        if K and K.Glyph then K.Glyph("mic", cx, cy, math.floor(r * 1.1), orbEdge) end
    end
    if not reducedMotion and row.audible then drawRingArcs(cx, cy, ring + 0.5, show, RealTime()) end
    if not electricityEnabled() then slot.burst, slot.burstFired = nil, nil end
    if slot.burst then
        local age = (RealTime() - slot.burst) / 0.6
        if age < 1 then
            if not slot.burstFired then
                slot.burstFired = true
                slot.sparks = slot.sparks or {}
                local keepMul = electricMul
                electricMul = 3
                for _ = 1, 16 do spawnSpark(slot, "bolt", cx, cy, ring + 1, 1, cy + r * 2, r * 1.5) end
                electricMul = keepMul
            end
            sparkFlash.a = 255 * (1 - age)
            glowDot(cx, cy, ring * (5 + 14 * age), sparkFlash)
        else
            slot.burst, slot.burstFired = nil, nil
        end
    end
    drawSparks(slot, show, cx, cy, ring + 1, reducedMotion, dt, cy + r * 2, r * 1.5)
    flushDots()
end

function V.OverheadBurst(uid)
    for ply, slot in pairs(overheadAnim) do
        if IsValid(ply) and ply:UserID() == uid then slot.burst, slot.burstFired = RealTime(), nil end
    end
    for ply, slot in pairs(dockAnim) do
        if IsValid(ply) and ply:UserID() == uid then slot.burst, slot.burstFired = RealTime(), nil end
    end
end

-- === Voice inside the spectator ESP tags (owner 2026-09-24, late) ===============================================
-- "Over-head voice indicators should ONLY be shown to spectators, when spectating, integrated in the same panel as
-- the spectator ESP, and toggle off with ALT along with it." So there is no over-head hook any more: the ESP in
-- lua/zc_observer/cl_observer.lua (spectators only, ALT toggles it) asks V.TagVoiceWidth(ply, u) for the extra
-- plate width a speaking player needs (0 when silent; eases in and out), draws the plate wider, and calls
-- V.PaintTagVoice(ply, ..., mult) twice per tag, mult = its own alpha: layer "under" before the plate fill (accent outline, superadmin border
-- electricity, the burst) and layer "bars" after the name (the visualizer inside the plate). Identity: only a
-- player with a voice row gets any of it (rows pass hg.CanIdentifyVoicePanel in V.Poll); the level is the engine's.
local TAG_BARS = 10
local tagAcc = Color(0, 0, 0, 0)
local function tagSlot(ply, now, dt)
    local slot = overheadAnim[ply]
    if not slot then slot = {ply = ply, alpha = 0, gain = 0.3} overheadAnim[ply] = slot end
    if slot.seen ~= now then
        slot.seen = now
        local row = V.Ready() and rowOf(ply) or nil
        if row then slot.row = row end -- keep the last row while fading out
        local want = (row and row.audible and V.Visible(row)) and 1 or 0
        slot.alpha = Lerp(1 - math.exp(-dt * (want > slot.alpha and 14 or 6)), slot.alpha, want)
        if want == 0 and slot.alpha < 0.01 then slot.alpha = 0 end
        slot.show = (row and slot.alpha > 0) and slotShow(slot, row, dt) or 0
        if now - (slot.sweep or 0) > 2 then -- prune slots of players gone from the ESP or the server
            slot.sweep = now
            for p, s in pairs(overheadAnim) do
                if not IsValid(p) or now - (s.seen or 0) > 5 then overheadAnim[p] = nil end
            end
        end
    end
    return slot
end
function V.TagVoiceWidth(ply, u)
    if not V.Enabled() or not IsValid(ply) then return 0 end
    local now, dt = RealTime(), FrameTime()
    frameBegin(now, dt)
    local slot = tagSlot(ply, now, dt)
    if slot.alpha <= 0 then return 0 end
    u = u or 1
    local bw, gap = math.max(2, math.floor(3 * u + 0.5)), math.max(1, math.floor(2 * u + 0.5))
    slot.barW, slot.barGap = bw, gap
    slot.tagW = TAG_BARS * bw + (TAG_BARS - 1) * gap + math.floor(6 * u + 0.5)
    local e = 1 - (1 - slot.alpha) ^ 2
    return math.floor(slot.tagW * e + 0.5)
end
function V.PaintTagVoice(ply, x, y, w, h, layer, u, mult)
    if not V.Enabled() or not IsValid(ply) then return false end
    local now, dt = RealTime(), FrameTime()
    frameBegin(now, dt)
    matOX, matOY, matS = 0, 0, 1
    local slot = tagSlot(ply, now, dt)
    if slot.alpha <= 0 or not slot.row then return false end
    u = u or 1
    local show = slot.show or 0
    local staff = slotStaff(slot, now)
    local super = staff and slot.isSuper == true
    local accent = staff and ELECTRIC_BLUE or T.accent
    local hot = show * 0.35
    local reducedMotion = ZCPhoneSettings and ZCPhoneSettings.ReducedMotion()
    local keep = mult or 1 -- the ESP's own distance fade, passed in (SetAlphaMultiplier replaces, it does not stack)
    surface.SetAlphaMultiplier(keep * slot.alpha)
    if layer == "under" then
        -- a 1 px accent outline (the ESP fills the plate over the inside), a glow when loud, then the border
        -- electricity of a superadmin and the burst
        local R = math.max(3, math.floor(4 * u + 0.5))
        local glow = math.Clamp((show - 0.55) / 0.35, 0, 1)
        if glow > 0 and not reducedMotion and Q > 0 then
            liftInto(sparkGlow, accent, hot, glow * 70)
            glowDot(x + w / 2, y + h / 2, w * 1.1, sparkGlow)
        end
        liftInto(tagAcc, accent, hot, 255 * (0.35 + 0.6 * show))
        draw.RoundedBox(R + 1, x - 1, y - 1, w + 2, h + 2, tagAcc)
        if super then
            drawEdgeElectricity(slot, x, y, w, h, R, reducedMotion and 0 or show, dt, now, true)
        elseif slot.sparks then
            slot.sparks, slot.sparkAcc = nil, 0
        end
        drawBurst(slot, x, y, w, h, R, x + w / 2, y + h / 2, h, accent, super, now, true)
        flushDots()
    else
        -- the visualizer, left-aligned in the widened part of the plate; bars that no longer fit while the plate is
        -- easing shut are skipped
        local bw, gap = slot.barW or 3, slot.barGap or 2
        local minH, maxH = math.max(2, math.floor(2 * u + 0.5)), math.max(4, h - math.floor(2 * u))
        local bars = stepBars(slot, TAG_BARS, show, slot.row.audible and show > 0.01, dt, now, reducedMotion)
        liftInto(tagAcc, accent, hot, 255)
        surface.SetDrawColor(tagAcc.r, tagAcc.g, tagAcc.b, tagAcc.a)
        local cy = y + h / 2
        for i = 1, TAG_BARS do
            local bx = x + (i - 1) * (bw + gap)
            if bx + bw > x + w then break end
            local hgt = minH + (maxH - minH) * bars[i]
            surface.DrawRect(bx, cy - hgt / 2, bw, hgt)
        end
    end
    surface.SetAlphaMultiplier(keep)
    return true
end

-- The observer dock's avatar becomes the spectated player's orb while they talk: ring, electricity and the
-- burst, drawn around the dock's own avatar square. Called from cl_observer.lua with the square's rect and the
-- dock's alpha; returns true when the target is a live voice row.
function V.PaintDockOrb(ply, x, y, size, alpha255, layer, fill)
    if not V.Ready() or not IsValid(ply) then return false end
    local row = rowOf(ply)
    if not row or not row.audible then return false end
    local slot = dockAnim[ply]
    if not slot then slot = {ply = ply, gain = 0.3} dockAnim[ply] = slot end
    slot.row = row
    local dt, now = FrameTime(), RealTime()
    frameBegin(now, dt)
    matOX, matOY, matS = 0, 0, 1
    local reducedMotion = ZCPhoneSettings and ZCPhoneSettings.ReducedMotion()
    -- Two layers (2026-09-25 perf pass): "under" before the dock paints its avatar square draws the ring as filled
    -- discs with the dock's own fill inside (5 polygons; the stroke ring was 40 segments x 4 passes = 160), "over"
    -- after it draws the corona, arcs, burst and sparks. With no layer (an older cl_observer) it is one call after
    -- the avatar and the ring is the stroke. The level is stepped once per frame, in whichever layer comes first.
    local under = layer == "under"
    local show
    if layer == "over" and slot.showAt == now then show = slot.show or 0
    else show = slotShow(slot, row, dt); slot.showAt = now end
    local alpha = math.Clamp((alpha255 or 255) / 255, 0, 1)
    local cx, cy, r = x + size / 2, y + size / 2, size * 0.82 -- inner disc clears the dock's 46 px team square (half-diagonal 32.5 at size 42)
    local staff = slotStaff(slot, now)
    electric = electricityEnabled() and staff and ELECTRIC_BLUE or T.accent
    electricMul = staff and 2 or 1
    local hot = electricityEnabled() and show * 0.65 or 0
    orbEdge.r, orbEdge.g, orbEdge.b = electric.r + (255 - electric.r) * hot, electric.g + (255 - electric.g) * hot, electric.b + (255 - electric.b) * hot
    orbEdge.a = (120 + show * 135) * alpha
    local ring = r + (reducedMotion and 0 or show * 3)
    local half = 1 + (reducedMotion and 0 or show * 0.75) -- half the ring's width; fixed under Reduced motion like the ring
    slot.orbX, slot.orbY, slot.orbR, slot.show = cx, cy, ring, show
    local keepA = orbEdge.a
    if under then
        for _, f in ipairs(FEATHER) do
            orbEdge.a = keepA * f[2]
            circle(cx, cy, ring + half + f[1], orbEdge)
        end
        orbEdge.a = keepA
        circle(cx, cy, ring + half, orbEdge)
        circle(cx, cy, ring - half, fill or T.bg)
        return true
    elseif layer == nil then
        local pts, n = ringPath(cx, cy, ring, 40, 41)
        for _, f in ipairs(FEATHER) do
            orbEdge.a = keepA * f[2]
            thickPolyline(pts, n, half * 2 + f[1] * 2, orbEdge)
        end
        orbEdge.a = keepA
        thickPolyline(pts, n, half * 2, orbEdge)
    end
    if not reducedMotion and show > 0.25 and Q > 0 then
        sparkGlow.r, sparkGlow.g, sparkGlow.b, sparkGlow.a = orbEdge.r, orbEdge.g, orbEdge.b, (30 + 110 * (show - 0.25)) * alpha
        glowDot(cx, cy, ring * (2.6 + 0.5 * math.sin(now * 9)), sparkGlow)
    end
    if not reducedMotion then drawRingArcs(cx, cy, ring + 0.5, show, now) end
    if not electricityEnabled() then slot.burst, slot.burstFired = nil, nil end
    if slot.burst then
        local age = (now - slot.burst) / 0.6
        if age < 1 then
            sparkFlash.a = 255 * (1 - age) * alpha
            glowDot(cx, cy, ring * (4 + 12 * age), sparkFlash)
        else
            slot.burst, slot.burstFired = nil, nil
        end
    end
    drawSparks(slot, show, cx, cy, ring + 1, reducedMotion, dt, y + size + 12, size)
    flushDots()
    for p in pairs(dockAnim) do if p ~= ply then dockAnim[p] = nil end end
    return true
end

-- === Voice monitor (owner 2026-09-24, late) =====================================================================
-- Your own orb, centred BELOW the stamina bar (addons/stamina_bar/cl_staminabar.lua: centre line at ScrH * 0.8) and
-- below the organism notification line (sh_notification.lua draws it centred at ScrH - ScrH / 6), so it never sits
-- on either; or in any of the four corners (zc_goobos_voice_monitor_pos, GoobOS Settings > "Voice orb position").
-- Your avatar in the same reactive ring as every other orb, no name. Shown while you transmit (or whisper),
-- alive only - dead and spectating players already have their "You" orb at the top of the column.
-- It also takes over the chat's ALT whisper icon (cl_zchat.lua ZCChat_WhisperIndicator, retired here): holding ALT
-- (cl_chat.lua -> ZChatWhisper -> net ChatWhisper -> ply.ChatWhisper) makes the server hear you at 100 units instead
-- of 3000 (sv_comunication.lua chat_dist_whisper / chat_dist_normal, used by PlayerCanHearPlayersVoice), so the
-- orb's excitement is damped by that same ratio - floored so a whisper still reads as life - and a small whisper
-- badge hangs off the bottom of the orb.
local monitorCv = CreateClientConVar("zc_goobos_voice_monitor", "1", true, false, "Your own voice orb while you talk (0/1)", 0, 1)
local monitorPosCv = CreateClientConVar("zc_goobos_voice_monitor_pos", "0", true, false, "Voice orb position: 0 centre (below the stamina bar), 1 top left, 2 top right, 3 bottom left, 4 bottom right", 0, 4)
local NOTIF_LINE, NOTIF_H = 5 / 6, 34 -- sh_notification.lua: the organism line is centred at ScrH - ScrH / 6, HuyFont ~34 px
local WHISPER_RANGE, NORMAL_RANGE = 100, 3000 -- sv_comunication.lua chat_dist_whisper / chat_dist_normal (not networked)
-- PROVISIONAL(2026-09-24, the 0.25 floor under the 1/30 range ratio is a guess at what still reads as a live orb,
-- ratify-by: 2026-10-08)
local WHISPER_FLOOR = 0.25
local MONITOR_R = 15 -- 75% of a column orb (ORB_SIZE / 2 = 20), like everything else after the resize
local monitorSlot = {alpha = 0, gain = 0.3}
local monitorMeter = nil
local monitorRow = {audible = false}
local whisperBadge = Color(192, 0, 0, 255)
local whisperInk = Color(40, 8, 8, 255)
local whisperPoly = {{x = 0, y = 0}, {x = 0, y = 0}, {x = 0, y = 0}, {x = 0, y = 0}}
hook.Remove("HUDPaint", "ZCChat_WhisperIndicator")
timer.Simple(0, function() hook.Remove("HUDPaint", "ZCChat_WhisperIndicator") end)
local function whispering()
    if ZChatWhisper then return true end
    local me = LocalPlayer()
    return IsValid(me) and me.ChatWhisper == true
end
-- the old 16 px icon (a mouth, a raised hand, two sound lines), drawn on a red disc at the orb's shoulder
local function paintWhisperBadge(x, y)
    circle(x + 8, y + 8, 9, whisperBadge)
    surface.SetDrawColor(whisperInk)
    surface.DrawRect(x + 3, y + 6, 3, 4)
    whisperPoly[1].x, whisperPoly[1].y = x + 6, y + 6
    whisperPoly[2].x, whisperPoly[2].y = x + 10, y + 3
    whisperPoly[3].x, whisperPoly[3].y = x + 10, y + 13
    whisperPoly[4].x, whisperPoly[4].y = x + 6, y + 10
    draw.NoTexture()
    surface.DrawPoly(whisperPoly)
    surface.DrawLine(x + 12, y + 6, x + 13, y + 8)
    surface.DrawLine(x + 13, y + 8, x + 12, y + 10)
end
local function monitorPos()
    local pos, m = monitorPosCv:GetInt(), 10 + MONITOR_R -- owner 2026-09-25: to the edge; the ring + feather reach ~7 px past r
    if pos == 1 then return m, m end
    if pos == 2 then return ScrW() - m, m end
    if pos == 3 then return m, ScrH() - m end
    if pos == 4 then return ScrW() - m, ScrH() - m end
    -- centre: under the stamina bar (ScrH * 0.8) AND under the organism notification line, over neither
    return math.floor(ScrW() / 2), math.floor(ScrH() * NOTIF_LINE + NOTIF_H / 2 + 10 + MONITOR_R)
end
hook.Add("HUDPaint", "GoobOS.Voice.Monitor", function()
    if not enabled:GetBool() or not monitorCv:GetBool() then return end
    local me = LocalPlayer()
    if not IsValid(me) or not me:Alive() then monitorSlot.alpha = 0 return end
    local hud = GetConVar("cl_drawhud")
    if hud and not hud:GetBool() then return end
    if gui.IsGameUIVisible() then return end
    local now, dt = RealTime(), FrameTime()
    frameBegin(now, dt)
    matOX, matOY, matS = 0, 0, 1
    local reducedMotion = ZCPhoneSettings and ZCPhoneSettings.ReducedMotion()
    local whisper = whispering()
    local speaking = me:IsSpeaking() and not me:IsMuted()
    local row = V.Ready() and rowOf(me) or nil
    if not row then
        -- not in V.rows (display off, identity rule): a private meter with the same stand-in envelope V.Poll uses
        local raw = speaking and me:VoiceVolume() or 0
        if speaking and raw <= 0.001 then
            local c = math.abs(math.sin(now * 6.3)) * math.abs(math.sin(now * 2.1 + 0.7))
            raw = 0.28 + 0.42 * c
        end
        monitorMeter = V.Step(monitorMeter or {start = now}, raw, dt, now)
        if not speaking then monitorMeter.level = 0; monitorMeter.peak = 0 end
        monitorRow.meter, monitorRow.audible = monitorMeter, speaking
        row = monitorRow
    end
    local want = (speaking or whisper) and 1 or 0
    monitorSlot.alpha = reducedMotion and want or Lerp(1 - math.exp(-dt * (want > 0 and 14 or 5)), monitorSlot.alpha, want)
    if monitorSlot.alpha <= 0.02 then return end
    monitorSlot.ply, monitorSlot.row = me, row
    local show = slotShow(monitorSlot, row, dt)
    -- the dampening: what the server does to your range while you whisper, with a floor so the orb still lives
    if whisper then show = show * math.max(WHISPER_FLOOR, WHISPER_RANGE / NORMAL_RANGE) end
    local cx, cy = monitorPos()
    surface.SetAlphaMultiplier(monitorSlot.alpha * (whisper and 0.85 or 1))
    paintBareOrb(monitorSlot, cx, cy, MONITOR_R, show, true, reducedMotion, dt)
    if whisper then paintWhisperBadge(cx - 8, cy + MONITOR_R - 6) end -- hangs off the bottom of the ring
    surface.SetAlphaMultiplier(1)
end)

-- In-app page (kit rebuild, 2026-09-24): header + live-count pill, a grouped settings Card
-- (K.Toggle/K.Segmented wired to the SAME convars the old buttons toggled), then the speaker
-- List (56 px rows, K.Avatar with a state ring, name/status, segmented meter + LEVEL/PEAK).
-- Below 360 px wide the meter moves under the name. Nothing above this line changes: the HUD
-- overlay hook, V.Poll/V.Step/V.Meters and every convar stay exactly as shipped.
local SETTING_ROW_H = 44
local ROW_H = 56
local AVATAR_SIZE = 40
local STACK_BREAKPOINT = 360 -- two-column stack break used across the kit (tokens.md §4)
local badgeInk = Color(22, 32, 28) -- dark text over the green "N live" pill (01_voice.html:179)

local function liveCount()
    local count = 0
    for _, row in ipairs(V.rows) do
        if V.Visible(row) then count = count + 1 end
    end
    return count
end

local function build(body)
    local K = A.Kit
    if not K then
        -- Defensive fallback for a client missing kit.lua (apps.lua auto-includes it; this
        -- should not happen in practice). Keeps every control reachable, drops the live list.
        A.Label(body, "Live voice", "GoobTitle")
        A.Status(body, "Live levels with peak hold. Hidden speakers stay anonymous. Playback volume stays in your scoreboard.")
        local toggle = A.Button(body, "", function() RunConsoleCommand("zc_goobos_voice_hud", compact:GetBool() and "0" or "1") end, T.accent)
        toggle.Think = function(s) s:SetText(compact:GetBool() and "ON   Gameplay indicator on" or "OFF   Gameplay indicator off") end
        local placement = A.Button(body, "", function() RunConsoleCommand("zc_goobos_voice_lower", lowerHUD:GetBool() and "0" or "1") end, T.muted)
        placement.Think = function(s) s:SetText(lowerHUD:GetBool() and "Position: lower right" or "Position: upper right") end
        local monitor = A.Button(body, "", function()
            if staffRole() and GetConVar("zc_micbox_enabled") then RunConsoleCommand("zc_micbox") end
        end, T.gold)
        monitor.Think = function(s)
            s:SetVisible(staffRole() and GetConVar("zc_micbox_enabled") ~= nil)
            s:SetText(staffAllowed() and "ON   Staff monitor on" or "OFF   Staff monitor off")
        end
        A.Status(body, "Voice display unavailable or disabled. Enable it in Settings > GoobOS.")
        return
    end

    -- Header: title + live-count pill.
    local header = K.Panel(body)
    header:Dock(TOP)
    header:SetTall(30)
    header.Paint = function(_, w)
        K.Text("Live voice", 20, 700, 0, 4, T.green)
        local count = liveCount()
        local label = count .. " live"
        local font = K.Font(12, 600)
        surface.SetFont(font)
        local pillWide = math.max(40, surface.GetTextSize(label) + 20)
        local x = w - pillWide
        draw.RoundedBox(9, x, 5, pillWide, 20, count > 0 and T.green or T.card)
        draw.SimpleText(label, font, x + pillWide / 2, 15, count > 0 and badgeInk or T.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    A.Status(body, "Live levels with peak hold. Hidden speakers stay anonymous. Playback volume stays in your scoreboard.")

    -- Settings card: gameplay indicator toggle, position segmented, staff monitor (when it
    -- exists today). Row visibility/values are synced from card.Think, which always runs
    -- (card is never hidden) -- a row must never gate its own visibility from its own Think,
    -- or it can never turn itself back on.
    local card = K.Panel(body)
    card:Dock(TOP)
    card:DockMargin(0, 4, 0, 10)

    local function settingRow(labelText, helpText, controlWide)
        local row = K.Panel(card)
        row.LabelText, row.HelpText, row.ControlWide = labelText, helpText, controlWide
        row.Paint = function(s, w)
            local textWidth = math.max(10, w - s.ControlWide - 10)
            K.Text(K.Fit(s.LabelText, K.Font(14, 600), textWidth), 14, 600, 0, 4, T.text)
            if s.HelpText then K.Text(K.Fit(s.HelpText, K.Font(12, 500), textWidth), 12, 500, 0, 23, T.muted) end
        end
        return row
    end

    local indicatorRow = settingRow("Show speakers while playing", "Gameplay indicator overlay while you play", 38)
    local indicatorToggle = K.Toggle(indicatorRow, compact:GetBool(), function(v)
        RunConsoleCommand("zc_goobos_voice_hud", v and "1" or "0")
    end)

    local positionRow = settingRow("Position", "Where the gameplay indicator docks on screen", 168)
    local positionSeg = K.Segmented(positionRow, {"Upper right", "Lower right"}, lowerHUD:GetBool() and 2 or 1, function(index)
        RunConsoleCommand("zc_goobos_voice_lower", index == 2 and "1" or "0")
    end)
    positionSeg:SetWide(168)

    local fxRow = settingRow("Electricity density", "Auto thins the sparks when frames are slow; Full never does", 168)
    local fxSeg = K.Segmented(fxRow, {"Auto", "Full"}, fxCv:GetInt() + 1, function(index)
        RunConsoleCommand("zc_goobos_voice_fx", tostring(index - 1))
    end)
    fxSeg:SetWide(168)

    local monitorRow = settingRow("Staff monitor", "Shows every mic, including hidden speakers", 38)
    local monitorToggle = K.Toggle(monitorRow, staffAllowed(), function()
        if staffRole() and GetConVar("zc_micbox_enabled") then RunConsoleCommand("zc_micbox") end
    end)

    local electricityRow = settingRow("Indicator electricity", "Show decorative sparks, arcs and bolts on voice indicators", 38)
    local electricityToggle = K.Toggle(electricityRow, electricityEnabled(), function(v)
        RunConsoleCommand("zc_goobos_voice_electricity", v and "1" or "0")
    end)

    local settingRows = {
        {row = indicatorRow, control = indicatorToggle},
        {row = electricityRow, control = electricityToggle},
        {row = positionRow, control = positionSeg},
        {row = fxRow, control = fxSeg},
        {row = monitorRow, control = monitorToggle}
    }

    card.Think = function(s)
        monitorRow:SetVisible(staffRole() and GetConVar("zc_micbox_enabled") ~= nil)
        indicatorToggle:SetValue(compact:GetBool())
        electricityToggle:SetValue(electricityEnabled())
        positionSeg.Selected = lowerHUD:GetBool() and 2 or 1
        fxSeg.Selected = fxCv:GetInt() + 1
        monitorToggle:SetValue(staffAllowed())

        local w, pad, y = s:GetWide(), 12, 6
        for _, entry in ipairs(settingRows) do
            local row = entry.row
            if row:IsVisible() then
                row:SetPos(pad, y)
                row:SetSize(w - pad * 2, SETTING_ROW_H)
                local control = entry.control
                control:SetPos(w - pad - control:GetWide(), y + (SETTING_ROW_H - control:GetTall()) / 2)
                y = y + SETTING_ROW_H
            end
        end
        y = y + 6
        if s:GetTall() ~= y then s:SetTall(y) end
    end
    card.Paint = function(_, w, h)
        K.Card(0, 0, w, h, T.cardGlass, K.Alpha(T.edge, 180))
        local y, drawnOne = 6, false
        for _, entry in ipairs(settingRows) do
            if entry.row:IsVisible() then
                if drawnOne then
                    surface.SetDrawColor(T.hair)
                    surface.DrawRect(12, y, w - 24, 1)
                end
                y = y + SETTING_ROW_H
                drawnOne = true
            end
        end
    end

    -- Speaker list.
    local listCaption = K.Panel(body)
    listCaption:Dock(TOP)
    listCaption:SetTall(20)
    listCaption.Paint = function(_, w) K.Text("SPEAKERS", 12, 600, 0, 4, T.muted) end

    local listArea = K.Panel(body)
    listArea:Dock(FILL)

    local visibleRows = {}
    local function computeVisible()
        local out = {}
        for _, row in ipairs(V.rows) do
            if V.Visible(row) then out[#out + 1] = row end
        end
        visibleRows = out
    end

    local list = K.List(listArea, {
        rowHeight = ROW_H,
        gap = 0,
        count = function()
            computeVisible()
            return #visibleRows
        end,
        build = function(row)
            local avatar = K.Avatar(row, AVATAR_SIZE, T.card)
            avatar:SetPos(0, (ROW_H - AVATAR_SIZE) / 2)
            row.Avatar = avatar
            row.Paint = function(s, w, h)
                local data = visibleRows[s.GoobIndex]
                if not data then return end
                if (s.GoobIndex or 1) > 1 then
                    surface.SetDrawColor(T.hair)
                    surface.DrawRect(0, 0, w, 1)
                end
                avatar.Ring = data.muted and T.line or (data.ply == nil and T.muted or (data.audible and T.green or T.card))
                local stacked = w < STACK_BREAKPOINT
                local left = AVATAR_SIZE + 10
                local textWidth = w - left - (stacked and 4 or 150)
                K.Text(K.Fit(V.Title(data), K.Font(14, 600), textWidth), 14, 600, left, 4, T.text)
                K.Text(K.Fit(V.Status(data), K.Font(12, 500), textWidth), 12, 500, left, 21, T.muted)
                local meterText = data.audible
                    and string.format("LEVEL %02d%%  /  PEAK %02d%%", math.floor(data.meter.level * 100), math.floor(data.meter.peak * 100))
                    or "Unavailable"
                if stacked then
                    V.DrawMeter(data.meter, left, h - 18, math.max(4, w - left - 4), 8, data.audible)
                    K.Text(K.Fit(meterText, K.Font(11, 600), w - left - 4), 11, 600, left, h - 8, T.muted)
                else
                    local meterWide = 140
                    local mx = w - meterWide
                    V.DrawMeter(data.meter, mx, h / 2 - 12, meterWide, 8, data.audible)
                    K.Text(meterText, 11, 600, mx + meterWide, h / 2 + 2, T.muted, TEXT_ALIGN_RIGHT)
                end
            end
            -- No "clear identity" call exists on K.Avatar; the anonymous slot is drawn with the
            -- image hidden (set directly, kit candidate below) and a mic glyph painted over it
            -- in PaintOver so it lands above the avatar's own child paint.
            row.PaintOver = function(s)
                local data = visibleRows[s.GoobIndex]
                if data and data.ply == nil then K.Glyph("mic", AVATAR_SIZE / 2, ROW_H / 2, 18, T.muted) end
            end
        end,
        fill = function(row, index)
            local data = visibleRows[index]
            if not data then return end
            if data.ply then
                row.Avatar:SetPlayer(data.ply)
            elseif row.Avatar.Target ~= nil then
                row.Avatar.Target, row.Avatar.Bot = nil, false
                row.Avatar.Image:SetVisible(false)
            end
        end
    })
    list:Dock(FILL)

    local emptyPanel, emptyKey
    local function ensureEmpty(key)
        if emptyKey == key then return end
        emptyKey = key
        if IsValid(emptyPanel) then emptyPanel:Remove() end
        if key == "ready" then
            emptyPanel = K.EmptyState(listArea, "mic", "Nobody's talking right now", "Speakers appear here the moment someone keys their mic.")
        else
            emptyPanel = K.EmptyState(listArea, "mic", "Voice display unavailable", "Enable it in Settings > GoobOS, or wait for it to come back.")
        end
    end

    -- Always-running parent (listArea is never hidden) decides list vs. empty state, for the
    -- same reason card.Think owns monitorRow's visibility above.
    listArea.Think = function()
        local ready = V.Ready()
        local showList = ready and liveCount() > 0
        list:SetVisible(showList)
        if showList then
            if IsValid(emptyPanel) then emptyPanel:SetVisible(false) end
        else
            ensureEmpty(ready and "ready" or "unavailable")
            emptyPanel:SetVisible(true)
        end
    end
end

A.Register("voice", "Voice", "Live speakers & levels", "icon16/sound.png", T.green, build)
