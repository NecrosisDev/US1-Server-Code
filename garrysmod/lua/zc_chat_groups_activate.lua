local fn=CompileString(assert(file.Read("zc_chat_groups_preview.lua","LUA")),"PMPreviewActivation",false)
local result={compiled=isfunction(fn)}
if result.compiled then result.ok,result.error=pcall(fn) else result.error=tostring(fn) end
result.ownerOnline=false
for _,p in ipairs(player.GetHumans()) do if p:SteamID64()=="76561198011536179" then result.ownerOnline=true;result.ownerUserID=p:UserID() end end
file.Write("zc_chat_groups_activation.json",util.TableToJSON(result,true))
print("ZC_GROUP_ACTIVATION",result.ok,result.error or "ok")
