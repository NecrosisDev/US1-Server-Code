if SERVER then
    AddCSLuaFile()
    return
end

local BASE_W, BASE_H = 1920, 1080

local function UIScale()
    return math.min(ScrW() / BASE_W, ScrH() / BASE_H)
end

local function ui(v)
    return math.max(1, math.floor(v * UIScale()))
end

local function rebuildPersistentPropFonts()
    surface.CreateFont("PPROP_Title", {
        font = "Bahnschrift",
        size = ui(28),
        weight = 800,
        antialias = true
    })

    surface.CreateFont("PPROP_Header", {
        font = "Bahnschrift",
        size = ui(18),
        weight = 700,
        antialias = true
    })

    surface.CreateFont("PPROP_Row", {
        font = "Bahnschrift",
        size = ui(17),
        weight = 500,
        antialias = true
    })

    surface.CreateFont("PPROP_Button", {
        font = "Bahnschrift",
        size = ui(16),
        weight = 700,
        antialias = true
    })
end

rebuildPersistentPropFonts()

hook.Add("OnScreenSizeChanged", "PersistentProps_RebuildFonts", function()
    rebuildPersistentPropFonts()
end)

local COL_BG = Color(8, 8, 8, 235)
local COL_BG2 = Color(18, 18, 18, 235)
local COL_BG3 = Color(30, 30, 30, 235)
local COL_RED = Color(190, 20, 20, 230)
local COL_RED_SOFT = Color(255, 45, 45, 90)
local COL_WHITE = Color(240, 240, 240)
local COL_MUTED = Color(145, 145, 145)

local function drawOutlinedRect(x, y, w, h, col, thick)
    surface.SetDrawColor(col)
    surface.DrawOutlinedRect(x, y, w, h, thick or 1)
end

local function blurPanel(panel, a)
    if hg and hg.DrawBlur then
        hg.DrawBlur(panel, 5, 1, a or 120)
    else
        surface.SetDrawColor(0, 0, 0, a or 120)
        surface.DrawRect(0, 0, panel:GetWide(), panel:GetTall())
    end
end

local PANEL_OPEN

local function createButton(parent, txt, dock, fn)
    local btn = vgui.Create("DButton", parent)
    btn:Dock(dock or LEFT)
    btn:DockMargin(0, 0, ui(8), 0)
    btn:SetWide(ui(140))
    btn:SetText("")
    btn.DoClick = fn
    btn.Paint = function(self, w, h)
        surface.SetDrawColor(0, 0, 0, 155)
        surface.DrawRect(0, 0, w, h)
        drawOutlinedRect(0, 0, w, h, COL_RED_SOFT, ui(2))
        draw.SimpleText(txt, "PPROP_Button", w / 2, h / 2, COL_WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    return btn
end

local function openPersistentPropsMenu(rows, mapName)
    if IsValid(PANEL_OPEN) then
        PANEL_OPEN:Remove()
        PANEL_OPEN = nil
    end

    local frameClass = vgui.GetControlTable("ZFrame") and "ZFrame" or "DFrame"
    local fr = vgui.Create(frameClass)
    PANEL_OPEN = fr

    fr:SetSize(math.min(ui(1200), ScrW() * 0.88), math.min(ui(760), ScrH() * 0.88))
    fr:Center()
    fr:MakePopup()
    fr:SetKeyboardInputEnabled(false)

    if fr.SetTitle then fr:SetTitle("") end
    if fr.ShowCloseButton then fr:ShowCloseButton(false) end

    fr.Paint = function(self, w, h)
        blurPanel(self, 100)
        surface.SetDrawColor(COL_BG)
        surface.DrawRect(0, 0, w, h)
        drawOutlinedRect(0, 0, w, h, COL_RED, ui(2))
        draw.SimpleText("PERSISTENT PROP MANAGER", "PPROP_Title", ui(18), ui(14), COL_WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("Map: " .. tostring(mapName or game.GetMap()), "PPROP_Header", ui(20), ui(48), COL_MUTED, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    local topBar = vgui.Create("DPanel", fr)
    topBar:SetPos(ui(16), ui(80))
    topBar:SetSize(fr:GetWide() - ui(32), ui(36))
    topBar.Paint = function() end

    createButton(topBar, "Refresh", LEFT, function()
        net.Start("PersistentProps_RequestList")
        net.SendToServer()
    end)

    createButton(topBar, "Reload All", LEFT, function()
        net.Start("PersistentProps_ReloadAll")
        net.SendToServer()
    end)

    if LocalPlayer():IsSuperAdmin() then
        createButton(topBar, "Wipe Map", LEFT, function()
            Derma_Query(
                "Wipe all persistent props for this map?",
                "Confirm Wipe",
                "Yes", function()
                    net.Start("PersistentProps_WipeMap")
                    net.SendToServer()
                end,
                "No"
            )
        end)
    end

    local closeBtn = createButton(topBar, "Close", RIGHT, function()
        if IsValid(fr) then
            fr:Remove()
        end
    end)
    closeBtn:SetWide(ui(120))

    local list = vgui.Create("DScrollPanel", fr)
    list:SetPos(ui(16), ui(124))
    list:SetSize(fr:GetWide() - ui(32), fr:GetTall() - ui(140))
    list.Paint = function(self, w, h)
        surface.SetDrawColor(0, 0, 0, 120)
        surface.DrawRect(0, 0, w, h)
        drawOutlinedRect(0, 0, w, h, COL_RED_SOFT, ui(2))
    end

    local bar = list:GetVBar()
    function bar:Paint() end
    function bar.btnUp:Paint(w, h)
        surface.SetDrawColor(0, 0, 0, 150)
        surface.DrawRect(0, 0, w, h)
    end
    function bar.btnDown:Paint(w, h)
        surface.SetDrawColor(0, 0, 0, 150)
        surface.DrawRect(0, 0, w, h)
    end
    function bar.btnGrip:Paint(w, h)
        surface.SetDrawColor(40, 40, 40, 220)
        surface.DrawRect(0, 0, w, h)
    end
    bar:SetWide(ui(10))

    for _, row in ipairs(rows or {}) do
        local pnl = vgui.Create("DPanel", list)
        pnl:Dock(TOP)
        pnl:DockMargin(ui(10), ui(10), ui(10), 0)
        pnl:SetTall(ui(72))
        pnl.Paint = function(self, w, h)
            surface.SetDrawColor(COL_BG2)
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(COL_BG3)
            surface.DrawRect(0, h * 0.55, w, h * 0.45)
            drawOutlinedRect(0, 0, w, h, COL_RED_SOFT, ui(2))

            local modelText = row.model or "unknown"
            local pos = row.pos or vector_origin

            draw.SimpleText(modelText, "PPROP_Row", ui(12), ui(10), COL_WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText("ID: " .. tostring(row.id), "PPROP_Header", ui(12), ui(36), COL_MUTED, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(string.format("Pos: %.0f %.0f %.0f", pos.x, pos.y, pos.z), "PPROP_Header", ui(220), ui(36), COL_MUTED, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(row.frozen and "Frozen" or "Unfrozen", "PPROP_Header", w - ui(280), ui(10), COL_WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end

        local tp = vgui.Create("DButton", pnl)
        tp:SetSize(ui(90), ui(28))
        tp:SetPos(pnl:GetWide() - ui(200), ui(22))
        tp:SetText("")
        tp.DoClick = function()
            net.Start("PersistentProps_TeleportTo")
            net.WriteString(row.id)
            net.SendToServer()
        end
        tp.Paint = function(self, w, h)
            surface.SetDrawColor(0, 0, 0, 180)
            surface.DrawRect(0, 0, w, h)
            drawOutlinedRect(0, 0, w, h, COL_RED_SOFT, 1)
            draw.SimpleText("Teleport", "PPROP_Button", w / 2, h / 2, COL_WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        local rm = vgui.Create("DButton", pnl)
        rm:SetSize(ui(90), ui(28))
        rm:SetPos(pnl:GetWide() - ui(100), ui(22))
        rm:SetText("")
        rm.DoClick = function()
            Derma_Query(
                "Remove persistent prop " .. tostring(row.id) .. "?",
                "Confirm Remove",
                "Yes", function()
                    net.Start("PersistentProps_RemoveID")
                    net.WriteString(row.id)
                    net.SendToServer()
                end,
                "No"
            )
        end
        rm.Paint = function(self, w, h)
            surface.SetDrawColor(0, 0, 0, 180)
            surface.DrawRect(0, 0, w, h)
            drawOutlinedRect(0, 0, w, h, COL_RED, 1)
            draw.SimpleText("Remove", "PPROP_Button", w / 2, h / 2, COL_WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        pnl.PerformLayout = function(self, w, h)
            tp:SetPos(w - ui(200), ui(22))
            rm:SetPos(w - ui(100), ui(22))
        end
    end
end

net.Receive("PersistentProps_RequestList", function()
    net.Start("PersistentProps_RequestList")
    net.SendToServer()
end)

net.Receive("PersistentProps_SendList", function()
    local mapName = net.ReadString()
    local count = net.ReadUInt(16)
    local rows = {}

    for i = 1, count do
        rows[i] = {
            id = net.ReadString(),
            model = net.ReadString(),
            pos = net.ReadVector(),
            ang = net.ReadAngle(),
            frozen = net.ReadBool()
        }
    end

    openPersistentPropsMenu(rows, mapName)
end)

concommand.Add("persistent_props_menu", function()
    net.Start("PersistentProps_RequestList")
    net.SendToServer()
end)