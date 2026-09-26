local Debug = { enabled = false }

local function DBG(fmt, ...)
    if not Debug.enabled then return end
    MsgC(Color(255, 180, 60), "[SwingDoors:CL] ", Color(255, 255, 255), string.format(fmt, ...), "\n")
end

local swingableClasses = {
    prop_door_rotating = true,
    func_door_rotating = true,
}

local function IsSwingable(ent)
    if not SwingDoors.Enabled() then return false end
    if not IsValid(ent) then return false end
    if not swingableClasses[ent:GetClass()] then return false end
    if ent.NoOpen or ent.IsDecorative or ent.SwingDoors_Ignore then return false end
    return true
end

local function DragKey()
    return GetConVar("swingdoors_cl_drag_key"):GetInt()
end

local function FullSwingKey()
    return GetConVar("swingdoors_cl_fullswing_key"):GetInt()
end

local function ReachDistance()
    return GetConVar("swingdoors_sv_reach_distance"):GetFloat()
end

local function DragDown(ply)
    return ply:KeyDown(IN_USE) or input.IsKeyDown(DragKey())
end

local holding = false
local lookedAt = nil
local lastLoggedLookedAt = nil

local lastViewAngle = nil
local grabIgnoreUntil = 0
local moveDeadzone = 0.01

local NUDGE_SEND_INTERVAL = engine.TickInterval() or (1 / 66)
local pendingNudge = 0
local nextNudgeSend = 0

local function SendGrab(ent)
    DBG("Sending grab request for %s", tostring(ent))
    net.Start("SwingDoors_Grab")
        net.WriteEntity(ent)
    net.SendToServer()
end

local function SendRelease()
    DBG("Sending release")
    net.Start("SwingDoors_LetGo")
    net.SendToServer()
end

local function SendFullSwing(ent)
    DBG("Sending full swing request for %s", tostring(ent))
    net.Start("SwingDoors_FullSwing")
        net.WriteEntity(ent)
    net.SendToServer()
end

local fullSwingKeyWasDown = false

-- US1: a quick tap of the drag key (no mouse movement) opens/closes the door fully,
-- so "press E on a door" still works for players who never learn the drag.
local TAP_MAX_DURATION = 0.22
local TAP_MAX_MOUSE_DEG = 1.5
local holdStartedAt = 0
local holdEnt = nil
local holdPushTotal = 0

local function BeginHold(ent)
    holdStartedAt = RealTime()
    holdEnt = ent
    holdPushTotal = 0
    holding = true
    lastViewAngle = nil
    grabIgnoreUntil = CurTime() + 0.05
    pendingNudge = 0
    nextNudgeSend = 0
    SendGrab(ent)
end

local function EndHold()
    holding = false
    lastViewAngle = nil
    pendingNudge = 0
    SendRelease()

    if holdPushTotal <= TAP_MAX_MOUSE_DEG and IsValid(holdEnt) and RealTime() - holdStartedAt <= TAP_MAX_DURATION then
        SendFullSwing(holdEnt)
    end
    holdEnt = nil
end

net.Receive("SwingDoors_ForceRelease", function()
    if holding then
        DBG("Control taken by another player -> ending hold")
        holding = false
        lastViewAngle = nil
    end
end)

hook.Add("Think", "SwingDoors_InputWatch", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local eye, dist = SwingDoors.EyeTrace(ply, ReachDistance())
    local newLookedAt = IsSwingable(eye.Entity) and eye.Entity or nil

    if newLookedAt ~= lastLoggedLookedAt then
        if IsValid(newLookedAt) then
            DBG("Now looking at swingable door: %s", tostring(newLookedAt))
        end
        lastLoggedLookedAt = newLookedAt
    end

    lookedAt = newLookedAt

    local dragKey = DragKey()

    if not holding then
        local canStart = DragDown(ply) and lookedAt ~= nil and dist <= ReachDistance() and not vgui.CursorVisible()
        if canStart then
            BeginHold(lookedAt)
        end
    else
        if not DragDown(ply) then
            DBG("Drag key released -> ending hold")
            EndHold()
        elseif vgui.CursorVisible() then
            DBG("VGUI cursor visible during hold -> ending hold")
            EndHold()
        end
    end

    local fsKey = FullSwingKey()
    if fsKey == dragKey then
        fullSwingKeyWasDown = false
    else
        local fsIsDown = input.IsKeyDown(fsKey)
        if fsIsDown and not fullSwingKeyWasDown and not holding and not vgui.CursorVisible()
            and lookedAt ~= nil and dist <= ReachDistance() then
            DBG("Full Swing key pressed on %s", tostring(lookedAt))
            SendFullSwing(lookedAt)
        end
        fullSwingKeyWasDown = fsIsDown
    end
end)

hook.Add("CreateMove", "SwingDoors_DragAndCamera", function(cmd)
    if not holding then
        lastViewAngle = nil
        return
    end

    local newAngle = cmd:GetViewAngles()

    if not lastViewAngle then
        lastViewAngle = newAngle
        return
    end

    local rawDeltaYaw = math.AngleDifference(newAngle.y, lastViewAngle.y)
    local rawDeltaPitch = math.AngleDifference(newAngle.p, lastViewAngle.p)

    local camScale = GetConVar("swingdoors_cl_camera_sensitivity"):GetFloat()
    local dampened = Angle(
        lastViewAngle.p + rawDeltaPitch * camScale,
        lastViewAngle.y + rawDeltaYaw * camScale,
        newAngle.r
    )
    cmd:SetViewAngles(dampened)
    lastViewAngle = dampened

    local push = rawDeltaYaw
    if CurTime() < grabIgnoreUntil then
        push = 0
    elseif math.abs(push) < moveDeadzone then
        push = 0
    end

    if push ~= 0 then
        holdPushTotal = holdPushTotal + math.abs(push)
        local sens = GetConVar("swingdoors_cl_push_sensitivity"):GetFloat()
        pendingNudge = pendingNudge + push * sens
    end

    if pendingNudge ~= 0 and CurTime() >= nextNudgeSend then
        net.Start("SwingDoors_Nudge")
            net.WriteFloat(pendingNudge)
        net.SendToServer()
        pendingNudge = 0
        nextNudgeSend = CurTime() + NUDGE_SEND_INTERVAL
    end
end)

hook.Add("OnPauseMenuShow", "SwingDoors_ReleaseOnMenu", function()
    if holding then
        DBG("Pause menu opened -> ending hold")
        EndHold()
    end
end)

concommand.Add("swingdoors_cl_check", function()
    local ply = LocalPlayer()
    local eye = ply:GetEyeTrace()
    local ent = eye.Entity

    local out = {}
    local function P(fmt, ...) out[#out + 1] = string.format(fmt, ...) end

    P("=== swingdoors_cl_check ===")
    P("Looking at: %s", tostring(ent))
    if IsValid(ent) then
        P("Class: %s", ent:GetClass())
    end
    P("IsSwingable: %s", tostring(IsSwingable(ent)))
    P("holding: %s", tostring(holding))
    local byKey = SwingDoors.Settings.ByKey
    P("camera_sensitivity=%s push_sensitivity=%s reach_distance=%s",
        SwingDoors.Settings.Format(byKey.cameraSensitivity, GetConVar(byKey.cameraSensitivity.cvar):GetFloat()),
        SwingDoors.Settings.Format(byKey.pushSensitivity, GetConVar(byKey.pushSensitivity.cvar):GetFloat()),
        SwingDoors.Settings.Format(byKey.reachDistance, ReachDistance()))
    P("=== end check ===")

    print(table.concat(out, "\n"))
end, nil, "Print swing-door details for the door you look at.")

concommand.Add("swingdoors_cl_debug", function(_, _, args)
    if args[1] ~= nil then
        Debug.enabled = tobool(args[1])
    else
        Debug.enabled = not Debug.enabled
    end
    print("[SwingDoors] client debug logging " .. (Debug.enabled and "ENABLED" or "DISABLED"))
end, nil, "Toggle swing-door client debug logging: swingdoors_cl_debug [1|0].")

net.Receive("SwingDoors_Status", function()
    local lines = { "[SwingDoors] current client settings:" }
    for _, def in ipairs(SwingDoors.Settings.Schema) do
        if def.realm == "cl" then
            local cv = GetConVar(def.cvar)
            local shown
            if def.kind == "key" then
                shown = string.format("%s (%d)", tostring(input.GetKeyName(cv:GetInt()) or "?"), cv:GetInt())
            else
                shown = SwingDoors.Settings.Format(def, cv:GetFloat())
            end
            lines[#lines + 1] = string.format("  %s = %s (default %s)", def.cvar, shown, def.kind == "key" and tostring(def.default) or SwingDoors.Settings.Format(def, def.default))
        end
    end
    lines[#lines + 1] = string.format("  swingdoors_cl_debug: %s", tostring(Debug.enabled))
    print(table.concat(lines, "\n"))
end)

net.Receive("SwingDoors_Print", function()
    print(net.ReadString())
end)

-- US1: Z-City paints a per-door hint ("E open normally / ALT+E slower ...") that is
-- wrong while SwingDoors owns the door. Swap it while enabled, restore it when not.
local function KeyLabel(cvar)
    return string.upper(input.LookupBinding("+use") or input.GetKeyName(GetConVar(cvar):GetInt()) or "?")
end

timer.Create("SwingDoors_ZCityHint", 0.25, 0, function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not markup then return end

    local ent = ply:GetEyeTrace().Entity
    if not IsValid(ent) or not ent.HudHintMarkup or not swingableClasses[ent:GetClass()] then return end

    if IsSwingable(ent) then
        if ent.SwingDoors_OrigHint then return end
        ent.SwingDoors_OrigHint = { ent.HudHintMarkup, ent.HowToUseInstructions, ent.AdditionalInfoFunc }
        ent.HowToUseInstructions =
            "<font=ZCity_Tiny>" .. KeyLabel("swingdoors_cl_drag_key") .. " tap to open or close</font>\n" ..
            "<font=ZCity_Tiny>" .. KeyLabel("swingdoors_cl_drag_key") .. " hold + move mouse to swing</font>\n"
        ent.HudHintMarkup = markup.Parse("<font=ZCity_Tiny>Door</font>\n<font=ZCity_SuperTiny><colour=125,125,125>" .. ent.HowToUseInstructions .. "</colour></font>", 450)
        ent.AdditionalInfoFunc = function() return "" end
    elseif ent.SwingDoors_OrigHint then
        ent.HudHintMarkup, ent.HowToUseInstructions, ent.AdditionalInfoFunc = unpack(ent.SwingDoors_OrigHint, 1, 3)
        ent.SwingDoors_OrigHint = nil
    end
end)
