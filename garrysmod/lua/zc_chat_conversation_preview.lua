-- One-session transport for clients already connected before beta installation.
-- Normal gamemode/AddCSLuaFile loading owns future map changes.
if not SERVER then return end
local BUILD = "20260922.social7f"
util.AddNetworkString("ZCChatConversationPayload")
util.AddNetworkString("ZCChatConversationAck")
ZCChatConversationRollout = ZCChatConversationRollout or {sent = {}, ack = {}}
local state = ZCChatConversationRollout
net.Receive("ZCChatConversationAck", function(length, ply)
    if length > 4096 or not state.sent[ply] then return end
    local ok, detail = net.ReadBool(), net.ReadString()
    if state.ack[ply] then return end
    state.ack[ply] = {ok = ok, detail = detail}
    print("ZC_CHAT_CONVERSATION_ACK", ply:UserID(), ok, detail)
end)
local sources={}
for _,name in ipairs({"client.lua","cl_zchat.lua","sh_chat.lua","cl_chat.lua","ulx_chat.lua"}) do
 local source=assert(file.Read("zc_chat_conversation_stage/"..name..".txt","DATA"))
 assert(isfunction(CompileString(source,"ConversationPreflight/"..name,false)),"compile failed "..name)
 if name~="ulx_chat.lua" then sources[name]=source end
end
local loader=assert(file.Read("zc_chat_conversation_stage/cl_apply.txt","DATA"))
assert(isfunction(CompileString(loader,"ConversationLoader",false)))
-- Recipient-scoped optional reply IDs are backward compatible with old clients.
CompileString(sources["sh_chat.lua"],"ConversationServer",false)()
-- Retain explicit admin chat, free the single @ prefix for public mentions.
assert(ULib and ULib.sayCmds and ULib.removeSayCommand and ULib.addSayCommand,"ULib unavailable")
local old=ULib.sayCmds["@"]
if old then
 ZCChatConversationPreviousAsay=old
 ULib.removeSayCommand("@")
 ULib.addSayCommand("!asay",old.fn,old.access,old.hide,false)
end
assert(not ULib.sayCmds["@"],"admin shortcut still captures mentions")
local packed = assert(util.Compress(util.TableToJSON({sources = sources, loader = loader})))
local bootstrap = [=[
ZCChatConversationParts={}
net.Receive("ZCChatConversationPayload",function()
 local i,n,len=net.ReadUInt(8),net.ReadUInt(8),net.ReadUInt(16)
 local p=ZCChatConversationParts if not p then return end p[i]=net.ReadData(len)
 for k=1,n do if not p[k] then return end end
 ZCChatConversationParts=nil
 local payload=util.JSONToTable(util.Decompress(table.concat(p)) or "")
 if not payload then return end
 local fn=CompileString(payload.loader,"ZCChatConversationApply",false)
 if not isfunction(fn) then ErrorNoHalt(tostring(fn)) return end
 fn()(payload.sources)
end)
]=]
local function send(ply)
    if IsValid(ply) and ply:SteamID64()=="76561198011536179" and file.Exists("zc_chat_pm_preview.lua","LUA") then return end

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
                net.Start("ZCChatConversationPayload")
                net.WriteUInt(i, 8) net.WriteUInt(count, 8)
                net.WriteUInt(#chunk, 16) net.WriteData(chunk, #chunk)
                net.Send(ply)
            end)
        end
        print("ZC_CHAT_CONVERSATION_SENT", ply:UserID(), BUILD)
    end)
end
state.Send = send
-- A stale social6 join refresh must not overwrite this owner's newer preview.
local legacy=hook.GetTable().PlayerInitialSpawn.ZCChatModerationJoinRefresh
if legacy and not ZCChatConversationPreviousJoin then ZCChatConversationPreviousJoin=legacy end
hook.Remove("PlayerInitialSpawn","ZCChatModerationJoinRefresh")
hook.Add("PlayerInitialSpawn","ZCChatConversationJoinRefresh",function(ply)
 if ply:SteamID()=="STEAM_0:1:25635225" then
  timer.Simple(18,function() if IsValid(ply) then send(ply) end end)
 elseif ZCChatConversationPreviousJoin then ZCChatConversationPreviousJoin(ply) end
end)
for _,ply in ipairs(player.GetHumans()) do if ply:SteamID()=="STEAM_0:1:25635225" then send(ply) end end
print("ZC_CHAT_CONVERSATION_PREVIEW_READY",#packed)
