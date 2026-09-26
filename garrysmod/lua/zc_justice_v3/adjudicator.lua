-- Server-independent decision engine. Inputs are copied data from trusted adapters.
-- This module has no engine, networking, persistence, damage or balance side effects.
return function(U,C,P)
    local A={}; A.__index=A
    local ordinary={ordinary_unarmed=true,kick_catch=true}
    local serious={firearm=true,dangerous_melee=true,explosive=true,hazardous_throw=true,
        choke=true,restrict=true,taser=true,forced_exposure=true}
    local allowed_relation={protected=true,enemy=true,exempt=true,unsupported=true}
    function A.new()
        return setmetatable({actions={},action_count=0,effects={},roots={},pending={},minor={},
            budgets={},buckets={},controls={},sequence=0,batch=nil,last_time=0,gaps={}},A)
    end
    function A:gap(code,ref)
        self.gaps[code]=(self.gaps[code] or 0)+1
        return {status="UNRESOLVED",reason=code,reference=ref,accountable=false,force="NONE"}
    end
    function A:end_batch()
        for _,r in ipairs(self.pending) do self.roots[r.id]=r end
        self.pending={}
    end
    function A:start_batch(batch,time)
        U.id(batch);U.number(time,0,1e12,"time")
        assert(time>=self.last_time,"nonmonotonic simulation time")
        if self.batch~=batch then self:end_batch();self.batch=batch end
        self.last_time=time
    end
    local function root_active(r,now)
        if r.closed and now>=r.closed then return false end
        if r.continuous and r.heartbeat and now<=r.heartbeat+C.heartbeat_seconds then return true end
        return now<=r.last+(r.severity=="minor" and C.minor_seconds or C.serious_seconds)
    end
    function A:permission(a,t)
        -- IDs include the life. A respawn never inherits these permissions.
        local selected=nil
        for _,id in ipairs(U.keys(self.roots)) do
            local r=self.roots[id]
            if r.match==a.match and r.source==t.life and root_active(r,a.time) then
                if r.victim==a.life and r.direct_observed then
                    if r.severity=="serious" then return "SERIOUS",r end
                    if ordinary[a.method] and (a.method~="kick_catch" or a.verified_counter)
                        and not a.hazardous_geometry and not r.counter_used then selected=r end
                elseif r.severity=="serious" and r.witnesses[a.life]
                    and (r.helpers[a.life] or a.time<=r.witnesses[a.life]+C.witness_seconds) then
                    return "INTERVENTION",r
                end
            end
        end
        if selected then return "LIMITED",selected end
        return "NONE",nil
    end
    function A:classify(a,t)
        assert(allowed_relation[t.relation],"unknown relation")
        local d={status="DETERMINED",force="NONE",reason="WRONGFUL",accountable=false,
            relation=t.relation,source=a.account,source_life=a.life,target=t.account,target_life=t.life,
            action=a.id,policy=a.policy,match=a.match,karma=t.karma,traitor_pair=t.traitor_pair==true}
        if a.account and a.account==t.account then d.reason="SELF";return d end
        if a.system then d.reason="SYSTEM_EFFECT";return d end
        if not a.account or not a.source_known then
            d.status="UNRESOLVED";d.reason="UNKNOWN_SOURCE";return d
        end
        local force,r=self:permission(a,t)
        d.force=force; d.root=r and r.id
        -- First classify physical justification; price relation is independent.
        if force~="NONE" then d.reason="DEFENCE_"..force end
        if a.authorized==true then d.force="AUTHORIZED";d.reason="MODE_AUTHORIZED" end
        if not a.scored or t.relation=="exempt" or a.phase_exempt or t.phase_exempt then
            d.reason="MODE_EXEMPT";return d
        end
        if t.relation=="enemy" then d.reason="ORDINARY_ENEMY";return d end
        if d.force~="NONE" then return d end
        if a.context_complete~=true or t.context_complete==false then
            d.status="UNRESOLVED";d.reason="UNRESOLVED_CONTEXT";return d
        end
        if t.relation=="unsupported" or a.profile_known~=true then
            d.status="UNRESOLVED";d.reason="UNSUPPORTED_PROFILE";return d
        end
        d.accountable=true
        return d
    end
    function A:commit(input)
        local a=U.copy(input)
        U.id(a.id);U.id(a.match);U.id(a.life);U.id(a.policy);U.id(a.batch)
        if a.account then U.id(a.account) end
        U.number(a.time,0,1e12,"time");U.integer(a.seq,1,9007199254740991,"sequence")
        local sig=U.canonical(a)
        local prior=self.actions[a.id]
        if prior then assert(prior.signature==sig,"conflicting action replay");return U.copy(prior.decisions) end
        assert(a.seq>self.sequence,"out-of-order commitment")
        assert(a.committed==true and a.cancelled~=true,"uncommitted operation")
        if self.action_count>=C.capacity.actions then return nil,self:gap("ACTION_CAPACITY",a.id) end
        self:start_batch(a.batch,a.time)
        assert(type(a.targets)=="table","targets required")
        a.decisions={};a.signature=sig;a.effects={};a.completed=false
        self.sequence=a.seq;self.action_count=self.action_count+1
        for _,tid in ipairs(U.keys(a.targets)) do
            local t=a.targets[tid];assert(tid==t.life,"receiver ID mismatch")
            U.id(t.life);U.id(t.account);U.number(t.karma,-60,120,"target karma")
            local d=self:classify(a,t);a.decisions[tid]=d
            if d.root then
                local r=self.roots[d.root]
                if d.force=="LIMITED" then r.counter_used=true end
                if d.force=="INTERVENTION" then r.helpers[a.life]=true end
            end
        end
        self.actions[a.id]=a
        for _,tid in ipairs(U.keys(a.targets)) do
            local t=a.targets[tid];local d=a.decisions[tid]
            if a.source_known and not a.system and not a.passive and d.force=="NONE"
                and t.directed==true and t.observation_complete==true and t.observed_source==true
                and a.profile_known and serious[a.method] and a.context_complete==true then
                self:add_root(a,t,"serious")
            end
        end
        return U.copy(a.decisions)
    end
    function A:add_root(a,t,severity)
        local id=a.id.."/"..t.life
        if #id>192 then id="root:"..a.seq..":"..t.life end
        if self.roots[id] then return self.roots[id] end
        for _,r in ipairs(self.pending) do if r.id==id then return r end end
        local witnesses={}
        for life,w in pairs(t.witnesses or {}) do
            U.id(life)
            if w.visible==true and w.participating==true and U.finite(w.distance)
                and w.distance<=C.witness_distance and w.distance>=0 then witnesses[life]=a.time end
        end
        local r={id=id,action=a.id,match=a.match,source=a.life,victim=t.life,
            direct_observed=t.observed_source==true,severity=severity,last=a.time,
            witnesses=witnesses,helpers={},source_account=a.account,counter_used=false}
        self.pending[#self.pending+1]=r;return r
    end
    -- A later trace enriches source observation without rewriting the prior-state verdict.
    -- In incomplete capture it remains candidate evidence, not a certified permission.
    function A:observe(action,life,observation)
        local a=assert(self.actions[action],"missing committed action")
        local t=assert(a.targets[life],"receiver was not snapshotted")
        local d=a.decisions[life]
        assert(type(observation)=="table" and observation.directed==true,"directed observation required")
        if a.completed then return false,"ALREADY_FINALIZED" end
        local o=U.copy(observation)
        a.observations=a.observations or {};a.observations[life]=o
        if not a.context_complete or t.context_complete==false then return false,"UNRESOLVED_CONTEXT" end
        if not a.source_known or a.system or a.passive or d.force~="NONE" or not a.profile_known
            or not serious[a.method] or o.observation_complete~=true or o.observed_source~=true then
            return false,"NO_OBSERVED_ROOT"
        end
        local physical=U.copy(t)
        physical.directed=true;physical.observed_source=true;physical.observation_complete=true
        physical.witnesses=o.witnesses or {}
        self:add_root(a,physical,"serious")
        return true,"ROOT_RECORDED"
    end
    function A:heartbeat(root,time,verified,observations)
        local r=assert(self.roots[root],"unknown root")
        U.number(time,r.last,1e12,"heartbeat time")
        if not verified or r.closed then return false end
        -- A heartbeat must reference maintained control, not residual blood/poison.
        r.continuous=true;r.heartbeat=time;r.last=time
        for life,o in pairs(observations or {}) do
            if o.visible==true and o.participating==true and U.finite(o.distance)
                and o.distance>=0 and o.distance<=C.witness_distance then r.witnesses[U.id(life)]=time end
        end
        return true
    end
    function A:release(root,time)
        local r=assert(self.roots[root]);U.number(time,r.last,1e12,"release time")
        r.continuous=false;r.last=time;r.heartbeat=nil
    end
    function A:closure(root,time,kind,observable)
        local r=assert(self.roots[root]);U.number(time,r.last,1e12,"closure time")
        if not observable then return false end
        assert(kind=="disengaged" or kind=="incapacitated" or kind=="life_end")
        local delay=kind=="disengaged" and C.disengagement_seconds
            or kind=="incapacitated" and C.incapacity_seconds or 0
        r.closed=math.min(r.closed or math.huge,time+delay);return true
    end
    function A:cancel_closure(root)
        local r=assert(self.roots[root]);r.closed=nil
    end
    function A:effect(action,input)
        local a=assert(self.actions[action],"missing committed action")
        local e=U.copy(input);U.id(e.id);U.id(e.target_life)
        assert(a.targets[e.target_life],"uncaptured receiver context")
        U.number(e.harm or 0,0,100000,"accepted harm")
        U.number(e.time,a.time,1e12,"effect time")
        if e.damage~=nil then U.number(e.damage,0,1e9,"raw damage") end
        if e.control~=nil then assert(C.control_floor[e.control],"unknown control category") end
        local sig=U.canonical(e);local old=self.effects[e.id]
        if old then assert(old.signature==sig and old.action==action,"conflicting effect replay");return false end
        assert(not a.completed,"immediate group already finalized")
        e.signature=sig;e.action=action;self.effects[e.id]=e;a.effects[#a.effects+1]=e
        return true
    end
    function A:can_waive(a,total)
        if not a.account or total<=0 or total>C.tolerance_harm then return false end
        local list=self.budgets[a.account] or {}; local round_harm,round_count,rolling_harm,rolling_count=0,0,0,0
        for _,b in ipairs(list) do
            if b.match==a.match then round_harm=round_harm+b.harm;round_count=round_count+1 end
            if a.time-b.time<C.tolerance_seconds then rolling_harm=rolling_harm+b.harm;rolling_count=rolling_count+1 end
        end
        return round_count<C.tolerance_actions and rolling_count<C.tolerance_actions
            and round_harm+total<=C.tolerance_harm+1e-9 and rolling_harm+total<=C.tolerance_harm+1e-9
    end
    function A:bucket(a,t)
        local key=a.match.."|"..(a.account or "unknown").."|"..t.life.."|"..a.policy
        local b=self.buckets[key]
        if not b then b={id=key,source=a.account,target=t.account,life=t.life,units=0,episodes={},harm=0};self.buckets[key]=b end
        return b
    end
    function A:finish(action)
        local a=assert(self.actions[action]);if a.completed then return U.copy(a.result),false end
        local groups={};local waiver_total=0;local waiver_candidate=true
        for _,e in ipairs(a.effects) do
            if e.accepted==true then
                local d=a.decisions[e.target_life]
                local g=groups[e.target_life] or {harm=0,control=nil,effects={},serious=false,last=a.time}
                groups[e.target_life]=g;g.harm=g.harm+(e.harm or 0);g.last=math.max(g.last,e.time)
                g.effects[#g.effects+1]=e;g.serious=g.serious or e.serious==true or e.lethal==true
                if e.control then
                    local old=g.control and C.control_floor[g.control] or 0
                    if C.control_floor[e.control]>old then g.control=e.control end
                end
                if d.accountable then
                    waiver_total=waiver_total+(e.harm or 0)
                    local method_ok=a.method=="ordinary_unarmed" or a.incidental_certified==true
                    if not method_ok or a.hazardous_geometry or a.passive or g.serious or e.control then waiver_candidate=false end
                end
            end
        end
        local waive=waiver_candidate and self:can_waive(a,waiver_total)
        if waive then
            local list=self.budgets[a.account] or {};self.budgets[a.account]=list
            list[#list+1]={action=a.id,match=a.match,time=a.time,harm=waiver_total}
        end
        local results={}
        for _,tid in ipairs(U.keys(groups)) do
            local g=groups[tid];local t=a.targets[tid];local d=U.copy(a.decisions[tid])
            d.harm=g.harm;d.control=g.control;d.effects=#g.effects;d.waived=waive and d.accountable or false
            d.control_only=g.control~=nil and g.harm==0
            d.proposed_debit=0;d.units_added=0
            if d.accountable and not d.waived then
                local b=self:bucket(a,t);local before=b.units
                local episode_key=t.life.."|"..a.life
                local ep=self.controls[episode_key]
                if (g.control or a.control_lineage) and (not ep or ep.match~=a.match or g.last-ep.last>=C.control_gap) then
                    ep={id=a.id,match=a.match,last=g.last,harm=0,floor=0,priced=0};self.controls[episode_key]=ep
                end
                if ep and ep.match==a.match and g.last-ep.last<C.control_gap and (g.control or a.control_lineage) then
                    ep.last=g.last;ep.harm=ep.harm+g.harm
                    ep.floor=math.max(ep.floor,g.control and C.control_floor[g.control] or 0)
                    local wanted=math.max(ep.harm,ep.floor)
                    b.units=math.min(10,b.units+wanted-ep.priced);ep.priced=wanted
                else b.units=math.min(10,b.units+g.harm) end
                b.harm=b.harm+g.harm;d.bucket=b.id;d.units_added=b.units-before;d.cumulative_units=b.units
                d.proposed_debit=P.loss(t.karma,b.units)-P.loss(t.karma,before)
            elseif d.waived then d.reason="MINOR_TOLERANCE" end
            d.brain_eligible=d.accountable and not d.waived and g.harm>0
            -- Later trace facts may establish contact, but never rewrite its prior-state verdict.
            local observed=a.observations and a.observations[tid]
            local physical=t
            if observed then
                physical=U.copy(t)
                physical.directed=observed.directed==true
                physical.observed_source=observed.observed_source==true
                physical.observation_complete=observed.observation_complete==true
                physical.witnesses=observed.witnesses or {}
            end
            if not a.passive and a.source_known and not a.system and d.force=="NONE"
                and physical.observed_source and physical.observation_complete and a.context_complete
                and t.context_complete~=false then
                if g.serious or g.control=="danger" or g.control=="restrict" then self:add_root(a,physical,"serious")
                elseif a.method=="ordinary_unarmed" and physical.directed and g.harm>0 then
                    local key=a.match.."|"..a.life.."|"..t.life
                    local history=self.minor[key] or {};self.minor[key]=history
                    local next_history={};local harm=g.harm
                    for _,r in ipairs(history) do if a.time-r.time<=C.escalation_seconds then
                        next_history[#next_history+1]=r;harm=harm+r.harm
                    end end
                    next_history[#next_history+1]={time=a.time,harm=g.harm,action=a.id};self.minor[key]=next_history
                    self:add_root(a,physical,(#next_history>=C.escalation_actions or harm>=C.escalation_harm) and "serious" or "minor")
                end
            end
            results[#results+1]=d
        end
        a.completed=true;a.result=results;return U.copy(results),true
    end
    function A:prune_resolved(now)
        -- Runtime may call only after it has durably archived completed outcomes.
        -- Active causal/financial records live in separate stores, not in this cache.
        U.number(now,self.last_time,1e12,"prune time")
        for id,a in pairs(self.actions) do
            if a.completed and a.archived and now-a.time>120 then
                for _,e in ipairs(a.effects) do self.effects[e.id]=nil end
                self.actions[id]=nil;self.action_count=self.action_count-1
            end
        end
        for id,r in pairs(self.roots) do if now-r.last>120 and not root_active(r,now) then self.roots[id]=nil end end
        for key,h in pairs(self.minor) do if #h==0 or now-h[#h].time>120 then self.minor[key]=nil end end
    end
    function A:archived(action) local a=assert(self.actions[action]);assert(a.completed);a.archived=true end
    return A
end
