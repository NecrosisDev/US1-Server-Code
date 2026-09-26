-- Bounded, passive wall-interval observer; never wraps existing callbacks.
local id='ZC48Passive_20260919t020013z';assert(not (hook.GetTable().Tick or {})[id],'already active')
local r={started=os.time(),tickInterval=engine.TickInterval(),timescale=game.GetTimeScale(),frames={},states={},events={},created={},removed={},cvars={}}
local started,last=SysTime(),nil;local nextState=0;local done=false
for _,n in ipairs({'host_timescale','sv_parallel_sendsnapshot','sv_maxrate','sv_minrate','sv_maxupdaterate','sv_minupdaterate','gmod_physiterations','zc_perf','zc_perf_auto','zc_orgsched_interval'}) do local c=GetConVar(n);if c then r.cvars[n]=c:GetString() end end
local function state()
 local ps=player.GetHumans();local alive,fake,maxloss=0,0,0
 for _,p in ipairs(ps) do if p:Alive() then alive=alive+1 end;if IsValid(p.FakeRagdoll) then fake=fake+1 end;maxloss=math.max(maxloss,p:PacketLoss()) end
 r.states[#r.states+1]={at=SysTime()-started,humans=#ps,alive=alive,fake=fake,maxloss=maxloss,map=game.GetMap(),mode=zb and zb.CROUND,round=zb and zb.ROUND_STATE,entities=ents.GetCount(),heapKB=collectgarbage('count'),budgetQueue=ZCTickBudget and ZCTickBudget.total,physicsPaused=physenv.GetPhysicsPaused()}
end
local function finish(reason)
 if done then return end;done=true
 for _,event in ipairs({'Tick','OnEntityCreated','EntityRemoved','ZB_StartRound','ZB_EndRound'}) do hook.Remove(event,id) end
 timer.Remove(id..'_guard');state();r.reason=reason;r.elapsed=SysTime()-started;r.finished=os.time()
 file.CreateDir('zc_48x60_audit');file.Write('zc_48x60_audit/passive_20260919t020013z.json',util.TableToJSON(r,false))
 print('ZC48_PASSIVE_FINISHED',reason,#r.frames)
end
local function event(name)r.events[#r.events+1]={at=SysTime()-started,name=name}end
hook.Add('ZB_StartRound',id,function()event('round_start')end)
hook.Add('ZB_EndRound',id,function()event('round_end')end)
hook.Add('OnEntityCreated',id,function(e)if IsValid(e) then local c=e:GetClass();r.created[c]=(r.created[c] or 0)+1 end end)
hook.Add('EntityRemoved',id,function(e)local c=e:GetClass();r.removed[c]=(r.removed[c] or 0)+1 end)
r.workMs=0;r.maxWorkMs=0
hook.Add('Tick',id,function()
 local now=SysTime()
 if last then r.frames[#r.frames+1]={now-started,(now-last)*1000,physenv.GetLastSimulationTime()*1000} end;last=now
 if now>=nextState then nextState=now+1;state() end
 local ms=(SysTime()-now)*1000;r.workMs=r.workMs+ms;r.maxWorkMs=math.max(r.maxWorkMs,ms)
 if now-started>=60 then finish('complete') end
end)
timer.Create(id..'_guard',70,1,function()finish('watchdog')end)
print('ZC48_PASSIVE_STARTED',game.GetMap(),#player.GetHumans())
