-- Homelander SWEP + ZCity Compatibility Fix (CLIENT)
-- Makes X-Ray vision also highlight ragdolled-but-alive players
if not CLIENT then return end

local HOMELANDER_CLASS = "weapon_homelander"

hook.Add("PreDrawHalos", "HomelanderXRay_ZCityRagdolls", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) or wep:GetClass() ~= HOMELANDER_CLASS then return end
    if not wep.HomelanderXRayEnabled then return end

    local targets = {}
    for _, p in player.Iterator() do
        if p == ply then continue end
        if not IsValid(p) or not p:Alive() then continue end

        -- Highlight their ZCity ragdoll if they're currently ragdolled
        local rag = p.FakeRagdoll
        if IsValid(rag) then
            targets[#targets + 1] = rag
        end

        local oldRag = p.OldRagdoll
        if IsValid(oldRag) and oldRag ~= rag then
            targets[#targets + 1] = oldRag
        end
    end

    if #targets > 0 then
        halo.Add(targets, Color(255, 35, 25), 1, 1, 3, true, true)
    end
end)

print("[Homelander ZCity Fix] Client X-Ray ragdoll patch loaded")
