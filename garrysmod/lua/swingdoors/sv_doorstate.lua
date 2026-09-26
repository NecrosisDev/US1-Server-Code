SwingDoors = SwingDoors or {}
SwingDoors.DoorState = SwingDoors.DoorState or {}

local DBG = SwingDoors.DBG
local Geometry = SwingDoors.Geometry

SwingDoors.DoorState.BaseAngles = setmetatable({}, { __mode = "k" })
local baseAngles = SwingDoors.DoorState.BaseAngles

local DOOR_STATE_CLOSED = 0
local NATIVE_STATE_OPENING = 1
local NATIVE_STATE_CLOSING = 3

function SwingDoors.DoorState.RememberBaseAngle(door)
    if not IsValid(door) or baseAngles[door] or not Geometry.IsSwingable(door, "RememberBaseAngle") then return end

    local nativeState
    if door.GetInternalVariable then
        local ok, val = pcall(door.GetInternalVariable, door, "m_eDoorState")
        if ok then nativeState = val end
    end

    local authored = Geometry.GetAuthoredClosedAngle(door)

    if authored then
        baseAngles[door] = authored
        if nativeState and nativeState ~= DOOR_STATE_CLOSED then
            DBG("%s spawned not closed (m_eDoorState=%s) -- using its map-authored angle (%.1f %.1f %.1f) as the closed reference instead of its current live angle",
                door:GetClass(), tostring(nativeState), authored.p, authored.y, authored.r)
        end
        return
    end

    if nativeState == NATIVE_STATE_OPENING or nativeState == NATIVE_STATE_CLOSING then
        DBG("%s mid transition (m_eDoorState=%s) and no authored angle -- deferring base angle, will retry on next touch",
            door:GetClass(), tostring(nativeState))
        return
    end

    if nativeState and nativeState ~= DOOR_STATE_CLOSED then
        door.SwingDoors_BaseIsApproximate = true
        DBG("%s spawned not closed (m_eDoorState=%s) and has no readable KeyValues -- falling back to its live angle as the closed reference; offsets may be approximate",
            door:GetClass(), tostring(nativeState))
    end

    baseAngles[door] = door:GetAngles()
end

function SwingDoors.DoorState.FreezeNativeMotion(door)
    local prevMoveType = door:GetMoveType()
    door:SetLocalAngularVelocity(angle_zero)
    local phys = door:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
        phys:Sleep()
    end
    door:SetMoveType(MOVETYPE_NONE)
    return prevMoveType
end

function SwingDoors.DoorState.RestoreNativeMotion(door, prevMoveType)
    if not IsValid(door) then return end
    door:SetMoveType(prevMoveType or MOVETYPE_PUSH)
    local phys = door:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(true)
        phys:Wake()
    end
end

function SwingDoors.DoorState.SetDoorAngle(door, ang)
    door:SetAngles(ang)
    local phys = door:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetPos(door:GetPos(), true)
        phys:SetAngles(ang)
    end
end

SwingDoors.DoorState.CLOSED_DEADZONE = 1
local CLOSED_DEADZONE = SwingDoors.DoorState.CLOSED_DEADZONE

function SwingDoors.DoorState.VisualOffset(offset)
    local a = math.abs(offset)
    if a <= CLOSED_DEADZONE then return 0 end
    return (offset > 0 and 1 or -1) * (a - CLOSED_DEADZONE)
end

local EXTERNAL_MOVE_TOLERANCE = CLOSED_DEADZONE + 0.5

function SwingDoors.DoorState.GetCurrentOffset(door, base, lo, hi)
    local actual = math.AngleDifference(door:GetAngles().y, base.y)
    local raw = door.SwingDoors_RawOffset

    if raw == nil then
        return math.Clamp(actual, lo, hi)
    end

    local expected = SwingDoors.DoorState.VisualOffset(raw)
    if math.abs(math.AngleDifference(actual, expected)) <= EXTERNAL_MOVE_TOLERANCE then
        return raw
    end

    local synced = math.Clamp(actual, lo, hi)
    DBG("%s (%s) was moved outside SwingDoors (tracked offset=%.1f, real=%.1f) -- resynced to real angle",
        door:GetClass(), tostring(door), raw, synced)
    door.SwingDoors_RawOffset = synced
    door.SwingDoors_LiveOffset = SwingDoors.DoorState.VisualOffset(synced)
    return synced
end

function SwingDoors.DoorState.AdoptSpawnPose(door)
    if not IsValid(door) or door.SwingDoors_PoseAdopted then return end
    if not Geometry.IsSwingable(door, "AdoptSpawnPose") then return end
    local base = baseAngles[door]
    if not base then return end

    door.SwingDoors_PoseAdopted = true

    local nativeState
    if door.GetInternalVariable then
        local ok, val = pcall(door.GetInternalVariable, door, "m_eDoorState")
        if ok then nativeState = val end
    end
    if not nativeState or nativeState == DOOR_STATE_CLOSED then return end

    local lo, hi = Geometry.GetDoorMotionBounds(door)
    local liveOffset = math.Clamp(math.AngleDifference(door:GetAngles().y, base.y), lo, hi)

    local ang = Angle(base.p, base.y + SwingDoors.DoorState.VisualOffset(liveOffset), base.r)
    door:SetAngles(ang)
    local phys = door:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetAngles(ang)
    end
    door.SwingDoors_RawOffset = liveOffset
    door.SwingDoors_LiveOffset = SwingDoors.DoorState.VisualOffset(liveOffset)

    DBG("%s spawned in native state %s (offset=%.1f) -- reasserted its pose so the engine's own settle/close animation can't run",
        door:GetClass(), tostring(nativeState), liveOffset)
end

hook.Add("OnEntityCreated", "SwingDoors_Remember", function(ent)
    timer.Simple(0, function()
        SwingDoors.DoorState.RememberBaseAngle(ent)
        SwingDoors.DoorState.AdoptSpawnPose(ent)
    end)
end)

hook.Add("InitPostEntity", "SwingDoors_RememberExisting", function()
    timer.Simple(0.5, function()
        for _, cls in ipairs({ "prop_door_rotating", "func_door_rotating" }) do
            for _, door in ipairs(ents.FindByClass(cls)) do
                SwingDoors.DoorState.RememberBaseAngle(door)
                SwingDoors.DoorState.AdoptSpawnPose(door)
            end
        end
    end)
end)
