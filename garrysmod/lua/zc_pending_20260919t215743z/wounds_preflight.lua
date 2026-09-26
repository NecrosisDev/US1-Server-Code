-- Isolated source tests; no live medical, network or player actions.
local r={time=os.time(),passed=false,tests={},liveActions=false}
local path='homigrad/organism/tier_1/modules/sv_blood.lua'
local ok,err=xpcall(function()
 local before=assert(file.Read(path,'LUA'))
 local after=assert(file.Read('zc_pending_20260919t215743z/wounds_candidate.lua','LUA'))
 r.before=util.SHA256(before);r.candidate=util.SHA256(after)
 assert(r.before=='01c885c465e54d881acaee9df51b90b07cab21352065af5508ed6027fb0b6fed','live source changed')
 assert(r.candidate=='7358d0fa13baf87fcd071eb17dc6c94fe62801d4fc87bd1a948d86ea3d26e028','candidate changed')
 assert(isfunction(CompileString(after,path,false)),'native compilation failed')
 local f=CompileString(assert(file.Read('zc_pending_20260919t215743z/test_wounds.lua','LUA')),'wounds_fixture',false)
 assert(isfunction(f),'suite compilation failed')
 local env=setmetatable({},{__index=_G});env._G=env
 env.loadstring=function(s,n)local fn=CompileString(s,n,false);if isfunction(fn)then return fn end;return nil,fn end
 setfenv(f,env);local tests=f()(before,after);r.tests=tests.tests;r.metrics=tests.metrics
 for _,t in ipairs(r.tests)do assert(t.pass,t.name..': '..tostring(t.error))end
 assert(#r.tests==28,'incomplete suite')
 local m=assert(hg.organism.module.blood)
 ZCPendingWoundCapture={module=m,run=m[2],time=r.time}
 r.liveSource=debug.getinfo(m[2],'S');r.passed=true
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_pending_deploy')
file.Write('zc_pending_deploy/wounds_preflight_20260919t215743z.json',util.TableToJSON(r,true))
print('ZC_PENDING_WOUNDS_PREFLIGHT',r.passed,#r.tests,r.error or '')
