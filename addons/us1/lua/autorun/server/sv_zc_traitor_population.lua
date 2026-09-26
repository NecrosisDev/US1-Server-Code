-- Population target for ordinary Homicide. Never edits a player's current role.
if not SERVER then return end
local previous = ZC_TRAITOR_POPULATION
if previous and previous.Shutdown then previous.Shutdown() end
local K = {Version = "1.0.0", active = true, depth = 0}
ZC_TRAITOR_POPULATION = K
local enabled = CreateConVar("zc_traitor_population_enabled", "1", FCVAR_ARCHIVE, "Use population-based traitor targets in ordinary Homicide", 0, 1)
local threshold = CreateConVar("zc_traitor_population_threshold", "16", FCVAR_ARCHIVE, "Non-spectator participants required for two traitors", 2, 128)
local allowed = {standard = true, gunfreezone = true, soe = true, wildwest = true}
local function pack(...) return {n = select("#", ...), ...} end
function K.Count()
    local count = 0
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:Team() ~= TEAM_SPECTATOR then count = count + 1 end
    end
    return count
end
function K.Target(count) return count >= threshold:GetInt() and 2 or 1 end
local function ordinary(self)
    if not zb or not zb.modes or self ~= zb.modes.hmcd or type(CurrentRound) ~= "function" then return false end
    local mode, variant = CurrentRound()
    if mode ~= self then return false end
    if variant and variant ~= "hmcd" then return allowed[variant] == true end
    -- Native generic hmcd chooses a random submode inside Intermission.
    -- Only scale it when every possible result is an ordinary variant.
    if type(self.SubModes) ~= "function" then return false end
    local modes = self:SubModes()
    if type(modes) ~= "table" or next(modes) == nil then return false end
    for _, name in pairs(modes) do if not allowed[name] then return false end end
    return true
end
local function dispatch(original, self, ...)
    if not K.active or K.depth > 0 or not enabled:GetBool() or not ordinary(self) then return original(self, ...) end
    local cv = GetConVar("homicide_traitoramount")
    if not cv then return original(self, ...) end
    local count = K.Count()
    local target, saved = K.Target(count), cv:GetInt()
    local args, result = pack(...)
    K.depth = K.depth + 1
    local ok, failure = xpcall(function()
        if saved ~= target then cv:SetInt(target) end
        result = pack(original(self, unpack(args, 1, args.n)))
    end, debug.traceback)
    K.depth = K.depth - 1
    -- Respect an explicit setting change made by another addon during selection.
    if saved ~= target and cv:GetInt() == target then cv:SetInt(saved) end
    if not ok then error(failure, 0) end
    K.last = {participants = count, target = target, at = CurTime()}
    return unpack(result, 1, result.n)
end
function K.Sync()
    if not K.active then return end
    local mode = zb and zb.modes and zb.modes.hmcd
    if not mode or type(mode.Intermission) ~= "function" then return end
    if K.mode == mode and mode.Intermission == K.wrapper then return end
    -- Restore only our own slot if the gamemode table has been replaced.
    if K.mode and K.mode.Intermission == K.wrapper then K.mode.Intermission = K.original end
    local original = mode.Intermission -- immutable delegate; no mutable-original recursion
    if ZCityMetaSafety and ZCityMetaSafety.RoleFunction then original=ZCityMetaSafety.RoleFunction(original) end
    local wrapper = function(self, ...) return dispatch(original, self, ...) end
    K.mode, K.original, K.wrapper = mode, original, wrapper
    mode.Intermission = wrapper
end
function K.Shutdown()
    K.active = false
    timer.Remove("zc_traitor_population_sync")
    hook.Remove("InitPostEntity", "zc_traitor_population_install")
    if K.mode and K.mode.Intermission == K.wrapper then K.mode.Intermission = K.original end
end
hook.Add("InitPostEntity", "zc_traitor_population_install", K.Sync)
-- Only checks a function slot; players are counted once at selection, not on this timer.
timer.Create("zc_traitor_population_sync", 1, 0, K.Sync)
K.Sync()
concommand.Add("zc_traitor_population_status", function(ply)
    if IsValid(ply) and not (ply:IsAdmin() or ply:IsSuperAdmin()) then return end
    local count = K.Count()
    local installed = K.mode and K.mode.Intermission == K.wrapper
    local message = string.format("[Traitor Population] v%s enabled=%s installed=%s participants=%d threshold=%d population target=%d",
        K.Version, tostring(enabled:GetBool()), tostring(installed == true), count, threshold:GetInt(), K.Target(count))
    if K.last then message = message .. string.format(" last selection: %d participants -> target %d", K.last.participants, K.last.target) end
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, message) else print(message) end
end)
print("[Traitor Population] v" .. K.Version .. " loaded; applies at the next ordinary Homicide selection")
