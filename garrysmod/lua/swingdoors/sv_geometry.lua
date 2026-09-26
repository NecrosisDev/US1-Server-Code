SwingDoors = SwingDoors or {}
SwingDoors.Geometry = SwingDoors.Geometry or {}

local CONST = SwingDoors.Const
local DBG = SwingDoors.DBG

local MIN_SANE_SWING_DEGREES = 1
local MAX_SANE_SWING_DEGREES = 170

function SwingDoors.Geometry.IsSaneAngle(ang)
    if not ang then return false end
    local p, y, r = ang.p, ang.y, ang.r

    if p ~= p or y ~= y or r ~= r then return false end
    return math.abs(p) < 100000 and math.abs(y) < 100000 and math.abs(r) < 100000
end

function SwingDoors.Geometry.ParseAngleValue(val)
    if not val then return nil end
    if isangle and isangle(val) then
        return Angle(val.p, val.y, val.r)
    end
    if isvector and isvector(val) then
        return Angle(val.x, val.y, val.z)
    end
    if isstring(val) then
        local p, y, r = string.match(val, "^%s*(-?[%d%.]+)%s+(-?[%d%.]+)%s+(-?[%d%.]+)%s*$")
        if p then
            return Angle(tonumber(p), tonumber(y), tonumber(r))
        else
            local yawOnly = tonumber(val)
            if yawOnly and yawOnly >= 0 then
                return Angle(0, yawOnly, 0)
            end
        end
    end
    if isnumber(val) and val >= 0 then
        return Angle(0, val, 0)
    end
    return nil
end

local warnedFallbackDoors = setmetatable({}, { __mode = "k" })

SwingDoors.Geometry.MotionBoundsCache = setmetatable({}, { __mode = "k" })
local doorMotionBoundsCache = SwingDoors.Geometry.MotionBoundsCache

function SwingDoors.Geometry.GetDoorMotionBounds(door)
    if IsValid(door) then
        local cached = doorMotionBoundsCache[door]
        if cached then
            return cached[1], cached[2], cached[3], cached[4], cached[5], cached[6]
        end
    end

    local dist
    local distSource = "fallback"

    if IsValid(door) and door.GetInternalVariable then
        local ok, val = pcall(door.GetInternalVariable, door, "m_flDistance")
        if ok and isnumber(val) and val == val and val ~= 0 then
            dist = val
            distSource = "native"
        end
    end

    if not dist and IsValid(door) and door.GetKeyValues then
        local ok, kv = pcall(door.GetKeyValues, door)
        if ok and istable(kv) then
            local raw = kv["distance"] or kv["Distance"]
            local d = raw and tonumber(raw)
            if d and d == d and d ~= 0 then
                dist = d
                distSource = "keyvalues"
            end
        end
    end

    if not dist or dist < MIN_SANE_SWING_DEGREES or dist > MAX_SANE_SWING_DEGREES then
        dist = math.Clamp(CONST.swingLimit, MIN_SANE_SWING_DEGREES, MAX_SANE_SWING_DEGREES)
        distSource = "fallback"

        if IsValid(door) and SwingDoors.Debug.enabled and not warnedFallbackDoors[door] then
            warnedFallbackDoors[door] = true
            DBG("%s (%s): couldn't read a real per-door swing angle (native/keyvalues both failed or out of [%d,%d] range) -- using SwingDoors.Const.swingLimit=%.0f as fallback. Run swingdoors_sv_check while looking at it for details.",
                door:GetClass(), tostring(door), MIN_SANE_SWING_DEGREES, MAX_SANE_SWING_DEGREES, CONST.swingLimit)
        end
    end

    local opendir = 0
    if IsValid(door) and door.GetInternalVariable then
        local ok, val = pcall(door.GetInternalVariable, door, "opendir")
        if ok and isnumber(val) then opendir = val end
    end
    if opendir == 0 and IsValid(door) and door.GetKeyValues then
        local ok, kv = pcall(door.GetKeyValues, door)
        if ok and istable(kv) and kv["opendir"] then
            local od = tonumber(kv["opendir"])
            if od then opendir = od end
        end
    end

    local spawnflags = 0
    if IsValid(door) and door.GetSpawnFlags then
        local ok, sf = pcall(door.GetSpawnFlags, door)
        if ok and isnumber(sf) then spawnflags = sf end
    end
    if spawnflags == 0 and IsValid(door) and door.GetInternalVariable then
        local ok, sf = pcall(door.GetInternalVariable, door, "spawnflags")
        if ok then
            local n = tonumber(sf)
            if n then spawnflags = n end
        end
    end

    local rotateBackwards = (bit.band(tonumber(spawnflags) or 0, 2) ~= 0)

    local lo, hi = -dist, dist
    if opendir == 2 then
        lo, hi = 0, dist
    elseif opendir == 1 then
        lo, hi = -dist, 0
    end

    if rotateBackwards and opendir ~= 0 then
        lo, hi = -hi, -lo
    end

    if IsValid(door) then
        doorMotionBoundsCache[door] = { lo, hi, dist, opendir, spawnflags, distSource }
    end

    return lo, hi, dist, opendir, spawnflags, distSource
end

local AUTHORED_CLOSED_FIELDS = { "m_angRotationClosed", "m_vecAngle1" }

function SwingDoors.Geometry.GetAuthoredClosedAngle(door)
    if not IsValid(door) then return nil end

    local IsSaneAngle = SwingDoors.Geometry.IsSaneAngle
    local ParseAngleValue = SwingDoors.Geometry.ParseAngleValue

    if door.GetSaveTable then
        local ok, save = pcall(door.GetSaveTable, door)
        if ok and istable(save) then
            for _, field in ipairs(AUTHORED_CLOSED_FIELDS) do
                if save[field] then
                    local ang = ParseAngleValue(save[field])
                    if ang and IsSaneAngle(ang) then return ang end
                end
            end
        end
    end

    if door.GetSaveValue then
        for _, field in ipairs(AUTHORED_CLOSED_FIELDS) do
            local ok, val = pcall(door.GetSaveValue, door, field)
            if ok and val ~= nil then
                local ang = ParseAngleValue(val)
                if ang and IsSaneAngle(ang) then return ang end
            end
        end
    end

    if door.GetInternalVariable then
        for _, field in ipairs(AUTHORED_CLOSED_FIELDS) do
            local ok, val = pcall(door.GetInternalVariable, door, field)
            if ok and val ~= nil then
                local ang = ParseAngleValue(val)
                if ang and IsSaneAngle(ang) then return ang end
            end
        end
    end

    if door.GetKeyValues then
        local ok, kv = pcall(door.GetKeyValues, door)
        if ok and istable(kv) then
            local raw = kv["angles"] or kv["Angles"] or kv["angle"] or kv["Angle"]
            if raw then
                local ang = ParseAngleValue(raw)
                if ang and IsSaneAngle(ang) then return ang end
            end
        end
    end

    local nativeState
    if door.GetInternalVariable then
        local ok, val = pcall(door.GetInternalVariable, door, "m_eDoorState")
        if ok and isnumber(val) then nativeState = val end
    end
    if nativeState == 0 then
        local cur = door:GetAngles()
        if IsSaneAngle(cur) then return cur end
    end

    if nativeState == 2 then
        local lo, hi, dist, opendir, spawnflags = SwingDoors.Geometry.GetDoorMotionBounds(door)
        local cur = door:GetAngles()
        if opendir == 2 then
            return Angle(cur.p, cur.y - dist, cur.r)
        elseif opendir == 1 then
            return Angle(cur.p, cur.y + dist, cur.r)
        end
    end

    return nil
end

function SwingDoors.Geometry.IsSafeToSwing(door)
    if door.SwingDoors_SaneChecked then
        return not door.SwingDoors_Unsafe
    end
    door.SwingDoors_SaneChecked = true

    local safe = SwingDoors.Geometry.IsSaneAngle(door:GetAngles()) and IsValid(door:GetPhysicsObject())

    if not safe then
        door.SwingDoors_Unsafe = true
        DBG("%s (%s) failed the door sanity check -- leaving it to native door logic",
            door:GetClass(), tostring(door))
    end

    return safe
end

local swingableClasses = {
    prop_door_rotating = true,
    func_door_rotating = true,
}

function SwingDoors.Geometry.IsSwingable(ent, whoFor)
    if not SwingDoors.Enabled() then return false end
    if not IsValid(ent) then return false end
    local class = ent:GetClass()
    if not swingableClasses[class] then return false end
    if ent.NoOpen or ent.IsDecorative or ent.SwingDoors_Ignore then return false end
    if ent.SwingDoors_Broken or ent:GetNoDraw() then return false end
    if not SwingDoors.Geometry.IsSafeToSwing(ent) then return false end
    return true
end

function SwingDoors.Geometry.IsLatched(ent)
    if not IsValid(ent) then return false end
    if isfunction(ent.isLocked) and ent:isLocked() then return true end
    if ent.LockedDoorNail then return true end
    if hgCheckBindObjects and (hgCheckBindObjects(ent) or 0) > 0 then return true end
    if hgCheckDuctTapeObjects and (hgCheckDuctTapeObjects(ent) or 0) > 0 then return true end
    local internal = ent.GetInternalVariable and ent:GetInternalVariable("m_bLocked")
    return internal == true
end
