-- US1.Net: validated, rate-limited net receivers. Every new client->server message goes through here.
local US1 = US1
US1.Net = US1.Net or {}
local Net = US1.Net

local last = {}   -- [name] = {[ply] = time}

-- opts: maxBits (default 4096), rate (min seconds between messages per player, default 0.1),
--       admin (require IsAdmin), superadmin (require IsSuperAdmin)
function Net.Receive(name, opts, fn)
    opts = opts or {}
    local maxBits, rate = opts.maxBits or 4096, opts.rate or 0.1
    util.AddNetworkString(name)
    last[name] = last[name] or setmetatable({}, {__mode = "k"})
    local times = last[name]
    net.Receive(name, function(len, ply)
        if not IsValid(ply) or not ply:IsPlayer() then return end
        if len > maxBits then return end
        if opts.superadmin and not ply:IsSuperAdmin() then return end
        if opts.admin and not ply:IsAdmin() then return end
        local now = SysTime()
        if times[ply] and now - times[ply] < rate then return end
        times[ply] = now
        local ok, err = pcall(fn, len, ply)
        if not ok then US1.Error("net:" .. name, err) end
    end)
end
