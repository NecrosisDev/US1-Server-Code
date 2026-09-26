-- Bounded incident diagnostic; no global dispatcher/timer/net replacements.
assert(SERVER)
assert(not ZCIncidentHookSample, "sample already active")
local id="ZCIncidentHooks20260919"
local started=SysTime()
local result={started=os.time(),map=game.GetMap(),rows={},frames={},states={}}
local installed={}
local wanted={Think=true,Tick=true,OrgThink=true,EntityTakeDamage=true,OnEntityCreated=true}
local function current(entry)
    if hook.GetULibTable then
        local events=hook.GetULibTable()[entry.event]
        local prio=events and events[entry.prio]
        local data=prio and prio[entry.name]
        return istable(data) and data.fn or data
    end
    local event=hook.GetTable()[entry.event]
    return event and event[entry.name]
end
local function add(entry,fn)
    if entry.prio~=nil then hook.Add(entry.event,entry.name,fn,entry.prio)
    else hook.Add(entry.event,entry.name,fn) end
end
local function record(row,start,...)
    local elapsed=(SysTime()-start)*1000
    row.calls=row.calls+1
    row.totalMs=row.totalMs+elapsed
    row.maxMs=math.max(row.maxMs,elapsed)
    return ...
end
local function install(event,name,fn,prio)
    if not isstring(name) or not isfunction(fn) then return end
    local info=debug.getinfo(fn,"S")
    local row={event=event,name=name,source=info.source,line=info.linedefined,calls=0,totalMs=0,maxMs=0}
    local entry={event=event,name=name,fn=fn,prio=prio}
    entry.wrapper=function(...) return record(row,SysTime(),fn(...)) end
    result.rows[#result.rows+1]=row
    installed[#installed+1]=entry
    add(entry,entry.wrapper)
end
local originals={}
if hook.GetULibTable then
    for event,prios in pairs(hook.GetULibTable()) do
        if wanted[event] then
            for prio,entries in pairs(prios) do
                for name,data in pairs(entries) do
                    originals[#originals+1]={event,name,istable(data) and data.fn or data,prio}
                end
            end
        end
    end
else
    for event,entries in pairs(hook.GetTable()) do
        if wanted[event] then
            for name,fn in pairs(entries) do originals[#originals+1]={event,name,fn} end
        end
    end
end
local function finish()
    if not ZCIncidentHookSample then return end
    result.elapsed=SysTime()-started
    result.restored=0
    result.concurrentChanges=0
    for _,entry in ipairs(installed) do
        if current(entry)==entry.wrapper then add(entry,entry.fn) result.restored=result.restored+1
        else result.concurrentChanges=result.concurrentChanges+1 end
    end
    hook.Remove("Think",id)
    hook.Remove("Tick",id)
    timer.Remove(id)
    file.Write("zc_incident_20260919/hooks_sample.json",util.TableToJSON(result,false))
    ZCIncidentHookSample=nil
    print("ZC_INCIDENT_HOOKS_DONE",result.elapsed,result.restored,result.concurrentChanges)
end
ZCIncidentHookSample={Finish=finish}
for _,entry in ipairs(originals) do install(unpack(entry)) end
local lastThink,lastTick,nextState=nil,nil,started
hook.Add("Think",id,function()
    local now=SysTime()
    if lastThink then result.frames[#result.frames+1]={"Think",(now-lastThink)*1000} end
    lastThink=now
end)
hook.Add("Tick",id,function()
    local now=SysTime()
    if lastTick then result.frames[#result.frames+1]={"Tick",(now-lastTick)*1000,physenv.GetLastSimulationTime()*1000} end
    lastTick=now
    if now>=nextState then
        nextState=now+1
        result.states[#result.states+1]={at=now-started,players=#player.GetHumans(),mode=zb.CROUND,round=zb.ROUND_STATE,entities=ents.GetCount()}
    end
    if now-started>=30 then finish() end
end)
timer.Create(id,45,1,finish)
print("ZC_INCIDENT_HOOKS_START",#installed)
