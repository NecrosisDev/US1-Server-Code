if SERVER then return end

-- Native file refresh has no loader-owned global MODE; reuse this mode only.
local refreshing = MODE == nil
local MODE = MODE or (zb and zb.modes and zb.modes.uncontainedriot)
if not MODE then return end

MODE.name = "uncontainedriot"

local soundGeneration = 0
local function IsThisMode()
    local mode = CurrentRound and CurrentRound()
    return mode and mode.name == "uncontainedriot"
end
local function StopIntro()
    soundGeneration = soundGeneration + 1
    if IsValid(UncontainedRiotSound) then UncontainedRiotSound:Stop() end
    UncontainedRiotSound = nil
end
StopIntro()

net.Receive("uncontainedriot_start", function()
    StopIntro()
    if not IsThisMode() then return end
    local generation = soundGeneration
    sound.PlayFile("sound/zbattle/riot.wav", "noplay", function(station)
        if not IsValid(station) then return end
        if generation ~= soundGeneration or not IsThisMode() or zb.ROUND_STATE == 3 then
            station:Stop()
            return
        end
        station:SetVolume(1)
        station:Play()
        UncontainedRiotSound = station
    end)
    zb.RemoveFade()
end)

hook.Add("Think", "zc_uncontainedriot_audio_cleanup", function()
    if IsValid(UncontainedRiotSound) and (not IsThisMode() or zb.ROUND_STATE == 3) then StopIntro() end
end)

local teams = {
    [0] = {
        objective = "Fuck em', burn it all.",
        name = "a Rioter",
        color1 = Color(190, 0, 0),
        color2 = Color(190, 0, 0)
    },
    [1] = {
        objective = "Lethal force authorized.",
        name = "Law Enforcement",
        color1 = Color(0, 120, 190),
        color2 = Color(0, 120, 190)
    },
}

function MODE:RenderScreenspaceEffects()
    if not zb or type(zb.ROUND_START) ~= "number" or zb.ROUND_START + 7.5 < CurTime() then return end
    local fade = math.Clamp(zb.ROUND_START + 7.5 - CurTime(), 0, 1)

    surface.SetDrawColor(0, 0, 0, 255 * fade)
    surface.DrawRect(-1, -1, ScrW() + 1, ScrH() + 1)
end

function MODE:HUDPaint()
    if not zb or type(zb.ROUND_START) ~= "number" or zb.ROUND_START + 8.5 < CurTime() then return end

    local lply = LocalPlayer()
    if not IsValid(lply) or not lply:Alive() or not teams[lply:Team()] then return end
    local sw, sh = ScrW(), ScrH()
    zb.RemoveFade()
    local fade = math.Clamp(zb.ROUND_START + 8 - CurTime(), 0, 1)
    local team_ = lply:Team()

    draw.SimpleText("Homicide | Uncontained Riot", "ZB_HomicideMediumLarge", sw * 0.5, sh * 0.1, Color(0, 162, 255, 255 * fade), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    local Rolename = teams[team_].name
    local ColorRole = teams[team_].color1
    ColorRole.a = 255 * fade
    draw.SimpleText("You are " .. Rolename, "ZB_HomicideMediumLarge", sw * 0.5, sh * 0.5, ColorRole, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    local Objective = teams[team_].objective
    local ColorObj = teams[team_].color2
    ColorObj.a = 255 * fade
    draw.SimpleText(Objective, "ZB_HomicideMedium", sw * 0.5, sh * 0.9, ColorObj, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    if hg.PluvTown and hg.PluvTown.Active then
        surface.SetMaterial(hg.PluvTown.PluvMadness)
        surface.SetDrawColor(255, 255, 255, math.random(175, 255) * fade / 2)
        surface.DrawTexturedRect(sw * 0.25, sh * 0.44 - ScreenScale(15), sw / 2, ScreenScale(30))

        draw.SimpleText("SOMEWHERE IN PLUVTOWN", "ZB_ScrappersLarge", sw / 2, sh * 0.44 - ScreenScale(2), Color(0, 0, 0, 255 * fade), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end

local CreateEndMenu

net.Receive("uncontainedriot_roundend", function()
    if not IsThisMode() or zb.ROUND_STATE ~= 3 then return end
    StopIntro()
    CreateEndMenu()
end)

local colGray = Color(85, 85, 85, 255)
local colRed = Color(130, 10, 10)
local colRedUp = Color(160, 30, 30)
local col = Color(255, 255, 255, 255)
local colSpect1 = Color(75, 75, 75, 255)
local colSpect2 = Color(255, 255, 255)

BlurBackground = BlurBackground or hg.DrawBlur

CreateEndMenu = function()
    if IsValid(hmcdEndMenu) then
        hmcdEndMenu:Remove()
        hmcdEndMenu = nil
    end

    hmcdEndMenu = vgui.Create("ZFrame")
    local frame = hmcdEndMenu
    if not IsValid(frame)then return end
    frame.Think = function(self)
        if not IsThisMode() or zb.ROUND_STATE ~= 3 then self:Remove() end
    end
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
        if IsValid(frame) then frame:Close() end
        if hmcdEndMenu == frame then hmcdEndMenu = nil end
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
        if IsValid(ply) and ply:Team() ~= TEAM_SPECTATOR then
            -- Snapshot results: disconnected players must not break panel paint/click.
            local result = {
                alive = ply:Alive(), name = ply:Name(),
                character = ply:GetPlayerName() or ply:Name(),
                color = ply:GetPlayerColor():ToColor(), frags = tostring(ply:Frags()),
                bot = ply:IsBot(), steamid = ply:IsBot() and ply:GetNWString("zcSteamID64", "") or ply:SteamID64()
            }
            local but = vgui.Create("DButton", DScrollPanel)
            but:SetSize(100, 50)
            but:Dock(TOP)
            but:DockMargin(8, 6, 8, -1)
            but:SetText("")
            but.Paint = function(self, w, h)
                local col1 = (result.alive and colRed) or colGray
                local col2 = (result.alive and colRedUp) or colSpect1
                surface.SetDrawColor(col1.r, col1.g, col1.b, col1.a)
                surface.DrawRect(0, 0, w, h)
                surface.SetDrawColor(col2.r, col2.g, col2.b, col2.a)
                surface.DrawRect(0, h / 2, w, h / 2)

                local pcol = result.color
                surface.SetFont("ZB_InterfaceMediumLarge")
                local lengthX, lengthY = surface.GetTextSize(result.character)
                surface.SetTextColor(0, 0, 0, 255)
                surface.SetTextPos(w / 2 + 1, h / 2 - lengthY / 2 + 1)
                surface.DrawText(result.character)
                surface.SetTextColor(pcol.r, pcol.g, pcol.b, pcol.a)
                surface.SetTextPos(w / 2, h / 2 - lengthY / 2)
                surface.DrawText(result.character)

                local col = colSpect2
                surface.SetFont("ZB_InterfaceMediumLarge")
                surface.SetTextColor(col.r, col.g, col.b, col.a)
                surface.SetTextPos(15, h / 2 - lengthY / 2)
                surface.DrawText(result.name .. (not result.alive and " - died" or ""))

                surface.SetFont("ZB_InterfaceMediumLarge")
                surface.SetTextColor(col.r, col.g, col.b, col.a)
                local lengthX, lengthY = surface.GetTextSize(result.frags)
                surface.SetTextPos(w - lengthX - 15, h / 2 - lengthY / 2)
                surface.DrawText(result.frags)
            end

            function but:DoClick()
                if result.steamid:match("^%d+$") then
                    gui.OpenURL("https://steamcommunity.com/profiles/" .. result.steamid)
                end
            end

            DScrollPanel:AddItem(but)
        end
    end

    return true
end

function MODE:RoundStart()
    if IsValid(hmcdEndMenu) then
        hmcdEndMenu:Remove()
        hmcdEndMenu = nil
    end
end

MODE.ZCRiotClientRevision = "1.0.1"
if refreshing then
    local callbacks = zb.modesHooks and zb.modesHooks.uncontainedriot
    if callbacks then
        -- The loader already registered these dispatch hooks. Refresh only ours.
        for _, key in ipairs({"RenderScreenspaceEffects", "HUDPaint", "RoundStart"}) do
            callbacks[key] = MODE[key]
        end
    end
    print("[RiotFix] 1.0.1 client callbacks refreshed")
end
