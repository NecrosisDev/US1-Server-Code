-- Server-only attachment decoration for newly generated Stable Chaos loot.
local H = {}
local slots = {"sight", "barrel", "grip", "underbarrel"}
local function nativeHook()
    local all = hook.GetTable and hook.GetTable()
    return all and all.ZB_InventoryChecked and all.ZB_InventoryChecked.LootSpawn
end
function H.Ready()
    if type(nativeHook()) ~= "function" then return false, "Native container loot hook is unavailable" end
    if not hg or type(hg.attachments) ~= "table" or not weapons
        or type(weapons.Get) ~= "function" or type(table.Copy) ~= "function" then
        return false, "Native attachment definitions are unavailable"
    end
    return true
end
local function occupied(entry)
    return type(entry) == "table" and type(entry[1]) == "string" and entry[1] ~= "empty"
end
local function mountMatches(allowed, mount)
    if type(mount) ~= "string" then return false end
    if allowed == mount then return true end
    if type(allowed) == "table" then
        for _, value in pairs(allowed) do if value == mount then return true end end
    end
    return false
end
local function candidates(def, slot)
    local available = def.availableAttachments and def.availableAttachments[slot]
    local registry = hg.attachments and hg.attachments[slot]
    if type(available) ~= "table" or type(registry) ~= "table"
        or (slot == "sight" and def.scopedef) then return {} end
    local direct, count = {}, 0
    for _, entry in pairs(available) do
        count = count + 1
        if count > 256 then return {} end
        if type(entry) == "table" and type(entry[1]) == "string" then direct[entry[1]] = entry end
    end
    local out = {}; count = 0
    for id, meta in pairs(registry) do
        count = count + 1
        if count > 256 then return {} end
        if type(id) == "string" and id ~= "empty" and type(meta) == "table"
            and meta[1] == slot and meta.valid ~= false and type(meta[2]) == "string" and meta[2] ~= "" then
            local entry = direct[id]
            if entry or (available.mount ~= nil and mountMatches(available.mountType, meta.mountType)) then
                out[#out + 1] = {id = id, value = entry or {id, {}}}
            end
        end
    end
    table.sort(out, function(a,b) return a.id < b.id end)
    return out
end
local function compatible(current, slot, id)
    local registry = hg.attachments or {}
    local meta = registry[slot] and registry[slot][id]
    if not meta then return false end
    for otherSlot, entry in pairs(current) do
        if occupied(entry) then
            local other = registry[otherSlot] and registry[otherSlot][entry[1]]
            -- Unknown installed parts cannot be certified compatible.
            if not other or meta.restrictatt == otherSlot or other.restrictatt == slot then return false end
        end
    end
    return true
end
function H.Attach(ctx, class, current)
    if type(current) ~= "table" or ZC_HMCD_MUTATORS:Random() >= 0.5 then return end
    local def = weapons.Get(class)
    if type(def) ~= "table" or type(def.availableAttachments) ~= "table" then return end
    local attachments, order = table.Copy(current), {1,2,3,4}
    for i = #order, 2, -1 do
        local j = math.floor(ZC_HMCD_MUTATORS:Random() * i) + 1
        order[i], order[j] = order[j], order[i]
    end
    local limit = ZC_HMCD_MUTATORS:Random() < 0.5 and 2 or 1
    local added = 0
    for _, index in ipairs(order) do
        local slot = slots[index]
        if not occupied(attachments[slot]) then
            local choices, valid = candidates(def, slot), {}
            for _, candidate in ipairs(choices) do
                if compatible(attachments, slot, candidate.id) then valid[#valid + 1] = candidate end
            end
            if #valid > 0 then
                local candidate = valid[math.floor(ZC_HMCD_MUTATORS:Random() * #valid) + 1]
                attachments[slot] = table.Copy(candidate.value)
                added = added + 1
                if added >= limit then break end
            end
        end
    end
    if added > 0 then return attachments, added end
end
function H.Install(ctx, guns, currentPool)
    local ready, reason = H.Ready(); if not ready then error(reason) end
    local original, rank = nativeHook(), 0
    local all = hook.GetULibTable and hook.GetULibTable()
    for priority, entries in pairs(all and all.ZB_InventoryChecked or {}) do
        if entries.LootSpawn then rank = priority break end
    end
    local function active() return ctx:Valid() and currentPool() end
    local wrapper
    wrapper = function(ply, ent, ...)
        local fresh = active() and IsValid(ent) and not ent.was_opened
            and not ent:IsPlayer() and string.sub(ent:GetClass(),1,5) == "prop_"
            and hg.loot_boxes and hg.loot_boxes[string.lower(ent:GetModel())]
        local previous = fresh and ent.inventory
        -- Let native errors propagate normally; never conceal a failed loot roll.
        local result = original(ply, ent, ...)
        if fresh and active() and IsValid(ent) and ent.was_opened and ent.inventory ~= previous
            and type(ent.inventory) == "table" and type(ent.inventory.Weapons) == "table" then
            ctx:Call(function()
                local replacements, count = {}, 0
                for class, info in pairs(ent.inventory.Weapons) do
                    count = count + 1; if count > 8 then break end
                    if guns[class] and type(info) == "table" and type(info[2]) == "table" then
                        local atts = H.Attach(ctx, class, info[2])
                        if atts then local copy = table.Copy(info); copy[2] = atts; replacements[class] = copy end
                    end
                end
                -- Commit only after every selected decoration was built successfully.
                if next(replacements) and active() and IsValid(ent) then
                    for class, info in pairs(replacements) do ent.inventory.Weapons[class] = info end
                    ent:SetNetVar("Inventory", ent.inventory)
                end
            end)
        end
        return result
    end
    ctx:Cleanup(function()
        if nativeHook() == wrapper then hook.Add("ZB_InventoryChecked", "LootSpawn", original, rank) end
    end)
    hook.Add("ZB_InventoryChecked", "LootSpawn", wrapper, rank)
    -- Ground loot gets its IsSpawned flag after creation. One deferred callback,
    -- bounded to 128 pending entities; no timer loop or entity scan is needed.
    local pending, pendingCount = {}, 0
    local function release(ent, record)
        if IsValid(ent) and ent.SetInfo == record.wrapper then ent.SetInfo = record.original end
        if pending[ent] == record then pending[ent] = nil; pendingCount = pendingCount - 1 end
    end
    ctx:Cleanup(function()
        for ent, record in pairs(pending) do release(ent, record) end
    end)
    ctx:Hook("OnEntityCreated", "loot_attachments", function(_, ent)
        if not active() or not IsValid(ent) or not guns[ent:GetClass()] or pending[ent] or pendingCount >= 128
            or type(ent.SetInfo) ~= "function" then return end
        local record = {original = ent.SetInfo}
        -- Inventory pickup and broken crates restore their saved info after
        -- creation. Observe that call so those guns never receive a second roll.
        record.wrapper = function(self, ...)
            record.imported = true
            return record.original(self, ...)
        end
        pending[ent] = record; pendingCount = pendingCount + 1
        ent.SetInfo = record.wrapper
        timer.Simple(0, function()
            local owned = IsValid(ent) and ent.SetInfo == record.wrapper
            release(ent, record)
            if not owned or record.imported or not active() or not IsValid(ent) or not ent.IsSpawned
                or IsValid(ent:GetOwner()) or ent._zcUnstableDecorated then return end
            ent._zcUnstableDecorated = true
            ctx:Call(function()
                local atts = H.Attach(ctx, ent:GetClass(), ent.attachments)
                if atts and active() and IsValid(ent) and not IsValid(ent:GetOwner()) then
                    ent.attachments = atts
                    ent:SetNetVar("attachments", atts)
                end
            end)
        end)
    end)
end
return H
