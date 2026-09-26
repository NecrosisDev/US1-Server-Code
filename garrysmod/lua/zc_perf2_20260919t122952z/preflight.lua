local base='zc_perf2_20260919t122952z/'
local r={time=os.time(),passed=false,tests={},metrics={},hashes={},livePlayerTests=false}
local ok,err=xpcall(function()
 local m=util.JSONToTable(assert(file.Read(base..'manifest.json','LUA')))
 local old,new={},{}
 for _,row in ipairs(m.changes)do
  local path=row.file:gsub('^garrysmod/addons/zcity/lua/',''):gsub('^garrysmod/lua/','')
  old[row.file]=assert(file.Read(path,'LUA'))
  new[row.file]=assert(file.Read(base..'candidate/'..row.file,'LUA'))
  assert(util.SHA256(old[row.file])==row.before_sha256,'concurrent edit '..path)
  assert(util.SHA256(new[row.file])==row.candidate_sha256,'staging mismatch '..path)
  assert(type(CompileString(new[row.file],'syntax_'..path,false))=='function','syntax '..path)
  r.hashes[row.file]=row.candidate_sha256
 end
 local function suite(name,...)
  local f=CompileString(assert(file.Read(base..name..'.lua','LUA')),name,false);assert(type(f)=='function',tostring(f))
  local tests,metrics=f()(...)
  for _,t in ipairs(tests)do r.tests[#r.tests+1]=t;assert(t.pass,t.name..': '..tostring(t.error))end
  if metrics then r.metrics[name]=metrics end
 end
 local g='garrysmod/addons/zcity/lua/entities/ent_hg_grenade/init.lua'
 local p='garrysmod/lua/autorun/server/zc_poop_throw.lua'
 local u='garrysmod/lua/autorun/server/zc_urine.lua'
 suite('test_fragments',old[g],new[g]);suite('test_fire',old[u],new[u])
 suite('test_scan',old[p]);r.metrics.scanBefore=r.metrics.test_scan
 suite('test_scan',new[p]);r.metrics.scanAfter=r.metrics.test_scan;r.metrics.test_scan=nil
 suite('test_sticky_regression',new[p])
 r.passed=true
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_perf_batch2')
file.Write('zc_perf_batch2/preflight_20260919t122952z.json',util.TableToJSON(r,true))
print('ZC_PERF2_PREFLIGHT',r.passed,#r.tests,r.error or '')
