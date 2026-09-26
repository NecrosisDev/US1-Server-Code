local r={time=os.time(),passed=false,tests={},livePlayerTest=false}
local ok,err=xpcall(function()
 local base='zc_sticky_stage_20260919t033648z/'
 local source=assert(file.Read(base..'candidate.lua','LUA'))
 r.hash=util.SHA256(source)
 assert(type(CompileString(source,'sticky_syntax',false))=='function','candidate syntax')
 local phys=FindMetaTable('PhysObj')
 for _,name in ipairs({'GetEntity','SetVelocityInstantaneous','SetAngleVelocityInstantaneous','EnableMotion','GetPos','GetAngles'})do assert(type(phys[name])=='function',name..' unavailable')end
 assert(COLLISION_GROUP_WORLD==20,'collision enum mismatch')
 local original=ZCityPoopThrow
 local tick=timer.Exists('ZCityPoopThrow_Tick')
 local hookCall=hook.Call;local netStart=net.Start
 local suite=CompileString(assert(file.Read(base..'test_sticky_native.lua','LUA')),'sticky_native_fixtures',false)
 assert(type(suite)=='function','test syntax')
 r.tests=suite()(source)
 assert(ZCityPoopThrow==original and original.Version~='20260919.stick2','fixture leaked to live module')
 assert(hook.Call==hookCall and net.Start==netStart and timer.Exists('ZCityPoopThrow_Tick')==tick,'fixture global mutation')
 for _,test in ipairs(r.tests)do assert(test.pass,test.name..': '..tostring(test.error))end
 r.passed=true;r.liveVersion=original.Version;r.liveHash=util.SHA256(assert(file.Read('autorun/server/zc_poop_throw.lua','LUA')))
 r.mass=ZCityPoop and ZCityPoop.Mass;r.urineVersion=ZCityUrine and ZCityUrine.Version
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_sticky_deploy');file.Write('zc_sticky_deploy/preflight_20260919t033648z.json',util.TableToJSON(r,true))
print('ZC_STICKY_PREFLIGHT',r.passed,#r.tests,r.error or '')
