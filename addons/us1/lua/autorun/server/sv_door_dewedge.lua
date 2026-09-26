-- DeWedge 3.0.0: bounded, event-driven door motor relief (server only).
-- Replaces lua/autorun/server/sv_door_dewedge.lua. See README before first upgrade.
if not SERVER then return end
local previous = ZC_DEWEDGE
if previous and previous.Shutdown then previous.Shutdown() end
local API = {Version = "3.0.0"}
ZC_DEWEDGE = API
local enabled = CreateConVar("zc_dewedge", "1", FCVAR_ARCHIVE, "Monitor commanded prop doors for a physical obstruction", 0, 1)
local stall = CreateConVar("zc_dewedge_stall", "0.4", FCVAR_ARCHIVE, "Seconds without angular progress before checking the native blocker", 0.2, 2)
local verbose = CreateConVar("zc_dewedge_verbose", "0", FCVAR_ARCHIVE, "Print bounded door recovery diagnostics", 0, 1)
local INTERVAL, WATCH_LIMIT, MAX_ACTIVE = 0.1, 12, 128
local BACKOFF_TIME, BACKOFF_DEGREES, COOLDOWN = 0.3, 6, 3
local active = {}
local parked = previous and previous.Parked or setmetatable({}, {__mode="k"})
local nextAttempt = previous and previous.NextAttempt or setmetatable({}, {__mode="k"})
API.Parked, API.NextAttempt = parked, nextAttempt
local internal, timers = {}, {}
local alive, serial, count = true, 0, 0
local bucketAt, bucketUsed, nextLog = 0, 0, 0
local stats = {checks=0, starts=0, attempts=0, parked=0, relieved=0, unverified=0, cancelled=0, unsupported=0, limited=0, errors=0, seconds=0}
local function finite(x) return type(x)=="number" and x==x and math.abs(x)<math.huge end
local function isDoor(e) return IsValid(e) and e:GetClass()=="prop_door_rotating" end
local function angleCopy(a) return Angle(a.p,a.y,a.r) end
local function delta(a,b)
    return math.max(math.abs(math.AngleDifference(a.p,b.p)),math.abs(math.AngleDifference(a.y,b.y)),math.abs(math.AngleDifference(a.r,b.r)))
end
local function goal(d)
    local g=d:GetInternalVariable("m_angGoal")
    if isvector(g) and finite(g.x) and finite(g.y) and finite(g.z) then return Angle(g.x,g.y,g.z) end
    if isangle(g) and finite(g.p) and finite(g.y) and finite(g.r) then return angleCopy(g) end
end
local function moving(d) local n=d:GetInternalVariable("m_eDoorState"); return n==1 or n==3,n end
local function note(message)
    if not verbose:GetBool() or CurTime()<nextLog then return end
    nextLog=CurTime()+1
    print("[DeWedge] "..message)
end
local function cancel(d)
    local s=active[d]
    if s then timer.Remove(s.timer); timers[s.timer]=nil; active[d]=nil; count=count-1 end
end
local function valid(d,s)
    return alive and ZC_DEWEDGE==API and enabled:GetBool() and isDoor(d) and active[d]==s
end
local function clear()
    for id in pairs(timers) do timer.Remove(id) end
    active, timers, internal = {}, {}, {}
    count=0
end
function API.Shutdown()
    alive=false
    clear()
    cvars.RemoveChangeCallback("zc_dewedge", "DoorDewedge_Enable")
end
local function later(d,s,delay,fn)
    timer.Remove(s.timer)
    timers[s.timer]=true
    timer.Create(s.timer,delay,1,function()
        timers[s.timer]=nil
        if not valid(d,s) then if active[d]==s then cancel(d) end return end
        local started=SysTime()
        local ok,err=pcall(fn,d,s)
        stats.seconds=stats.seconds+math.max(0,SysTime()-started)
        if not ok then stats.errors=stats.errors+1; note("check failed: "..tostring(err)); cancel(d) end
    end)
end
-- Require the engine's actual blocker, not just a prop somewhere in a door AABB.
local classes={prop_ragdoll=true,prop_physics=true,prop_physics_multiplayer=true,prop_physics_override=true}
local function blocker(d)
    local e=d:GetInternalVariable("m_hBlocker")
    if not IsValid(e) or not classes[e:GetClass()] or not e:IsSolid() then return nil end
    local da,db=d:WorldSpaceAABB(); local ea,eb=e:WorldSpaceAABB()
    if da.x>eb.x+4 or db.x<ea.x-4 or da.y>eb.y+4 or db.y<ea.y-4 or da.z>eb.z+4 or db.z<ea.z-4 then return nil end
    for i=0,math.min(e:GetPhysicsObjectCount(),32)-1 do
        local p=e:GetPhysicsObjectNum(i)
        if IsValid(p) and p:IsCollisionEnabled() then return e end
    end
end
-- Mirror CPropDoorRotating::DoorStop: zero local angular velocity and cancel
-- the native move-completion time. Ajar keeps Open/Close/player Use operable;
-- FirstBlocked prevents a stale OnEndBlocked from resuming the old motor goal.
-- Never change collisions, motion flags, positions, damage, locks or map speed.
local function park(d)
    local old={m_flMoveDoneTime=d:GetInternalVariable("m_flMoveDoneTime"),m_eDoorState=d:GetInternalVariable("m_eDoorState"),m_bFirstBlocked=d:GetInternalVariable("m_bFirstBlocked")}
    if not finite(old.m_flMoveDoneTime) or not finite(old.m_eDoorState) or type(old.m_bFirstBlocked)~="boolean" then
        stats.unsupported=stats.unsupported+1; return false
    end
    local values={m_flMoveDoneTime=-1,m_eDoorState=4,m_bFirstBlocked=true}
    local changed={}
    for _,k in ipairs({"m_flMoveDoneTime","m_eDoorState","m_bFirstBlocked"}) do
        if not d:SetSaveValue(k,values[k]) then
            for _,restore in ipairs(changed) do d:SetSaveValue(restore,old[restore]) end
            stats.unsupported=stats.unsupported+1; return false
        end
        changed[#changed+1]=k
    end
    d:SetLocalAngularVelocity(Angle(0,0,0))
    parked[d]=true
    return d:GetInternalVariable("m_flMoveDoneTime")==-1 and d:GetInternalVariable("m_eDoorState")==4
end
local function input(d,s,command)
    -- Called only from our timer, outside physics/input hooks. Input is immediate
    -- so cancellation cannot leave an unowned Fire event in the engine I/O queue.
    internal[d]=command:lower()
    local ok,err=pcall(d.Input,d,command,d,d)
    internal[d]=nil
    if not ok then error(err) end
    return valid(d,s)
end
local function finishPark(d,s)
    if not park(d) then cancel(d); return end
    local at=angleCopy(d:GetLocalAngles())
    later(d,s,INTERVAL,function(ent,session)
        local velocity=ent:GetLocalAngularVelocity()
        if ent:GetInternalVariable("m_eDoorState")==4 and ent:GetInternalVariable("m_flMoveDoneTime")==-1
            and delta(ent:GetLocalAngles(),at)<0.05 and delta(velocity,Angle(0,0,0))<0.05 then
            stats.parked=stats.parked+1
            note("motor parked on door "..ent:EntIndex())
        else stats.unverified=stats.unverified+1 end
        cancel(ent)
    end)
end
local function recover(d,s,state)
    local now=CurTime()
    if now-bucketAt>=1 then bucketAt=now; bucketUsed=0 end
    if bucketUsed>=8 then stats.limited=stats.limited+1; cancel(d); return end
    bucketUsed=bucketUsed+1
    stats.attempts=stats.attempts+1
    if now<(nextAttempt[d] or 0) or d:GetInternalVariable("m_bLocked")==true then
        nextAttempt[d]=now+COOLDOWN
        finishPark(d,s); return
    end
    nextAttempt[d]=now+COOLDOWN
    if not park(d) then cancel(d); return end
    s.phase="relief"
    s.reliefStart=now
    s.reliefAngle=angleCopy(d:GetLocalAngles())
    s.expected=state==1 and 3 or 1
    if not input(d,s,state==1 and "Close" or "Open") then return end
    local function verify(ent,session)
        local isMoving,current=moving(ent)
        if current==0 or current==2 then
            stats.relieved=stats.relieved+1; parked[ent]=nil; cancel(ent); return
        end
        if isMoving and current~=session.expected then
            stats.cancelled=stats.cancelled+1; parked[ent]=nil; cancel(ent); return
        end
        if CurTime()-session.reliefStart>=BACKOFF_TIME or delta(ent:GetLocalAngles(),session.reliefAngle)>=BACKOFF_DEGREES then
            finishPark(ent,session); return
        end
        later(ent,session,INTERVAL,verify)
    end
    later(d,s,INTERVAL,verify)
end
local sample
sample=function(d,s)
    stats.checks=stats.checks+1
    local now=CurTime(); local isMoving,state=moving(d)
    if not isMoving then
        -- PlayerUse/inputs can precede the engine's handle animation.
        if now-s.started<0.8 and not s.sawMotion then later(d,s,INTERVAL,sample) else cancel(d) end
        return
    end
    s.sawMotion=true
    local angle=d:GetLocalAngles()
    local destination=goal(d)
    local speed=d:GetInternalVariable("m_flSpeed")
    local epsilon=finite(speed) and math.max(0.0001,math.min(0.025,math.abs(speed)*INTERVAL*0.25)) or 0.025
    if state~=s.state or (destination and (not s.goal or delta(destination,s.goal)>0.01)) then
        s.state=state; s.angle=angleCopy(angle); s.progress=now
        s.goal=destination; s.best=destination and delta(angle,destination) or nil
    elseif destination then
        local remaining=delta(angle,destination)
        if not s.best or remaining<s.best-epsilon then s.best=remaining; s.progress=now end
    elseif delta(angle,s.angle)>=epsilon then
        s.angle=angleCopy(angle); s.progress=now
    end
    if now-s.progress>=stall:GetFloat() and blocker(d) then recover(d,s,state); return end
    if now-s.started>=WATCH_LIMIT then cancel(d); return end
    later(d,s,INTERVAL,sample)
end
local function start(d,reason,external)
    if not alive or not enabled:GetBool() or not isDoor(d) then return end
    local old=active[d]
    if old and (not external or (old.phase=="watch" and old.reason==reason)) then return end
    if old then stats.cancelled=stats.cancelled+1; cancel(d) end
    if count>=MAX_ACTIVE then stats.limited=stats.limited+1; return end
    serial=serial+1
    local s={timer="ZC_DeWedge_"..serial,phase="watch",reason=reason,started=CurTime(),progress=CurTime(),state=d:GetInternalVariable("m_eDoorState"),angle=angleCopy(d:GetLocalAngles())}
    active[d]=s; count=count+1; stats.starts=stats.starts+1
    later(d,s,INTERVAL,sample)
end
local commands={open=true,close=true,toggle=true,use=true,openawayfrom=true,movetorotationdistance=true,setspeed=true,setrotationdistance=true}
hook.Add("PlayerUse","DoorDewedge_Use",function(_,d) start(d,"use",false) end)
hook.Add("AcceptInput","DoorDewedge_Input",function(d,command,activator,caller)
    if not isDoor(d) then return end
    command=string.lower(command or "")
    if internal[d]==command and activator==d and caller==d then return end
    if commands[command] then
        -- Toggle ignores AJAR in the native prop-door handler. Translate only
        -- a motor parked by us, deferred and cancellable like every recovery.
        local translate=parked[d] and command=="toggle" and d:GetInternalVariable("m_eDoorState")==4
        parked[d]=nil
        start(d,command,true)
        local s=active[d]
        if translate and s then later(d,s,0.01,function(ent,session)
            if ent:GetInternalVariable("m_bLocked")==true then cancel(ent); return end
            if ent:GetInternalVariable("m_eDoorState")==4 and input(ent,session,"Open") then
                session.progress=CurTime(); session.angle=angleCopy(ent:GetLocalAngles())
                later(ent,session,INTERVAL,sample)
            else cancel(ent) end
        end) end
    elseif command=="lock" or command=="stop" then
        stats.cancelled=stats.cancelled+(active[d] and 1 or 0); cancel(d)
    end
end)
-- Native auto-closing/linked doors can damage a blocker without a Lua input.
-- This hook only starts a timer; it never changes physics or damage in a callback.
hook.Add("EntityTakeDamage","DoorDewedge_Damage",function(_,damage)
    start(damage:GetInflictor(),"damage",false)
    start(damage:GetAttacker(),"damage",false)
end)
hook.Add("EntityRemoved","DoorDewedge_Removed",function(d) cancel(d); parked[d]=nil; nextAttempt[d]=nil end)
hook.Add("PreCleanupMap","DoorDewedge_Cleanup",function()
    clear()
    for d in pairs(parked) do parked[d]=nil end
    for d in pairs(nextAttempt) do nextAttempt[d]=nil end
end)
cvars.AddChangeCallback("zc_dewedge",function() if not enabled:GetBool() then clear() end end,"DoorDewedge_Enable")
function API.Status()
    local out=table.Copy(stats)
    out.version=API.Version; out.enabled=enabled:GetBool(); out.active=count
    return out
end
local function reply(p,text) if IsValid(p) then p:ChatPrint(text) else print(text) end end
concommand.Add("zc_dewedge_status",function(p)
    if IsValid(p) and not p:IsSuperAdmin() then return end
    reply(p,string.format("[DeWedge] %s enabled=%s active=%d checks=%d attempts=%d parked=%d reached-end=%d unverified=%d cancelled=%d unsupported=%d limited=%d errors=%d check-ms=%.2f",API.Version,tostring(enabled:GetBool()),count,stats.checks,stats.attempts,stats.parked,stats.relieved,stats.unverified,stats.cancelled,stats.unsupported,stats.limited,stats.errors,stats.seconds*1000))
end, nil, "Superadmin: print DeWedge door-motor relief counters.")
concommand.Add("zc_dewedge_debug",function(p)
    if not IsValid(p) then print("[DeWedge] Run in-game aiming at a door."); return end
    if not p:IsSuperAdmin() then return end
    local d=p:GetEyeTrace().Entity
    if not isDoor(d) then reply(p,"[DeWedge] Aim at a prop_door_rotating."); return end
    local b=blocker(d); local s=active[d]
    reply(p,string.format("[DeWedge] door=%d state=%s phase=%s blocker=%s motor-stop-fields=%s",d:EntIndex(),tostring(d:GetInternalVariable("m_eDoorState")),s and s.phase or "idle",b and (b:GetClass().." #"..b:EntIndex()) or "none",tostring(finite(d:GetInternalVariable("m_flMoveDoneTime")))))
end, nil, "Superadmin: print DeWedge state for the door you aim at.")
print("[DeWedge] v"..API.Version.." loaded - bounded native-blocker detection and motor relief")
