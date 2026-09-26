local r={time=os.time(),removed=false}
local S=ZCTickIncident
if S and S.runID=='zc_tick_incident_20260919t013709z' then
 if S.active then S.Stop('cleanup') end
 ZCTickIncident=nil;r.removed=true
end
r.tickHookPresent=(hook.GetTable().Tick or {})['zc_tick_incident_20260919t013709z']~=nil
r.watchdogPresent=timer.Exists('zc_tick_incident_20260919t013709z')
r.restorePresent=timer.Exists('zc_tick_profiler_restore_20260919t013709z')
r.eventProbePresent=(hook.GetTable().Think or {})['ZCTickEventProbe_20260919t013709z_begin']~=nil
r.grenadeRuntimePresent=ZCTickGrenadePoseRepair~=nil
file.CreateDir('zc_tick_incident');file.Write('zc_tick_incident/cleanup_20260919t013709z.json',util.TableToJSON(r,true))
print('ZC_TICK_INCIDENT_CLEANUP',r.removed,r.tickHookPresent,r.watchdogPresent)
