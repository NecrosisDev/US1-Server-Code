local base='zc_waste_admin_collision_20260919t001443z/'
local r={time=os.time(),passed=false,sources={}}
local ok,err=xpcall(function()
 local names={'autorun/server/zc_poop.lua','autorun/server/zc_urine.lua','autorun/server/zc_poop_throw.lua','autorun/server/zc_poop_eat.lua','autorun/server/zc_poop_odor.lua','autorun/server/zc_poop_involuntary.lua','autorun/client/zc_urine_visuals.lua','autorun/client/zc_poop_smear.lua','autorun/client/zc_poop_visuals.lua','zc_poop/content.lua'}
 local sources={}
 for _,name in ipairs(names)do
  local text=assert(file.Read(base..name,'LUA'),'missing '..name)
  assert(type(CompileString(text,base..name,false))=='function','syntax '..name)
  sources[name]=text;r.sources[name]=util.SHA256(text)
 end
 local fn=CompileString(assert(file.Read(base..'test_combined.lua','LUA')),'waste_isolated_tests',false)
 assert(type(fn)=='function',tostring(fn))
 local scope=setmetatable({},{__index=_G});scope._G=scope
 for _,n in ipairs({'ZCityPoop','ZCityUrine','ZCityPoopThrow','ZCityPoopEat','ZCityPoopOdor','ZCityPoopInvoluntary','ZCityPillCompat','ZCityUrineVisuals','ZCPoopSmearClient','ZCPoopVisuals'})do scope[n]=false end
 scope.loadstring=function(s,n)local f=CompileString(s,n or 'test',false);if type(f)=='function'then return f end;return nil,f end
 setfenv(fn,scope);r.tests=fn()(sources)
 for _,t in ipairs(r.tests)do assert(t.pass,t.name..': '..tostring(t.error))end
 assert(#r.tests==95,'unexpected test count')
 r.passed=true
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_waste_admin_collision')
file.Write('zc_waste_admin_collision/preflight.json',util.TableToJSON(r,true))
print('ZCWASTE_ADMIN_COLLISION_PREFLIGHT',r.passed,r.error or '')
