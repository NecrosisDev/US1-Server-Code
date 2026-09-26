-- On-demand SWEP/SENT probe. No wrapping or scanning while idle; never throttles combat.
if not SERVER then return end
ZCPerfPass2=ZCPerfPass2 or {}
local P=ZCPerfPass2
if P.active and P.Stop then P.Stop(true)end
P.Version="20260916.1"
local clock=SysTime
local weaponKeys={"Think","Step","CoreStep","WorldModel_Transform","ChangeGunPos","GetAdditionalValues","GetTrace","CloseAnim"}
local entityKeys={"Think","FuelThink","LifeThink","BurnThink","EatThink","DropThink","SpreadThink"}
local entityClasses={"vfire","vfire_ball","vfire_cluster","armor_base"}
local function allowed(p)return not IsValid(p) or p:IsAdmin()end
function P.Leave(generation,depth,ok,...)
    if generation~=P.generation then
        if not ok then error((...),0)end
        return ...
    end
    local f=P.stack[depth]
    local dt=math.max(0,clock()-f.start)
    P.depth=depth-1
    if P.active then
        local r=f.row;local own=math.max(0,dt-f.children)
        r.calls=r.calls+1;r.inclusive=r.inclusive+dt;r.exclusive=r.exclusive+own
        r.max=math.max(r.max,dt);if not ok then r.errors=r.errors+1 end
        P.frameLua=P.frameLua+own
        if depth>1 then local parent=P.stack[depth-1];parent.children=parent.children+dt end
    end
    if not ok then error((...),0)end
    return ...
end
function P.Wrap(t,key,prefix)
    local original=rawget(t,key)
    if not isfunction(original) or P.wrappers[original] then return end
    local info=debug.getinfo(original,"S")
    local label=prefix..key.." @ "..info.short_src..":"..info.linedefined
    local row=P.rows[label]
    if not row then row={calls=0,inclusive=0,exclusive=0,max=0,errors=0};P.rows[label]=row end
    local generation=P.generation
    local wrapper=function(...)
        if not P.active or generation~=P.generation then return original(...)end
        local depth=P.depth+1;P.depth=depth
        local f=P.stack[depth];if not f then f={};P.stack[depth]=f end
        f.children=0;f.row=row;f.start=clock()
        return P.Leave(generation,depth,pcall(original,...))
    end
    P.slots[#P.slots+1]={t=t,key=key,original=original,wrapper=wrapper}
    P.wrappers[wrapper]=true;t[key]=wrapper
end
function P.InstrumentEntity(e)
    if not P.active or not IsValid(e)then return end
    local keys
    if e:IsWeapon()then keys=weaponKeys
    elseif table.HasValue(entityClasses,e:GetClass())then keys=entityKeys end
    if not keys then return end
    for _,key in ipairs(keys)do P.Wrap(e:GetTable(),key,e:IsWeapon()and "SWEP."or "SENT.")end
end
local function population()
    local connected,alive=0,0
    for _,p in ipairs(player.GetHumans())do connected=connected+1;if p:Alive()then alive=alive+1 end end
    return {connected=connected,alive=alive,mode=zb and zb.CROUND,roundState=zb and zb.ROUND_STATE}
end
function P.Stop(save)
    if not P.active then return end
    P.active=false;hook.Remove("Tick","ZCPerfPass2");hook.Remove("OnEntityCreated","ZCPerfPass2")
    timer.Remove("ZCPerfPass2_Stop")
    local conflicts=0
    for i=#P.slots,1,-1 do
        local r=P.slots[i]
        if r.t[r.key]==r.wrapper then r.t[r.key]=r.original else conflicts=conflicts+1 end
    end
    local rows={}
    for label,r in pairs(P.rows)do
        if r.calls>0 then rows[#rows+1]={name=label,calls=r.calls,exclusiveMs=r.exclusive*1000,
            inclusiveMs=r.inclusive*1000,maxInclusiveMs=r.max*1000,errors=r.errors}end
    end
    table.sort(rows,function(a,b)return a.exclusiveMs>b.exclusiveMs end)
    local report={version=P.Version,time=os.time(),map=P.map,elapsed=clock()-P.started,
        tickInterval=engine.TickInterval(),startPopulation=P.startPopulation,endPopulation=population(),
        samples=P.samples,methods=rows,restoreConflicts=conflicts,
        note="Scoped inclusive/exclusive Lua timings. Unattributed time includes other Lua, engine work and sleep. Instrumentation adds overhead; not a capacity benchmark."}
    P.lastReport=report;P.slots={};P.wrappers={}
    if save then
        file.CreateDir("zc_perf_pass2")
        P.lastFile="zc_perf_pass2/"..os.date("%Y%m%d_%H%M%S")..".json"
        file.Write(P.lastFile,util.TableToJSON(report,true))
    end
    return report
end
function P.Tick()
    if not P.active then return end
    local now=clock()
    if now>P.populationAt then P.population=population();P.populationAt=now+1 end
    P.samples[#P.samples+1]={at=now-P.started,intervalMs=(now-P.lastTickAt)*1000,
        measuredLuaMs=P.frameLua*1000,population=P.population}
    P.lastTickAt=now;P.frameLua=0
end
function P.Start(seconds)
    if P.active then return false,"A capture is already running."end
    seconds=tonumber(seconds)or 20
    if seconds~=seconds then return false,"Invalid duration."end
    seconds=math.Clamp(seconds,5,60)
    P.generation=(P.generation or 0)+1;P.depth=0;P.stack={};P.rows={};P.slots={};P.wrappers={}
    P.samples={};P.frameLua=0;P.map=game.GetMap();P.startPopulation=population()
    P.population=P.startPopulation;P.populationAt=clock()+1;P.active=true
    for _,v in ipairs(weapons.GetList())do
        local t=weapons.GetStored(v.ClassName)
        if t then for _,key in ipairs(weaponKeys)do P.Wrap(t,key,"SWEP.")end end
    end
    for _,name in ipairs(entityClasses)do
        local entry=scripted_ents.GetStored(name)
        if entry then for _,key in ipairs(entityKeys)do P.Wrap(entry.t,key,"SENT.")end end
    end
    for _,e in ipairs(ents.GetAll())do P.InstrumentEntity(e)end
    P.started=clock();P.lastTickAt=P.started
    hook.Add("Tick","ZCPerfPass2",P.Tick)
    hook.Add("OnEntityCreated","ZCPerfPass2",function(e)
        local generation=P.generation
        timer.Simple(0,function()if P.active and generation==P.generation then P.InstrumentEntity(e)end end)
    end)
    timer.Create("ZCPerfPass2_Stop",seconds,1,function()P.Stop(true)end)
    return true
end
concommand.Add("zc_perf2_capture",function(p,_,args)
    if not allowed(p)then return end
    local ok,err=P.Start(args[1])
    local message=ok and "[Perf2] Capture started; report will be saved under data/zc_perf_pass2/."or tostring(err)
    if IsValid(p)then p:PrintMessage(HUD_PRINTCONSOLE,message)else print(message)end
end)
concommand.Add("zc_perf2_stop",function(p)if allowed(p)then P.Stop(true)end end)
hook.Add("ShutDown","ZCPerfPass2",function()P.Stop(false)end)
