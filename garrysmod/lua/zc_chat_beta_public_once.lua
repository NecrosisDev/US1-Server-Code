if not SERVER or not ZCChatBetaRollout then return end
local count=0
for _,ply in ipairs(player.GetHumans()) do
    local ack=ZCChatBetaRollout.ack[ply]
    if not ack or not ack.ok then
        count=count+1
        timer.Simple((count-1)*2,function()
            if IsValid(ply) then ZCChatBetaRollout.Send(ply) end
        end)
    end
end
print("ZC_CHAT_BETA_PUBLIC_QUEUED",count)
