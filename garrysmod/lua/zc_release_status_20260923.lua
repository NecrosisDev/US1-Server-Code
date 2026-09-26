local result={at=os.time(),map=game.GetMap(),chat=ZCChatNativePublicVersion,
 scoreboard=ZCScoreboardServerVersion,observer=ZCObserverServer and ZCObserverServer.Version,
 observerMode=GetConVar("zc_observer_mode") and GetConVar("zc_observer_mode"):GetInt(),
 db=mysql and mysql.module,dbConnected=mysql and mysql.IsConnected and mysql:IsConnected(),
 eprotect=ZCEProtectStartup and ZCEProtectStartup.loaded,
 restart=ZC_RESTART_WARNING and ZC_RESTART_WARNING.Version,
 humans=#player.GetHumans(),bots=#player.GetBots(),viewerParts={}}
for i=1,8 do
 local path=string.format("zc_killcam/viewer_parts/cl_part_%02d.lua",i)
 local source=file.Read(path,"LUA")
 result.viewerParts[i]={present=source~=nil,compressedBytes=source and #util.Compress(source)}
end
file.Write("zc_release_runtime_status.json",util.TableToJSON(result,true))
print("ZC_RELEASE_STATUS_WRITTEN")
