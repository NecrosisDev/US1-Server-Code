if not CLIENT then return end

-- ============================================================================
-- ZC Crosshair (client) - true-aim reticle for homigrad weapons.
--
-- 2026-09-25: released to all players (the tester lock now applies only to
-- cl_zc_aimassist.lua, which the server grants per player; see sv_zc_crosshair.lua).
--
-- v3: the dot sits where the MUZZLE really points: SWEP:GetTrace() is the
-- same muzzle trace the bullet code starts from, so sway, lean, injuries and
-- recoil all move the dot exactly as they move the shot. Nothing here reads
-- hidden state or corrects aim - it only renders what the gun already does.
--
-- Ring   = stability readout: real shot recoil (LastShootTime), arm injuries
--          and hold-breath from the organism the camera code already uses.
-- Ticks  = "a shot of yours landed on someone you could see"; fed by
--          sv_zc_crosshair.lua (HomigradDamage, line-of-sight gated, no
--          kill or headshot info).
-- Fade   = follows the weapon's own ADS lerp (wep.k), deploy/holster and
--          sprint, and dims when the muzzle is pressed against a wall.
--
-- Convars (archived, per player; v3 also lists them in Settings > Crosshair):
--   zc_crosshair 1            zc_crosshair_centerdot 0 (opt-in centre dot)
--   zc_crosshair_size 0..12   zc_crosshair_r/g/b/a
--   zc_crosshair_outline 1    zc_crosshair_ads 0 (keep while aiming)
--   zc_crosshair_empty 1 (dashed ring when empty)
--   zc_crosshair_notches 1 (gaps in the ring so leaning shows)
--   zc_crosshair_notch_count 4 (1..8)   zc_crosshair_notch_width 24 (degrees, 4..40)
--   zc_crosshair_hitmarker 1  zc_crosshair_hitsound 0
--   zc_crosshair_color 0..5 (custom / white / yellow / cyan / green / magenta)
--   zc_crosshair_blocked 1 (X when the barrel is blocked by cover you can see past)
-- ============================================================================

ZC_CROSSHAIR_VERSION = "20260925.20"

-- Convar handles live in one table: LuaJIT caps a function at 60 upvalues,
-- and the paint function would otherwise hold one per convar.
local CV = {}
CV.Enable    = CreateClientConVar("zc_crosshair", "1", true, false, "Your crosshair, centred on where your gun really points", 0, 1)
CV.Size      = CreateClientConVar("zc_crosshair_size", "3", true, false, "How wide it sits at rest; movement and recoil widen it", 0, 12)
CV.R         = CreateClientConVar("zc_crosshair_r", "255", true, false, "Used when Colour is set to Custom", 0, 255)
CV.G         = CreateClientConVar("zc_crosshair_g", "255", true, false, "Used when Colour is set to Custom", 0, 255)
CV.B         = CreateClientConVar("zc_crosshair_b", "255", true, false, "Used when Colour is set to Custom", 0, 255)
CV.A         = CreateClientConVar("zc_crosshair_a", "200", true, false, "0 is invisible, 255 is solid", 0, 255)
CV.Hitmark   = CreateClientConVar("zc_crosshair_hitmarker", "1", true, false, "Brief ticks when your shot lands on someone you can see", 0, 1)


CV.Notch   = CreateClientConVar("zc_crosshair_notches", "1", true, false, "Gaps in the ring that turn when you lean", 0, 1)
CV.NotchCount = CreateClientConVar("zc_crosshair_notch_count", "4", true, false, "How many gaps, evenly spaced", 1, 8)
CV.NotchWidth = CreateClientConVar("zc_crosshair_notch_width", "24", true, false, "Width of each gap, in degrees", 4, 40)
CV.Dot     = CreateClientConVar("zc_crosshair_centerdot", "0", true, false, "Small dot on the exact aim point", 0, 1)
CV.Outline = CreateClientConVar("zc_crosshair_outline", "1", true, false, "Thin dark edge so it reads on bright walls", 0, 1)
CV.ADS     = CreateClientConVar("zc_crosshair_ads", "0", true, false, "Keep the ring on screen while aiming down sights", 0, 1)
CV.Empty   = CreateClientConVar("zc_crosshair_empty", "1", true, false, "Dashed ring and dimmed arms when your magazine is empty", 0, 1)
CV.HitSnd  = CreateClientConVar("zc_crosshair_hitsound", "0", true, false, "Quiet click with each hit tick", 0, 1)
CV.Preset  = CreateClientConVar("zc_crosshair_color", "1", true, false, "Pick a preset, or Custom to use the red, green and blue sliders", 0, 5)
CV.Type    = CreateClientConVar("zc_crosshair_type", "0", true, false, "Ring, a cross, both, or a T-shaped cross", 0, 3)
CV.Arm     = CreateClientConVar("zc_crosshair_arm", "8", true, false, "Length of each cross arm, in pixels at 1080p", 3, 24)
CV.Blocked = CreateClientConVar("zc_crosshair_blocked", "1", true, false, "An X appears when cover in front of the barrel would stop your shot", 0, 1)

-- Yellow, cyan, magenta and white stay distinct under the common red-green
-- colour-vision deficiencies; green is here because players ask for it.
local PRESETS = {
    [1] = { 255, 255, 255 },
    [2] = { 240, 228, 66 },
    [3] = { 86, 200, 240 },
    [4] = { 80, 230, 90 },
    [5] = { 235, 90, 235 },
}

local LocalPlayer = LocalPlayer
local IsValid     = IsValid
local FrameTime   = FrameTime
local CurTime     = CurTime
local EyeAngles   = EyeAngles
local Lerp        = Lerp
local math_rad    = math.rad
local math_cos    = math.cos
local math_sin    = math.sin
local angdiff     = math.AngleDifference
local ScrH        = ScrH
local util_TraceLine = util.TraceLine
local surface_SetDrawColor = surface.SetDrawColor
local surface_DrawPoly     = surface.DrawPoly
local draw_NoTexture       = draw.NoTexture

-- ---------------------------------------------------------------- geometry --
-- The ring is three polygon bands: a solid core, a thin dark edge just inside
-- it (reads on bright walls), and an outer glow textured with the stock
-- vgui/gradient-l so the fade is blended by the GPU instead of stepped.
local GRAD = Material("vgui/gradient-l")
-- u coordinate at which vgui/gradient-l is opaque (0 = left edge of the image).
local GRAD_U_SOLID = 0
local TAU = math.pi * 2

-- Rest radius in px at 1080p for a size setting: 3 px a step from size 2
-- (14 px) up, as it always was, and 3.5 px a step below it, so size 0 (7 px)
-- is half the old minimum.
local function restRadius(size)
    if size >= 2 then return 8 + size * 3 end
    return 7 + math.max(size, 0) * 3.5
end

-- spans: { startAngle, endAngle, pieces }; angles in screen space (y down).
-- drawBand now sizes pieces itself (PIECE); the third field is informational.
local function makeSpans(kind)
    local out = {}
    if kind == "dash" then
        for i = 0, 15 do
            local a0 = i * TAU / 16 + 0.06
            out[#out + 1] = { a0, a0 + TAU / 32, 1 }
        end
    else
        out[1] = { 0, TAU, 36 }
    end
    return out
end
local SPANS_FULL, SPANS_DASH = makeSpans("full"), makeSpans("dash")

-- Reload progress: 16 dashes in order, clockwise from the top of the ring.
local SPANS_RELOAD = {}
for i = 0, 15 do
    local a0 = -TAU / 4 + i * TAU / 16 + 0.06
    SPANS_RELOAD[i + 1] = { a0, a0 + TAU / 32, 1 }
end

-- Notched ring: count evenly spaced gaps of the given width, the first one
-- centred on the right. Rebuilt only when either setting changes.
local notchCache, notchKey = nil, nil
local function notchSpans()
    local count = math.Clamp(CV.NotchCount:GetInt(), 1, 8)
    local width = math.Clamp(CV.NotchWidth:GetFloat(), 4, 40)
    local key = count * 1000 + width
    if key == notchKey then return notchCache end
    local half, step = math_rad(width) * 0.5, TAU / count
    local out = {}
    for i = 0, count - 1 do
        local a0, a1 = i * step + half, (i + 1) * step - half
        -- about one polygon per 10 degrees of arc keeps the edge round
        out[#out + 1] = { a0, a1, math.max(1, math.ceil((a1 - a0) / math_rad(10))) }
    end
    notchCache, notchKey = out, key
    return out
end

local QUAD = { { x = 0, y = 0, u = 0, v = 0.5 }, { x = 0, y = 0, u = 0, v = 0.5 }, { x = 0, y = 0, u = 0, v = 0.5 }, { x = 0, y = 0, u = 0, v = 0.5 } }

-- One quad of a band between radii r0..r1 and angles a..b (radians). Vertices
-- go in increasing screen angle, the same winding as the dot polygon below.
local function bandPiece(x, y, r0, r1, a, b)
    local q1, q2, q3, q4 = QUAD[1], QUAD[2], QUAD[3], QUAD[4]
    local ca, sa, cb, sb = math_cos(a), math_sin(a), math_cos(b), math_sin(b)
    q1.x, q1.y = x + ca * r0, y + sa * r0
    q2.x, q2.y = x + ca * r1, y + sa * r1
    q3.x, q3.y = x + cb * r1, y + sb * r1
    q4.x, q4.y = x + cb * r0, y + sb * r0
    surface_DrawPoly(QUAD)
end

local PIECE = math_rad(10)   -- about one quad per 10 degrees keeps arcs round

-- One annular band from radius r0 to r1 over spans iFrom..iTo, rotated by roll
-- (radians), in colour cr, cg, cb, ca. uIn/uOut are the texture u at the inner
-- and outer edge. When fade > 0, the first and last `fade` radians of each span
-- ramp from nothing up to ca in `steps` flat sub-pieces: a surface polygon
-- cannot vary its alpha along its length, so the ramp is stepped (about 1 px
-- per step at the default size). A span that is a whole circle has no ends.
local function drawBand(x, y, r0, r1, spans, roll, uIn, uOut, cr, cg, cb, ca, fade, steps, iFrom, iTo)
    QUAD[1].u, QUAD[4].u, QUAD[2].u, QUAD[3].u = uIn, uIn, uOut, uOut
    for i = iFrom or 1, iTo or #spans do
        local sp = spans[i]
        local a0, a1 = sp[1] + roll, sp[2] + roll
        local f = 0
        if fade and fade > 0 and a1 - a0 < TAU - 1e-4 then f = math.min(fade, (a1 - a0) * 0.45) end
        if f > 0 then
            local st = f / steps
            for k = 1, steps do
                surface_SetDrawColor(cr, cg, cb, ca * (k - 0.5) / steps)
                bandPiece(x, y, r0, r1, a0 + st * (k - 1), a0 + st * k)
                bandPiece(x, y, r0, r1, a1 - st * k, a1 - st * (k - 1))
            end
        end
        surface_SetDrawColor(cr, cg, cb, ca)
        local m0, m1 = a0 + f, a1 - f
        local n = math.max(1, math.ceil((m1 - m0) / PIECE - 1e-6))
        local step = (m1 - m0) / n
        for k = 1, n do bandPiece(x, y, r0, r1, m0 + step * (k - 1), m0 + step * k) end
    end
end

local DOT_SEGS = 16
local DOTC, dotPoly, dotOutPoly = {}, {}, {}
for i = 1, DOT_SEGS do
    local a = math_rad((i - 1) / DOT_SEGS * 360)
    DOTC[i] = { math_cos(a), math_sin(a) }
    dotPoly[i] = { x = 0, y = 0 }
    dotOutPoly[i] = { x = 0, y = 0 }
end

local function fillDot(poly, x, y, r)
    for i = 1, DOT_SEGS do
        local p, c = poly[i], DOTC[i]
        p.x = x + c[1] * r
        p.y = y + c[2] * r
    end
end

-- One pass of the ring over spans iFrom..iTo, all alphas scaled by k. Every
-- band starts at the ring's inner face r0 and fades outward on the stock
-- gradient; only the inner face itself stays hard:
--   tail   16% of the ring's opacity over the full glow width
--   heavy  45% over the inner quarter of the glow
--   line  100% over coreW, so a crisp inner face with a soft outer side
--   edge   a flat dark line just inside r0, when outlines are on
-- Arc and dash ends fade out over `fade` radians in `steps` steps.
local function drawRingPass(x, y, r0, coreW, gw, spans, roll, cr, cg, cb, ringA, edgeA, k, fade, steps, iFrom, iTo)
    if iTo and iFrom and iTo < iFrom then return end
    local uIn, uOut = GRAD_U_SOLID, 1 - GRAD_U_SOLID
    surface.SetMaterial(GRAD)
    drawBand(x, y, r0, r0 + gw, spans, roll, uIn, uOut, cr, cg, cb, ringA * 0.16 * k, fade, steps, iFrom, iTo)
    drawBand(x, y, r0, r0 + gw * 0.25, spans, roll, uIn, uOut, cr, cg, cb, ringA * 0.45 * k, fade, steps, iFrom, iTo)
    drawBand(x, y, r0, r0 + coreW, spans, roll, uIn, uOut, cr, cg, cb, ringA * k, fade, steps, iFrom, iTo)
    draw.NoTexture()
    if edgeA > 0 then
        drawBand(x, y, r0 - math.max(1, coreW * 0.5), r0, spans, roll, 0, 0, 0, 0, 0, edgeA * k, fade, steps, iFrom, iTo)
    end
end

-- A soft stroke from A to B (offsets from x, y, turned by the roll c, s), w px
-- wide, on the stock gradient: u = uA at A and uB at B, so a stroke can start
-- crisp and ease off toward its tip like the ring. Colour and material are
-- set by the caller. Vertex order keeps the dot polygon's (proven) winding.
local STROKE = { { x = 0, y = 0, u = 0, v = 0.5 }, { x = 0, y = 0, u = 0, v = 0.5 }, { x = 0, y = 0, u = 0, v = 0.5 }, { x = 0, y = 0, u = 0, v = 0.5 } }
local DIAMOND = { { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 } }
local function drawDiamond(x, y, d, c, s)
    local v1, v2, v3, v4 = DIAMOND[1], DIAMOND[2], DIAMOND[3], DIAMOND[4]
    v1.x, v1.y = x + d * s, y - d * c
    v2.x, v2.y = x + d * c, y + d * s
    v3.x, v3.y = x - d * s, y + d * c
    v4.x, v4.y = x - d * c, y - d * s
    surface_DrawPoly(DIAMOND)
end

local function drawStroke(x, y, ax, ay, bx, by, c, s, w, uA, uB)
    local px, py = x + ax * c - ay * s, y + ax * s + ay * c
    local qx, qy = x + bx * c - by * s, y + bx * s + by * c
    local dx, dy = qx - px, qy - py
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then return end
    local nx, ny = dy / len * w * 0.5, -dx / len * w * 0.5
    local v1, v2, v3, v4 = STROKE[1], STROKE[2], STROKE[3], STROKE[4]
    v1.x, v1.y, v1.u = px + nx, py + ny, uA
    v2.x, v2.y, v2.u = qx + nx, qy + ny, uB
    v3.x, v3.y, v3.u = qx - nx, qy - ny, uB
    v4.x, v4.y, v4.u = px - nx, py - ny, uA
    surface_DrawPoly(STROKE)
end

-- Hit ticks: four soft strokes on the diagonals just outside the ring, solid at
-- the inner end and 40% at the tip, with a dark outline 1.5 px wider. p is
-- the pulse (1 -> 0), tk the strength floor, k a size factor (1 on the HUD,
-- smaller when the settings preview has to fit a large ring).
local function drawHitTicks(x, y, ringR, size, scale, p, tk, outline, cr, cg, cb, c, s, k)
    k = k or 1
    local off = ringR + (3 + (1 - p) * 6) * k
    local len = (4 + size * 1.5) * k
    local o = off * 0.7071
    local e = (off + len) * 0.7071
    local w = math.max(1.5, 1.5 * scale * k)
    surface.SetMaterial(GRAD)
    if outline then
        -- strong enough to read on bright walls, where the white vanishes
        surface_SetDrawColor(0, 0, 0, 170 * p * tk)
        drawStroke(x, y, -o, -o, -e, -e, c, s, w + 1.5, 0, 0.6)
        drawStroke(x, y, o, -o, e, -e, c, s, w + 1.5, 0, 0.6)
        drawStroke(x, y, -o, o, -e, e, c, s, w + 1.5, 0, 0.6)
        drawStroke(x, y, o, o, e, e, c, s, w + 1.5, 0, 0.6)
    end
    surface_SetDrawColor(cr, cg, cb, 255 * p * tk)
    drawStroke(x, y, -o, -o, -e, -e, c, s, w, 0, 0.6)
    drawStroke(x, y, o, -o, e, -e, c, s, w, 0, 0.6)
    drawStroke(x, y, -o, o, -e, e, c, s, w, 0, 0.6)
    drawStroke(x, y, o, o, e, e, c, s, w, 0, 0.6)
    draw_NoTexture()
end

-- The reticle at x, y for ring radius ringR, in one of four types: the ring
-- (0), a cross (1), both (2), or a T-cross with no top arm (3). Shared by the
-- HUD and the settings preview; k scales it down when the preview must fit.
-- reloadP lights the ring's dashes (or, for a cross alone, its arms) clockwise
-- from the top; empty dashes the ring and dims the arms.
local ARM_DIRS = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }   -- top, right, bottom, left (screen, y down)
local function drawShape(x, y, ringR, scale, k, roll, cr, cg, cb, ringA, edgeA, gw, reloadP, empty)
    local kind = CV.Type:GetInt()
    local fade = math.min(4 * scale * k / math.max(ringR, 1), 0.5)   -- arc ends fade over ~4 px
    local dashFade = math.min(fade, 0.049)    -- short dashes keep a solid middle
    if kind == 0 or kind == 2 then
        local r0 = ringR - 0.5 * scale * k      -- the ring's inner face
        local coreW = 2 * scale * k             -- line fades out over 2 px, reads as 1 px
        if reloadP then
            local lit = math.floor(reloadP * 16 + 0.5)
            drawRingPass(x, y, r0, coreW, gw, SPANS_RELOAD, roll, cr, cg, cb, ringA, edgeA, 1, dashFade, 2, 1, lit)
            drawRingPass(x, y, r0, coreW, gw, SPANS_RELOAD, roll, cr, cg, cb, ringA, edgeA, 0.3, dashFade, 2, lit + 1, 16)
        else
            local spans = empty and SPANS_DASH or (CV.Notch:GetBool() and notchSpans() or SPANS_FULL)
            drawRingPass(x, y, r0, coreW, gw, spans, roll, cr, cg, cb, ringA, edgeA, 1, empty and dashFade or fade, empty and 2 or 3)
        end
    end
    if kind == 0 then return end
    -- arms: in a cross they start at the ring radius (the gap grows and shrinks
    -- like the ring would); with the ring they start just outside its glow
    local inner = kind == 2 and (ringR + gw * 0.35 + 2 * scale * k) or ringR
    local outer = inner + CV.Arm:GetInt() * scale * k
    local w = math.max(1.5, 1.5 * scale * k)
    local c, s = math.cos(roll), math.sin(roll)
    local first = kind == 3 and 2 or 1        -- the T-cross has no top arm
    local n = 5 - first
    local lit = (reloadP and kind ~= 2) and math.floor(reloadP * n + 0.5) or n
    local dim = empty and 0.35 or 1
    surface.SetMaterial(GRAD)
    for i = first, 4 do
        local d = ARM_DIRS[i]
        local a = ringA * dim * ((i - first + 1) <= lit and 1 or 0.3)
        if edgeA > 0 then
            surface_SetDrawColor(0, 0, 0, edgeA * a / math.max(ringA, 1))
            drawStroke(x, y, d[1] * inner, d[2] * inner, d[1] * outer, d[2] * outer, c, s, w + 1.5, 0, 0.6)
        end
        surface_SetDrawColor(cr, cg, cb, a)
        drawStroke(x, y, d[1] * inner, d[2] * inner, d[1] * outer, d[2] * outer, c, s, w, 0, 0.6)
    end
    draw_NoTexture()
end

local COL_MAIN = Color(255, 255, 255, 220)
local COL_OUT  = Color(0, 0, 0, 180)

-- ------------------------------------------------------------------- state --
local alpha      = 0      -- fade multiplier
local ringR      = 0      -- current ring radius (asymmetric spring)
local breath     = 0      -- hold-breath lerp
local speedK     = 0      -- eased horizontal speed (movement term)
local heat       = 0      -- sustained-fire bloom, +1 per shot, cools off
local lastShot   = 0      -- LastShootTime seen last frame (detects new shots)
local lastP, lastY = nil, nil -- view angles last frame (turn rate)
local hitPulse   = 0      -- 1 right after a landed shot, decays over ~0.35 s
local scrX, scrY = 0, 0   -- screen-space smoothed dot position
local haveScr    = false
local lastWep    = nil
local isGun      = false
local blockedK   = 0      -- 0..1 lerp of the blocked-barrel cue

-- Blocked barrel: the muzzle trace stops on something close while the eye,
-- looking the same way, sees clear well past it (gun under a cover lip, or
-- pointed into the floor). Bodies never count - that is a close-range target.
local BLOCK_NEAR  = 300   -- only check when the muzzle hit is closer than this
local BLOCK_CLEAR = 160   -- the eye must see this much further than the muzzle
local eyeFilter = {}
local eyeTrace  = { filter = eyeFilter, mask = MASK_SHOT }

-- True while anything but this player's own eyes owns the screen:
--   * a killcam or highlight replay: the replay viewer (lua/zc_killcam viewer
--     parts) returns its state from ZCKillcamView.State() only while one runs,
--     including its waiting, end-card and leaving phases; allocation-free
--   * the replay drawn inside a GoobOS panel (ZCKillcamView.UIActive)
--   * any other view entity
--   * as a backstop, a camera more than 512 units from this player's eyes
--     (far enough that homigrad's ragdoll camera and third person never trip it)
-- Replays can play while the player is alive (quick respawn, highlights), and
-- the viewer paints its own screens from HUDPaint, so the crosshair must check.
local CAMERA_FAR_SQR = 512 * 512
local function replayOwnsScreen(ply)
    local kc = ZCKillcamView
    -- postround_20260925: a replay kept OUT of the player's view (the round-end side card, a living player's
    -- highlight: ZCKillcamView.UISide, killcam cl_part_06) does not own the screen - their own eyes do.
    local side = false
    if kc and kc.UISide then
        local ok, s = pcall(kc.UISide)
        side = ok and s == true
    end
    if kc and not side then
        if kc.State then
            local ok, st = pcall(kc.State)
            if ok and st ~= nil then return true end
        end
        if kc.UIActive then
            local ok, on = pcall(kc.UIActive)
            if ok and on == true then return true end
        end
    end
    if ply.GetViewEntity and ply:GetViewEntity() ~= ply then return true end
    return EyePos():DistToSqr(ply:EyePos()) > CAMERA_FAR_SQR
end

local function reset()
    alpha = 0
    haveScr = false
end

-- Firearm = homigrad base weapon with a real muzzle and a known cartridge.
-- Melee (weapon_melee, ammo "none"), grenades and repair tools fall out here.
local function weaponIsGun(wep)
    if not wep.GetTrace or not wep.LocalMuzzlePos then return false end
    local ammo = wep.Primary and wep.Primary.Ammo
    if not isstring(ammo) or ammo == "" or ammo == "none" then return false end
    local tbl = hg and hg.ammotypeshuy
    if istable(tbl) and tbl[ammo] == nil then return false end
    return true
end

net.Receive("zc_crosshair_hit", function()
    if not CV.Hitmark:GetBool() then return end
    local me = LocalPlayer()
    if IsValid(me) and replayOwnsScreen(me) then return end   -- no ticks queued behind a replay
    hitPulse = 1
    if CV.HitSnd:GetBool() then
        local ply = LocalPlayer()
        if IsValid(ply) then ply:EmitSound("buttons/lightswitch2.wav", 60, 160, 0.3, CHAN_STATIC) end
    end
end)

local function v3Paint()
    if not CV.Enable:GetBool() then return end

    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then reset() return end
    -- never over a replay: gone at once (no fade), and a hit tick that lands
    -- meanwhile is dropped so it cannot flash when play resumes
    if replayOwnsScreen(ply) then reset() hitPulse = 0 return end

    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) then reset() return end
    if wep ~= lastWep then
        lastWep = wep
        isGun = weaponIsGun(wep)
        haveScr = false
    end
    if not isGun then reset() return end

    local ft = math.min(FrameTime(), 0.05)

    -- ---------------------------------------------------------- visibility --
    local vis = 1
    if wep.deploy or wep.holster then vis = 0 end
    if vis > 0 and wep.IsSprinting and wep:IsSprinting() then vis = 0 end
    if vis > 0 and not CV.ADS:GetBool() then
        -- wep.k is the base's own 0..1 aim lerp; gone once the sights are a third of the way up
        vis = vis * math.Clamp(1 - (tonumber(wep.k) or 0) * 3, 0, 1)
    end

    -- --------------------------------------------------------------- trace --
    local ok, tr = pcall(wep.GetTrace, wep)
    if ok and istable(tr) and tr.HitPos and tr.StartPos then
        local dist = tr.StartPos:Distance(tr.HitPos)
        if vis > 0 and dist < 40 then vis = vis * math.Clamp((dist - 12) / 28, 0, 1) end

        local blocked = false
        if vis > 0 and dist >= 30 and dist < BLOCK_NEAR and CV.Blocked:GetBool() then
            local hitEnt = tr.Entity
            if not (IsValid(hitEnt) and (hitEnt:IsPlayer() or hitEnt:IsNPC() or hitEnt:IsRagdoll() or hitEnt:IsNextBot())) then
                local eye = ply:EyePos()
                eyeFilter[1], eyeFilter[2] = ply, wep
                eyeFilter[3] = IsValid(ply.FakeRagdoll) and ply.FakeRagdoll or ply
                eyeFilter[4] = IsValid(wep.worldModel) and wep.worldModel or wep
                eyeTrace.start = eye
                eyeTrace.endpos = eye + ply:GetAimVector() * (dist + BLOCK_CLEAR)
                blocked = not util_TraceLine(eyeTrace).Hit
            end
        end
        blockedK = Lerp(12 * ft, blockedK, blocked and 1 or 0)
        local scr = tr.HitPos:ToScreen()
        if scr.visible then
            if haveScr and math.abs(scr.x - scrX) < 48 and math.abs(scr.y - scrY) < 48 then
                local f = 1 - math.exp(-60 * ft)
                scrX = scrX + (scr.x - scrX) * f
                scrY = scrY + (scr.y - scrY) * f
            else
                scrX, scrY = scr.x, scr.y
                haveScr = true
            end
        else
            haveScr = false
        end
    else
        vis = 0
    end

    alpha = Lerp(14 * ft, alpha, vis)
    hitPulse = math.max(0, hitPulse - ft / 0.35)
    if not haveScr then return end
    if alpha < 0.02 and hitPulse <= 0 then return end

    -- ------------------------------------------------------------ ring size --
    -- A readout of how steady the gun is. The shot still goes to the ring
    -- centre (the muzzle trace); every cartridge here has zero cone spread.
    local size = CV.Size:GetInt()
    local scale = ScrH() / 1080
    local base = restRadius(size) * scale

    -- recoil: a kick per shot (engine shot timer) plus heat that builds under
    -- sustained fire and cools at ~2.5 shots per second
    local shotT = wep.LastShootTime and wep:LastShootTime() or 0
    if shotT > lastShot then heat = math.min(heat + 1, 8) end
    lastShot = shotT
    heat = math.max(0, heat - ft * 2.5)
    local since = CurTime() - shotT
    local kick = math.Clamp(1 - since / 0.28, 0, 1)
    kick = kick * kick
    -- kick grows with the cartridge's force on a log curve, so guns differ:
    -- about 4 px at force 12, 9 at 25, 14 at 50, 18 at 80 (1080p). Heat adds a
    -- third of that per shot held, and all recoil stops at 1.25x the rest size.
    local force = wep.Primary and tonumber(wep.Primary.Force) or 10
    local kickPx = math.Clamp(4 + 5 * math.log(math.max(force, 1) / 12) / math.log(2), 3, 20)
    local recoil = math.min((kick * kickPx + heat * kickPx * 0.35) * scale, base * 1.25)

    -- movement: walking widens, running more, airborne a lot. Speed is eased
    -- (~0.15 s) so each step breathes instead of jumping.
    speedK = Lerp(8 * ft, speedK, ply:GetVelocity():Length2D())
    local move = math.Clamp(speedK / 200, 0, 1.5) * 10 * scale
    if not ply:IsOnGround() then move = move + 16 * scale end

    -- turning: fast mouse turns swing the gun (homigrad sway lags the view)
    local ang = EyeAngles()
    local turn = 0
    if lastP then
        local dp, dy = angdiff(ang.p, lastP), angdiff(ang.y, lastY)
        turn = math.Clamp(math.sqrt(dp * dp + dy * dy) / ft / 20, 0, 10) * scale
    end
    lastP, lastY = ang.p, ang.y

    -- body: hurt arms widen, held breath tightens (same organism fields cl_camera reads)
    local unstable = 0
    local holding = false
    local org = ply.organism
    if istable(org) then
        local larm = tonumber(org.larm) or 0
        local rarm = tonumber(org.rarm) or 0
        unstable = math.Clamp(larm + rarm, 0, 2) * 5 * scale
        holding = org.holdingbreath and true or false
    end
    breath = Lerp(6 * ft, breath, holding and 1 or 0)

    -- stance: crouched is steadier
    local stance = ply:Crouching() and 0.8 or 1

    -- never more than 2.5x the resting ring, whatever stacks up
    local target = math.min((base + move + turn + unstable) * stance * (1 - 0.25 * breath) + recoil, base * 2.5)
    -- aim assist cue (cl_zc_aimassist.lua): ring tightens while friction is on
    local assist = tonumber(ZC_AIMASSIST_WEIGHT) or 0
    if assist > 0 then target = target * (1 - 0.2 * assist) end
    if target > ringR then
        ringR = Lerp(30 * ft, ringR, target)
    else
        ringR = Lerp(6 * ft, ringR, target)
    end

    -- ------------------------------------------------------------- colours --
    local a = CV.A:GetInt() * alpha
    local preset = PRESETS[CV.Preset:GetInt()]
    if preset then
        COL_MAIN.r, COL_MAIN.g, COL_MAIN.b = preset[1], preset[2], preset[3]
    else
        COL_MAIN.r, COL_MAIN.g, COL_MAIN.b = CV.R:GetInt(), CV.G:GetInt(), CV.B:GetInt()
    end
    -- the ring steps back while the blocked X is up
    COL_MAIN.a = a * (1 - 0.6 * blockedK)
    local op = CV.A:GetInt() / 255
    COL_OUT.a = 180 * alpha * op
    local outline = CV.Outline:GetBool()

    local x, y = math.Round(scrX), math.Round(scrY)
    local roll = math.rad(-EyeAngles().r)
    local c, s = math.cos(roll), math.sin(roll)

    local empty = false
    if CV.Empty:GetBool() and wep.Clip1 and wep.GetMaxClip1 then
        local maxClip = wep:GetMaxClip1() or 0
        empty = maxClip > 0 and (wep:Clip1() or 0) <= 0
    end

    -- reload progress from the weapon base (LastReload = start, reload = end)
    local reloadP
    if wep.reload and wep.LastReload then
        local dur = wep.reload - wep.LastReload
        if dur > 0 then reloadP = math.Clamp((CurTime() - wep.LastReload) / dur, 0, 1) end
    end

    -- ------------------------------------------------------------- shape --
    if alpha > 0.02 then
        local gw = math.Clamp(base * 0.65, 5 * scale, 12 * scale) -- glow width follows ring size
        local edgeA = outline and 140 * alpha * op or 0
        -- COL_MAIN.a is already dimmed while the blocked X is up
        drawShape(x, y, ringR, scale, 1, roll, COL_MAIN.r, COL_MAIN.g, COL_MAIN.b, COL_MAIN.a, edgeA, gw, reloadP, empty)
    end
    COL_MAIN.a = a

    -- ----------------------------------------------------------------- dot --
    if blockedK > 0.5 and alpha > 0.02 then
        -- a solid diamond where the diagonals cross, and four arms that start at
        -- its edge (so nothing overlaps) and ease off to 40% at the tips; a
        -- dark outline 1 px wider underneath so it reads on bright walls
        local h = 2 + size * 0.75
        local w = math.max(1.5, 1.5 * scale)
        local d = w * 0.7071
        local a0 = w * 0.3536                   -- arm start: w/2 along the diagonal
        if outline then
            surface_SetDrawColor(0, 0, 0, COL_OUT.a * 0.85)   -- a warning: keep it readable on bright walls
            draw_NoTexture()
            drawDiamond(x, y, d + 0.5, c, s)
            surface.SetMaterial(GRAD)
            drawStroke(x, y, -a0, -a0, -h, -h, c, s, w + 1, 0, 0.6)
            drawStroke(x, y, a0, -a0, h, -h, c, s, w + 1, 0, 0.6)
            drawStroke(x, y, -a0, a0, -h, h, c, s, w + 1, 0, 0.6)
            drawStroke(x, y, a0, a0, h, h, c, s, w + 1, 0, 0.6)
        end
        surface_SetDrawColor(COL_MAIN)
        draw_NoTexture()
        drawDiamond(x, y, d, c, s)
        surface.SetMaterial(GRAD)
        drawStroke(x, y, -a0, -a0, -h, -h, c, s, w, 0, 0.6)
        drawStroke(x, y, a0, -a0, h, -h, c, s, w, 0, 0.6)
        drawStroke(x, y, -a0, a0, -h, h, c, s, w, 0, 0.6)
        drawStroke(x, y, a0, a0, h, h, c, s, w, 0, 0.6)
        draw_NoTexture()
    elseif CV.Dot:GetBool() and alpha > 0.02 then
        local r = 1 + size * 0.25
        draw_NoTexture()
        if outline then
            surface_SetDrawColor(COL_OUT)
            fillDot(dotOutPoly, x, y, r + 1)
            surface_DrawPoly(dotOutPoly)
        end
        surface_SetDrawColor(COL_MAIN)
        fillDot(dotPoly, x, y, r)
        surface_DrawPoly(dotPoly)
    end

    -- --------------------------------------------------------------- ticks --
    if hitPulse > 0 then
        local tk = math.max(op, 0.5)            -- ticks keep at least half strength
        drawHitTicks(x, y, ringR, size, scale, hitPulse, tk, outline, COL_MAIN.r, COL_MAIN.g, COL_MAIN.b, c, s)
    end
end

hook.Add("HUDPaint", "ZC_Crosshair.HUDPaint", v3Paint)

-- ------------------------------------------------------------- settings UI --
-- hg.settings:AddOpt feeds both the legacy ZCity options menu and the GoobOS
-- Settings app (which copies hg.settings.tbl by category).
-- Rows for the ZCity settings list, which GoobOS Settings shows. Grouped under
-- four headings; meta[8] is the row's position (GoobOS A.OrderedRows), and a
-- choice row carries its labels in meta[7]. The old ZCity menu ignores both.
local SETTINGS = {
    { "Crosshair", {
        { "zc_crosshair", "Show crosshair" },
        { "zc_crosshair_type", "Type", choice = { "Ring", "Cross", "Ring + cross", "T-cross" } },
        { "zc_crosshair_size", "Size" },
        { "zc_crosshair_a", "Opacity" },
        { "zc_crosshair_ads", "Keep while aiming" },
    } },
    { "Crosshair colour", {
        { "zc_crosshair_color", "Colour", choice = { "Custom", "White", "Yellow", "Cyan", "Green", "Magenta" } },
        { "zc_crosshair_r", "Custom red" },
        { "zc_crosshair_g", "Custom green" },
        { "zc_crosshair_b", "Custom blue" },
        { "zc_crosshair_outline", "Dark edge" },
    } },
    { "Crosshair feedback", {
        { "zc_crosshair_hitmarker", "Hit ticks" },
        { "zc_crosshair_hitsound", "Hit click" },
        { "zc_crosshair_empty", "Dashed ring when empty" },
        { "zc_crosshair_blocked", "X when the barrel is blocked" },
    } },
    { "Crosshair shape", {
        { "zc_crosshair_notches", "Lean notches" },
        { "zc_crosshair_notch_count", "Notch count" },
        { "zc_crosshair_notch_width", "Notch width" },
        { "zc_crosshair_arm", "Cross arm length" },
        { "zc_crosshair_centerdot", "Centre dot" },
    } },
}

-- ---------------------------------------------------- share and reset --
-- A share code is "zcx1-" and all 17 values in SETTINGS order, '-' separated;
-- each convar clamps what it receives to its own range.
local SHARE_ORDER = {}
for _, group in ipairs(SETTINGS) do
    for _, row in ipairs(group[2]) do SHARE_ORDER[#SHARE_ORDER + 1] = row[1] end
end
local SHARE_PREFIX = "zcx2"
-- codes made before types existed (zcx1: 17 values in the old order) still apply
local SHARE_ORDER_V1 = { "zc_crosshair", "zc_crosshair_size", "zc_crosshair_a", "zc_crosshair_ads", "zc_crosshair_color",
    "zc_crosshair_r", "zc_crosshair_g", "zc_crosshair_b", "zc_crosshair_outline", "zc_crosshair_hitmarker",
    "zc_crosshair_hitsound", "zc_crosshair_empty", "zc_crosshair_blocked", "zc_crosshair_notches",
    "zc_crosshair_notch_count", "zc_crosshair_notch_width", "zc_crosshair_centerdot" }

local function exportCode()
    local parts = { SHARE_PREFIX }
    for _, name in ipairs(SHARE_ORDER) do
        local cv = GetConVar(name)
        parts[#parts + 1] = tostring(math.Round(cv and cv:GetFloat() or 0))
    end
    return table.concat(parts, "-")
end

-- returns ok, message
local function importCode(code)
    local parts = string.Explode("-", string.Trim(code or ""))
    local order = (parts[1] == SHARE_PREFIX and SHARE_ORDER) or (parts[1] == "zcx1" and SHARE_ORDER_V1)
    if not order or #parts ~= #order + 1 then
        return false, "That is not a crosshair code."
    end
    local values = {}
    for i = 2, #parts do
        local v = tonumber(parts[i])
        if not v then return false, "That code is damaged; nothing was changed." end
        values[i - 1] = v
    end
    for i, name in ipairs(order) do RunConsoleCommand(name, tostring(values[i])) end
    return true, "Crosshair code applied."
end

local function resetAll()
    for _, cv in pairs(CV) do RunConsoleCommand(cv:GetName(), cv:GetDefault()) end
end

-- ------------------------------------------------------ settings preview --
-- The same drawing code as the HUD, fed by the live settings and a looping
-- demo: at rest, walking, firing with hit ticks, reloading. Returns the phase.
local PREVIEW_CYCLE = 8
local PREVIEW_KICK = math.Clamp(4 + 5 * math.log(35 / 12) / math.log(2), 3, 20)   -- a typical rifle
local function drawPreview(cx, cy, t, fit)
    local cyc = t % PREVIEW_CYCLE
    local scale = ScrH() / 1080
    local size = CV.Size:GetInt()
    local base = restRadius(size) * scale
    local r, reloadP, hitP, label = base, nil, 0, "At rest"
    if cyc >= 2.4 and cyc < 4 then
        label = "Walking"
        r = base + math.min(1, (cyc - 2.4) / 0.35) * 7.5 * scale
    elseif cyc >= 4 and cyc < 5.6 then
        label = "Firing"
        local kick = 1 - ((cyc - 4) % 0.15) / 0.15
        local demoHeat = math.min(4, (cyc - 4) / 0.15 * 0.6)
        r = base + math.min((kick * kick * PREVIEW_KICK + demoHeat * PREVIEW_KICK * 0.35) * scale, base * 1.25)
        for _, at in ipairs({ 4.3, 5.0 }) do
            local since = cyc - at
            if since >= 0 and since < 0.35 then hitP = 1 - since / 0.35 end
        end
    elseif cyc >= 5.6 and cyc < 7.6 then
        label = "Reloading"
        reloadP = (cyc - 5.6) / 2
    end
    r = math.min(r, base * 2.5)
    local gw = math.Clamp(base * 0.65, 5 * scale, 12 * scale)
    -- a big crosshair shrinks as a whole to fit the swatch (arms included)
    local kind = CV.Type:GetInt()
    local reach = gw
    if kind ~= 0 then reach = math.max(gw, (kind == 2 and gw * 0.35 + 2 * scale or 0) + CV.Arm:GetInt() * scale) end
    local k = 1
    if fit and r + reach + 12 > fit then k = fit / (r + reach + 12) end
    r, gw = r * k, gw * k

    local preset = PRESETS[CV.Preset:GetInt()]
    local cr, cg, cb
    if preset then cr, cg, cb = preset[1], preset[2], preset[3] else cr, cg, cb = CV.R:GetInt(), CV.G:GetInt(), CV.B:GetInt() end
    local ringA = CV.A:GetInt()
    local op = ringA / 255
    local outline = CV.Outline:GetBool()
    local edgeA = outline and 140 * op or 0
    drawShape(cx, cy, r, scale, k, 0, cr, cg, cb, ringA, edgeA, gw, reloadP, false)
    if CV.Dot:GetBool() then
        local rd = (1 + size * 0.25) * k
        draw_NoTexture()
        if outline then
            surface_SetDrawColor(0, 0, 0, 180 * op)
            fillDot(dotOutPoly, cx, cy, rd + 1)
            surface_DrawPoly(dotOutPoly)
        end
        surface_SetDrawColor(cr, cg, cb, ringA)
        fillDot(dotPoly, cx, cy, rd)
        surface_DrawPoly(dotPoly)
    end
    if hitP > 0 and CV.Hitmark:GetBool() then
        drawHitTicks(cx, cy, r, size, scale, hitP, math.max(op, 0.5), outline, cr, cg, cb, 1, 0, k)
    end
    return label
end

-- The preview column of the Crosshair page: the preview on a dark and a
-- bright swatch (stacked), Reset / Copy code, and a field to apply a code.
-- refresh() rebuilds the page so the sliders show values changed here.
local PREVIEW_DARK, PREVIEW_BRIGHT = Color(22, 24, 28), Color(198, 205, 212)
local function buildPreviewColumn(parent, K, T, refresh)
    local function button(p, label, onClick)
        local b = vgui.Create("DButton", p)
        b:SetText("")
        b.label = label
        b.Paint = function(self, w, h)
            draw.RoundedBox(4, 0, 0, w, h, T.card)
            if self:IsHovered() then
                surface.SetDrawColor(T.main.r, T.main.g, T.main.b, 255)
                surface.DrawRect(0, 0, 2, h)
            end
            K.Text(self.label, 13, 500, w / 2, h / 2, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        b.DoClick = onClick
        return b
    end
    local function flash(b, text, back, seconds)
        b.label = text
        b.flashAt = RealTime()
        local at = b.flashAt
        timer.Simple(seconds, function() if IsValid(b) and b.flashAt == at then b.label = back end end)
    end
    local function later() timer.Simple(0.2, function() if refresh then refresh() end end) end

    local view = vgui.Create("DPanel", parent)
    view.zcxRole = "preview"
    view:Dock(TOP)
    view:DockMargin(0, 0, 0, 8)
    view:SetTall(300)
    view.Paint = function(_, w, h)
        local sh = math.floor((h - 30) / 2)
        draw.RoundedBox(6, 0, 0, w, sh, PREVIEW_DARK)
        draw.RoundedBox(6, 0, sh + 8, w, sh, PREVIEW_BRIGHT)
        local now = RealTime()
        local fit = math.min(w, sh) / 2 - 4
        local label = drawPreview(w / 2, sh / 2, now, fit)
        drawPreview(w / 2, sh + 8 + sh / 2, now, fit)
        K.Text("Preview: " .. label, 12, 500, 0, h - 10, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local bar = vgui.Create("DPanel", parent)
    bar:Dock(TOP)
    bar:DockMargin(0, 0, 0, 6)
    bar:SetTall(32)
    bar.Paint = function() end
    local resetB = button(bar, "Reset to defaults", function(self)
        if (self.armedUntil or 0) > RealTime() then
            self.armedUntil = 0
            resetAll()
            flash(self, "Reset done", "Reset to defaults", 2)
            later()
        else
            self.armedUntil = RealTime() + 3
            flash(self, "Click again to reset", "Reset to defaults", 3)
        end
    end)
    resetB.zcxRole = "reset"
    local copyB = button(bar, "Copy code", function(self)
        SetClipboardText(exportCode())
        flash(self, "Copied to clipboard", "Copy code", 2)
    end)
    copyB.zcxRole = "copy"
    bar.PerformLayout = function(_, w, h)
        local bw = math.floor((w - 8) / 2)
        resetB:SetPos(0, 0)
        resetB:SetSize(bw, h)
        copyB:SetPos(w - bw, 0)
        copyB:SetSize(bw, h)
    end

    local row = vgui.Create("DPanel", parent)
    row:Dock(TOP)
    row:DockMargin(0, 0, 0, 10)
    row:SetTall(32)
    row.Paint = function() end
    local entry = vgui.Create("DTextEntry", row)
    entry.zcxRole = "entry"
    entry:SetFont(K.Font(13, 500))
    entry:SetPlaceholderText("Paste a crosshair code")
    local applyB = button(row, "Apply code", function(self)
        local ok, msg = importCode(entry:GetValue())
        flash(self, ok and "Applied" or "Not a code", "Apply code", 2)
        if ok then
            entry:SetValue("")
            later()
        else
            entry:SetTooltip(msg)
        end
    end)
    applyB.zcxRole = "apply"
    row.PerformLayout = function(_, w, h)
        local bw = math.min(120, math.floor(w * 0.34))
        entry:SetPos(0, 0)
        entry:SetSize(w - bw - 8, h)
        applyB:SetPos(w - bw, 0)
        applyB:SetSize(bw, h)
    end
end

-- The Crosshair page in GoobOS Settings (its own entry beside Preferences):
-- the details in a scrolling column, the preview in a column beside them,
-- stacked above them when the window is too narrow for two. api comes from
-- GoobOS: K, T, row(parent, category, convar) builds a GoobOS setting row,
-- matches(text, query), query, refresh().
local function buildCrosshairPage(list, api)
    local K, T = api.K, api.T
    local query = api.query or ""
    local page = vgui.Create("DPanel", list)
    page.zcxRole = "page"
    page:Dock(TOP)
    page.Paint = function() end
    page.Think = function(self)
        local want = math.max(420, IsValid(list) and list:GetTall() or 420)
        if self:GetTall() ~= want then self:SetTall(want) end
    end
    local left = vgui.Create("DPanel", page)
    left.Paint = function() end
    local scroll = (ZCGoobApps and ZCGoobApps.Scroll) and ZCGoobApps.Scroll(left) or vgui.Create("DScrollPanel", left)
    scroll:Dock(FILL)
    scroll.zcxRole = "details"
    local right = vgui.Create("DPanel", page)
    right.Paint = function() end
    right.zcxRole = "previewColumn"
    page.PerformLayout = function(_, w, h)
        if w < 560 then
            right:SetPos(0, 0)
            right:SetSize(w, 386)
            left:SetPos(0, 394)
            left:SetSize(w, math.max(1, h - 394))
        else
            local rw = math.Clamp(math.floor(w * 0.42), 260, 340)
            left:SetPos(0, 0)
            left:SetSize(w - rw - 16, h)
            right:SetPos(w - rw, 0)
            right:SetSize(rw, h)
        end
    end

    local shown = 0
    for _, group in ipairs(SETTINGS) do
        local heading = false
        for _, item in ipairs(group[2]) do
            local text = group[1] .. " " .. item[2] .. " " .. item[1]
            if query == "" or not api.matches or api.matches(text, query) then
                if not heading then
                    local h = vgui.Create("DPanel", scroll)
                    h:Dock(TOP)
                    h:SetTall(24)
                    h:DockMargin(0, shown == 0 and 0 or 10, 6, 2)
                    local label = string.upper(group[1])
                    h.Paint = function(_, w, hh) K.Text(label, 12, 600, 0, hh / 2, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
                    heading = true
                end
                if api.row(scroll, group[1], item[1]) then shown = shown + 1 end
            end
        end
    end
    if shown == 0 then
        local none = vgui.Create("DPanel", scroll)
        none:Dock(TOP)
        none:SetTall(30)
        none.Paint = function(_, w, h) K.Text("No crosshair settings match that search.", 13, 500, 0, h / 2, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
    end
    buildPreviewColumn(right, K, T, api.refresh)
end

-- GoobOS builds from before settings pages list the rows in Preferences; there
-- the preview column sits under the CROSSHAIR heading (hg.settings.extras).
local function buildSettingsFallback(list, K, T)
    buildPreviewColumn(list, K, T, function()
        if IsValid(list) and list.RefreshSettings then list:RefreshSettings() end
    end)
end

local CROSSHAIR_PAGE = {
    order = 10,
    title = "Crosshair",
    short = "Crosshair",
    subtitle = "Changes show live in the preview",
    categories = { "Crosshair", "Crosshair colour", "Crosshair feedback", "Crosshair shape" },
    wide = true,
    build = buildCrosshairPage,
}

local function registerSettings()
    if not (hg and istable(hg.settings) and hg.settings.AddOpt) then return false end
    local S = hg.settings
    -- the rows live on their own Settings page (GoobOS hg.settings.pages). A
    -- page's categories never reach Preferences, so the fallback below only
    -- draws on GoobOS builds from before pages.
    S.pages = S.pages or {}
    S.pages.Crosshair = CROSSHAIR_PAGE
    S.extras = S.extras or {}
    S.extras.Crosshair = buildSettingsFallback
    local goob = ZCGoobApps ~= nil
    for _, group in ipairs(SETTINGS) do
        -- these categories are ours alone: rebuild so a reload never leaves stale rows
        S.tbl[group[1]] = nil
        for i, row in ipairs(group[2]) do
            local choice = goob and row.choice or nil
            S:AddOpt(group[1], row[1], row[2], false, false, choice and "choice" or nil)
            local meta = S.tbl[group[1]][row[1]]
            meta[8] = i
            if choice then meta[7] = choice end
        end
    end
    return true
end
-- One-time reset of every crosshair setting to its default (owner request
-- 2026-09-25, after test values like zc_crosshair_a 1 left rings invisible).
-- The marker is a data file, not a convar, so it never shows in the console.
-- Bump RESET_REV to reset everyone again.
local RESET_REV = "20260925"
local RESET_FILE = "zc_crosshair_reset.txt"
if file.Read(RESET_FILE, "DATA") ~= RESET_REV then
    for _, cv in pairs(CV) do
        RunConsoleCommand(cv:GetName(), cv:GetDefault())
    end
    file.Write(RESET_FILE, RESET_REV)
end

-- Default refresh (owner, 2026-09-25): new defaults reach players who never
-- changed those settings; anyone who changed one keeps their value. Garry's
-- Mod saves untouched settings too, so "untouched" can only mean "still equal
-- to the old default". Runs once per player; bump DEFAULTS_REV for the next one.
-- The file holds the last step applied; each step runs once, so a value a
-- player picks after a step is never moved again.
local DEFAULTS_REV = 3
local DEFAULTS_FILE = "zc_crosshair_defaults.txt"
local defaultsDone = tonumber(file.Read(DEFAULTS_FILE, "DATA") or "") or 1
if defaultsDone < DEFAULTS_REV then
    local function at(cv, v) return tonumber(cv:GetString()) == v end
    if defaultsDone < 2 then
        -- ring size 4 (20 px at rest) -> 3 (17 px)
        if at(CV.Size, 4) then RunConsoleCommand("zc_crosshair_size", "3") end
        -- Custom with untouched white sliders -> the White preset (identical look).
        -- Anyone who mixed their own colour keeps Custom.
        if at(CV.Preset, 0) and at(CV.R, 255) and at(CV.G, 255) and at(CV.B, 255) then
            RunConsoleCommand("zc_crosshair_color", "1")
        end
    end
    -- wider gaps between the quadrants: notch width 16 -> 24 degrees
    if defaultsDone < 3 and at(CV.NotchWidth, 16) then
        RunConsoleCommand("zc_crosshair_notch_width", "24")
    end
    file.Write(DEFAULTS_FILE, tostring(DEFAULTS_REV))
end

-- hg.settings comes from ZCity's initpost menu code, whose load time relative
-- to this file varies (join vs mid-session refresh). Try now, then at
-- InitPostEntity, then once a second for 30 s. AddOpt overwrites, so repeats
-- are harmless; GoobOS reads the list each time Settings opens.
local function registerWhenReady()
    if registerSettings() then return end
    timer.Create("ZC_Crosshair.Settings", 1, 30, function()
        if registerSettings() then timer.Remove("ZC_Crosshair.Settings") end
    end)
end
registerWhenReady()
hook.Add("InitPostEntity", "ZC_Crosshair.Settings", registerWhenReady)

-- Console twins of the Settings buttons.
concommand.Add("zc_crosshair_reset", function()
    resetAll()
    print("[zc_crosshair] every crosshair setting is back to its default")
end)

concommand.Add("zc_crosshair_export", function()
    local code = exportCode()
    SetClipboardText(code)
    print("[zc_crosshair] copied to your clipboard: " .. code)
end)

concommand.Add("zc_crosshair_import", function(_, _, args, argStr)
    local _, msg = importCode(argStr or table.concat(args or {}, ""))
    print("[zc_crosshair] " .. msg)
end)

concommand.Add("zc_crosshair_version", function()
    print("[zc_crosshair] client " .. ZC_CROSSHAIR_VERSION)
end)
