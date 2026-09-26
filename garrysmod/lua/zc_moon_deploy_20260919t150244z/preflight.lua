-- Compile and run isolated map-lifecycle fixtures; never write real gravity.
local base='zc_moon_deploy_20260919t150244z/'
local path='zc_hmcd_mutators/mutators/sv_moon_gravity.lua'
local r={time=os.time(),passed=false,realMapChangeTest=false,gravityBefore=GetConVar('sv_gravity'):GetFloat()}
local physics=physenv.GetGravity();local current=ZC_HMCD_MUTATORS.current
local ok,err=xpcall(function()
 local old=assert(file.Read(path,'LUA'));local code=assert(file.Read(base..'candidate.lua','LUA'))
 r.liveHash=util.SHA256(old);r.candidateHash=util.SHA256(code)
 assert(r.liveHash=='2101320ae29fad0b9411fc19bf60342152005bd969ce8dc6532124dde4d70fce','live source changed')
 assert(r.candidateHash=='757e68e6a366c8f803313cfee4f485dea937d22ddae50d805e2575d9f584b87d','candidate hash mismatch')
 assert(type(CompileString(code,'moon_candidate_parse',false))=='function','candidate syntax')
 local suite=CompileString(assert(file.Read(base..'test_native.lua','LUA')),'moon_native_fixtures',false)
 assert(type(suite)=='function',tostring(suite));r.tests=suite()(old,code)
 for _,t in ipairs(r.tests)do assert(t.pass,t.name..': '..tostring(t.error))end
 assert(GetConVar('sv_gravity'):GetFloat()==r.gravityBefore and physenv.GetGravity()==physics,'live gravity changed in tests')
 assert(ZC_HMCD_MUTATORS.current==current,'live modifier changed in tests')
 r.testsUsedNativeVectorJSON=true;r.passed=true
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_moon_deploy')
file.Write('zc_moon_deploy/preflight_20260919t150244z.json',util.TableToJSON(r,true))
print('ZC_MOON_DEPLOY_PREFLIGHT',r.passed,r.tests and #r.tests or 0,r.error or '')
