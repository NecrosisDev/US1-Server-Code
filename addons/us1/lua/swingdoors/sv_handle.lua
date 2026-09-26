SwingDoors = SwingDoors or {}
SwingDoors.Handle = SwingDoors.Handle or {}

local CONST = SwingDoors.Const

local HANDLE_BONE_NAMES = { "handle", "handle02" }
local HANDLE_MAX_HITBOX_SIZE = 16

SwingDoors.Handle.ANGLE_GRAB     = 20
SwingDoors.Handle.ANGLE_GRAB_MIN = 5
SwingDoors.Handle.ANGLE_SPIKE    = 35
SwingDoors.Handle.ANGLE_TOUCH    = 14
SwingDoors.Handle.ANGLE_DENIED   = 6

SwingDoors.Handle.SPIKE_HOLD  = 0.10
SwingDoors.Handle.DENIED_HOLD = 0.08

local HANDLE_STIFFNESS        = 900
local HANDLE_STIFFNESS_BOUNCY = 550
local HANDLE_BOUNCE_RATIO     = 0.4

local HANDLE_MAX_SUBSTEP = 1 / 120

local handleAnimators = {}

local function BoneLooksLikeHandle(door, boneID)
    local setCount = door.GetHitboxSetCount and door:GetHitboxSetCount() or 0
    local found = false

    for hs = 0, setCount - 1 do
        local hbCount = door:GetHitBoxCount(hs)
        for hb = 0, hbCount - 1 do
            if door:GetHitBoxBone(hb, hs) == boneID then
                found = true
                local mins, maxs = door:GetHitBoxBounds(hb, hs)
                if mins and maxs then
                    local size = maxs - mins
                    local biggest = math.max(size.x, size.y, size.z)
                    if biggest > HANDLE_MAX_HITBOX_SIZE then return false end
                end
            end
        end
    end

    return found
end

function SwingDoors.Handle.GetHandleBoneIDs(door)
    if door.SwingDoors_HandleBoneIDs ~= nil then
        return door.SwingDoors_HandleBoneIDs
    end
    local ids = {}
    for _, name in ipairs(HANDLE_BONE_NAMES) do
        local id = door:LookupBone(name)
        if id and id >= 0 and BoneLooksLikeHandle(door, id) then
            table.insert(ids, id)
        end
    end
    door.SwingDoors_HandleBoneIDs = ids
    return ids
end

local function ApplyHandleBoneAngle(door, yaw)
    local ids = SwingDoors.Handle.GetHandleBoneIDs(door)
    if #ids == 0 then return end
    local ang = Angle(0, yaw, 0)
    for _, id in ipairs(ids) do
        door:ManipulateBoneAngles(id, ang)
    end
end

local function GetOrCreateHandleAnimator(door)
    local a = handleAnimators[door]
    if not a then
        a = { angle = 0, vel = 0, target = 0, bouncy = false, timeScale = 1 }
        handleAnimators[door] = a
    end
    return a
end

function SwingDoors.Handle.SetHandleTarget(door, target, bouncy)
    if #SwingDoors.Handle.GetHandleBoneIDs(door) == 0 then return end
    local a = GetOrCreateHandleAnimator(door)
    if a.impulseUntil then
        a.impulseRevertTarget = target
        a.impulseRevertBouncy = bouncy or false
        return
    end
    a.target = target
    a.bouncy = bouncy or false
    a.timeScale = 1
end

function SwingDoors.Handle.HandleImpulse(door, angle, holdTime, revertTarget, revertBouncy, slowMult)
    if #SwingDoors.Handle.GetHandleBoneIDs(door) == 0 then return end
    local a = GetOrCreateHandleAnimator(door)
    slowMult = slowMult or 1
    a.target = angle
    a.bouncy = false
    a.timeScale = slowMult
    a.impulseUntil = CurTime() + holdTime / slowMult
    a.impulseRevertTarget = revertTarget or 0
    a.impulseRevertBouncy = revertBouncy or false
end

function SwingDoors.Handle.GrabAngleForOffset(absOffset)
    local minA, maxA = CONST.handleGrabMinAngle, CONST.handleGrabMaxAngle
    if maxA <= minA then maxA = minA + 1 end
    local proximity = 1 - math.Clamp((absOffset - minA) / (maxA - minA), 0, 1)
    return SwingDoors.Handle.ANGLE_GRAB_MIN + (SwingDoors.Handle.ANGLE_GRAB - SwingDoors.Handle.ANGLE_GRAB_MIN) * proximity
end

hook.Add("Think", "SwingDoors_HandleSpring", function()
    if next(handleAnimators) == nil then return end
    local dt = FrameTime()
    if dt <= 0 then return end
    dt = math.min(dt, 0.05)
    local now = CurTime()

    for door, a in pairs(handleAnimators) do
        if not IsValid(door) then
            handleAnimators[door] = nil
        else
            if a.impulseUntil and now >= a.impulseUntil then
                a.impulseUntil = nil
                a.target = a.impulseRevertTarget or 0
                a.bouncy = a.impulseRevertBouncy or false
            end

            local stiffness = a.bouncy and HANDLE_STIFFNESS_BOUNCY or HANDLE_STIFFNESS
            local dampingRatio = a.bouncy and HANDLE_BOUNCE_RATIO or 1
            local damping = 2 * math.sqrt(stiffness) * dampingRatio
            local scaledDt = dt * (a.timeScale or 1)

            local steps = math.max(1, math.ceil(scaledDt / HANDLE_MAX_SUBSTEP))
            local h = scaledDt / steps
            for _ = 1, steps do
                local accel = (a.target - a.angle) * stiffness - a.vel * damping
                a.vel = a.vel + accel * h
                a.angle = a.angle + a.vel * h
            end

            if a.angle ~= a.angle or a.vel ~= a.vel or math.abs(a.angle) > 360 then
                a.angle, a.vel = 0, 0
            end

            ApplyHandleBoneAngle(door, a.angle)

            if not a.impulseUntil and a.target == 0 and math.abs(a.angle) < 0.05 and math.abs(a.vel) < 0.5 then
                a.angle, a.vel = 0, 0
                ApplyHandleBoneAngle(door, 0)
                handleAnimators[door] = nil
            end
        end
    end
end)
