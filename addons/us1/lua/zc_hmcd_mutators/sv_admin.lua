local M = ZC_HMCD_MUTATORS
local function allowed(ply) return not IsValid(ply) or ply:IsAdmin() end
local function reply(ply, text)
    local line = "[zc_mutators] " .. tostring(text)
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line .. "\n") else print(line) end
end
local HELP = {
    zc_mutator_status = "Admin: print the round mutator state (enabled, chance, active, queued).",
    zc_mutator_list = "Admin: list every round mutator with its weight and whether it can run this round.",
    zc_mutator_next = "Admin: queue a mutator for the next compatible round: zc_mutator_next <id|none>.",
    zc_mutator_now = "Admin: start a mutator in the current round: zc_mutator_now <id>.",
    zc_mutator_cancel = "Admin: cancel the current or waiting mutator (a queued one stays queued).",
    zc_mutator_point_add = "Admin: save a mutator point: zc_mutator_point_add <group> [x y z yaw]; in game, aim at a surface.",
    zc_mutator_point_list = "Admin: list saved mutator points: zc_mutator_point_list [group] (default altar).",
    zc_mutator_point_remove = "Admin: remove a saved mutator point: zc_mutator_point_remove <group> <index>.",
    zc_mutator_role = "Admin: pick who gets a special role: zc_mutator_role <role> <steamid64|none>.",
    zc_mutator_roles = "Admin: list the special roles and their picks."
}
local function command(name, fn)
    concommand.Add(name, function(ply, _, args)
        if not allowed(ply) then return end
        fn(ply, args)
    end, nil, HELP[name])
end
command("zc_mutator_status", function(ply)
    local mode, variant = M:Round()
    reply(ply, "v" .. ZC_HMCD_MUTATOR_INFO.Version .. " enabled=" .. M.enabled:GetInt()
        .. " auto=" .. M.auto:GetInt() .. " chance=" .. M.chance:GetFloat()
        .. " round=" .. tostring(variant or "unsupported") .. " index=" .. M.roundIndex)
    reply(ply, "active=" .. (M.current and M.current.definition.ID or "none")
        .. " waiting=" .. tostring(M.waiting ~= nil) .. " queued=" .. (M.forced or "none"))
    if M.current then reply(ply, "Running for " .. math.floor(CurTime() - M.current.started) .. " seconds; tracked cleanup actions=" .. #M.current.cleanups) end
end)
command("zc_mutator_list", function(ply)
    local mode, variant = M:Round()
    local ids = {}
    for id in pairs(M.definitions) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local def = M.definitions[id]
        local _, reason = M:Eligible(def, mode, variant, false)
        reply(ply, id .. " | " .. def.Title .. " | weight=" .. def.weight:GetFloat() .. " | " .. reason)
    end
end)
command("zc_mutator_next", function(ply, args)
    local id = args[1]
    if id == "none" then M.forced = nil; reply(ply, "Queued mutator cleared."); return end
    if not id or not M.definitions[id] then reply(ply, "Usage: zc_mutator_next <id|none>; see zc_mutator_list."); return end
    M.forced = id
    reply(ply, id .. " queued for the next compatible round; bypasses chance/cooldown, not requirements or the master switch.")
    M:Log("Queued " .. id .. " by " .. (IsValid(ply) and ply:Nick() or "server console"))
end)
command("zc_mutator_now", function(ply, args)
    local _, message = M:ActivateNow(args[1], IsValid(ply) and ply:Nick() or "server console")
    reply(ply, message)
end)
command("zc_mutator_cancel", function(ply)
    M:Cancel("cancelled by admin")
    reply(ply, "Current/waiting event cancelled. A separately queued next event remains queued.")
end)
command("zc_mutator_point_add", function(ply, args)
    local group, pos, yaw = args[1], nil, 0
    if #args == 1 and IsValid(ply) then
        local tr = ply:GetEyeTrace()
        if not tr.Hit or tr.HitSky then reply(ply, "Aim at a surface."); return end
        pos, yaw = tr.HitPos + tr.HitNormal * 2, ply:EyeAngles().y
    elseif #args == 5 then
        local x, y, z, angle = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]), tonumber(args[5])
        if M.Finite(x) and M.Finite(y) and M.Finite(z) and M.Finite(angle) then pos, yaw = Vector(x, y, z), angle end
    end
    if not pos then reply(ply, "Usage: zc_mutator_point_add <group> [x y z yaw]; in-game admins may aim at a surface."); return end
    local _, message = M:AddPoint(group, pos, yaw)
    reply(ply, message)
end)
command("zc_mutator_point_list", function(ply, args)
    local group = args[1] or "altar"
    local points = M:GetPoints(group)
    reply(ply, #points .. " saved points in " .. group .. " on " .. game.GetMap())
    for i, point in ipairs(points) do reply(ply, i .. ": " .. tostring(point.pos) .. " yaw=" .. point.ang.y) end
end)
command("zc_mutator_point_remove", function(ply, args)
    local _, message = M:RemovePoint(args[1], tonumber(args[2]))
    reply(ply, message)
end)


command("zc_mutator_role", function(ply, args)
    local ok, message = M:QueueSpecialRole(args[1], args[2])
    reply(ply, message)
    if ok then M:Log((IsValid(ply) and ply:Nick() or "Server console") .. " set special role " .. args[1] .. " = " .. args[2]) end
end)
command("zc_mutator_roles", function(ply)
    for id, role in pairs(M.roles) do
        local pick = M.rolePicks[id]
        local _, reason = M:SpecialRoleCandidates(id)
        reply(ply, id .. " [" .. role.Mutator .. "] " .. (pick and (pick.name .. " / " .. pick.steamID) or "random") .. " | " .. reason)
    end
end)
