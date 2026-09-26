local base='zc_urine_material_20260918t235348z/'
local names={'autorun/server/zc_poop.lua','autorun/server/zc_poop_involuntary.lua','autorun/server/zc_poop_throw.lua','autorun/server/zc_urine.lua','autorun/client/zc_poop_smear.lua','autorun/client/zc_urine_visuals.lua'}
local result={time=os.time(),sources={},passed=false}
local ok,err=xpcall(function()
 local sources={}
 for _,name in ipairs(names)do
  local text=assert(file.Read(name=='autorun/client/zc_urine_visuals.lua' and (base..'zc_urine_visuals.lua') or name,'LUA'),'missing staged '..name)
  local fn=CompileString(text,base..name,false)
  assert(type(fn)=='function',tostring(fn))
  sources[name]=text;result.sources[name]=util.SHA256(text)
 end
 local code=assert(file.Read(base..'test_material.lua','LUA'))
 local fn=CompileString(code,'waste_isolated_tests',false)
 assert(type(fn)=='function',tostring(fn))
 local scope=setmetatable({},{__index=_G});scope._G=scope
 for _,name in ipairs({'ZCityPoop','ZCityUrine','ZCityPoopThrow','ZCityPoopInvoluntary','ZCityPoopEat','ZCityPoopOdor','ZCityPillCompat','ZCityUrineVisuals','ZCPoopSmearClient','ZCPoopVisuals'})do scope[name]=false end
 scope.loadstring=function(s,name)local f=CompileString(s,name or 'waste_test',false);if type(f)=='function'then return f end;return nil,f end
 setfenv(fn,scope)
 result.tests=fn()(sources)
 for _,r in ipairs(result.tests)do assert(r.pass,r.name..': '..tostring(r.error))end
 result.assets={correct=file.Exists('materials/sprites/physbeam.vtf','GAME'),incorrect=file.Exists('materials/cable/physbeam.vtf','GAME'),fallback=file.Exists('materials/color/white.vtf','GAME')}
 result.passed=true
end,debug.traceback)
if not ok then result.error=err end
file.CreateDir('zc_waste_hardening')
file.Write('zc_waste_hardening/material_preflight_20260918t235348z.json',util.TableToJSON(result,true))
print('ZCWASTE_PREFLIGHT',result.passed,result.tests and #result.tests or 0)
