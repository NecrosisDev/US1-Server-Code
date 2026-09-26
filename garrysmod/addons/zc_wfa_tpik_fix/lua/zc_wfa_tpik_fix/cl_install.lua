-- Install after WFA has loaded; never replace an unknown implementation.
local VERSION = "1.0.1"
local SOURCE_HASH = "a90dc090f290a9c81f11c76364ab08aad3afaebc0d1c689c662d45242c72a937"
local SOURCE_PATH = "homigrad/cl_tpikzzzmwwork.lua"
local NET = "zc_wfa_tpik_status"
local SERVER_HASH_KEY = "zc_wfa_tpik_source_sha256"
local factory = include("zc_wfa_tpik_fix/cl_dotypik.lua")
ZC_WFA_TPIK_FIX = ZC_WFA_TPIK_FIX or {counts = {}}
local state = ZC_WFA_TPIK_FIX
state.version = VERSION
local keys = {"cache_rebuilt", "invalid_position", "missing_matrix", "missing_bone", "bad_pole", "missing_weapon"}

local function Record(reason)
    state.counts[reason] = (state.counts[reason] or 0) + 1
end

local function Active()
    return hg and state.installed and hg.DoTPIK == state.installed or false
end

local function Install()
    if Active() then return true end
    if not hg or type(hg.DoTPIK) ~= "function" or type(hg.IKSolve) ~= "function" then
        state.reason = "waiting for WFA"
        return false
    end
    local info = debug.getinfo(hg.DoTPIK, "S")
    if not info or not string.find(info.source or "", "cl_tpikzzzmwwork.lua", 1, true) then
        state.reason = "another addon owns hg.DoTPIK"
        return false
    end
    local solverInfo = debug.getinfo(hg.IKSolve, "S")
    if not solverInfo or not string.find(solverInfo.source or "", "cl_tpikzzzmwwork.lua", 1, true) then
        state.reason = "another addon owns hg.IKSolve"
        return false
    end
    -- Cached server-delivered Lua can execute while file.Read returns nil.
    -- Both live functions must still belong to the reviewed source layout.
    if info.source ~= solverInfo.source
        or info.linedefined ~= 920 or info.lastlinedefined ~= 1331
        or solverInfo.linedefined ~= 901 or solverInfo.lastlinedefined ~= 918 then
        state.reason = "WFA function layout differs from the reviewed export"
        return false
    end
    local source = file.Read(SOURCE_PATH, "LUA")
    local verification
    if source ~= nil then
        if util.SHA256(source) ~= SOURCE_HASH then
            state.reason = "client WFA source differs from the reviewed export"
            return false
        end
        verification = "client source verified"
    else
        local serverHash = GetGlobalString(SERVER_HASH_KEY, "")
        if serverHash == "" or serverHash == "unreadable" then
            state.reason = "client source unreadable; waiting for server source verification"
            return false
        end
        if serverHash ~= SOURCE_HASH then
            state.reason = "client source unreadable; server WFA source differs from the reviewed export"
            return false
        end
        verification = "server source verified"
    end
    state.verification = verification
    state.original = hg.DoTPIK
    state.installed = factory(hg, hg.IKSolve, Record)
    hg.DoTPIK = state.installed
    state.reason = "active"
    print("[zc_wfa_tpik_fix] v" .. VERSION .. " active")
    return true
end

local function Attempt()
    if Install() then timer.Remove("zc_wfa_tpik_install") end
end

-- Bounded startup retry handles addon/gamemode load order. No per-frame patching.
timer.Create("zc_wfa_tpik_install", 1, 30, Attempt)
hook.Add("OnGamemodeLoaded", "zc_wfa_tpik_fix", Attempt)
hook.Add("InitPostEntity", "zc_wfa_tpik_fix", Attempt)
hook.Add("OnReloaded", "zc_wfa_tpik_fix", function()
    timer.Create("zc_wfa_tpik_install", 1, 30, Attempt)
    timer.Simple(0, Attempt)
end)
Attempt()

local function Reason()
    if Active() then return "active; " .. (state.verification or "previously verified") end
    if state.installed then return "override no longer active; run status after checking load order" end
    return state.reason or "not initialized"
end

concommand.Add("zc_wfa_tpik_fix_status", function()
    print("[zc_wfa_tpik_fix] v" .. VERSION .. " " .. Reason())
    for _, key in ipairs(keys) do print("  " .. key .. ": " .. (state.counts[key] or 0)) end
end)

net.Receive(NET, function()
    local request = net.ReadUInt(16)
    net.Start(NET)
    net.WriteUInt(request, 16)
    net.WriteString(VERSION)
    net.WriteBool(Active())
    net.WriteString(Reason())
    for _, key in ipairs(keys) do
        net.WriteUInt(math.min(state.counts[key] or 0, 4294967295), 32)
    end
    net.SendToServer()
end)
