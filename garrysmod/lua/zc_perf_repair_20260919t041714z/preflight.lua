local base='zc_perf_repair_20260919t041714z/'
local stateName='ZCPerfRepair041714'
local r={time=os.time(),passed=false,compiled={},liveMethodsChanged=false}
local function resolve()
 return {shake=util.ScreenShake,grenade=weapons.GetStored('weapon_hg_grenade_tpik').Throw,
  medPrimary=weapons.GetStored('weapon_bandage_sh').PrimaryAttack,medSecondary=weapons.GetStored('weapon_bandage_sh').SecondaryAttack,
  shoot=weapons.GetStored('homigrad_base').Shoot}
end
local ok,err=xpcall(function()
 local manifest=util.JSONToTable(assert(file.Read(base..'MANIFEST.json','LUA')))
 local normalize=function(s)return s:gsub('\r\n','\n')end
 for _,c in ipairs(manifest.changes) do
  assert(util.SHA256(assert(file.Read(c.file:gsub('^garrysmod/',''),'GAME')))==c.before_sha256,'live source changed: '..c.file)
  local s=assert(file.Read(base..'candidate/'..c.file,'LUA'))
  assert(util.SHA256(s)==c.candidate_sha256,'staged hash differs: '..c.file)
  local f=CompileString(s,'syntax_'..c.file,false);assert(type(f)=='function',tostring(f))
 end
 local loader=CompileString(assert(file.Read(base..'compile_method.lua','LUA')),'compile_method',false)
 assert(type(loader)=='function',tostring(loader));local build=loader()
 local originals=resolve();local prepared={}
 local helper=assert(file.Read(base..'medical_publication.inc.lua','LUA'))
 for name,d in pairs(manifest.functions) do
  local before=assert(file.Read(base..name..'_before.lua','LUA'))
  local after=assert(file.Read(base..name..'_candidate.lua','LUA'))
  assert(normalize(assert(file.Read(d.file:gsub('^garrysmod/',''),'GAME'))):find(before,1,true),'old body not in live source: '..name)
  assert(normalize(assert(file.Read(base..'candidate/'..d.file,'LUA'))):find(after,1,true),'new body not in candidate: '..name)
  local old=assert(originals[name]);local meta=debug.getinfo(old,'S')
  assert(meta.source=='@'..d.file:gsub('^garrysmod/',''),'unexpected runtime owner: '..name)
  local code=normalize(assert(file.Read(d.file:gsub('^garrysmod/',''),'GAME')));local lines=string.Explode('\n',code)
  local runtimeBody=table.concat(lines,'\n',meta.linedefined,meta.lastlinedefined)
  assert(runtimeBody==before,'runtime body/source mismatch: '..name)
  local useHelper=(name=='medPrimary' or name=='medSecondary') and helper or ''
  local fn,upvalues=build(old,after,useHelper,'perf_repair/'..name)
  prepared[name]={old=old,new=fn}
  r.compiled[name]={upvalues=upvalues,bodySHA256=util.SHA256(after),sourceSHA256=util.SHA256(assert(file.Read(d.file:gsub('^garrysmod/',''),'GAME')))}
 end
 local ss=util.JSONToTable(assert(file.Read('zc_48x60_audit/screenshake_fixture_20260919t020013z.json','DATA')))
 local gg=util.JSONToTable(assert(file.Read('zc_tick_incident/grenade_preflight_20260919t013709z.json','DATA')))
 assert(ss.passed and ss.time>=manifest.testNotBefore,'fresh screenshake tests missing')
 assert(gg.passed and gg.time>=manifest.testNotBefore,'fresh grenade tests missing')
 r.nativeScreenTests=ss.tests;r.nativeGrenadeTests=gg.tests
 assert(_G[stateName]==nil or not _G[stateName].active,'repair is already active')
 _G[stateName]={prepared=prepared,manifest=manifest,resolve=resolve,slots={},active=false}
 r.passed=true
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_perf_repairs')
file.Write('zc_perf_repairs/preflight_20260919t041714z.json',util.TableToJSON(r,true))
print('ZC_PERF_REPAIR_PREFLIGHT',r.passed,r.error or '')
