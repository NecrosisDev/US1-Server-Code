SwingDoors = SwingDoors or {}
SwingDoors.Collision = SwingDoors.Collision or {}

local CONFIG = SwingDoors.Config
local CONST = SwingDoors.Const

function SwingDoors.Collision.AabbVsDoorOverlapDepthAt(aCenter, aHalf, doorPos, doorAng, dMins, dMaxs, margin)
    local bHalf = (dMaxs - dMins) * 0.5
    local bCenter = LocalToWorld((dMaxs + dMins) * 0.5, angle_zero, doorPos, doorAng)

    local ax, ay, az = doorAng:Forward(), doorAng:Right(), doorAng:Up()
    local delta = bCenter - aCenter

    local axes = { Vector(1, 0, 0), Vector(0, 1, 0), Vector(0, 0, 1), ax, ay, az }
    local minOverlap = math.huge

    for _, axis in ipairs(axes) do
        local dist = math.abs(delta:Dot(axis))
        local aProj = aHalf.x * math.abs(axis.x) + aHalf.y * math.abs(axis.y) + aHalf.z * math.abs(axis.z)
        local bProj = bHalf.x * math.abs(axis:Dot(ax)) + bHalf.y * math.abs(axis:Dot(ay)) + bHalf.z * math.abs(axis:Dot(az))
        local overlap = (aProj + bProj - margin) - dist
        if overlap <= 0 then return 0 end
        if overlap < minOverlap then minOverlap = overlap end
    end

    return minOverlap
end

function SwingDoors.Collision.AabbVsDoorOverlapDepth(aCenter, aHalf, door, margin)
    if not IsValid(door) then return 0 end
    local dMins, dMaxs = door:OBBMins(), door:OBBMaxs()
    return SwingDoors.Collision.AabbVsDoorOverlapDepthAt(aCenter, aHalf, door:GetPos(), door:GetAngles(), dMins, dMaxs, margin)
end

function SwingDoors.Collision.EntityOverlapDepth(ent, door, margin)
    if not IsValid(ent) or not IsValid(door) then return 0 end
    local mins, maxs = ent:GetCollisionBounds()
    local aHalf = (maxs - mins) * 0.5
    local aCenter = ent:GetPos() + (maxs + mins) * 0.5
    return SwingDoors.Collision.AabbVsDoorOverlapDepth(aCenter, aHalf, door, margin)
end

function SwingDoors.Collision.ComputePlayerPushOut(ent, door, margin)
    if not IsValid(ent) or not IsValid(door) then return nil end

    local mins, maxs = ent:GetCollisionBounds()
    local aHalf = (maxs - mins) * 0.5
    local aCenter = ent:GetPos() + (maxs + mins) * 0.5

    local dMins, dMaxs = door:OBBMins(), door:OBBMaxs()
    local bHalf = (dMaxs - dMins) * 0.5
    local bCenter = door:LocalToWorld((dMaxs + dMins) * 0.5)

    local ax, ay, az = door:GetForward(), door:GetRight(), door:GetUp()
    local delta = bCenter - aCenter

    local axes = { Vector(1, 0, 0), Vector(0, 1, 0), Vector(0, 0, 1), ax, ay, az }
    local minOverlap, pushDir = math.huge, nil

    for _, axis in ipairs(axes) do
        local dist = math.abs(delta:Dot(axis))
        local aProj = aHalf.x * math.abs(axis.x) + aHalf.y * math.abs(axis.y) + aHalf.z * math.abs(axis.z)
        local bProj = bHalf.x * math.abs(axis:Dot(ax)) + bHalf.y * math.abs(axis:Dot(ay)) + bHalf.z * math.abs(axis:Dot(az))
        local overlap = (aProj + bProj - margin) - dist
        if overlap <= 0 then return nil end
        if overlap < minOverlap then
            minOverlap = overlap
            local sign = (delta:Dot(axis) >= 0) and -1 or 1
            pushDir = axis * sign
        end
    end

    if not pushDir then return nil end
    return pushDir, minOverlap
end

local STUCK_PUSH_CLEARANCE = 0.75
local STUCK_HARD_DEPTH = 5

function SwingDoors.Collision.UnstickPlayersFromDoor(door, nearby)
    if not IsValid(door) then return end
    local doorPos = door:GetPos()
    local radiusSqr = (CONFIG.reachDistance + 60) ^ 2
    nearby = nearby or ents.FindInSphere(doorPos, CONFIG.reachDistance + 60)

    for _, ent in ipairs(nearby) do
        if IsValid(ent) and ent ~= door and ent:IsPlayer() and ent:Alive() and not SwingDoors.PlayerBody(ent)
            and ent:GetPos():DistToSqr(doorPos) <= radiusSqr then
            local pushDir, depth = SwingDoors.Collision.ComputePlayerPushOut(ent, door, CONST.contactMargin)
            if pushDir and depth and depth > STUCK_HARD_DEPTH then
                ent:SetPos(ent:GetPos() + pushDir * (depth + STUCK_PUSH_CLEARANCE))
            end
        end
    end
end

local PUSHABLE_PROP_CLASSES = {
    prop_physics             = true,
    prop_physics_multiplayer = true,
}

local BLOCKING_STATIC_CLASSES = {
    prop_dynamic          = true,
    prop_dynamic_override = true,
    func_physbox           = true,
}

function SwingDoors.Collision.IsBlockingEntity(ent)
    if not IsValid(ent) then return false end
    if ent:IsPlayer() then return ent:Alive() and not SwingDoors.PlayerBody(ent) end
    if ent:IsNPC() then return ent:Health() > 0 end
    if BLOCKING_STATIC_CLASSES[ent:GetClass()] then return true end

    if PUSHABLE_PROP_CLASSES[ent:GetClass()] then
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) and phys:HasGameFlag(FVPHYSICS_PLAYER_HELD) then
            return true
        end
    end

    return false
end

local IGNORE_SET_SWEEP_SAMPLES = 6

function SwingDoors.Collision.ComputeStructuralIgnoreSet(door, base, lo, hi)
    local ignore = {}
    if not IsValid(door) then return ignore end

    local doorPos = door:GetPos()
    local dMins, dMaxs = door:OBBMins(), door:OBBMaxs()

    local angles = {}
    if base and lo and hi then
        for i = 0, IGNORE_SET_SWEEP_SAMPLES do
            local offset = lo + (hi - lo) * (i / IGNORE_SET_SWEEP_SAMPLES)
            angles[#angles + 1] = Angle(base.p, base.y + offset, base.r)
        end
    else
        angles[1] = door:GetAngles()
    end

    local nearby = ents.FindInSphere(doorPos, CONFIG.reachDistance + 100)
    for _, ent in ipairs(nearby) do
        if ent ~= door and IsValid(ent) and BLOCKING_STATIC_CLASSES[ent:GetClass()] then
            local mins, maxs = ent:GetCollisionBounds()
            local aHalf = (maxs - mins) * 0.5
            local aCenter = ent:GetPos() + (maxs + mins) * 0.5
            for _, ang in ipairs(angles) do
                if SwingDoors.Collision.AabbVsDoorOverlapDepthAt(aCenter, aHalf, doorPos, ang, dMins, dMaxs, CONST.contactMargin) > 0.05 then
                    ignore[ent] = true
                    break
                end
            end
        end
    end

    return ignore
end

local BLOCK_SUBSTEP_DEG = 1.0
local BLOCK_MAX_SUBSTEPS = 8

function SwingDoors.Collision.FindBlockingEntity(door, prevAngle, candidateAngle, ignoreSet, nearby)
    if not IsValid(door) then return nil end
    local doorPos = door:GetPos()
    local dMins, dMaxs = door:OBBMins(), door:OBBMaxs()

    nearby = nearby or ents.FindInSphere(doorPos, CONFIG.reachDistance + 100)
    local radiusSqr = (CONFIG.reachDistance + 100) ^ 2

    local yawDelta = math.AngleDifference(candidateAngle.y, prevAngle.y)
    local steps = math.Clamp(math.ceil(math.abs(yawDelta) / BLOCK_SUBSTEP_DEG), 1, BLOCK_MAX_SUBSTEPS)

    for _, ent in ipairs(nearby) do
        if ent ~= door and not (ignoreSet and ignoreSet[ent]) and SwingDoors.Collision.IsBlockingEntity(ent)
            and ent:GetPos():DistToSqr(doorPos) <= radiusSqr then
            local mins, maxs = ent:GetCollisionBounds()
            local aHalf = (maxs - mins) * 0.5
            local aCenter = ent:GetPos() + (maxs + mins) * 0.5

            local depthPrev = SwingDoors.Collision.AabbVsDoorOverlapDepthAt(aCenter, aHalf, doorPos, prevAngle, dMins, dMaxs, CONST.contactMargin)

            for i = 1, steps do
                local t = i / steps
                local sampleAngle = Angle(prevAngle.p, prevAngle.y + yawDelta * t, prevAngle.r)
                local depthNow = SwingDoors.Collision.AabbVsDoorOverlapDepthAt(aCenter, aHalf, doorPos, sampleAngle, dMins, dMaxs, CONST.contactMargin)

                if depthNow > 0.02 and depthNow > depthPrev + 0.02 then
                    return ent
                end

                depthPrev = depthNow
            end
        end
    end

    return nil
end

function SwingDoors.Collision.GetEjectVector(door, worldPos)
    local localPos = door:WorldToLocal(worldPos)
    local mins, maxs = door:OBBMins(), door:OBBMaxs()
    local axes = { "x", "y", "z" }

    local bestAxis, bestDepth, bestSign = nil, math.huge, 1
    for _, axis in ipairs(axes) do
        local p = localPos[axis]
        local lo, hi = mins[axis], maxs[axis]
        local distToMin, distToMax = p - lo, hi - p

        if distToMin < bestDepth then bestDepth, bestAxis, bestSign = distToMin, axis, -1 end
        if distToMax < bestDepth then bestDepth, bestAxis, bestSign = distToMax, axis, 1 end
    end
    if not bestAxis then return nil end

    local localDir = Vector(0, 0, 0)
    localDir[bestAxis] = bestSign
    local worldDir = door:LocalToWorld(localDir) - door:GetPos()
    if worldDir:LengthSqr() < 0.0001 then return nil end

    return worldDir:GetNormalized()
end

function SwingDoors.Collision.GetBlockingProps(door, nearby)
    if not IsValid(door) then return {} end
    local mins, maxs = door:OBBMins(), door:OBBMaxs()
    local doorPos = door:GetPos()
    local radiusSqr = CONST.propCheckRadius ^ 2
    nearby = nearby or ents.FindInSphere(doorPos, CONST.propCheckRadius)
    local found = {}

    for _, e in ipairs(nearby) do
        if IsValid(e) and e ~= door and PUSHABLE_PROP_CLASSES[e:GetClass()]
            and e:GetPos():DistToSqr(doorPos) <= radiusSqr then
            local phys = e:GetPhysicsObject()
            local isHeld = IsValid(phys) and phys:HasGameFlag(FVPHYSICS_PLAYER_HELD)

            if not isHeld then
                local pos = door:WorldToLocal(e:GetPos())
                local pad = (e:BoundingRadius() or 0) * 0.35
                if pos.x >= mins.x - pad and pos.x <= maxs.x + pad and
                   pos.y >= mins.y - pad and pos.y <= maxs.y + pad and
                   pos.z >= mins.z - pad and pos.z <= maxs.z + pad then
                    found[#found + 1] = e
                end
            end
        end
    end

    return found
end

function SwingDoors.Collision.ApplyPropCollision(door, exclude, nearby)
    local props = SwingDoors.Collision.GetBlockingProps(door, nearby)
    if #props == 0 then return 1 end

    local slowest = 1

    for _, prop in ipairs(props) do
        local phys = prop:GetPhysicsObject()
        if IsValid(phys) then
            local mass = math.max(phys:GetMass(), 1)

            local massFactor = math.Clamp(18 / mass, 0.35, 1.0)

            local ejectDir = SwingDoors.Collision.GetEjectVector(door, prop:GetPos())
            if ejectDir then
                phys:SetVelocityInstantaneous(ejectDir * (CONST.propEjectSpeed * massFactor))
                phys:Wake()
            end

            local slowdown = math.Clamp(mass / 25, 0.2, 0.9)
            local factor = 1 - slowdown
            if factor < slowest then slowest = factor end
        end
    end

    return slowest
end
