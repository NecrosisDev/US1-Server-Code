CreateConVar("sv_indicator_disable_hmcd", "0", {FCVAR_REPLICATED, FCVAR_ARCHIVE})
CreateConVar("sv_indicator_disable_path", "0", {FCVAR_REPLICATED, FCVAR_ARCHIVE})
CreateConVar("sv_indicator_disable_coop", "0", {FCVAR_REPLICATED, FCVAR_ARCHIVE})
CreateConVar("sv_indicator_disable_def", "0", {FCVAR_REPLICATED, FCVAR_ARCHIVE})
CreateConVar("sv_indicator_disable_as", "0", {FCVAR_REPLICATED, FCVAR_ARCHIVE})
CreateConVar("sv_indicator_disable_team", "0", {FCVAR_REPLICATED, FCVAR_ARCHIVE})
CreateConVar("sv_indicator_show_all_teams", "0", {FCVAR_REPLICATED, FCVAR_ARCHIVE})
CreateConVar("sv_indicator_enable_dm", "0", {FCVAR_REPLICATED, FCVAR_ARCHIVE})
CreateConVar("sv_indicator_enable_event", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE})
CreateConVar("sv_indicator_event_show_staff", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE})
CreateConVar("sv_indicator_event_show_player", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE})
CreateConVar("sv_indicator_spec_see_all", "0", {FCVAR_REPLICATED, FCVAR_ARCHIVE})

if SERVER then
    util.AddNetworkString("HMCD_SyncTraitors")
    util.AddNetworkString("Indicator_ChangeSVConVar")
    util.AddNetworkString("Indicator_CustomSet")
    util.AddNetworkString("Indicator_CustomUpdate")

    util.AddNetworkString("Indicator_OpenMenu")

    -- ZChat doesn't fire the client OnPlayerChat hook, so the !indicators
    -- chat trigger is relayed server-side through ZCity's real chat event
    hook.Add("HG_PlayerSay", "Indicator_ChatOpen", function(ply, text, rawtext)
        if istable(text) then text = text[1] or rawtext end
        if not IsValid(ply) or not isstring(text) then return end
        if string.Trim(string.lower(text)) ~= "!indicators" then return end
        net.Start("Indicator_OpenMenu")
        net.Send(ply)
    end)

    local CustomIndicators = {}

    function Octavu_SetCustomIndicatorSV(targetIdx, isSetting, text, r, g, b, visMode, adminIdx)
        if isSetting then
            CustomIndicators[targetIdx] = {text = text, color = Color(r, g, b), visMode = visMode or 0, adminIdx = adminIdx or 0}
        else
            CustomIndicators[targetIdx] = nil
        end

        net.Start("Indicator_CustomUpdate")
        net.WriteUInt(targetIdx, 16)
        net.WriteBool(isSetting)
        if isSetting then
            net.WriteString(text)
            net.WriteUInt(r, 8)
            net.WriteUInt(g, 8)
            net.WriteUInt(b, 8)
            net.WriteUInt(visMode or 0, 2)
            net.WriteUInt(adminIdx or 0, 16)
        end
        net.Broadcast()
    end

    net.Receive("Indicator_CustomSet", function(len, ply)
        if not (IsValid(ply) and ply:IsAdmin()) then return end
        
        local targetIdx = net.ReadUInt(16)
        local isSetting = net.ReadBool()

        if isSetting then
            local text = net.ReadString()
            local r, g, b = net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(8)
            local visMode = net.ReadUInt(2)
            Octavu_SetCustomIndicatorSV(targetIdx, true, text, r, g, b, visMode, ply:EntIndex())
        else
            Octavu_SetCustomIndicatorSV(targetIdx, false)
        end
    end)

    hook.Add("ZB_StartRound", "Indicator_CustomResetSV", function()
        CustomIndicators = {}
        net.Start("Indicator_CustomUpdate")
        net.WriteUInt(0, 16)
        net.WriteBool(false)
        net.Broadcast()
    end)

    hook.Add("PlayerDisconnected", "Indicator_CustomCleanupSV", function(ply)
        CustomIndicators[ply:EntIndex()] = nil
    end)

    -- a mode counts as homicide-family if it's hmcd itself OR carries a
    -- SubRoles table (modes built off hmcd inherit that structure) - this
    -- makes mass casualty and future hmcd-derived modes work automatically
    local function IsHomicideFamily(mode)
        if not mode then return false end
        return mode.name == "hmcd" or mode.SubRoles ~= nil
    end

    function HMCD_SyncTraitors_Func()
        if not CurrentRound then return end
        local mode = CurrentRound()
        if not IsHomicideFamily(mode) then return end

        local traitors, traitorFilter = {}, {}
        local sheriffs, sheriffFilter = {}, {}
        local police, policeFilter = {}, {}

        for _, ply in player.Iterator() do
            if ply.isTraitor then
                table.insert(traitors, ply:EntIndex())
                table.insert(traitorFilter, ply)
            elseif ply.isGunner then
                table.insert(sheriffs, ply:EntIndex())
                table.insert(sheriffFilter, ply)
            elseif ply.isPolice then
                table.insert(police, ply:EntIndex())
                table.insert(policeFilter, ply)
            end
        end

        local showAll = GetConVar("sv_indicator_show_all_teams"):GetBool()

        net.Start("HMCD_SyncTraitors")
        net.WriteUInt(4, 4)
        net.Broadcast()

        if #traitors > 0 then
            net.Start("HMCD_SyncTraitors")
            net.WriteUInt(1, 4)
            net.WriteUInt(#traitors, 8)
            for _, idx in ipairs(traitors) do net.WriteUInt(idx, 16) end
            if showAll then net.Broadcast() else net.Send(traitorFilter) end
        end

        if #sheriffs > 0 then
            net.Start("HMCD_SyncTraitors")
            net.WriteUInt(2, 4)
            net.WriteUInt(#sheriffs, 8)
            for _, idx in ipairs(sheriffs) do net.WriteUInt(idx, 16) end
            if showAll then net.Broadcast() else net.Send(sheriffFilter) end
        end

        if #police > 0 then
            net.Start("HMCD_SyncTraitors")
            net.WriteUInt(3, 4)
            net.WriteUInt(#police, 8)
            for _, idx in ipairs(police) do net.WriteUInt(idx, 16) end
            if showAll then net.Broadcast() else net.Send(policeFilter) end
        end
    end

    cvars.AddChangeCallback("sv_indicator_show_all_teams", function() HMCD_SyncTraitors_Func() end)

    hook.Add("ZB_StartRound", "Indicator_Sync", function() timer.Simple(2, HMCD_SyncTraitors_Func) end)

    -- rescan every 10s during live rounds so role assignments that land
    -- after round start (role picker, late changes) always get tags
    timer.Create("Indicator_PeriodicSync", 10, 0, function()
        if zb and zb.ROUND_STATE == 1 then
            HMCD_SyncTraitors_Func()
        end
    end)
    hook.Add("PlayerSpawn", "Indicator_SyncSpawn", function(ply)
        timer.Simple(2, function()
            if IsValid(ply) and (ply.isTraitor or ply.isGunner or ply.isPolice) then HMCD_SyncTraitors_Func() end
        end)
    end)

    hook.Add("ZB_EndRound", "Indicator_ResetRoles", function()
        for _, ply in player.Iterator() do
            ply.isTraitor, ply.isGunner, ply.isPolice = false, false, false
        end
    end)

    net.Receive("Indicator_ChangeSVConVar", function(len, ply)
        if IsValid(ply) and ply:IsSuperAdmin() then
            RunConsoleCommand(net.ReadString(), net.ReadString())
        end
    end)
end

if CLIENT then
    local cv_master_disable = CreateClientConVar("indicator_master_disable", "0", true, false)
    local cv_show_names = CreateClientConVar("indicator_show_names", "0", true, false)

    local cv_font = CreateClientConVar("indicator_font", "Bahnschrift", true, false)
    local cv_size = CreateClientConVar("indicator_size", "26", true, false)
    local cv_alpha = CreateClientConVar("indicator_opacity", "1.0", true, false)
    local cv_sat = CreateClientConVar("indicator_saturation", "1.0", true, false)
    local cv_pulse = CreateClientConVar("indicator_pulse", "0", true, false)

    local cv_en_hmcd = CreateClientConVar("indicator_en_hmcd", "1", true, false)
    local cv_en_path = CreateClientConVar("indicator_en_pathowogen", "1", true, false)
    local cv_en_coop = CreateClientConVar("indicator_en_coop", "1", true, false)
    local cv_en_def = CreateClientConVar("indicator_en_defense", "1", true, false)
    local cv_en_as = CreateClientConVar("indicator_en_as", "1", true, false)
    local cv_en_team = CreateClientConVar("indicator_en_team", "1", true, false)

    local sv_cv_hmcd = GetConVar("sv_indicator_disable_hmcd")
    local sv_cv_path = GetConVar("sv_indicator_disable_path")
    local sv_cv_coop = GetConVar("sv_indicator_disable_coop")
    local sv_cv_def  = GetConVar("sv_indicator_disable_def")
    local sv_cv_as   = GetConVar("sv_indicator_disable_as")
    local sv_cv_team = GetConVar("sv_indicator_disable_team")
    local sv_cv_showall = GetConVar("sv_indicator_show_all_teams")
    local sv_cv_dm   = GetConVar("sv_indicator_enable_dm")
    local sv_cv_ev   = GetConVar("sv_indicator_enable_event")
    local sv_cv_ev_staff = GetConVar("sv_indicator_event_show_staff")
    local sv_cv_ev_player = GetConVar("sv_indicator_event_show_player") 
    local sv_cv_spec = GetConVar("sv_indicator_spec_see_all")

    local CustomIndicators = {}

    net.Receive("Indicator_CustomUpdate", function()
        local targetIdx = net.ReadUInt(16)
        local isSetting = net.ReadBool()
        
        if targetIdx == 0 then
            CustomIndicators = {}
            return
        end

        if isSetting then
            local text = net.ReadString()
            local r, g, b = net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(8)
            local visMode = net.ReadUInt(2)
            local adminIdx = net.ReadUInt(16)
            CustomIndicators[targetIdx] = {text = text, color = Color(r, g, b), visMode = visMode, adminIdx = adminIdx}
        else
            CustomIndicators[targetIdx] = nil
        end
    end)

    properties.Add("indicator_add", {
        MenuLabel = "Set Custom Indicator",
        Order = 2000,
        MenuIcon = "icon16/tag_blue_add.png",
        Filter = function(self, ent, ply)
            return IsValid(ent) and ent:IsPlayer() and ply:IsAdmin() and not CustomIndicators[ent:EntIndex()]
        end,
        Action = function(self, ent)
            local frame = vgui.Create("DFrame")
            frame:SetSize(300, 410)
            frame:Center()
            frame:SetTitle("Set Custom Indicator")
            frame:MakePopup()

            local textEntry = vgui.Create("DTextEntry", frame)
            textEntry:Dock(TOP)
            textEntry:DockMargin(10, 10, 10, 10)
            textEntry:SetPlaceholderText("Enter custom text here...")

            local visLabel = vgui.Create("DLabel", frame)
            visLabel:Dock(TOP)
            visLabel:DockMargin(10, 0, 10, 0)
            visLabel:SetText("Who can see this?")
            
            local visCombo = vgui.Create("DComboBox", frame)
            visCombo:Dock(TOP)
            visCombo:DockMargin(10, 0, 10, 10)
            visCombo:AddChoice("Everyone", 0, true)
            visCombo:AddChoice("Same Team", 1)
            visCombo:AddChoice("Only Me (Admin)", 2)

            local colorMixer = vgui.Create("DColorMixer", frame)
            colorMixer:Dock(FILL)
            colorMixer:DockMargin(10, 0, 10, 10)
            colorMixer:SetPalette(true)
            colorMixer:SetAlphaBar(false)
            colorMixer:SetWangs(true)
            colorMixer:SetColor(Color(255, 255, 255))

            local btn = vgui.Create("DButton", frame)
            btn:Dock(BOTTOM)
            btn:DockMargin(10, 0, 10, 10)
            btn:SetText("Apply Indicator")
            btn.DoClick = function()
                local txt = textEntry:GetValue()
                if txt == "" then txt = "INDICATOR" end
                local col = colorMixer:GetColor()
                local _, visMode = visCombo:GetSelected()

                net.Start("Indicator_CustomSet")
                net.WriteUInt(ent:EntIndex(), 16)
                net.WriteBool(true)
                net.WriteString(txt)
                net.WriteUInt(col.r, 8)
                net.WriteUInt(col.g, 8)
                net.WriteUInt(col.b, 8)
                net.WriteUInt(visMode or 0, 2)
                net.SendToServer()

                frame:Remove()
            end
        end
    })

    properties.Add("indicator_remove", {
        MenuLabel = "Remove Custom Indicator",
        Order = 2001,
        MenuIcon = "icon16/tag_blue_delete.png",
        Filter = function(self, ent, ply)
            return IsValid(ent) and ent:IsPlayer() and ply:IsAdmin() and CustomIndicators[ent:EntIndex()]
        end,
        Action = function(self, ent)
            net.Start("Indicator_CustomSet")
            net.WriteUInt(ent:EntIndex(), 16)
            net.WriteBool(false)
            net.SendToServer()
        end
    })

    local function UpdateIndicatorFont()
        surface.CreateFont("IndicatorFont", {
            font = cv_font:GetString(),
            size = cv_size:GetInt(),
            weight = 800,
            outline = true,
            antialias = true
        })
    end
    
    cvars.AddChangeCallback("indicator_size", UpdateIndicatorFont)
    cvars.AddChangeCallback("indicator_font", UpdateIndicatorFont)
    UpdateIndicatorFont()

    local function OpenAdminIndicatorSettings()
        if IsValid(IndicatorAdminMenu) then IndicatorAdminMenu:Remove() end
        IndicatorAdminMenu = vgui.Create("DFrame")
        IndicatorAdminMenu:SetSize(280, 360)
        IndicatorAdminMenu:Center()
        IndicatorAdminMenu:SetTitle("")
        IndicatorAdminMenu:MakePopup()
        IndicatorAdminMenu:ShowCloseButton(false)

        IndicatorAdminMenu.Paint = function(self, w, h)
            surface.SetDrawColor(20, 20, 25, 250)
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(255, 255, 255, 20)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
            draw.SimpleText("SERVER OVERRIDES (ADMIN)", "DermaDefaultBold", 12, 10, color_white, 0, 0)
        end

        local close = vgui.Create("DButton", IndicatorAdminMenu)
        close:SetSize(28, 24)
        close:SetPos(IndicatorAdminMenu:GetWide() - 34, 6)
        close:SetText("X")
        close:SetTextColor(color_white)
        close.Paint = function(self, w, h)
            if self:IsHovered() then
                surface.SetDrawColor(200, 60, 60, 200)
                surface.DrawRect(0, 0, w, h)
            end
        end
        close.DoClick = function() IndicatorAdminMenu:Remove() end

        local content = vgui.Create("DScrollPanel", IndicatorAdminMenu)
        content:Dock(FILL)
        content:DockMargin(10, 10, 10, 10)

        local function AddSVCheckbox(parent, label, cvar)
            local cb = vgui.Create("DCheckBoxLabel", parent)
            cb:Dock(TOP) 
            cb:DockMargin(5, 5, 5, 5) 
            cb:SetText(label)
            cb:SetTextColor(color_white)
            
            local cv = GetConVar(cvar)
            cb:SetValue(cv and cv:GetBool() or false)
            cb.OnChange = function(s, val)
                net.Start("Indicator_ChangeSVConVar")
                net.WriteString(cvar)
                net.WriteString(val and "1" or "0")
                net.SendToServer()
            end
        end

        AddSVCheckbox(content, "Force Disable Homicide", "sv_indicator_disable_hmcd")
        AddSVCheckbox(content, "Force Disable Pathowogen", "sv_indicator_disable_path")
        AddSVCheckbox(content, "Force Disable CO-OP", "sv_indicator_disable_coop")
        AddSVCheckbox(content, "Force Disable NPC Defense", "sv_indicator_disable_def")
        AddSVCheckbox(content, "Force Disable Active Shooter", "sv_indicator_disable_as")
        AddSVCheckbox(content, "Force Disable Team Modes", "sv_indicator_disable_team")
        AddSVCheckbox(content, "Show All Teams", "sv_indicator_show_all_teams") 
        AddSVCheckbox(content, "Spectators & Dead see all", "sv_indicator_spec_see_all") 
        AddSVCheckbox(content, "Enable DM Player Indicators", "sv_indicator_enable_dm") 
        AddSVCheckbox(content, "Enable EVENT Player Indicators", "sv_indicator_enable_event") 
        AddSVCheckbox(content, "Show staff (event)", "sv_indicator_event_show_staff")
        AddSVCheckbox(content, "Show players (event)", "sv_indicator_event_show_player")
    end

    local function OpenIndicatorSettings()
        if IsValid(IndicatorSettingsMenu) then IndicatorSettingsMenu:Remove() end
        IndicatorSettingsMenu = vgui.Create("DFrame")
        IndicatorSettingsMenu:SetSize(420, 450)
        IndicatorSettingsMenu:Center()
        IndicatorSettingsMenu:SetTitle("")
        IndicatorSettingsMenu:MakePopup()
        IndicatorSettingsMenu:ShowCloseButton(false)

        IndicatorSettingsMenu.Paint = function(self, w, h)
            if GetConVar("zcity_sb_blur") and GetConVar("zcity_sb_blur"):GetBool() and (1 / math.max(RealFrameTime(), 0.001)) >= 25 then
                local amount = 5
                surface.SetMaterial(Material("pp/blurscreen"))
                surface.SetDrawColor(0, 0, 0, 125)
                surface.DrawRect(0, 0, w, h)
                local x, y = self:LocalToScreen(0, 0)
                for i = -0.2, 1, 0.2 do
                    Material("pp/blurscreen"):SetFloat("$blur", i * amount)
                    Material("pp/blurscreen"):Recompute()
                    render.UpdateScreenEffectTexture()
                    surface.DrawTexturedRect(x * -1, y * -1, ScrW(), ScrH())
                end
            end
            surface.SetDrawColor(20, 20, 25, 250)
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(255, 255, 255, 20)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
            draw.SimpleText("INDICATOR SETTINGS", "DermaDefaultBold", 12, 10, color_white, 0, 0)
        end

        local close = vgui.Create("DButton", IndicatorSettingsMenu)
        close:SetSize(28, 24)
        close:SetPos(IndicatorSettingsMenu:GetWide() - 34, 6)
        close:SetText("X")
        close:SetTextColor(color_white)
        close.Paint = function(self, w, h)
            if self:IsHovered() then
                surface.SetDrawColor(200, 60, 60, 200)
                surface.DrawRect(0, 0, w, h)
            end
        end
        close.DoClick = function() IndicatorSettingsMenu:Remove() end

        local content = vgui.Create("DPanel", IndicatorSettingsMenu)
        content:Dock(FILL)
        content:DockMargin(10, 5, 10, 10)
        content.Paint = function() end

        local topToggles = vgui.Create("DPanel", content)
        topToggles:Dock(TOP) topToggles:DockMargin(10, 0, 10, 10) topToggles:SetTall(45) topToggles.Paint = function() end
        
        local masterCheck = vgui.Create("DCheckBoxLabel", topToggles) 
        masterCheck:Dock(TOP) masterCheck:DockMargin(0, 0, 0, 5) masterCheck:SetText("Turn Off All Indicators") masterCheck:SetConVar("indicator_master_disable") masterCheck:SetTextColor(color_white)
        
        local namesCheck = vgui.Create("DCheckBoxLabel", topToggles) 
        namesCheck:Dock(TOP) namesCheck:SetText("Show Player Names instead of Roles/Teams") namesCheck:SetConVar("indicator_show_names") namesCheck:SetTextColor(color_white)

        local fontPanel = vgui.Create("DPanel", content)
        fontPanel:Dock(TOP) fontPanel:DockMargin(10, 0, 10, 5) fontPanel:SetTall(25) fontPanel.Paint = function() end
        local fontLabel = vgui.Create("DLabel", fontPanel)
        fontLabel:Dock(LEFT) fontLabel:SetText("Text Font") fontLabel:SetTextColor(Color(255, 255, 255)) fontLabel:SetWide(80)
        local fontCombo = vgui.Create("DComboBox", fontPanel)
        fontCombo:Dock(FILL) fontCombo:SetValue(cv_font:GetString())
        for _, f in ipairs({"Bahnschrift", "Arial", "Roboto", "Tahoma", "Trebuchet MS", "Verdana", "Impact", "Courier New", "Comic Sans MS"}) do fontCombo:AddChoice(f) end
        fontCombo.OnSelect = function(self, index, value) cv_font:SetString(value) end

        local sizeSlider = vgui.Create("DNumSlider", content) sizeSlider:Dock(TOP) sizeSlider:DockMargin(10, 5, 10, 5) sizeSlider:SetText("Text Size") sizeSlider:SetMin(12) sizeSlider:SetMax(72) sizeSlider:SetDecimals(0) sizeSlider:SetConVar("indicator_size")
        if IsValid(sizeSlider.Label) then sizeSlider.Label:SetTextColor(color_white) end

        local alphaSlider = vgui.Create("DNumSlider", content) alphaSlider:Dock(TOP) alphaSlider:DockMargin(10, 5, 10, 5) alphaSlider:SetText("Opacity Multiplier") alphaSlider:SetMin(0) alphaSlider:SetMax(1) alphaSlider:SetDecimals(1) alphaSlider:SetConVar("indicator_opacity")
        if IsValid(alphaSlider.Label) then alphaSlider.Label:SetTextColor(color_white) end

        local satSlider = vgui.Create("DNumSlider", content) satSlider:Dock(TOP) satSlider:DockMargin(10, 5, 10, 5) satSlider:SetText("Color Saturation") satSlider:SetMin(0) satSlider:SetMax(2) satSlider:SetDecimals(1) satSlider:SetConVar("indicator_saturation")
        if IsValid(satSlider.Label) then satSlider.Label:SetTextColor(color_white) end
        
        local pulseCheck = vgui.Create("DCheckBoxLabel", content) pulseCheck:Dock(TOP) pulseCheck:DockMargin(10, 5, 10, 10) pulseCheck:SetText("Enable Pulsing Effect") pulseCheck:SetConVar("indicator_pulse") pulseCheck:SetTextColor(color_white)

        local toggleContainer = vgui.Create("DPanel", content) toggleContainer:Dock(TOP) toggleContainer:DockMargin(10, 5, 10, 10) toggleContainer:SetTall(75) toggleContainer.Paint = function() end
        local col1 = vgui.Create("DPanel", toggleContainer) col1:Dock(LEFT) col1:SetWide(190) col1.Paint = function() end
        local col2 = vgui.Create("DPanel", toggleContainer) col2:Dock(RIGHT) col2:SetWide(190) col2.Paint = function() end

        local cb1 = vgui.Create("DCheckBoxLabel", col1) cb1:Dock(TOP) cb1:DockMargin(0, 0, 0, 5) cb1:SetText("Enable in Homicide") cb1:SetConVar("indicator_en_hmcd") cb1:SetTextColor(color_white)
        local cb2 = vgui.Create("DCheckBoxLabel", col1) cb2:Dock(TOP) cb2:DockMargin(0, 0, 0, 5) cb2:SetText("Enable in Pathowogen") cb2:SetConVar("indicator_en_pathowogen") cb2:SetTextColor(color_white)
        local cb3 = vgui.Create("DCheckBoxLabel", col1) cb3:Dock(TOP) cb3:SetText("Enable in CO-OP") cb3:SetConVar("indicator_en_coop") cb3:SetTextColor(color_white)
        local cb4 = vgui.Create("DCheckBoxLabel", col2) cb4:Dock(TOP) cb4:DockMargin(0, 0, 0, 5) cb4:SetText("Enable in NPC Defense") cb4:SetConVar("indicator_en_defense") cb4:SetTextColor(color_white)
        local cb5 = vgui.Create("DCheckBoxLabel", col2) cb5:Dock(TOP) cb5:DockMargin(0, 0, 0, 5) cb5:SetText("Enable in Active Shooter") cb5:SetConVar("indicator_en_as") cb5:SetTextColor(color_white)
        local cb6 = vgui.Create("DCheckBoxLabel", col2) cb6:Dock(TOP) cb6:SetText("Enable in Team Modes") cb6:SetConVar("indicator_en_team") cb6:SetTextColor(color_white)

        local resetBtn = vgui.Create("DButton", content) resetBtn:Dock(BOTTOM) resetBtn:DockMargin(10, 5, 10, 5) resetBtn:SetText("Reset to Default") resetBtn:SetTall(28) resetBtn:SetTextColor(color_white)
        resetBtn.Paint = function(s, w, h)
            if s:IsHovered() then
                surface.SetDrawColor(50, 50, 60, 255)
            else
                surface.SetDrawColor(30, 30, 35, 255)
            end
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(255, 255, 255, 20)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
        end

        resetBtn.DoClick = function()
            cv_master_disable:SetBool(false)
            cv_show_names:SetBool(false)
            cv_font:SetString("Bahnschrift") fontCombo:SetValue("Bahnschrift") 
            cv_size:SetInt(26) 
            cv_alpha:SetFloat(1.0) 
            cv_sat:SetFloat(1.0) 
            cv_pulse:SetBool(false)
            cv_en_hmcd:SetBool(true) cv_en_path:SetBool(true) cv_en_coop:SetBool(true) cv_en_def:SetBool(true) cv_en_as:SetBool(true) cv_en_team:SetBool(true)
        end

        if LocalPlayer():IsSuperAdmin() then
            local adminBtn = vgui.Create("DButton", content) adminBtn:Dock(BOTTOM) adminBtn:DockMargin(10, 0, 10, 5) adminBtn:SetText("Server Settings (Admin Only)") adminBtn:SetTall(28) adminBtn:SetTextColor(color_white)
            adminBtn.Paint = function(s, w, h)
                if s:IsHovered() then
                    surface.SetDrawColor(50, 50, 60, 255)
                else
                    surface.SetDrawColor(30, 30, 35, 255)
                end
                surface.DrawRect(0, 0, w, h)
                surface.SetDrawColor(255, 255, 255, 20)
                surface.DrawOutlinedRect(0, 0, w, h, 1)
            end
            adminBtn.DoClick = OpenAdminIndicatorSettings
        end
    end

    concommand.Add("indicators_menu", OpenIndicatorSettings)

    net.Receive("Indicator_OpenMenu", OpenIndicatorSettings)

    hook.Add("OnPlayerChat", "Indicator_SettingsMenu", function(ply, text)
        if ply == LocalPlayer() and string.lower(text) == "!indicators" then OpenIndicatorSettings() return true end
    end)

    local TraitorList, SheriffList, PoliceList = {}, {}, {}
    local function ClearLists() 
        TraitorList, SheriffList, PoliceList = {}, {}, {} 
        CustomIndicators = {}
    end

    net.Receive("HMCD_SyncTraitors", function()
        local type = net.ReadUInt(4)
        if type == 4 then ClearLists() return end
        
        local count = net.ReadUInt(8)
        local list = {}
        for i = 1, count do list[net.ReadUInt(16)] = true end
        
        if type == 1 then TraitorList = list 
        elseif type == 2 then SheriffList = list 
        elseif type == 3 then PoliceList = list end
    end)

    hook.Add("RoundInfoCalled", "Indicator_ClearOnRoundInfo", function() timer.Simple(0, ClearLists) end)
    hook.Add("PlayerDisconnected", "Indicator_CustomCleanupCL", function(ply) CustomIndicators[ply:EntIndex()] = nil end)

    local teamInfo = {
        ["cstrike"] = { [0] = { "Terrorist", Color(220, 120, 60) }, [1] = { "CT", Color(80, 140, 220) } },
        ["criresp"] = { [0] = { "SWAT", Color(0, 0, 190) }, [1] = { "Suspect", Color(190, 0, 0) } },
        ["gwars"]   = { [0] = { "Blood", Color(110, 45, 45) }, [1] = { "Groove", Color(60, 150, 40) }, [2] = { "SWAT", Color(50, 50, 255) } },
        ["hl2dm"]   = { [0] = { "Rebel", Color(200, 100, 0) }, [1] = { "Combine", Color(0, 100, 200) } },
        ["tdm"]     = { [0] = { "Terrorist", Color(218, 165, 32) }, [1] = { "CT", Color(90, 140, 180) } },
        ["riot"]    = { [0] = { "Rioter", Color(180, 50, 50) }, [1] = { "Law", Color(50, 50, 180) } }
    }

    -- Tag colours: literals below go through TagColor, so each RGB is one shared Color; the saturation-adjusted
    -- colour is cached per base colour and saturation value. Each draw writes .a and uses the colour at once.
    local tagColors = {}
    local function TagColor(r, g, b)
        local key = r * 65536 + g * 256 + b
        local c = tagColors[key]
        if not c then c = Color(r, g, b) tagColors[key] = c end
        return c
    end
    local satCache = setmetatable({}, {__mode = "k"})
    local function GetIndicatorDrawColor(baseColor, distAlpha, pulseVal)
        local sat = cv_sat:GetFloat()
        local entry = satCache[baseColor]
        if not entry or entry.sat ~= sat or entry.r ~= baseColor.r or entry.g ~= baseColor.g or entry.b ~= baseColor.b then
            local h, s, v = ColorToHSV(baseColor)
            entry = {sat = sat, r = baseColor.r, g = baseColor.g, b = baseColor.b, col = HSVToColor(h, math.Clamp(s * sat, 0, 1), v)}
            satCache[baseColor] = entry
        end
        local modColor = entry.col
        modColor.a = math.Clamp(pulseVal * distAlpha * cv_alpha:GetFloat(), 0, 255)
        return modColor
    end
    -- Per-player tag fade-in (0.2 s, RealTime) so a tag never pops on.
    local tagSeen = setmetatable({}, {__mode = "k"})
    local tagFrame = 0

    local function GetHeadPos(ent)
        local bone_id = ent:LookupBone("ValveBiped.Bip01_Head1")
        if bone_id and bone_id > 0 then
            local bonePos = ent:GetBonePosition(bone_id)
            if bonePos and bonePos ~= ent:GetPos() then return bonePos + Vector(0, 0, 12) end
        end

        local attach_id = ent:LookupAttachment("eyes")
        if attach_id > 0 then
            local attach = ent:GetAttachment(attach_id)
            if attach and attach.Pos then
                local forward = ent:GetAngles():Forward()
                forward.z = 0 
                if forward:LengthSqr() > 0 then forward:Normalize() end
                return attach.Pos + Vector(0, 0, 12) - (forward * 3)
            end
        end

        local pos = ent:GetPos()
        if ent:IsPlayer() then
            pos = pos + Vector(0, 0, ent:Crouching() and 60 or 80)
        else
            pos = pos + Vector(0, 0, 20)
        end
        return pos
    end

    local activeTeamCount = 0
    local nextTeamCheck = 0

    hook.Add("HUDPaint", "Indicator_Draw", function()
        if cv_master_disable:GetBool() then return end

        local lply = LocalPlayer()
        if not IsValid(lply) then return end
        if zb and zb.ROUND_STATE and zb.ROUND_STATE ~= 1 then
            if next(TraitorList) or next(SheriffList) or next(PoliceList) then ClearLists() end
            return
        end
        
        local pulseVal = cv_pulse:GetBool() and (200 + math.sin(CurTime() * 5) * 55) or 255
        local lplyEyePos = lply:EyePos()
        local lplyTeam = lply:Team()
        
        local modeName = zb and zb.CROUND or ""
        local modeTbl = zb and zb.modes and zb.modes[modeName]
        local isHomicide = (modeName == "hmcd") or (modeTbl and modeTbl.SubRoles ~= nil) or false
        local isActiveShooter = (modeName == "as")
        local isDM = (modeName == "dm")
        local isEV = (modeName == "event")
        
        local lplyIsSpec = (lplyTeam == 1002 or not lply:Alive())
        local specSeeAll = sv_cv_spec and sv_cv_spec:GetBool() or false
        local baseShowAll = sv_cv_showall and sv_cv_showall:GetBool() or false
        
        local spectatorBypass = (specSeeAll and lplyIsSpec and not isHomicide)
        local effectiveShowAll = baseShowAll or spectatorBypass

        if CurTime() > nextTeamCheck then
            local activeTeams = {}
            for _, p in player.Iterator() do
                if IsValid(p) and p:Alive() then
                    local t = p:Team()
                    if t ~= TEAM_SPECTATOR and t ~= TEAM_UNASSIGNED and t < 1000 then activeTeams[t] = true end
                end
            end
            activeTeamCount = table.Count(activeTeams)
            nextTeamCheck = CurTime() + 1
        end
        local isTeamMode = (not isHomicide) and (isActiveShooter or activeTeamCount >= 2) and lplyTeam ~= TEAM_SPECTATOR and lplyTeam ~= TEAM_UNASSIGNED and lplyTeam < 1000

        local modeDisabled = false
        if isHomicide and (not cv_en_hmcd:GetBool() or (sv_cv_hmcd and sv_cv_hmcd:GetBool())) then modeDisabled = true end
        if modeName == "pathowogen" and (not cv_en_path:GetBool() or (sv_cv_path and sv_cv_path:GetBool())) then modeDisabled = true end
        if modeName == "coop" and (not cv_en_coop:GetBool() or (sv_cv_coop and sv_cv_coop:GetBool())) then modeDisabled = true end
        if modeName == "defense" and (not cv_en_def:GetBool() or (sv_cv_def and sv_cv_def:GetBool())) then modeDisabled = true end
        if isActiveShooter and (not cv_en_as:GetBool() or (sv_cv_as and sv_cv_as:GetBool())) then modeDisabled = true end
        if isTeamMode and not isActiveShooter and (not cv_en_team:GetBool() or (sv_cv_team and sv_cv_team:GetBool())) then modeDisabled = true end
        if isDM and not (sv_cv_dm and sv_cv_dm:GetBool()) then modeDisabled = true end
        if isEV and not (sv_cv_ev and sv_cv_ev:GetBool()) then modeDisabled = true end

        if spectatorBypass then
            modeDisabled = false
        end

        local lplyIdx = lply:EntIndex()
        local viewPos, viewFwd = EyePos(), EyeVector()
        local rnow = RealTime()
        tagFrame = tagFrame + 1
        local lplyTraitor = TraitorList[lplyIdx]
        local lplySheriff = SheriffList[lplyIdx]
        local lplyPolice = PoliceList[lplyIdx]

        for _, ply in player.Iterator() do
            if ply == lply or not ply:Alive() then continue end

            local fakeRag = ply:GetNWEntity("FakeRagdoll")
            local targetEnt = IsValid(fakeRag) and fakeRag or ply

            local text, color
            local shouldDraw = false
            
            local customInd = CustomIndicators[ply:EntIndex()]
            local customOverrides = false

            if customInd then
                local vMode = customInd.visMode or 0
                local canSeeCustom = false
                
                if vMode == 0 then
                    canSeeCustom = true
                elseif vMode == 1 and (ply:Team() == lplyTeam or effectiveShowAll) then
                    canSeeCustom = true
                elseif vMode == 2 and lplyIdx == (customInd.adminIdx or 0) then
                    canSeeCustom = true 
                end

                if canSeeCustom then
                    text = customInd.text
                    color = customInd.color
                    shouldDraw = true
                    customOverrides = true
                end
            end

            if not customOverrides and not modeDisabled then
                -- juggernaut round: hunters see TEAM over fellow hunters;
                -- the Juggernaut himself sees no indicators, and no tag is
                -- ever drawn over him. zc_juggernaut's client publishes
                -- ZCJUGG_CL = {ent = jugg, round = zb.ROUND_START} - the
                -- round stamp makes stale carryover impossible.
                local jcl = ZCJUGG_CL
                if jcl and IsValid(jcl.ent) and zb and zb.ROUND_START == jcl.round then
                    if lply == jcl.ent then continue end
                    if ply == jcl.ent then continue end
                    if not cv_en_team:GetBool() or (sv_cv_team and sv_cv_team:GetBool()) then continue end
                    text, color, shouldDraw = "TEAM", TagColor(60, 140, 255), true

                elseif isHomicide then
                    if not lplyTraitor and not lplySheriff and not lplyPolice and not effectiveShowAll then continue end
                    local idx = ply:EntIndex()
                    
                    if TraitorList[idx] and (effectiveShowAll or lplyTraitor) then
                        text, color, shouldDraw = "TRAITOR", TagColor(255, 50, 50), true
                    elseif SheriffList[idx] and (effectiveShowAll or lplySheriff) then
                        text, color, shouldDraw = "SHERIFF", TagColor(50, 150, 255), true
                    elseif PoliceList[idx] and (effectiveShowAll or lplyPolice) then
                        text, color, shouldDraw = "POLICE", TagColor(50, 50, 255), true
                    elseif effectiveShowAll then
                        text, color, shouldDraw = "INNOCENT", TagColor(150, 255, 150), true
                    end

                elseif modeName == "pathowogen" then
                    local round = CurrentRound and CurrentRound()
                    if not round or not round.saved then continue end
                    
                    local isFurry = ply.PlayerClassName == "furry"
                    local isDelta = ply.PlayerClassName == "commanderforces"
                    local isTraitor = round.saved.traitors and round.saved.traitors[ply]

                    local sameTeam = effectiveShowAll or (lply.PlayerClassName == "furry" and isFurry) 
                                     or (lply.PlayerClassName == "commanderforces" and isDelta) 
                                     or (lply.PlayerClassName ~= "furry" and lply.PlayerClassName ~= "commanderforces" and not isFurry and not isDelta)

                    if sameTeam then
                        if isFurry then text, color, shouldDraw = "FURRY", TagColor(255, 100, 255), true
                        elseif isDelta then text, color, shouldDraw = "DELTA", TagColor(50, 100, 255), true
                        elseif isTraitor then text, color, shouldDraw = "OPERATIVE", TagColor(200, 50, 100), true
                        else text, color, shouldDraw = "SURVIVOR", TagColor(255, 120, 120), true end
                    end

                elseif modeName == "coop" then
                    local pClass = string.lower(ply.PlayerClassName or ply:GetNWString("PlayerClass", ""))
                    local sClass = ply.subClass or ""
                    local pRole = string.lower(ply:GetNWString("Role", ""))
                    
                    if pClass == "gordon" or pRole == "freeman" then text, color, shouldDraw = "FREEMAN", TagColor(255, 155, 0), true
                    elseif sClass == "medic" or pRole == "medic" then text, color, shouldDraw = "MEDIC", TagColor(190, 0, 0), true
                    elseif sClass == "grenadier" or pRole == "grenadier" then text, color, shouldDraw = "GRENADIER", TagColor(190, 90, 0), true
                    elseif pClass == "refugee" or pClass == "citizen" or pRole == "refugee" then text, color, shouldDraw = "REFUGEE", TagColor(200, 200, 200), true
                    else text, color, shouldDraw = "REBEL", TagColor(255, 155, 0), true end

                elseif modeName == "defense" then
                    local role = ply:GetNWString("PlayerRole", "")
                    if role == "Commander" then text, color, shouldDraw = "COMMANDER", TagColor(255, 200, 0), true
                    elseif role == "Medic" then text, color, shouldDraw = "MEDIC", TagColor(190, 0, 0), true
                    elseif role == "Engineer" then text, color, shouldDraw = "ENGINEER", TagColor(0, 200, 100), true
                    elseif role == "Soldier" then text, color, shouldDraw = "SOLDIER", TagColor(200, 200, 200), true
                    else text, color, shouldDraw = "DEFENDER", TagColor(200, 200, 200), true end

                elseif isDM then
                    text, color, shouldDraw = "PLAYER", TagColor(255, 100, 100), true

                elseif isEV then
                    local showStaff = sv_cv_ev_staff and sv_cv_ev_staff:GetBool()
                    local showPlayer = sv_cv_ev_player and sv_cv_ev_player:GetBool()

                    local isStaff = ply:IsSuperAdmin() or ply:IsAdmin()

                    if isStaff and (showStaff or spectatorBypass) then
                        text, color, shouldDraw = "STAFF", TagColor(255, 215, 0), true
                    elseif (not isStaff) and (showPlayer or spectatorBypass) then
                        text, color, shouldDraw = "PLAYER", TagColor(255, 100, 100), true
                    else
                        shouldDraw = false
                    end

                elseif isTeamMode then
                    local t = ply:Team()
                    if t == TEAM_SPECTATOR or t == TEAM_UNASSIGNED then continue end
                    if not effectiveShowAll and t ~= lplyTeam then continue end

                    if isActiveShooter then
                        local tName = team.GetName(t) or ""
                        local tnLow = string.lower(tName)
                        if tnLow == "players" then text, color, shouldDraw = "SHOOTER", TagColor(255, 80, 80), true
                        elseif tnLow == "players2" then text, color, shouldDraw = "CIVILIAN", TagColor(80, 200, 255), true
                        elseif tnLow == "players3" then text, color, shouldDraw = "SWAT", TagColor(0, 0, 190), true
                        else text, color, shouldDraw = tName, team.GetColor(t), true end
                    else
                        -- universal team labels: teammates show TEAM, enemy
                        -- teams never render - applies to every team mode
                        if t ~= lplyTeam then continue end
                        text, color = "TEAM", TagColor(60, 140, 255)
                        shouldDraw = true
                    end
                end
            end

            if shouldDraw then
                if cv_show_names:GetBool() and not customOverrides then
                    text = ply:Nick()
                end

                local targetPos = targetEnt:GetPos()
                local distSqr = lplyEyePos:DistToSqr(targetPos)
                if distSqr > 4000000 then continue end
                -- more than 100 units behind the camera: the head cannot be on screen, skip the bone lookup
                if (targetPos - viewPos):Dot(viewFwd) < -100 then continue end

                local alpha = 1
                if distSqr > 2250000 then
                    alpha = 1 - ((math.sqrt(distSqr) - 1500) / 500)
                    alpha = alpha * alpha * (3 - 2 * alpha)
                end

                local seen = tagSeen[ply]
                if not seen or seen.frame < tagFrame - 1 then
                    seen = seen or {}
                    seen.born = rnow
                    tagSeen[ply] = seen
                end
                seen.frame = tagFrame
                local fadeIn = math.Clamp((rnow - seen.born) / 0.2, 0, 1)
                alpha = alpha * fadeIn * fadeIn * (3 - 2 * fadeIn)

                local pos = GetHeadPos(targetEnt)
                local screenPos = pos:ToScreen()

                if screenPos.visible then
                    local drawColor = GetIndicatorDrawColor(color, alpha, pulseVal)
                    local K = ZCGoobApps and ZCGoobApps.Kit
                    if K and K.HudText then -- 2026-09-25 HUD pass: shared 1 px shadow
                        K.HudText(text, "IndicatorFont", screenPos.x, screenPos.y, drawColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    else
                        draw.SimpleText(text, "IndicatorFont", math.floor(screenPos.x), math.floor(screenPos.y), drawColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    end
                end
            end
        end
    end)
end

local function Octavu_RegisterULX()
    if not ULib or not ulx then 
        timer.Simple(0.5, Octavu_RegisterULX)
        return 
    end

    local CATEGORY_NAME = "Octavu"

    local function ulx_setindicator(calling_ply, target_plys, text, r, g, b, visModeStr)
        if SERVER then
            local visMode = 0
            if visModeStr == "Team" then visMode = 1
            elseif visModeStr == "Admin" then visMode = 2 end
            
            local adminIdx = IsValid(calling_ply) and calling_ply:EntIndex() or 0

            for _, target in ipairs(target_plys) do
                if IsValid(target) then
                    Octavu_SetCustomIndicatorSV(target:EntIndex(), true, text, r, g, b, visMode, adminIdx)
                end
            end
            ulx.fancyLogAdmin(calling_ply, "#A set a custom indicator for #T to '#s' (Color: #i, #i, #i, Vis: #s)", target_plys, text, r, g, b, visModeStr)
        end
    end

    local setind = ulx.command(CATEGORY_NAME, "ulx setindicator", ulx_setindicator, "!setindicator")
    setind:addParam{ type=ULib.cmds.PlayersArg }
    setind:addParam{ type=ULib.cmds.StringArg, hint="Text" }
    setind:addParam{ type=ULib.cmds.NumArg, hint="Red", min=0, max=255, default=255, ULib.cmds.optional }
    setind:addParam{ type=ULib.cmds.NumArg, hint="Green", min=0, max=255, default=255, ULib.cmds.optional }
    setind:addParam{ type=ULib.cmds.NumArg, hint="Blue", min=0, max=255, default=255, ULib.cmds.optional }
    setind:addParam{ type=ULib.cmds.StringArg, hint="Visibility", completes={"Everyone", "Team", "Admin"}, default="Everyone", ULib.cmds.optional }
    setind:defaultAccess(ULib.ACCESS_ADMIN)
    setind:help("Sets a custom indicator for the target(s).")

    local function ulx_removeindicator(calling_ply, target_plys)
        if SERVER then
            for _, target in ipairs(target_plys) do
                if IsValid(target) then
                    Octavu_SetCustomIndicatorSV(target:EntIndex(), false)
                end
            end
            ulx.fancyLogAdmin(calling_ply, "#A removed custom indicators for #T", target_plys)
        end
    end

    local remind = ulx.command(CATEGORY_NAME, "ulx removeindicator", ulx_removeindicator, "!removeindicator")
    remind:addParam{ type=ULib.cmds.PlayersArg }
    remind:defaultAccess(ULib.ACCESS_ADMIN)
    remind:help("Removes custom indicators for the target(s).")
end
hook.Add("Initialize", "Octavu_ULX_Indicators", Octavu_RegisterULX)