-- ============================================================
--  ZC HOMELANDER PIN - client: persistent HnS status panel (v2.0)
-- ------------------------------------------------------------
--  Jugg-panel-style bottom-center HUD for Homelander: Hide & Seek,
--  drawn for EVERYONE all round:
--    row 1  HOMELANDER | "WAKES IN 0:27" (freeze) -> "12 HIDERS" (hunt)
--    row 2  the hunt clock - survive-until bar draining toward the
--           "Homelander grows bored" hiders win, time text on it
--    row 3  the PIN meter - dim "AT LARGE" track normally; when he's
--           nailed/taped down it fills GOLD toward the execution
--           ("RESTRAINED - HOLD HIM!")
--  Fed by the sv half's zc_hl_status broadcast (4x/s). The ONLY
--  show/hide gate is packet freshness (<2s) - no zb round-type
--  reads (they go stale across mode families; the jugg splash
--  lesson). Panel fades ~2s after the round ends.
--  Client file = RESTART CARGO.
-- ============================================================
if not CLIENT then return end

surface.CreateFont("HLP_Meter", {
	font = "Bahnschrift",
	size = 22, -- v2.2: whole panel scaled x1.5 per Joey
	weight = 800,
	antialias = true,
})

local freezeLeft, timeLeft, roundTime, hiders = 0, 0, 330, 0
local pinFrac, restrained = 0, false
local vitFrac, burned, vialsLeft = 2, false, 0 -- vitFrac 2 = no Temp V system
local rxAt = 0
local show = 0

net.Receive("zc_hl_status", function()
	freezeLeft = net.ReadUInt(6)
	timeLeft = net.ReadUInt(10)
	roundTime = math.max(1, net.ReadUInt(10))
	hiders = net.ReadUInt(6)
	pinFrac = net.ReadFloat()
	restrained = net.ReadBool()
	-- v2.1 extension (a v2.0 server's packet simply ends here)
	if net.BytesLeft() > 0 then
		vitFrac = net.ReadFloat()
		burned = net.ReadBool()
		vialsLeft = net.ReadUInt(4)
	else
		vitFrac, burned, vialsLeft = 2, false, 0
	end
	rxAt = CurTime()
end)

local col_bg    = Color(12, 12, 14, 200)
local col_track = Color(255, 255, 255, 18)
local col_lab   = Color(220, 224, 230)
local col_hl    = Color(228, 49, 49)   -- the mode's own Homelander red
local col_hider = Color(0, 162, 255)   -- the mode's own civilian blue
local col_pin   = Color(255, 200, 60)  -- restraint gold

hook.Add("HUDPaint", "zc_hlpin_panel", function()
	local fresh = (CurTime() - rxAt) < 2
	show = Lerp(FrameTime() * 6, show, fresh and 1 or 0)
	if show < 0.02 then return end

	local sw, sh = ScrW(), ScrH()
	local w = 390 -- v2.2: x1.5 scale
	local x, y = (sw - w) / 2, sh * 0.895 -- y = pin bar top (jugg anchor)
	local a = 255 * show

	-- v2.1: with the Temp V system live the panel grows a vitality row
	local hasVit = vitFrac <= 1.5
	local top = hasVit and (y - 120) or (y - 93)
	draw.RoundedBox(8, x - 15, top, w + 30, (y + 30) - top, Color(col_bg.r, col_bg.g, col_bg.b, 200 * show))

	-- row 1: title + phase info
	local ty = hasVit and (y - 105) or (y - 78)
	draw.SimpleText("HOMELANDER", "HLP_Meter", x, ty, Color(col_hl.r, col_hl.g, col_hl.b, a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	if freezeLeft > 0 then
		-- arrival phase: pulsing countdown
		local pulse = 0.7 + 0.3 * math.abs(math.sin(CurTime() * 4))
		draw.SimpleText("WAKES IN " .. string.FormattedTime(freezeLeft, "%02i:%02i"), "HLP_Meter",
			x + w, ty, Color(col_hl.r, col_hl.g, col_hl.b, a * pulse), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	else
		draw.SimpleText(hiders .. (hiders == 1 and " HIDER" or " HIDERS"), "HLP_Meter",
			x + w, ty, Color(col_hider.r, col_hider.g, col_hider.b, a), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end

	-- v2.1 vitality row: his red bar - drained by Temp V attacks; at
	-- zero he's BURNED OUT (SWEP + crusher stripped, mortal)
	if hasVit then
		draw.RoundedBox(4, x, y - 81, w, 18, Color(col_track.r, col_track.g, col_track.b, 40 * show))
		if burned then
			local flash = 0.55 + 0.45 * math.abs(math.sin(CurTime() * 5))
			draw.SimpleText("BURNED OUT", "HLP_Meter", x + w / 2, y - 72,
				Color(255, 70, 50, a * flash), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		else
			if vitFrac > 0 then
				draw.RoundedBox(4, x, y - 81, math.max(6, w * vitFrac), 18, Color(col_hl.r, col_hl.g, col_hl.b, a * 0.9))
			end
			draw.SimpleText("VITALITY", "HLP_Meter", x + 6, y - 72,
				Color(255, 255, 255, a * 0.55), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			if vialsLeft > 0 then
				draw.SimpleText(vialsLeft .. " VIALS", "HLP_Meter", x + w - 6, y - 72,
					Color(255, 200, 60, a), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
			end
		end
	end

	-- row 2: hunt clock (drains toward the hiders' survival win)
	draw.RoundedBox(4, x, y - 51, w, 21, Color(col_track.r, col_track.g, col_track.b, 40 * show))
	local tfrac = math.Clamp(timeLeft / roundTime, 0, 1)
	if tfrac > 0 then
		draw.RoundedBox(4, x, y - 51, math.max(9, w * tfrac), 21, Color(col_hider.r, col_hider.g, col_hider.b, a * 0.85))
	end
	draw.SimpleText(string.FormattedTime(timeLeft, "%02i:%02i"), "HLP_Meter",
		x + w / 2, y - 40, Color(255, 255, 255, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

	-- row 3: pin meter
	local active = restrained or pinFrac > 0.01
	draw.SimpleText(active and "RESTRAINED - HOLD HIM!" or "AT LARGE", "HLP_Meter",
		x + w / 2, y - 15,
		active and Color(col_pin.r, col_pin.g, col_pin.b, a) or Color(col_lab.r, col_lab.g, col_lab.b, a * 0.45),
		TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.RoundedBox(4, x, y, w, 21, Color(col_track.r, col_track.g, col_track.b, 40 * show))
	if pinFrac > 0.005 then
		draw.RoundedBox(4, x, y, math.max(9, w * pinFrac), 21, Color(col_pin.r, col_pin.g, col_pin.b, a))
	end
end)

print("[HnS Pin] client status panel loaded")
