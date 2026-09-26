local M = ZC_HMCD_MUTATORS
local CLASS = "hg_brassknuckles"

local function Inventory(ply)
    local inv = ply:GetNetVar("Inventory")
    -- Do not fabricate an inventory before ZCity finishes its spawn/loadout work.
    if type(inv) ~= "table" or type(inv.Weapons) ~= "table" or ply.inventory ~= inv then return end
    return inv
end

M:Register({
    ID = "brass_tacks",
    Title = "Brass Tacks",
    Description = "Everyone starts with brass knuckles equipped. Existing gear stays. One set per starting player; no respawn grants. Combat karma loss is halved.",
    Types = {standard = true, gunfreezone = true, soe = true, wildwest = true},
    MinPlayers = 2,
    Weight = 1,
    MidRound = true,
    MidRoundRequiresUpright = true,
    CanStart = function(_, manager)
        if not scripted_ents or not scripted_ents.GetStored or not scripted_ents.GetStored(CLASS)
            or not weapons.GetStored("weapon_hands_sh") then
            return false, "Native brass knuckles or Hands definition is unavailable"
        end
        for _, ply in ipairs(manager:Players()) do
            if not Inventory(ply) or not ply:HasWeapon("weapon_hands_sh") then
                return false, "Wait for player inventories and Hands loadouts to finish"
            end
        end
        return true
    end,
    Start = function(ctx)
        local grants, committed = {}, false
        ctx.data.granted, ctx.data.existing = 0, 0
        -- Validate the entire starting snapshot before changing anyone's equipment.
        for _, ply in ipairs(ctx.participants) do
            if not IsValid(ply) or not ply:Alive() or ply:Team() == TEAM_SPECTATOR then
                error("Brass Tacks participant changed during setup")
            end
            local inv = Inventory(ply)
            if not inv or not ply:HasWeapon("weapon_hands_sh") then error("Brass Tacks loadout is not ready") end
            if inv.Weapons[CLASS] then
                ctx.data.existing = ctx.data.existing + 1
            else
                grants[#grants + 1] = {ply = ply, inv = inv, weapons = inv.Weapons, previous = inv.Weapons[CLASS]}
            end
        end
        for _, grant in ipairs(grants) do
            if not ctx:Valid() then return end
            local ply, inv = grant.ply, grant.inv
            if not IsValid(ply) or not ply:Alive() or ply:Team() == TEAM_SPECTATOR
                or Inventory(ply) ~= inv or inv.Weapons ~= grant.weapons or inv.Weapons[CLASS] ~= grant.previous then
                error("Brass Tacks inventory changed during setup")
            end
            ctx:Cleanup(function()
                -- Roll back partial setup only. Successful grants are ordinary transferable
                -- native items: their boolean flag cannot identify an item after trading.
                if committed then return end
                if grant.weapons[CLASS] == true then grant.weapons[CLASS] = grant.previous end
                if IsValid(ply) and Inventory(ply) == inv and inv.Weapons == grant.weapons then
                    ply:SetNetVar("Inventory", inv)
                end
            end)
            inv.Weapons[CLASS] = true
            ply:SetNetVar("Inventory", inv)
            if not ctx:Valid() then return end
            if Inventory(ply) ~= inv or inv.Weapons ~= grant.weapons or inv.Weapons[CLASS] ~= true then
                error("Brass Tacks equipment grant did not persist")
            end
            ctx.data.granted = ctx.data.granted + 1
        end
        -- One starting grant, not an aura: no recurring work, late-join or respawn refill.
        -- Native drop, loot and next-life inventory reset own these items from here.
        committed = true
    end
})
