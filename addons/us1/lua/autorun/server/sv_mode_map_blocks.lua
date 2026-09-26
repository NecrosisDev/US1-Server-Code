-- Mode/map blocks: stop specific modes from rolling on specific maps.
-- Wraps each mode's CanLaunch (the check the round queue already
-- respects), so blocked modes silently drop out of rotation on listed
-- maps. Forced modes (setforcemode) still work. No chance-table edits,
-- nothing persisted - pure runtime gate.
--
-- Edit the table, hotload the file, done:
--   lua_run include("autorun/server/sv_mode_map_blocks.lua")
if not SERVER then return end

-- map -> set of mode keys that must not roll there
local BLOCKED = {
    ["zs_abandonedmall_2025_v6"] = {
        ["tdm"] = true,
        ["cstrike"] = true,
        ["criresp"] = true,   -- crisis response
        ["civilwar"] = true,
        ["hl2dm"] = true,
        ["dm"] = true,        -- deathmatch
        ["uncontainedriot"] = true,
        ["wildcard"] = true,
    },
}

local function Apply()
    if not (zb and zb.modes) then return false end

    local blockedHere = BLOCKED[game.GetMap()] or {}

    for key, mode in pairs(zb.modes) do
        -- restore any previous wrap first (hotload-safe)
        if mode.__origCanLaunch then
            mode.CanLaunch = mode.__origCanLaunch
            mode.__origCanLaunch = nil
        end

        if blockedHere[key] then
            mode.__origCanLaunch = mode.CanLaunch
            local orig = mode.CanLaunch
            mode.CanLaunch = function(self, ...)
                return false
            end
            print("[ModeMapBlocks] '" .. key .. "' blocked on " .. game.GetMap())
        end
    end
    return true
end

hook.Add("InitPostEntity", "ModeMapBlocks_Apply", function()
    timer.Create("ModeMapBlocks_Retry", 5, 6, function()
        if Apply() then timer.Remove("ModeMapBlocks_Retry") end
    end)
    Apply()
end)

-- immediate attempt for hotloads mid-session
if zb and zb.modes then Apply() end
