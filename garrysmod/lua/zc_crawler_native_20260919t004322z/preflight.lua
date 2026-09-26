local base='zc_crawler_native_20260919t004322z/'
local r={time=os.time(),passed=false,tests={}}
local ok,err=xpcall(function()
 local gore=assert(file.Read('autorun/z_podgruz.lua','LUA'),'mounted gore source missing')
 r.goreSHA256=util.SHA256(gore)
 assert(r.goreSHA256=='f90551cb3f25cd8ffc347e71a274501de9fa947837f34e6f2d85349e380489c6','native dependency changed')
 assert(hg and isfunction(hg.ZCityGore_AmputateTorso),'native torso API missing')
 r.native=debug.getinfo(hg.ZCityGore_AmputateTorso,'S')
 local code=assert(file.Read(base..'candidate.lua','LUA'))
 r.candidateSHA256=util.SHA256(code)
 assert(isfunction(CompileString(code,'crawler_candidate',false)),'candidate syntax error')
 local native=assert(file.Read(base..'native_transition.lua','LUA'))
 assert(gore:find(native,1,true),'test native transition is not the mounted implementation')
 local suite=CompileString(assert(file.Read(base..'test_adapter.lua','LUA')),'crawler_isolated_tests',false)
 assert(isfunction(suite),'test syntax error')
 local scope=setmetatable({ZCMakeCrawler=false},{__index=_G});scope._G=scope
 scope.loadstring=function(s,n)local f=CompileString(s,n or 'crawler_test',false);if isfunction(f) then return f end;return nil,f end
 setfenv(suite,scope);r.tests=suite()(code,native)
 for _,t in ipairs(r.tests) do assert(t.pass,t.name..': '..tostring(t.error)) end
 r.passed=true
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_crawler_native')
file.Write('zc_crawler_native/preflight_20260919t004322z.json',util.TableToJSON(r,true))
print('ZC_CRAWLER_NATIVE_PREFLIGHT',r.passed,#r.tests,r.error or '')
