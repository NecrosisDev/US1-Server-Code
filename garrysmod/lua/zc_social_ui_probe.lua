util.AddNetworkString("ZCSocialUIProbe")
net.Receive("ZCSocialUIProbe",function(len,p)
 if len>24000 or p:SteamID()~="STEAM_0:1:25635225" then return end
 print("ZC_SOCIAL_UI_STATE",net.ReadString():sub(1,2900))
end)
for _,p in ipairs(player.GetHumans()) do if p:SteamID()=="STEAM_0:1:25635225" then p:SendLua([=[
local function info(p)
 if not IsValid(p) then return {valid=false} end
 local x,y=p:GetPos() local w,h=p:GetSize()
 return {valid=true,x=x,y=y,w=w,h=h,alpha=p:GetAlpha(),visible=p:IsVisible(),mouse=p:IsMouseInputEnabled()}
end
local function probe()
 local c=hg and hg.chat local m=ZCChatMedia
 local out={build=ZCChatBuild,media=m and m.Version,chat=info(c),picker=info(m and m.Picker),rows={}}
 if IsValid(c) then
  out.active=c:GetActive();out.page=c.phonePage;out.plus=info(c.ZCEmoteButton);out.history=info(c.history)
  for i=math.max(1,#c.entries-5),#c.entries do local r=c.entries[i] if IsValid(r) then
   out.rows[#out.rows+1]={id=r.ZCMessageID,bubble=r.ZCBubble,row=info(r),reaction=info(r.ZCReactionAdd),report=info(r.ZCReportButton),blend=IsValid(r.ZCReactionAdd) and r.ZCReactionAdd.ZCBlend}
  end end
 end
 net.Start("ZCSocialUIProbe") net.WriteString(util.TableToJSON(out)) net.SendToServer()
end
probe()
timer.Create("ZCSocialUIProbeOpen",1,45,function() local c=hg and hg.chat if IsValid(c) and c:GetActive() then probe();timer.Remove("ZCSocialUIProbeOpen") end end)
]=]) end end
