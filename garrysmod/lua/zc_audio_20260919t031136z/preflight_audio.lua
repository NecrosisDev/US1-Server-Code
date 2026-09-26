local r={time=os.time(),passed=false,tests={},renderedTest=false}
local ok,err=xpcall(function()
 local src=assert(file.Read('zc_audio_20260919t031136z/candidate.lua','LUA'))
 r.sha256=util.SHA256(src)
 assert(r.sha256=='687475204301976705db49f70cf2fae34fb1302819364706fc5ce6d4ff28451a','candidate hash changed')
 assert(type(CompileString(src,'zc_audio_compile',false))=='function','syntax failure')
 assert(BLOOD_COLOR_YELLOW==1,'unexpected yellow blood enum')
 r.customBloodEffect=file.Exists('effects/bloodspray/init.lua','LUA') or file.Exists('effects/bloodspray.lua','LUA')
 assert(not r.customBloodEffect,'bloodspray override needs an audio review')
 for i=1,4 do assert(file.Exists('sound/homigrad/blooddrip'..i..'.wav','GAME'),'blood-drip audio missing') end
 local sources={['autorun/server/zc_urine.lua']=src}
 for _,p in ipairs({'autorun/server/zc_poop.lua','autorun/server/zc_poop_involuntary.lua','autorun/server/zc_poop_throw.lua','autorun/client/zc_urine_visuals.lua','autorun/client/zc_poop_smear.lua'}) do sources[p]=assert(file.Read(p,'LUA')) end
 local suite=CompileString(assert(file.Read('zc_audio_20260919t031136z/test_audio.lua','LUA')),'zc_audio_tests',false)
 assert(type(suite)=='function','test compilation failed')
 local scope=setmetatable({ZCityPoop=false,ZCityUrine=false,ZCityPoopThrow=false,ZCityPoopInvoluntary=false,ZCPoopSmearClient=false,ZCityUrineVisuals=false},{__index=_G})
 scope._G=scope
 scope.loadstring=function(s,n)local f=CompileString(s,n or 'audio_test',false);if type(f)=='function' then return f end;return nil,f end
 setfenv(suite,scope);r.tests=suite()(sources)
 assert(#r.tests==59,'test suite incomplete')
 for _,t in ipairs(r.tests)do assert(t.pass,t.name..': '..tostring(t.error))end
 r.passed=true
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_audio_repair')
file.Write('zc_audio_repair/preflight_20260919t031136z.json',util.TableToJSON(r,true))
print('ZC_AUDIO_PREFLIGHT',r.passed,#r.tests,r.error or '')
