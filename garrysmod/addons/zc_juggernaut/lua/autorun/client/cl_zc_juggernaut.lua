-- ============================================================
--  ZC JUGGERNAUT - client: splash + status panel + shared injections
-- ------------------------------------------------------------
--  The stock homicide splash (cl_homicide.lua MODE:HUDPaint)
--  titles rounds "Homicide | <Type>" - but it SELF-SKIPS when
--  MODE.TypeObjectives has no entry for the type. We deliberately
--  never register TypeObjectives.juggernaut, so the stock splash
--  stays silent, and this file draws its own fear-style splash
--  (per Joey: title says just "Juggernaut").
--  Client file = restart cargo.
-- ============================================================
if not CLIENT then return end

surface.CreateFont("Jugg_Title", {
	font = "Bahnschrift",
	size = ScreenScale(46),
	weight = 900,
	antialias = true,
})

-- shared-table injections the client needs too (TypeNames/Roles)
local function injectCL()
	local hmcd = zb and zb.modes and zb.modes["hmcd"]
	if not hmcd then return false end
	hmcd.TypeNames = hmcd.TypeNames or {}
	hmcd.TypeNames.juggernaut = "Juggernaut"
	hmcd.Roles = hmcd.Roles or {}
	hmcd.Roles.juggernaut = {
		traitor  = { name = "Juggernaut", color = Color(255, 120, 0) },
		gunner   = { name = "Hunter",     color = Color(0, 120, 190) },
		innocent = { name = "Hunter",     color = Color(0, 120, 190) },
	}
	return true
end
timer.Create("zc_jugg_injectcl", 2, 30, function()
	if injectCL() then timer.Remove("zc_jugg_injectcl") end
end)

-- The splash is gated on the server's announce packet, NOT on
-- zb.modes["hmcd"].Type - that field goes STALE when the next round
-- is a different mode family (nothing resets it), which made the
-- splash draw over the following round's screen. The announce only
-- ever arrives at a juggernaut roundstart, so its timestamp is truth.
local juggName = nil
local annAt = 0
net.Receive("zc_jugg_announce", function()
	juggName = net.ReadString()
	annAt = CurTime()
	-- publish the jugg's identity for the indicators addon (round-stamped
	-- so it self-invalidates the moment the next round starts)
	local ent = net.ReadEntity()
	ZCJUGG_CL = { ent = ent, round = zb and zb.ROUND_START or 0 }
end)

local col_title   = Color(255, 120, 0)
local col_outline = Color(60, 20, 0)
local col_jugg    = Color(255, 120, 0)
local col_hunter  = Color(90, 170, 235)
local fade = 0

hook.Add("HUDPaint", "zc_jugg_splash", function()
	local MODE = zb and zb.modes and zb.modes["hmcd"]
	if not MODE or MODE.Type ~= "juggernaut" or annAt == 0 then
		if fade ~= 0 then fade = 0 end
		return
	end

	-- announce arrives ~0.6s after the juggernaut roundstart
	local StartTime = annAt - 0.6
	if StartTime + 12 < CurTime() then
		if fade ~= 0 then fade = 0 end
		return
	end

	local lply = LocalPlayer()
	if not IsValid(lply) or lply:Team() == TEAM_SPECTATOR then return end

	fade = Lerp(FrameTime() * 1, fade, math.Clamp(StartTime + 5 - CurTime(), -2, 2))
	if fade <= 0 then return end

	local sw, sh = ScrW(), ScrH()

	-- the title: just "Juggernaut" - orange, dark outline, fear-style
	local tx, ty = sw * 0.5, sh * 0.1
	local outline = Color(col_outline.r, col_outline.g, col_outline.b, 255 * fade)
	for ox = -2, 2, 2 do
		for oy = -2, 2, 2 do
			if ox ~= 0 or oy ~= 0 then
				draw.SimpleText("Juggernaut", "Jugg_Title", tx + ox, ty + oy, outline, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
		end
	end
	draw.SimpleText("Juggernaut", "Jugg_Title", tx, ty, Color(col_title.r, col_title.g, col_title.b, 255 * fade), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

	local isJugg = lply.isTraitor == true
	local roleCol = isJugg and col_jugg or col_hunter
	roleCol = Color(roleCol.r, roleCol.g, roleCol.b, 255 * fade)
	local white = Color(255, 255, 255, 255 * fade)

	local cur_y = sh * 0.5
	draw.SimpleText(isJugg and "You are THE JUGGERNAUT" or "You are a Hunter",
		"ZB_HomicideMediumLarge", sw * 0.5, cur_y, roleCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

	cur_y = cur_y + ScreenScale(20)
	draw.SimpleText(isJugg
			and "Heavy plates. Big gun. Kill them all."
			or "Bring down the Juggernaut. Aim for the gaps in the armor.",
		"ZB_HomicideMedium", sw * 0.5, cur_y, white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

	if not isJugg and juggName then
		cur_y = cur_y + ScreenScale(18)
		draw.SimpleText("The Juggernaut: " .. juggName, "ZB_HomicideMedium", sw * 0.5, cur_y,
			Color(255, 120, 0, 255 * fade), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end)

-- ---- JUGGERNAUT STATUS PANEL (v2.4) ----
-- The suppression meter grew into a PERSISTENT boss panel everyone
-- sees for the whole round: JUGGERNAUT HP bar (his superfighter
-- engine pool) + VEST/HELM/MASK armor chips + the suppression bar.
-- Fed by the zc_jugg_ow broadcast (every 0.25s while he lives).
-- Packet freshness is the ONLY show/hide gate - deliberately no
-- zb round-type reads (hmcd.Type goes stale across mode families,
-- the old splash bug) - so the panel appears with the round and
-- fades ~2s after the jugg dies or the round ends.
-- Mixed-version safe: a pre-v2.4 server sends only the two meter
-- fields -> we detect the short packet and fall back to meter-only.
surface.CreateFont("Jugg_Meter", {
	font = "Bahnschrift",
	size = 15,
	weight = 800,
	antialias = true,
})

local owFrac, owCD, owAt = 0, false, 0
local jHP, jMax = 0, 0
local slotOn = { false, false, false } -- torso, head, face
local slotHP = { 1, 1, 1 }
local SLOT_LABEL = { "VEST", "HELM", "MASK" }
local owShow = 0

net.Receive("zc_jugg_ow", function()
	owFrac = net.ReadFloat()
	owCD = net.ReadBool()
	owAt = CurTime()
	local hp = net.ReadUInt(13)
	local mhp = net.ReadUInt(13)
	if mhp and mhp > 0 then -- v2.4 extended packet
		jHP, jMax = hp, mhp
		for i = 1, 3 do
			slotOn[i] = net.ReadBool() or false
			slotHP[i] = slotOn[i] and (net.ReadUInt(5) / 31) or 0
		end
	else -- short packet (pre-v2.4 server): meter-only fallback
		jMax = 0
	end
end)

local col_bg2   = Color(12, 12, 14, 200)
local col_track = Color(255, 255, 255, 18)
local col_lab   = Color(220, 224, 230)

hook.Add("HUDPaint", "zc_jugg_meter", function()
	-- persistent: visible while the status packets flow (all round)
	local fresh = (CurTime() - owAt) < 2
	owShow = Lerp(FrameTime() * 6, owShow, fresh and 1 or 0)
	if owShow < 0.02 then return end

	local sw, sh = ScrW(), ScrH()
	local w = 260
	local x, y = (sw - w) / 2, sh * 0.895 -- y = suppression bar top (same spot as before)
	local a = 255 * owShow
	local full = jMax > 0

	-- backdrop spans the whole stack (or just the meter on fallback)
	local top = full and (y - 84) or (y - 20)
	draw.RoundedBox(6, x - 10, top, w + 20, (y + 20) - top, Color(col_bg2.r, col_bg2.g, col_bg2.b, 200 * owShow))

	if full then
		-- HP row: name + numbers + bar (orange at full -> red when low)
		local hpfrac = math.Clamp(jHP / jMax, 0, 1)
		draw.SimpleText("JUGGERNAUT", "Jugg_Meter", x, y - 74, Color(255, 120, 0, a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText(jHP .. " / " .. jMax, "Jugg_Meter", x + w, y - 74, Color(col_lab.r, col_lab.g, col_lab.b, a), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		draw.RoundedBox(3, x, y - 64, w, 12, Color(col_track.r, col_track.g, col_track.b, 40 * owShow))
		if hpfrac > 0 then
			local hr = Lerp(hpfrac, 200, 255)
			local hg = Lerp(hpfrac, 45, 120)
			local hb = Lerp(hpfrac, 35, 0)
			draw.RoundedBox(3, x, y - 64, math.max(6, w * hpfrac), 12, Color(hr, hg, hb, a))
		end

		-- armor chips: lit while worn, dark when the piece is gone;
		-- thin strip below the label = piece condition
		local chipW = (w - 8) / 3
		for i = 1, 3 do
			local cx = x + (i - 1) * (chipW + 4)
			local on = slotOn[i]
			draw.RoundedBox(4, cx, y - 46, chipW, 20, on and Color(255, 255, 255, 16 * owShow) or Color(0, 0, 0, 90 * owShow))
			draw.SimpleText(SLOT_LABEL[i], "Jugg_Meter", cx + chipW / 2, y - 38,
				on and Color(col_lab.r, col_lab.g, col_lab.b, a) or Color(150, 95, 95, a * 0.55), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			draw.RoundedBox(1, cx + 5, y - 30, chipW - 10, 3, Color(255, 255, 255, 12 * owShow))
			if on then
				local f = slotHP[i]
				local sc = f > 0.66 and Color(120, 200, 90, a) or (f > 0.33 and Color(235, 190, 60, a) or Color(220, 70, 50, a))
				draw.RoundedBox(1, cx + 5, y - 30, math.max(2, (chipW - 10) * f), 3, sc)
			end
		end
	end

	-- suppression row (original look, now always visible; label dims
	-- to 45% while the meter sits at zero so the panel stays calm)
	local active = owCD or owFrac > 0.01
	draw.SimpleText(owCD and "STAGGERED - RECOVERING" or "SUPPRESSION", "Jugg_Meter",
		x + w / 2, y - 10, Color(col_lab.r, col_lab.g, col_lab.b, active and a or a * 0.45), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.RoundedBox(3, x, y, w, 14, Color(col_track.r, col_track.g, col_track.b, 40 * owShow))
	local frac = owCD and 1 or owFrac
	if frac > 0.005 then
		local g = Lerp(frac, 190, 60)
		local fill = owCD and Color(120, 120, 130, a) or Color(255, g, 40, a)
		draw.RoundedBox(3, x, y, math.max(6, w * frac), 14, fill)
	end
end)

print("[Juggernaut] client splash loaded")
