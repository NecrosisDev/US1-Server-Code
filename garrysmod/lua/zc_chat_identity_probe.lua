util.AddNetworkString("ZCChatIdentityProbe")
net.Receive("ZCChatIdentityProbe",function(length,p)
 if length>16000 or p:SteamID64()~="76561198011536179" then return end
 file.Write("zc_chat_identity_probe.json",net.ReadString())
end)
local source=[=[
 local c=hg and hg.chat
 local out={build=ZCChatBuild,media=ZCChatMedia and ZCChatMedia.Version,pending=timer.Exists("ZCChatIdentityApply"),publicPending=timer.Exists("ZCChatGroupPreviewApply"),active=IsValid(c) and c:GetActive(),icons={}}
 for _,name in ipairs({"shield","group_gear","star","medal_gold_1"})do out.icons[name]=not Material("icon16/"..name..".png"):IsError() end
 local cv=GetConVar("zchat_fontaa");out.fontAA=cv and cv:GetBool()
 if IsValid(c) then
  out.rows=#(c.entries or {});out.scrollInstalled=IsValid(c.history) and c.history.ZCRowScrollInstalled or false
  for _,row in ipairs(c.entries or {})do if IsValid(row) and IsValid(row.ZCAvatar) then out.avatar=row.ZCAvatar:GetWide();out.body=row.ZCBubbleBodyHeight;break end end
 end
 net.Start("ZCChatIdentityProbe");net.WriteString(util.TableToJSON(out));net.SendToServer()
]=]
for _,p in ipairs(player.GetHumans())do if p:SteamID64()=="76561198011536179" then p:SendLua(source)end end
