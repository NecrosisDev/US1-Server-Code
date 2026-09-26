-- ZCity Traitor Admin Tool - Client Side

if not CLIENT then return end



local playerData    = {}

local forcedSteamIDs = {}  -- now a table for multiple traitors

local forcedHomelander = ""

local abnoData      = nil  -- Abnormal tab payload (nil until first fetch)

local MutatorPage = include("traitor_admin/cl_mutators.lua")

local StaffPage = include("traitor_admin/cl_staff.lua")



-- Colors

local COL_BG          = Color(19, 22, 27)

local COL_HEADER      = Color(25, 29, 35)

local COL_ROW         = Color(29, 34, 41)

local COL_ROW_ALT     = Color(25, 30, 37)

local COL_TRAITOR_DIM = Color(80, 15, 15, 255)

local COL_FORCED_DIM  = Color(80, 50, 0, 255)

local COL_TRAITOR     = Color(180, 30, 30, 255)

local COL_FORCED      = Color(220, 140, 0, 255)

local COL_DEAD        = Color(156, 163, 174)

local COL_ACCENT      = Color(192, 62, 72)

local COL_BTN         = Color(42, 48, 58)

local COL_BTN_HOVER   = Color(57, 65, 77)

local COL_BTN_FORCE   = Color(160, 30, 30, 255)

local COL_BTN_FORCE_H = Color(200, 50, 50, 255)

local COL_BTN_CLEAR   = Color(35, 60, 35, 255)

local COL_BTN_CLEAR_H = Color(50, 90, 50, 255)

local COL_WHITE       = Color(255, 255, 255, 255)

local COL_GREY        = Color(170, 179, 191)

local COL_DIVIDER     = Color(48, 55, 65)



local function RBox(r, x, y, w, h, col)

    draw.RoundedBox(r, x, y, w, h, col)

end



-- Net receiver

net.Receive("traitoradmin_playerlist", function()

    playerData    = net.ReadTable()

    forcedSteamIDs = net.ReadTable()

    forcedHomelander = net.ReadString()

    if IsValid(TraitorAdminFrame) then

        TraitorAdminFrame:RefreshList()

    end

end)



net.Receive("traitoradmin_abno_data", function()

    abnoData = net.ReadTable()

    if IsValid(TraitorAdminFrame) then

        TraitorAdminFrame:RefreshAbno()

    end

end)



-- one message for every Abnormal-tab action: name + int arg + string arg

local function AbnoAction(action, i, s)

    net.Start("traitoradmin_abno_action")

        net.WriteString(action)

        net.WriteInt(i or 0, 32)

        net.WriteString(s or "")

    net.SendToServer()

end



-- Main Frame

local FRAME = {}

FRAME.__index = FRAME



function FRAME:StyleInput(panel, textEntry)

    panel:SetFont("DermaDefault")

    panel:SetTextColor(COL_WHITE)

    panel.Paint = function(control, w, h)

        RBox(4, 0, 0, w, h, COL_BTN)

        if textEntry then

            control:DrawTextEntryText(COL_WHITE, COL_ACCENT, COL_WHITE)

            if control:GetValue() == "" and not control:HasFocus() then

                draw.SimpleText(control:GetPlaceholderText() or "", "DermaDefault", 5, h / 2, COL_GREY, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            end

        end

    end

end



function FRAME:Init()

    self:SetSize(math.min(940, ScrW() - 32), math.min(760, ScrH() - 32))

    self:Center()

    self:SetTitle("")

    self:SetDraggable(true)

    self:ShowCloseButton(false)

    self:MakePopup()



    -- Close button

    local closeBtn = vgui.Create("DButton", self)

    closeBtn:SetSize(28, 28)

    closeBtn:SetPos(self:GetWide() - 34, 6)

    closeBtn:SetText("âœ•")

    closeBtn:SetFont("DermaDefaultBold")

    closeBtn:SetTextColor(COL_GREY)

    closeBtn.Paint = function(s, w, h)

        if s:IsHovered() then RBox(4, 0, 0, w, h, Color(80,30,30,200)) end

    end

    closeBtn.DoClick = function() self:Close() end



    -- Stable main navigation; numeric IDs retain the existing request routes.

    self.curTab = 1

    for order, item in ipairs({{1, "Players"}, {4, "Mutations"}, {5, "Events"}, {6, "Timers"}, {3, "Abnormalities"}, {2, "Server"}}) do

        local id = item[1]

        local tab = vgui.Create("DButton", self)

        tab:SetPos(16 + (order - 1) * ((self:GetWide() - 32) / 6), 70)

        tab:SetSize((self:GetWide() - 32) / 6 - 6, 34)

        tab:SetText(item[2]); tab:SetFont("DermaDefaultBold"); tab:SetTextColor(COL_WHITE)

        tab.Paint = function(s, w, h)

            RBox(4, 0, 0, w, h, self.curTab == id and COL_ACCENT or (s:IsHovered() and COL_BTN_HOVER or COL_BTN))

        end

        tab.DoClick = function() self:SetTab(id) end

    end

    MutatorPage.Setup(self)

    StaffPage.Setup(self)



    self.playerTools = vgui.Create("DPanel", self)

    self.playerTools:SetPos(16, 116); self.playerTools:SetSize(self:GetWide() - 32, 102)

    self.playerTools.Paint = nil

    local search = vgui.Create("DTextEntry", self.playerTools)

    self:StyleInput(search, true)

    self.playerSearchEntry = search

    search:SetPos(0, 0); search:SetSize(self:GetWide() - 248, 30)

    search:SetPlaceholderText("Search Steam name, character name or SteamID...")

    search.OnChange = function(s) self.playerSearch = string.lower(s:GetValue()); self:RefreshList(true) end

    local filter = vgui.Create("DComboBox", self.playerTools)

    self:StyleInput(filter)

    self.playerFilterBox = filter

    filter:SetPos(self:GetWide() - 238, 0); filter:SetSize(206, 30)

    filter:SetSortItems(false)

    for _, name in ipairs({"All players", "Alive", "Dead", "Current traitors", "Queued roles"}) do filter:AddChoice(name, name, name == "All players") end

    filter.OnSelect = function(_, _, _, value) self.playerFilter = value; self:RefreshList(true) end

    self.queueSummary = vgui.Create("DLabel", self.playerTools)

    self.queueSummary:SetPos(0, 38); self.queueSummary:SetSize(self.playerTools:GetWide(), 38)

    self.queueSummary:SetFont("DermaDefault"); self.queueSummary:SetTextColor(COL_GREY)

    self.queueSummary:SetWrap(true)

    local columns = vgui.Create("DLabel", self.playerTools)

    columns:SetPos(8, 82); columns:SetSize(340, 18)

    columns:SetText("PLAYER / CURRENT ROLE"); columns:SetTextColor(COL_GREY); columns:SetFont("DermaDefaultBold")

    local actionColumns = vgui.Create("DLabel", self.playerTools)

    actionColumns:SetPos(self.playerTools:GetWide() - 346, 82); actionColumns:SetSize(346, 18)

    actionColumns:SetText("NEXT ROUND                              LIVE ROUND")

    actionColumns:SetTextColor(COL_GREY); actionColumns:SetFont("DermaDefaultBold")



    self.abnoNav = vgui.Create("DPanel", self)

    self.abnoNav:SetPos(16, 116); self.abnoNav:SetSize(self:GetWide() - 32, 30); self.abnoNav.Paint = nil

    self.abnoNav:SetVisible(false)

    self.abnoSection = "System"

    for i, title in ipairs({"System", "Players", "Rituals", "Zones"}) do

        local name = title

        local tab = vgui.Create("DButton", self.abnoNav)

        tab:SetPos((i - 1) * 132, 0); tab:SetSize(124, 28); tab:SetText(name)

        tab:SetTextColor(COL_WHITE); tab:SetFont("DermaDefaultBold")

        tab.Paint = function(s, w, h) RBox(4, 0, 0, w, h, self.abnoSection == name and COL_ACCENT or (s:IsHovered() and COL_BTN_HOVER or COL_BTN)) end

        tab.DoClick = function() self.abnoSection = name; self.abnoScroll:GetVBar():SetScroll(0); self:RefreshAbno() end

    end



    -- Scroll (traitors tab)

    self.scroll = vgui.Create("DScrollPanel", self)

    self.scroll:SetPos(16, 222)

    self.scroll:SetSize(self:GetWide() - 32, self:GetTall() - 282)



    -- Server tab panel

    self.serverPanel = vgui.Create("DPanel", self)

    self.serverPanel:SetPos(16, 154)

    self.serverPanel:SetSize(self:GetWide() - 32, self:GetTall() - 214)

    self.serverPanel:SetVisible(false)

    self.serverPanel.Paint = nil



    -- Abnormal tab panel (scrolling; content built in RefreshAbno)

    self.abnoScroll = vgui.Create("DScrollPanel", self)

    self.abnoScroll:SetPos(16, 154)

    self.abnoScroll:SetSize(self:GetWide() - 32, self:GetTall() - 214)

    self.abnoScroll:SetVisible(false)



    local function serverLabel(text, y, bold)

        local label = vgui.Create("DLabel", self.serverPanel)

        label:SetPos(20, y); label:SetSize(self.serverPanel:GetWide() - 40, 30)

        label:SetText(text); label:SetWrap(true)

        label:SetFont(bold and "DermaDefaultBold" or "DermaDefault"); label:SetTextColor(bold and COL_WHITE or COL_GREY)

    end

    serverLabel("ROUND ASSISTANCE", 4, true)

    serverLabel("Deploy in Homicide, or force police into any active game mode.", 34)

    serverLabel("SERVER RESTART", 166, true)



    local policeBtn = vgui.Create("DButton", self.serverPanel)

    policeBtn:SetPos(20, 70)

    policeBtn:SetSize(200, 34)

    policeBtn:SetText("Deploy reinforcements")

    policeBtn:SetFont("DermaDefaultBold")

    policeBtn:SetTextColor(COL_WHITE)

    policeBtn.Paint = function(s, w, h)

        RBox(6, 0, 0, w, h, s:IsHovered() and Color(50, 110, 50) or Color(35, 80, 35))

    end

    policeBtn.DoClick = function()

        net.Start("traitoradmin_spawnpolice")

        net.SendToServer()

        surface.PlaySound("buttons/button14.wav")

    end



    local forcePoliceBtn = vgui.Create("DButton", self.serverPanel)
    forcePoliceBtn:SetPos(232, 70)
    forcePoliceBtn:SetSize(200, 34)
    forcePoliceBtn:SetText("Force reinforcements")
    forcePoliceBtn:SetFont("DermaDefaultBold")
    forcePoliceBtn:SetTextColor(COL_WHITE)
    forcePoliceBtn:SetTooltip("Override game-mode restrictions. Uses eligible dead players; SOE keeps National Guard.")
    forcePoliceBtn.Paint = function(s, w, h)
        RBox(6, 0, 0, w, h, s:IsHovered() and COL_BTN_FORCE_H or COL_BTN_FORCE)
    end
    forcePoliceBtn.DoClick = function()
        net.Start("traitoradmin_forcepolice")
        net.SendToServer()
        surface.PlaySound("buttons/button14.wav")
    end

    local restartBtn = vgui.Create("DButton", self.serverPanel)

    restartBtn:SetPos(20, 228)

    restartBtn:SetSize(200, 34)

    restartBtn:SetText("Restart server...")

    restartBtn:SetFont("DermaDefaultBold")

    restartBtn:SetTextColor(COL_WHITE)

    restartBtn.Paint = function(s, w, h)

        RBox(6, 0, 0, w, h, s:IsHovered() and COL_BTN_FORCE_H or COL_BTN_FORCE)

    end

    restartBtn.DoClick = function()

        local confirm = vgui.Create("DFrame")

        confirm:SetSize(340, 120)

        confirm:Center()

        confirm:SetTitle("Confirm Restart")

        confirm:MakePopup()

        confirm.Paint = function(s, w, h)

            RBox(6, 0, 0, w, h, COL_BG)

            RBox(6, 0, 0, w, 24, COL_HEADER)

        end



        local lbl = vgui.Create("DLabel", confirm)

        lbl:SetText("Restart the server? Players get a 30s warning.")

        lbl:SetFont("DermaDefaultBold")

        lbl:SetTextColor(COL_WHITE)

        lbl:SizeToContents()

        lbl:SetPos(170 - lbl:GetWide() / 2, 36)



        local yes = vgui.Create("DButton", confirm)

        yes:SetPos(10, 78)

        yes:SetSize(150, 28)

        yes:SetText("Yes, Restart")

        yes:SetTextColor(COL_WHITE)

        yes.Paint = function(s, w, h)

            RBox(4, 0, 0, w, h, s:IsHovered() and COL_BTN_FORCE_H or COL_BTN_FORCE)

        end

        yes.DoClick = function()

            net.Start("traitoradmin_restart")

            net.SendToServer()

            confirm:Close()

        end



        local no = vgui.Create("DButton", confirm)

        no:SetPos(180, 78)

        no:SetSize(150, 28)

        no:SetText("Cancel")

        no:SetTextColor(COL_WHITE)

        no.Paint = function(s, w, h)

            RBox(4, 0, 0, w, h, s:IsHovered() and COL_BTN_HOVER or COL_BTN)

        end

        no.DoClick = function() confirm:Close() end

    end



    local warnLbl = vgui.Create("DLabel", self.serverPanel)

    warnLbl:SetText("Restart starts a cancellable 30-second countdown.")

    warnLbl:SetTextColor(COL_GREY)

    warnLbl:SetFont("DermaDefault")

    warnLbl:SizeToContents()

    warnLbl:SetPos(20, 198)

    warnLbl:SetSize(self.serverPanel:GetWide() - 40, 26)

    warnLbl:SetWrap(true)



    -- Clear button

    local clearBtn = vgui.Create("DButton", self)

    self.clearForcedButton = clearBtn

    clearBtn:SetPos(10, self:GetTall() - 44)

    clearBtn:SetSize(160, 32)

    clearBtn:SetText("Clear queued traitors")

    clearBtn:SetFont("DermaDefaultBold")

    clearBtn:SetTextColor(COL_WHITE)

    clearBtn.Paint = function(s, w, h)

        RBox(5, 0, 0, w, h, s:IsHovered() and COL_BTN_CLEAR_H or COL_BTN_CLEAR)

    end

    clearBtn.DoClick = function()

        net.Start("traitoradmin_settraitor")

            net.WriteString("")

            net.WriteBool(true)

        net.SendToServer()

    end



    -- Refresh button

    local refreshBtn = vgui.Create("DButton", self)

    refreshBtn:SetPos(self:GetWide() - 110, self:GetTall() - 44)

    refreshBtn:SetSize(100, 32)

    refreshBtn:SetText("â†º Refresh")

    refreshBtn:SetFont("DermaDefaultBold")

    refreshBtn:SetTextColor(COL_WHITE)

    refreshBtn.Paint = function(s, w, h)

        RBox(5, 0, 0, w, h, s:IsHovered() and COL_BTN_HOVER or COL_BTN)

    end

    refreshBtn.DoClick = function()

        if self.curTab == 5 or self.curTab == 6 or (self.curTab == 2 and self.staffSection ~= "overview") then

            StaffPage.Request(self)

        elseif self.curTab == 4 then

            MutatorPage.Request()

        elseif self.curTab == 3 then

            net.Start("traitoradmin_abno_open")

            net.SendToServer()

        else

            net.Start("traitoradmin_open")

            net.SendToServer()

        end

    end



    self:RefreshList()

end



function FRAME:SetTab(n)

    self.curTab = n

    self.scroll:SetVisible(n == 1)

    self.serverPanel:SetVisible(n == 2 and self.staffSection == "overview")

    self.abnoScroll:SetVisible(n == 3)

    self.mutatorScroll:SetVisible(n == 4)

    self.clearForcedButton:SetVisible(n == 1)

    self.playerTools:SetVisible(n == 1)

    self.abnoNav:SetVisible(n == 3)

    self.mutatorNav:SetVisible(n == 4)

    StaffPage.SetTab(self)

    if n == 4 then

        MutatorPage.Request()

        MutatorPage.Refresh(self)

    end

    if n == 3 then

        net.Start("traitoradmin_abno_open")

        net.SendToServer()

        self:RefreshAbno() -- draw what we have while fresh data rides in

    end

end



function FRAME:Paint(w, h)

    RBox(8, 0, 0, w, h, COL_BG)

    RBox(8, 0, 0, w, 60, COL_HEADER)

    surface.SetDrawColor(COL_ACCENT); surface.DrawRect(0, 0, w, 3)

    draw.SimpleText("TRAITOR ADMIN", "DermaLarge", 16, 14, COL_WHITE)

    draw.SimpleText("ZCITY  /  STAFF CONTROLS", "DermaDefault", 280, 25, COL_GREY)

    surface.SetDrawColor(COL_HEADER); surface.DrawRect(0, h - 52, w, 52)

    surface.SetDrawColor(COL_DIVIDER); surface.DrawRect(0, h - 52, w, 1)

    draw.SimpleText("F8 to close", "DermaDefault", w - 220, h - 34, COL_GREY)

end



function FRAME:RefreshList(resetScroll)

    if not IsValid(self.scroll) then return end

    local scrollPosition = resetScroll and 0 or self.scroll:GetVBar():GetScroll()

    self.scroll:Clear()

    local names = {}

    local function nameFor(sid)

        for _, d in ipairs(playerData) do if d.steamid == sid then return d.name end end

        return sid

    end

    for _, sid in ipairs(forcedSteamIDs) do names[#names + 1] = nameFor(sid) end

    self.queueSummary:SetText("Next traitors (" .. #forcedSteamIDs .. "/2): " .. (#names > 0 and table.concat(names, ", ") or "Random") .. "\nNext Homelander: " .. (forcedHomelander ~= "" and nameFor(forcedHomelander) or "Random"))

    self.queueSummary:SetTooltip(self.queueSummary:GetText())

    local filtered = {}

    local query, filter = self.playerSearch or "", self.playerFilter or "All players"

    for _, d in ipairs(playerData) do

        local match = string.find(string.lower(d.name .. " " .. (d.charname or "") .. " " .. d.steamid), query, 1, true)

        if match and (filter == "All players" or filter == "Alive" and d.alive or filter == "Dead" and not d.alive

            or filter == "Current traitors" and d.istraitor or filter == "Queued roles" and (d.isforced or d.ishomelander)) then

            filtered[#filtered + 1] = d

        end

    end

    table.sort(filtered, function(a, b) return string.lower(a.name) < string.lower(b.name) end)



    if #filtered == 0 then

        local lbl = vgui.Create("DLabel", self.scroll)

        lbl:SetText("No matching players. Clear the filter or refresh.")

        lbl:SetTextColor(COL_GREY)

        lbl:SetFont("DermaDefaultBold")

        lbl:SizeToContents()

        lbl:SetPos(self:GetWide() / 2 - lbl:GetWide() / 2, 40)

        return

    end



    local yOff = 0

    for i, data in ipairs(filtered) do

        local row = vgui.Create("DPanel", self.scroll)

        row:SetSize(self.scroll:GetWide() - 16, 76)

        row:SetPos(0, yOff)



        -- Avatar

        local av = vgui.Create("AvatarImage", row)

        av:SetSize(38, 38)

        av:SetPos(10, 16)

        av:SetSteamID(util.SteamIDTo64(data.steamid), 32)



        row.Paint = function(s, w, h)

            local bg = (i % 2 == 0) and COL_ROW or COL_ROW_ALT

            if data.istraitor then bg = COL_TRAITOR_DIM end

            if data.isforced  then bg = COL_FORCED_DIM  end

            surface.SetDrawColor(bg)

            surface.DrawRect(0, 0, w, h)



            if data.istraitor then

                surface.SetDrawColor(COL_TRAITOR)

                surface.DrawRect(0, 0, 3, h)

            elseif data.isforced then

                surface.SetDrawColor(COL_FORCED)

                surface.DrawRect(0, 0, 3, h)

            end



            local karmaVal = math.Round(data.karma or 100)

            draw.SimpleText("Karma " .. karmaVal, "DermaDefault", w - 440, 18, COL_GREY)

            local role = data.istraitor and (data.ismaintraitor and "MAIN TRAITOR" or "TRAITOR") or "NOT TRAITOR"

            draw.SimpleText((data.alive and "ALIVE" or "DEAD") .. "  /  " .. role, "DermaDefault", 56, 52, data.istraitor and Color(239, 117, 125) or COL_GREY)



            surface.SetDrawColor(COL_DIVIDER)

            surface.DrawRect(0, h - 1, w, 1)

        end



        local name = vgui.Create("DLabel", row)

        name:SetPos(56, 10); name:SetSize(row:GetWide() - 504, 20)

        name:SetText(data.name); name:SetTooltip(data.name .. " / " .. data.steamid)

        name:SetFont("DermaDefaultBold"); name:SetTextColor(COL_WHITE)

        local character = vgui.Create("DLabel", row)

        character:SetPos(56, 30); character:SetSize(row:GetWide() - 504, 18)

        character:SetText(data.charname or "Unknown"); character:SetTooltip(data.charname or "Unknown")

        character:SetFont("DermaDefault"); character:SetTextColor(COL_GREY)



        -- Set Next Round button (toggle add/remove)

        local btnNext = vgui.Create("DButton", row)

        btnNext:SetSize(104, 32)

        btnNext:SetPos(row:GetWide() - 340, 22)

        btnNext:SetFont("DermaDefault")

        btnNext:SetTextColor(COL_WHITE)

        btnNext:SetText(data.isforced and "âœ“ Traitor" or "+ Traitor")

        btnNext.Paint = function(s, w, h)

            local col = data.isforced and (s:IsHovered() and Color(180,120,0) or COL_FORCED) or (s:IsHovered() and COL_BTN_HOVER or COL_BTN)

            RBox(4, 0, 0, w, h, col)

        end

        local sid = data.steamid

        btnNext:SetTooltip("Toggle next-round traitor. Maximum two queued players.")

        btnNext.DoClick = function()

            if not data.isforced and #forcedSteamIDs >= 2 then

                surface.PlaySound("buttons/button10.wav")

                return

            end

            net.Start("traitoradmin_settraitor")

                net.WriteString(sid)

                net.WriteBool(false)

            net.SendToServer()

        end



        -- Set Homelander button (toggle)

        local btnHL = vgui.Create("DButton", row)

        btnHL:SetSize(116, 32)

        btnHL:SetPos(row:GetWide() - 228, 22)

        btnHL:SetFont("DermaDefault")

        btnHL:SetTextColor(COL_WHITE)

        btnHL:SetText(data.ishomelander and "âœ“ Homelander" or "+ Homelander")

        btnHL.Paint = function(s, w, h)

            local hlCol = Color(60, 100, 200)

            local hlColH = Color(80, 130, 230)

            local col = data.ishomelander and (s:IsHovered() and hlColH or hlCol) or (s:IsHovered() and COL_BTN_HOVER or COL_BTN)

            RBox(4, 0, 0, w, h, col)

        end

        btnHL.DoClick = function()

            net.Start("traitoradmin_sethomelander")

                net.WriteString(sid)

            net.SendToServer()

        end



        -- Force Now button

        local btnForce = vgui.Create("DButton", row)

        btnForce:SetSize(92, 32)

        btnForce:SetPos(row:GetWide() - 100, 22)

        btnForce:SetFont("DermaDefault")

        btnForce:SetTextColor(COL_WHITE)

        btnForce:SetText("Force Now")

        btnForce:SetEnabled(data.alive)

        btnForce.Paint = function(s, w, h)

            local col = not data.alive and Color(30,30,30,180) or (s:IsHovered() and COL_BTN_FORCE_H or COL_BTN_FORCE)

            RBox(4, 0, 0, w, h, col)

        end



        local uid = data.userid

        local dname = data.name

        btnForce.DoClick = function()

            if not data.alive then return end



            local confirm = vgui.Create("DFrame")

            confirm:SetSize(300, 110)

            confirm:Center()

            confirm:SetTitle("Confirm")

            confirm:MakePopup()

            confirm.Paint = function(s, w, h)

                RBox(6, 0, 0, w, h, COL_BG)

                RBox(6, 0, 0, w, 24, COL_HEADER)

            end



            local lbl = vgui.Create("DLabel", confirm)

            lbl:SetText("Force " .. dname .. " as traitor now?")

            lbl:SetFont("DermaDefaultBold")

            lbl:SetTextColor(COL_WHITE)

            lbl:SizeToContents()

            lbl:SetPos(150 - lbl:GetWide() / 2, 32)



            local yes = vgui.Create("DButton", confirm)

            yes:SetPos(10, 68)

            yes:SetSize(130, 28)

            yes:SetText("Yes, Force Now")

            yes:SetTextColor(COL_WHITE)

            yes.Paint = function(s, w, h)

                RBox(4, 0, 0, w, h, s:IsHovered() and COL_BTN_FORCE_H or COL_BTN_FORCE)

            end

            yes.DoClick = function()

                net.Start("traitoradmin_forcenow")

                    net.WriteInt(uid, 16)

                net.SendToServer()

                confirm:Close()

                timer.Simple(0.5, function()

                    net.Start("traitoradmin_open")

                    net.SendToServer()

                end)

            end



            local no = vgui.Create("DButton", confirm)

            no:SetPos(155, 68)

            no:SetSize(130, 28)

            no:SetText("Cancel")

            no:SetTextColor(COL_WHITE)

            no.Paint = function(s, w, h)

                RBox(4, 0, 0, w, h, s:IsHovered() and COL_BTN_HOVER or COL_BTN)

            end

            no.DoClick = function() confirm:Close() end

        end



        yOff = yOff + 80

    end

    self.scroll:InvalidateLayout(true)

    self.scroll:GetVBar():SetScroll(scrollPosition)

end



-- =====================================================================

-- ABNORMAL TAB

-- Rebuilt only when data arrives or the tab is opened - no Think hooks,

-- no polling; every button fires one net message and the server answers

-- with fresh data.

-- =====================================================================

local COL_ABNO   = Color(226, 119, 128)

local COL_ON     = Color(50, 110, 50)

local COL_ON_H   = Color(70, 140, 70)

local COL_OFF    = Color(70, 35, 35)

local COL_OFF_H  = Color(95, 50, 50)



local function abnoBtn(parent, x, y, w, h, label, isOn, onClick)

    local b = vgui.Create("DButton", parent)

    b:SetPos(x, y)

    b:SetSize(w, h)

    b:SetText(label)

    b:SetFont("DermaDefault")

    b:SetTextColor(COL_WHITE)

    b.Paint = function(s, bw, bh)

        local col

        if isOn == true then col = s:IsHovered() and COL_ON_H or COL_ON

        elseif isOn == false then col = s:IsHovered() and COL_OFF_H or COL_OFF

        else col = s:IsHovered() and COL_BTN_HOVER or COL_BTN end

        RBox(4, 0, 0, bw, bh, col)

    end

    b.DoClick = function()

        surface.PlaySound("buttons/button14.wav")

        onClick()

    end

    return b

end



local function abnoHeader(parent, y, text)

    local lbl = vgui.Create("DLabel", parent)

    lbl:SetText(text)

    lbl:SetFont("DermaDefaultBold")

    lbl:SetTextColor(COL_ABNO)

    lbl:SizeToContents()

    lbl:SetPos(12, y)

    return y + 20

end



function FRAME:RefreshAbno()

    if not IsValid(self.abnoScroll) then return end

    local scrollPosition = self.abnoScroll:GetVBar():GetScroll()

    self.abnoScroll:Clear()

    local W = self.abnoScroll:GetWide()



    if not abnoData then

        local lbl = vgui.Create("DLabel", self.abnoScroll)

        lbl:SetText("Loading...")

        lbl:SetTextColor(COL_GREY)

        lbl:SetFont("DermaDefaultBold")

        lbl:SizeToContents()

        lbl:SetPos(W / 2 - lbl:GetWide() / 2, 40)

        return

    end



    local d = abnoData

    local canvas = vgui.Create("DPanel", self.abnoScroll)

    canvas:SetWide(W - 16)

    canvas.Paint = nil

    local y = 6



    if self.abnoSection == "System" then

    -- ---- SYSTEM ----

    y = abnoHeader(canvas, y, "SYSTEM")

    abnoBtn(canvas, 12, y, 150, 26, d.enabled and "Abnormalties: ON" or "Abnormalties: OFF", d.enabled, function() AbnoAction("toggle") end)

    abnoBtn(canvas, 168, y, 120, 26, d.swarm and "Swarm: ON" or "Swarm: OFF", d.swarm, function() AbnoAction("swarm") end)

    abnoBtn(canvas, 294, y, 120, 26, d.funmode and "FunMode: ON" or "FunMode: OFF", d.funmode, function() AbnoAction("funmode") end)

    y = y + 32

    abnoBtn(canvas, 12, y, 118, 24, "Re-roll letters", nil, function() AbnoAction("reroll") end)

    abnoBtn(canvas, 136, y, 110, 24, "Clear all zones", nil, function() AbnoAction("clearzones") end)

    abnoBtn(canvas, 252, y, 118, 24, "Hot zone HERE", nil, function() AbnoAction("zonehere") end)

    abnoBtn(canvas, 376, y, 130, 24, d.symptoms and "Symptoms: ON" or "Symptoms: OFF", d.symptoms, function() AbnoAction("symptoms") end)

    y = y + 30

    local status = vgui.Create("DLabel", canvas)

    local hotN = 0

    for _, z in ipairs(d.zones or {}) do if z.hot then hotN = hotN + 1 end end

    status:SetText(("live: %s  â€¢  zones: %d (%d hot)  â€¢  hot letters: %d"):format(

        d.live and "yes" or "no", #(d.zones or {}), hotN, d.hotchars or 0))

    status:SetTextColor(d.enabled == d.live and COL_GREY or Color(220, 160, 60))

    status:SetFont("DermaDefault")

    status:SizeToContents()

    status:SetPos(12, y)

    y = y + 24



    end

    if self.abnoSection == "Rituals" then

    -- ---- CONJURE / PHRASES ----

    y = abnoHeader(canvas, y, "CONJURE AT CROSSHAIR  /  BLOOD RITE  /  PHRASES")

    abnoBtn(canvas, 12, y, 96, 24, "Equalizer", nil, function() AbnoAction("conjure", 0, "equalizer") end)

    abnoBtn(canvas, 112, y, 96, 24, "Bleed Musket", nil, function() AbnoAction("conjure", 0, "musket") end)

    abnoBtn(canvas, 212, y, 96, 24, "Thauma Arm", nil, function() AbnoAction("conjure", 0, "arm") end)

    abnoBtn(canvas, 312, y, 118, 24, "BLOOD RITE HERE", false, function() AbnoAction("bloodrite") end)

    y = y + 30

    -- meaning row: CLICK SELECTS the meaning (highlight); "To me" prints

    -- the phrase to you; each player row's Whisper sends it to THEM

    self.selMeaning = self.selMeaning or "ritual"

    local mx = 12

    for _, meaning in ipairs({"harm", "ritual", "shield", "help", "sacrifice"}) do

        local mw = 12 + 7 * #meaning

        local m = meaning

        abnoBtn(canvas, mx, y, mw, 22, meaning, self.selMeaning == m, function()

            self.selMeaning = m

            self:RefreshAbno()

        end)

        mx = mx + mw + 6

    end

    abnoBtn(canvas, mx + 4, y, 58, 22, "To me", nil, function() AbnoAction("phrase", 0, self.selMeaning) end)

    y = y + 30



    -- ---- RITUALS (direct cast) ----

    y = abnoHeader(canvas, y, "CAST A RITUAL  (no zone, pattern, or resources needed)")

    local combo = vgui.Create("DComboBox", canvas)

    self:StyleInput(combo)

    combo:SetPos(12, y)

    combo:SetSize(190, 22)

    combo:SetSortItems(false)

    local chose = false

    for _, p in ipairs(d.players or {}) do

        if p.alive then

            local sel = (self.abnoTarget == p.userid)

            combo:AddChoice(p.name, p.userid, sel)

            if sel then chose = true end

        end

    end

    if not chose then combo:SetValue("target player...") end

    combo.OnSelect = function(_, _, _, uid) self.abnoTarget = uid end



    local costs = vgui.Create("DCheckBoxLabel", canvas)

    costs:SetPos(210, y + 3)

    costs:SetText("apply Balance costs")

    costs:SetTextColor(COL_GREY)

    costs:SetChecked(self.abnoCosts == true)

    costs.OnChange = function(_, val) self.abnoCosts = val end

    y = y + 28



    local function castBtn(x, w, label, ritual, needsTarget)

        abnoBtn(canvas, x, y, w, 24, label, nil, function()

            if needsTarget and not self.abnoTarget then

                chat.AddText(Color(150, 0, 0), "[Abno] pick a target player first")

                return

            end

            AbnoAction("cast", self.abnoTarget or 0, ritual .. ":" .. (self.abnoCosts and "1" or "0"))

        end)

    end

    castBtn(12, 62, "Heal", "heal", true)

    castBtn(78, 88, "Invisibility", "invis", true)

    castBtn(170, 82, "Broadcast", "bcast", true)

    castBtn(256, 158, "Resurrect nearest body", "res", false)

    y = y + 30

    local castNote = vgui.Create("DLabel", canvas)

    castNote:SetText("Resurrect targets the closest corpse within 500u of YOU. Swarm roll follows the Swarm toggle.")

    castNote:SetTextColor(COL_GREY)

    castNote:SetFont("DermaDefault")

    castNote:SizeToContents()

    castNote:SetPos(12, y)

    y = y + 24



    end

    if self.abnoSection == "Players" then

    -- ---- PLAYERS ----

    y = abnoHeader(canvas, y, "PLAYERS  (Balance / Blood / Equalizers / Punish)")

    for i, p in ipairs(d.players or {}) do

        local row = vgui.Create("DPanel", canvas)

        row:SetPos(0, y)

        row:SetSize(W - 16, 84)

        row.Paint = function(s, rw, rh)

            surface.SetDrawColor((i % 2 == 0) and COL_ROW or COL_ROW_ALT)

            surface.DrawRect(0, 0, rw, rh)

            local nameCol = p.alive and COL_WHITE or COL_DEAD

            

            local balCol = COL_GREY

            if math.abs(p.bal or 0) >= 300 then balCol = Color(220, 100, 100)

            elseif math.abs(p.bal or 0) >= 20 then balCol = Color(220, 160, 60) end

            draw.SimpleText(("Bal %d   Bld %d   Eq %d   Pun %d"):format(p.bal or 0, p.blood or 0, p.eq or 0, p.pun or 0),

                "DermaDefault", 10, 28, balCol)

            surface.SetDrawColor(COL_DIVIDER)

            surface.DrawRect(0, rh - 1, rw, 1)

        end



        local name = vgui.Create("DLabel", row)

        name:SetPos(10, 4); name:SetSize(W - 48, 20); name:SetText(p.name .. (p.swm and "  [SWARM]" or ""))

        name:SetTooltip(p.name); name:SetFont("DermaDefaultBold"); name:SetTextColor(COL_WHITE)

        local uid = p.userid

        local entry = vgui.Create("DTextEntry", row)

        self:StyleInput(entry, true)

        entry:SetPos(10, 52)

        entry:SetSize(48, 22)

        entry:SetNumeric(true)

        entry:SetPlaceholderText("bal")

        abnoBtn(row, 62, 52, 34, 22, "Set", nil, function()

            local v = tonumber(entry:GetValue())

            if v then AbnoAction("setbal", uid, tostring(v)) end

        end)

        abnoBtn(row, 100, 52, 40, 22, "+100", nil, function() AbnoAction("addbal", uid, "100") end)

        abnoBtn(row, 144, 52, 40, 22, "-100", nil, function() AbnoAction("addbal", uid, "-100") end)

        abnoBtn(row, 188, 52, 56, 22, "+5k Bld", nil, function() AbnoAction("blood", uid, "5000") end)

        abnoBtn(row, 248, 52, 52, 22, "+500 Eq", nil, function() AbnoAction("eq", uid, "500") end)

        abnoBtn(row, 304, 52, 50, 22, "ClrPun", nil, function() AbnoAction("clearpunish", uid) end)

        abnoBtn(row, 358, 52, 46, 22, "Pages", nil, function() AbnoAction("unlock", uid) end)

        if p.swm then

            abnoBtn(row, 408, 52, 44, 22, "Cure", true, function() AbnoAction("cure", uid) end)

        else

            abnoBtn(row, 408, 52, 44, 22, "Infect", false, function() AbnoAction("infect", uid) end)

        end

        abnoBtn(row, 456, 52, 60, 22, "Whisper", nil, function()

            AbnoAction("whisperto", uid, self.selMeaning or "ritual")

        end)

        y = y + 88

    end

    y = y + 8



    end

    if self.abnoSection == "Zones" then

    -- ---- ZONES ----

    abnoBtn(canvas, 12, y, 160, 28, "Hot zone HERE", nil, function() AbnoAction("zonehere") end)

    abnoBtn(canvas, 180, y, 160, 28, "Clear all zones", nil, function() AbnoAction("clearzones") end)

    y = y + 38

    y = abnoHeader(canvas, y, "ZONES")

    if #(d.zones or {}) == 0 then

        local lbl = vgui.Create("DLabel", canvas)

        lbl:SetText("No zones. Chanting creates them, or use Hot zone HERE.")

        lbl:SetTextColor(COL_GREY)

        lbl:SizeToContents()

        lbl:SetPos(12, y)

        y = y + 22

    end

    for i, z in ipairs(d.zones or {}) do

        local row = vgui.Create("DPanel", canvas)

        row:SetPos(0, y)

        row:SetSize(W - 16, 28)

        row.Paint = function(s, rw, rh)

            surface.SetDrawColor((i % 2 == 0) and COL_ROW or COL_ROW_ALT)

            surface.DrawRect(0, 0, rw, rh)

            local me = LocalPlayer()

            local dist = IsValid(me) and math.Round(me:GetPos():Distance(Vector(z.x, z.y, z.z))) or 0

            draw.SimpleText(("#%d %s  r%d  pts %d  blood %d  (%du away)"):format(

                z.id, z.hot and "HOT" or "   ", z.radius, z.points, z.blood, dist),

                "DermaDefault", 10, 7, z.hot and Color(220, 100, 100) or COL_GREY)

            surface.SetDrawColor(COL_DIVIDER)

            surface.DrawRect(0, rh - 1, rw, 1)

        end

        local zid = z.id

        if not z.hot then

            abnoBtn(row, W - 196, 3, 40, 22, "Hot", nil, function() AbnoAction("zonehot", zid) end)

        end

        abnoBtn(row, W - 152, 3, 44, 22, "+Rad", nil, function() AbnoAction("zonegrow", zid) end)

        abnoBtn(row, W - 104, 3, 36, 22, "TP", nil, function() AbnoAction("zonetp", zid) end)

        abnoBtn(row, W - 64, 3, 28, 22, "X", false, function() AbnoAction("zonedel", zid) end)

        y = y + 28

    end

    y = y + 8



    end

    if self.abnoSection == "System" then

    -- ---- SWARM ----

    y = abnoHeader(canvas, y, "SWARM")

    local st = d.swarmstats

    local lbl = vgui.Create("DLabel", canvas)

    lbl:SetText(st and ("NPCs: %d  â€¢  infected players: %d  â€¢  mothers: %d"):format(st.npcs, st.infected, st.mothers)

        or "Swarm system not loaded")

    lbl:SetTextColor(COL_GREY)

    lbl:SetFont("DermaDefault")

    lbl:SizeToContents()

    lbl:SetPos(12, y)

    y = y + 22

    abnoBtn(canvas, 12, y, 170, 26, "KILL ALL SWARM NPCS", false, function() AbnoAction("killswarm") end)

    y = y + 36



    end

    canvas:SetTall(y)

    self.abnoScroll:InvalidateLayout(true)

    self.abnoScroll:GetVBar():SetScroll(scrollPosition)

end



vgui.Register("TraitorAdmin_Frame", FRAME, "DFrame")



-- Idempotent open: a manual F8 bind and our built-in shortcut may both fire.

-- Repeated requests must not close the menu or discard edits/current tab.

local function OpenTraitorAdmin()

    local ply = LocalPlayer()

    if not IsValid(ply) then return end

    if not (ply:IsAdmin() or ply:IsSuperAdmin()) then

        ply:ChatPrint("[TraitorAdmin] Admins only.")

        return

    end



    if IsValid(TraitorAdminFrame) then

        TraitorAdminFrame:SetVisible(true)

        TraitorAdminFrame:MakePopup()

        TraitorAdminFrame:MoveToFront()

        return

    end



    TraitorAdminFrame = vgui.Create("TraitorAdmin_Frame")

    net.Start("traitoradmin_open")

    net.SendToServer()

end



-- Share one physical-key latch between polling and a manually bound command.

-- Whichever sees F8 first handles it; the other cannot reverse the same press.

hook.Remove("PlayerButtonDown", "traitoradmin_f8")

local f8Down = input.IsKeyDown(KEY_F8)

local lastF8Frame = -1

local function PollF8()

    local down = input.IsKeyDown(KEY_F8)

    local pressed = down and not f8Down

    f8Down = down -- Consume blocked presses too; never toggle later from a held key.

    if not pressed then return end

    lastF8Frame = FrameNumber()

    if not system.HasFocus() or gui.IsGameUIVisible() or gui.IsConsoleVisible() then return end

    local ply = LocalPlayer()

    if not IsValid(ply) or ply:IsTyping() then return end

    if not (ply:IsAdmin() or ply:IsSuperAdmin()) then return end

    if IsValid(TraitorAdminFrame) and TraitorAdminFrame:IsVisible() then

        TraitorAdminFrame:Close()

        TraitorAdminFrame = nil

    else

        OpenTraitorAdmin()

    end

end

concommand.Add("traitor_admin", function()

    -- An explicitly typed console command remains an open/focus command.

    if gui.IsConsoleVisible() then OpenTraitorAdmin() return end

    if input.IsKeyDown(KEY_F8) then PollF8() return end

    -- Covers a bind delivered after key-up in the same frame as the toggle.

    if lastF8Frame == FrameNumber() then return end

    OpenTraitorAdmin()

end, nil, "Open the Traitor admin panel (also F8): forced roles, reinforcements, mode votes, rotations, spawns, events and restarts. Admins only; the server checks every action.")

hook.Add("Think", "traitoradmin_f8", PollF8)

