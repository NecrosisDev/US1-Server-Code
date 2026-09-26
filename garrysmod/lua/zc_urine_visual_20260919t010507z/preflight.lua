local base='zc_urine_visual_20260919t010507z/'
local names={'autorun/server/zc_poop.lua','autorun/server/zc_poop_involuntary.lua','autorun/server/zc_poop_throw.lua','autorun/server/zc_urine.lua','autorun/client/zc_poop_smear.lua','autorun/client/zc_urine_visuals.lua'}
local result={time=os.time(),sources={},passed=false,renderedTest=false}
local ok,err=xpcall(function()
 local sources={}
 for _,name in ipairs(names)do
  local text=assert(file.Read(base..name,'LUA'),'missing staged '..name)
  assert(type(CompileString(text,base..name,false))=='function','syntax error '..name)
  sources[name]=text;result.sources[name]=util.SHA256(text)
 end
 local fn=CompileString(assert(file.Read(base..'test_visual.lua','LUA')),'urine_visual_isolated_tests',false)
 assert(type(fn)=='function','test syntax error')
 local scope=setmetatable({},{__index=_G});scope._G=scope
 for _,name in ipairs({'ZCityPoop','ZCityUrine','ZCityPoopThrow','ZCityPoopInvoluntary','ZCityPoopEat','ZCityPoopOdor','ZCityPillCompat','ZCityUrineVisuals','ZCPoopSmearClient','ZCPoopVisuals'})do scope[name]=false end
 scope.loadstring=function(s,n)local f=CompileString(s,n or 'visual_test',false);if type(f)=='function'then return f end;return nil,f end
 local refs={hook.Add,hook.Call,net.Start,timer.Simple,ZCityUrine}
 setfenv(fn,scope);result.tests=fn()(sources)
 for _,r in ipairs(result.tests)do assert(r.pass,r.name..': '..tostring(r.error))end
 assert(refs[1]==hook.Add and refs[2]==hook.Call and refs[3]==net.Start and refs[4]==timer.Simple and refs[5]==ZCityUrine,'live references changed')
 result.assets={sprite=file.Exists('materials/sprites/physbeam.vtf','GAME'),fallback=file.Exists('materials/color/white.vtf','GAME')}
 assert(result.assets.sprite and result.assets.fallback,'required built-in texture missing')
 result.passed=true
end,debug.traceback)
if not ok then result.error=err end
file.CreateDir('zc_urine_visual')
file.Write('zc_urine_visual/preflight_20260919t010507z.json',util.TableToJSON(result,true))
print('ZC_URINE_VISUAL_PREFLIGHT',result.passed,result.tests and #result.tests or 0,result.error or '')
