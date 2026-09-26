local r={time=os.time(),activated=false,renderedTest=false,behavioralTestsRun=false}
local ok,err=xpcall(function()
 local pre=util.JSONToTable(assert(file.Read('zc_fart_puff/preflight_20260919t012630z.json','DATA')))
 assert(pre.passed,'preflight failed')
 assert(util.SHA256(assert(file.Read('autorun/zc_fart_puff.lua','LUA')))==pre.hash,'installed hash mismatch')
 local hookCall,hookAdd,netStart,includeRef=hook.Call,hook.Add,net.Start,include
 local urine,poop,crawler=ZCityUrine,ZCityPoop,ZCMakeCrawler
 include('autorun/zc_fart_puff.lua')
 assert(ZCFartPuff and ZCFartPuff.Version=='20260919.puff1','module not active')
 assert(hook.GetTable().EntityEmitSound.ZCFartPuff_Sound==ZCFartPuff.OnSound,'sound observer missing')
 assert(hook.Call==hookCall and hook.Add==hookAdd and net.Start==netStart and include==includeRef,'dispatcher replaced')
 assert(ZCityUrine==urine and ZCityPoop==poop and ZCMakeCrawler==crawler,'unrelated module changed')
 r.version=ZCFartPuff.Version;r.activated=true;r.hash=pre.hash
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_fart_puff')
file.Write('zc_fart_puff/activation_20260919t012630z.json',util.TableToJSON(r,true))
print('ZCFART_ACTIVATION',r.activated,r.error or '')
