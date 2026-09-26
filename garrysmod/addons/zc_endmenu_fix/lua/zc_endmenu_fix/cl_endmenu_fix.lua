-- ZCity end-menu lifetime fix v1.0.1
-- Retire results frames before captured player references become invalid.
-- No error suppression, private callback patches or entity-method overrides.

local VERSION = "1.0.1"
local HOOK_ID = "zc_endmenu_fix"
local trackedMenu
local trackedMode
local trackedPlayers = {}
local closed = 0
local lastReason = "none"

local function RetirePanel(panel, reason)
    if not IsValid(panel) then return end

    -- Hide immediately: VGUI removal can be deferred until a later frame.
    panel:SetVisible(false)
    panel:SetMouseInputEnabled(false)
    panel:SetKeyboardInputEnabled(false)
    if hmcdEndMenu == panel then hmcdEndMenu = nil end
    panel:Remove()

    closed = closed + 1
    lastReason = reason
end

local function CloseMenu(reason)
    local panel = hmcdEndMenu
    local previous = trackedMenu
    trackedMenu = nil
    trackedMode = nil
    trackedPlayers = {}

    RetirePanel(panel, reason)
    if previous ~= panel then RetirePanel(previous, reason) end
end

local function CheckMenu()
    local panel = hmcdEndMenu
    if panel ~= trackedMenu then
        -- ZFrame:Close animates for 0.2s, while the original click handler
        -- immediately clears hmcdEndMenu. A replaced frame can also still
        -- exist until deferred removal. Retire it before dropping our reference.
        RetirePanel(trackedMenu, "menu closed or replaced")
        trackedMenu = nil
        trackedMode = nil
        trackedPlayers = {}
    end

    if not IsValid(panel) then return end
    if not zb then return end

    -- The shipped receiver uses 0 = waiting, 1 = active, 3 = ended.
    -- The incoming mode need not implement MODE:RoundStart().
    if zb.ROUND_STATE == 0 or zb.ROUND_STATE == 1 then
        CloseMenu("round started or waiting")
        return
    end

    if panel ~= trackedMenu then
        trackedMenu = panel
        trackedMode = zb.CROUND
        trackedPlayers = player.GetAll()
    elseif trackedMode ~= zb.CROUND then
        CloseMenu("mode changed")
        return
    end

    -- Fallback after a menu has been observed if another hook stops
    -- EntityRemoved propagation. Keep old references across full updates,
    -- rather than looking up entity indices. No roster scans when menus close.
    for _, ply in ipairs(trackedPlayers) do
        if not IsValid(ply) then
            CloseMenu("player reference invalidated")
            return
        end
    end
end

hook.Add("EntityRemoved", HOOK_ID, function(ent)
    if not IsValid(hmcdEndMenu) and not IsValid(trackedMenu) then return end
    -- Runs before removal. Full updates also invalidate captured players.
    if ent:IsPlayer() then CloseMenu("player entity removed") end
end)

hook.Add("RoundInfoCalled", HOOK_ID, function(incomingMode)
    -- Fires BEFORE CROUND / ROUND_STATE are changed by the net receiver.
    -- Only the incoming mode is known here; CheckMenu handles the new state.
    if zb and incomingMode ~= zb.CROUND then CloseMenu("mode changed") end
end)

hook.Add("Think", HOOK_ID, CheckMenu)
hook.Add("PreRender", HOOK_ID, CheckMenu)
hook.Add("PreCleanupMap", HOOK_ID, function()
    CloseMenu("map cleanup")
end)

-- A menu may already contain invalid references when this is hotloaded.
CloseMenu("addon loaded or reloaded")

concommand.Add("zc_endmenu_fix_status", function()
    print(string.format("[zc_endmenu_fix] v%s | closed: %d | last: %s | menu open: %s",
        VERSION, closed, lastReason, tostring(IsValid(hmcdEndMenu))))
end)
