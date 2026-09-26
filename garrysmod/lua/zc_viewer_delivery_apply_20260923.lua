include("autorun/server/zc_killcam_viewer_delivery.lua")
local source=assert(file.Read("zc_killcam/cl_viewer.lua","LUA"))
assert(#source<16000 and isfunction(CompileString(source,"ViewerDeliveryClientPreflight",false)))
for _,p in ipairs(player.GetHumans())do p:SendLua(source) end
print("ZC_REPLAY_DELIVERY_REFRESH",#player.GetHumans())
