-- Read-only runtime verification. Does not call the transformation on anyone.
local r={time=os.time(),passed=false,livePlayerTest=false,players=#player.GetAll(),map=game.GetMap()}
local ok,err=xpcall(function()
 local M=assert(ZCMakeCrawler,'button module missing')
 assert(M.Version=='20260919.native2','wrong active button version')
 assert(M.Stabilize==M.RetiredStabilize and M.SyncOrganism==nil,'legacy physiology still active')
 for _,v in ipairs({{'Fake','ZCMakeCrawler_FlagRagdoll'},{'PostPlayerDeath','ZCMakeCrawler_DeathRagdoll'},{'PlayerSpawn','ZCMakeCrawler_Reset'},{'PlayerInitialSpawn','ZCMakeCrawler_Client'}}) do
  assert(not (hook.GetTable()[v[1]] or {})[v[2]],'legacy hook remains '..v[2])
 end
 for _,p in player.Iterator() do
  assert(not timer.Exists('ZCMakeCrawler_Stabilize_'..p:EntIndex()),'legacy stabilization timer remains')
 end
 local handler=assert(net.Receivers['zcmakecrawler_apply'],'button receiver missing')
 local linked=false
 for i=1,40 do local name,value=debug.getupvalue(handler,i);if not name then break end;if value==M then linked=true;break end end
 assert(linked,'button receiver does not use active module')
 assert(hg and isfunction(hg.ZCityGore_AmputateTorso),'native torso routine missing')
 r.receiver=debug.getinfo(handler,'S');r.apply=debug.getinfo(M.Apply,'S')
 r.native=debug.getinfo(hg.ZCityGore_AmputateTorso,'S')
 r.goreSHA256=util.SHA256(assert(file.Read('autorun/z_podgruz.lua','LUA')))
 r.adapterSHA256=util.SHA256(assert(file.Read('autorun/server/zc_make_crawler.lua','LUA')))
 r.version=M.Version;r.stats=table.Copy(M.stats);r.legacyRemoved=true;r.receiverLinked=true;r.passed=true
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_crawler_native')
file.Write('zc_crawler_native/verified_native2_20260919t004322z.json',util.TableToJSON(r,true))
print('ZC_CRAWLER_NATIVE_VERIFIED',r.passed,r.error or '')
