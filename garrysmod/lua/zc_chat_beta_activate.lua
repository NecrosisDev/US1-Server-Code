if not SERVER then return end
hook.Remove("PlayerInitialSpawn","ZCChatOwnerPreviewReconnect")
include("autorun/server/sv_zc_chat_reaction.lua")
include("homigrad/zchat/sh_chat.lua")
include("zc_bots/sv_chatter.lua")
assert(isfunction(ZCChatReaction_Register),"reaction registry missing")
assert(isfunction(FindMetaTable("Player").zChatPrintMeta),"bot metadata missing")
include("zc_chat_beta_rollout.lua")
for _,ply in ipairs(player.GetHumans()) do
    if ply:SteamID()=="STEAM_0:1:25635225" then ZCChatBetaRollout.Send(ply) end
end
print("ZC_CHAT_BETA_SERVER_ACTIVE")
