local s=ZCChatGroupPreviewRollout or {}
local r={build=s.Build,public=s.Public==true,halted=s.Halted==true,total=0,ack=0,pmReady=0,groupReady=0,pending={},failed={},previewRestricted=ZCChatGroups.Preview~=nil or ZCChatPM.Preview~=nil}
for _,p in ipairs(player.GetHumans())do
 r.total=r.total+1
 if ZCChatPM.ready[p]then r.pmReady=r.pmReady+1 end
 if ZCChatGroups.ready[p]then r.groupReady=r.groupReady+1 end
 local a=s.ack and s.ack[p]
 if a and a.ok and isstring(a.detail) and a.detail:find("20260923.identity2",1,true)==1 then r.ack=r.ack+1
 elseif a and not a.ok then r.failed[#r.failed+1]={user=p:UserID(),detail=a.detail}
 else r.pending[#r.pending+1]={user=p:UserID(),sent=s.sent and s.sent[p] or false}end
end
file.Write("zc_chat_identity_public_status.json",util.TableToJSON(r,true))
