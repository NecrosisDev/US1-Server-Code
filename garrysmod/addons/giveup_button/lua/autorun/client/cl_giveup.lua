-- Give Up button: while unconscious (same org.otrub state the unconscious
-- ring reads), shows "PRESS K TO GIVE UP" and space kills you.
-- Companion addon - the workshop ring stays untouched.
if not CLIENT then return end

surface.CreateFont("GiveUp_Text", {
    font = "Bahnschrift",
    size = 30,
    weight = 800,
    antialias = true,
})

local alpha = 0
local lastSend = 0

local function IsUnconscious()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return false end
    local org = ply.organism
    return org and org.otrub == true
end

-- 2026-09-25 HUD pass: a keycap and two words on a GoobOS plate, eased in and out, no pulse.
local fade = {}
-- Pre-restyle drawing, verbatim from the live A+B file; used when the GoobOS kit is not loaded.
local legacyDraw = function()
    local target = IsUnconscious() and 1 or 0
    alpha = math.Approach(alpha, target, FrameTime() * (target == 1 and 2 or 3))
    if alpha <= 0 then return end

    local x = ScrW() / 2
    local y = ScrH() / 2 + 330  -- just below the ring (radius 280)

    -- gentle pulse so it reads as interactive
    local pulse = 0.75 + math.abs(math.sin(CurTime() * 2)) * 0.25

    draw.SimpleText("PRESS K TO GIVE UP", "GiveUp_Text", x + 1, y + 1,
        Color(0, 0, 0, 200 * alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText("PRESS K TO GIVE UP", "GiveUp_Text", x, y,
        Color(255, 255, 255, 255 * alpha * pulse), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

hook.Add("HUDPaint", "GiveUp_Draw", function()
    local K = ZCGoobApps and ZCGoobApps.Kit
    if not (K and K.HudPlate) then return legacyDraw() end
    local a = K.HudFade(fade, IsUnconscious(), 0.3, 0.25)
    if a <= 0 then return end

    local s = K.HudScale()
    local font = K.HudFont(18, 600)
    surface.SetFont(font)
    local tw = surface.GetTextSize("Give up")
    local keyH = math.floor(26 * s)
    local pad, gap, h = math.floor(6 * s), math.floor(10 * s), math.floor(36 * s)
    local w = pad + keyH + gap + tw + math.floor(14 * s)
    local x = math.floor(ScrW() / 2 - w / 2)
    local y = K.HudY("giveup") - math.floor(h / 2) + math.floor((1 - a) * 6 * s) -- just below the ring (radius 280)
    K.HudPlate(x, y, w, h, a)
    K.HudKey("K", x + pad, y + math.floor((h - keyH) / 2), keyH, a)
    K.HudText("Give up", font, x + pad + keyH + gap, y + h / 2, nil, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, a)
end)

-- K is (usually) unbound, so PlayerBindPress never sees it - poll
-- the physical key instead. Works regardless of the player's binds.
local wasDown = false
hook.Add("Think", "GiveUp_Key", function()
    local down = input.IsKeyDown(KEY_K)
    if down and not wasDown and IsUnconscious() then
        if CurTime() - lastSend > 1 then
            lastSend = CurTime()
            net.Start("zc_giveup")
            net.SendToServer()
        end
    end
    wasDown = down
end)
