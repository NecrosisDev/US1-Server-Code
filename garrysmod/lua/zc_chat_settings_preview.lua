if not SERVER then return end
return function(activate)
local DATA="zc_chat_settings_20260923t012302z"
local hashes={ ["apps.lua"]="413bcb1628fbc0e67f27925d42ff7225bae284dbca23e91115e4378dd4f43b0f",
 ["phone_preferences.lua"]="3d5b235744d0e0ae95231171ca4f8addb66e0fdd25d792ca32aa329acd70352c",
 ["settings.lua"]="3126b9624797c23066169373eb1687662930cf2243905b5580f9ea1dfd00c392",
 ["threads.lua"]="7ca0d03308bf83332623a13e100a7d133b227cf5e7fc8687d1a540ca2f82d281",
 ["groups.lua"]="56c79a4ad2daca9c5dd476d7b1a64d468e8c0382f14b53927821749d5c8e71e9",
 ["client.lua"]="cc105f95db78bea36f7a47ce18dde110e93217bf47368a9c31517f26eb775b72",
 ["cl_zchat.lua"]="5534358a324f3a220bbf023b52ef37b7c70f7ce01e421e29a63aad4d1dacae94",
 ["sh_chat.lua"]="1bcc1e90151aa98acd11a7da9e8db698f6f6459e22b69411db71cb616e2dd715",
 ["cl_chat.lua"]="9c43307a6daf7827a184cba005fa589ddad79620dba2b7da95626e1a71b9c27c",
 ["cl_apply.lua"]="c7ee4a3ab6f6729bb5c95f5f57927e46aaace76e5cebb070124d5c8ab15f379a"}
local baseline={ ["zc_chat_media/client.lua"]="bda3a02aac9e5a0a43d5facc5ed988a31f530f03e59253d4cc6efb4241d45069",
 ["homigrad/zchat/derma/cl_zchat.lua"]="4d2274bee3a442c6c0b3ea18b6b41e252df667ab64d2dc8924f3669c000a3898",
 ["homigrad/zchat/sh_chat.lua"]="10b15e16ec856ac3ea1aadf46fdb543ea02220e33d970feb532199a4a1d90a36",
 ["homigrad/cl_chat.lua"]="9c43307a6daf7827a184cba005fa589ddad79620dba2b7da95626e1a71b9c27c",
 ["zc_chat_media/threads.lua"]="ae704da5211364ece8472682a967a8125a1e3a8f0dcd9057aa6d2fddcbca739d",
 ["zc_chat_media/groups.lua"]="56c79a4ad2daca9c5dd476d7b1a64d468e8c0382f14b53927821749d5c8e71e9"}
local sources={}
local receipt={ok=true,build="20260923.settings2",compiled={},humans=#player.GetHumans()}
for path,sha in pairs(baseline)do assert(util.SHA256(file.Read(path,"LUA") or "")==sha,"Native chat source changed: "..path)end
for name,sha in pairs(hashes)do
 local source=assert(file.Read(DATA.."/"..name..".txt","DATA"))
 assert(util.SHA256(source)==sha,"Candidate changed: "..name)
 local fn=CompileString(source,"ChatIdentity/"..name,false)
 assert(isfunction(fn),tostring(fn));receipt.compiled[#receipt.compiled+1]=name;sources[name]=source
end
for _,p in ipairs(player.GetHumans())do if p:SteamID64()=="76561198011536179" then receipt.owner={userid=p:UserID(),rank=p:GetUserGroup(),seconds=p:GetNWInt("ZCPlaytimeTotal",-1)} end end
file.Write("zc_chat_settings_preflight.json",util.TableToJSON(receipt,true))
if not activate then print("ZC_SETTINGS_PREFLIGHT_OK")return end
util.AddNetworkString("ZCChatSettingsPayload");util.AddNetworkString("ZCChatSettingsAck")
local state={sent={},ack={}};ZCChatSettingsPreview=state
net.Receive("ZCChatSettingsAck",function(length,p)
 if length>4096 or not state.sent[p] or p:SteamID64()~="76561198011536179" then return end
 local ok,detail=net.ReadBool(),net.ReadString()
 state.ack[p]={ok=ok,detail=detail}
 file.Write("zc_chat_settings_ack.json",util.TableToJSON({ok=ok,detail=detail,userid=p:UserID()},true))
 print("ZC_SETTINGS_ACK",p:UserID(),ok,detail)
end)
local loader=sources["cl_apply.lua"];sources["cl_apply.lua"]=nil
local packed=assert(util.Compress(util.TableToJSON({sources=sources,loader=loader})))
local bootstrap=[=[
ZCChatSettingsParts={}
net.Receive("ZCChatSettingsPayload",function()
 local i,n,len=net.ReadUInt(8),net.ReadUInt(8),net.ReadUInt(16)
 local parts=ZCChatSettingsParts;if not parts then return end;parts[i]=net.ReadData(len)
 for k=1,n do if not parts[k] then return end end
 ZCChatSettingsParts=nil
 local payload=util.JSONToTable(util.Decompress(table.concat(parts)) or "")
 if not payload then return end
 local fn=CompileString(payload.loader,"ChatIdentityApply",false)
 if not isfunction(fn)then ErrorNoHalt(tostring(fn))return end
 fn()(payload.sources)
end)
]=]
local function send(p)
 if not IsValid(p) or p:SteamID64()~="76561198011536179" then return end
 state.sent[p]=true;p:SendLua(bootstrap)
 timer.Simple(1,function()
  if not IsValid(p)then return end
  local count=math.ceil(#packed/8192)
  for i=1,count do
   local chunk=packed:sub((i-1)*8192+1,i*8192)
   timer.Simple((i-1)*0.3,function()
    if not IsValid(p)then return end
    net.Start("ZCChatSettingsPayload");net.WriteUInt(i,8);net.WriteUInt(count,8);net.WriteUInt(#chunk,16);net.WriteData(chunk,#chunk);net.Send(p)
   end)
  end
 end)
end
state.Send=send
hook.Add("PlayerInitialSpawn","ZCChatSettingsPreviewJoin",function(p)timer.Simple(32,function()send(p)end)end)
hook.Add("PlayerDisconnected","ZCChatSettingsPreviewCleanup",function(p)state.sent[p]=nil;state.ack[p]=nil end)
for _,p in ipairs(player.GetHumans())do send(p)end
print("ZC_SETTINGS_OWNER_PREVIEW_QUEUED")
end
