-- One-session transport for clients already connected before beta installation.
-- Normal gamemode/AddCSLuaFile loading owns future map changes.
if not SERVER then return end
local BUILD = "20260922.social6"
util.AddNetworkString("ZCChatModerationPayload")
util.AddNetworkString("ZCChatModerationAck")
ZCChatModerationRollout = ZCChatModerationRollout or {sent = {}, ack = {}}
local state = ZCChatModerationRollout
net.Receive("ZCChatModerationAck", function(length, ply)
    if length > 4096 or not state.sent[ply] then return end
    local ok, detail = net.ReadBool(), net.ReadString()
    if state.ack[ply] then return end
    state.ack[ply] = {ok = ok, detail = detail}
    print("ZC_CHAT_MODERATION_ACK", ply:UserID(), ok, detail)
end)
local sources={}
for _,name in ipairs({"client.lua","cl_zchat.lua","sv_zc_chat_reaction.lua","sv_zc_chat_moderation.lua"}) do
 local source=assert(file.Read("zc_chat_moderation_stage/"..name..".txt","DATA"))
 assert(isfunction(CompileString(source,"ModerationPreflight/"..name,false)))
 if name=="client.lua" or name=="cl_zchat.lua" then sources[name]=source end
end
ZCChatModeration=ZCChatModeration or {records={},order={}}
ZCChatModeration.PreviewOnly="76561198011536179"
CompileString(file.Read("zc_chat_moderation_stage/sv_zc_chat_moderation.lua.txt","DATA"),"ModerationPreviewServer",false)()
-- Retain the existing reaction registry and IDs during this map.
if not ZCChatModeration.LiveBridge then
 local original=ZCChatReaction_Register
 assert(isfunction(original))
 ZCChatReaction_Register=function(speaker,recipients)
  local id=original(speaker,recipients)
  ZCChatModeration_Register(id,speaker,recipients)
  return id
 end
 ZCChatModeration.LiveBridge=true
end
local loader=assert(file.Read("zc_chat_moderation_stage/cl_apply.txt","DATA"))
assert(isfunction(CompileString(loader,"ModerationLoader",false)))
local packed = assert(util.Compress(util.TableToJSON({sources = sources, loader = loader})))
local bootstrap = [=[
ZCChatModerationParts={}
net.Receive("ZCChatModerationPayload",function()
 local i,n,len=net.ReadUInt(8),net.ReadUInt(8),net.ReadUInt(16)
 local p=ZCChatModerationParts if not p then return end p[i]=net.ReadData(len)
 for k=1,n do if not p[k] then return end end
 ZCChatModerationParts=nil
 local payload=util.JSONToTable(util.Decompress(table.concat(p)) or "")
 if not payload then return end
 local fn=CompileString(payload.loader,"ZCChatModerationApply",false)
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
                net.Start("ZCChatModerationPayload")
                net.WriteUInt(i, 8) net.WriteUInt(count, 8)
                net.WriteUInt(#chunk, 16) net.WriteData(chunk, #chunk)
                net.Send(ply)
            end)
        end
        print("ZC_CHAT_MODERATION_SENT", ply:UserID(), BUILD)
    end)
end
state.Send = send
hook.Add("PlayerInitialSpawn","ZCChatModerationOwnerRestore",function(ply)
 if ply:SteamID()~="STEAM_0:1:25635225" then return end
 timer.Simple(18,function() if IsValid(ply) then send(ply) end end)
end)
for _,ply in ipairs(player.GetHumans()) do if ply:SteamID()=="STEAM_0:1:25635225" then send(ply) end end
print("ZC_CHAT_MODERATION_PREVIEW_READY",#packed)
