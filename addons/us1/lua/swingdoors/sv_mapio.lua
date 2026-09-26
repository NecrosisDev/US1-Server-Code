SwingDoors = SwingDoors or {}
SwingDoors.MapIO = SwingDoors.MapIO or {}

local DBG = SwingDoors.DBG
local Geometry = SwingDoors.Geometry

function SwingDoors.MapIO.Fire(door, output, activator)
    if not IsValid(door) then return end
    DBG("%s: firing %s (activator=%s)", tostring(door), output, tostring(activator))
    pcall(door.TriggerOutput, door, output, IsValid(activator) and activator or door)
end

function SwingDoors.MapIO.ReportBlocked(s, blockingEnt, opening)
    local flag = opening and "blockedOpening" or "blockedClosing"
    if s[flag] then return end
    s[flag] = true
    SwingDoors.MapIO.Fire(s.door, opening and "OnBlockedOpening" or "OnBlockedClosing", blockingEnt)
end

function SwingDoors.MapIO.ReportUnblocked(s)
    if s.blockedOpening then
        s.blockedOpening = false
        SwingDoors.MapIO.Fire(s.door, "OnUnblockedOpening")
    end
    if s.blockedClosing then
        s.blockedClosing = false
        SwingDoors.MapIO.Fire(s.door, "OnUnblockedClosing")
    end
end

-- US1: keyed lowercase. Z-City kicks fire "open" / "openawayfrom" / "Close"; input names are case-insensitive
-- to the engine but arrive here exactly as fired.
local GUARD_WHILE_HELD = {
    open           = true,
    close          = true,
    toggle         = true,
    settogglestate = true,
    openawayfrom   = true,
}

-- leg kick / jump kick: ent:Fire("openawayfrom" | "open" | "Close", name, 0, ply, ply)
local KICK_INPUTS = { openawayfrom = true, open = true, close = true }

hook.Add("AcceptInput", "SwingDoors_MapIO_GuardNativeInputs", function(ent, input, activator, caller, value)
    local lowered = string.lower(input or "")
    if not GUARD_WHILE_HELD[lowered] then return end
    if not Geometry.IsSwingable(ent, "AcceptInput") then return end

    if KICK_INPUTS[lowered] and SwingDoors.Impact and IsValid(caller) and caller:IsPlayer() and activator == caller then
        if SwingDoors.Impact.HandleNativeKick(ent, caller) then return true end
    end
    if not IsValid(ent.SwingDoors_HeldBy) then return end

    if activator == ent and caller == ent then return end

    -- A door nobody is actively steering (knocked, or let go and coasting) yields to kicks, bots and map logic.
    if SwingDoors.Impact and SwingDoors.Impact.YieldToNative(ent) then return end

    DBG("%s: ignoring native '%s' input -- SwingDoors session active (held by %s)",
        tostring(ent), input, tostring(ent.SwingDoors_HeldBy))
    return true
end)
