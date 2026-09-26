if SERVER then
    AddCSLuaFile()
end

local WEAPON_CLASS = "weapon_bloodclotter_sh"

local function hasLootWeapon(tbl, class)
    for _, entry in ipairs(tbl or {}) do
        if entry[2] == class then
            return true
        end
    end
    return false
end

local function addLootWeapon(bucket, chance, class)
    if not istable(bucket) then return false end
    if hasLootWeapon(bucket, class) then return false end
    table.insert(bucket, {chance, class})
    return true
end

local function injectLoot()
    if CLIENT then return true end

    if not zb or not zb.modes or not zb.modes["hmcd"] then
        return false
    end

    local mode = zb.modes["hmcd"]
    local changed = false

    if istable(mode.LootTable) and istable(mode.LootTable[1]) and istable(mode.LootTable[1][2]) then
        changed = addLootWeapon(mode.LootTable[1][2], 0.6, WEAPON_CLASS) or changed
    end

    if istable(mode.LootTableStandard) and istable(mode.LootTableStandard[1]) and istable(mode.LootTableStandard[1][2]) then
        changed = addLootWeapon(mode.LootTableStandard[1][2], 4, WEAPON_CLASS) or changed
    end

    if changed then
        print("[HemostaticInject] Added hemostatic syringe to HMCD loot tables.")
    end

    return true
end

local function injectTDMShop()
    if not zb or not zb.modes then
        return false
    end

    local mode = zb.modes["tdm"]
    if not mode then
        for _, v in pairs(zb.modes) do
            if istable(v) and v.PrintName == "Team Deathmatch" then
                mode = v
                break
            end
        end
    end

    if not mode then
        return false
    end

    if not istable(mode.BuyItems) then
        return false
    end

    mode.BuyItems["Medical"] = mode.BuyItems["Medical"] or {}
    mode.BuyItems["Medical"].Priority = mode.BuyItems["Medical"].Priority or 1

    if mode.BuyItems["Medical"]["Hemostatic Syringe"] then
        return true
    end

    mode.BuyItems["Medical"]["Hemostatic Syringe"] = {
        Type = "Weapon",
        ItemClass = WEAPON_CLASS,
        Price = 400,
        Category = "Medical",
        Attachments = {},
        Amount = nil,
        TeamBased = nil
    }

    print("[HemostaticInject] Added hemostatic syringe to TDM buy menu in realm: " .. (SERVER and "SERVER" or "CLIENT"))
    return true
end

local function tryInjectAll()
    local a = injectLoot()
    local b = injectTDMShop()
    return a and b
end

local function startInject()
    if tryInjectAll() then return end

    local id = "HemostaticInject_All_Retry_" .. (SERVER and "SV" or "CL")
    timer.Create(id, 1, 15, function()
        if tryInjectAll() then
            timer.Remove(id)
        end
    end)
end

hook.Add("InitPostEntity", "HemostaticInject_All_InitPostEntity_" .. (SERVER and "SV" or "CL"), function()
    timer.Simple(0, startInject)
end)