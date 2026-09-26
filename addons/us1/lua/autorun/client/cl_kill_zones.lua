-- Kill Zones admin menu (open with: zkill_menu)
if not CLIENT then return end

local zones = {}
local hasCorner1 = false
local showZones = false

local COL_BG      = Color(28, 28, 32, 245)
local COL_HEADER  = Color(22, 22, 26)
local COL_ACCENT  = Color(200, 50, 50)
local COL_BTN     = Color(55, 55, 62)
local COL_BTN_H   = Color(75, 75, 85)
local COL_GREEN   = Color(60, 140, 70)
local COL_GREEN_H = Color(80, 170, 90)
local COL_RED     = Color(150, 45, 45)
local COL_RED_H   = Color(180, 60, 60)
local COL_WHITE   = Color(235, 235, 235)
local COL_GREY    = Color(150, 150, 155)
local COL_DIVIDER = Color(60, 60, 68)

local function RBox(r, x, y, w, h, col)
    draw.RoundedBox(r, x, y, w, h, col)
end

local function SendAction(action, id)
    net.Start("zkill_action")
        net.WriteString(action)
        if action == "remove" then net.WriteInt(id, 16) end
    net.SendToServer()
end

local function StyleButton(btn, colNormal, colHover)
    btn:SetFont("DermaDefault")
    btn:SetTextColor(COL_WHITE)
    btn.Paint = function(s, w, h)
        RBox(4, 0, 0, w, h, s:IsHovered() and colHover or colNormal)
    end
end

local function BuildMenu()
    if IsValid(KillZoneMenu) then KillZoneMenu:Remove() end

    local fw, fh = 460, 480
    KillZoneMenu = vgui.Create("DFrame")
    KillZoneMenu:SetSize(fw, fh)
    KillZoneMenu:Center()
    KillZoneMenu:SetTitle("")
    KillZoneMenu:MakePopup()
    KillZoneMenu:ShowCloseButton(true)
    KillZoneMenu.Paint = function(self, w, h)
        RBox(6, 0, 0, w, h, COL_BG)
        RBox(6, 0, 0, w, 64, COL_HEADER)
        surface.SetDrawColor(COL_ACCENT)
        surface.DrawRect(0, 0, w, 3)
        draw.SimpleText("KILL ZONES", "DermaLarge", 16, 14, COL_ACCENT, TEXT_ALIGN_LEFT)
        draw.SimpleText(game.GetMap() .. "  •  " .. #zones .. " zone(s)" .. (hasCorner1 and "  •  CORNER 1 SET" or ""), "DermaDefault", 16, 42, hasCorner1 and Color(120, 220, 120) or COL_GREY, TEXT_ALIGN_LEFT)
    end

    -- Top action buttons
    local btnC1 = vgui.Create("DButton", KillZoneMenu)
    btnC1:SetSize(105, 30)
    btnC1:SetPos(12, 72)
    btnC1:SetText("Set Corner 1")
    StyleButton(btnC1, COL_BTN, COL_BTN_H)
    btnC1.DoClick = function() SendAction("corner1") end

    local btnC2 = vgui.Create("DButton", KillZoneMenu)
    btnC2:SetSize(105, 30)
    btnC2:SetPos(124, 72)
    btnC2:SetText("Create Zone")
    StyleButton(btnC2, COL_GREEN, COL_GREEN_H)
    btnC2.DoClick = function() SendAction("corner2") end

    local btnClear = vgui.Create("DButton", KillZoneMenu)
    btnClear:SetSize(90, 30)
    btnClear:SetPos(236, 72)
    btnClear:SetText("Clear All")
    StyleButton(btnClear, COL_RED, COL_RED_H)
    btnClear.DoClick = function()
        Derma_Query("Remove ALL kill zones on this map?", "Kill Zones",
            "Yes", function() SendAction("clear") end,
            "No", function() end)
    end

    -- Show zones toggle
    local chk = vgui.Create("DCheckBoxLabel", KillZoneMenu)
    chk:SetPos(340, 79)
    chk:SetText("Show zones")
    chk:SetTextColor(COL_WHITE)
    chk:SetValue(showZones)
    chk:SizeToContents()
    chk.OnChange = function(_, val) showZones = val end

    -- Zone list
    local scroll = vgui.Create("DScrollPanel", KillZoneMenu)
    scroll:SetPos(12, 112)
    scroll:SetSize(fw - 24, fh - 124)
    scroll.Paint = function(self, w, h)
        RBox(4, 0, 0, w, h, Color(20, 20, 24, 200))
    end

    if #zones == 0 then
        local lbl = vgui.Create("DLabel", scroll)
        lbl:SetText("No zones on this map.\nStand at one corner, hit Set Corner 1,\nwalk to the opposite corner, hit Create Zone.")
        lbl:SetTextColor(COL_GREY)
        lbl:SetFont("DermaDefaultBold")
        lbl:SetContentAlignment(5)
        lbl:SetSize(fw - 24, 80)
        lbl:SetPos(0, 20)
    end

    for i, z in ipairs(zones) do
        local row = vgui.Create("DPanel", scroll)
        row:SetTall(48)
        row:Dock(TOP)
        row:DockMargin(4, 4, 4, 0)
        row.Paint = function(self, w, h)
            RBox(4, 0, 0, w, h, Color(38, 38, 44))
            draw.SimpleText("Zone #" .. i, "DermaDefaultBold", 12, 8, COL_WHITE, TEXT_ALIGN_LEFT)
            local size = z.max - z.min
            draw.SimpleText(string.format("size %d x %d x %d", size.x, size.y, size.z), "DermaDefault", 12, 26, COL_GREY, TEXT_ALIGN_LEFT)
            draw.SimpleText(string.format("center (%d, %d, %d)", (z.min.x + z.max.x) / 2, (z.min.y + z.max.y) / 2, (z.min.z + z.max.z) / 2), "DermaDefault", 160, 26, COL_GREY, TEXT_ALIGN_LEFT)
        end

        local btnGo = vgui.Create("DButton", row)
        btnGo:SetSize(60, 26)
        btnGo:Dock(RIGHT)
        btnGo:DockMargin(4, 11, 78, 11)
        btnGo:SetText("Look at")
        StyleButton(btnGo, COL_BTN, COL_BTN_H)
        btnGo.DoClick = function()
            local center = (z.min + z.max) / 2
            local ang = (center - LocalPlayer():EyePos()):Angle()
            LocalPlayer():SetEyeAngles(ang)
        end

        local btnDel = vgui.Create("DButton", row)
        btnDel:SetSize(66, 26)
        btnDel:SetPos(row:GetWide() - 74, 11)
        btnDel.PerformLayout = function(s) s:SetPos(row:GetWide() - 74, 11) end
        btnDel:SetText("Remove")
        StyleButton(btnDel, COL_RED, COL_RED_H)
        btnDel.DoClick = function() SendAction("remove", i) end
    end
end

net.Receive("zkill_zonelist", function()
    zones = net.ReadTable()
    hasCorner1 = net.ReadBool()
    BuildMenu()
end)

-- In-world zone rendering
hook.Add("PostDrawTranslucentRenderables", "KillZones_Render", function()
    if not showZones and not IsValid(KillZoneMenu) then return end
    if #zones == 0 then return end

    for i, z in ipairs(zones) do
        local center = (z.min + z.max) / 2
        local mins = z.min - center
        local maxs = z.max - center

        render.SetColorMaterial()
        render.DrawBox(center, angle_zero, mins, maxs, Color(255, 40, 40, 30))
        render.DrawWireframeBox(center, angle_zero, mins, maxs, Color(255, 60, 60, 200), true)
    end
end)

-- Label overlay while visible
hook.Add("HUDPaint", "KillZones_Labels", function()
    if not showZones and not IsValid(KillZoneMenu) then return end
    for i, z in ipairs(zones) do
        local center = (z.min + z.max) / 2
        local scr = center:ToScreen()
        if scr.visible then
            draw.SimpleTextOutlined("KILL ZONE #" .. i, "DermaDefaultBold", scr.x, scr.y, Color(255, 80, 80), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 220))
        end
    end
end)
