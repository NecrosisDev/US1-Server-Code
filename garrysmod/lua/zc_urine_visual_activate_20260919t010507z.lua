local r={time=os.time(),activated=false,renderedTest=false}
local ok,err=xpcall(function()
 local pre=util.JSONToTable(assert(file.Read('zc_urine_visual/preflight_20260919t010507z.json','DATA')))
 assert(pre.passed and #pre.tests==47,'preflight missing')
 for _,path in ipairs({'autorun/server/zc_urine.lua','autorun/client/zc_urine_visuals.lua'})do
  assert(util.SHA256(assert(file.Read(path,'LUA')))==pre.sources[path],'installed hash mismatch '..path)
 end
 local old=assert(ZCityUrine);local active,bladder,stats=old.active,old.bladder,old.stats
 r.errorsBefore=old.stats.errors or 0
 include('autorun/server/zc_urine.lua')
 local u=assert(ZCityUrine)
 assert(u==old and u.active==active and u.bladder==bladder and u.stats==stats,'persistent state replaced')
 assert(u.Version=='20260919.visual1' and u.ClientVersion==4,'incorrect active version')
 assert(type(u.QueueSplash)=='function','collision splash missing')
 assert(timer.Exists('ZCityUrine_Tick') and timer.Exists('ZCityUrine_Bladder'),'timer missing')
 assert(hook.GetTable().PostCleanupMap.ZCityUrine_SplashReset,'splash cleanup missing')
 r.version=u.Version;r.clientVersion=u.ClientVersion;r.errorsAfter=u.stats.errors or 0
 r.activeSessions=table.Count(u.active);r.bladderStatePreserved=true;r.activated=true
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_urine_visual')
file.Write('zc_urine_visual/activation_20260919t010507z.json',util.TableToJSON(r,true))
print('ZC_URINE_VISUAL_ACTIVATION',r.activated,r.error or '')
