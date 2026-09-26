assert(SERVER)
local expected={
 ['zc_justice_v3/medical_core.lua']='ae7773dfe6c5703300c988b57d706e1258146d84ce1829527a7d43b32274a312',
 ['zc_justice_v3/util.lua']='00105b4e2b981831cb2b3942a3935906f68232d361b6984d358769a36fa0c827',
 ['zc_justice_v3/config.lua']='dfdb804d1035a0b3ab8f1e3943eeb0ddf1da3de437cbaba02a36e33acf4a0238'}
for path,hash in pairs(expected)do assert(util.SHA256(assert(file.Read(path,'LUA')))==hash,'source changed: '..path)end
local p=assert(ZCMedicalReceiptPreflight,'missing runtime preflight')
local R=assert(ZCJusticeV3Integration)
assert(R==p.runtime and R.enabled and R.medical_model==p.model,'observer changed')
assert(getmetatable(p.model)==p.proto and p.proto.change==p.original and rawget(p.model,'change')==nil,'method changed')
assert(not ZCLuaMethodSample and not ZCMedicalBench20260919,'diagnostic still active')
local U=include('zc_justice_v3/util.lua')
local C=include('zc_justice_v3/config.lua')
local replacement=include('zc_justice_v3/medical_core.lua')(U,C).change
local seq=R.medical_sequence
local count,causes=p.model.state_count,p.model.cause_count
p.proto.change=replacement
assert(R.medical_sequence==seq and p.model.state_count==count and p.model.cause_count==causes)
assert(p.model.states==p.states and p.model.causes==p.causes,'model state changed')
ZCMedicalReceiptOptimization={version='20260919.1',runtime=R,proto=p.proto,prior=p.original,installed=replacement,at=os.time()}
ZCMedicalReceiptPreflight=nil
local info=debug.getinfo(replacement,'S')
local r={at=os.time(),version='20260919.1',enabled=R.enabled,source=info.source,line=info.linedefined,
 statesPreserved=true,sequence=seq,stateCount=count,causeCount=causes,stats=table.Copy(R.stats),hash=expected['zc_justice_v3/medical_core.lua']}
file.Write('zc_incident_20260919/medical_installed.json',util.TableToJSON(r,false))
print('ZC_MEDICAL_OPTIMIZATION_ACTIVE',r.version,r.line,r.stats.errors)
