SwingDoors = SwingDoors or {}

local Geometry = SwingDoors.Geometry

local function BlockVanillaUse(ply, ent)
    if not Geometry.IsSwingable(ent, "PlayerUse") then return end

    return false
end

-- US1: this must run before Z-City's own door PlayerUse hooks ("DoorClose" fires a native close).
-- ULib's hook library takes a priority; it loads after this autorun file, so re-add once it exists.
-- The stock hook library ignores the extra argument.
hook.Add("PlayerUse", "SwingDoors_BlockVanillaUse", BlockVanillaUse, HOOK_HIGH)
hook.Add("InitPostEntity", "SwingDoors_BlockVanillaUsePriority", function()
    hook.Add("PlayerUse", "SwingDoors_BlockVanillaUse", BlockVanillaUse, HOOK_HIGH)
end)
