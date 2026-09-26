-- Stamina bar (rebuilt 2026-09-24 for the owner: "a thin, horizontal, central bar that floats 1/5 of the way up
-- the centre of the screen"). Replaces the textured vertical bar that sat in the bottom-left corner. Same value
-- source (LocalPlayer().organism.stamina, {value, max = ...}), same gates (alive, not unconscious, no game menu).
-- Standalone on purpose: it does not require the GoobOS kit, but borrows its theme colours when they are present.
-- No per-frame Color() allocation; every colour below is mutated in place.

local cv = CreateClientConVar("zc_stamina_bar", "1", true, false, "Stamina bar (0 = off)", 0, 1)

local WIDTH_FRAC, HEIGHT, RADIUS = 0.18, 5, 3      -- ~18% of the screen wide, 5 px tall, rounded ends
local Y_FRAC = 0.8                                  -- centre line 1/5 of the way up from the bottom
local FADE_IN, FADE_OUT, HOLD_FULL = 0.2, 0.7, 1.5  -- seconds: appear, disappear, and how long a full bar lingers after a change

local track = Color(12, 10, 10, 215)
local edge = Color(255, 255, 255, 26)
local fill = Color(255, 255, 255, 255)
local glow = Color(255, 255, 255, 0)
local tick = Color(255, 255, 255, 60)
local glowMat = Material("sprites/light_glow02_add")

-- colour stops: full -> off-white, half -> gold, empty -> red (theme colours when GoobOS is loaded)
local function stops()
    local T = ZCGoobApps and ZCGoobApps.Theme
    return (T and T.text) or fill, (T and T.gold) or Color(230, 190, 90), (T and T.red) or Color(220, 70, 60)
end
local function mix(out, a, b, t)
    out.r, out.g, out.b = a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t
end

local function staminaFraction(org)
    local st = org.stamina
    if not st then return nil end
    local val = (type(st) == "table") and st[1] or st
    if type(val) == "table" then val = val[1] end
    if type(val) ~= "number" then val = 0 end
    local max = (type(st) == "table") and st.max or 100
    if type(max) ~= "number" or max <= 0 then max = 100 end
    return math.Clamp(val / max, 0, 1)
end

local shown, lastFrac, lastChange = 0, nil, 0

hook.Add("HUDPaint", "HG_StaminaBar", function()
    local ply = LocalPlayer()
    local frac
    if cv:GetBool() and IsValid(ply) and ply:Alive() and not gui.IsGameUIVisible() then
        local org = ply.organism
        if org and not org.otrub then frac = staminaFraction(org) end
    end
    local now, dt = RealTime(), FrameTime()
    if frac ~= nil and frac ~= lastFrac then lastFrac, lastChange = frac, now end
    -- visible while stamina is below full or changed recently; fades out once it has sat at full
    local want = frac ~= nil and (frac < 0.995 or now - lastChange < HOLD_FULL)
    shown = math.Clamp(shown + (want and dt / FADE_IN or -dt / FADE_OUT), 0, 1)
    if shown <= 0.001 then return end
    frac = frac or lastFrac or 0

    local w = math.floor(ScrW() * WIDTH_FRAC)
    local x = math.floor((ScrW() - w) / 2)
    local y = math.floor(ScrH() * Y_FRAC - HEIGHT / 2)
    local a = shown * shown -- ease

    local hi, mid, lo = stops()
    if frac > 0.5 then mix(fill, mid, hi, (frac - 0.5) * 2) else mix(fill, lo, mid, frac * 2) end
    fill.a = 255 * a

    -- low stamina: a soft pulsing glow under the filled part
    if frac < 0.3 then
        local pulse = 0.6 + 0.4 * math.abs(math.sin(now * 5))
        glow.r, glow.g, glow.b, glow.a = fill.r, fill.g, fill.b, 110 * pulse * a * (1 - frac / 0.3)
        surface.SetMaterial(glowMat)
        surface.SetDrawColor(glow.r, glow.g, glow.b, glow.a)
        surface.DrawTexturedRect(x - 12, y - 16, math.max(24, w * frac + 24), HEIGHT + 32)
    end

    -- 2026-09-25 HUD pass: edge hairline and ticks from the GoobOS tokens (edge, muted); geometry unchanged
    local T = ZCGoobApps and ZCGoobApps.Theme
    if T and T.edge then
        edge.r, edge.g, edge.b = T.edge.r, T.edge.g, T.edge.b
        tick.r, tick.g, tick.b = T.muted.r, T.muted.g, T.muted.b
        edge.a, tick.a = 180 * a, 90 * a
    else
        edge.a, tick.a = 26 * a, 60 * a
    end
    track.a = 215 * a
    draw.RoundedBox(RADIUS + 1, x - 1, y - 1, w + 2, HEIGHT + 2, edge)
    draw.RoundedBox(RADIUS, x, y, w, HEIGHT, track)
    local fw = math.max(HEIGHT, math.floor(w * frac))
    draw.RoundedBox(RADIUS, x, y, fw, HEIGHT, fill)
    -- quarter ticks on the empty part, so the remaining distance reads at a glance
    for i = 1, 3 do
        local tx = x + math.floor(w * i / 4)
        if tx > x + fw + 2 then draw.RoundedBox(0, tx, y + 1, 1, HEIGHT - 2, tick) end
    end
end)
