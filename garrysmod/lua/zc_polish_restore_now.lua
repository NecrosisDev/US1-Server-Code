include("autorun/server/zc_chat_polish_preview_restore.lua")
include("zc_chat_polish_preview.lua")
print("ZC_POLISH_PERSISTENCE_ACTIVE", isfunction((hook.GetTable().PlayerInitialSpawn or {}).ZCChatPolishOwnerRestore))
