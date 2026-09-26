-- Removes entities that have fallen out of the map (into the void)
-- Prevents DataTable out-of-range warnings and wasted physics/network budget
if not SERVER then return end

local VOID_Z = -20000  -- anything below this is considered out of the map
local SWEEP_INTERVAL = 30

timer.Create("VoidEntityCleanup", SWEEP_INTERVAL, 0, function()
    local removed = 0
    for _, e in ipairs(ents.GetAll()) do
        if IsValid(e) and not e:IsPlayer() and not e:IsWorld() and e:GetPos().z < VOID_Z then
            e:Remove()
            removed = removed + 1
        end
    end
    if removed > 0 then
        print("[VoidCleanup] Removed " .. removed .. " out-of-bounds entities")
    end
end)

-- Stand down during map change / server shutdown
hook.Add("ShutDown", "VoidCleanup_Shutdown", function()
    timer.Remove("VoidEntityCleanup")
end)
