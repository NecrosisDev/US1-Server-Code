-- Parse and inspect only. Does not construct constraints or call weapon actions.
local r={time=os.time(),passed=false,liveActions=false,nativeBehaviorTests=false}
local ok,err=xpcall(function()
 local path='weapons/weapon_ducttape.lua';local source=assert(file.Read(path,'LUA'))
 local staged=assert(file.Read('zc_tape_repair_20260919t153737z/candidate.lua','LUA'))
 r.before=util.SHA256(source);r.candidate=util.SHA256(staged)
 assert(r.before=='f5faff36e93a866e1b31285c8b1e57d02d8c801d219aade4285e5744fd649508','live file changed')
 assert(r.candidate=='8bf1e137ac43445c709a93c6990617318f88aaa32303f2ddfec54e78545a4b56','candidate changed')
 assert(isfunction(CompileString(staged,'tape_candidate_compile',false)),'syntax failure')
 local normalized=staged:gsub('\r\n','\n')
 local a=assert(normalized:find('local function BindObjects(',1,true))
 local b=assert(normalized:find('function hgCheckDuctTapeObjects',a,true))
 local body=normalized:sub(a,b-1):gsub('%s+$','')..'\n'
 r.bindingHash=util.SHA256(body)
 assert(r.bindingHash=='cfd5a7a1b314aef506fa14f68875bbb0f89de034fd7747a693fc79ad687ce4ec','not the locally tested binding function')
 local t=assert(weapons.GetStored('weapon_ducttape'));local f=assert(t.PrimaryAttack)
 ZCTape153737Check={oldPrimary=f,time=os.time()}
 r.runtime=debug.getinfo(f,'S');r.passed=true
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_perf_next');file.Write('zc_perf_next/tape_preflight_20260919t153737z.json',util.TableToJSON(r,true))
print('ZC_TAPE_PREFLIGHT',r.passed,r.error or '')
