SwingDoors = SwingDoors or {}
SwingDoors.Sessions = SwingDoors.Sessions or {}

local CONFIG = SwingDoors.Config
local CONST = SwingDoors.Const
local DBG = SwingDoors.DBG
local SOUNDS = SwingDoors.Sounds
local Geometry = SwingDoors.Geometry
local Collision = SwingDoors.Collision
local DoorState = SwingDoors.DoorState
local Handle = SwingDoors.Handle
local Portals = SwingDoors.Portals

local VisualOffset = DoorState.VisualOffset
local SetDoorAngle = DoorState.SetDoorAngle
local baseAngles = DoorState.BaseAngles
local CLOSED_DEADZONE = DoorState.CLOSED_DEADZONE

SwingDoors.Sessions.Sessions = SwingDoors.Sessions.Sessions or {}

SwingDoors.Sessions.DoorSessions = SwingDoors.Sessions.DoorSessions or {}

SwingDoors.Sessions.PendingNativeGrabs = SwingDoors.Sessions.PendingNativeGrabs or {}

local sessions = SwingDoors.Sessions.Sessions
local doorSessions = SwingDoors.Sessions.DoorSessions
local pendingNativeGrabs = SwingDoors.Sessions.PendingNativeGrabs

function SwingDoors.Sessions.FinalizeSession(s)
    if not IsValid(s.door) then return end
    local settled = Angle(s.base.p, s.base.y + VisualOffset(s.offset), s.base.r)
    SetDoorAngle(s.door, settled)
    Portals.UpdateDoorOpenState(s.door, s.offset, s)
    s.door.SwingDoors_HeldBy = nil
    s.door.SwingDoors_RawOffset = s.offset
    Handle.SetHandleTarget(s.door, 0, true)
    DoorState.RestoreNativeMotion(s.door, s.prevMoveType)
end

function SwingDoors.Sessions.EndSession(ply)
    local s = sessions[ply]
    if not s then return end
    DBG("EndSession: closing session for %s (offset=%.2f)", IsValid(ply) and ply:Nick() or "?", s.offset)

    if IsValid(s.door) then s.door:StopSound(SOUNDS.swing) end
    SwingDoors.Sessions.FinalizeSession(s)

    sessions[ply] = nil
end

function SwingDoors.Sessions.DetachCoastingSession(ply)
    local s = sessions[ply]
    if not s or not s.coasting then return end

    sessions[ply] = nil
    s.ownerPly = ply
    doorSessions[s.door] = s

    DBG("Detached coasting session for %s (door still settling on its own, offset=%.2f)",
        IsValid(ply) and ply:Nick() or "?", s.offset)
end

function SwingDoors.Sessions.FindActiveSessionForDoor(door)
    for ply, s in pairs(sessions) do
        if s.door == door then return ply, s, false end
    end
    local s = doorSessions[door]
    if s then return nil, s, true end
    return nil, nil, false
end

local AT_LIMIT_EPSILON = 0.4

function SwingDoors.Sessions.IsAtOpenLimit(offset, lo, hi)
    local limit = offset >= 0 and hi or lo
    if limit == 0 then return false end
    return math.abs(offset - limit) < AT_LIMIT_EPSILON
end

function SwingDoors.Sessions.StartSession(ply, door)
    DoorState.RememberBaseAngle(door)
    local base = baseAngles[door] or door:GetAngles()

    local lo, hi = Geometry.GetDoorMotionBounds(door)

    local currentOffset = DoorState.GetCurrentOffset(door, base, lo, hi)

    local prevMoveType = DoorState.FreezeNativeMotion(door)
    SetDoorAngle(door, Angle(base.p, base.y + VisualOffset(currentOffset), base.r))

    door.SwingDoors_HeldBy = ply
    Handle.SetHandleTarget(door, Handle.GrabAngleForOffset(math.abs(currentOffset)), false)

    door.SwingDoors_ControlUntil = CurTime() + CONFIG.stealProofWindow

    Portals.PreOpenPortal(door)

    sessions[ply] = {
        door = door,
        base = base,
        offset = currentOffset,
        angVel = 0,
        prevMoveType = prevMoveType,
        lo = lo,
        hi = hi,
        nextSwoosh = 0,
        ignoreStatics = Collision.ComputeStructuralIgnoreSet(door, base, lo, hi),
        everOpened = math.abs(currentOffset) > 2,

        lastReportedOpen = math.abs(currentOffset) > CLOSED_DEADZONE,
        closeSoundPlayed = math.abs(currentOffset) <= 0.5,
        stopSoundPlayed = (currentOffset <= lo + 0.5) or (currentOffset >= hi - 0.5),
        fullyOpenFired = SwingDoors.Sessions.IsAtOpenLimit(currentOffset, lo, hi),

        openSoundPending = math.abs(currentOffset) <= 2,
        openSoundPlayed = false,
        coasting = false,
        reverseLockUntil = 0,
        mode = "drag",
        target = 0,
        blockedOpening = false,
        blockedClosing = false,
    }

    DBG("Grab ACCEPTED for %s: offset=%.2f bounds=[%.1f, %.1f]", ply:Nick(), currentOffset, lo, hi)
end

function SwingDoors.Sessions.ChooseOpenTarget(door, ply, base, lo, hi)
    if hi <= 0 then return lo end
    if lo >= 0 then return hi end

    local mins, maxs = door:OBBMins(), door:OBBMaxs()
    local edgeX = (math.abs(mins.x) > math.abs(maxs.x)) and mins.x or maxs.x
    local edgeY = (math.abs(mins.y) > math.abs(maxs.y)) and mins.y or maxs.y
    local edgeLocal = Vector(edgeX, edgeY, (mins.z + maxs.z) * 0.5)

    local prevAngle = door:GetAngles()

    door:SetAngles(Angle(base.p, base.y + VisualOffset(lo), base.r))
    local loPos = door:LocalToWorld(edgeLocal)

    door:SetAngles(Angle(base.p, base.y + VisualOffset(hi), base.r))
    local hiPos = door:LocalToWorld(edgeLocal)

    door:SetAngles(prevAngle)

    local plyPos = SwingDoors.PlayerPos(ply)
    if loPos:DistToSqr(plyPos) >= hiPos:DistToSqr(plyPos) then
        return lo
    end
    return hi
end

local MIN_REVERSAL_DELAY = 0.15

function SwingDoors.Sessions.StartOrRetargetAutoSession(ply, door, ownerPly, existing, fromDoorSessions, forceOpen)
    DoorState.RememberBaseAngle(door)
    local base = baseAngles[door] or door:GetAngles()
    local lo, hi, dist = Geometry.GetDoorMotionBounds(door)

    local currentOffset
    if existing then
        currentOffset = existing.offset
    else
        currentOffset = DoorState.GetCurrentOffset(door, base, lo, hi)
    end

    if existing and existing.mode == "auto" and existing.reversed then
        DBG("%s: Full Swing ignored on %s -- already reversed once this animation",
            ply:Nick(), tostring(door))
        return
    end

    if existing and existing.mode == "auto" and existing.startedAt
       and (CurTime() - existing.startedAt) < MIN_REVERSAL_DELAY then
        DBG("%s: Full Swing ignored on %s -- reversal too soon after start (%.3fs)",
            ply:Nick(), tostring(door), CurTime() - existing.startedAt)
        return
    end

    local target
    local justReversed = false
    if forceOpen ~= nil then
        -- linked leaf / bot: follow the requested direction instead of toggling
        target = forceOpen and SwingDoors.Sessions.ChooseOpenTarget(door, ply, base, lo, hi) or 0
    elseif existing and existing.mode == "auto" then
        if existing.target == 0 then
            target = SwingDoors.Sessions.ChooseOpenTarget(door, ply, base, lo, hi)
        else
            target = 0
        end
        justReversed = true
    elseif math.abs(currentOffset) < dist / 2 then
        target = SwingDoors.Sessions.ChooseOpenTarget(door, ply, base, lo, hi)
    else
        target = 0
    end

    Handle.HandleImpulse(door, Handle.ANGLE_TOUCH, Handle.SPIKE_HOLD, 0, true, target == 0 and 0.5 or 1)

    Portals.PreOpenPortal(door)

    if existing then
        if ownerPly and not fromDoorSessions then
            sessions[ownerPly] = nil
            if IsValid(ownerPly) and ownerPly ~= ply then
                net.Start("SwingDoors_ForceRelease")
                net.Send(ownerPly)
            end
        end

        existing.lo, existing.hi = lo, hi
        existing.mode = "auto"
        existing.target = target
        existing.coasting = false
        existing.bodyPush = false
        existing.pusher = nil
        existing.reverseLockUntil = 0
        existing.ownerPly = ply
        existing.blockedOpening = false
        existing.blockedClosing = false
        if justReversed then existing.reversed = true end

        if target == 0 then
            existing.everOpened = true
            existing.closeSoundPlayed = false
        end

        door.SwingDoors_HeldBy = ply
        door.SwingDoors_ControlUntil = CurTime() + CONFIG.stealProofWindow
        doorSessions[door] = existing

        DBG("%s: Full Swing retargeted existing session on %s -> target=%.1f (offset=%.2f)",
            ply:Nick(), tostring(door), target, existing.offset)
        return
    end

    local prevMoveType = DoorState.FreezeNativeMotion(door)
    SetDoorAngle(door, Angle(base.p, base.y + VisualOffset(currentOffset), base.r))

    door.SwingDoors_HeldBy = ply
    door.SwingDoors_ControlUntil = CurTime() + CONFIG.stealProofWindow

    doorSessions[door] = {
        door = door,
        base = base,
        offset = currentOffset,
        angVel = 0,
        prevMoveType = prevMoveType,
        lo = lo,
        hi = hi,
        nextSwoosh = 0,
        ignoreStatics = Collision.ComputeStructuralIgnoreSet(door, base, lo, hi),
        everOpened = math.abs(currentOffset) > 2,

        lastReportedOpen = math.abs(currentOffset) > CLOSED_DEADZONE,
        closeSoundPlayed = math.abs(currentOffset) <= 0.5,
        stopSoundPlayed = (currentOffset <= lo + 0.5) or (currentOffset >= hi - 0.5),
        fullyOpenFired = SwingDoors.Sessions.IsAtOpenLimit(currentOffset, lo, hi),

        openSoundPending = math.abs(currentOffset) <= 2,
        openSoundPlayed = false,
        coasting = false,
        reverseLockUntil = 0,
        mode = "auto",
        target = target,
        reversed = false,
        ownerPly = ply,
        startedAt = CurTime(),
        blockedOpening = false,
        blockedClosing = false,
    }

    DBG("%s: Full Swing started new auto session on %s -> target=%.1f (offset=%.2f)",
        ply:Nick(), tostring(door), target, currentOffset)
end

hook.Add("PlayerDisconnected", "SwingDoors_CleanupA", function(ply)
    pendingNativeGrabs[ply] = nil
    if SwingDoors.Input then SwingDoors.Input.LastNudgeAt[ply] = nil end
    SwingDoors.Sessions.EndSession(ply)
end)
hook.Add("PlayerDeath", "SwingDoors_CleanupB", function(ply)
    local s = sessions[ply]
    if s then s.coasting = true end
end)

local thinkTick = 0

local AUTO_TARGET_DEADZONE = 0.5
local AUTO_SPEED_FRACTION  = 0.55
local AUTO_ACCEL_MULT      = 20

local AUTO_LOOK_GRACE = 0.5
local AUTO_LOOK_COS_THRESHOLD = 0.4

function SwingDoors.Sessions.IsAutoSessionStillEngaged(s, ply)
    if not IsValid(ply) or not ply:Alive() or not IsValid(s.door) then return false end

    local toDoor = s.door:WorldSpaceCenter() - (SwingDoors.PlayerBody(ply) and SwingDoors.PlayerPos(ply) or ply:EyePos())
    local dist = toDoor:Length()
    if dist > CONFIG.reachDistance + 40 then return false end
    if dist < 1 then return true end

    return true
end

function SwingDoors.Sessions.LatchClosed(s, ply, closingSpeed)
    s.offset = 0
    s.angVel = 0
    s.reverseLockUntil = CurTime() + CONFIG.closeLatchDelay

    s.openSoundPending = true
    s.openSoundPlayed = false

    if s.everOpened and not s.closeSoundPlayed then
        SwingDoors.PlayDoorStinger(s.door, "close", closingSpeed)
        s.closeSoundPlayed = true
    end

    Handle.HandleImpulse(s.door, Handle.ANGLE_SPIKE, Handle.SPIKE_HOLD, 0, true)

    SetDoorAngle(s.door, Angle(s.base.p, s.base.y, s.base.r))
    s.door.SwingDoors_LiveOffset = 0
    s.door.SwingDoors_RawOffset = 0
    Portals.UpdateDoorOpenState(s.door, 0, s)

    SwingDoors.MapIO.Fire(s.door, "OnFullyClosed", ply)

    Collision.UnstickPlayersFromDoor(s.door)

    s.door:StopSound(SOUNDS.swing)

    if Geometry.IsLatched(s.door) then
        if not s.coasting and IsValid(ply) and s.door.SwingDoors_HeldBy == ply then
            net.Start("SwingDoors_ForceRelease")
            net.Send(ply)
        end
        s.coasting = true
    end

    DBG("%s: door reached closed -> latched for %.2fs", IsValid(ply) and ply:Nick() or "?", CONFIG.closeLatchDelay)
end

function SwingDoors.Sessions.SimulateSessionTick(s, ply, dt, logThisTick)
    if not IsValid(s.door) or (not IsValid(ply) and not (s.ownerless and s.door.SwingDoors_HeldBy == s.door)) then
        if IsValid(s.door) then s.door:StopSound(SOUNDS.swing) end
        SwingDoors.Sessions.FinalizeSession(s)
        return true
    end

    if not s.coasting and (not ply:Alive() or SwingDoors.PlayerPos(ply):Distance(s.door:GetPos()) > CONFIG.reachDistance + 40) then
        s.coasting = true

        if IsValid(ply) and s.door.SwingDoors_HeldBy == ply then
            net.Start("SwingDoors_ForceRelease")
            net.Send(ply)
        end
    end

    s.door.SwingDoors_Quiet = (not s.coasting and IsValid(ply) and ply:IsPlayer() and ply:KeyDown(IN_WALK)) or nil

    if not s.coasting and s.mode == "auto" then
        if SwingDoors.Sessions.IsAutoSessionStillEngaged(s, ply) then
            s.autoLookLostAt = nil
        else
            s.autoLookLostAt = s.autoLookLostAt or CurTime()
            if CurTime() - s.autoLookLostAt >= AUTO_LOOK_GRACE then
                s.coasting = true
                if IsValid(ply) and s.door.SwingDoors_HeldBy == ply then
                    net.Start("SwingDoors_ForceRelease")
                    net.Send(ply)
                end
            end
        end
    end

    if s.mode == "drag" and not s.bodyPush then
        if s.coasting then
            Handle.SetHandleTarget(s.door, 0, true)
        else
            Handle.SetHandleTarget(s.door, Handle.GrabAngleForOffset(math.abs(s.offset)), false)
        end
    end

    if CurTime() < s.reverseLockUntil then
        s.offset = 0
        s.angVel = 0
        SetDoorAngle(s.door, Angle(s.base.p, s.base.y, s.base.r))
        s.door:StopSound(SOUNDS.swing)
        if s.coasting then
            SwingDoors.Sessions.FinalizeSession(s)
            return true
        end
        return false
    end

    if s.bodyPush then
        SwingDoors.BodyPush.ApplyBodyPushForce(s, dt)
    end

    if s.mode == "auto" and not s.coasting then
        local dir = 0
        if s.offset < s.target - AUTO_TARGET_DEADZONE then
            dir = 1
        elseif s.offset > s.target + AUTO_TARGET_DEADZONE then
            dir = -1
        end

        if CurTime() < s.reverseLockUntil then dir = 0 end

        local desiredVel = dir * CONFIG.maxSwingSpeed * AUTO_SPEED_FRACTION
        s.angVel = math.Approach(s.angVel, desiredVel, CONST.springStrength * AUTO_ACCEL_MULT * dt)
    else
        local damp = s.coasting and CONFIG.coastResistance or CONST.dragDamping
        s.angVel = math.Approach(s.angVel, 0, math.abs(s.angVel) * damp * dt + 5 * dt)
    end

    local prevOffset = s.offset
    local proposed = math.Clamp(s.offset + s.angVel * dt, s.lo, s.hi)

    local doorPos = s.door:GetPos()
    local tickNearby = nil
    local function GetTickNearby()
        if not tickNearby then
            local radius = math.max(CONFIG.reachDistance + 100, CONST.propCheckRadius)
            tickNearby = ents.FindInSphere(doorPos, radius)
        end
        return tickNearby
    end

    local angleSynced = false

    if math.abs(proposed - prevOffset) > 0.0001 then
        local prevAngle = Angle(s.base.p, s.base.y + VisualOffset(prevOffset), s.base.r)
        local candidateAngle = Angle(s.base.p, s.base.y + VisualOffset(proposed), s.base.r)

        local attemptingOpen = math.abs(proposed) > math.abs(prevOffset)

        local blockingEnt = Collision.FindBlockingEntity(s.door, prevAngle, candidateAngle, s.ignoreStatics, GetTickNearby())
        if blockingEnt then
            SwingDoors.MapIO.ReportBlocked(s, blockingEnt, attemptingOpen)

            SetDoorAngle(s.door, prevAngle)
            angleSynced = true
            proposed = prevOffset

            if IsValid(blockingEnt) and blockingEnt:IsPlayer() and math.abs(s.angVel) > CONST.bounceMinSpeed then
                if SwingDoors.Impact then SwingDoors.Impact.SlamPlayer(s, blockingEnt, ply) end
                s.angVel = -s.angVel * CONST.bounceRestitution
                s.stopSoundPlayed = false
                SwingDoors.PlayDoorStinger(s.door, "stop", math.abs(s.angVel))
            else
                s.angVel = 0
            end
        else
            SwingDoors.MapIO.ReportUnblocked(s)

            SetDoorAngle(s.door, candidateAngle)
            angleSynced = true
            local propFactor = Collision.ApplyPropCollision(s.door, ply, GetTickNearby())
            if propFactor < 1 then
                s.angVel = s.angVel * propFactor
                proposed = math.Clamp(prevOffset + s.angVel * dt, s.lo, s.hi)
                SetDoorAngle(s.door, Angle(s.base.p, s.base.y + VisualOffset(proposed), s.base.r))
            end
            if SwingDoors.Impact then SwingDoors.Impact.ShoveRagdolls(s, GetTickNearby(), dt) end
        end
    end

    local crossedZero = (prevOffset > 0 and proposed <= 0) or (prevOffset < 0 and proposed >= 0)
    local wasAtZero = math.abs(prevOffset) < 0.05

    if crossedZero and not wasAtZero and s.target == 0 then
        local closingSpeed = math.abs(s.angVel)

        SwingDoors.Sessions.LatchClosed(s, ply, closingSpeed)

        if s.coasting or s.mode == "auto" then
            SwingDoors.Sessions.FinalizeSession(s)
            return true
        end
        return false
    end

    s.offset = proposed

    if s.openSoundPending and not s.openSoundPlayed and math.abs(s.offset) > SwingDoors.OPEN_SOUND_THRESHOLD then
        SwingDoors.PlayDoorStinger(s.door, "open", math.max(math.abs(s.angVel), SwingDoors.OPEN_STINGER_BASELINE_SPEED))
        s.openSoundPlayed = true

        local openRevertTarget = 0
        if s.mode == "drag" and not s.bodyPush and not s.coasting then
            openRevertTarget = Handle.GrabAngleForOffset(math.abs(s.offset))
        end
        Handle.HandleImpulse(s.door, Handle.ANGLE_SPIKE, Handle.SPIKE_HOLD, openRevertTarget, openRevertTarget == 0)
    end

    if math.abs(s.offset) > 2 then s.everOpened = true end

    local atLimit = math.abs(s.offset - (s.offset >= 0 and s.hi or s.lo)) < AT_LIMIT_EPSILON
    if atLimit then
        if not s.stopSoundPlayed and math.abs(s.angVel) > 3 then
            SwingDoors.PlayDoorStinger(s.door, "stop", math.abs(s.angVel))
            s.stopSoundPlayed = true
        end
        s.angVel = 0
    else
        s.stopSoundPlayed = false
    end

    if SwingDoors.Sessions.IsAtOpenLimit(s.offset, s.lo, s.hi) then
        if not s.fullyOpenFired then
            s.fullyOpenFired = true

            SwingDoors.MapIO.Fire(s.door, "OnFullyOpen")
        end
    else
        s.fullyOpenFired = false
    end

    if math.abs(s.offset) > 0.5 then
        s.closeSoundPlayed = false
    end

    if not angleSynced then
        SetDoorAngle(s.door, Angle(s.base.p, s.base.y + VisualOffset(s.offset), s.base.r))
    end
    s.door.SwingDoors_LiveOffset = VisualOffset(s.offset)
    s.door.SwingDoors_RawOffset = s.offset
    Portals.UpdateDoorOpenState(s.door, s.offset, s)

    Collision.UnstickPlayersFromDoor(s.door, GetTickNearby())

    if logThisTick then
        DBG("Tick[%s]: offset=%.2f angVel=%.2f coasting=%s",
            IsValid(ply) and ply:Nick() or "?", s.offset, s.angVel, tostring(s.coasting))
    end

    local speed = math.abs(s.angVel)
    if speed > SwingDoors.SWOOSH_START_SPEED then
        if not s.swooshPlaying and CurTime() >= (s.nextSwoosh or 0) then
            local vol, pitch = SwingDoors.ComputeSwoosh(speed, CONFIG.maxSwingSpeed)
            s.door:EmitSound(SOUNDS.swing, 70, pitch, vol * CONFIG.soundVolume, CHAN_STATIC)
            s.swooshPlaying = true
            s.nextSwoosh = CurTime() + SwingDoors.SWOOSH_RETRIGGER_INTERVAL
        end
    else
        s.swooshPlaying = false
    end

    local reachedAutoTarget = s.mode == "auto" and math.abs(s.offset - s.target) <= AUTO_TARGET_DEADZONE
    if s.coasting then
        if speed < 0.5 or atLimit then
            SwingDoors.Sessions.FinalizeSession(s)
            return true
        end
    elseif s.mode == "auto" and reachedAutoTarget then
        if s.target == 0 then
            SwingDoors.Sessions.LatchClosed(s, ply, math.abs(s.angVel))
        end
        SwingDoors.Sessions.FinalizeSession(s)
        return true
    end

    return false
end

hook.Add("Think", "SwingDoors_Simulate", function()
    local dt = FrameTime()
    if dt <= 0 then return end
    dt = math.min(dt, 0.05)

    thinkTick = thinkTick + 1
    local logThisTick = SwingDoors.Debug.enabled and (thinkTick % 30 == 0)

    SwingDoors.BodyPush.ScanForBodyPushes()

    for ply, pending in pairs(pendingNativeGrabs) do
        local door = pending.door

        local cancel = false
        if not IsValid(ply) or not IsValid(door) or not Geometry.IsSwingable(door, "PendingGrab") then
            cancel = true
        elseif Geometry.IsLatched(door) then
            cancel = true
        elseif CurTime() - pending.requestedAt > 3 then
            cancel = true
        end

        if not cancel then
            local nativeState = door:GetInternalVariable("m_eDoorState")
            if nativeState ~= 1 and nativeState ~= 3 then
                pendingNativeGrabs[ply] = nil
                if not sessions[ply] and not IsValid(door.SwingDoors_HeldBy) then
                    SwingDoors.Sessions.StartSession(ply, door)
                end
            end
        else
            pendingNativeGrabs[ply] = nil
        end
    end

    for ply, s in pairs(sessions) do
        if SwingDoors.Sessions.SimulateSessionTick(s, ply, dt, logThisTick) then
            sessions[ply] = nil
        end
    end

    for door, s in pairs(doorSessions) do
        if SwingDoors.Sessions.SimulateSessionTick(s, s.ownerPly, dt, logThisTick) then
            doorSessions[door] = nil
        end
    end
end)
