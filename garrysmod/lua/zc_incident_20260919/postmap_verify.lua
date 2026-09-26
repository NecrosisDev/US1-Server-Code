assert(SERVER)
local R=assert(ZCJusticeV3Integration)
local f=assert(R.medical_model).change
local info=debug.getinfo(f,'S')
local r={at=os.time(),map=game.GetMap(),players=#player.GetHumans(),medical={enabled=R.enabled,stats=table.Copy(R.stats),source=info.source,line=info.linedefined},leftovers={},timers={},globals={},compression=GetConVar('net_compresspackets'):GetInt()}
for event,rows in pairs(hook.GetTable())do for name in pairs(rows)do
 if isstring(name)and(name:find('ZCRoundCost20260919',1,true)or name:find('ZCRoundPhase20260919',1,true)or name:find('ZCGCCost20260919',1,true)or name=='ZCCapacityObserve20260919'or name=='ZCReplicationCensus20260919')then r.leftovers[#r.leftovers+1]=event..'/'..name end
end end
for _,name in ipairs({'ZCRoundCost20260919','ZCRoundPhase20260919','ZCGCCost20260919','ZCCapacityObserve20260919','ZCReplicationCensus20260919'})do if timer.Exists(name)then r.timers[#r.timers+1]=name end end
for _,name in ipairs({'ZCRoundCost20260919','ZCRoundPhase20260919','ZCGCCost20260919','ZCIncidentObserve','ZCReplicationLabel','ZCIncidentObserveLabel','ZCCompressionTrial20260919'})do if _G[name]~=nil then r.globals[#r.globals+1]=name end end
local K=assert(ZC_TRAITOR_POPULATION)
r.traitorOwner=K.mode.Intermission==K.wrapper
r.gcHook=debug.getinfo(hook.GetTable().Tick.ZC_GCSmooth,'S').source
r.sourceHash=util.SHA256(assert(file.Read('zc_justice_v3/medical_core.lua','LUA')))
file.Write('zc_incident_20260919/postmap_verify.json',util.TableToJSON(r,false))
assert(R.enabled and info.source=='@lua/zc_justice_v3/medical_core.lua'and info.linedefined==73)
assert(r.sourceHash=='ae7773dfe6c5703300c988b57d706e1258146d84ce1829527a7d43b32274a312')
assert(#r.leftovers==0 and #r.timers==0 and #r.globals==0)
assert(r.traitorOwner and r.compression==1)
print('ZC_POSTMAP_VERIFY_OK',r.map,r.medical.stats.errors)
