SwingDoors = SwingDoors or {}
SwingDoors.Portals = SwingDoors.Portals or {}

local DBG = SwingDoors.DBG
local CLOSED_DEADZONE = SwingDoors.DoorState.CLOSED_DEADZONE

local portalOpenCount = setmetatable({}, { __mode = "k" })

hook.Add("EntityRemoved", "SwingDoors_PortalCleanup", function(door)
    if door.SwingDoors_PortalCounted then
        door.SwingDoors_PortalCounted = false
        local portals = door.SwingDoors_Portals
        if portals then
            for _, portal in ipairs(portals) do
                if IsValid(portal) then
                    local count = math.max(0, (portalOpenCount[portal] or 0) - 1)
                    portalOpenCount[portal] = count
                    if count == 0 then
                        portal:Fire("Close", "", 0)
                    end
                end
            end
        end
    end
end)

local TS_AT_TOP, TS_AT_BOTTOM = 0, 1
local PORTAL_SEARCH_RADIUS = 300

local function EntityWorldCenter(ent)
    local mins, maxs = ent:WorldSpaceAABB()
    if mins == maxs then
        return ent:GetPos()
    end
    return (mins + maxs) * 0.5
end

function SwingDoors.Portals.GetPortalLinkedDoorName(portal)
    if portal.GetInternalVariable then
        local ok, val = pcall(portal.GetInternalVariable, portal, "m_target")
        if ok and val and val ~= "" then
            return val, "m_target"
        end
    end
    if portal.GetKeyValues then
        local ok, kv = pcall(portal.GetKeyValues, portal)
        if ok and istable(kv) then
            local raw = kv["target"] or kv["Target"]
            if raw and raw ~= "" then
                return raw, "GetKeyValues"
            end
        end
    end
    return nil
end

local PORTAL_TWIN_EPSILON = 8

function SwingDoors.Portals.ResolveDoorPortal(door)
    if door.SwingDoors_PortalResolved then
        return door.SwingDoors_Portals
    end
    door.SwingDoors_PortalResolved = true

    local doorName = door:GetName()
    local matches = {}
    local matchMethod = nil

    if doorName and doorName ~= "" then
        for _, portal in ipairs(ents.FindByClass("func_areaportal")) do
            local linkedName, via = SwingDoors.Portals.GetPortalLinkedDoorName(portal)
            DBG("ResolveDoorPortal: %s (%s) portal %s target=%s (via %s)",
                tostring(door), door:GetClass(), tostring(portal), tostring(linkedName), tostring(via))
            if linkedName == doorName then
                table.insert(matches, portal)
                matchMethod = "target:" .. via
            end
        end
    end

    if #matches == 0 then
        local doorPos = EntityWorldCenter(door)
        local candidates = {}
        local bestDist = PORTAL_SEARCH_RADIUS

        for _, portal in ipairs(ents.FindByClass("func_areaportal")) do
            local portalPos = EntityWorldCenter(portal)
            local dist = doorPos:Distance(portalPos)
            DBG("ResolveDoorPortal: %s (%s) candidate %s dist=%.1f", tostring(door), door:GetClass(), tostring(portal), dist)
            if dist < PORTAL_SEARCH_RADIUS then
                table.insert(candidates, { portal = portal, dist = dist })
                if dist < bestDist then bestDist = dist end
            end
        end

        for _, c in ipairs(candidates) do
            if c.dist <= bestDist + PORTAL_TWIN_EPSILON then
                table.insert(matches, c.portal)
                matchMethod = "distance"
            end
        end
    end

    door.SwingDoors_Portals = matches
    door.SwingDoors_PortalMatchMethod = matchMethod

    if #matches > 0 then
        DBG("ResolveDoorPortal: %s -> %d portal(s) via %s", tostring(door), #matches, tostring(matchMethod))
        for _, p in ipairs(matches) do
            DBG("ResolveDoorPortal:   -> %s", tostring(p))
        end
    else
        DBG("ResolveDoorPortal: %s -> no func_areaportal matched (name or within %d units)", tostring(door), PORTAL_SEARCH_RADIUS)
    end

    return matches
end

local function FireDoorTransitionIO(door, opening)
    if not IsValid(door) then return end

    pcall(door.Fire, door, opening and "Open" or "Close", "", 0, door, door)

    door:SetLocalAngularVelocity(angle_zero)
    local phys = door:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
        phys:Sleep()
    end
    door:SetMoveType(MOVETYPE_NONE)
end

function SwingDoors.Portals.SetPortalDoorOpen(door, portals, isOpen)
    if not portals or #portals == 0 then return end

    if isOpen then
        if door.SwingDoors_PortalCounted then return end
        door.SwingDoors_PortalCounted = true

        for _, portal in ipairs(portals) do
            if IsValid(portal) then
                local count = (portalOpenCount[portal] or 0) + 1
                portalOpenCount[portal] = count
                if count == 1 then
                    DBG("SetPortalDoorOpen: %s firing Open on portal %s (count=%d)", tostring(door), tostring(portal), count)
                    portal:Fire("Open", "", 0)
                end
            end
        end
    else
        if not door.SwingDoors_PortalCounted then return end
        door.SwingDoors_PortalCounted = false

        for _, portal in ipairs(portals) do
            if IsValid(portal) then
                local count = math.max(0, (portalOpenCount[portal] or 0) - 1)
                portalOpenCount[portal] = count
                if count == 0 then
                    DBG("SetPortalDoorOpen: %s firing Close on portal %s (count=%d)", tostring(door), tostring(portal), count)
                    portal:Fire("Close", "", 0)
                end
            end
        end
    end
end

local CLOSE_PORTAL_DELAY = 0.1

function SwingDoors.Portals.PreOpenPortal(door)
    if not IsValid(door) then return end
    if door.SwingDoors_PortalOpen then return end
    door.SwingDoors_PortalOpen = true
    local portals = SwingDoors.Portals.ResolveDoorPortal(door)
    SwingDoors.Portals.SetPortalDoorOpen(door, portals, true)
end

function SwingDoors.Portals.UpdateDoorOpenState(door, offset, s)
    if not IsValid(door) then return end
    local isOpen = math.abs(offset) > CLOSED_DEADZONE

    if s and s.lastReportedOpen ~= isOpen then
        door:SetSaveValue("m_eDoorState", isOpen and 2 or 0)
        pcall(door.SetSaveValue, door, "m_toggle_state", isOpen and TS_AT_TOP or TS_AT_BOTTOM)

        s.lastReportedOpen = isOpen
        FireDoorTransitionIO(door, isOpen)
    elseif not s then
        door:SetSaveValue("m_eDoorState", isOpen and 2 or 0)
        pcall(door.SetSaveValue, door, "m_toggle_state", isOpen and TS_AT_TOP or TS_AT_BOTTOM)
    end

    if door.SwingDoors_PortalOpen ~= isOpen then
        door.SwingDoors_PortalOpen = isOpen

        if isOpen then
            local portals = SwingDoors.Portals.ResolveDoorPortal(door)
            SwingDoors.Portals.SetPortalDoorOpen(door, portals, true)
        elseif game.SinglePlayer() then
            local portals = SwingDoors.Portals.ResolveDoorPortal(door)
            SwingDoors.Portals.SetPortalDoorOpen(door, portals, false)
        else
            timer.Simple(CLOSE_PORTAL_DELAY, function()
                if not IsValid(door) then return end
                if door.SwingDoors_PortalOpen then return end
                local portals = SwingDoors.Portals.ResolveDoorPortal(door)
                SwingDoors.Portals.SetPortalDoorOpen(door, portals, false)
            end)
        end
    end
end
