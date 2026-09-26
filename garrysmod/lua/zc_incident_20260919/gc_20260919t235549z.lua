assert(SERVER)
assert(not ZCGCCost20260919)
local key='ZC_GCSmooth'
local original=assert(hook.GetTable().Tick[key])
assert(debug.getinfo(original,'S').source=='@addons/zc_gcsmooth/lua/autorun/server/sv_zc_gcsmooth.lua','unexpected GC owner')
local label=assert(ZCGCCostLabel)
local start=SysTime()
local r={label=label,started=os.time(),calls=0,totalMs=0,maxMs=0,spikes={},states={},map=game.GetMap()}
local function record(t,before,...)
 local ms=(SysTime()-t)*1000
 r.calls=r.calls+1;r.totalMs=r.totalMs+ms;r.maxMs=math.max(r.maxMs,ms)
 if ms>10 and #r.spikes<200 then r.spikes[#r.spikes+1]={at=SysTime()-start,ms=ms,heapDropKB=before-collectgarbage('count'),round=zb.ROUND_STATE,mode=zb.CROUND,players=#player.GetHumans()}end
 return ...
end
local wrapper=function(...)local heap=collectgarbage('count');return record(SysTime(),heap,original(...))end
local active=true
local function finish(reason)
 if not active then return end;active=false
 if hook.GetTable().Tick[key]==wrapper then hook.Add('Tick',key,original);r.restored=true else r.drift=true end
 hook.Remove('ZB_EndRound','ZCGCCost20260919');timer.Remove('ZCGCCost20260919')
 r.elapsed=SysTime()-start;r.reason=reason;r.remaining=hook.GetTable().Tick[key]==wrapper
 ZCGCCost20260919=nil;ZCGCCostLabel=nil
 file.Write('zc_incident_20260919/'..label..'.json',util.TableToJSON(r,false))
 print('ZC_GC_COST_DONE',label,r.restored,r.maxMs)
end
ZCGCCost20260919={finish=finish}
hook.Add('Tick',key,wrapper)
hook.Add('ZB_EndRound','ZCGCCost20260919',function()r.ended=SysTime()-start end,HOOK_MONITOR_LOW)
timer.Create('ZCGCCost20260919',1,0,function()
 local elapsed=SysTime()-start
 r.states[#r.states+1]={at=elapsed,round=zb.ROUND_STATE,mode=zb.CROUND,players=#player.GetHumans()}
 if r.ended and elapsed-r.ended>3 then finish('natural round end')elseif elapsed>=300 then finish('time limit')end
end)
