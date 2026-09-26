assert(SERVER)
local r={time=os.time(),map=game.GetMap(),players=#player.GetHumans(),convars={},hooks={},timers={}}
local function info(fn)
    if not isfunction(fn) then return {kind=type(fn)} end
    local d=debug.getinfo(fn,"S")
    return {source=d.source,line=d.linedefined,last=d.lastlinedefined}
end
for _,name in ipairs({"zc_orgsched","zc_orgsched_interval","zc_governor","zc_governor_freeze_props","zc_tick_budget","zc_tick_budget_ms","zc_perf","zc_perf_auto","zc_wound_net_queue"}) do
    local cv=GetConVar(name)
    r.convars[name]=cv and cv:GetString() or "MISSING"
end
for event,rows in pairs(hook.GetTable()) do
    for name,fn in pairs(rows) do
        if isstring(name) and (name:find("TickGov",1,true) or name:find("ZCityTickBudget",1,true) or name=="homigrad-organism" or name=="ZC_WoundNetFlush") then
            r.hooks[event.."/"..name]=info(fn)
        end
    end
end
for _,name in ipairs({"zc_orgsched_sync","TickGov_Evaluate","TickGov_ThawScan"}) do
    r.timers[name]={exists=timer.Exists(name),left=timer.TimeLeft(name),reps=timer.RepsLeft(name)}
end
local em=FindMetaTable("Entity")
r.sender=info(em.SendNetVar)
r.setter=info(em.SetNetVar)
local B=ZCTickBudget
if B then
    r.budget={version=B.Version,hookMatches=hook.GetTable().Tick.ZCityTickBudget==B.Step,lastTick=B.lastTick,currentTick=engine.TickCount(),lastAt=B.lastAt,now=SysTime(),total=B.total,stats=table.Copy(B.stats),lastError=B.lastError,
        install=info(B.Install),senderWrapperActive=B.entitySender and em.SendNetVar==B.entitySender.wrapper,
        senderWrapper=B.entitySender and info(B.entitySender.wrapper),senderOriginal=B.entitySender and info(B.entitySender.original)}
end
if ZCORGSCHED then
    local count,fresh,oldest=0,0,0
    local now=SysTime()
    for owner,org in pairs(hg.organism.list) do
        count=count+1
        if org.zc_lastThink then
            local age=now-org.zc_lastThink
            if age<0.5 then fresh=fresh+1 end
            oldest=math.max(oldest,age)
        end
    end
    r.organism={active=hook.GetTable().Think["homigrad-organism"]==ZCORGSCHED.mine,mine=info(ZCORGSCHED.mine),original=info(ZCORGSCHED.orig),count=count,fresh=fresh,oldest=oldest}
end
r.governor=TickGov and {frozen=#TickGov.frozen,frozenTotal=TickGov.frozenTotal,sweptTotal=TickGov.sweptTotal}
file.Write("zc_incident_20260919/module_state.json",util.TableToJSON(r,true))
print("ZC_MODULE_STATE",r.time,r.organism and r.organism.active,r.budget and r.budget.senderWrapperActive)
