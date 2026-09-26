-- Private, source-driven medical observation. NOT a production accounting writer.
return function(R,B,Medical)
    local U=B.U
    local function weak()return setmetatable({},{__mode="k"})end
    local function result(t)if not t[1]then error(t[2],0)end;return (unpack or table.unpack)(t,2,t.n)end
    function R:MedicalState(org)
        if type(org)~="table"then return nil end
        local p=self:Receiver(org.owner)
        if not p or p.organism~=org then return nil end
        local a=self:Actor(p);if not a then return nil end
        local state=self.medical_states[org]
        if state and (state.life~=a.life or state.match~=self.observer.round)then
            self.medical_states[org]=nil;self.medical_pending[org]=nil;state=nil
        end
        if not state then
            local id=self:Next("medical_state")
            self.medical_model:state(id,a.life,self.observer.round)
            state={id=id,life=a.life,match=self.observer.round,owner=p,org=org,causes={}}
            self.medical_states[org]=state
        end
        return state
    end
    function R:MedicalSequence()
        self.medical_sequence=self.medical_sequence+1;return self.medical_sequence
    end
    -- DamageInfo identity is only a cache key. It cannot authenticate a later
    -- mutation after its source call returned, another call nested, or time advanced.
    function R:MedicalRecordCurrent(record)
        if not record or not record.pending or record.pending.closed
            or record.tick~=engine.TickCount()then return false end
        local effect=self.effect_stack and self.effect_stack[#self.effect_stack]
        if effect then return effect==record and (record.active_depth or 0)>0 end
        return self.scope and self.scope[#self.scope]==record.pending or false
    end
    function R:MedicalCause(state,record)
        if not record or record.org~=state.org or record.life~=state.life then return nil end
        local pending=record.pending
        if not pending or pending.action.match~=state.match then return nil end
        local d=pending.decisions and pending.decisions[state.life]
        if not d then return nil end
        local key=pending.action.id
        if state.causes[key]then return state.causes[key]end
        local id=self:Next("medical_cause")
        self.medical_model:cause(id,{state=state.id,account=pending.action.account,
            action=key,policy=pending.action.policy,status=d.status,
            verdict=d.reason,force=d.force})
        state.causes[key]=id;return id
    end
    function R:MedicalContextCause(state)
        local top=self.medical_context[#self.medical_context]
        if not top or top.state~=state.id or top.org~=state.org then return nil end
        local active=self.scope and self.scope[#self.scope]
        local cause=self.medical_model.causes[top.cause]
        if active and (not cause or active.action.id~=cause.action)then return nil end
        return top.cause
    end
    function R:MedicalWoundAddition(p,wound,before,added,record)
        local state=self:MedicalState(p.organism);if not state then return end
        local binding=self.medical_wounds[wound]
        if not binding or binding.state~=state.id then
            binding={state=state.id,id=self:Next("medical_wound")};self.medical_wounds[wound]=binding
        end
        local cause
        if record then
            if self:MedicalRecordCurrent(record)then cause=self:MedicalCause(state,record)end
        else cause=self:MedicalContextCause(state)end
        self.medical_model:wound_add(state.id,self:MedicalSequence(),binding.id,before,before+added,cause)
        self.stats.medical_wound_additions=(self.stats.medical_wound_additions or 0)+1
    end
    function R:MedicalCreatedWound(org,wound,info)
        local state=self:MedicalState(org);if not state then return end
        local record=self:FindDamage(info,state.owner)
        self:MedicalWoundAddition(state.owner,wound,0,wound[1],record)
    end
    function R:MedicalWoundWeights(state,wound)
        if type(wound)~="table"then return nil end
        local binding=self.medical_wounds[wound]
        if not binding or binding.state~=state.id then
            binding={state=state.id,id=self:Next("medical_wound")};self.medical_wounds[wound]=binding
        end
        return self.medical_model:wound_weights(state.id,binding.id,wound[1])
    end
    function R:MedicalUnknownChokeInput(org)
        if self.medical_chokes then self.medical_chokes[org]=nil end
    end
    function R:MedicalChokeInput(org,pending,already)
        if not pending or pending.closed or pending.action.method~="choke"
            or self.scope[#self.scope]~=pending then return end
        local state=self:MedicalState(org);if not state then return end
        local source=self:Actor(pending.source)
        if not source or source.life~=pending.action.life or pending.action.match~=state.match then return end
        self.medical_chokes=self.medical_chokes or weak()
        local previous=self.medical_chokes[org]
        if already and (not previous or previous.pending~=pending)then
            self.medical_chokes[org]=nil;return
        end
        local cause=self:MedicalCause(state,{org=org,life=state.life,pending=pending})
        if not cause then return end
        self.medical_chokes[org]={pending=pending,state=state.id,org=org,o2=org.o2,cause=cause,
            source_life=source.life,life=state.life,match=state.match,at=self:Clock()}
    end
    local function normalBreathing(org)
        -- Certify only an otherwise normal breathing baseline. Other native
        -- suppression and capacity changes require their own cause bindings.
        -- At these bounds native minimum regeneration exceeds consumption;
        -- the observed choke is the input which prevents replenishment.
        local o2,stamina=org.o2,org.stamina
        if type(o2)~="table"or type(stamina)~="table"
            or type(org.lungsL)~="table"or type(org.lungsR)~="table"
            or not U.finite(org.brain)or not U.finite(org.blood)or not U.finite(org.temperature)
            or not U.finite(org.pulse)or not U.finite(stamina[1])or not U.finite(stamina.max)
            or not U.finite(o2.regen)or not U.finite(o2.range)then return end
        if not org.alive or org.heartstop or not org.lungsfunction or org.brain>=.4
            or org.vomitInThroat or org.holdingbreath or org.is_sprayed_at
            or org.CO~=0 or org.COregen~=0 or (org.lastCOBreathe and org.lastCOBreathe+1>CurTime())
            or org.blood<4500 or org.pulse<40 or org.temperature>38 or org.trachea~=0 or org.pneumothorax~=0
            or org.lungsL[1]~=0 or org.lungsR[1]~=0 or org.lungsL[2]~=0 or org.lungsR[2]~=0
            or stamina.max<=0 or stamina[1]<stamina.max
            or o2.regen<4 or o2.range<30
            or org.owner:WaterLevel()>=3 or org.owner:GetNetVar("zableval_masku",false)then return end
        return true
    end
    function R:MedicalChokeCause(state,blocked)
        local org=state.org local token=self.medical_chokes and self.medical_chokes[org]
        if self.medical_chokes then self.medical_chokes[org]=nil end -- consume once, including refusal
        if not blocked or not token or token.state~=state.id or token.org~=org or token.o2~=org.o2
            or token.life~=state.life or token.match~=state.match or org.choking~=true then return end
        local age=self:Clock()-token.at
        local source=self:Actor(token.pending.source)
        if age<0 or age>.25 or not source or source.life~=token.source_life or not normalBreathing(org)then return end
        return token.cause
    end
    function R:MedicalWireCause(state,weapon)
        local session=self.wire and self.wire[weapon]
        if not session or session.closed or not self.WireState
            or session.org~=state.org or session.life~=state.life or session.match~=state.match
            or session.medical_state~=state.id or session.medical_o2~=state.org.o2
            or not session.medical_cause then return end
        local source,target,rag=self:WireState(weapon)
        if source~=session.source or target~=state.owner or rag~=session.rag then return end
        local actor=self:Actor(source);local age=self:Clock()-session.last
        if not actor or actor.life~=session.source_life or age<0 or age>1
            or state.org.choking or not normalBreathing(state.org)then return end
        return session.medical_cause
    end
    function R:MedicalMutation(org,channel,before,after,kind,object)
        if type(org)~="table"then return end
        U.number(before,0,100000,"medical before");U.number(after,0,100000,"medical after")
        local actual=org[channel]
        if channel=="oxygen"then actual=type(org.o2)=="table"and org.o2[1]or nil end
        if actual~=after then
            if channel=="oxygen"and kind=="consumption"then self:MedicalUnknownChokeInput(org)end
            self.stats.medical_stale_deltas=(self.stats.medical_stale_deltas or 0)+1
            return {status="STALE_SCALAR",delta=0,gap=0}
        end
        local state=self:MedicalState(org);if not state then return end
        local weights
        if channel=="oxygen"and kind=="consumption"then
            local cause=self:MedicalChokeCause(state,object==true)
            if not cause and object and object~=true then cause=self:MedicalWireCause(state,object)end
            if cause then weights={[cause]=1}end
        elseif kind=="wound"then weights=self:MedicalWoundWeights(state,object)
        elseif kind=="impact"then
            local r=self:FindDamage(object,state.owner)
            local cause=self:MedicalRecordCurrent(r)and self:MedicalCause(state,r)or nil
            if cause then weights={[cause]=1}end
        elseif kind=="hypoxia_or_skull"and org.o2 and org.o2[1]<0.25 and org.skull==0 then
            -- Native low oxygen is the only active term in this branch. Keep
            -- the surviving deficit history, including unknown/preexisting loss.
            -- Synchronization exposes untapped changes as unknown, never as the
            -- most recent attacker's oxygen debt.
            self.medical_model:change(state.id,self:MedicalSequence(),"oxygen",org.o2[1],org.o2[1],nil)
            weights=self.medical_model:channel_weights(state.id,"oxygen")
        elseif kind=="skull"or (kind=="hypoxia_or_skull"and org.o2 and org.o2[1]>=0.25)then
            self.medical_model:change(state.id,self:MedicalSequence(),"skull",org.skull,org.skull,nil)
            weights=self.medical_model:channel_weights(state.id,"skull")
        elseif kind=="system"then weights={system=1}end
        local event=self.medical_model:change(state.id,self:MedicalSequence(),channel,before,after,weights)
        self.stats.medical_mutations=(self.stats.medical_mutations or 0)+1
        if event.gap~=0 then
            self.stats.medical_unobserved_deltas=(self.stats.medical_unobserved_deltas or 0)+1
        end
        return event
    end
    function R:MedicalWireStart(session,pending)
        local state=self:MedicalState(session.org);if not state then return end
        local record={org=session.org,life=session.life,pending=pending}
        session.medical_cause=self:MedicalCause(state,record)
        session.medical_state=state.id
        session.medical_o2=state.org.o2
    end
    function R:WithWireMedical(p,fn,...)
        if not self.enabled then return fn(...)end
        local context=self:Safe(function(s)
            local state=s:MedicalState(p.organism);if not state then return nil end
            local match
            for weapon,session in pairs(s.wire or {})do
                local source,target,rag=s:WireState(weapon)
                if not session.closed and source==session.source and target==p and rag==session.rag
                    and session.org==state.org and session.life==state.life and session.match==state.match
                    and s:Actor(source).life==session.source_life and s:Clock()-session.last<=1
                    and session.medical_state==state.id and session.medical_cause then
                    if match then return nil end
                    match={state=state.id,cause=session.medical_cause,org=state.org}
                end
            end
            return match
        end)
        if not context then return fn(...)end
        if #self.medical_context>=(B.C.capacity.contexts or 32)then
            self:Issue("medical_context_capacity","private medical context limit reached")
            return fn(...)
        end
        self.medical_context[#self.medical_context+1]=context
        local out=U.pack(pcall(fn,...))
        if self.medical_context[#self.medical_context]~=context then self:Issue("medical_scope","context mismatch")end
        self.medical_context[#self.medical_context]=nil
        return result(out)
    end
    function R:MedicalTerminalDecision(org,branch)
        local state=self:MedicalState(org)
        if not state or org.alive~=false then return end
        self.medical_model:change(state.id,self:MedicalSequence(),"brain",org.brain,org.brain,nil)
        local proof=self.medical_model:terminal(state.id,branch)
        self.medical_pending[org]={proof=proof,org=org,owner=state.owner,life=state.life,
            match=state.match,tick=engine.TickCount(),used=false}
        self.stats.medical_terminal_decisions=(self.stats.medical_terminal_decisions or 0)+1
    end
    function R:WithMedicalTerminal(p,org,fn,...)
        if not self.enabled then return fn(...)end
        local token=self:Safe(function(s)
            local t=s.medical_pending[org];local a=s:Actor(p)
            if not t or t.used or not a or t.owner~=p or t.org~=p.organism or t.life~=a.life
                or t.match~=s.observer.round or t.tick~=engine.TickCount()or org.alive~=false then return nil end
            return t
        end)
        if not token then return fn(...)end
        if #self.medical_terminal_stack>=(B.C.capacity.contexts or 32)then
            self:Issue("medical_terminal_capacity","private terminal context limit reached")
            return fn(...)
        end
        self.medical_terminal_stack[#self.medical_terminal_stack+1]=token
        local out=U.pack(pcall(fn,...))
        if self.medical_terminal_stack[#self.medical_terminal_stack]~=token then
            self:Issue("medical_terminal_scope","context mismatch")
        end
        self.medical_terminal_stack[#self.medical_terminal_stack]=nil
        if self.medical_pending[org]==token then self.medical_pending[org]=nil end
        return result(out)
    end
    function R:MedicalDeathProof(p)
        local a=self:Actor(p);local t=self.medical_terminal_stack[#self.medical_terminal_stack]
        if not t or t.used or not a or t.owner~=p or t.org~=p.organism or t.life~=a.life
            or t.match~=self.observer.round or t.tick~=engine.TickCount()then return nil end
        t.used=true;return U.copy(t.proof)
    end
    function R:InstallMedical()
        self.medical_model=Medical.new();self.medical_sequence=0
        self.medical_states=weak();self.medical_wounds=weak();self.medical_pending=weak()
        self.medical_chokes=weak()
        self.medical_context={};self.medical_terminal_stack={}
        local selfref=self
        self:Wrap(hg and hg.organism,"AddWoundManual","private_manual_wounds",function(original)
            return function(entity,...)
                local before=selfref:Safe(function(s)
                    local p=s:Receiver(entity);if not p or not p.organism then return nil end
                    local out={};for _,w in pairs(p.organism.wounds or {})do out[w]=w[1]end
                    return out
                end)
                local out=U.pack(pcall(original,entity,...))
                if out[1]and before then selfref:Safe(function(s)
                    local p=s:Receiver(entity);if not p or not p.organism then return end
                    for _,w in pairs(p.organism.wounds or {})do
                        local old=before[w]or 0;local added=(w[1]or 0)-old
                        if added>0 then s:MedicalWoundAddition(p,w,old,added,nil)end
                    end
                end)end
                return result(out)
            end
        end)
        self.coverage.medical="candidate_delta_taps_require_native_source_installation"
        self.coverage.medical_hypoxia="native_oxygen_deltas_and_unmixed_brain_transfer; respiratory_source_bindings_pending"
    end
end
