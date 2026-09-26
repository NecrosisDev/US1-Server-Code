local state = ZCChatBetaRollout or {ack={}}
local result = {build="20260922.polish4", humans=0, applied=0, pending=0, failed={}, map=game.GetMap()}
for _, ply in ipairs(player.GetHumans()) do
    result.humans = result.humans + 1
    local ack = state.ack[ply]
    if ack and ack.ok and ack.detail == result.build then
        result.applied = result.applied + 1
    elseif ack and not ack.ok then
        result.failed[#result.failed+1] = {id=ply:UserID(), detail=ack.detail}
    else result.pending = result.pending + 1 end
end
result.preview_hook_removed = not ((hook.GetTable().PlayerInitialSpawn or {}).ZCChatPolishOwnerRestore)
result.preview_autorun_removed = not file.Exists("autorun/server/zc_chat_polish_preview_restore.lua", "LUA")
file.Write("zc_chat_polish_stage/rollout_status.json", util.TableToJSON(result, true))
print("ZC_POLISH_STATUS " .. util.TableToJSON(result))
