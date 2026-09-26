-- HD character textures: server half (tester lock only; the swap itself is client-side).
-- Owner 2026-09-25: opt-in, off by default, toggled from GoobOS Settings. New US1 features
-- start locked to one tester: zc_hd_textures_tester holds SteamID64s (any separator) or "*"
-- for everyone. Server-only convar, never replicated: clients only learn their own answer.
if not SERVER then return end

util.AddNetworkString("zc_hd_textures_hello")
util.AddNetworkString("zc_hd_textures_grant")

local cvTester = CreateConVar("zc_hd_textures_tester", "76561198011536179", FCVAR_ARCHIVE,
    "SteamID64s allowed to use HD character textures, or * for everyone; server only")

local function allowed(ply)
    local v = string.Trim(cvTester:GetString())
    if v == "*" then return true end
    local id = ply:SteamID64()
    for want in string.gmatch(v, "%d+") do
        if want == id then return true end
    end
    return false
end

-- The client asks once its file has loaded (join, reconnect, file refresh); the answer
-- goes to that player only. Same handshake as the aim-assist grant in sv_zc_crosshair.lua.
local function sendGrant(ply)
    if not IsValid(ply) then return end
    net.Start("zc_hd_textures_grant")
    net.WriteBool(allowed(ply))
    net.Send(ply)
end

local lastHello = setmetatable({}, { __mode = "k" })
net.Receive("zc_hd_textures_hello", function(_, ply)
    local now = CurTime()
    if (lastHello[ply] or 0) > now - 2 then return end
    lastHello[ply] = now
    sendGrant(ply)
end)

cvars.AddChangeCallback("zc_hd_textures_tester", function()
    for _, ply in ipairs(player.GetHumans()) do sendGrant(ply) end
end, "ZCHDTextures.Grant")

-- FastDL (owner 2026-09-25): the textures live loose in addons/zc_hd_textures/materials/zc_hd/
-- and every joining player downloads them. Registration happens at map load and stays off until
-- the FastDL mirror has been checked to serve them (otherwise joiners fall back to the slow direct
-- download). Set zc_hd_textures_fastdl 1; it applies from the next map change.
local cvFastDL = CreateConVar("zc_hd_textures_fastdl", "0", FCVAR_ARCHIVE,
    "1 = send the HD character textures to joining players via FastDL (applies at the next map change)", 0, 1)

local function walk(dir, register, count)
    local files, dirs = file.Find(dir .. "*", "GAME")
    for _, f in ipairs(files or {}) do
        if string.EndsWith(f, ".vtf") then
            if register then resource.AddSingleFile(dir .. f) end
            count = count + 1
        end
    end
    for _, d in ipairs(dirs or {}) do count = walk(dir .. d .. "/", register, count) end
    return count
end

local enabled = cvFastDL:GetBool()
local found = walk("materials/zc_hd/", enabled, 0)
-- Receipt: proves which build loaded, how many textures the server sees, and what it registered.
file.Write("zc_hd_textures_receipt.txt", os.date("!%Y-%m-%d %H:%M:%S") .. " sv 20260925.2 fastdl="
    .. tostring(enabled) .. " found=" .. found .. " registered=" .. (enabled and found or 0) .. "\n")
