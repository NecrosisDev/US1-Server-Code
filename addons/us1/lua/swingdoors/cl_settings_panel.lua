local function CleanNumSlider(panel, label, convar, min, max, decimals)
    local slider = panel:NumSlider(label, convar, min, max, decimals or 1)
    if not IsValid(slider) or not IsValid(slider.TextArea) then return slider end

    local function Clean(val)
        local mult = 10 ^ (decimals or 1)
        return math.Round(val * mult) / mult
    end

    local function UpdateDisplay()
        local val = Clean(GetConVar(convar):GetFloat())
        slider.TextArea:SetText(string.format("%g", val))
    end

    slider.OnValueChanged = function(_, val)
        val = Clean(val)
        RunConsoleCommand(convar, tostring(val))
        UpdateDisplay()
    end

    cvars.AddChangeCallback(convar, UpdateDisplay, "SwingDoors_CleanDisplay_" .. convar)
    UpdateDisplay()

    return slider
end

local serverSliderRefreshers = {}

local function BuildServerSlider(panel, def, canEdit)
    local slider = panel:NumSlider(def.label, nil, def.min, def.max, def.decimals)
    local syncing = false

    local function UpdateDisplay()
        if not IsValid(slider) then return end
        syncing = true
        slider:SetValue(GetConVar(def.cvar):GetFloat())
        syncing = false
    end
    UpdateDisplay()
    cvars.AddChangeCallback(def.cvar, UpdateDisplay, "SwingDoors_ServerSliderSync_" .. def.key)
    table.insert(serverSliderRefreshers, UpdateDisplay)

    slider:SetEnabled(canEdit)
    slider.OnValueChanged = function(_, value)
        if syncing or not canEdit then return end
        net.Start("SwingDoors_Tune")
            net.WriteString(def.key)
            net.WriteFloat(value)
        net.SendToServer()
    end

    return slider
end

local function ResetClientSettings()
    for _, def in ipairs(SwingDoors.Settings.Schema) do
        if def.realm == "cl" then RunConsoleCommand(def.cvar, tostring(def.default)) end
    end

    for _, refresh in ipairs(serverSliderRefreshers) do
        refresh()
    end
end

net.Receive("SwingDoors_ResetClient", ResetClientSettings)

local function BuildSettingsPanel(panel)
    local canEdit = game.SinglePlayer() or (IsValid(LocalPlayer()) and LocalPlayer():IsAdmin())
    serverSliderRefreshers = {}

    panel:Help(":: CLIENT ::")

    local byKey = SwingDoors.Settings.ByKey
    local keyBinders = panel:KeyBinder(
        "[ " .. string.upper(byKey.dragKey.label) .. " ]", byKey.dragKey.cvar,
        "[ " .. string.upper(byKey.fullSwingKey.label) .. " ]", byKey.fullSwingKey.cvar)
    keyBinders:DockMargin(0, 4, 0, 4)

    for _, def in ipairs(SwingDoors.Settings.Schema) do
        if def.realm == "cl" and def.kind ~= "key" then
            CleanNumSlider(panel, def.label, def.cvar, def.min, def.max, def.decimals)
        end
    end

    panel:Help("")
    panel:Help(":: SERVER ::")
    if not canEdit then
        panel:Help("Only admins (or singleplayer) can change these.")
    end

    for _, def in ipairs(SwingDoors.Settings.Schema) do
        if def.realm == "sv" then BuildServerSlider(panel, def, canEdit) end
    end

    local btn = vgui.Create("DButton", panel)
    btn:SetText("Reset to Default Settings")
    btn:SetTall(30)
    btn:Dock(TOP)
    btn:DockMargin(0, 4, 0, 4)
    btn.DoClick = function() RunConsoleCommand("swingdoors_reset") end
    panel:AddItem(btn)
    panel:Help("")
end

hook.Add("PopulateToolMenu", "SwingDoors_ToolMenu", function()
    spawnmenu.AddToolMenuOption("Utilities", "Swing Doors", "SwingDoors_Settings",
        "Settings", "", "", function(panel)
            panel:ClearControls()
            BuildSettingsPanel(panel)
        end)
end)
