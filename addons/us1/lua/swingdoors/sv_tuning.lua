SwingDoors = SwingDoors or {}
SwingDoors.Tuning = SwingDoors.Tuning or {}
-- US1: safe to re-run; change callbacks are keyed and replace themselves.

local CONFIG = SwingDoors.Config
local DBG = SwingDoors.DBG
local Schema = SwingDoors.Settings.ByKey

for _, def in ipairs(SwingDoors.Settings.Schema) do
    if def.realm == "sv" then
        CONFIG[def.key] = SwingDoors.Settings.Sanitize(def, GetConVar(def.cvar):GetFloat())

        cvars.AddChangeCallback(def.cvar, function(_, _, new)
            local clean = SwingDoors.Settings.SanitizeConVar(def, new)
            if clean then CONFIG[def.key] = clean end
        end, "SwingDoors_Sync_" .. def.key)
    end
end

net.Receive("SwingDoors_Tune", function(_, ply)
    if not (game.SinglePlayer() or (IsValid(ply) and ply:IsAdmin())) then return end
    local key = net.ReadString()
    local value = net.ReadFloat()

    local def = Schema[key]
    if not def or def.realm ~= "sv" then return end
    if value ~= value then return end

    value = SwingDoors.Settings.Sanitize(def, value)
    GetConVar(def.cvar):SetFloat(value)
    DBG("Tune: %s = %s (by %s)", key, tostring(value), IsValid(ply) and ply:Nick() or "?")
end)

concommand.Add("swingdoors_reset", function(ply)
    if not IsValid(ply) or game.SinglePlayer() or ply:IsAdmin() then
        for _, def in ipairs(SwingDoors.Settings.Schema) do
            if def.realm == "sv" then RunConsoleCommand(def.cvar, tostring(def.default)) end
        end

        SwingDoors.PrintTo(ply, "[SwingDoors] settings reset to defaults.")
    end

    if IsValid(ply) then
        net.Start("SwingDoors_ResetClient")
        net.Send(ply)
    end
end)

concommand.Add("swingdoors_status", function(ply)
    local lines = { "[SwingDoors] current settings:" }
    for _, def in ipairs(SwingDoors.Settings.Schema) do
        if def.realm == "sv" then
            lines[#lines + 1] = string.format("  %s = %s (default %s)", def.cvar, SwingDoors.Settings.Format(def, CONFIG[def.key]), SwingDoors.Settings.Format(def, def.default))
        end
    end
    lines[#lines + 1] = string.format("  swingdoors_sv_debug: %s", tostring(SwingDoors.Debug.enabled))

    SwingDoors.PrintTo(ply, table.concat(lines, "\n"))
    if IsValid(ply) then
        net.Start("SwingDoors_Status")
        net.Send(ply)
    end
end)
