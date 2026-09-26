-- Bounded observer hooks. Existing callbacks and dispatchers are never replaced.
assert(SERVER and hook.GetULibTable, "requires current ULib priority hooks")
local label=assert(ZCLuaCostLabel)
local prefix="ZCLuaCost20260919_"
local started=SysTime()
local r={label=label,started=os.time(),map=game.GetMap(),events={},states={},elapsed=0}
local events={"Org Think","Think","PlayerPostThink","SetupMove","StartCommand","Move","FinishMove","PlayerTick"}
local function finish()
    for _,event in ipairs(events) do
        hook.Remove(event,prefix.."before")
        hook.Remove(event,prefix.."after")
    end
    hook.Remove("Tick",prefix.."finish")
    timer.Remove(prefix.."watchdog")
    r.elapsed=SysTime()-started
    for _,row in pairs(r.events) do
        if row.open then row.unmatched=row.unmatched+1 end
        row.open=nil
    end
    file.Write("zc_incident_20260919/"..label..".json",util.TableToJSON(r,false))
    print("ZC_LUA_COST_COMPLETE",label,r.elapsed)
end
for _,event in ipairs(events) do
    assert(not (hook.GetTable()[event] or {})[prefix.."before"],"observer already installed")
    local row={started=0,completed=0,unmatched=0,totalMs=0,maxMs=0,handlers={}}
    r.events[event]=row
    for name,fn in pairs(hook.GetTable()[event] or {}) do
        if isfunction(fn) then
            local d=debug.getinfo(fn,"S")
            row.handlers[#row.handlers+1]={name=tostring(name),source=d.source,line=d.linedefined}
        end
    end
    -- No listed event is intentionally recursive. Re-entry/short circuits are
    -- counted as incomplete rather than treating the idle gap as execution time.
    hook.Add(event,prefix.."before",function()
        if row.open then row.unmatched=row.unmatched+1 end
        row.started=row.started+1
        row.open=SysTime()
    end,HOOK_MONITOR_HIGH)
    hook.Add(event,prefix.."after",function()
        local t=row.open
        row.open=nil
        if not t then return end
        local ms=(SysTime()-t)*1000
        row.completed=row.completed+1
        row.totalMs=row.totalMs+ms
        row.maxMs=math.max(row.maxMs,ms)
    end,HOOK_MONITOR_LOW)
end
local nextState=started
hook.Add("Tick",prefix.."finish",function()
    local now=SysTime()
    if now>=nextState then
        nextState=now+1
        local humans=player.GetHumans()
        local alive=0
        for _,ply in ipairs(humans) do if ply:Alive() then alive=alive+1 end end
        r.states[#r.states+1]={at=now-started,players=#humans,alive=alive,organisms=table.Count(hg.organism.list),entities=ents.GetCount(),mode=zb.CROUND,round=zb.ROUND_STATE}
    end
    if now-started>=20 then finish() end
end)
timer.Create(prefix.."watchdog",35,1,finish)
