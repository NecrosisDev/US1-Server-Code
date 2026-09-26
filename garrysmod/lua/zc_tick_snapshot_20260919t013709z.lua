-- Read-only state/census, manually invoked outside autorun.
local r={time=os.time(),map=game.GetMap(),mode=zb and zb.CROUND,round=zb and zb.ROUND_STATE,
 players=#player.GetHumans(),tickInterval=engine.TickInterval(),jit={jit.status()},classes={},physics={total=0,awake=0,movable=0},sources={}}
local before=SysTime()
for _,e in ipairs(ents.GetAll()) do
 local name=e:GetClass();r.classes[name]=(r.classes[name] or 0)+1
 for i=0,e:GetPhysicsObjectCount()-1 do
  local p=e:GetPhysicsObjectNum(i)
  if IsValid(p) then
   r.physics.total=r.physics.total+1
   if p:IsMotionEnabled() then r.physics.movable=r.physics.movable+1 end
   if not p:IsAsleep() then r.physics.awake=r.physics.awake+1 end
  end
 end
end
r.censusCostMs=(SysTime()-before)*1000
r.physics.lastMs=physenv.GetLastSimulationTime()*1000
r.physics.paused=physenv.GetPhysicsPaused()
r.budget=ZCTickBudget and ZCTickBudget.Snapshot and ZCTickBudget.Snapshot()
r.netopt={sent=ZCNETOPT and table.Copy(ZCNETOPT.sent) or {},skipped=ZCNETOPT and table.Copy(ZCNETOPT.skip) or {}}
for _,n in ipairs({'zc_perf','zc_perf_auto','zc_orgsched','sv_parallel_sendsnapshot','sv_maxrate','sv_minrate','sv_minupdaterate','sv_maxupdaterate','vprof_dump_oninterval','vprof_dump_spikes'}) do
 local v=GetConVar(n);if v then r[n]=v:GetString() end
end
for _,name in ipairs({'ZCityUrine','ZCityPoop','ZCMakeCrawler','ZCFartPuff'}) do
 local s=_G[name];if type(s)=='table' then r[name]={version=s.Version,stats=s.stats} end
end
r.ourRecorderActive=ZCTickIncident and ZCTickIncident.active or false
r.ourTickHookPresent=(hook.GetTable().Tick or {})['zc_tick_incident_20260919t013709z']~=nil
r.ourRestoreTimer=timer.Exists('zc_tick_profiler_restore_20260919t013709z')
file.CreateDir('zc_tick_incident');file.Write('zc_tick_incident/snapshot_20260919t013709z.json',util.TableToJSON(r,true))
print('ZC_TICK_INCIDENT_SNAPSHOT',r.players,r.censusCostMs)
