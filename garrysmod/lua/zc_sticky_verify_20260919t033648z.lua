local r={time=os.time(),passed=false,livePlayerTest=false}
local ok,err=xpcall(function()
 local T=assert(ZCityPoopThrow);r.version=T.Version;r.stats=table.Copy(T.stats)
 assert(T.Version=='20260919.stick2','wrong active version')
 r.hash=util.SHA256(assert(file.Read('autorun/server/zc_poop_throw.lua','LUA')))
 local pre=util.JSONToTable(assert(file.Read('zc_sticky_deploy/preflight_20260919t033648z.json','DATA')))
 assert(r.hash==pre.hash,'file differs from tested candidate')
 r.functions={}
 for _,name in ipairs({'OnCollide','QueueStick','StickPose','Step','Tick','ArmGrab','DetachSticky'})do
  r.functions[name]=debug.getinfo(T[name],'S').source
  assert(r.functions[name]=='@lua/autorun/server/zc_poop_throw.lua','wrong source '..name)
 end
 assert(timer.Exists('ZCityPoopThrow_Tick'),'timer missing')
 r.mass=ZCityPoop.Mass;r.urineVersion=ZCityUrine.Version;r.poops=0;r.stuck=0;r.masses={}
 for ent in pairs(ZCityPoop.owned)do if IsValid(ent)then
  r.poops=r.poops+1;if ent.ZCPoopSticky then r.stuck=r.stuck+1 end
  local phys=ent:GetPhysicsObject();if IsValid(phys)then r.masses[#r.masses+1]=phys:GetMass() end
 end end
 r.players=#player.GetHumans();r.map=game.GetMap();r.passed=true
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_sticky_deploy');file.Write('zc_sticky_deploy/verify_20260919t033648z.json',util.TableToJSON(r,true))
print('ZC_STICKY_VERIFIED',r.passed,r.version,r.error or '')
