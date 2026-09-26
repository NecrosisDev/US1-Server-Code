SwingDoors = SwingDoors or {}
SwingDoors.BodyPush = SwingDoors.BodyPush or {}

local CONFIG = SwingDoors.Config
local CONST = SwingDoors.Const
local DBG = SwingDoors.DBG
local Geometry = SwingDoors.Geometry
local Collision = SwingDoors.Collision
local DoorState = SwingDoors.DoorState

local VisualOffset = DoorState.VisualOffset
local SetDoorAngle = DoorState.SetDoorAngle
local baseAngles = DoorState.BaseAngles
local CLOSED_DEADZONE = DoorState.CLOSED_DEADZONE

local BODY_PUSH_PROBE_DEG = 3
local BODY_PUSH_MIN_DEPTH = 0.2

function SwingDoors.BodyPush.GetPlayerPushDirection(door, ply, base, offset, lo, hi)
    if not IsValid(door) or not IsValid(ply) then return nil end

    local curAngle = Angle(base.p, base.y + VisualOffset(offset), base.r)
    door:SetAngles(curAngle)
    local curDepth = Collision.EntityOverlapDepth(ply, door, CONST.contactMargin)
    if curDepth < BODY_PUSH_MIN_DEPTH then
        door:SetAngles(curAngle)
        return nil
    end

    local fwd = math.Clamp(offset + BODY_PUSH_PROBE_DEG, lo, hi)
    local back = math.Clamp(offset - BODY_PUSH_PROBE_DEG, lo, hi)

    door:SetAngles(Angle(base.p, base.y + VisualOffset(fwd), base.r))
    local fwdDepth = Collision.EntityOverlapDepth(ply, door, CONST.contactMargin)

    door:SetAngles(Angle(base.p, base.y + VisualOffset(back), base.r))
    local backDepth = Collision.EntityOverlapDepth(ply, door, CONST.contactMargin)

    door:SetAngles(curAngle)

    if fwdDepth >= curDepth and backDepth >= curDepth then
        return nil
    end

    if fwdDepth < backDepth then
        return 1, curDepth
    end
    return -1, curDepth
end

function SwingDoors.BodyPush.StartBodyPushSession(door, ply, pushSign)
    DoorState.RememberBaseAngle(door)
    local base = baseAngles[door] or door:GetAngles()

    local lo, hi = Geometry.GetDoorMotionBounds(door)

    local currentOffset = DoorState.GetCurrentOffset(door, base, lo, hi)

    local prevMoveType = DoorState.FreezeNativeMotion(door)
    SetDoorAngle(door, Angle(base.p, base.y + VisualOffset(currentOffset), base.r))

    door.SwingDoors_HeldBy = ply
    door.SwingDoors_ControlUntil = 0

    local s = {
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
        coasting = true,
        reverseLockUntil = 0,
        bodyPush = true,
        pusher = ply,
        pushSign = pushSign,
        ownerPly = ply,
        mode = "drag",
        target = 0,
        blockedOpening = false,
        blockedClosing = false,
    }

    SwingDoors.Sessions.DoorSessions[door] = s

    DBG("%s BODY-PUSHED door open (offset=%.2f, dir=%d, bounds=[%.1f, %.1f])", ply:Nick(), currentOffset, pushSign, lo, hi)
end

function SwingDoors.BodyPush.ApplyBodyPushForce(s, dt)
    local pusher = s.pusher
    if not IsValid(pusher) or not pusher:Alive() or SwingDoors.PlayerBody(pusher) then
        s.bodyPush = false
        return
    end

    if pusher:GetPos():Distance(s.door:GetPos()) > CONFIG.reachDistance + 40 then
        s.bodyPush = false
        return
    end

    local sign, depth = SwingDoors.BodyPush.GetPlayerPushDirection(s.door, pusher, s.base, s.offset, s.lo, s.hi)
    if not sign then
        s.bodyPush = false
        return
    end

    local accel = math.Clamp(depth, 0, 10) * CONFIG.bodyPushStrength
    s.angVel = math.Clamp(s.angVel + sign * accel * dt, -CONST.bodyPushMaxAngVel, CONST.bodyPushMaxAngVel)
end

local BODY_PUSH_SCAN_INTERVAL = 0.1
local NO_ENTS = {}
local nextBodyPushScan = 0

-- perf 2026-09-21: the scan used to call ents.FindInSphere for EVERY ajar door every 0.1 s (a fresh table each, 1.3-1.5 MB/s of
-- garbage on door-heavy maps). Only alive, non-ragdolled players in that sphere can ever matter, so collect them once per scan and
-- skip the sphere query for doors none of them can reach. FindInSphere tests the entity's bounding box, not its origin, hence the
-- reach = scan radius + the player's collision-box corner length + slack. The arrays are reused: no per-scan garbage from the filter.
local PUSHER_BOUNDS_SLACK = 128
local pusherX, pusherY, pusherZ, pusherReachSqr = {}, {}, {}, {}
local pusherCount = 0

local function CollectPushers()
    local n = 0
    local radius = CONST.bodyPushScanRadius
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:Alive() and not SwingDoors.PlayerBody(ply) then
            local pos = ply:GetPos()
            local mins, maxs = ply:GetCollisionBounds()
            local ex = math.max(math.abs(mins.x), math.abs(maxs.x))
            local ey = math.max(math.abs(mins.y), math.abs(maxs.y))
            local ez = math.max(math.abs(mins.z), math.abs(maxs.z))
            local reach = radius + math.sqrt(ex * ex + ey * ey + ez * ez) + PUSHER_BOUNDS_SLACK
            n = n + 1
            pusherX[n], pusherY[n], pusherZ[n] = pos.x, pos.y, pos.z
            pusherReachSqr[n] = reach * reach
        end
    end
    pusherCount = n
end

local function AnyPusherNear(pos)
    local x, y, z = pos.x, pos.y, pos.z
    for i = 1, pusherCount do
        local dx, dy, dz = pusherX[i] - x, pusherY[i] - y, pusherZ[i] - z
        if dx * dx + dy * dy + dz * dz <= pusherReachSqr[i] then return true end
    end
    return false
end

function SwingDoors.BodyPush.ScanForBodyPushes()
    if CurTime() < nextBodyPushScan then return end
    nextBodyPushScan = CurTime() + BODY_PUSH_SCAN_INTERVAL

    local collected = false

    for door, base in pairs(baseAngles) do
        if IsValid(door) and Geometry.IsSwingable(door, "BodyPushScan")
           and not IsValid(door.SwingDoors_HeldBy)
           and not Geometry.IsLatched(door) then
            local lo, hi = Geometry.GetDoorMotionBounds(door)

            local currentOffset = DoorState.GetCurrentOffset(door, base, lo, hi)

            if math.abs(currentOffset) > CLOSED_DEADZONE then
                if not collected then
                    CollectPushers()
                    collected = true
                end
                local doorPos = door:GetPos()
                local nearby = AnyPusherNear(doorPos) and ents.FindInSphere(doorPos, CONST.bodyPushScanRadius) or NO_ENTS
                for _, ent in ipairs(nearby) do
                    if IsValid(ent) and ent ~= door and ent:IsPlayer() and ent:Alive() and not SwingDoors.PlayerBody(ent) then
                        local sign = SwingDoors.BodyPush.GetPlayerPushDirection(door, ent, base, currentOffset, lo, hi)
                        if sign then
                            SwingDoors.BodyPush.StartBodyPushSession(door, ent, sign)
                            break
                        end
                    end
                end
            end
        end
    end
end
