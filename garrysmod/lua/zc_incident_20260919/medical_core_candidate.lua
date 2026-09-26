-- Actual-delta provenance only. No physiology simulation or financial writes.
return function(U,C)
    local M={};M.__index=M
    local channels={blood={limit=5000,deficit=true},brain={limit=1},skull={limit=1}}
    local reserved={unknown=true,preexisting=true,environment=true,system=true}
    local SCALE=1000000
    -- The change receipt is always the same five-key tuple. Cache its fixed
    -- canonical fragments instead of allocating and sorting that outer table
    -- for every observation. Values and cause weights keep the same serializer.
    local change_prefix={}
    local change_four,change_five=U.canonical(4),U.canonical(5)
    for channel in pairs(channels)do
        local prefix=U.canonical({"change",channel})
        change_prefix[channel]=prefix:sub(1,-2)..U.canonical(3)
    end
    local function sum(weights)local n=0;for _,v in pairs(weights)do n=n+v end;return n end
    local function units(channel,value)
        local cfg=assert(channels[channel],"unregistered medical channel")
        U.number(value,0,100000,"actual medical value")
        if not cfg.deficit then assert(value<=cfg.limit,"injury beyond registered range")end
        return U.round((cfg.deficit and math.max(0,cfg.limit-value)or value)*SCALE)
    end
    local function rebalance(weights,total)
        if sum(weights)==0 then return total>0 and {unknown=total}or {}end
        return U.allocate(total,weights)
    end
    local function receipt(s,sequence,signature)
        U.integer(sequence,1,9007199254740991,"medical sequence")
        if sequence==s.last_sequence then
            assert(signature==s.last_signature,"conflicting medical mutation replay")
            return U.copy(s.last_result),false
        end
        if sequence<s.last_sequence then return {status="STALE_EVENT"},false end
        return nil,true
    end
    local function finish(s,sequence,signature,result)
        s.last_sequence=sequence;s.last_signature=signature;s.last_result=U.copy(result)
        return U.copy(result),true
    end
    function M.new()
        return setmetatable({states={},causes={},state_count=0,cause_count=0},M)
    end
    function M:state(id,life,match)
        U.id(id);U.id(life);U.id(match)
        local old=self.states[id]
        if old then assert(old.life==life and old.match==match,"medical generation conflict");return old end
        assert(self.state_count<C.capacity.lives,"medical state capacity")
        local s={id=id,life=life,match=match,channels={},wounds={},last_sequence=0}
        self.states[id]=s;self.state_count=self.state_count+1;return s
    end
    function M:cause(id,input)
        U.id(id);assert(not reserved[id],"reserved cause identifier")
        local c=U.copy(input)
        U.id(c.state);U.id(c.account);U.id(c.action);U.id(c.policy)
        assert(self.states[c.state],"missing medical state")
        assert(c.status=="DETERMINED"or c.status=="UNRESOLVED","missing adjudication status")
        assert(type(c.verdict)=="string"and type(c.force)=="string","missing frozen verdict")
        local old=self.causes[id]
        if old then assert(U.equal(old,c),"conflicting cause replay");return id end
        assert(self.cause_count<C.capacity.conditions,"medical cause capacity")
        self.causes[id]=c;self.cause_count=self.cause_count+1;return id
    end
    function M:weights(state,input)
        if input==nil then return {unknown=1}end
        local out=U.copy(input)
        for id,n in pairs(out)do
            U.id(id);U.integer(n,0,1e12,"cause weight")
            assert(reserved[id]or (self.causes[id]and self.causes[id].state==state),"wrong-generation medical cause")
        end
        U.integer(sum(out),0,1e12,"combined cause weights")
        return sum(out)>0 and out or {unknown=1}
    end
    function M:change(id,sequence,channel,before,after,input)
        local s=assert(self.states[id])
        local old_units,new_units=units(channel,before),units(channel,after)
        local weights=self:weights(id,input)
        local sig=change_prefix[channel]..U.canonical(before)..change_four
            ..U.canonical(after)..change_five..U.canonical(weights).."}"
        local prior_result,new=receipt(s,sequence,sig)
        if not new then return prior_result,false end
        local prior=s.channels[channel]
        local row=prior and U.copy(prior)or {value=old_units,weights=old_units>0 and {preexisting=old_units}or {}}
        local gap=old_units-row.value
        if gap>0 then row.weights.unknown=(row.weights.unknown or 0)+gap
        elseif gap<0 then row.weights=rebalance(row.weights,old_units)end
        local delta=new_units-old_units
        if delta>0 then
            for cause,n in pairs(U.allocate(delta,weights))do row.weights[cause]=(row.weights[cause]or 0)+n end
        elseif delta<0 then row.weights=rebalance(row.weights,new_units)end
        assert(sum(row.weights)==new_units,"medical units not conserved")
        row.value=new_units;row.actual=after
        local result={status="OBSERVED",delta=delta,gap=gap,total=new_units,channel=channel}
        s.channels[channel]=row
        return finish(s,sequence,sig,result)
    end
    function M:wound_add(id,sequence,wound,before,after,cause)
        local s=assert(self.states[id]);U.id(wound)
        U.number(before,0,1e6,"wound strength");U.number(after,before,1e6,"wound strength")
        local weights=self:weights(id,cause and {[cause]=1}or nil)
        local sig=U.canonical({"wound_add",wound,before,after,weights})
        local old_result,new=receipt(s,sequence,sig)
        if not new then return old_result,false end
        local prior=s.wounds[wound];local row=prior and U.copy(prior)or {weights={},value=0}
        local was,now=U.round(before*SCALE),U.round(after*SCALE)
        if was>row.value then row.weights.unknown=(row.weights.unknown or 0)+(was-row.value)
        elseif was<row.value then row.weights=rebalance(row.weights,was)end
        if now>was then
            for key,n in pairs(U.allocate(now-was,weights))do row.weights[key]=(row.weights[key]or 0)+n end
        end
        row.value=now
        assert(sum(row.weights)==now,"wound units not conserved")
        s.wounds[wound]=row
        return finish(s,sequence,sig,{status="WOUND_ADDITION",total=now,wound=wound})
    end
    function M:wound_weights(id,wound,strength)
        local s=assert(self.states[id]);U.id(wound);U.number(strength,0,1e6,"wound strength")
        local prior=s.wounds[wound];local row=prior and U.copy(prior)
        local n=U.round(strength*SCALE)
        if not row then row={value=n,weights=n>0 and {unknown=n}or {}}
        elseif n>row.value then row.weights.unknown=(row.weights.unknown or 0)+n-row.value;row.value=n
        elseif n<row.value then row.weights=rebalance(row.weights,n);row.value=n end
        assert(sum(row.weights)==n,"wound units not conserved")
        s.wounds[wound]=row;return U.copy(row.weights)
    end
    function M:channel_weights(id,channel)
        local s=assert(self.states[id]);assert(channels[channel]);local row=s.channels[channel]
        return row and U.copy(row.weights)or {unknown=1}
    end
    function M:support(id,channel)
        local weights=self:channel_weights(id,channel);local selected;local found=false
        local has_unknown,has_unresolved,has_mixed=false,false,false
        local actions={}
        for key,n in pairs(weights)do if n>0 then
            local c=self.causes[key]
            if not c then has_unknown=true
            else
                found=true;actions[c.action]=true
                if c.status~="DETERMINED"then has_unresolved=true end
                if selected and (selected.account~=c.account or selected.verdict~=c.verdict
                    or selected.policy~=c.policy or selected.force~=c.force)then has_mixed=true end
                selected=selected or c
            end
        end end
        -- Deterministic precedence; Lua table traversal cannot change a verdict.
        if has_unknown then return {status="UNRESOLVED_CAUSE"}end
        if has_mixed then return {status="MIXED_CAUSE"}end
        if has_unresolved then return {status="UNRESOLVED_CLASSIFICATION"}end
        if not found then return {status="NO_SUPPORT"}end
        return {status="CONSISTENT_SUPPORT",account=selected.account,verdict=selected.verdict,
            force=selected.force,policy=selected.policy,actions=U.keys(actions)}
    end
    function M:terminal(id,branch)
        assert(branch=="brain_threshold","uncertified terminal branch")
        local s=assert(self.states[id]);local row=s.channels.brain
        assert(row and row.actual>=0.7,"terminal condition not met")
        local proof=self:support(id,"brain")
        proof.branch=branch;proof.life=s.life;proof.match=s.match;proof.state=id
        proof.certified_operation=true
        -- Attribution consistency is not proof of complete physiological coverage.
        proof.full_cause_coverage=false;proof.financial_eligible=false
        return proof
    end
    return M
end
