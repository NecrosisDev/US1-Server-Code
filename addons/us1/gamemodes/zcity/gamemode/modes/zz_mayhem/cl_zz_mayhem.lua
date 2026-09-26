MODE.name = "mayhem"

local MODE = MODE

StartTime = StartTime or 0

zb.ROUND_START = zb.ROUND_START or 0

local mayhemmusic = nil
local roundend = false

local snds = {
	"https://vgmtreasurechest.com/soundtracks/superfighters-deluxe-original-soundtrack-2018/fflmfnap/03.%20Anarchy%20.mp3",
	"https://vgmtreasurechest.com/soundtracks/superfighters-deluxe-original-soundtrack-2018/vmvsazvg/20.%20Iron%20Fists.mp3",
	"https://vgmtreasurechest.com/soundtracks/superfighters-deluxe-original-soundtrack-2018/icnhxrsl/28.%20Seek%20And%20Destroy.mp3",
	"https://vgmtreasurechest.com/soundtracks/superfighters-deluxe-original-soundtrack-2018/odapyyyv/27.%20Rust%20And%20Gore.mp3",
	"https://vgmtreasurechest.com/soundtracks/superfighters-deluxe-original-soundtrack-2018/digfibga/18.%20Heroes%20Battle.mp3",
	"https://vgmtreasurechest.com/soundtracks/superfighters-deluxe-original-soundtrack-2018/wkmgufqo/39.%20Zombie%20Nightmare.mp3",
}

local function restartMusic()
	local snd = snds[math.random(#snds)]

	if IsValid(mayhemmusic) then
		mayhemmusic:Stop()
		mayhemmusic = nil
	end

	sound.PlayURL(snd, "mono noblock noplay", function(station, errID, err)
		if IsValid(station) then
			station:SetVolume(0.1)
			mayhemmusic = station
		else
			print(errID, err)
		end
	end)
end

net.Receive("mayhem_start", function()
	roundend = false

	restartMusic()

	zb.RemoveFade()

	StartTime = CurTime()
	net.ReadVector()
end)

local fighter = {
	objective = "Kill everyone. Feel nothing.",
	name = "Maniac",
	color1 = Color(190, 15, 15)
}

function MODE:RenderScreenspaceEffects()
	if zb.ROUND_START + 7.5 < CurTime() then return end

	local fade = math.Clamp(zb.ROUND_START + 7.5 - CurTime(), 0, 1)

	surface.SetDrawColor(0, 0, 0, 255 * fade)
	surface.DrawRect(-1, -1, ScrW() + 1, ScrH() + 1)
end

function MODE:HUDPaint()
	if zb.ROUND_START + 5 > CurTime() then
		draw.SimpleText(string.FormattedTime(zb.ROUND_START + 5 - CurTime(), "%02i:%02i:%02i"), "ZB_HomicideMedium", sw * 0.5, sh * 0.75, Color(255, 55, 55), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	else
		local ply = LocalPlayer()
		if IsValid(mayhemmusic) then
			if mayhemmusic:GetTime() >= (mayhemmusic:GetLength() - 1) then
				restartMusic()
				return
			end

			if mayhemmusic:GetState() != GMOD_CHANNEL_PLAYING then
				mayhemmusic:Play()
				return
			end

			local vol = math.Clamp((CurTime() - (zb.ROUND_START + 7)), 0.1, ply:Alive() and ply.organism.otrub and 0.1 or 1 + math.min((ply.organism.adrenaline or 0) * 25, 2))
			if roundend then
				vol = math.Clamp((roundend - CurTime() + 1) / 2, 0.1, ply:Alive() and ply.organism.otrub and 0.1 or 1 + math.min((ply.organism.adrenaline or 0) * 25, 2))
			end
			local musicVolume = GetConVar("snd_musicvolume"):GetFloat()
			mayhemmusic:SetVolume(vol * musicVolume)
		end
	end

	-- Names above heads (no health bar)
	for i, ply in player.Iterator() do
		if not IsValid(ply) or ply == LocalPlayer() or not ply:Alive() then continue end
		local tr = hg.eyeTrace(ply)
		local pos = tr.StartPos + vector_up * 15
		local posscr = pos:ToScreen()

		surface.SetTextColor(255, 255, 255, 255)
		surface.SetFont("ScoreboardDefault")
		local txt = ply:Name()
		local w, h = surface.GetTextSize(txt)
		surface.SetTextPos(posscr.x - w / 2, posscr.y - h)
		surface.DrawText(txt)
	end

	if not lply:Alive() then return end
	if zb.ROUND_START + 8.5 < CurTime() then return end
	zb.RemoveFade()
	local fade = math.Clamp(zb.ROUND_START + 8 - CurTime(), 0, 1)

	draw.SimpleText("MAYHEM", "ZB_HomicideMediumLarge", sw * 0.5, sh * 0.1, Color(255, 30, 30, 255 * fade), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	local Rolename = fighter.name
	local ColorRole = Color(fighter.color1.r, fighter.color1.g, fighter.color1.b, 255 * fade)
	draw.SimpleText("You are a " .. Rolename, "ZB_HomicideMediumLarge", sw * 0.5, sh * 0.5, ColorRole, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

	local Objective = fighter.objective
	local ColorObj = Color(fighter.color1.r, fighter.color1.g, fighter.color1.b, 255 * fade)
	draw.SimpleText(Objective, "ZB_HomicideMedium", sw * 0.5, sh * 0.9, ColorObj, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local CreateEndMenu = nil
local wonply = nil

net.Receive("mayhem_end", function()
	local ent = net.ReadEntity()
	wonply = nil
	if IsValid(ent) then
		ent.won = true
		wonply = ent
	end

	roundend = CurTime()

	if IsValid(mayhemmusic) then
		mayhemmusic:Stop()
		mayhemmusic = nil
	end

	CreateEndMenu()
end)

local colGray = Color(85, 85, 85, 255)
local colRed = Color(217, 201, 99)
local colRedUp = Color(207, 181, 59)

local colBlue = Color(160, 10, 10)
local colBlueUp = Color(190, 40, 40)
local col = Color(255, 255, 255, 255)

local colSpect1 = Color(75, 75, 75, 255)
local colSpect2 = Color(255, 255, 255)

BlurBackground = BlurBackground or hg.DrawBlur

if IsValid(hmcdEndMenu) then
	hmcdEndMenu:Remove()
	hmcdEndMenu = nil
end

CreateEndMenu = function()
	if IsValid(hmcdEndMenu) then
		hmcdEndMenu:Remove()
		hmcdEndMenu = nil
	end
	hmcdEndMenu = vgui.Create("ZFrame")

	surface.PlaySound("ambient/alarms/warningbell1.wav")

	local sizeX, sizeY = ScrW() / 2.5, ScrH() / 1.2
	local posX, posY = ScrW() / 1.3 - sizeX / 2, ScrH() / 2 - sizeY / 2

	hmcdEndMenu:SetPos(posX, posY)
	hmcdEndMenu:SetSize(sizeX, sizeY)
	hmcdEndMenu:MakePopup()
	hmcdEndMenu:SetKeyboardInputEnabled(false)
	hmcdEndMenu:ShowCloseButton(false)

	local closebutton = vgui.Create("DButton", hmcdEndMenu)
	closebutton:SetPos(5, 5)
	closebutton:SetSize(ScrW() / 20, ScrH() / 30)
	closebutton:SetText("")

	closebutton.DoClick = function()
		if IsValid(hmcdEndMenu) then
			hmcdEndMenu:Close()
			hmcdEndMenu = nil
		end
	end

	closebutton.Paint = function(self, w, h)
		surface.SetDrawColor(122, 122, 122, 255)
		surface.DrawOutlinedRect(0, 0, w, h, 2.5)
		surface.SetFont("ZB_InterfaceMedium")
		surface.SetTextColor(col.r, col.g, col.b, col.a)
		local lengthX, lengthY = surface.GetTextSize("Close")
		surface.SetTextPos(lengthX - lengthX / 1.1, 4)
		surface.DrawText("Close")
	end

	hmcdEndMenu.Paint = function(self, w, h)
		BlurBackground(self)
		local txt = (IsValid(wonply) and wonply:GetPlayerName() or "Nobody") .. " survived the Mayhem!"
		surface.SetFont("ZB_InterfaceMediumLarge")
		surface.SetTextColor(col.r, col.g, col.b, col.a)
		local lengthX, lengthY = surface.GetTextSize(txt)
		surface.SetTextPos(w / 2 - lengthX / 2, 20)
		surface.DrawText(txt)

		surface.SetDrawColor(255, 0, 0, 128)
		surface.DrawOutlinedRect(0, 0, w, h, 2.5)
	end

	local DScrollPanel = vgui.Create("DScrollPanel", hmcdEndMenu)
	DScrollPanel:SetPos(10, 80)
	DScrollPanel:SetSize(sizeX - 20, sizeY - 90)
	function DScrollPanel:Paint(w, h)
		BlurBackground(self)

		surface.SetDrawColor(255, 0, 0, 128)
		surface.DrawOutlinedRect(0, 0, w, h, 2.5)
	end

	for i, ply in player.Iterator() do
		if ply:Team() == TEAM_SPECTATOR then continue end
		local but = vgui.Create("DButton", DScrollPanel)
		but:SetSize(100, 50)
		but:Dock(TOP)
		but:DockMargin(8, 6, 8, -1)
		but:SetText("")
		but.Paint = function(self, w, h)
			if not IsValid(ply) then
				surface.SetDrawColor(colGray.r, colGray.g, colGray.b, colGray.a)
				surface.DrawRect(0, 0, w, h)
				surface.SetFont("ZB_InterfaceMediumLarge")
				surface.SetTextColor(255, 255, 255, 255)
				surface.SetTextPos(15, h / 2 - 12)
				surface.DrawText("He quited...")
				return
			end
			local col1 = (ply.won and colRed) or (ply:Alive() and colBlue) or colGray
			local col2 = (ply.won and colRedUp) or (ply:Alive() and colBlueUp) or colSpect1

			surface.SetDrawColor(col1.r, col1.g, col1.b, col1.a)
			surface.DrawRect(0, 0, w, h)
			surface.SetDrawColor(col2.r, col2.g, col2.b, col2.a)
			surface.DrawRect(0, h / 2, w, h / 2)

			local pcol = ply:GetPlayerColor():ToColor()
			surface.SetFont("ZB_InterfaceMediumLarge")
			local lengthX, lengthY = surface.GetTextSize(ply:GetPlayerName() or "He quited...")

			surface.SetTextColor(0, 0, 0, 255)
			surface.SetTextPos(w / 2 + 1, h / 2 - lengthY / 2 + 1)
			surface.DrawText(ply:GetPlayerName() or "He quited...")

			surface.SetTextColor(pcol.r, pcol.g, pcol.b, pcol.a)
			surface.SetTextPos(w / 2, h / 2 - lengthY / 2)
			surface.DrawText(ply:GetPlayerName() or "He quited...")

			local scol = colSpect2
			surface.SetFont("ZB_InterfaceMediumLarge")
			surface.SetTextColor(scol.r, scol.g, scol.b, scol.a)
			surface.SetTextPos(15, h / 2 - lengthY / 2)
			surface.DrawText((ply:Name() .. (not ply:Alive() and " - died" or "")) or "He quited...")

			surface.SetFont("ZB_InterfaceMediumLarge")
			local fx, fy = surface.GetTextSize(ply:Frags() or "0")
			surface.SetTextPos(w - fx - 15, h / 2 - fy / 2)
			surface.DrawText(ply:Frags() or "0")
		end

		function but:DoClick()
			if not IsValid(ply) then return end
			local id64 = ply:SteamID64()
			if ply:IsBot() then
				id64 = ply:GetNWString("zcSteamID64", "")
				if id64 == "" then return end
			end
			gui.OpenURL("https://steamcommunity.com/profiles/" .. id64)
		end

		DScrollPanel:AddItem(but)
	end

	return true
end

function MODE:RoundStart()
	for i, ply in player.Iterator() do
		ply.won = nil
	end

	if IsValid(hmcdEndMenu) then
		hmcdEndMenu:Remove()
		hmcdEndMenu = nil
	end
end
