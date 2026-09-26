local r={time=os.time(),activated=false,renderedTest=false}
local ok,err=xpcall(function()
 local pre=util.JSONToTable(assert(file.Read('zc_audio_repair/preflight_20260919t031136z.json','DATA')))
 assert(pre.passed and #pre.tests==59,'preflight not passed')
 assert(util.SHA256(assert(file.Read('autorun/server/zc_urine.lua','LUA')))==pre.sha256,'installed hash mismatch')
 local u=assert(ZCityUrine);local active,bladder,stats=u.active,u.bladder,u.stats
 r.errorsBefore=stats.errors
 include('autorun/server/zc_urine.lua')
 assert(ZCityUrine==u and u.active==active and u.bladder==bladder and u.stats==stats,'state lost')
 assert(u.Version=='20260919.drips2' and u.StreamSound==nil and u.StopSound==nil,'audio configuration not active')
 local info=debug.getinfo(u.QueueSplash,'S');r.source=info.source
 assert(info.source=='@lua/autorun/server/zc_urine.lua','loaded staged source instead of live')
 assert(timer.Exists('ZCityUrine_Tick') and timer.Exists('ZCityUrine_Bladder'),'timer missing')
 r.version=u.Version;r.errorsAfter=stats.errors;r.activeSessions=table.Count(active)
 r.activated=true
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_audio_repair')
file.Write('zc_audio_repair/activation_20260919t031136z.json',util.TableToJSON(r,true))
print('ZC_AUDIO_ACTIVATED',r.activated,r.error or '')
