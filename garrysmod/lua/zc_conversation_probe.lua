util.AddNetworkString("ZCConversationProbe")
net.Receive("ZCConversationProbe",function(bits,ply)
 if ply:SteamID()~="STEAM_0:1:25635225" or bits>32000 then return end
 local result=util.JSONToTable(net.ReadString())
 if not istable(result) then return end
 file.Write("zc_chat_conversation_stage/probe.json",util.TableToJSON(result,true))
end)
local source=[=[
local c=hg and hg.chat
local out={build=ZCChatBuild,media=ZCChatMedia and ZCChatMedia.Version,valid=IsValid(c),rows={}}
if IsValid(c) then
 out.count=#c.entries;out.active=c:GetActive();out.page=c.phonePage;out.reply=c.ZCReplyID
 for i=math.max(1,#c.entries-8),#c.entries do
  local r=c.entries[i]
  if IsValid(r) then out.rows[#out.rows+1]={id=r.ZCMessageID,reply=r.ZCReplyID,grouped=r.ZCGrouped,avatar=IsValid(r.ZCAvatar) and r.ZCAvatar:IsVisible(),gap=r.ZCTopGap,width=r:GetWide(),height=r:GetTall(),bubble=r.ZCBubbleWidth,chain=r.ZCChainKey,quote=IsValid(r.ZCQuote),deadHeader=r.ZCSourceElements and r.ZCSourceElements[2]==":skull: ",speakerAt4=r.ZCSourceElements and r.ZCSourceElements[4]==r.ZCSpeaker,
 skull=r.text and r.text:find(ZCChatMedia.Format(":skull:",18),1,true)~=nil,
 headerMatch=r.text and r.text:find("<color=255,0,0>"..ZCChatMedia.Format(":skull: ",18),1,true)~=nil} end
 end
end
net.Start("ZCConversationProbe");net.WriteString(util.TableToJSON(out));net.SendToServer()
]=]
for _,p in ipairs(player.GetHumans()) do if p:SteamID()=="STEAM_0:1:25635225" then p:SendLua(source) end end
local state=ZCChatConversationRollout
local server={map=game.GetMap(),humans=#player.GetHumans(),aliasRemoved=ULib.sayCmds["@"]==nil,explicitAdmin=ULib.sayCmds["!asay "]~=nil,acks={}}
for p,a in pairs(state and state.ack or {}) do if IsValid(p) then server.acks[tostring(p:UserID())]=a end end
file.Write("zc_chat_conversation_stage/server.json",util.TableToJSON(server,true))
