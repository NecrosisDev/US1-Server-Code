-- ============================================================
--  ZC MIC BOX v3 - CLIENT half (renderer)
-- ------------------------------------------------------------
--  Draws the operator speaking box from the SERVER-sent speaking
--  list (sv_zc_micbox.lua) - so staff see everyone talking,
--  map-wide, whether or not their own client can hear them.
--  Speakers do NOT need this addon or anything enabled; it is
--  purely a viewer.
--
--  Gate is server-authoritative: non-staff never receive the
--  data. The allowed() check here is just UI politeness.
--
--  Green flash: names light up with the speaker's REAL voice
--  volume when you can hear them; speakers out of earshot pulse
--  gently and show a dim "far" tag so you can go find them.
--
--  Toggle: zc_micbox  (or bind a key). Client file = restart cargo.
-- ============================================================
if not CLIENT then return end

local enabledCV = CreateClientConVar("zc_micbox_enabled", "0", true, false,
	"Show the operator speaking-players box", 0, 1)

-- ---- who may use it (operator+; ULib inheritance, falls back to admin) ----
local function allowed()
	local p = LocalPlayer()
	if not IsValid(p) then return false end
	if p:IsAdmin() then return true end
	if p.CheckGroup and p:CheckGroup("operator") then return true end
	return false
end

-- ---- server-sent speaking list ----
local serverSpeak = {}   -- userid -> { start = CurTime start, last = RealTime received }

net.Receive("zc_micbox_state", function()
	local n = net.ReadUInt(7)
	local now = RealTime()
	local seen = {}
	for i = 1, n do
		local uid = net.ReadUInt(32)
		local start = net.ReadFloat()
		seen[uid] = true
		local d = serverSpeak[uid] or {}
		d.start = start
		d.last = now
		serverSpeak[uid] = d
	end
	for uid in pairs(serverSpeak) do
		if not seen[uid] then serverSpeak[uid] = nil end
	end
end)

-- Read-only adapter: the original receiver and server authorization stay owned here.
hg = hg or {}
function hg.GetMicBoxSpeakers()
    local result = {}
    if not allowed() or not enabledCV:GetBool() then return result end
    local now = RealTime()
    for uid, data in pairs(serverSpeak) do
        local ply = Player(uid)
        if now - (data.last or 0) <= 5 and IsValid(ply) then result[ply] = true end
    end
    return result
end

-- ---- toggle command ----
concommand.Add("zc_micbox", function(_, _, args)
	if not allowed() then
		chat.AddText(Color(226, 96, 96), "[Mic Box] Operators and above only.")
		return
	end
	local to
	if args[1] == "1" or args[1] == "on" then to = 1
	elseif args[1] == "0" or args[1] == "off" then to = 0
	else to = enabledCV:GetBool() and 0 or 1 end
	RunConsoleCommand("zc_micbox_enabled", tostring(to))
	chat.AddText(Color(120, 165, 255), "[Mic Box] ", Color(214, 220, 232),
		"speaking box " .. (to == 1 and "ON" or "OFF") ..
		"  (type ", Color(255, 255, 255), "zc_micbox", Color(214, 220, 232), " to toggle)")
end, nil, "Staff: toggle the map-wide speaking box: zc_micbox [on|off].")

-- ---- colours ----
local col_bg     = Color(20, 26, 22, 235)
local col_row    = Color(28, 46, 32, 240)
local col_head   = Color(30, 40, 34, 245)
local col_green  = Color(90, 210, 130)
local col_greenD = Color(60, 150, 95)
local col_text   = Color(224, 240, 228)
local col_dim    = Color(150, 175, 158)
local col_flash  = Color(110, 255, 150)   -- name colour at full voice volume
local nameColor  = Color(255, 255, 255)   -- written per row (text blended toward green by level), used at once

surface.CreateFont("ZCMicBox", { font = "Roboto", size = 17, weight = 600, extended = true })
surface.CreateFont("ZCMicBoxHead", { font = "Roboto", size = 14, weight = 700, extended = true })
surface.CreateFont("ZCMicBoxFar", { font = "Roboto", size = 12, weight = 600, extended = true })

-- ---- per-player smoothed voice level (vanilla-style green flash) ----
-- Real VoiceVolume() when you can hear them; jittery, so rise fast / fall slower.
local volS = {}
local function voiceLevel(uid, ply, dt, t)
	local audible = IsValid(ply) and ply.IsSpeaking and ply:IsSpeaking()
	local raw
	if audible then
		raw = math.Clamp(ply:VoiceVolume() * 1.4, 0, 1)
	else
		-- out of earshot: gentle pulse so the row still visibly "talks"
		raw = 0.35 + 0.25 * math.sin(t * 5 + uid)
	end
	local s = volS[uid] or 0
	local rate = (raw > s) and 16 or 6
	s = s + (raw - s) * math.Clamp(dt * rate, 0, 1)
	volS[uid] = s
	return s, audible
end

-- little mic glyph drawn from primitives (no external material)
local function drawMic(x, y, pulse)
	local g = Color(col_green.r, col_green.g, col_green.b, 160 + math.floor(95 * pulse))
	draw.RoundedBox(4, x, y, 8, 12, g)           -- capsule
	surface.SetDrawColor(g)
	surface.DrawRect(x + 3, y + 12, 2, 4)        -- stem
	surface.DrawRect(x, y + 16, 8, 2)            -- base
end

-- Pre-restyle drawing, verbatim from the live A+B file; used when the GoobOS kit is not loaded.
local legacyDraw = function()
	if not enabledCV:GetBool() or not allowed() then return end
	if ZCGoobApps and ZCGoobApps.Voice and ZCGoobApps.Voice.Ready() then return end

	local rnow = RealTime()

	-- collect + safety-age entries (5s without a server keepalive = drop)
	local list = {}
	for uid, d in pairs(serverSpeak) do
		if (rnow - (d.last or 0)) > 5 then
			serverSpeak[uid] = nil
			volS[uid] = nil
		else
			list[#list + 1] = uid
		end
	end
	if #list == 0 then return end
	table.sort(list, function(a, b)
		return (serverSpeak[a].start or 0) < (serverSpeak[b].start or 0)
	end)

	local W, rowH, headH, pad = 260, 30, 22, 8
	local x = ScrW() - W - 24
	local y = math.floor(ScrH() * 0.20)
	local totalH = headH + #list * (rowH + 4) + pad

	draw.RoundedBox(6, x, y, W, totalH, col_bg)
	draw.RoundedBoxEx(6, x, y, W, headH, col_head, true, true, false, false)
	draw.SimpleText("SPEAKING  (" .. #list .. ")", "ZCMicBoxHead", x + 10, y + headH / 2, col_dim, 0, 1)
	draw.SimpleText("op view", "ZCMicBoxHead", x + W - 10, y + headH / 2, col_greenD, 2, 1)

	local ry = y + headH + 4
	local t = CurTime()
	local ft = FrameTime()
	for _, uid in ipairs(list) do
		local d = serverSpeak[uid]
		local ply = Player(uid)
		local name = IsValid(ply) and ply:Nick() or ("#" .. uid)

		draw.RoundedBox(4, x + 6, ry, W - 12, rowH, col_row)

		-- real voice level when audible, soft pulse when out of earshot
		local vol, audible = voiceLevel(uid, ply, ft, rnow)
		drawMic(x + 14, ry + (rowH - 18) / 2, vol)
		draw.SimpleText(name, "ZCMicBox", x + 32, ry + rowH / 2,
			col_text:Lerp(col_flash, vol), 0, 1)

		-- thin VU strip along the bottom of the row
		surface.SetDrawColor(col_green.r, col_green.g, col_green.b, 60 + math.floor(160 * vol))
		surface.DrawRect(x + 8, ry + rowH - 3, math.floor((W - 16) * vol), 2)

		-- seconds talking, right-aligned; "far" tag when you can't hear them
		local secs = math.max(0, math.floor(t - (d.start or t)))
		draw.SimpleText(secs .. "s", "ZCMicBox", x + W - 16, ry + rowH / 2, col_dim, 2, 1)
		if not audible then
			draw.SimpleText("far", "ZCMicBoxFar", x + W - 48, ry + rowH / 2, col_greenD, 2, 1)
		end

		ry = ry + rowH + 4
	end
end

hook.Add("HUDPaint", "zc_micbox_draw", function()
	local K = ZCGoobApps and ZCGoobApps.Kit
	local T = ZCGoobApps and ZCGoobApps.Theme
	if not (K and K.HudPlate and T) then return legacyDraw() end
	if not enabledCV:GetBool() or not allowed() then return end
	if ZCGoobApps and ZCGoobApps.Voice and ZCGoobApps.Voice.Ready() then return end

	local rnow = RealTime()

	-- collect + safety-age entries (5s without a server keepalive = drop)
	local list = {}
	for uid, d in pairs(serverSpeak) do
		if (rnow - (d.last or 0)) > 5 then
			serverSpeak[uid] = nil
			volS[uid] = nil
		else
			list[#list + 1] = uid
		end
	end
	if #list == 0 then return end
	table.sort(list, function(a, b)
		return (serverSpeak[a].start or 0) < (serverSpeak[b].start or 0)
	end)

	-- 2026-09-25 HUD pass: GoobOS plate, fonts and tokens (glass, edge, text, muted, green).
	local s = K.HudScale()
	local W, rowH, headH, pad = math.floor(260 * s), math.floor(28 * s), math.floor(24 * s), math.floor(8 * s)
	local x = ScrW() - W - math.floor(24 * s)
	local y = math.floor(ScrH() * 0.20)
	local totalH = headH + #list * rowH + pad
	local nameFont, smallFont, headFont = K.HudFont(15, 600), K.HudFont(12, 600), K.HudFont(12, 700)

	K.HudPlate(x, y, W, totalH)
	draw.SimpleText("VOICE  " .. #list, headFont, x + pad + 2, y + math.floor(headH / 2), T.muted, 0, 1)

	local ry = y + headH
	local t = CurTime()
	local ft = FrameTime()
	for _, uid in ipairs(list) do
		local d = serverSpeak[uid]
		local ply = Player(uid)
		local name = IsValid(ply) and ply:Nick() or ("#" .. uid)

		-- real voice level when audible, soft pulse when out of earshot
		local vol, audible = voiceLevel(uid, ply, ft, rnow)
		local cy = ry + math.floor(rowH / 2)
		draw.RoundedBox(4, x + pad + 2, cy - 4, 8, 8, K.Alpha(T.green, 110 + math.floor(145 * vol)))
		nameColor.r = T.text.r + (T.green.r - T.text.r) * vol
		nameColor.g = T.text.g + (T.green.g - T.text.g) * vol
		nameColor.b = T.text.b + (T.green.b - T.text.b) * vol
		draw.SimpleText(name, nameFont, x + pad + 18, cy, nameColor, 0, 1)

		-- thin level strip along the bottom of the row
		surface.SetDrawColor(T.green.r, T.green.g, T.green.b, 60 + math.floor(160 * vol))
		surface.DrawRect(x + pad, ry + rowH - 3, math.floor((W - pad * 2) * vol), 2)

		-- seconds talking, right-aligned; "far" when you can't hear them
		local secs = math.max(0, math.floor(t - (d.start or t)))
		draw.SimpleText(secs .. "s", smallFont, x + W - pad - 2, cy, T.muted, 2, 1)
		if not audible then
			draw.SimpleText("far", smallFont, x + W - pad - math.floor(36 * s), cy, T.muted, 2, 1)
		end

		ry = ry + rowH
	end
end)

print("[ZC Mic Box] v3 loaded - operators: type  zc_micbox  to toggle (server-fed, map-wide)")
