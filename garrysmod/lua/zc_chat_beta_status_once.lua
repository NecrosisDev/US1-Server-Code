if not SERVER then return end
local state=ZCChatBetaRollout or {sent={},ack={}}
local result={humans=0,applied=0,pending=0,failed={},unacknowledged={},build="20260922.beta1",map=game.GetMap()}
for _,ply in ipairs(player.GetHumans()) do
    result.humans=result.humans+1
    local ack=state.ack[ply]
    if ack and ack.ok then result.applied=result.applied+1
    elseif ack then result.failed[#result.failed+1]={id=ply:UserID(),detail=ack.detail}
    else result.pending=result.pending+1 result.unacknowledged[#result.unacknowledged+1]=ply:UserID() end
end
result.server_reactions=isfunction(ZCChatReaction_Register)
result.server_bot_metadata=isfunction(FindMetaTable("Player").zChatPrintMeta)
result.owner_hook_removed=not ((hook.GetTable().PlayerInitialSpawn or {}).ZCChatOwnerPreviewReconnect)
print("ZC_CHAT_BETA_STATUS "..util.TableToJSON(result))
file.CreateDir("zc_chat_beta_stage")
file.Write("zc_chat_beta_stage/rollout_status.json",util.TableToJSON(result,true))
