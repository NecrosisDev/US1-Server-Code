local M = ZC_HMCD_MUTATORS
local CLASS = "weapon_glock17"
local function ReplacementPlan(ply)
    local slot = ply.weaponInv and ply.weaponInv[2]
    local plan = {ply = ply, remove = {}, slot = slot}
    if not slot then return plan end
    local limit = slot.limit
    if not M.Finite(limit) or limit < 1 or limit ~= math.floor(limit) then error("Invalid pistol slot capacity") end
    local needed = math.max(#slot - limit + 1, 0)
    if needed == 0 then return plan end
    if not hg or not hg.weaponInv or not hg.weaponInv.Remove or not hg.weaponInv.Sync then error("Missing pistol inventory API") end
    for i = 1, needed do
        local wep = slot[i]
        if not IsValid(wep) or wep:GetOwner() ~= ply or wep.weaponInvCategory ~= 2 then error("Invalid pistol slot reference") end
        plan.remove[#plan.remove + 1] = wep
    end
    return plan
end
-- Delete only references to this exact event-created entity, including corpse inventories.
local function RemoveGrant(wep)
    if not IsValid(wep) then return end
    local holders = {}
    local function add(ent) if IsValid(ent) then holders[ent] = true end end
    add(wep:GetOwner())
    add(wep:GetParent())
    for _, ply in ipairs(player.GetAll()) do
        add(ply)
        add(ply.FakeRagdoll)
        add(ply:GetNWEntity("RagdollDeath"))
    end
    for ent in pairs(holders) do
        if ent.weaponInv and hg and hg.weaponInv and hg.weaponInv.Remove and hg.weaponInv.Sync then
            if hg.weaponInv.Remove(ent, wep) then hg.weaponInv.Sync(ent) end
        end
        local CLASS = wep:GetClass()
        local inv = ent.inventory
        if inv and inv.Weapons and inv.Weapons[CLASS] == wep then
            inv.Weapons[CLASS] = nil
            ent:SetNetVar("Inventory", inv)
        end
    end
    wep:Remove()
end
M:Register({
    MidRound = true, MidRoundRequiresUpright = true,
    ID = "everyone_armed",
    Title = "Everyone's Armed",
    Description = "A loaded Glock for each starting player. Conflicting pistols are replaced only when needed. No spare ammo is added. Combat karma loss is halved.",
    Types = {standard = true},
    Weight = 1,
    MinPlayers = 2,
    CanStart = function()
        return weapons.GetStored(CLASS) ~= nil, "Glock weapon definition is unavailable"
    end,
    Start = function(ctx)
        ctx.data.granted, ctx.data.replaced = 0, 0
        local plans = {}
        for _, ply in ipairs(ctx.participants) do
            if IsValid(ply) and ply:Alive() and not ply:HasWeapon(CLASS) then plans[#plans + 1] = ReplacementPlan(ply) end
        end
        -- All grants must succeed before removing any original pistol.
        for _, plan in ipairs(plans) do
            local slot, limit = plan.slot, plan.slot and plan.slot.limit
            if slot and #plan.remove > 0 then slot.limit = #slot + 1 end
            -- Give can create the weapon and then throw inside a WeaponEquip hook.
            local granted, pending = nil, true
            ctx:Cleanup(function()
                local wep = granted or (pending and IsValid(plan.ply) and plan.ply:GetWeapon(CLASS))
                if IsValid(wep) then RemoveGrant(wep) end
            end)
            local ok, err = xpcall(function()
                local wep = plan.ply:Give(CLASS, true)
                granted, pending = wep, false
                if not IsValid(wep) then error("Glock grant failed") end
                wep.DontEquipInstantly = true -- ZCity checks this in its deferred WeaponEquip callback.
                if wep:GetOwner() ~= plan.ply or wep:GetClass() ~= CLASS then error("Unexpected Glock owner or class") end
                local capacity = wep:GetMaxClip1()
                if not M.Finite(capacity) or capacity < 1 or capacity > 200 then error("Unexpected Glock magazine capacity") end
                wep:SetClip1(capacity)
                ctx.data.granted = ctx.data.granted + 1
            end, debug.traceback)
            if slot and #plan.remove > 0 then
                slot.limit = limit
                if hg and hg.weaponInv and hg.weaponInv.Sync then hg.weaponInv.Sync(plan.ply) end
            end
            if not ok then error(err) end
        end
        if not ctx:Valid() then return end
        for _, plan in ipairs(plans) do
            for _, wep in ipairs(plan.remove) do
                RemoveGrant(wep)
                ctx.data.replaced = ctx.data.replaced + 1
            end
        end
    end
})
