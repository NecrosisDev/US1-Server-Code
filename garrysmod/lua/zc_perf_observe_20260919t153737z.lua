-- Bounded passive sample: no wrappers, cvar changes, sends or gameplay actions.
local id='ZCPerfObserve153737';assert(not timer.Exists(id),'capture already active')
local r={time=os.time(),map=game.GetMap(),tick=engine.TickInterval(),frames={},states={},netBefore=ZCNETOPT and table.Copy(ZCNETOPT.sent),versions={}}
for _,n in ipairs({'ZCityPoopThrow','ZCityUrine','ZCFartPuff'}) do r.versions[n]=_G[n] and _G[n].Version end
r.fragmentVersion=scripted_ents.GetStored('ent_hg_grenade').t.ZCFragmentBudgetVersion
local started,last,roster=SysTime(),nil,0;local done=false
local function finish(reason)
 if done then return end;done=true;hook.Remove('Tick',id);timer.Remove(id)
 r.elapsed=SysTime()-started;r.reason=reason;r.finished=os.time()
 r.netAfter=ZCNETOPT and table.Copy(ZCNETOPT.sent)
 file.CreateDir('zc_perf_next');file.Write('zc_perf_next/observe_20260919t153737z.json',util.TableToJSON(r,false))
 print('ZC_PERF_NEXT_OBSERVE_COMPLETE',#r.frames)
end
hook.Add('Tick',id,function()
 local n=SysTime();if last then r.frames[#r.frames+1]={n-started,(n-last)*1000,physenv.GetLastSimulationTime()*1000}end;last=n
 if n>=roster then
  roster=n+1;local ps=player.GetHumans();local alive=0;for _,p in ipairs(ps)do if p:Alive()then alive=alive+1 end end
  r.states[#r.states+1]={at=n-started,players=#ps,alive=alive,entities=ents.GetCount(),map=game.GetMap(),mode=zb and zb.CROUND,round=zb and zb.ROUND_STATE,heapKB=collectgarbage('count')}
 end
 if n-started>=60 or #r.frames>=10000 then finish('complete')end
end)
timer.Create(id,70,1,function()finish('watchdog')end)
print('ZC_PERF_NEXT_OBSERVE_START',r.map,#player.GetHumans())
