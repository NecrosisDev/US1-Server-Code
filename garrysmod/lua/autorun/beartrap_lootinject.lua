if SERVER then
    AddCSLuaFile()
end

local WEAPON_CLASS = "weapon_beartrap_homigrad"
local SHOP_NAME = "Bear Trap"
local SHOP_CATEGORY = "Special"

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
        changed = addLootWeapon(mode.LootTable[1][2], 0.35, WEAPON_CLASS) or changed
    end

    if istable(mode.LootTableStandard) and istable(mode.LootTableStandard[1]) and istable(mode.LootTableStandard[1][2]) then
        changed = addLootWeapon(mode.LootTableStandard[1][2], 2.0, WEAPON_CLASS) or changed
    end

    if changed then
        print("[BearTrapInject] Added bear trap to HMCD loot tables.")
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

    if not mode or not istable(mode.BuyItems) then
        return false
    end

    mode.BuyItems[SHOP_CATEGORY] = mode.BuyItems[SHOP_CATEGORY] or {}
    mode.BuyItems[SHOP_CATEGORY].Priority = mode.BuyItems[SHOP_CATEGORY].Priority or 6

    if mode.BuyItems[SHOP_CATEGORY][SHOP_NAME] then
        return true
    end

    mode.BuyItems[SHOP_CATEGORY][SHOP_NAME] = {
        Type = "Weapon",
        ItemClass = WEAPON_CLASS,
        Price = 450,
        Category = SHOP_CATEGORY,
        Attachments = {},
        Amount = nil,
        TeamBased = nil
    }

    print("[BearTrapInject] Added bear trap to TDM buy menu in realm: " .. (SERVER and "SERVER" or "CLIENT"))
    return true
end

local function tryInjectAll()
    local lootReady = injectLoot()
    local shopReady = injectTDMShop()
    return lootReady and shopReady
end

local function startInject()
    if tryInjectAll() then return end

    local id = "BearTrapInject_All_Retry_" .. (SERVER and "SV" or "CL")
    timer.Create(id, 1, 15, function()
        if tryInjectAll() then
            timer.Remove(id)
        end
    end)
end

hook.Add("InitPostEntity", "BearTrapInject_All_InitPostEntity_" .. (SERVER and "SV" or "CL"), function()
    timer.Simple(0, startInject)
end)
