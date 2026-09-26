-- Civil War rotation fix: the mode ships ForBigMaps = true, which keeps
-- it out of the round queue on any map not classified "big" by the
-- roundsystem's whitelist/size math. Flip it at boot so it rolls in the
-- normal rotation on every map.
--
-- Waits for the mode loader, retries briefly in case of load order.
if not SERVER then return end

local tries = 0
local function Apply()
    if zb and zb.modes and zb.modes["civilwar"] then
        zb.modes["civilwar"].ForBigMaps = false
        print("[CivilWarRotation] ForBigMaps disabled - civil war in normal rotation")
        return true
    end
    return false
end

hook.Add("InitPostEntity", "CivilWarRotation_Apply", function()
    timer.Create("CivilWarRotation_Retry", 5, 6, function()
        if Apply() then timer.Remove("CivilWarRotation_Retry") end
    end)
    Apply()
end)
