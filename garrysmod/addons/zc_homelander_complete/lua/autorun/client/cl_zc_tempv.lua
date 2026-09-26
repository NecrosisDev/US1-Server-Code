-- ============================================================
--  ZC TEMP V - client: vial markers + personal V status chip
-- ------------------------------------------------------------
--  BIG vial indicators (per Joey: "so people can rush for them"):
--  every unclaimed vial gets a through-wall blue halo glow PLUS a
--  pulsing on-screen "V" marker with distance, drawn for everyone
--  EXCEPT the Homelander (team 0 - he has x-ray, this is theirs).
--  Also draws the injector's own gold TEMP V countdown chip (with
--  HEAT VISION tag on a laser roll). Restart cargo.
-- ============================================================
if not CLIENT then return end

surface.CreateFont("TempV_Marker", {
	font = "Bahnschrift",
	size = 22,
	weight = 900,
	antialias = true,
})
surface.CreateFont("TempV_Small", {
	font = "Bahnschrift",
	size = 14,
	weight = 800,
	antialias = true,
})

local V_BLUE = Color(80, 140, 255)
local V_GOLD = Color(255, 200, 60)

-- vial cache (0.5s refresh - a handful of props, cheap)
local vials, nextScan = {}, 0
local function scanVials()
	if CurTime() < nextScan then return end
	nextScan = CurTime() + 0.5
	vials = {}
	for _, e in ipairs(ents.FindByClass("prop_physics")) do
		if IsValid(e) and e:GetNWBool("zc_vial") then vials[#vials + 1] = e end
	end
end

local function canSeeMarkers()
	local lply = LocalPlayer()
	return IsValid(lply) and lply:Team() ~= 0 -- Homelander gets no free intel
end

-- through-wall glow
hook.Add("PreDrawHalos", "zc_tempv_halos", function()
	scanVials()
	if #vials == 0 or not canSeeMarkers() then return end
	halo.Add(vials, V_BLUE, 3, 3, 2, true, true) -- ignoreZ = glows through walls
end)

-- screen markers
hook.Add("HUDPaint", "zc_tempv_markers", function()
	if #vials == 0 or not canSeeMarkers() then return end
	local lply = LocalPlayer()
	local eye = lply:EyePos()
	local pulse = 0.72 + 0.28 * math.abs(math.sin(CurTime() * 3))

	for _, v in ipairs(vials) do
		if IsValid(v) then
			local pos = v:GetPos() + Vector(0, 0, 26)
			local scr = pos:ToScreen()
			if scr.visible then
				local a = 255 * pulse
				local dist = math.Round(eye:Distance(v:GetPos()) / 40) -- rough meters
				draw.SimpleText("V", "TempV_Marker", scr.x + 1, scr.y + 1, Color(0, 0, 0, a * 0.8), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
				draw.SimpleText("V", "TempV_Marker", scr.x, scr.y, Color(V_BLUE.r, V_BLUE.g, V_BLUE.b, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
				draw.SimpleText("TEMP V - " .. dist .. "m", "TempV_Small", scr.x, scr.y + 2, Color(200, 220, 255, a * 0.9), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
			end
		end
	end
end)

-- ---- v1.1 HEAT VISION BEAM - the real thing ----
-- Drawn clientside for EVERYONE from networked key state, using the
-- actual Homelander SWEP laser materials (mounted content), twin
-- beams from the eyes converging on the hit point + a hot core glow.
local matCore = Material("homelander/laser_core")
local matGlow = Material("homelander/laser_glow")
if matCore:IsError() then matCore = Material("sprites/laserbeam") end
if matGlow:IsError() then matGlow = Material("sprites/light_glow02_add") end
local COL_BEAM = Color(255, 40, 25, 255)
local COL_GLOW = Color(255, 120, 60, 200)

hook.Add("PostDrawTranslucentRenderables", "zc_tempv_beam", function(depth, sky)
	if sky then return end
	for _, ply in player.Iterator() do
		if IsValid(ply) and ply:Alive() and ply:KeyDown(IN_ATTACK2) then
			local wep = ply:GetActiveWeapon()
			if IsValid(wep) and wep:GetClass() == "weapon_tempv_laser" then
				local eye = ply:EyePos()
				local aim = ply:GetAimVector()
				local tr = util.TraceLine({ start = eye, endpos = eye + aim * 4096, filter = ply, mask = MASK_SHOT })
				local hit = tr.HitPos
				local right = aim:Angle():Right()
				local jitter = 0.6 + 0.5 * math.abs(math.sin(CurTime() * 40))
				local isLocal = ply == LocalPlayer() and GetViewEntity() == LocalPlayer()
				-- twin eye beams converging on the hit point (from your own
				-- view they start just ahead so they don't clip the camera)
				for side = -1, 1, 2 do
					local from = eye + right * (side * 1.6) - Vector(0, 0, 0.5)
					if isLocal then from = eye + aim * 14 + right * (side * 2.2) - Vector(0, 0, 1.6) end
					render.SetMaterial(matCore)
					render.DrawBeam(from, hit, 2.5 * jitter, 0, 1, COL_BEAM)
					render.SetMaterial(matGlow)
					render.DrawBeam(from, hit, 7 * jitter, 0, 1, COL_GLOW)
				end
				render.SetMaterial(matGlow)
				render.DrawSprite(hit, 26 * jitter, 26 * jitter, COL_BEAM)
				render.DrawSprite(hit, 48 * jitter, 48 * jitter, Color(255, 90, 40, 90))
			end
		end
	end
end)

-- personal V status chip (sits just above the HnS status panel)
local vUntil, vLaser = 0, false
net.Receive("zc_tempv_state", function()
	vUntil = net.ReadFloat()
	vLaser = net.ReadBool()
end)

surface.CreateFont("TempV_Chip", {
	font = "Bahnschrift",
	size = 20,
	weight = 800,
	antialias = true,
})

hook.Add("HUDPaint", "zc_tempv_chip", function()
	local left = vUntil - CurTime()
	if left <= 0 then return end
	local sw, sh = ScrW(), ScrH()
	local label = "TEMP V  " .. string.FormattedTime(left, "%02i:%02i") .. (vLaser and "  ·  HEAT VISION" or "")
	surface.SetFont("TempV_Chip")
	local tw = surface.GetTextSize(label)
	local w = tw + 34
	local x, y = (sw - w) / 2, sh * 0.895 - 168
	draw.RoundedBox(6, x, y, w, 32, Color(12, 12, 14, 190))
	draw.RoundedBox(6, x, y + 28, w, 4, Color(V_GOLD.r, V_GOLD.g, V_GOLD.b, 220))
	draw.SimpleText(label, "TempV_Chip", x + w / 2, y + 15,
		vLaser and Color(255, 120, 70) or V_GOLD, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)

-- v1.3.3 CLIENT-SIDE ORPHAN SOUND GUARD: the laser wav loops, and a
-- loop the client started (the SWEP's cl beam sound) can outlive its
-- source in ways server StopSound can't always reach. Every 0.5s,
-- any player NOT visibly beaming gets the sound stopped locally.
timer.Create("zc_tempv_sndguard", 0.5, 0, function()
	for _, p in player.Iterator() do
		if IsValid(p) then
			local w = p:GetActiveWeapon()
			local firing = p:Alive() and p:KeyDown(IN_ATTACK2) and IsValid(w)
				and (w:GetClass() == "weapon_tempv_laser" or w:GetClass() == "weapon_homelander")
			if not firing then
				p:StopSound("homelander/laser.wav")
			end
		end
	end
end)

print("[Temp V] client markers + chip loaded")
