local NET = "zc_wfa_tpik_status"
if CLIENT then
    include("zc_wfa_tpik_fix/cl_install.lua")
    return
end

AddCSLuaFile("zc_wfa_tpik_fix/cl_install.lua")
AddCSLuaFile("zc_wfa_tpik_fix/cl_dotypik.lua")
util.AddNetworkString(NET)

-- Publish the actual server-mounted source hash. Clients with unreadable cached
-- Lua may use this alongside strict checks on both loaded WFA function layouts.
local SOURCE_PATH = "homigrad/cl_tpikzzzmwwork.lua"
local SERVER_HASH_KEY = "zc_wfa_tpik_source_sha256"
local function PublishSourceHash()
    local source = file.Read(SOURCE_PATH, "LUA")
    SetGlobalString(SERVER_HASH_KEY, source ~= nil and util.SHA256(source) or "unreadable")
    if source ~= nil then timer.Remove("zc_wfa_tpik_source_verify") end
end
local function VerifySource()
    timer.Create("zc_wfa_tpik_source_verify", 1, 30, PublishSourceHash)
    PublishSourceHash()
end
hook.Add("OnGamemodeLoaded", "zc_wfa_tpik_source_verify", VerifySource)
hook.Add("InitPostEntity", "zc_wfa_tpik_source_verify", VerifySource)
hook.Add("OnReloaded", "zc_wfa_tpik_source_verify", VerifySource)
VerifySource()

local request = 0
local pending = {}
local deadline = 0
local keys = {"cache_rebuilt", "invalid_position", "missing_matrix", "missing_bone", "bad_pole", "missing_weapon"}

concommand.Add("zc_wfa_tpik_fix_status", function(caller)
    if IsValid(caller) and not caller:IsAdmin() then return end
    request = (request + 1) % 65536
    pending = {}
    local humans = player.GetHumans()
    if #humans == 0 then print("[zc_wfa_tpik_fix] No connected human players.") return end
    for _, ply in ipairs(humans) do pending[ply] = true end
    deadline = CurTime() + 5
    net.Start(NET)
    net.WriteUInt(request, 16)
    net.Send(humans)
    print("[zc_wfa_tpik_fix] Requesting client status...")
    local thisRequest = request
    timer.Simple(5, function()
        if thisRequest ~= request then return end
        for ply in pairs(pending) do
            if IsValid(ply) then print("[zc_wfa_tpik_fix] " .. ply:Nick() .. ": NO RESPONSE") end
        end
        pending = {}
    end)
end, nil, "Admin: collect the weapon TPIK fix status from every client.")

net.Receive(NET, function(_, ply)
    if not pending[ply] or CurTime() > deadline then return end
    if net.ReadUInt(16) ~= request then return end
    pending[ply] = nil
    local version = string.sub(net.ReadString(), 1, 20)
    local active = net.ReadBool()
    local reason = string.sub(net.ReadString(), 1, 140)
    local counts = {}
    for _, key in ipairs(keys) do counts[#counts + 1] = key .. "=" .. net.ReadUInt(32) end
    print("[zc_wfa_tpik_fix] " .. ply:Nick() .. " v" .. version .. " "
        .. (active and "ACTIVE" or "INACTIVE") .. " (" .. reason .. ") " .. table.concat(counts, " "))
end)
