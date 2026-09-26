local MODE = MODE

local function ShowShadows(ent, ply, bool)
	ply:DrawShadow(bool)
	ent:DrawShadow(bool)
end

function MODE:PreDrawPlayer2(ent, ply)
	local lply = LocalPlayer()

	if !IsValid(ent) or !IsValid(ply) then return end
	if lply == ply then return end

	if !lply:Alive() then
		ShowShadows(ent, ply, true)
		local wpn = ply.GetActiveWeapon and ply:GetActiveWeapon()
		if IsValid(wpn) then
			wpn:DrawShadow(true)
		end
		return
	end

	local bool = lply:GetNetVar("disappearance", nil) // it's not actually bool but float. works either way :3. update: it's a bool now >w<
	if bool then
		ShowShadows(ent, ply, false)
		local wpn = ply.GetActiveWeapon and ply:GetActiveWeapon()
		if IsValid(wpn) then
			wpn:DrawShadow(false)
		end
		return bool
	end

	local bool2 = ply:GetNetVar("disappearance", nil)
	if bool2 then
		ShowShadows(ent, ply, false)
		local wpn = ply.GetActiveWeapon and ply:GetActiveWeapon()
		if IsValid(wpn) then
			wpn:DrawShadow(false)
		end
		return bool2
	end
end

hg.ghostStation = hg.ghostStation or nil
local cc = Material( "effects/shaders/merc_chromaticaberration" )

local tab = {
	[ "$pp_colour_addr" ] = 0,
	[ "$pp_colour_addg" ] = 0,
	[ "$pp_colour_addb" ] = 0,
	[ "$pp_colour_brightness" ] = 0,
	[ "$pp_colour_contrast" ] = 1,
	[ "$pp_colour_colour" ] = 1,
	[ "$pp_colour_mulr" ] = 0,
	[ "$pp_colour_mulg" ] = 0,
	[ "$pp_colour_mulb" ] = 0
}

local alone = {
	"Where is everyone?",
	"Anyone here?",
	"Where did everyone go?",
	"Did i miss something?",
	"It's oddly quiet."
}

function MODE:CheckInDarkness(ply)
	return render.GetLightColor(ply:EyePos())
end

net.Receive("check_lightness", function(len)
	local ply = net.ReadEntity()
	
	if IsValid(ply) then
		net.Start("check_lightness")
		net.WriteVector(MODE:CheckInDarkness(ply))
		net.SendToServer()
	end
end)

local atpeace = {
	"I feel... At peace.",
	"Is this the end?",
	"What is happening?",
	"I think i've lived long enough.",
	"Finally, light at the end of a tunnel...",
	"I think that's it.",
	"Is this really how it ends?"
}

hg.fearphrase1 = hg.fearphrase1 or nil
hg.fearphrase2 = hg.fearphrase2 or nil

function MODE:RenderScreenspaceEffects()
	local lply = LocalPlayer()

	self.BaseClass.RenderScreenspaceEffects(self)

	local disappearance = lply:GetNetVar("disappearance", nil)

	if disappearance and !hg.fearphrase1 then
		timer.Simple(math.Rand(20, 40), function()
			hg.CreateNotification(table.Random(alone))
		end)
		hg.fearphrase1 = true
	end

	if !disappearance then
		hg.fearphrase1 = nil
	end

	local ghost = lply:GetNetVar("afterlife") // curtime start here
	if !ghost then
		if IsValid(hg.ghostStation) then
			hg.ghostStation:Stop()
			hg.ghostStation = nil
		end

		hg.fearphrase2 = nil
		return
	end
	
	local intensity = CurTime() - ghost

	local time = 60

	if intensity > time and !IsValid(hg.ghostStation) then
		sound.PlayFile("sound/zbattle/dragonfly_wings.ogg", "noplay", function(channel) //the track is 59 seconds btw
			channel:SetVolume(0)
			channel:Play()
			hg.ghostStation = channel
		end)
	end

	if intensity > time then
		local intensity2 = (intensity - time) / 100
		tab[ "$pp_colour_contrast" ] = 1 + intensity2
		tab[ "$pp_colour_addr" ] = intensity2 / 10
		tab[ "$pp_colour_brightness" ] = intensity2
		DrawColorModify(tab)
		DrawBloom( 0.65, intensity2 * 4, 9, 9, 1, 1, intensity2 / 16, 0.2, 0.2 )

		render.UpdateScreenEffectTexture()
			cc:SetFloat("$c0_x", intensity2 / 5)
			cc:SetInt("$c0_y", 1)
			render.SetMaterial(cc)
		render.DrawScreenQuad()
	end

	if IsValid(hg.ghostStation) then
		hg.ghostStation:SetVolume(math.min((intensity - time) / 50, 1))
	end

	if intensity > time + 30 and !hg.fearphrase2 then
		hg.CreateNotification(table.Random(atpeace))
		hg.fearphrase2 = true
	end
end

local ScarySounds = {
	--"npc/stalker/stalker_scream1.wav",
	--"npc/stalker/stalker_scream2.wav",
	--"npc/stalker/stalker_scream3.wav",
	--"npc/stalker/stalker_scream4.wav",
	--"npc/stalker/breathing3.wav",
	--"npc/crow/alert1.wav",
	--"npc/advisor/advisorscreenvx06.wav",
	--"npc/advisor/advisorscreenvx07.wav",
	--"npc/advisor/advisorscreenvx08.wav",
	--"cry1.wav",
	--"cry2.wav",
	"mumbling.wav",
	"blow.mp3",
	--"strangeround.wav",
	"knock.mp3",
	"ambient/atmosphere/hole_hit1.wav",
	"ambient/atmosphere/hole_hit2.wav",
	"ambient/atmosphere/hole_hit3.wav",
	"ambient/atmosphere/hole_hit4.wav",
	--"ambient/creatures/town_child_scream1.wav",
	"ambient/creatures/town_moan1.wav",
	"ambient/creatures/town_muffled_cry1.wav",
	"ambient/creatures/town_scared_breathing1.wav",
	"ambient/creatures/town_scared_breathing2.wav",
	"ambient/creatures/town_scared_sob1.wav",
	"ambient/creatures/town_scared_sob2.wav",
}

local notifs = {
	"Uh-oh...",
	"Oh no",
	"This isn't good",
	"Where's everyone?",
}

function MODE:Player_Death(ply)
	local lply = LocalPlayer()

	self:CreateTimer("fearfearingfearful", 3, 1, function()
		local players = zb:CheckAlive()

		if #players == 1 and players[1] == lply then
			self:CreateTimer("fearfearingfearful2", 0.1, 1, function()
				RunConsoleCommand("stopsound")
			end)

			self:CreateTimer("fear", 5, 1, function()
				--RunConsoleCommand("cl_soundscape_flush")
				hg.CreateNotification(table.Random(notifs))

				self:CreateTimer("fear2", 115, 1, function()
					hg.CreateNotification("bye")
				end)
			end)

			self:CreateTimer("fearfearingfearful3", 1, 1, function()
				sound.PlayFile("sound/crawlspace.mp3", "", function(channel)
					hg.lastOneStation = channel
				end)
			end)
		end
	end)
end

function MODE:RoundStart()
	self:CreateTimer("FearSounds", 1, 0, function()
		local lply = LocalPlayer()
		if !IsValid(lply) then return end
		local snd = table.Random(ScarySounds)

		if snd == "knock.mp3" then
			surface.PlaySound("knock.mp3")
			timer.Adjust("FearSounds", math.Rand(20, 60))

			return
		end

		local pos = lply:GetPos() + Vector(math.Rand(-512, 512), math.Rand(-512, 512), math.Rand(0, 512))
		
		EmitSound(snd, pos, 0, nil)
		timer.Adjust("FearSounds", math.Rand(40, 90))
	end)
end

function MODE:EndRound()
	for k, _ in pairs(self.saved.Timers or {}) do
		timer.Remove(k)
	end

	if IsValid(hg.lastOneStation) then
		hg.lastOneStation:Stop()
		hg.lastOneStation = nil
	end
end

function MODE:EntityEmitSound(data)
	local disappearance = lply:GetNetVar("disappearance", nil)
	if disappearance and IsValid(data.Entity) and (data.Entity:IsRagdoll() or data.Entity:IsPlayer() or ishgweapon(data.Entity) or data.Entity.ismelee) then
		return false
	end
end

--[[concommand.Add("status", function()
	for _, ply in ipairs( player.GetAll() ) do
		print( ply:Nick() .. ", " .. ply:SteamID() .. "\n" )
	end
end)--]]


-- =====================================================================
-- Round start splash: homicide-style (roles, traitor words, objectives)
-- with the title "Fear" in bright yellow. Self-contained and defensive:
-- resolves fear's remapped types (standard2/soe2) lazily, falls back to
-- basic role display if objectives can't resolve, and always releases
-- the round-transition fade so the screen never sticks black.
-- =====================================================================

surface.CreateFont("Fear_Title", {
	font = "Bahnschrift",
	size = ScreenScale(46),
	weight = 900,
	antialias = true,
})

local handicap = {
	[1] = "You are handicapped: your right leg is broken.",
	[2] = "You are handicapped: you are suffering from severe obesity.",
	[3] = "You are handicapped: you are suffering from hemophilia.",
	[4] = "You are handicapped: you are physically incapacitated."
}

local fade = 0

local function ResolveObjectives()
	if not MODE.TypeObjectives then return nil end
	local t = MODE.Type
	if t and MODE.TypeObjectives[t] then return MODE.TypeObjectives[t] end
	-- fear's remapped types fall back to their base entries
	if t == "fear" or t == "standard2" then return MODE.TypeObjectives.standard end
	if t == "fear_soe" or t == "soe2" then return MODE.TypeObjectives.soe end
	-- last resort: standard's entries fit fear's roles fine
	return MODE.TypeObjectives.standard
end

function MODE:HUDPaint()
	if not zb.ROUND_START then return end

	local StartTime = zb.ROUND_START
	if StartTime + 12 < CurTime() then return end

	local lply = LocalPlayer()
	if not IsValid(lply) or lply:Team() == TEAM_SPECTATOR then return end

	-- never leave the transition fade stuck
	zb.RemoveFade()

	-- black intro that fades out
	local fadetime = MODE.FadeScreenTime or 5
	local time_diff = StartTime + fadetime - CurTime()
	if time_diff > 0 then
		local blackfade = math.min(time_diff / fadetime, 1)
		surface.SetDrawColor(0, 0, 0, 255 * blackfade)
		surface.DrawRect(-1, -1, ScrW() + 1, ScrH() + 1)
	end

	fade = Lerp(FrameTime() * 1, fade, math.Clamp(StartTime + 5 - CurTime(), -2, 2))
	if fade <= 0 then return end

	local sw, sh = ScrW(), ScrH()

	-- big yellow FEAR with a red outline
	local tx, ty = sw * 0.5, sh * 0.1
	local outline = Color(180, 0, 0, 255 * fade)
	for ox = -2, 2, 2 do
		for oy = -2, 2, 2 do
			if ox != 0 or oy != 0 then
				draw.SimpleText("Fear", "Fear_Title", tx + ox, ty + oy, outline, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
		end
	end
	draw.SimpleText("Fear", "Fear_Title", tx, ty, Color(255, 230, 0, 255 * fade), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

	local obj = ResolveObjectives()

	-- role name/colors: from objectives when available, sane fallbacks when not
	local Rolename, ColorRole, ColorInno, Objective
	if obj then
		Rolename = ( lply.isTraitor and "Cultist" ) or ( lply.isGunner and obj.gunner.name ) or obj.innocent.name
		ColorRole = ( lply.isTraitor and obj.traitor.color1 ) or ( lply.isGunner and obj.gunner.color1 ) or obj.innocent.color1
		ColorInno = obj.innocent.color1
		Objective = ( lply.isTraitor and obj.traitor.objective ) or ( lply.isGunner and obj.gunner.objective ) or obj.innocent.objective
	else
		Rolename = lply.isTraitor and "Cultist" or "Innocent"
		ColorRole = lply.isTraitor and Color(255, 60, 60) or Color(120, 220, 120)
		ColorInno = Color(120, 220, 120)
		Objective = lply.isTraitor and "Eliminate without being caught." or "Survive."
	end

	ColorRole = Color(ColorRole.r, ColorRole.g, ColorRole.b, 255 * fade)
	ColorInno = Color(ColorInno.r, ColorInno.g, ColorInno.b, 255 * fade)
	local color_white_faded = Color(255, 255, 255, 255 * fade)

	draw.SimpleText("You are " .. Rolename, "ZB_HomicideMediumLarge", sw * 0.5, sh * 0.5, ColorRole, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

	local cur_y = sh * 0.5
	local SubRoles = MODE.SubRoles or {}
	local Professions = MODE.Professions or {}

	if lply.SubRole and lply.SubRole != "" then
		cur_y = cur_y + ScreenScale(20)
		draw.SimpleText("" .. ((SubRoles[lply.SubRole] and SubRoles[lply.SubRole].Name or lply.SubRole) or lply.SubRole), "ZB_HomicideMediumLarge", sw * 0.5, cur_y, ColorRole, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	if !lply.MainTraitor and lply.isTraitor then
		cur_y = cur_y + ScreenScale(20)
		draw.SimpleText("Assistant", "ZB_HomicideMedium", sw * 0.5, cur_y, ColorRole, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	if lply.isTraitor then
		cur_y = cur_y + ScreenScale(20)

		if lply.MainTraitor then
			MODE.TraitorsLocal = MODE.TraitorsLocal or {}
			if #MODE.TraitorsLocal > 1 then
				draw.SimpleText("Traitors list:", "ZB_HomicideMedium", sw * 0.5, cur_y, ColorRole, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				for _, traitor_info in ipairs(MODE.TraitorsLocal) do
					local traitor_color = Color(traitor_info[1].r, traitor_info[1].g, traitor_info[1].b, 255 * fade)
					cur_y = cur_y + ScreenScale(15)
					draw.SimpleText(traitor_info[2], "ZB_HomicideMedium", sw * 0.5, cur_y, traitor_color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
			end
		elseif MODE.TraitorWord and MODE.TraitorWordSecond then
			draw.SimpleText("Traitor secret words:", "ZB_HomicideMedium", sw * 0.5, cur_y, ColorRole, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			cur_y = cur_y + ScreenScale(15)
			draw.SimpleText("\"" .. MODE.TraitorWord .. "\"", "ZB_HomicideMedium", sw * 0.5, cur_y, color_white_faded, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			cur_y = cur_y + ScreenScale(15)
			draw.SimpleText("\"" .. MODE.TraitorWordSecond .. "\"", "ZB_HomicideMedium", sw * 0.5, cur_y, color_white_faded, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end

	if lply.Profession and lply.Profession != "" then
		cur_y = cur_y + ScreenScale(20)
		draw.SimpleText("Occupation: " .. ((Professions[lply.Profession] and Professions[lply.Profession].Name or lply.Profession) or lply.Profession), "ZB_HomicideMedium", sw * 0.5, cur_y, ColorInno, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	if handicap[lply:GetLocalVar("karma_sickness", 0)] then
		cur_y = cur_y + ScreenScale(20)
		draw.SimpleText(handicap[lply:GetLocalVar("karma_sickness", 0)], "ZB_HomicideMedium", sw * 0.5, cur_y, ColorInno, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	if lply.SubRole and lply.SubRole != "" and SubRoles[lply.SubRole] and SubRoles[lply.SubRole].Objective then
		Objective = SubRoles[lply.SubRole].Objective
	end

	if !lply.MainTraitor and lply.isTraitor then
		Objective = "You are equipped with nothing. Help other traitors win."
	end

	-- fear's own objective lines
	Objective = lply.isTraitor and "A powerful pact has formed."
		or "Survive. One of you has summoned something."

	if MODE.RoleEndedChosingState == false then
		Objective = "Round is starting..."
	end

	draw.SimpleText(Objective or "", "ZB_HomicideMedium", sw * 0.5, sh * 0.9, color_white_faded, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end


-- =====================================================================
-- Jumpscares: embedded images written to data/ at load (no downloads
-- needed), flashed fullscreen with a scream when the server says so.
-- =====================================================================

local __jsimgs = {
    ["fear_js1.jpg"] = "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",
    ["fear_js2.jpg"] = "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",
}

file.CreateDir("fear_js")
for name, b64 in pairs(__jsimgs) do
    local path = "fear_js/" .. name
    if not file.Exists(path, "DATA") then
        file.Write(path, util.Base64Decode(b64))
    end
end
__jsimgs = nil

local jsMats = {
    { mat = Material("../data/fear_js/fear_js1.jpg", "smooth"), w = 240, h = 427 },
    { mat = Material("../data/fear_js/fear_js2.jpg", "smooth"), w = 508, h = 557 },
}

local jsActive -- { idx, endtime, start }

local jsDazedUntil = 0

net.Receive("fear_jumpscare", function()
    local idx = math.Clamp(net.ReadUInt(2), 1, 2)
    jsActive = {
        idx = idx,
        start = CurTime(),
        endtime = CurTime() + 0.45,
    }
    jsDazedUntil = CurTime() + 6
    surface.PlaySound("npc/fast_zombie/fz_scream1.wav")
    util.ScreenShake(vector_origin, 8, 90, 0.5, 10000)
end)

-- the concussed aftermath: motion blur + washed color + view sway,
-- strongest right after the scare, gone in ~6 seconds
hook.Add("RenderScreenspaceEffects", "Fear_JumpscareDaze", function()
    local left = jsDazedUntil - CurTime()
    if left <= 0 then return end
    local strength = math.min(left / 6, 1)

    DrawMotionBlur(0.12, 0.7 * strength, 0.01)
    DrawColorModify({
        ["$pp_colour_addr"] = 0,
        ["$pp_colour_addg"] = 0,
        ["$pp_colour_addb"] = 0,
        ["$pp_colour_brightness"] = 0.02 * strength,
        ["$pp_colour_contrast"] = 1 - 0.25 * strength,
        ["$pp_colour_colour"] = 1 - 0.55 * strength,
        ["$pp_colour_mulr"] = 0,
        ["$pp_colour_mulg"] = 0,
        ["$pp_colour_mulb"] = 0,
    })
end)

hook.Add("CalcView", "Fear_JumpscareSway", function(ply, pos, angles, fov)
    local left = jsDazedUntil - CurTime()
    if left <= 0 then return end
    local strength = math.min(left / 6, 1) * 2.2

    local t = CurTime()
    angles.roll = angles.roll + math.sin(t * 1.7) * strength
    angles.pitch = angles.pitch + math.sin(t * 1.3) * strength * 0.5
    angles.yaw = angles.yaw + math.cos(t * 1.1) * strength * 0.4

    return { origin = pos, angles = angles, fov = fov }
end)

hook.Add("HUDPaint", "Fear_Jumpscare", function()
    if not jsActive then return end
    local now = CurTime()
    if now > jsActive.endtime then
        jsActive = nil
        return
    end

    -- quick fade out over the last 0.15s
    local alpha = 1
    local untilEnd = jsActive.endtime - now
    if untilEnd < 0.15 then alpha = untilEnd / 0.15 end

    local sw, sh = ScrW(), ScrH()

    surface.SetDrawColor(0, 0, 0, 255 * alpha)
    surface.DrawRect(-1, -1, sw + 1, sh + 1)

    local img = jsMats[jsActive.idx]
    if img and img.mat and not img.mat:IsError() then
        local drawH = sh * 0.85
        local drawW = drawH * (img.w / img.h)
        surface.SetDrawColor(255, 255, 255, 255 * alpha)
        surface.SetMaterial(img.mat)
        surface.DrawTexturedRect(sw / 2 - drawW / 2, sh / 2 - drawH / 2, drawW, drawH)
    end
end)



-- =====================================================================
-- The mark: while the entity hunts you, your own heartbeat is faintly
-- audible. Learn the tell, live with the knowledge.
-- =====================================================================
local heartSound

net.Receive("fear_marked", function()
	local marked = net.ReadBool()
	if marked then
		if not heartSound then
			heartSound = CreateSound(LocalPlayer(), "player/heartbeatloop.wav")
		end
		heartSound:PlayEx(0.25, 85)
	elseif heartSound then
		heartSound:FadeOut(2)
		heartSound = nil
	end
end)

hook.Add("ZB_EndRound", "Fear_HeartStop", function()
	if heartSound then heartSound:FadeOut(1) heartSound = nil end
end)


-- =====================================================================
-- The wrath banner: big, red, yellow-outlined, glitching. Type 0 =
-- cultist died (broadcast); type 1 = pact broken (last-alive cultist).
-- =====================================================================
surface.CreateFont("Fear_Wrath", {
	font = "Bahnschrift",
	size = ScreenScale(19),
	weight = 900,
	antialias = true,
})

local wrathUntil = 0
local wrathLines = {
	[0] = {
		"THE ONE WHO BOUND ME IS DEAD.",
		"NOW NOTHING WILL BE SPARED.",
	},
	[1] = {
		"THE PACT IS ENDED.",
		"IT IS COMING FOR WHAT REMAINS.",
	},
	[2] = {
		"THERE IS NO ONE LEFT BUT YOU.",
		"IT HAS STOPPED HIDING.",
	},
}
local activeLines = wrathLines[0]

net.Receive("fear_wrath", function()
	local kind = net.ReadUInt(2)
	activeLines = wrathLines[kind] or wrathLines[0]
	wrathUntil = CurTime() + 7
	surface.PlaySound("ambient/levels/citadel/strange_talk8.wav")
end)

hook.Add("HUDPaint", "Fear_WrathDraw", function()
	local left = wrathUntil - CurTime()
	if left <= 0 then return end

	local alpha = math.min(left / 1.2, 1)
	local t = CurTime()
	local lines = activeLines

	-- unstable: slow drunken drift plus violent glitch spasms
	local driftX = math.sin(t * 1.9) * 6 + math.sin(t * 3.7) * 3
	local driftY = math.cos(t * 1.4) * 4 + math.sin(t * 4.3) * 2

	local glitching = math.sin(t * 13) > 0.86
	local gx = glitching and math.random(-14, 14) or 0
	local gy = glitching and math.random(-4, 4) or 0

	local x = ScrW() / 2 + driftX + gx
	local y = ScrH() * 0.34 + driftY + gy

	for i, text in ipairs(lines) do
		local ly = y + (i - 1) * ScreenScale(22)
		local lx = x + math.sin(t * 6.1 + i * 2.4) * 2

		if glitching then
			draw.SimpleText(text, "Fear_Wrath", lx + math.random(8, 20), ly + math.random(-3, 3),
				Color(190, 0, 0, 90 * alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end

		for ox = -2, 2, 2 do
			for oy = -2, 2, 2 do
				if ox != 0 or oy != 0 then
					draw.SimpleText(text, "Fear_Wrath", lx + ox, ly + oy,
						Color(255, 230, 0, 255 * alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
			end
		end
		draw.SimpleText(text, "Fear_Wrath", lx, ly,
			Color(190, 0, 0, 255 * alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end)
