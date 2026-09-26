-- ZC BEARTRAP RARITY 2.2.0 - repair of Joey's existing rarity override.
-- ZCity pools are { {groupWeight, { {itemWeight, class}, ... }}, ... }.
-- Only existing beartrap item weights change; group weights, other items,
-- trap mechanics and Infiltrator equipment are preserved.
-- Defaults remain standard/GFZ/Wild West 0.3 and SOE 0.06 (relative weights).
-- Hotload: lua_run include("autorun/server/sv_zc_beartrap_rarity.lua")
if not SERVER then return end
local VERSION = "2.2.0"
local CLASS = "weapon_beartrap_homigrad"
local cv_std = CreateConVar("zc_beartrap_weight_standard", "0.3", FCVAR_ARCHIVE,
    "Bear trap loot weight in the hmcd standard pool")
local cv_soe = CreateConVar("zc_beartrap_weight_soe", "0.06", FCVAR_ARCHIVE,
    "Bear trap loot weight in the hmcd SOE pool")
local function weight(cv, fallback)
    local value = cv:GetFloat()
    if value ~= value or value < 0 or value == math.huge then return fallback end
    return value
end
local function visitPool(pool, fn)
    if type(pool) ~= "table" then return 0 end
    local count = 0
    for groupIndex, group in pairs(pool) do
        -- group[1] is the category weight; group[2] holds its item entries.
        local entries = type(group) == "table" and group[2]
        if type(entries) == "table" then
            for itemIndex, entry in pairs(entries) do
                if type(entry) == "table" and entry[2] == CLASS then
                    fn(entry, groupIndex, itemIndex)
                    count = count + 1
                end
            end
        end
    end
    return count
end
local function applyPool(pool, target)
    return visitPool(pool, function(entry) entry[1] = target end)
end
local function apply(report)
    local hmcd = zb and zb.modes and zb.modes.hmcd
    if not hmcd then
        if report then print("[Beartrap Rarity " .. VERSION .. "] hmcd mode not loaded") end
        return 0, 0
    end
    local standard, soe = weight(cv_std, 0.3), weight(cv_soe, 0.06)
    local nStd = applyPool(hmcd.LootTableStandard, standard)
    local nSoe = applyPool(hmcd.LootTable, soe)
    if report then
        print(string.format("[Beartrap Rarity %s] applied: standard %d entries @ %.4g | SOE %d entries @ %.4g",
            VERSION, nStd, standard, nSoe, soe))
    end
    return nStd, nSoe
end
local function status()
    local hmcd = zb and zb.modes and zb.modes.hmcd
    local out = {version=VERSION, standardTarget=weight(cv_std, 0.3), soeTarget=weight(cv_soe, 0.06), pools={}}
    for _, name in ipairs({"LootTableStandard", "LootTable"}) do
        local entries = {}
        visitPool(hmcd and hmcd[name], function(entry, group, index)
            entries[#entries + 1] = {group=group, index=index, weight=entry[1]}
        end)
        out.pools[name] = entries
    end
    print("[Beartrap Rarity status] " .. util.TableToJSON(out))
end
local function startRetry()
    apply(false) -- existing live pools are fixed immediately on hotload
    local tries, reported = 0, false
    timer.Create("zc_beartrap_rarity_retry", 2, 20, function()
        tries = tries + 1
        local a, b = apply(false)
        if not reported and a > 0 and b > 0 then apply(true); reported = true end
        -- Keep the full 40-second window: a later injector retry may restore old weights.
        if tries >= 20 then
            timer.Remove("zc_beartrap_rarity_retry")
            print("[Beartrap Rarity " .. VERSION .. "] startup retry window complete")
            status()
        end
    end)
end
hook.Add("InitPostEntity", "zc_beartrap_rarity", startRetry)
-- Rebuilt mode tables are repaired at the next normal round boundary.
hook.Add("ZB_PreRoundStart", "zc_beartrap_rarity", function() apply(false) end)
cvars.AddChangeCallback("zc_beartrap_weight_standard", function() apply(true) end, "zc_beartrap_rarity")
cvars.AddChangeCallback("zc_beartrap_weight_soe", function() apply(true) end, "zc_beartrap_rarity")
concommand.Add("zc_beartrap_rarity", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    apply(true)
    status()
end)
-- This separate command observes tables without applying or changing any weights.
concommand.Add("zc_beartrap_rarity_status", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    status()
end)
startRetry()
print("[Beartrap Rarity " .. VERSION .. "] loaded")
