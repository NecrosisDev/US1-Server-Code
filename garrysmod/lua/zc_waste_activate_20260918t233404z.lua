local report={time=os.time(),activated=false,loaded={},beforeStats={}}
local mapping={['autorun/server/zc_poop.lua']='ZCityPoop',['autorun/server/zc_poop_involuntary.lua']='ZCityPoopInvoluntary',['autorun/server/zc_poop_throw.lua']='ZCityPoopThrow',['autorun/server/zc_urine.lua']='ZCityUrine'}
local expected={ZCityPoop='20260918.h1',ZCityPoopInvoluntary='20260918.h1',ZCityPoopThrow='20260918.h2',ZCityUrine='20260918.h2'}
local ok,err=xpcall(function()
 local pre=util.JSONToTable(assert(file.Read('zc_waste_hardening/preflight_20260918t233404z.json','DATA')))
 assert(pre and pre.passed,'native preflight missing')
 for path,hash in pairs(pre.sources)do assert(util.SHA256(assert(file.Read(path,'LUA')))==hash,'installed hash mismatch '..path)end
 local refs={}
 for _,name in pairs(mapping)do refs[name]=_G[name];report.beforeStats[name]=table.Copy(_G[name] and _G[name].stats or {})end
 for _,path in ipairs({'autorun/server/zc_poop.lua','autorun/server/zc_poop_involuntary.lua','autorun/server/zc_poop_throw.lua','autorun/server/zc_urine.lua'})do
  include(path)
  local name=mapping[path]
  assert(_G[name].Version==expected[name],'wrong active version '..name)
  assert(_G[name]==refs[name],'persistent state table replaced '..name)
  report.loaded[name]=_G[name].Version
 end
 report.activated=true
end,debug.traceback)
if not ok then report.error=err end
file.CreateDir('zc_waste_hardening')
file.Write('zc_waste_hardening/activation_20260918t233404z.json',util.TableToJSON(report,true))
print('ZCWASTE_ACTIVATION',report.activated,report.error or '')
