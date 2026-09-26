local r={time=os.time(),restored=false}
local ok,err=xpcall(function()
 local original='e098b2375d05b2e7308b2664e10669cd993b2f75d485aff88ce46c5ea9f5a2df'
 assert(util.SHA256(assert(file.Read('autorun/server/zc_poop_throw.lua','LUA')))==original,'restore original disk file first')
 local T=ZCityPoopThrow
 for ent in pairs(ZCityPoop and ZCityPoop.owned or {})do
  if IsValid(ent) then
   if T and T.DetachSticky then T.DetachSticky(ent) end
   ent.ZCPoopStickPending=nil
  end
 end
 hook.Remove('ZB_EndRound','ZCityPoopThrow_StickReset')
 include('autorun/server/zc_poop_throw.lua')
 assert(ZCityPoopThrow.Version=='20260918.h2','restore version mismatch')
 r.restored=true
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_sticky_deploy');file.Write('zc_sticky_deploy/rollback_20260919t033648z.json',util.TableToJSON(r,true))
print('ZC_STICKY_ROLLBACK',r.restored,r.error or '')
