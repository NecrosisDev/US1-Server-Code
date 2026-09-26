-- Optional homicide-mutator page bridge. All mutations are authorized on the server.
AddCSLuaFile("traitor_admin/cl_mutators.lua")
util.AddNetworkString("traitoradmin_mutator_action")
util.AddNetworkString("traitoradmin_mutator_data")
local enqueue = include("traitor_admin/sv_requests.lua")(0.25)
local selectedGroups = setmetatable({}, {__mode = "k"})
local settings = {
    enabled = {"zc_mutators_enabled", 0, 1, true},
    auto = {"zc_mutators_auto", 0, 1, true},
    chance = {"zc_mutators_chance", 0, 100, false, 0.01},
    cooldown = {"zc_mutators_cooldown", 0, 20, true},
    timeout = {"zc_mutators_ready_timeout", 5, 300, true}
}
local function finite(n) return type(n) == "number" and n == n and math.abs(n) < math.huge end
local function groupOK(s) return type(s) == "string" and #s > 0 and #s <= 40 and s:match("^[a-z][a-z0-9_]*$") end
local function number(s, lo, hi, integer)
    local n = tonumber(s)
    if not finite(n) or n < lo or n > hi or (integer and n ~= math.floor(n)) then return end
    return n
end
local function Framework()
    local m = ZC_HMCD_MUTATORS
    if not m or not m.enabled or not m.auto or not m.chance or not m.definitions then return end
    return m
end
-- PointGroups metadata lets a future mutation advertise empty point types.
-- Existing saved groups remain selectable even without their original module.
local function PointGroups(m, selected)
    local names = {altar = "Altars"}
    local function add(id, title)
        if not groupOK(id) then return end
        if type(title) == "string" and #title > 0 then names[id] = title:sub(1, 80)
        elseif not names[id] then names[id] = id:gsub("_", " "):gsub("^%l", string.upper) end
    end
    for id in pairs(m.points or {}) do add(id) end
    local ids = {}
    for id in pairs(m.definitions) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local groups = m.definitions[id].PointGroups
        if type(groups) == "table" then
            for key, title in pairs(groups) do add(key, title) end
        end
    end
    add(selected)
    local out = {}
    for id, title in pairs(names) do out[#out + 1] = {id = id, title = title} end
    table.sort(out, function(a, b) return a.title == b.title and a.id < b.id or a.title < b.title end)
    return out
end
local function Send(ply, message, group)
    local m = Framework()
    local data = {available = m ~= nil, message = message or "", group = group or selectedGroups[ply] or "altar"}
    if m then
        local mode, variant = m:Round()
        data.version = ZC_HMCD_MUTATOR_INFO.Version
        data.active = m.current and m.current.definition.Title or "None"
        data.queued = m.forced or "none"
        data.waiting = m.waiting ~= nil
        data.midRoundSupport = type(m.ActivateNow) == "function" and type(m.CanActivateNow) == "function" and type(m.RoundToken) == "function"
        data.nowToken = data.midRoundSupport and m:RoundToken() or ""
        data.variant = variant or "unsupported"
        data.settings = {}
        for key, spec in pairs(settings) do
            local cv = GetConVar(spec[1])
            data.settings[key] = cv:GetFloat() / (spec[5] or 1)
        end
        data.definitions = {}
        local ids = {}
        for id in pairs(m.definitions) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local def = m.definitions[id]
            local _, reason = m:Eligible(def, mode, variant, false)
            local nowAllowed, nowReason = false, "Update zc_hmcd_mutators to enable mid-round controls."
            if data.midRoundSupport then nowAllowed, nowReason = m:CanActivateNow(id) end
            local variants = {}
            for name, allowed in pairs(def.Types) do if allowed then variants[#variants + 1] = name end end
            table.sort(variants)
            data.definitions[#data.definitions + 1] = {
                id = id, title = def.Title, description = def.Description,
                enabled = def.enabled:GetBool(), weight = def.weight:GetFloat(),
                variants = table.concat(variants, ", "), reason = reason, nowAllowed = nowAllowed, nowReason = nowReason
            }
        end
        data.specialRoles, data.rolePlayers = {}, {}
        data.roleSupport = type(m.QueueSpecialRole) == "function"
        if data.roleSupport then
            for _, target in ipairs(player.GetAll()) do
                local id = m.RolePlayerID(target)
                if id then data.rolePlayers[#data.rolePlayers + 1] = {id = id, name = target:Nick():sub(1, 128)} end
            end
            table.sort(data.rolePlayers, function(a, b) return a.name == b.name and a.id < b.id or a.name < b.name end)
            for id, role in pairs(m.roles) do
                local pick = m.rolePicks[id]
                local _, reason = m:SpecialRoleCandidates(id)
                data.specialRoles[#data.specialRoles + 1] = {id = id, title = role.Title, mutation = role.Mutator,
                    queued = pick and pick.steamID or "none", name = pick and pick.name or "Random", status = reason}
            end
            table.sort(data.specialRoles, function(a, b) return a.id < b.id end)
        end
        data.pointGroups = PointGroups(m, data.group)
        data.points = {}
        for i, point in ipairs(m:GetPoints(data.group)) do
            data.points[i] = {x = point.pos.x, y = point.pos.y, z = point.pos.z, yaw = point.ang.y}
        end
    end
    net.Start("traitoradmin_mutator_data")
    net.WriteTable(data)
    net.Send(ply)
end
net.Receive("traitoradmin_mutator_action", function(len, ply)
    -- No generic console executor: only known operations and bounded values get through.
    if not IsValid(ply) or not (ply:IsAdmin() or ply:IsSuperAdmin()) or len > 2048 then return end
    local action, target, value = net.ReadString(), net.ReadString(), net.ReadString()
    if #action > 24 or #target > 40 or #value > 160 then return end
    enqueue(ply, function()
    local isPointAction = action == "point_list" or action == "point_add" or action == "point_remove"
    local group = isPointAction and target or selectedGroups[ply] or "altar"
    if not groupOK(group) then Send(ply, "Use a group name such as altar."); return end
    local m = Framework()
    if not m then Send(ply, "Install zc_hmcd_mutators and restart to enable this page."); return end
    if isPointAction then selectedGroups[ply] = group end
    local message = ""
    if action == "get" then
        -- Read-only snapshot; no subscriptions or player polling.
    elseif action == "next" then
        if target ~= "none" and not m.definitions[target] then Send(ply, "Unknown mutation."); return end
        concommand.Run(ply, "zc_mutator_next", {target}, target)
        message = target == "none" and "Next mutation cleared." or "Queued for the next compatible round."
    elseif action == "now" then
        if type(m.ActivateNow) ~= "function" or type(m.RoundToken) ~= "function" then Send(ply, "Update zc_hmcd_mutators for mid-round controls."); return end
        if value ~= m:RoundToken() then Send(ply, "The round or mutation changed. Review the refreshed controls before starting."); return end
        local ok
        ok, message = m:ActivateNow(target, ply:Nick())
    elseif action == "role_pick" then
        if not m.QueueSpecialRole then Send(ply, "Update zc_hmcd_mutators for special-role controls."); return end
        local ok
        ok, message = m:QueueSpecialRole(target, value)
        if ok then m:Log(ply:Nick() .. " set special role " .. target .. " = " .. value) end
    elseif action == "cancel" then
        concommand.Run(ply, "zc_mutator_cancel", {}, "")
        message = "Current/waiting mutation cancelled. Next queue unchanged."
    elseif action == "status" or action == "list" then
        concommand.Run(ply, "zc_mutator_" .. action, {}, "")
        message = "Output printed to your client console."
    elseif action == "setting" then
        local spec = settings[target]
        local n = spec and number(value, spec[2], spec[3], spec[4])
        if not n then Send(ply, "Invalid setting or value."); return end
        local cv = GetConVar(spec[1])
        cv:SetFloat(n * (spec[5] or 1)) -- Existing FCVAR_ARCHIVE convars persist in server.vdf.
        message = "Saved " .. target .. ". Applies to future selections."
        if target == "enabled" and n == 0 then message = "Saved: framework OFF. Active/waiting mutation will stop." end
        m:Log(ply:Nick() .. " set " .. spec[1] .. " = " .. tostring(cv:GetFloat()))
    elseif action == "module_enabled" or action == "module_weight" then
        local def = m.definitions[target]
        local toggle = action == "module_enabled"
        local n = number(value, 0, toggle and 1 or 100, toggle)
        if not def or not n then Send(ply, "Invalid mutation setting."); return end
        local cv = toggle and def.enabled or def.weight
        cv:SetFloat(n)
        message = "Saved mutation setting. Applies to future selections."
        m:Log(ply:Nick() .. " set " .. target .. " " .. action .. " = " .. tostring(n))
    elseif action == "point_list" then
        concommand.Run(ply, "zc_mutator_point_list", {group}, group)
        message = "Map points refreshed; details also printed to your console."
    elseif action == "point_add" then
        local args = {group}
        if value ~= "" then
            for part in value:gmatch("%S+") do
                if not number(part, -32768, 32768, false) then Send(ply, "Enter numeric x y z yaw.", group); return end
                args[#args + 1] = part
            end
            if #args ~= 5 then Send(ply, "Enter x y z yaw, or leave blank to use your crosshair.", group); return end
        end
        concommand.Run(ply, "zc_mutator_point_add", args, table.concat(args, " "))
        message = "Point command completed; see your console for the result."
    elseif action == "point_remove" then
        local index = number(value, 1, 64, true)
        if not index then Send(ply, "Select a saved point.", group); return end
        concommand.Run(ply, "zc_mutator_point_remove", {group, tostring(index)}, group .. " " .. index)
        message = "Point command completed; see your console for the result."
    else
        Send(ply, "Unknown mutation action.")
        return
    end
    Send(ply, message, group)
    end, action == "get" or action == "point_list")
end)
