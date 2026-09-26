hook.Remove("PlayerInitialSpawn", "ZCChatPolishOwnerRestore")
-- One-session transport for clients already connected before beta installation.
-- Normal gamemode/AddCSLuaFile loading owns future map changes.
if not SERVER then return end
local BUILD = "20260922.polish4"
util.AddNetworkString("ZCChatBetaPayload")
util.AddNetworkString("ZCChatBetaAck")
ZCChatBetaRollout = ZCChatBetaRollout or {sent = {}, ack = {}}
local state = ZCChatBetaRollout
net.Receive("ZCChatBetaAck", function(length, ply)
    if length > 4096 or not state.sent[ply] then return end
    local ok, detail = net.ReadBool(), net.ReadString()
    if state.ack[ply] then return end
    state.ack[ply] = {ok = ok, detail = detail}
    print("ZC_CHAT_BETA_ACK", ply:UserID(), ok, detail)
end)
local paths = {
    ["client.lua"] = "zc_chat_media/client.lua",
    ["cl_zchat.lua"] = "homigrad/zchat/derma/cl_zchat.lua",
    ["sh_chat.lua"] = "homigrad/zchat/sh_chat.lua",
    ["cl_ulx_lib.lua"] = "ulx/cl_lib.lua",
}
local sources = {}
for name, path in pairs(paths) do
    sources[name] = assert(file.Read(path, "LUA"), "Missing beta source " .. path)
    AddCSLuaFile(path)
end
local loader = assert(file.Read("zc_chat_beta_stage/cl_beta_apply.txt", "DATA"))
local packed = assert(util.Compress(util.TableToJSON({sources = sources, loader = loader})))
local bootstrap = [=[
ZCChatBetaParts={}
net.Receive("ZCChatBetaPayload",function()
 local i,n,len=net.ReadUInt(8),net.ReadUInt(8),net.ReadUInt(16)
 local p=ZCChatBetaParts if not p then return end p[i]=net.ReadData(len)
 for k=1,n do if not p[k] then return end end
 ZCChatBetaParts=nil
 local payload=util.JSONToTable(util.Decompress(table.concat(p)) or "")
 if not payload then return end
 local fn=CompileString(payload.loader,"ZCChatBetaApply",false)
 if not isfunction(fn) then ErrorNoHalt(tostring(fn)) return end
 fn()(payload.sources)
end)
]=]
local function send(ply)
    if not IsValid(ply) or ply:IsBot() then return end
    state.sent[ply] = true
    state.ack[ply] = nil
    ply:SendLua(bootstrap)
    timer.Simple(1, function()
        if not IsValid(ply) then return end
        local count = math.ceil(#packed / 8192)
        for i = 1, count do
            local chunk = packed:sub((i - 1) * 8192 + 1, i * 8192)
            timer.Simple((i - 1) * 0.3, function()
                if not IsValid(ply) then return end
                net.Start("ZCChatBetaPayload")
                net.WriteUInt(i, 8) net.WriteUInt(count, 8)
                net.WriteUInt(#chunk, 16) net.WriteData(chunk, #chunk)
                net.Send(ply)
            end)
        end
        print("ZC_CHAT_BETA_SENT", ply:UserID(), BUILD)
    end)
end
state.Send = send
hook.Add("PlayerInitialSpawn", "ZCChatBetaJoinRefresh", function(ply)
    timer.Simple(12, function() if IsValid(ply) then send(ply) end end)
end)
hook.Add("PlayerDisconnected", "ZCChatBetaRolloutCleanup", function(ply)
    state.sent[ply], state.ack[ply] = nil, nil
end)
print("ZC_CHAT_BETA_TRANSPORT_READY", #packed)

for i, ply in ipairs(player.GetHumans()) do
    timer.Simple((i-1)*2, function()
        if IsValid(ply) then ZCChatBetaRollout.Send(ply) end
    end)
end
print("ZC_POLISH_PUBLIC_REFRESH_QUEUED")
