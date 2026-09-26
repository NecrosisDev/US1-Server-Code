-- Passive, bounded incident measurement. Does not replace game callbacks.
assert(SERVER)
local id = "ZCCapacityObserve20260919"
assert(not ZCIncidentObserve or not ZCIncidentObserve.active, "capture already active")
local label = assert(ZCIncidentObserveLabel, "missing capture label")
local start, last = SysTime(), nil
local r = {label=label, started=os.time(), map=game.GetMap(), tick=engine.TickInterval(),
    frames={}, thinkFrames={}, states={}, netBefore=ZCNETOPT and table.Copy(ZCNETOPT.sent),
    skippedBefore=ZCNETOPT and table.Copy(ZCNETOPT.skip), active=true,
    woundBefore=ZCWoundQueue and table.Copy(ZCWoundQueue.Stats), woundVersion=ZCWoundQueue and ZCWoundQueue.Version}
ZCIncidentObserve = r
local nextState = start
local function finish(reason)
    if not r.active then return end
    r.active=false
    hook.Remove("Tick", id)
    hook.Remove("Think", id)
    timer.Remove(id)
    r.elapsed=SysTime()-start
    r.finished=os.time()
    r.reason=reason
    r.netAfter=ZCNETOPT and table.Copy(ZCNETOPT.sent)
    r.skippedAfter=ZCNETOPT and table.Copy(ZCNETOPT.skip)
    r.woundAfter=ZCWoundQueue and table.Copy(ZCWoundQueue.Stats)
    file.CreateDir("zc_incident_20260919")
    file.Write("zc_incident_20260919/"..label..".json",util.TableToJSON(r,false))
    print("ZC_INCIDENT_CAPTURE_COMPLETE",label,#r.frames,r.elapsed)
end
r.finish=finish
local lastThink
hook.Add("Think",id,function()
    local now=SysTime()
    if lastThink then r.thinkFrames[#r.thinkFrames+1]=(now-lastThink)*1000 end
    lastThink=now
end)
hook.Add("Tick",id,function()
    local now=SysTime()
    if last then r.frames[#r.frames+1]={now-start,(now-last)*1000,physenv.GetLastSimulationTime()*1000} end
    last=now
    if now>=nextState then
        nextState=now+1
        local players=player.GetHumans()
        local alive,organisms=0,0
        for _ in pairs(hg.organism.list) do organisms=organisms+1 end
        for _,ply in ipairs(players) do if ply:Alive() then alive=alive+1 end end
        r.states[#r.states+1]={at=now-start,players=#players,alive=alive,organisms=organisms,entities=ents.GetCount(),
            mode=zb and zb.CROUND,round=zb and zb.ROUND_STATE,heapKB=collectgarbage("count"),
            addonProfiler=ZCPERF and ZCPERF.wrapped and true or false}
    end
    if now-start>=30 or #r.frames>=10000 then r.finish=nil; finish("complete") end
end)
timer.Create(id,45,1,function()r.finish=nil; finish("watchdog")end)
print("ZC_INCIDENT_CAPTURE_START",label,r.map,#player.GetHumans())
