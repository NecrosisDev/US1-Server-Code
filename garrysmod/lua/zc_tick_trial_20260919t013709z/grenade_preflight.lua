local base='zc_tick_trial_20260919t013709z/'
local r={time=os.time(),passed=false}
local ok,err=xpcall(function()
 local source=assert(file.Read('weapons/weapon_hg_grenade_tpik.lua','LUA'))
 r.liveSHA256=util.SHA256(source)
 assert(r.liveSHA256=='1897e2e69b40792a1782826baf38178d67a64fadbc88d9331d6f952cda1aad6d','concurrent source edit')
 local old=assert(file.Read(base..'throw-before.lua','LUA'))
 local new=assert(file.Read(base..'throw-candidate.lua','LUA'))
 local candidate=assert(file.Read(base..'weapon_hg_grenade_tpik.candidate.lua','LUA'))
 assert(type(CompileString(candidate,'grenade_candidate_parse',false))=='function','full candidate syntax')
 local normalized=source:gsub('\r\n','\n');assert(normalized:find((old:gsub('\r\n','\n')),1,true),'old test body not in current source')
 local fn=CompileString(assert(file.Read(base..'test_grenade_native.lua','LUA')),'grenade_isolated_tests',false)
 assert(type(fn)=='function','test syntax')
 local scope=setmetatable({},{__index=_G});scope._G=scope
 scope.loadstring=function(s,n)local f=CompileString(s,n or 'grenade_test',false);if type(f)=='function' then return f end;return nil,f end
 setfenv(fn,scope);r.tests=fn()(old,new)
 for _,t in ipairs(r.tests)do assert(t.pass,t.name..': '..tostring(t.error))end
 local stored=assert(weapons.GetStored('weapon_hg_grenade_tpik'))
 local throw=assert(rawget(stored,'Throw'));r.runtime=debug.getinfo(throw,'S');r.environmentNative=getfenv(throw)==_G
 r.aliases=0
 for _,entry in ipairs(weapons.GetList())do local t=weapons.GetStored(entry.ClassName);if t and rawget(t,'Throw')==throw then r.aliases=r.aliases+1 end end
 r.candidateSHA256=util.SHA256(candidate);r.passed=true
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_tick_incident');file.Write('zc_tick_incident/grenade_preflight_20260919t013709z.json',util.TableToJSON(r,true))
print('ZC_GRENADE_POSE_PREFLIGHT',r.passed,r.error or '')
