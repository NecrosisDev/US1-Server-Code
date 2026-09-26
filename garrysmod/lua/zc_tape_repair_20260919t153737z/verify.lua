-- Read-only post-install inspection; no weapon use or entity creation.
local r={time=os.time(),map=game.GetMap(),players=#player.GetHumans(),passed=false,liveActionTest=false}
local ok,err=xpcall(function()
 local source=assert(file.Read('weapons/weapon_ducttape.lua','LUA'));r.hash=util.SHA256(source)
 assert(r.hash=='8bf1e137ac43445c709a93c6990617318f88aaa32303f2ddfec54e78545a4b56','installed source differs')
 local t=assert(weapons.GetStored('weapon_ducttape'));local old=assert(ZCTape153737Check)
 r.version=t.ZCConstraintRepairVersion;r.primary=debug.getinfo(t.PrimaryAttack,'S');r.reloaded=t.PrimaryAttack~=old.oldPrimary
 r.staleInstances=0;r.updatedInstances=0
 for _,e in ipairs(ents.GetAll())do if e:IsWeapon() then
  if e.PrimaryAttack==old.oldPrimary then r.staleInstances=r.staleInstances+1
  elseif e:GetClass()=='weapon_ducttape' and e.PrimaryAttack==t.PrimaryAttack then r.updatedInstances=r.updatedInstances+1 end
 end end
 for i=1,64 do local name,fn=debug.getupvalue(t.PrimaryAttack,i);if not name then break end
  if name=='BindObjects' then r.binding=debug.getinfo(fn,'S')end
 end
 r.observerLeft=(hook.GetTable().Tick or {}).ZCPerfObserve153737~=nil or timer.Exists('ZCPerfObserve153737')
 assert(r.version=='20260919.bind1' and r.reloaded and r.binding,'new binding path not loaded')
 assert(r.staleInstances==0 and not r.observerLeft,'stale instance or observer')
 r.passed=true
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_perf_next');file.Write('zc_perf_next/tape_verify_20260919t153737z.json',util.TableToJSON(r,true))
print('ZC_TAPE_VERIFIED',r.passed,r.error or '')
