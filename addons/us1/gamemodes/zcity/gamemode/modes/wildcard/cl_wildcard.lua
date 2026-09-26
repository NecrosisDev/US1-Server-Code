MODE.name = "wildcard"
local MODE = MODE

-- =====================================================================
-- standard zcity round splash (cb/civilwar pattern)
-- =====================================================================

local myClass -- { name, color } - arrives per player at equip

net.Receive("wildcard_class", function()
	myClass = {
		name = net.ReadString(),
		color = net.ReadColor(),
	}
end)

net.Receive("wildcard_start", function()
	myClass = nil
	zb.RemoveFade()
end)

function MODE:RenderScreenspaceEffects()
	if zb.ROUND_START + 7.5 < CurTime() then return end
	local fade = math.Clamp(zb.ROUND_START + 7.5 - CurTime(), 0, 1)

	surface.SetDrawColor(0, 0, 0, 255 * fade)
	surface.DrawRect(-1, -1, ScrW() + 1, ScrH() + 1)
end

function MODE:HUDPaint()
	if zb.ROUND_START + 8.5 < CurTime() then return end

	local lply = LocalPlayer()
	if not IsValid(lply) or not lply:Alive() then return end
	zb.RemoveFade()

	local fade = math.Clamp(zb.ROUND_START + 8 - CurTime(), 0, 1)
	local sw, sh = ScrW(), ScrH()

	draw.SimpleText("ZBattle | Wildcard", "ZB_HomicideMediumLarge",
		sw * 0.5, sh * 0.1, Color(255, 200, 60, 255 * fade), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

	if myClass then
		local c = myClass.color
		draw.SimpleText("You are " .. myClass.name, "ZB_HomicideMediumLarge",
			sw * 0.5, sh * 0.5, Color(c.r, c.g, c.b, 255 * fade), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	draw.SimpleText("Anyone can be anything. Eliminate the enemy team.", "ZB_HomicideMedium",
		sw * 0.5, sh * 0.9, Color(160, 160, 160, 255 * fade), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- =====================================================================
-- standard zcity end-round menu (the players list panel every mode
-- shows - same implementation cb/civilwar carry)
-- =====================================================================

local CreateEndMenu

net.Receive("wildcard_roundend", function()
	local winner = net.ReadUInt(4)
	surface.PlaySound("ambient/alarms/warningbell1.wav")
	CreateEndMenu()
end)

local colGray = Color(85, 85, 85, 255)
local colRed = Color(130, 10, 10)
local colRedUp = Color(160, 30, 30)
local colBlue = Color(10, 10, 160)
local colBlueUp = Color(40, 40, 160)
local col = Color(255, 255, 255, 255)
local colSpect1 = Color(75, 75, 75, 255)

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
		surface.SetFont("ZB_InterfaceMediumLarge")
		surface.SetTextColor(col.r, col.g, col.b, col.a)
		local lengthX, lengthY = surface.GetTextSize("Players:")
		surface.SetTextPos(w / 2 - lengthX / 2, 20)
		surface.DrawText("Players:")
		surface.SetDrawColor(255, 200, 60, 128)
		surface.DrawOutlinedRect(0, 0, w, h, 2.5)
	end

	local DScrollPanel = vgui.Create("DScrollPanel", hmcdEndMenu)
	DScrollPanel:SetPos(10, 80)
	DScrollPanel:SetSize(sizeX - 20, sizeY - 90)

	function DScrollPanel:Paint(w, h)
		BlurBackground(self)
		surface.SetDrawColor(255, 200, 60, 128)
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
			local teamColor = (ply:Team() == 0 and colBlue) or (ply:Team() == 1 and colRed) or colGray
			local teamColorUp = (ply:Team() == 0 and colBlueUp) or (ply:Team() == 1 and colRedUp) or colSpect1

			surface.SetDrawColor(teamColor.r, teamColor.g, teamColor.b, teamColor.a)
			surface.DrawRect(0, 0, w, h)
			surface.SetDrawColor(teamColorUp.r, teamColorUp.g, teamColorUp.b, teamColorUp.a)
			surface.DrawRect(0, h / 2, w, h / 2)

			local playerColor = ply:GetPlayerColor():ToColor()
			surface.SetFont("ZB_InterfaceMediumLarge")
			surface.SetTextColor(0, 0, 0, 255)
			surface.SetTextPos(w / 2 + 1, h / 2 - 12 + 1)
			surface.DrawText(ply:GetPlayerName() or "He quited...")
			surface.SetTextColor(playerColor.r, playerColor.g, playerColor.b, playerColor.a)
			surface.SetTextPos(w / 2, h / 2 - 12)
			surface.DrawText(ply:GetPlayerName() or "He quited...")

			surface.SetFont("ZB_InterfaceMediumLarge")
			surface.SetTextColor(255, 255, 255, 255)
			surface.SetTextPos(15, h / 2 - 12)
			surface.DrawText((ply:Name() .. (not ply:Alive() and " - died" or "")) or "He quited...")

			surface.SetFont("ZB_InterfaceMediumLarge")
			surface.SetTextColor(255, 255, 255, 255)
			surface.SetTextPos(w - 45, h / 2 - 12)
			surface.DrawText(ply:Frags() or "0")
		end

		function but:DoClick()
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
	if IsValid(hmcdEndMenu) then
		hmcdEndMenu:Remove()
		hmcdEndMenu = nil
	end
end
