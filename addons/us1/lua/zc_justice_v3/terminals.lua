-- Explicit terminal categories. A request is not a death; tokens are scoped to
-- the synchronous trusted operation and consumed only by an actual death callback.
return function(R,B)
    local U=B.U
    local allowed={giveup=true,timeout=true,admin=true,objective=true,suicide=true,environment=true}
    function R:WithTerminal(p,category,fn,...)
        if not self.enabled then return fn(...)end
        local token=self:Safe(function(s)
            assert(allowed[category],"unregistered terminal category")
            local actor=s:Actor(p);if not actor then return nil end
            local life=s.observer:Life(p)
            return {id=s:Next("terminal_token"),life=actor.life,account=actor.account,
                generation=life.generation,organism=p.organism,match=s.observer.round,
                category=category,used=false,player=p}
        end)
        if not token then return fn(...)end
        self.terminal_stack=self.terminal_stack or {}
        self.terminal_stack[#self.terminal_stack+1]=token
        local result=U.pack(pcall(fn,...))
        if self.terminal_stack[#self.terminal_stack]~=token then self:Issue("terminal_scope","terminal unwind mismatch")end
        self.terminal_stack[#self.terminal_stack]=nil
        -- A denied Give Up/suicide operation leaves no token in any future lookup.
        if not result[1]then error(result[2],0)end
        return unpack(result,2,result.n)
    end
    function R:Death(p,kind)
        local actor=self:Actor(p);if not actor then return end
        self.observed_terminals=self.observed_terminals or {}
        local old=self.observed_terminals[actor.life]
        if old then
            old.callbacks=old.callbacks+1
            self.stats.terminal_aliases=(self.stats.terminal_aliases or 0)+1
            return
        end
        self.terminal_count=(self.terminal_count or 0)+1
        assert(self.terminal_count<=B.C.capacity.lives,"unarchived terminal capacity")
        local generation=self.observer:Life(p).generation
        local token
        for i=#(self.terminal_stack or {}),1,-1 do
            local candidate=self.terminal_stack[i]
            if candidate.player==p and candidate.life==actor.life and candidate.generation==generation
                and candidate.organism==p.organism and candidate.match==self.observer.round and not candidate.used then
                token=candidate;break
            end
        end
        local provisional=ZCityPillCompat and ZCityPillCompat.spawning and ZCityPillCompat.spawning[p]
        local medical=not token and not provisional and self.MedicalDeathProof and self:MedicalDeathProof(p)or nil
        local category=provisional and "provisional"or token and token.category or medical and "medical"or "unknown"
        if token then token.used=true end
        local context=self.effect_stack[#self.effect_stack]
        local row={id=self:Next("terminal"),target=actor.account,life=actor.life,
            generation=generation,match=self.observer.round,category=category,callback=kind,
            token=token and token.id,callbacks=1,medical=medical,
            certified_operation=(token~=nil or medical~=nil)and not provisional,
            effect_candidate=context and context.life==actor.life and context.id or nil,
            time=self:Clock(),sealed=false}
        self.observed_terminals[actor.life]=row
        self.terminal_queue[#self.terminal_queue+1]=row
        if category=="unknown"then self.stats.unknown_terminal=self.stats.unknown_terminal+1
        else self.stats.categorized_terminal=(self.stats.categorized_terminal or 0)+1 end
        self:Summary({reason=category=="unknown"and "TERMINAL_CAUSE_ADAPTER_REQUIRED"or "TERMINAL_"..category,
            target=actor.account,target_life=actor.life,harm=0,proposed_debit=0})
    end
    function R:SealObservedTerminals()
        if #self.scope>0 or #self.effect_stack>0 or #(self.terminal_stack or {})>0 then return end
        local queue=self.terminal_queue or {}
        local done=0
        while self.terminal_head<=#queue and done<B.C.capacity.events_per_tick do
            local row=queue[self.terminal_head]
            if not row.sealed then
                self.observer:Record({kind="terminal_operation_observed",id=row.id,
                    round=row.match,target=row.target,target_life=row.life,generation=row.generation,
                    category=row.category,callback=row.callback,certified_operation=row.certified_operation,
                    effect_candidate=row.effect_candidate,callbacks=row.callbacks,token=row.token,medical=row.medical,
                    observation_only=true,financial_writes=0,full_cause_coverage=false})
                row.sealed=true
            end
            self.terminal_head=self.terminal_head+1;done=done+1
        end
        if self.terminal_head>#queue then self.terminal_queue={};self.terminal_head=1 end
    end
    function R:InstallTerminals()
        self.terminal_stack={};self.observed_terminals={}
        self.terminal_queue={};self.terminal_head=1;self.terminal_count=0
        self:Add("Think","TerminalSeal",R.SealObservedTerminals,2)
        self.coverage.terminal="explicit_giveup_timeout_tokens_other_causes_pending"
    end
end
