local source=assert(file.Read("zc_killcam/cl_viewer.lua","LUA"))
assert(#source<16000 and isfunction(CompileString(source,"ViewerDeliveryClientPreflight",false)))
for _,p in ipairs(player.GetHumans())do p:SendLua(source)end
include("zc_release_delivery_ack_20260923.lua")
include("zc_release_status_20260923.lua")
print("ZC_REPLAY_DELIVERY_REFRESH_FINAL",#player.GetHumans())
