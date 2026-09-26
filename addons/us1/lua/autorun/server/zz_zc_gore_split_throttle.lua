-- Throttle for Z-City Gore V2's "ZCity Gore V2_SplitPhysics" Think (workshop 3780773397, z_podgruz.lua:806).
-- Measured 2026-09-24 (zc_perf, 27 players): 0.12 ms every frame + 250 KB/s allocation, the second largest
-- allocator on the server. The body only re-pins hidden physics on severed torsos and their caps; doing that
-- every other tick (25 Hz at 50 tick) is visually identical. Wraps the addon's own hook by identity, so a
-- re-registration by the addon (it installs via a 0.25 s wait timer) is picked up within a second.
-- zc_gore_split_every 1 = untouched (addon behaviour), 2 = every other tick (default), up to 4.
if not SERVER then return end

local NAME = "ZCity Gore V2_SplitPhysics"
local cv = CreateConVar("zc_gore_split_every", "2", FCVAR_ARCHIVE, "Run the Gore V2 split-physics Think every N ticks (1 = off)", 1, 4)

ZCGoreSplitThrottle = ZCGoreSplitThrottle or {version = "20260924.1"}
local T = ZCGoreSplitThrottle
T.wrapped = T.wrapped or setmetatable({}, {__mode = "k"}) -- wrapper -> original

local function install()
    local think = hook.GetTable().Think
    local fn = think and think[NAME]
    if not fn or T.wrapped[fn] then return end -- absent, or already ours
    local original = fn
    local n = 0
    local function wrapper(...)
        local every = cv:GetInt()
        if every > 1 then
            n = n + 1
            if n % every ~= 0 then return end
        end
        return original(...)
    end
    T.wrapped[wrapper] = original
    hook.Add("Think", NAME, wrapper)
    T.installedAt = CurTime()
end

hook.Add("InitPostEntity", "ZCGoreSplitThrottle", install)
timer.Create("ZCGoreSplitThrottle", 1, 0, install)
install()

concommand.Add("zc_gore_split_status", function(p)
    if IsValid(p) and not p:IsAdmin() then return end
    local think = hook.GetTable().Think
    local fn = think and think[NAME]
    local line = string.format("[GoreSplitThrottle %s] every=%d hook=%s wrapped=%s", T.version, cv:GetInt(),
        fn and "present" or "absent", tostring(fn ~= nil and T.wrapped[fn] ~= nil))
    if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
end, nil, "Admin: print the gore split-physics throttle status.")
