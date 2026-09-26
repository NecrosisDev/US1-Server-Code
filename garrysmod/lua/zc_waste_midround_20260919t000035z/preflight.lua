local base='zc_waste_midround_20260919t000035z/'
local names={'autorun/server/zc_poop.lua','autorun/server/zc_poop_involuntary.lua','autorun/server/zc_poop_throw.lua','autorun/server/zc_poop_eat.lua','autorun/server/zc_poop_odor.lua','autorun/server/zc_urine.lua','autorun/client/zc_poop_smear.lua','autorun/client/zc_urine_visuals.lua'}
local r={time=os.time(),passed=false,sources={}}
local ok,err=xpcall(function()
 local sources={}
 for _,name in ipairs(names)do
  local text=assert(file.Read(base..name,'LUA'));local fn=CompileString(text,base..name,false)
  assert(type(fn)=='function',tostring(fn));sources[name]=text;r.sources[name]=util.SHA256(text)
 end
 local fn=CompileString(assert(file.Read(base..'test_midround.lua','LUA')),'midround_isolated_tests',false)
 assert(type(fn)=='function',tostring(fn))
 local scope=setmetatable({},{__index=_G});scope._G=scope
 for _,n in ipairs({'ZCityPoop','ZCityUrine','ZCityPoopThrow','ZCityPoopInvoluntary','ZCityPoopEat','ZCityPoopOdor','ZCityPillCompat','ZCityUrineVisuals','ZCPoopSmearClient','ZCPoopVisuals','OverrideSpawn'})do scope[n]=false end
 scope.loadstring=function(s,name)local f=CompileString(s,name or 'midround_test',false);if type(f)=='function'then return f end;return nil,f end
 setfenv(fn,scope);r.tests=fn()(sources)
 for _,t in ipairs(r.tests)do assert(t.pass,t.name..': '..tostring(t.error))end
 r.passed=true
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_waste_midround')
file.Write('zc_waste_midround/preflight_20260919t000035z.json',util.TableToJSON(r,true))
print('ZCWASTE_MIDROUND_PREFLIGHT',r.passed,r.tests and #r.tests or 0)
