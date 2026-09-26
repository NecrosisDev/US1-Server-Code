local state=ZCChatSocialRollout or {ack={}}
local out={build="20260922.social5",map=game.GetMap(),humans=0,applied=0,pending={},failed={}}
for _,p in ipairs(player.GetHumans()) do
 out.humans=out.humans+1
 local a=state.ack[p]
 if a and a.ok and a.detail==out.build then out.applied=out.applied+1
 elseif a and not a.ok then out.failed[#out.failed+1]={id=p:UserID(),detail=a.detail}
 else out.pending[#out.pending+1]=p:UserID() end
end
out.owner_restore_removed=not file.Exists("autorun/server/zc_chat_social_preview_restore.lua","LUA")
out.owner_hook_removed=not ((hook.GetTable().PlayerInitialSpawn or {}).ZCChatSocialOwnerRestore)
file.Write("zc_chat_social_stage/status.json",util.TableToJSON(out,true))
print("ZC_SOCIAL_STATUS",util.TableToJSON(out))
