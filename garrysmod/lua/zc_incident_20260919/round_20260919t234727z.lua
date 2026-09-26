assert(SERVER)
assert(not ZCRoundCost20260919,'round capture already active')
local label=assert(ZCRoundCostLabel)
local start=SysTime()
local id='ZCRoundCost20260919'
local r={label=label,started=os.time(),map=game.GetMap(),rows={},spikes={},states={},restored=0,drift=0}
local slots={}
local function record(row,t,group,...)
 local dt=(SysTime()-t)*1000
 row.calls=row.calls+1;row.totalMs=row.totalMs+dt;row.maxMs=math.max(row.maxMs,dt)
 if group=='zb.EndRound'then r.roundEnded=SysTime()-start end
 return ...
end
local function install(slot,key,group)
 if not istable(slot)or not isfunction(slot[key])then return end
 local original=slot[key];local info=debug.getinfo(original,'S')
 if info.what~='Lua'then return end
 local row={calls=0,totalMs=0,maxMs=0,source=info.source,line=info.linedefined};r.rows[group]=row
 local e={slot=slot,key=key,own=rawget(slot,key)}
 e.wrapper=function(...)return record(row,SysTime(),group,original(...))end
 slots[#slots+1]=e;slot[key]=e.wrapper
end
for _,key in ipairs({'EndRound','EndRoundThink','KillPlayers'})do install(zb,key,'zb.'..key)end
local mode=CurrentRound()
install(mode,'EndRound','mode.EndRound')
install(mode,'Intermission','mode.Intermission')
for _,key in ipairs({'SavePlayerAchievements','SaveToSQL'})do install(hg.achievements,key,'achievements.'..key)end
local R=ZCJusticeV3Integration
if R then
 for _,key in ipairs({'Flush','WriteStatus'})do install(R,key,'justice.'..key)end
 if R.observer then
  for _,key in ipairs({'EndRound','Flush','WriteStatus'})do install(R.observer,key,'shadow.'..key)end
 end
end
local active=true
local function finish(reason)
 if not active then return end;active=false
 hook.Remove('Tick',id);timer.Remove(id)
 for _,e in ipairs(slots)do
  if rawget(e.slot,e.key)==e.wrapper then e.slot[e.key]=e.own;r.restored=r.restored+1
  else r.drift=r.drift+1 end
 end
 r.remaining=0
 for _,e in ipairs(slots)do if rawget(e.slot,e.key)==e.wrapper then r.remaining=r.remaining+1 end end
 r.installed=#slots;r.elapsed=SysTime()-start;r.reason=reason
 ZCRoundCost20260919=nil;ZCRoundCostLabel=nil
 file.Write('zc_incident_20260919/'..label..'.json',util.TableToJSON(r,false))
 print('ZC_ROUND_COST_DONE',label,r.reason,r.restored,r.drift,r.remaining)
end
ZCRoundCost20260919={finish=finish}
local last,nextState=nil,start
hook.Add('Tick',id,function()
 local now=SysTime()
 if last and now-last>.06 and #r.spikes<150 then r.spikes[#r.spikes+1]={at=now-start,ms=(now-last)*1000,state=zb.ROUND_STATE,mode=zb.CROUND}end
 last=now
 if now>=nextState then
  nextState=now+3;local alive=0
  for _,p in ipairs(player.GetHumans())do if p:Alive()then alive=alive+1 end end
  r.states[#r.states+1]={at=now-start,players=#player.GetHumans(),alive=alive,mode=zb.CROUND,state=zb.ROUND_STATE,entities=ents.GetCount()}
 end
 if r.roundEnded and now-start>r.roundEnded+3 then finish('natural round end')
 elseif now-start>=300 then finish('time limit')end
end)
timer.Create(id,310,1,function()finish('watchdog')end)
print('ZC_ROUND_COST_STARTED',label)
