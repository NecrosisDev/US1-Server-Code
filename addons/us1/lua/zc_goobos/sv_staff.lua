-- GoobOS Staff app, server side (UI cohesion U5, 2026-09-26): ULX access rights for every staff tool.
-- ZCStaff.Can(ply, tool) is the one permission check for the tools the Staff app (zc_goobos/staff.lua) lists: a ULX access
-- query (ULib.ucl.query) on the tool's right; IsAdmin() only when ULib is not installed. A tool that IS a ULX command uses
-- that command's own access string (ULX registers it, XGUI already lists it); every other tool gets a "zc staff <tool>"
-- right registered here with the group its old IsAdmin()/rank check implied, so the owner can move it in XGUI > Groups.
-- The client learns which tiles to show from "GoobOS.Staff.Rights" (on request, when ULib authenticates the player and
-- after any UCL change). That list is presentation only: every tool still checks on the server.
-- Also included directly by the server files whose commands check a right (if not ZCStaff then include(...) end), so it
-- must stay safe to run more than once.
if not SERVER then return end
local S = ZCStaff or (US1 and US1.Staff) or {}
ZCStaff = S
if US1 then US1.Staff = S end
S.Version = "20260926.staff1"
S.NetName = "GoobOS.Staff.Rights"

-- Tile order is the client's (staff.lua St.Tools); this is the permission table. group = the default ULX group for a
-- right registered here; nil = the right belongs to a ULX command that registers it itself.
S.Tools = {
    {id = "guilt", right = "ulx guiltadmin"},
    {id = "logs", right = "zc staff logs", group = "operator", help = "Staff app: the ULX command log and punishment history (ulx_logs_open)"},
    {id = "restart", right = "ulx restart"},
    {id = "killzones", right = "zc staff killzones", group = "admin", help = "Staff app: the kill zone editor (zkill_menu)"},
    {id = "pprops", right = "ulx persistentpropsmenu"},
    {id = "watchdog", right = "zc staff watchdog", group = "admin", help = "Staff app: the Watchdog panel (wd)"},
    {id = "traitor", right = "zc staff traitor", group = "admin", help = "Staff app: Traitor admin (traitor_admin, F8)"},
    {id = "playertools", right = "zc staff playertools", group = "admin", help = "Crusher, super crusher and torso tools: make_torso, give_supercrusher, remove_supercrusher, the zc_selfmenu relay"}
}
S.ById = {}
for _, tool in ipairs(S.Tools) do S.ById[tool.id] = tool end

-- One ULX access check. The server console (and rcon) has every right, as it does in ULib.
function S.Allowed(ply, right)
    if not IsValid(ply) then return true end
    if not ply:IsPlayer() or not isstring(right) then return false end
    local ucl = ULib and ULib.ucl
    if ucl and ucl.query then
        local ok, yes = pcall(ucl.query, ply, right) -- errors for a player ULib has not authenticated yet: deny
        return ok and yes == true
    end
    return ply:IsAdmin() -- ULib not installed: the check these tools used before
end

-- Unknown tool ids are denied.
function S.Can(ply, tool)
    local entry = S.ById[tool]
    return entry ~= nil and S.Allowed(ply, entry.right)
end

function S.Right(tool)
    local entry = S.ById[tool]
    return entry and entry.right or nil
end

function S.List(ply)
    local out = {}
    for _, tool in ipairs(S.Tools) do
        if S.Allowed(ply, tool.right) then out[#out + 1] = tool end
    end
    return out
end

-- Staff action log: ULX's log and silent echo (staff with "ulx hiddenecho" see it) when ULX is loaded, else the console.
-- format uses fancyLogAdmin tags: #A = ply (no argument), #T = a player argument, #s = a string argument.
function S.Log(ply, format, ...)
    if ulx and isfunction(ulx.fancyLogAdmin) then
        local ok, err = pcall(ulx.fancyLogAdmin, ply, true, format, ...)
        if ok then return end
        ErrorNoHalt("[US1 Staff] log failed: " .. tostring(err) .. "\n")
    end
    local args, i = {...}, 0
    local text = string.gsub(format, "#(%a)", function(tag)
        if tag == "A" then return IsValid(ply) and ply:Nick() or "(Console)" end
        i = i + 1
        local value = args[i]
        if IsValid(value) and value.Nick then return value:Nick() end
        return tostring(value)
    end)
    print("[US1 Staff] " .. text)
end

-- Runs `cmd "<target's name>"` the way game.ConsoleCommand did (as the server console), but through concommand.Run, so a
-- name holding a quote, semicolon or line break can never reach the console parser and run a second command. Returns
-- true when the command ran.
function S.RunOn(cmd, target)
    if not IsValid(target) or not target:IsPlayer() then return false end
    local name = target:Nick()
    local lua = concommand.GetTable()
    if lua[string.lower(cmd)] then
        local ok, err = pcall(concommand.Run, NULL, cmd, {name}, '"' .. name .. '"')
        if not ok then ErrorNoHalt("[US1 Staff] " .. cmd .. ": " .. tostring(err) .. "\n") end
        return ok
    end
    if string.find(name, "[%c\";]") then return false end -- engine command: only a name the parser reads as one argument
    game.ConsoleCommand(cmd .. ' "' .. name .. '"\n')
    return true
end

-- Rights registration (ULib keeps the default groups the first time a right appears; XGUI can change them after).
local function register()
    local ucl = ULib and ULib.ucl
    if not (ucl and ucl.registerAccess) then return false end
    for _, tool in ipairs(S.Tools) do
        if tool.group then ucl.registerAccess(tool.right, tool.group, tool.help, "US1 Staff") end
    end
    return true
end
if not register() then hook.Add("Initialize", "US1.Staff.Register", register) end

-- Rights list: UInt(5) count, then per tool its id and the ULX right it needs.
function S.Send(ply)
    if not IsValid(ply) or not ply:IsPlayer() or ply:IsBot() then return end
    local list = S.List(ply)
    net.Start(S.NetName)
    net.WriteUInt(#list, 5)
    for _, tool in ipairs(list) do
        net.WriteString(tool.id)
        net.WriteString(tool.right)
    end
    net.Send(ply)
end

-- The request carries no data; one per player every 2 s.
if US1 and US1.Net and US1.Net.Receive then
    US1.Net.Receive(S.NetName, {maxBits = 0, rate = 2}, function(_, ply) S.Send(ply) end)
else
    util.AddNetworkString(S.NetName)
    local asked = setmetatable({}, {__mode = "k"})
    net.Receive(S.NetName, function(len, ply)
        if len ~= 0 or not IsValid(ply) or not ply:IsPlayer() then return end
        if asked[ply] and SysTime() - asked[ply] < 2 then return end
        asked[ply] = SysTime()
        S.Send(ply)
    end)
end

-- Group or right changes reach open phones without a request (debounced: ULib fires these in bursts). The names are
-- ULib.HOOK_UCLCHANGED and ULib.HOOK_UCLAUTH.
local function pushAll()
    for _, ply in player.Iterator() do S.Send(ply) end
end
hook.Add("UCLChanged", "US1.Staff.Push", function()
    timer.Create("US1.Staff.Push", 1, 1, pushAll)
end)
hook.Add("UCLAuthed", "US1.Staff.Authed", function(ply)
    timer.Simple(0, function() S.Send(ply) end)
end)
