local r={time=os.time(),restored=false}
local ok,err=xpcall(function()
 if ZCityUrine then ZCityUrine.SplashEpoch=(ZCityUrine.SplashEpoch or 0)+1 end
 hook.Remove('ZB_EndRound','ZCityUrine_SplashReset')
 hook.Remove('PostCleanupMap','ZCityUrine_SplashReset')
 include('autorun/server/zc_urine.lua')
 assert(ZCityUrine.Version=='20260918.h2','wrong restored version')
 r.restored=true
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_urine_visual')
file.Write('zc_urine_visual/rollback_20260919t010507z.json',util.TableToJSON(r,true))
print('ZC_URINE_VISUAL_ROLLBACK',r.restored,r.error or '')
