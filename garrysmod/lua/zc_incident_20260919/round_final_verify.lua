assert(SERVER)
local r={at=os.time(),leftovers={},timers={},globals={},netCompress=GetConVar('net_compresspackets'):GetInt()}
for event,rows in pairs(hook.GetTable())do for name in pairs(rows)do
 if isstring(name)and(name:find('ZCRoundCost20260919',1,true)or name:find('ZCRoundPhase20260919',1,true)or name:find('ZCGCCost20260919',1,true))then r.leftovers[#r.leftovers+1]=event..'/'..name end
end end
for _,name in ipairs({'ZCRoundCost20260919','ZCRoundPhase20260919','ZCGCCost20260919'})do if timer.Exists(name)then r.timers[#r.timers+1]=name end end
for _,name in ipairs({'ZCRoundCost20260919','ZCRoundCostLabel','ZCRoundPhase20260919','ZCRoundPhaseLabel','ZCGCCost20260919','ZCGCCostLabel','ZCCompressionTrial20260919'})do if _G[name]~=nil then r.globals[#r.globals+1]=name end end
local K=assert(ZC_TRAITOR_POPULATION)
r.traitorOwner=K.mode.Intermission==K.wrapper
r.traitorDelegate=debug.getinfo(K.original,'S').source
r.gcHook=debug.getinfo(hook.GetTable().Tick.ZC_GCSmooth,'S').source
assert(#r.leftovers==0 and #r.timers==0 and #r.globals==0,'observer remains')
assert(r.traitorOwner and r.traitorDelegate=='@zc_role_privacy','traitor delegate changed')
assert(r.gcHook=='@addons/zc_gcsmooth/lua/autorun/server/sv_zc_gcsmooth.lua','GC not restored')
assert(r.netCompress==1,'compression changed')
file.Write('zc_incident_20260919/round_final_verify.json',util.TableToJSON(r,false))
print('ZC_ROUND_FINAL_VERIFY_OK')
