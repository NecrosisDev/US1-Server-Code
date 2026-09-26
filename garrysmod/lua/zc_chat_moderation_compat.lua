local source=assert(file.Read("zc_chat_moderation_stage/cl_compat.txt","DATA"))
assert(isfunction(CompileString(source,"ModerationCompat",false)))
local function send(p) if IsValid(p) and not p:IsBot() then p:SendLua(source) end end
for _,p in ipairs(player.GetHumans()) do send(p) end
hook.Add("PlayerInitialSpawn","ZCChatModerationCompat",function(p) timer.Simple(10,function() send(p) end) end)
print("ZC_MODERATION_COMPAT_SENT",#player.GetHumans())
