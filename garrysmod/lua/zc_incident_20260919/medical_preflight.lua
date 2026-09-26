assert(SERVER)
assert(not ZCLuaMethodSample and not ZCMedicalBench20260919,'diagnostic still active')
local R=assert(ZCJusticeV3Integration,'justice observer missing')
assert(R.enabled,'justice observer disabled')
local model=assert(R.medical_model)
assert(rawget(model,'change')==nil,'unexpected instance override')
local proto=assert(getmetatable(model))
local info=debug.getinfo(proto.change,'S')
assert(info.source=='@lua/zc_justice_v3/medical_core.lua' and info.linedefined==64,'unexpected current function')
ZCMedicalReceiptPreflight={runtime=R,model=model,proto=proto,original=proto.change,states=model.states,causes=model.causes}
local r={at=os.time(),enabled=R.enabled,stats=table.Copy(R.stats),source=info.source,line=info.linedefined,
    sequence=R.medical_sequence,stateCount=model.state_count,causeCount=model.cause_count,players=#player.GetHumans(),map=game.GetMap()}
file.Write('zc_incident_20260919/medical_preflight.json',util.TableToJSON(r,false))
print('ZC_MEDICAL_PREFLIGHT_OK',r.sequence,r.stats.errors)
