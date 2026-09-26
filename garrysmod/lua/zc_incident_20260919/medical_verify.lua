assert(SERVER)
local R=assert(ZCJusticeV3Integration)
local patch=assert(ZCMedicalReceiptOptimization)
local info=debug.getinfo(R.medical_model.change,'S')
local leftovers={hooks={},timers={},globals={}}
for event,rows in pairs(hook.GetTable())do
 for name in pairs(rows)do
  if isstring(name)and(name:find('ZCLuaCost',1,true)or name:find('ZCLuaMethods',1,true)or name=='ZCMedicalBench20260919')then leftovers.hooks[#leftovers.hooks+1]=event..'/'..name end
 end
end
for _,name in ipairs({'ZCLuaCost20260919_watchdog','ZCLuaCostHands20260919','ZCLuaMethods20260919','ZCMedicalBench20260919'})do
 if timer.Exists(name)then leftovers.timers[#leftovers.timers+1]=name end
end
for _,name in ipairs({'ZCLuaMethodSample','ZCLuaCostLabel','ZCMedicalBench20260919','ZCMedicalReceiptPreflight'})do
 if _G[name]~=nil then leftovers.globals[#leftovers.globals+1]=name end
end
assert(#leftovers.hooks==0 and #leftovers.timers==0 and #leftovers.globals==0,'diagnostic remains')
assert(R.enabled and R==patch.runtime and getmetatable(R.medical_model)==patch.proto)
assert(R.medical_model.change==patch.installed,'optimized method not active')
local result={at=os.time(),active=true,version=patch.version,source=info.source,line=info.linedefined,
 sequence=R.medical_sequence,stats=table.Copy(R.stats),leftovers=leftovers,players=#player.GetHumans(),map=game.GetMap()}
file.Write('zc_incident_20260919/medical_verified.json',util.TableToJSON(result,false))
print('ZC_MEDICAL_VERIFY_OK',result.sequence,result.stats.errors)
