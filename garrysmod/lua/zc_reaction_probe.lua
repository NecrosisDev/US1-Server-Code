util.AddNetworkString("ZCReactionProbe")
net.Receive("ZCReactionProbe", function(len, ply)
 if len>16384 or ply:SteamID()~="STEAM_0:1:25635225" then return end
 print("ZC_REACTION_CLIENT",net.ReadString():sub(1,1800))
end)
print("ZC_REACTION_SERVER",isfunction(ZCChatReaction_Register),isfunction(net.Receivers.zcchatreact))
for _,p in ipairs(player.GetHumans()) do if p:SteamID()=="STEAM_0:1:25635225" then p:SendLua([=[
local c=hg and hg.chat local out={build=ZCChatBuild,active=IsValid(c) and c:GetActive(),rows={}}
if IsValid(c) then for i=math.max(1,#c.entries-7),#c.entries do local r=c.entries[i] if IsValid(r) then out.rows[#out.rows+1]={id=r.ZCMessageID,bubble=r.ZCBubble,button=IsValid(r.ZCReactionAdd),visible=IsValid(r.ZCReactionAdd) and r.ZCReactionAdd:IsVisible(),media=r.ZCHasInlineMedia} end end end
net.Start("ZCReactionProbe") net.WriteString(util.TableToJSON(out)) net.SendToServer()
]=]) end end
