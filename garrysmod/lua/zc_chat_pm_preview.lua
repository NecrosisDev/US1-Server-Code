-- Owner-only GoobOS PM preview. Restored after the previous chat preview on joins/maps.
if not SERVER then return end
local BUILD = "20260922.pm1"
util.AddNetworkString("ZCChatPMPreviewPayload")
util.AddNetworkString("ZCChatPMPreviewAck")
ZCChatPMPreviewRollout = ZCChatPMPreviewRollout or {sent = {}, ack = {}}
local state = ZCChatPMPreviewRollout
net.Receive("ZCChatPMPreviewAck", function(length, ply)
    if length > 4096 or not state.sent[ply] then return end
    local ok, detail = net.ReadBool(), net.ReadString()
    if state.ack[ply] then return end
    state.ack[ply] = {ok = ok, detail = detail}
    print("ZC_PM_PREVIEW_ACK", ply:UserID(), ok, detail)
    local receipt={build=BUILD,clients={}}
    for p,a in pairs(state.ack) do if IsValid(p) then receipt.clients[p:SteamID64()]={ok=a.ok,detail=a.detail} end end
    file.Write("zc_chat_pm_ack.json",util.TableToJSON(receipt,true))
end)
local allowed = {["76561198011536179"]=true}
state.Owns=function(ply)return IsValid(ply) and allowed[ply:SteamID64()]==true end
local sources, compiled = {}, {}
for _,name in ipairs({"threads.lua","client.lua","cl_zchat.lua","sh_chat.lua","cl_chat.lua","sv_zc_chat_pm.lua"}) do
 local source=assert(file.Read("zc_chat_pm_stage/"..name..".txt","DATA"),name)
 if name=="sv_zc_chat_pm.lua" then source=source:gsub('AddCSLuaFile%("zc_chat_media/threads.lua"%)','') end
 compiled[name]=CompileString(source,"PMPreview/"..name,false)
 assert(isfunction(compiled[name]),tostring(compiled[name]))
 if name~="sv_zc_chat_pm.lua" then sources[name]=source end
end
local loader=assert(file.Read("zc_chat_pm_stage/cl_apply.lua.txt","DATA"))
assert(isfunction(CompileString(loader,"PMPreviewLoader",false)))
assert(isfunction(utf8.len) and ZCChatModeration and ZCChatReaction_Register,"PM dependencies missing")
assert(ULib and ULib.cmds and ULib.cmds.translatedCmds["ulx psay"],"ULX private command unavailable")
compiled["sv_zc_chat_pm.lua"]()
ZCChatPM.Preview=allowed
compiled["sh_chat.lua"]()
-- Preserve the registered command object, access flags and argument validation.
ZCChatPM.LegacyPsay=ZCChatPM.LegacyPsay or ULib.cmds.translatedCmds["ulx psay"].fn
local function psay(caller,target,message)
 if state.Owns(caller) then return ZCChatPM.Send(caller,target,message,0,0) end
 return ZCChatPM.LegacyPsay(caller,target,message)
end
ULib.cmds.translatedCmds["ulx psay"].fn=psay
ulx.psay=psay
local packed = assert(util.Compress(util.TableToJSON({sources = sources, loader = loader})))
local bootstrap = [=[
timer.Remove("ZCChatConversationApply")
ZCChatPMPreviewParts={}
net.Receive("ZCChatPMPreviewPayload",function()
 local i,n,len=net.ReadUInt(8),net.ReadUInt(8),net.ReadUInt(16)
 local p=ZCChatPMPreviewParts if not p then return end p[i]=net.ReadData(len)
 for k=1,n do if not p[k] then return end end
 ZCChatPMPreviewParts=nil
 local payload=util.JSONToTable(util.Decompress(table.concat(p)) or "")
 if not payload then return end
 local fn=CompileString(payload.loader,"ZCChatPMPreviewApply",false)
 if not isfunction(fn) then ErrorNoHalt(tostring(fn)) return end
 fn()(payload.sources)
end)
]=]
local function send(ply)
    if IsValid(ply) and ply:SteamID64()=="76561198011536179" and file.Exists("zc_chat_groups_preview.lua","LUA") then return end

    if not state.Owns(ply) or ply:IsBot() then return end
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
                net.Start("ZCChatPMPreviewPayload")
                net.WriteUInt(i, 8) net.WriteUInt(count, 8)
                net.WriteUInt(#chunk, 16) net.WriteData(chunk, #chunk)
                net.Send(ply)
            end)
        end
        print("ZC_PM_PREVIEW_SENT", ply:UserID(), BUILD)
    end)
end
state.Send = send
local previous=hook.GetTable().PlayerInitialSpawn.ZCChatConversationJoinRefresh
if previous and not state.PreviousJoin then state.PreviousJoin=previous end
hook.Remove("PlayerInitialSpawn","ZCChatConversationJoinRefresh")
hook.Add("PlayerInitialSpawn","ZCChatPMPreviewJoinRefresh",function(ply)
 if state.Owns(ply) then timer.Simple(18,function()if IsValid(ply) then send(ply)end end)
 elseif state.PreviousJoin then state.PreviousJoin(ply) end
end)
for _,ply in ipairs(player.GetHumans()) do if state.Owns(ply) then send(ply) end end
hook.Add("PlayerDisconnected", "ZCChatPMPreviewRolloutCleanup", function(ply)
    state.sent[ply], state.ack[ply] = nil, nil
end)
print("ZC_PM_PREVIEW_TRANSPORT_READY", #packed)
