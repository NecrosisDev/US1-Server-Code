local base='zc_priority_20260919t025322z/'
local r={time=os.time(),passed=false,tests={},hashes={}}
local ok,err=xpcall(function()
 local names={'autorun/server/zc_poop.lua','autorun/server/zc_poop_throw.lua','autorun/server/zc_poop_involuntary.lua','autorun/server/zc_urine.lua','autorun/client/zc_urine_visuals.lua','autorun/client/zc_poop_smear.lua'}
 local changed={['autorun/server/zc_poop.lua']=true,['autorun/server/zc_poop_involuntary.lua']=true,['autorun/server/zc_urine.lua']=true}
 local sources={}
 for _,name in ipairs(names) do
  local path=changed[name] and base..name or name
  local text=assert(file.Read(path,'LUA'),'missing '..path);sources[name]=text;r.hashes[name]=util.SHA256(text)
  assert(type(CompileString(text,name,false))=='function','compile failed '..name)
 end
 for i=1,4 do assert(file.Exists('sound/homigrad/blooddrip'..i..'.wav','GAME'),'missing drip asset') end
 local material=util.DecalMaterial('YellowBlood')
 assert(type(material)=='string' and file.Exists('materials/'..material..'.vmt','GAME'),'decal unavailable')
 r.decal=material
 local suite=CompileString(assert(file.Read(base..'test_priority.lua','LUA')),'priority_isolated_tests',false)
 assert(type(suite)=='function')
 local scope=setmetatable({ZCityPoop=false,ZCityPoopThrow=false,ZCityPoopInvoluntary=false,ZCityUrine=false,ZCityUrineVisuals=false,ZCPoopSmearClient=false,ZCityPillCompat=false},{__index=_G})
 scope._G=scope
 scope.loadstring=function(s,n)local f=CompileString(s,n or 'fixture',false);if type(f)=='function' then return f end;return nil,f end
 setfenv(suite,scope);r.tests=suite()(sources)
 for _,t in ipairs(r.tests) do assert(t.pass,t.name..': '..tostring(t.error)) end
 r.passed=true
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_repair_batches');file.Write('zc_repair_batches/preflight_priority_20260919t025322z.json',util.TableToJSON(r,true))
print('ZC_PRIORITY_PREFLIGHT',r.passed,#r.tests,r.error or '')
