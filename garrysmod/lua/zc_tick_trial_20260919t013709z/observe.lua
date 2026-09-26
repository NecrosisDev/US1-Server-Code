-- Temporary read-only tick/physics recorder. No gameplay function wrapping.
assert(SERVER,'server only')
local id='zc_tick_incident_20260919t013709z'
assert(type(rawget(physenv,'GetLastSimulationTime'))=='function','physics timer unavailable')
assert(not (ZCTickIncident and ZCTickIncident.active),'a capture is already active')
local S={active=true,phase='baseline',start=SysTime(),last=nil,rows={},samples={},events={},cost=0,maxCost=0}
S.runID=id
ZCTickIncident=S
local output='zc_tick_incident/capture_20260919t013709z.json'
local clock=SysTime
local function snapshot()
 local p={at=clock()-S.start,time=os.time(),map=game.GetMap(),mode=zb and zb.CROUND,round=zb and zb.ROUND_STATE}
 p.humans=0;p.alive=0;p.fake=0;p.highPing=0;p.lossMax=0
 for _,v in ipairs(player.GetAll()) do
  if not v:IsBot() then p.humans=p.humans+1;if v:Ping()>150 then p.highPing=p.highPing+1 end end
  if v:Alive() then p.alive=p.alive+1 end
  if IsValid(v.FakeRagdoll) then p.fake=p.fake+1 end
  if v.PacketLoss then p.lossMax=math.max(p.lossMax,v:PacketLoss()) end
 end
 p.entities=ents.GetCount();p.heapKB=collectgarbage('count')
 local b=ZCTickBudget
 p.queued=b and b.total or 0;p.workMs=b and b.lastWorkMs or 0
 p.physicsPaused=physenv.GetPhysicsPaused();p.phase=S.phase
 return p
end
S.initial=snapshot();S.tickInterval=engine.TickInterval();S.version=VERSIONSTR
S.originals={hookCall=hook.Call,hookAdd=hook.Add,include=include,netStart=net.Start}
function S.Mark(phase)
 assert(type(phase)=='string' and #phase<40,'invalid phase')
 S.phase=phase;S.events[#S.events+1]={at=clock()-S.start,label=phase}
 file.CreateDir('zc_tick_incident');file.Write('zc_tick_incident/control_20260919t013709z.json',util.TableToJSON({runID=S.runID,phase=phase,active=S.active,time=os.time(),at=clock()-S.start,population=snapshot()},false))
end
function S.Stop(reason)
 if not S.active then return end
 S.active=false;hook.Remove('Tick',id);timer.Remove(id)
 hook.Remove('ZB_StartRound',id);hook.Remove('ZB_EndRound',id);hook.Remove('ShutDown',id)
 local r={startTime=S.initial.time,ended=os.time(),elapsed=clock()-S.start,reason=reason,
  tickInterval=S.tickInterval,version=S.version,initial=S.initial,final=snapshot(),
  frames=S.rows,seconds=S.samples,events=S.events,captureCostMs=S.cost*1000,maxCaptureCostMs=S.maxCost*1000,
  globalsUnchanged=hook.Call==S.originals.hookCall and hook.Add==S.originals.hookAdd and include==S.originals.include and net.Start==S.originals.netStart,
  note='Wall intervals and last native physics duration; observation is not a controlled capacity benchmark. Capture serialization excluded from measured work.'}
 file.CreateDir('zc_tick_incident');file.Write(output,util.TableToJSON(r,false))
 S.lastReport=output;print('ZC_TICK_INCIDENT_SAVED',reason,#S.rows)
end
local nextSample=0
hook.Add('Tick',id,function()
 local now=clock()
 if S.last then S.rows[#S.rows+1]={now-S.start,(now-S.last)*1000,physenv.GetLastSimulationTime()*1000,#S.samples} end
 S.last=now
 if now>=nextSample then S.samples[#S.samples+1]=snapshot();nextSample=now+1 end
 local dt=clock()-now;S.cost=S.cost+dt;S.maxCost=math.max(S.maxCost,dt)
 if now-S.start>=330 or #S.rows>=24000 then S.Stop('limit') end
end)
hook.Add('ZB_StartRound',id,function()S.events[#S.events+1]={at=clock()-S.start,label='round_start'}end)
hook.Add('ZB_EndRound',id,function()S.events[#S.events+1]={at=clock()-S.start,label='round_end'}end)
hook.Add('ShutDown',id,function()S.Stop('map_or_shutdown')end)
timer.Create(id,340,1,function()S.Stop('watchdog')end)
S.Mark('baseline')
print('ZC_TICK_INCIDENT_STARTED',S.initial.map,S.initial.humans)
