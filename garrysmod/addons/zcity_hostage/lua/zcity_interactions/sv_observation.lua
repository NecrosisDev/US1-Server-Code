-- Private adapter to the installed justice observer. Never writes karma,
-- organs or network fields, and never retries an already executed effect.
local I=ZCityInteractions
local observed=setmetatable({}, {__mode="k"})
local function pack(...) return {n=select('#',...),...} end
local function observer()
    local r=ZCJusticeV3Integration
    if r and r.enabled and r.Safe and r.Prepare and r.Scope and r.Finish and r.ControlAccepted and r.ContactObserved then return r end
end
local function scoped(r,pending,fn)
    if not pending or not r or not r.enabled then return fn() end
    local called,result,failure
    local function once()
        if called then
            if result then return unpack(result,1,result.n) end
            return
        end
        called=true
        local values=pack(pcall(fn))
        if not values[1] then failure=values[2];error(failure,0) end
        result={n=values.n-1}
        for index=2,values.n do result[index-1]=values[index] end
        return unpack(result,1,result.n)
    end
    local ok,err=pcall(r.Scope,r,pending,once)
    if not ok and not failure then
        ErrorNoHalt("[Interactions] Observer scope failed: "..tostring(err).."\n")
        -- A partially unwound diagnostic scope must not own later effects.
        if r.Issue then r:Safe(r.Issue,"interaction_scope",tostring(err)) end
    end
    if failure then error(failure,0) end
    if not called then return fn() end
    return unpack(result,1,result.n)
end
function I.EndObservedControl(s)
    local record=observed[s]
    if not record then return end
    observed[s]=nil
    local r,pending=record.observer,record.pending
    pending.hold_open=false
    r:Safe(function(audit)
        local root=audit.adjudicator.roots[record.root]
        if root then audit.adjudicator:release(record.root,math.max(audit:Clock(),root.last)) end
        audit:Finish(pending)
    end)
end
local function current(s,record)
    local r=record.observer
    if s.done or not r.enabled or r~=ZCJusticeV3Integration or record.pending.closed
        or not IsValid(s.a) or not IsValid(record.target) or not s.a:Alive() or not record.target:Alive()
        or record.target.organism~=record.organism or I.Session(s.a)~=s or I.Session(record.target)~=s then return false end
    return r:Safe(function(audit)
        local source,target=audit:Actor(s.a),audit:Actor(record.target)
        return source and target and source.life==record.sourceLife and target.life==record.targetLife
            and audit.observer.round==record.match
    end)==true
end
function I.StartObservedControl(s,method,kind)
    if s.observationAttempted or s.done or s.phase=="attempt" then return end
    s.observationAttempted=true
    local target=IsValid(s.originalVictim) and s.originalVictim or s.v
    if not IsValid(target) or not target:IsPlayer() or not target:Alive() then return end
    local r=observer();if not r then return end
    local pending=r:Safe(r.Prepare,s.a,method,"paired_interaction")
    if not pending then return end
    pending.hold_open=true
    local life
    scoped(r,pending,function() life=r:Safe(r.ControlAccepted,pending,target,kind,"PAIRED_INTERACTION") end)
    if not life then pending.hold_open=false;r:Safe(r.Finish,pending);return end
    observed[s]={observer=r,pending=pending,target=target,organism=target.organism,
        sourceLife=pending.action.life,targetLife=life,match=pending.action.match,
        root=pending.action.id.."/"..life,seen=CurTime(),last=CurTime()}
end
function I.StepObservedControl(s)
    local record=observed[s];if not record then return end
    record.seen=CurTime()
    if CurTime()-record.last<.25 then return end
    if not current(s,record) then I.EndObservedControl(s);return end
    record.last=CurTime()
    record.observer:Safe(function(r)
        local root=r.adjudicator.roots[record.root]
        if root then r.adjudicator:heartbeat(record.root,math.max(r:Clock(),root.last),true) end
    end)
end
function I.WithObservedDamage(s,attacker,target,fn)
    local r=observer();if not r then return fn() end
    local record=observed[s]
    local pending=record and record.observer==r and current(s,record) and record.pending.source==attacker and record.pending
    pending=pending or r:Safe(r.Prepare,attacker,"dangerous_melee","paired_contact")
    return scoped(r,pending,function()
        if pending then r:Safe(r.ContactObserved,pending,target) end
        return fn()
    end)
end
function I.ObserveChokeInput(s,org)
    local record=observed[s]
    if not record or org~=record.organism or not current(s,record) then return end
    local r=record.observer
    if not r.MedicalChokeInput or record.pending.action.method~="choke" then return end
    scoped(r,record.pending,function()
        r:Safe(r.MedicalChokeInput,org,record.pending,org.choking and true or false)
    end)
end
local nextCheck=0
hook.Add("Think","ZCityInteractions.ObservationLifetime",function()
    if CurTime()<nextCheck then return end
    nextCheck=CurTime()+.25
    for s,record in pairs(observed) do
        if CurTime()-record.seen>1 or not current(s,record) then I.EndObservedControl(s) end
    end
end)
