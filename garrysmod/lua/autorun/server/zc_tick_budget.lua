-- Cooperative server maintenance budget. Combat callbacks are never queued here.
if not SERVER then return end
ZCTickBudget=ZCTickBudget or {}
local B=ZCTickBudget
B.Version="20260916.2"
B.enabled=CreateConVar("zc_tick_budget","1",FCVAR_ARCHIVE,"Budget equipment replication and secondary fire work",0,1)
B.limit=CreateConVar("zc_tick_budget_ms","2",FCVAR_ARCHIVE,"Shared soft work budget per server tick in milliseconds",0.25,5)
B.names={"weapons","attachments","armor","fire"}
B.queues=B.queues or {};B.byOwner=B.byOwner or {};B.stats=B.stats or {}
B.total=B.total or 0;B.cursor=B.cursor or 0;B.maxQueued=2048
for _,name in ipairs(B.names)do
    B.queues[name]=B.queues[name] or {first=1,last=0}
    B.stats[name]=B.stats[name] or {queued=0,merged=0,ran=0,totalMs=0,worstMs=0,worstAge=0,errors=0}
end
local clock=SysTime
local function valid(owner)return owner==B or IsValid(owner)end
function B.Queue(name,owner,key,fn,arg)
    if not B.enabled:GetBool() or not valid(owner) or not B.queues[name] then return false end
    local jobs=B.byOwner[owner]
    local id=name..":"..key;local old=jobs and jobs[id];local stats=B.stats[name]
    if old then old.fn=fn;old.arg=arg;stats.merged=stats.merged+1;return true end
    if B.total>=B.maxQueued then B.overflow=(B.overflow or 0)+1;return false end
    if not jobs then jobs={};B.byOwner[owner]=jobs end
    local now=CurTime();local phase=owner==B and 0 or (owner:EntIndex()%4)*engine.TickInterval()
    local job={owner=owner,id=id,key=key,fn=fn,arg=arg,firstAt=now,due=now+phase,name=name}
    jobs[id]=job;local q=B.queues[name];q.last=q.last+1;q[q.last]=job
    B.total=B.total+1;stats.queued=stats.queued+1
    B.highWater=math.max(B.highWater or 0,B.total)
    return true
end
function B.Cancel(owner)
    local jobs=B.byOwner[owner];if not jobs then return end
    for _,job in pairs(jobs)do job.cancelled=true end
    B.byOwner[owner]=nil
end
local function pop(q)
    local job=q[q.first];q[q.first]=nil;q.first=q.first+1;B.total=B.total-1
    if q.first>q.last then q.first=1;q.last=0 end
    local jobs=B.byOwner[job.owner]
    if jobs and jobs[job.id]==job then
        jobs[job.id]=nil;if next(jobs)==nil then B.byOwner[job.owner]=nil end
    end
    return job
end
function B.Step()
    local tick=engine.TickCount();if B.lastTick==tick then return end;B.lastTick=tick
    local start=clock();local gap=B.lastAt and start-B.lastAt or engine.TickInterval();B.lastAt=start
    B.lastGap=gap
    if B.Sample then B.Sample(gap)end
    if B.total==0 then B.lastWorkMs=0;return end
    -- Back off maintenance after a late tick, rather than queueing catch-up bursts.
    local allowance=B.limit:GetFloat()*(gap>engine.TickInterval()*1.5 and 0.5 or 1)/1000
    local attempts,idle=0,0;local now=CurTime()
    while attempts<128 and idle<#B.names do
        if clock()-start>=allowance then break end
        B.cursor=B.cursor%#B.names+1;local name=B.names[B.cursor];local q=B.queues[name]
        local head=q[q.first]
        if not head or (not head.cancelled and head.due>now)then idle=idle+1
        else
            idle=0;attempts=attempts+1;local job=pop(q)
            if not job.cancelled and valid(job.owner) and (name~="fire" or B.enabled:GetBool()) then
                local at=clock();local ok,err=xpcall(function()job.fn(job.owner,job.key,job.arg)end,debug.traceback)
                local ms=(clock()-at)*1000;local st=B.stats[name]
                st.ran=st.ran+1;st.totalMs=st.totalMs+ms;st.worstMs=math.max(st.worstMs,ms)
                st.worstAge=math.max(st.worstAge,now-job.firstAt)
                if not ok then
                    st.errors=st.errors+1;B.lastError=tostring(err)
                    if not B.errorAt or CurTime()-B.errorAt>30 then
                        B.errorAt=CurTime();file.CreateDir("zc_tick_budget")
                        file.Append("zc_tick_budget/errors.txt",os.date().." "..name.." "..B.lastError.."\n")
                    end
                end
            end
        end
    end
    B.lastWorkMs=(clock()-start)*1000
    B.worstWorkMs=math.max(B.worstWorkMs or 0,B.lastWorkMs)
    if B.lastWorkMs>allowance*1000 then B.overruns=(B.overruns or 0)+1 end
end
hook.Add("Tick","ZCityTickBudget",B.Step)
hook.Add("EntityRemoved","ZCityTickBudget_Cancel",function(e)B.Cancel(e)end)
include("zc_tick_budget/work.lua")
include("zc_tick_budget/monitor.lua")
