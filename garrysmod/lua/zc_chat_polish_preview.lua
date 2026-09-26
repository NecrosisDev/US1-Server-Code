-- One-session transport for clients already connected before beta installation.
-- Normal gamemode/AddCSLuaFile loading owns future map changes.
if not SERVER then return end
local BUILD = "20260922.polish4"
util.AddNetworkString("ZCChatPolishPayload")
util.AddNetworkString("ZCChatPolishAck")
ZCChatPolishRollout = ZCChatPolishRollout or {sent = {}, ack = {}}
local state = ZCChatPolishRollout
net.Receive("ZCChatPolishAck", function(length, ply)
    if length > 4096 or not state.sent[ply] then return end
    local ok, detail = net.ReadBool(), net.ReadString()
    if state.ack[ply] then return end
    state.ack[ply] = {ok = ok, detail = detail}
    print("ZC_CHAT_POLISH_ACK", ply:UserID(), ok, detail)
end)
local sources = {}
for _, name in ipairs({"client.lua", "cl_zchat.lua"}) do
    sources[name] = assert(file.Read("zc_chat_polish_stage/" .. name .. ".txt", "DATA"))
    local compiled = CompileString(sources[name], "PhonePreflight/" .. name, false)
    assert(isfunction(compiled), tostring(compiled))
end
local loader = assert(file.Read("zc_chat_polish_stage/cl_polish_apply.txt", "DATA"))
assert(isfunction(CompileString(loader, "PhoneLoaderPreflight", false)))
local packed = assert(util.Compress(util.TableToJSON({sources = sources, loader = loader})))
local bootstrap = [=[
ZCChatPolishParts={}
net.Receive("ZCChatPolishPayload",function()
 local i,n,len=net.ReadUInt(8),net.ReadUInt(8),net.ReadUInt(16)
 local p=ZCChatPolishParts if not p then return end p[i]=net.ReadData(len)
 for k=1,n do if not p[k] then return end end
 ZCChatPolishParts=nil
 local payload=util.JSONToTable(util.Decompress(table.concat(p)) or "")
 if not payload then return end
 local fn=CompileString(payload.loader,"ZCChatPolishApply",false)
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
                net.Start("ZCChatPolishPayload")
                net.WriteUInt(i, 8) net.WriteUInt(count, 8)
                net.WriteUInt(#chunk, 16) net.WriteData(chunk, #chunk)
                net.Send(ply)
            end)
        end
        print("ZC_CHAT_POLISH_SENT", ply:UserID(), BUILD)
    end)
end
state.Send = send
print("ZC_CHAT_POLISH_TRANSPORT_READY", #packed)
local target
for _, ply in ipairs(player.GetHumans()) do
    if ply:SteamID() == "STEAM_0:1:25635225" then target=ply break end
end
if IsValid(target) then send(target) else print("ZC_CHAT_POLISH_OWNER_OFFLINE") end
