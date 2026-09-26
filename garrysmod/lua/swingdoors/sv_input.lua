SwingDoors = SwingDoors or {}
SwingDoors.Input = SwingDoors.Input or {}

local CONFIG = SwingDoors.Config
local CONST = SwingDoors.Const
local DBG = SwingDoors.DBG
local SOUNDS = SwingDoors.Sounds
local Geometry = SwingDoors.Geometry
local Handle = SwingDoors.Handle
local Sessions = SwingDoors.Sessions

local sessions = Sessions.Sessions
local doorSessions = Sessions.DoorSessions
local pendingNativeGrabs = Sessions.PendingNativeGrabs

local DOOR_REQUEST_MIN_INTERVAL = 0.1

local function MakeThrottle(name, minInterval)
    local lastAt = {}

    hook.Add("PlayerDisconnected", "SwingDoors_Clear" .. name .. "Throttle", function(ply)
        lastAt[ply] = nil
    end)

    return function(ply)
        local now = CurTime()
        if (lastAt[ply] or 0) + minInterval > now then return false end
        lastAt[ply] = now
        return true
    end
end

local fullSwingThrottle = MakeThrottle("FullSwing", DOOR_REQUEST_MIN_INTERVAL)
local grabThrottle = MakeThrottle("Grab", DOOR_REQUEST_MIN_INTERVAL)

local function DenyIfLatched(ply, door)
    if not Geometry.IsLatched(door) then return false end
    if CurTime() < (door.SwingDoors_NextDenied or 0) then return true end
    door.SwingDoors_NextDenied = CurTime() + 0.4

    door:EmitSound(SOUNDS.denied, 70, 100, CONFIG.soundVolume)
    Handle.HandleImpulse(door, Handle.ANGLE_DENIED, Handle.DENIED_HOLD, 0, true)

    SwingDoors.MapIO.Fire(door, "OnLockedUse", ply)
    return true
end

local function AcceptDoorRequest(ply, throttle, whoFor)
    if not IsValid(ply) then return nil end
    if not throttle(ply) then return nil end

    local door = net.ReadEntity()
    if not Geometry.IsSwingable(door, whoFor) then return nil end

    if not ply:Alive() or ply:GetObserverMode() ~= OBS_MODE_NONE then return nil end
    -- Z-City: mirrors its PlayerUse "restrictuser" hook, and the unconscious cannot act.
    local org = ply.organism
    if org and (org.handcuffed or org.otrub) then return nil end

    local eye, eyeDist = SwingDoors.EyeTrace(ply, CONFIG.reachDistance)
    if eye.Entity ~= door then return nil end
    if eyeDist > CONFIG.reachDistance then return nil end

    if DenyIfLatched(ply, door) then return nil end

    local useHooks = hook.GetTable().PlayerUse
    local oneShot = useHooks and useHooks["dooruse" .. door:EntIndex()]
    if isfunction(oneShot) then oneShot(ply, door) end

    return door
end

local function FreeOwnSession(ply, door, allowSameDoor)
    local own = sessions[ply]
    if not own then return true end
    if own.door == door then return allowSameDoor end
    if not own.coasting then return false end

    Sessions.DetachCoastingSession(ply)
    return true
end

net.Receive("SwingDoors_FullSwing", function(_, ply)
    local door = AcceptDoorRequest(ply, fullSwingThrottle, "FullSwing")
    if not door then return end

    local ownerPly, existing, fromDoorSessions = Sessions.FindActiveSessionForDoor(door)

    if existing and existing.mode == "drag" and not existing.coasting then
        return
    end

    if not FreeOwnSession(ply, door, true) then return end

    Sessions.StartOrRetargetAutoSession(ply, door, ownerPly, existing, fromDoorSessions)
    if SwingDoors.Impact then SwingDoors.Impact.SwingPartners(ply, door) end
end)

net.Receive("SwingDoors_Grab", function(_, ply)
    local door = AcceptDoorRequest(ply, grabThrottle, "Grab")
    if not door then return end

    local holder = door.SwingDoors_HeldBy
    if IsValid(holder) then
        local existing = sessions[holder]
        local fromDoorSessions = false
        if not existing then
            existing = doorSessions[door]
            fromDoorSessions = existing ~= nil
        end

        if existing and existing.door == door and (existing.coasting or existing.mode == "auto") then
            if holder ~= ply and not FreeOwnSession(ply, door, false) then return end

            if fromDoorSessions then
                doorSessions[door] = nil
                if existing.mode == "auto" and IsValid(holder) and holder ~= ply then
                    net.Start("SwingDoors_ForceRelease")
                    net.Send(holder)
                end
            else
                sessions[holder] = nil
            end
            door.SwingDoors_HeldBy = ply
            sessions[ply] = existing

            door.SwingDoors_ControlUntil = CurTime() + CONFIG.stealProofWindow
            existing.coasting = false
            existing.mode = "drag"

            existing.bodyPush = false
            existing.pusher = nil
            existing.reverseLockUntil = 0
            Handle.SetHandleTarget(door, Handle.GrabAngleForOffset(math.abs(existing.offset)), false)
            DBG("Grab TAKEOVER for %s: offset=%.2f angVel=%.2f", ply:Nick(), existing.offset, existing.angVel)
            return
        end

        if not existing or existing.door ~= door then return end
        if CurTime() < (door.SwingDoors_ControlUntil or 0) then return end

        sessions[holder] = nil
        door.SwingDoors_HeldBy = ply
        door.SwingDoors_ControlUntil = CurTime() + CONFIG.stealProofWindow
        sessions[ply] = existing

        net.Start("SwingDoors_ForceRelease")
        net.Send(holder)

        DBG("Grab STOLEN by %s from %s (control window expired): offset=%.2f",
            ply:Nick(), holder:Nick(), existing.offset)
        return
    end

    if not FreeOwnSession(ply, door, false) then return end

    local nativeState = door:GetInternalVariable("m_eDoorState")
    if nativeState == 1 or nativeState == 3 then
        pendingNativeGrabs[ply] = { door = door, requestedAt = CurTime() }
        DBG("Grab QUEUED for %s: door mid native transition (state=%d)", ply:Nick(), nativeState)
        return
    end

    Sessions.StartSession(ply, door)
end)

local NUDGE_MIN_INTERVAL = (engine.TickInterval() or (1 / 66)) * 0.5
local NUDGE_MAX_DELTA = 200

SwingDoors.Input.LastNudgeAt = {}
local lastNudgeAt = SwingDoors.Input.LastNudgeAt

net.Receive("SwingDoors_Nudge", function(_, ply)
    local delta = net.ReadFloat()
    if not IsValid(ply) then return end

    local now = CurTime()
    if (lastNudgeAt[ply] or 0) + NUDGE_MIN_INTERVAL > now then return end
    lastNudgeAt[ply] = now

    delta = math.Clamp(delta, -NUDGE_MAX_DELTA, NUDGE_MAX_DELTA)

    local s = sessions[ply]
    if not s or s.coasting or s.mode == "auto" then return end

    if not IsValid(s.door) or SwingDoors.PlayerPos(ply):Distance(s.door:GetPos()) > CONFIG.reachDistance + 20 then
        net.Start("SwingDoors_ForceRelease")
        net.Send(ply)
        Sessions.EndSession(ply)
        return
    end

    if CurTime() < s.reverseLockUntil then return end

    local push = delta * CONST.springStrength

    if s.offset <= s.lo and push < 0 then return end
    if s.offset >= s.hi and push > 0 then return end

    s.angVel = math.Clamp(s.angVel + push, -CONFIG.maxSwingSpeed, CONFIG.maxSwingSpeed)
end)

local function HandleLetGo(ply)
    pendingNativeGrabs[ply] = nil
    local s = sessions[ply]
    if s then s.coasting = true end
end

net.Receive("SwingDoors_LetGo", function(_, ply)
    HandleLetGo(ply)
end)
