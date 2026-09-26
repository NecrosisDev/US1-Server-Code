local MODE = MODE
MODE.name = "homelanderhns"

local FREEZE_TIME = 30
local homelanderEnt = nil

local song
local songfade = 0

net.Receive("homelanderhns_start", function()
    homelanderEnt = net.ReadEntity()

    surface.PlaySound("zbattle/criresp.mp3")

    timer.Simple(3, function()
        sound.PlayFile("sound/zbattle/criresp/criepmission.mp3", "mono noblock", function(station)
            if IsValid(station) then
                station:Play()
                song = station
                songfade = 1
            end
        end)
    end)
end)

local teams = {
    [0] = {
        objective = "Hunt them down. Show them what you really are.",
        name = "the Homelander",
        color1 = Color(228, 49, 49),
        color2 = Color(228, 49, 49)
    },
    [1] = {
        objective = "Hide. Run. Survive 5 minutes.",
        name = "a Civilian",
        color1 = Color(0, 162, 255),
        color2 = Color(0, 162, 255)
    },
}

function MODE:RenderScreenspaceEffects()
    zb.RemoveFade()
    if zb.ROUND_START + FREEZE_TIME - 5 < CurTime() then
        if songfade <= 0.01 and IsValid(song) then
            song:Stop()
            surface.PlaySound(lply:Team() == 0 and "zbattle/criresp/barricadedsuspectstart.mp3" or "snd_jack_hmcd_policesiren.wav")
        elseif IsValid(song) then
            songfade = Lerp(0.01, songfade, 0)
            song:SetVolume(songfade)
        end
    end
    if zb.ROUND_START + 7.5 < CurTime() then return end
    local fade = math.Clamp(zb.ROUND_START + 7.5 - CurTime(), 0, 1)
    surface.SetDrawColor(0, 0, 0, 255 * fade)
    surface.DrawRect(-1, -1, ScrW() + 1, ScrH() + 1)
end

local posadd = 0
function MODE:HUDPaint()
    if zb.ROUND_START + FREEZE_TIME > CurTime() then
        posadd = Lerp(FrameTime() * 5, posadd or 0, zb.ROUND_START + 7.3 < CurTime() and 0 or -sw * 0.4)
        local color = Color(255 * -math.sin(CurTime() * 3), 25, 255 * math.sin(CurTime() * 3))

        local labelText
        if lply:Team() == 0 then
            labelText = "You are unleashed in: "..string.FormattedTime(zb.ROUND_START + FREEZE_TIME - CurTime(), "%02i:%02i")
        else
            labelText = "Homelander wakes in: "..string.FormattedTime(zb.ROUND_START + FREEZE_TIME - CurTime(), "%02i:%02i")
        end

        draw.SimpleText(labelText, "ZB_HomicideMedium", sw * 0.02 + posadd, sh * 0.95, Color(0, 0, 0), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(labelText, "ZB_HomicideMedium", (sw * 0.02) - 2 + posadd, (sh * 0.95) - 2, color, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        local fade = math.Clamp(zb.ROUND_START + 7.5 - CurTime(), 0, 1)
        surface.SetDrawColor(0, 0, 0, 255 * fade)
        surface.DrawRect(-1, -1, ScrW() + 1, ScrH() + 1)
    end

    if zb.ROUND_START + 8.5 > CurTime() then
        if not lply:Alive() and lply:Team() ~= 0 then return end
        local fade = math.Clamp(zb.ROUND_START + 8 - CurTime(), 0, 1)
        local team_ = lply:Team()
        if not teams[team_] then return end

        draw.SimpleText("Homelander: Hide & Seek", "ZB_HomicideMediumLarge", sw * 0.5, sh * 0.1, Color(255, 50, 50, 255 * fade), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        local Rolename = teams[team_].name
        local ColorRole = Color(teams[team_].color1.r, teams[team_].color1.g, teams[team_].color1.b, 255 * fade)
        draw.SimpleText("You are " .. Rolename, "ZB_HomicideMediumLarge", sw * 0.5, sh * 0.5, ColorRole, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        local Objective = teams[team_].objective
        local ColorObj = Color(teams[team_].color2.r, teams[team_].color2.g, teams[team_].color2.b, 255 * fade)
        draw.SimpleText(Objective, "ZB_HomicideMedium", sw * 0.5, sh * 0.9, ColorObj, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end

local CreateEndMenu
net.Receive("homelanderhns_roundend", function() CreateEndMenu(net.ReadInt(8)) end)

local colGray = Color(85, 85, 85, 255)
local colRed = Color(130, 10, 10)
local colRedUp = Color(160, 30, 30)
local colBlue = Color(10, 10, 160)
local colBlueUp = Color(40, 40, 160)
local col = Color(255, 255, 255, 255)
local colSpect1 = Color(75, 75, 75, 255)
local colSpect2 = Color(255, 255, 255)

if IsValid(hmcdEndMenu) then
    hmcdEndMenu:Remove()
    hmcdEndMenu = nil
end

CreateEndMenu = function(whowin)
    if IsValid(hmcdEndMenu) then
        hmcdEndMenu:Remove()
        hmcdEndMenu = nil
    end

    hmcdEndMenu = vgui.Create("ZFrame")
    surface.PlaySound((whowin == 1) and "zbattle/criresp/failedSWAT.mp3" or "ambient/alarms/warningbell1.wav")
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

    hmcdEndMenu.PaintOver = function(self, w, h)
        surface.SetFont("ZB_InterfaceMediumLarge")
        surface.SetTextColor(col.r, col.g, col.b, col.a)
        local titleText = whowin == 0 and "Homelander Wins!" or "Hiders Survive!"
        local lengthX, lengthY = surface.GetTextSize(titleText)
        surface.SetTextPos(w / 2 - lengthX / 2, 20)
        surface.DrawText(titleText)
    end

    local DScrollPanel = vgui.Create("DScrollPanel", hmcdEndMenu)
    DScrollPanel:SetPos(10, 80)
    DScrollPanel:SetSize(sizeX - 20, sizeY - 90)

    for _, ply in player.Iterator() do
        if ply:Team() == TEAM_SPECTATOR then continue end
        local but = vgui.Create("DButton", DScrollPanel)
        but:SetSize(100, 50)
        but:Dock(TOP)
        but:DockMargin(8, 6, 8, -1)
        but:SetText("")
        but.Paint = function(self, w, h)
            local col1 = (ply:Alive() and colRed) or colGray
            local col2 = (ply:Alive() and colRedUp) or colSpect1
            surface.SetDrawColor(col1.r, col1.g, col1.b, col1.a)
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(col2.r, col2.g, col2.b, col2.a)
            surface.DrawRect(0, h / 2, w, h / 2)
            local nameColor = ply:GetPlayerColor():ToColor()
            surface.SetFont("ZB_InterfaceMediumLarge")
            local lengthX, lengthY = surface.GetTextSize(ply:GetPlayerName() or "He quited...")
            surface.SetTextColor(0, 0, 0, 255)
            surface.SetTextPos(w / 2 + 1, h / 2 - lengthY / 2 + 1)
            surface.DrawText(ply:GetPlayerName() or "He quited...")
            surface.SetTextColor(nameColor.r, nameColor.g, nameColor.b, nameColor.a)
            surface.SetTextPos(w / 2, h / 2 - lengthY / 2)
            surface.DrawText(ply:GetPlayerName() or "He quited...")

            surface.SetFont("ZB_InterfaceMediumLarge")
            surface.SetTextColor(colSpect2.r, colSpect2.g, colSpect2.b, colSpect2.a)
            local lengthX, lengthY = surface.GetTextSize(ply:GetPlayerName() or "He quited...")
            surface.SetTextPos(15, h / 2 - lengthY / 2)
            surface.DrawText(ply:Name() .. ((not ply:Alive()) and " - dead" or ""))

            surface.SetFont("ZB_InterfaceMediumLarge")
            local lengthX, lengthY = surface.GetTextSize(ply:Frags() or "He quited...")
            surface.SetTextPos(w - lengthX - 15, h / 2 - lengthY / 2)
            surface.DrawText(ply:Frags() or "He quited...")
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
