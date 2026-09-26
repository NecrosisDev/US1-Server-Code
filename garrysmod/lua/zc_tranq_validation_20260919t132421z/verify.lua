-- Read-only post-install method and source verification.
local r={time=os.time(),passed=false,players=#player.GetHumans(),map=game.GetMap(),livePlayerTest=false}
local ok,err=xpcall(function()
 local text=assert(file.Read('weapons/weapon_tranquilizer.lua','LUA'))
 r.hash=util.SHA256(text)
 assert(r.hash=='879fa0155b451120110d5a0170c8eab1312441cf35073431a5c2863855dbb9c5','source differs')
 local t=assert(weapons.GetStored('weapon_tranquilizer'));local f=assert(t.Shoot)
 r.method=debug.getinfo(f,'S');r.changedSinceCapture=ZCTranqValidation132421 and f~=ZCTranqValidation132421.old or false
 assert(r.method.source=='@addons/zcity/lua/weapons/weapon_tranquilizer.lua','unexpected runtime source')
 assert(r.method.linedefined==123 and r.method.lastlinedefined==150,'method still has old source span')
 r.staleInstances=0;r.updatedInstances=0
 for _,e in ipairs(ents.GetAll()) do if IsValid(e) and e:GetClass()=='weapon_tranquilizer' then
  if e.Shoot==f then r.updatedInstances=r.updatedInstances+1
  elseif ZCTranqValidation132421 and e.Shoot==ZCTranqValidation132421.old then r.staleInstances=r.staleInstances+1 end
 end end
 assert(r.staleInstances==0,'stale active tranquilizer method')
 r.networkBudgetLinked=ZCTickBudget and ZCTickBudget.entitySender and FindMetaTable('Entity').SendNetVar==ZCTickBudget.entitySender.wrapper or false
 r.fullSyncInstalled=zb.net.fullSync~=nil
 r.passed=true
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_net_validation')
file.Write('zc_net_validation/tranq_verify_20260919t132421z.json',util.TableToJSON(r,true))
print('ZC_TRANQ_VERIFIED',r.passed,r.error or '')
