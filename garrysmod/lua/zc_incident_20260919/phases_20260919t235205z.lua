assert(SERVER)
assert(not ZCRoundPhase20260919)
assert(HOOK_MONITOR_HIGH==-2 and HOOK_MONITOR_LOW==2)
local id='ZCRoundPhase20260919'
local label=assert(ZCRoundPhaseLabel)
local start=SysTime()
local r={label=label,started=os.time(),map=game.GetMap(),frames={},marks={},reason='',unmatched=0}
local last,thinkStart,lastHeap=nil,nil,nil
local phase={thinkMs=0,removedMs=0,removed=0,created=0,classes={}}
local removals={}
local registrations={}
local function add(event,suffix,fn,priority)
 local name=id..suffix;hook.Add(event,name,fn,priority);registrations[#registrations+1]={event,name}
end
local active=true
local function finish(reason)
 if not active then return end;active=false
 for _,h in ipairs(registrations)do hook.Remove(h[1],h[2])end
 timer.Remove(id);r.reason=reason;r.elapsed=SysTime()-start
 ZCRoundPhase20260919=nil;ZCRoundPhaseLabel=nil
 file.Write('zc_incident_20260919/'..label..'.json',util.TableToJSON(r,false))
 print('ZC_ROUND_PHASE_DONE',label,reason,#r.frames)
end
ZCRoundPhase20260919={finish=finish}
add('Think','ThinkBegin',function()thinkStart=SysTime()end,HOOK_MONITOR_HIGH)
add('Think','ThinkEnd',function()if thinkStart then phase.thinkMs=phase.thinkMs+(SysTime()-thinkStart)*1000;thinkStart=nil end end,HOOK_MONITOR_LOW)
add('EntityRemoved','RemoveBegin',function(e)
 local class=IsValid(e)and e:GetClass()or'unknown'
 removals[#removals+1]=SysTime();phase.removed=phase.removed+1;phase.classes[class]=(phase.classes[class]or 0)+1
end,HOOK_MONITOR_HIGH)
add('EntityRemoved','RemoveEnd',function()
 local t=removals[#removals]
 if t then phase.removedMs=phase.removedMs+(SysTime()-t)*1000;removals[#removals]=nil else r.unmatched=r.unmatched+1 end
end,HOOK_MONITOR_LOW)
add('OnEntityCreated','Created',function()phase.created=phase.created+1 end,HOOK_MONITOR_LOW)
for _,event in ipairs({'ZB_EndRound','PreCleanupMap','PostCleanupMap'})do
 add(event,event,function()
  r.marks[#r.marks+1]={event=event,at=SysTime()-start}
  if event=='ZB_EndRound'then r.ended=SysTime()end
 end,HOOK_MONITOR_HIGH)
end
add('Tick','Tick',function()
 local now=SysTime();local heap=collectgarbage('count')
 if last then
  local dt=(now-last)*1000
  if dt>100 or (r.ended and now-r.ended<6)then
   phase.ms=dt;phase.at=now-start;phase.heapDeltaKB=lastHeap and heap-lastHeap or 0
   phase.physicsMs=physenv.GetLastSimulationTime()*1000;phase.state=zb.ROUND_STATE
   phase.players=#player.GetHumans();phase.entities=ents.GetCount()
   phase.incompleteThink=thinkStart~=nil;phase.openRemoved=#removals
   r.frames[#r.frames+1]=phase
  end
 end
 phase={thinkMs=0,removedMs=0,removed=0,created=0,classes={}};last=now;lastHeap=heap
 if r.ended and now-r.ended>=6 then finish('natural round end')elseif now-start>=300 then finish('time limit')end
end,HOOK_MONITOR_LOW)
timer.Create(id,310,1,function()finish('watchdog')end)
