-- Exact method compilation and isolated fixtures; no live weapon actions.
local base='zc_tranq_validation_20260919t132421z/'
local r={time=os.time(),passed=false,tests={},liveActions=false}
local ok,err=xpcall(function()
 local original=assert(file.Read('weapons/weapon_tranquilizer.lua','LUA'))
 local candidate=assert(file.Read(base..'tranq_file.lua','LUA'))
 r.beforeHash=util.SHA256(original);r.candidateHash=util.SHA256(candidate)
 assert(r.beforeHash=='4d96a58f8d058d42a8a2ee1cf22eec4104486efaddd8967b944258c5c2edbbbd','live source changed')
 assert(r.candidateHash=='879fa0155b451120110d5a0170c8eab1312441cf35073431a5c2863855dbb9c5','candidate changed')
 assert(type(CompileString(candidate,'tranquilizer_full_parse',false))=='function','full source failed to compile')
 local before=assert(file.Read(base..'tranq_before.lua','LUA'))
 local after=assert(file.Read(base..'tranq_candidate.lua','LUA'))
 local function normalize(s)return s:gsub('\r\n','\n')end
 assert(normalize(original):find(normalize(before),1,true),'old fixture not exact source')
 assert(normalize(candidate):find(normalize(after),1,true),'new fixture not exact source')
 local suite=CompileString(assert(file.Read(base..'test_tranquilizer.lua','LUA')),'tranquilizer_tests',false)
 assert(type(suite)=='function','fixture syntax')
 r.tests,r.metrics=suite()(before,after,function(s,n)return CompileString(s,n,false)end)
 for _,t in ipairs(r.tests) do assert(t.pass,t.name..': '..tostring(t.error)) end
 local t=assert(weapons.GetStored('weapon_tranquilizer'));r.loaded=debug.getinfo(t.Shoot,'S')
 ZCTranqValidation132421={old=t.Shoot,time=r.time}
 r.passed=true
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_net_validation')
file.Write('zc_net_validation/tranq_preflight_20260919t132421z.json',util.TableToJSON(r,true))
print('ZC_TRANQ_PREFLIGHT',r.passed,#r.tests,r.error or '')
