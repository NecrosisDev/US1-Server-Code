local r={time=os.time(),activated=false,livePlayerTest=false}
local ok,err=xpcall(function()
 local pre=util.JSONToTable(assert(file.Read('zc_crawler_native/preflight_native2_20260919t004322z.json','DATA')))
 assert(pre.passed and #pre.tests==20,'preflight missing or failed')
 assert(util.SHA256(assert(file.Read('autorun/server/zc_make_crawler.lua','LUA')))==pre.candidateSHA256,'installed adapter hash differs')
 assert(util.SHA256(assert(file.Read('autorun/z_podgruz.lua','LUA')))==pre.goreSHA256,'native gore changed')
 local native=assert(hg.ZCityGore_AmputateTorso)
 local nativeHooks={}
 for event,entries in pairs(hook.GetTable()) do
  for id,f in pairs(entries) do if tostring(id):find('ZCity Gore V2',1,true) then nativeHooks[#nativeHooks+1]={event,id,f} end end
 end
 local old=ZCMakeCrawler
 include('autorun/server/zc_make_crawler.lua')
 assert(ZCMakeCrawler==old and ZCMakeCrawler.Version=='20260919.native2','adapter not active')
 assert(hg.ZCityGore_AmputateTorso==native,'native API replaced')
 for _,v in ipairs(nativeHooks) do assert(hook.GetTable()[v[1]][v[2]]==v[3],'native hook changed '..v[2]) end
 r.nativeHooksUnchanged=#nativeHooks;r.nativeAPIUnchanged=true
 r.version=ZCMakeCrawler.Version;r.stats=table.Copy(ZCMakeCrawler.stats);r.activated=true
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_crawler_native')
file.Write('zc_crawler_native/activation_native2_20260919t004322z.json',util.TableToJSON(r,true))
print('ZC_CRAWLER_NATIVE_ACTIVATION',r.activated,r.error or '')
