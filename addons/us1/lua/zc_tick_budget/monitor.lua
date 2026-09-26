local B=assert(ZCTickBudget)
function B.Snapshot()
    local queues={};local now=CurTime()
    for _,name in ipairs(B.names)do
        local q=B.queues[name];local head=q[q.first]
        queues[name]={count=q.last-q.first+1,oldest=head and math.max(0,now-head.firstAt) or 0,stats=table.Copy(B.stats[name])}
    end
    return {version=B.Version,map=game.GetMap(),players=#player.GetAll(),tickInterval=engine.TickInterval(),
        enabled=B.enabled:GetBool(),budgetMs=B.limit:GetFloat(),queued=B.total,queues=queues,
        highWater=B.highWater or 0,overflow=B.overflow or 0,fireShed=B.fireShed or 0,lastWorkMs=B.lastWorkMs or 0,
        worstWorkMs=B.worstWorkMs or 0,overruns=B.overruns or 0,networkDrift=B.networkDrift==true,lastError=B.lastError}
end
function B.Sample(gap)
    local c=B.capture;if not c then return end
    c.frames[#c.frames+1]=gap*1000
    if SysTime()<c.finish then return end
    B.capture=nil
    local total,worst,late=0,0,0
    for _,ms in ipairs(c.frames)do total=total+ms;worst=math.max(worst,ms);if ms>25 then late=late+1 end end
    table.sort(c.frames);local n=#c.frames
    local function pct(p)return c.frames[math.max(1,math.ceil(n*p))] or 0 end
    local r=B.Snapshot();r.capture={seconds=total/1000,frames=n,effectiveTick=n/(total/1000),
        meanMs=total/n,p50Ms=pct(0.5),p95Ms=pct(0.95),p99Ms=pct(0.99),worstMs=worst,above25ms=late,
        note="Tick-to-tick wall intervals, not total engine CPU cost; workload is not controlled."}
    file.CreateDir("zc_tick_budget")
    B.lastCapture="zc_tick_budget/"..os.date("%Y%m%d_%H%M%S")..".json"
    file.Write(B.lastCapture,util.TableToJSON(r,true))
end
local function allowed(p)return not IsValid(p) or p:IsAdmin()end
concommand.Add("zc_budget_status",function(p)
    if not allowed(p)then return end
    local r=B.Snapshot();file.CreateDir("zc_tick_budget")
    file.Write("zc_tick_budget/status.json",util.TableToJSON(r,true))
    local text=string.format("[TickBudget] %s enabled=%s budget=%.2fms queued=%d worst-worker=%.3fms; details in data/zc_tick_budget/status.json",r.version,tostring(r.enabled),r.budgetMs,r.queued,r.worstWorkMs)
    if IsValid(p)then p:PrintMessage(HUD_PRINTCONSOLE,text)else print(text)end
end, nil, "Admin: print the tick budget (details in data/zc_tick_budget/status.json).")
concommand.Add("zc_budget_capture",function(p,_,args)
    if not allowed(p)then return end
    local seconds=tonumber(args[1])or 60
    if seconds~=seconds then return end
    seconds=math.Clamp(seconds,10,120)
    B.capture={finish=SysTime()+seconds,frames={}}
end, nil, "Admin: capture tick budget frames: zc_budget_capture [10-120 seconds].")
