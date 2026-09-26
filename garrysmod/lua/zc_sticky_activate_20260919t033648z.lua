local r={time=os.time(),activated=false,livePlayerTest=false}
local ok,err=xpcall(function()
 local pre=util.JSONToTable(assert(file.Read('zc_sticky_deploy/preflight_20260919t033648z.json','DATA')))
 assert(pre.passed and #pre.tests==22,'preflight failed or incomplete')
 assert(util.SHA256(assert(file.Read('autorun/server/zc_poop_throw.lua','LUA')))==pre.hash,'installed hash mismatch')
 local old=ZCityPoopThrow;local stats=old.stats;local grabs=old.grabPending
 local poop,urine=ZCityPoop,ZCityUrine;local hands=weapons.GetStored('weapon_hands_sh').SetCarrying
 r.errorsBefore=stats.errors or 0
 include('autorun/server/zc_poop_throw.lua')
 assert(ZCityPoopThrow==old and old.Version=='20260919.stick2','activation mismatch')
 assert(old.stats==stats and old.grabPending==grabs,'persistent state replaced')
 assert(ZCityPoop==poop and ZCityUrine==urine,'unrelated system replaced')
 assert(weapons.GetStored('weapon_hands_sh').SetCarrying==hands,'native hands modified')
 assert(timer.Exists('ZCityPoopThrow_Tick'),'timer missing')
 assert(math.abs(poop.Mass-3.9003355503082275)<.00001 and urine.Version=='20260919.drips2','priority changes missing')
 r.source=debug.getinfo(old.OnCollide,'S').source
 assert(r.source=='@lua/autorun/server/zc_poop_throw.lua','loaded noncanonical source')
 r.version=old.Version;r.errorsAfter=stats.errors or 0;r.activated=true
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_sticky_deploy');file.Write('zc_sticky_deploy/activation_20260919t033648z.json',util.TableToJSON(r,true))
print('ZC_STICKY_ACTIVATED',r.activated,r.error or '')
