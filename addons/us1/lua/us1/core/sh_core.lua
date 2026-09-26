-- US1 core: logging, guarded includes, readiness gate, function wrapping.
-- Mirrors Z-City's loader conventions (lua/autorun/loader.lua upstream): sv_/sh_/cl_ prefix selects the realm,
-- every include is pcall-guarded so one broken module cannot stop the rest from loading.
US1 = US1 or {}
local US1 = US1

------------------------------------------------------------------------------------------------------------------------
-- Logging
------------------------------------------------------------------------------------------------------------------------
US1.Errors = US1.Errors or {}

function US1.Log(module, fmt, ...)
    MsgC(Color(90, 170, 255), "[US1:" .. tostring(module) .. "] ", color_white, string.format(fmt, ...), "\n")
end

function US1.Error(module, err)
    local msg = "[US1:" .. tostring(module) .. "] " .. tostring(err)
    US1.Errors[#US1.Errors + 1] = {module = module, err = tostring(err), time = os.time()}
    ErrorNoHalt(msg .. "\n")
end

------------------------------------------------------------------------------------------------------------------------
-- Realm-aware guarded include (Z-City naming: sv_/sh_/cl_ prefix; no prefix = shared)
------------------------------------------------------------------------------------------------------------------------
local function realmOf(path)
    local name = string.GetFileFromFilename(path)
    local p = string.sub(name, 1, 3)
    if p == "sv_" then return "sv" elseif p == "cl_" then return "cl" end
    return "sh"
end

function US1.Include(path, realm)
    realm = realm or realmOf(path)
    if SERVER and realm ~= "sv" then AddCSLuaFile(path) end
    if (realm == "sv" and CLIENT) or (realm == "cl" and SERVER) then return true end
    local ok, err = pcall(include, path)
    if not ok then US1.Error(path, err) end
    return ok
end

-- A module is a folder under us1/modules/<name>/. Its files load in the order given by <name>/_order.lua
-- (a plain list of file names); without one, files load sorted by name. Load order is never implied by
-- filename tricks like zz_ prefixes.
US1.Modules = US1.Modules or {}

function US1.LoadModules(root)
    local _, dirs = file.Find(root .. "/*", "LUA")
    table.sort(dirs)
    for _, name in ipairs(dirs) do
        local dir = root .. "/" .. name
        local order
        if file.Exists(dir .. "/_order.lua", "LUA") then
            if SERVER then AddCSLuaFile(dir .. "/_order.lua") end
            local ok, list = pcall(include, dir .. "/_order.lua")
            if ok and istable(list) then order = list else US1.Error(name, "bad _order.lua: " .. tostring(list)) end
        end
        if not order then
            order = file.Find(dir .. "/*.lua", "LUA")
            table.sort(order)
        end
        local okAll = true
        for _, f in ipairs(order) do
            if f ~= "_order.lua" then okAll = US1.Include(dir .. "/" .. f) and okAll end
        end
        US1.Modules[name] = {loaded = okAll, files = #order}
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Readiness: run code once Z-City's globals (hg, zb) exist and the world has spawned.
-- Replaces the "retry every 0.25-1 s" timers and InitPostEntity/HomigradRun guesswork in older files.
------------------------------------------------------------------------------------------------------------------------
US1.ReadyQueue = US1.ReadyQueue or {}
US1.Ready = US1.Ready or {homigrad = false, world = false}

local function isReady() return US1.Ready.homigrad and US1.Ready.world end

local function flush()
    if not isReady() then return end
    local q = US1.ReadyQueue
    US1.ReadyQueue = {}
    for _, item in ipairs(q) do
        local ok, err = pcall(item.fn)
        if not ok then US1.Error(item.id, err) end
    end
end

-- fn runs exactly once, after both HomigradRun and InitPostEntity; immediately if both already happened
-- (e.g. on a lua refresh).
function US1.OnReady(id, fn)
    if isReady() then
        local ok, err = pcall(fn)
        if not ok then US1.Error(id, err) end
        return
    end
    US1.ReadyQueue[#US1.ReadyQueue + 1] = {id = id, fn = fn}
end

if hg and hg.loaded then US1.Ready.homigrad = true end
hook.Add("HomigradRun", "US1.core.ready", function() US1.Ready.homigrad = true flush() end)
hook.Add("InitPostEntity", "US1.core.ready", function() US1.Ready.world = true flush() end)
-- A refresh after the map loaded: InitPostEntity will not fire again.
if game.GetWorld and IsValid(game.GetWorld()) and CurTime() > 1 then US1.Ready.world = true end

------------------------------------------------------------------------------------------------------------------------
-- Function wrapping: the one sanctioned way to override hg.* / zb.* / engine functions.
-- Chains the original, is idempotent across lua refresh (re-wrapping replaces our layer instead of stacking),
-- and records every wrapper so collisions are visible via US1.Status().
------------------------------------------------------------------------------------------------------------------------
US1.Wrapped = US1.Wrapped or {}

function US1.Wrap(tbl, key, id, make)
    assert(istable(tbl), "US1.Wrap: target is not a table")
    local reg = US1.Wrapped[tbl] or {}
    US1.Wrapped[tbl] = reg
    local entry = reg[key]
    local current = tbl[key]
    -- Our own layer is on top: rebuild on the original underneath instead of stacking another copy.
    if entry and current == entry.wrapped and entry.id == id then current = entry.original end
    assert(isfunction(current), "US1.Wrap: " .. tostring(key) .. " is not a function")
    local wrapped = make(current)
    assert(isfunction(wrapped), "US1.Wrap: maker must return a function")
    tbl[key] = wrapped
    reg[key] = {id = id, original = current, wrapped = wrapped, previous = entry and entry.id}
    return wrapped
end

------------------------------------------------------------------------------------------------------------------------
-- Status
------------------------------------------------------------------------------------------------------------------------
function US1.Status()
    US1.Log("core", "version %s  ready: homigrad=%s world=%s  queued=%d  errors=%d", US1.Version,
        tostring(US1.Ready.homigrad), tostring(US1.Ready.world), #US1.ReadyQueue, #US1.Errors)
    for name, m in SortedPairs(US1.Modules) do US1.Log("core", "module %-20s %s (%d files)", name, m.loaded and "ok" or "ERR", m.files) end
    for _, e in ipairs(US1.Errors) do US1.Log("core", "error %s: %s", e.module, e.err) end
end

if SERVER then
    concommand.Add("us1_status", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        US1.Status()
    end)
end
