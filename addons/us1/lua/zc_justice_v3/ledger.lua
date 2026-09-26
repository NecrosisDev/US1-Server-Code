-- Once-only financial transactions. Pure request data, transactional store injected.
-- Does not touch ply.Karma, native SQL tables, chat, sanctions or organism state.
return function(U,C,P)
    local L={};L.__index=L
    function L.new(store)return setmetatable({store=store},L)end
    function L:tx(receipt,kind,request,fn)
        U.id(receipt);U.id(kind);local signature=U.canonical(request)
        assert(#signature<=65536,"oversized operation")
        return self.store:transaction(function(s)
            local old=s:get("receipts",receipt)
            if old then assert(old.kind==kind and old.signature==signature,"conflicting receipt replay")
                return U.copy(old.result),true
            end
            local meta=s:get("meta","sequence") or {value=0};meta.value=meta.value+1
            local result=fn(s,meta.value)
            assert(type(result)=="table","result required")
            s:put("meta","sequence",meta)
            s:insert("receipts",receipt,{kind=kind,signature=signature,sequence=meta.value,result=result})
            return U.copy(result),false
        end)
    end
    function L:open(account,seed,receipt)
        U.id(account);U.integer(seed,C.minimum,C.maximum,"seed")
        return self:tx(receipt,"import_account",{account,seed},function(s)
            local row=s:get("accounts",account)
            if row then return {account=account,balance=row.balance,existing=true}end
            row={account=account,balance=seed,revision=1};s:insert("accounts",account,row)
            return {account=account,balance=seed,existing=false}
        end)
    end
    function L:match(id,hidden,receipt)
        U.id(id)
        return self:tx(receipt,"create_match",{id,hidden==true},function(s)
            local old=s:get("matches",id)
            if old then assert(old.hidden==(hidden==true));return old end
            local row={id=id,hidden=hidden==true,state="ACTIVE"};s:insert("matches",id,row);return row
        end)
    end
    function L:snapshot(match,account,receipt)
        U.id(match);U.id(account)
        return self:tx(receipt,"snapshot",{match,account},function(s)
            local m=assert(s:get("matches",match),"unknown match")
            local key=match.."|"..account
            local old=s:get("snapshots",key);if old then return old end
            local a=assert(s:get("accounts",account),"unknown account")
            assert(m.state=="ACTIVE","match closed to new snapshots")
            local snap={match=match,account=account,value=a.balance};s:insert("snapshots",key,snap);return snap
        end)
    end
    local function adjust(s,account,delta)
        U.integer(delta,-1000000000,1000000000,"delta")
        local a=assert(s:get("accounts",account),"unknown account")
        local before=a.balance;a.balance=U.clamp(before+delta,C.minimum,C.maximum);a.revision=a.revision+1
        s:put("accounts",account,a);return a.balance-before,a.balance
    end
    function L:change(account,delta,receipt,reason)
        U.id(account);U.id(reason);U.integer(delta,-1000000000,1000000000)
        return self:tx(receipt,reason,{account,delta},function(s)
            local applied,balance=adjust(s,account,delta)
            return {requested=delta,applied=applied,balance=balance}
        end)
    end
    function L:effect(receipt,r)
        r=U.copy(r);U.id(r.account);U.id(r.target);U.id(r.life);U.id(r.match);U.id(r.policy)
        U.id(r.action);U.number(r.units,0,10,"unit increment");U.number(r.karma,-60,120,"target karma")
        assert(r.account~=r.target,"self effect cannot be a liability")
        assert(r.verdict=="WRONGFUL","only determined accountable effects may post")
        local key=r.match.."|"..r.account.."|"..r.life.."|"..r.policy
        return self:tx(receipt,"injury_or_control",r,function(s)
            assert(not s:get("terminals",r.match.."|"..r.life),"life already sealed")
            local m=assert(s:get("matches",r.match));assert(m.state~="REVEALED","late effect requires explicit reconciliation")
            local b=s:get("buckets",key) or {key=key,account=r.account,target=r.target,life=r.life,match=r.match,
                policy=r.policy,units=0,debits=0,credits=0,waived=0}
            assert(not b.decision,"closed financial decision")
            local before=b.units;b.units=math.min(10,b.units+r.units)
            local debit=P.loss(r.karma,b.units)-P.loss(r.karma,before)
            local applied,balance=adjust(s,r.account,-debit)
            b.debits=b.debits+math.max(0,-applied);s:put("buckets",key,b)
            return {bucket=key,requested=-debit,applied=applied,balance=balance,units=b.units,
                outstanding=b.debits-b.credits-b.waived}
        end)
    end
    local function outstanding(b)return math.max(0,b.debits-b.credits-b.waived)end
    local function reward(s,receipt,match,source,target,amount,kind)
        local claim=match.."|"..target
        local old=s:get("claims",claim)
        if old then return 0,"ALREADY_CLAIMED"end
        s:insert("claims",claim,{receipt=receipt,source=source,target=target,kind=kind})
        local applied=adjust(s,source,amount);return math.max(0,applied),"CLAIMED"
    end
    local terminal_categories={direct=true,medical=true,impulse=true,suicide=true,giveup=true,
        timeout=true,environment=true,objective=true,admin=true,unknown=true}
    function L:terminal(receipt,r)
        r=U.copy(r);U.id(r.match);U.id(r.life);U.id(r.target);U.id(r.policy)
        U.number(r.karma,-60,120);U.number(r.time,0,1e12);assert(terminal_categories[r.category],"invalid terminal category")
        if r.account then U.id(r.account)end
        local key=r.match.."|"..r.life
        return self:tx(receipt,"terminal",r,function(s)
            local old=s:get("terminals",key);if old then return {already_sealed=true,original=old.receipt,result=old.result}end
            local m=assert(s:get("matches",r.match));local adjustment,bounty=0,0;local claim="INELIGIBLE"
            local causal=(r.category=="direct" or r.category=="medical" or r.category=="impulse")
                and r.certified==true and r.account~=nil and r.account~=r.target
            local valid=causal and r.scored==true and not r.phase_exempt
            local bucket=r.account and (r.match.."|"..r.account.."|"..r.life.."|"..r.policy)
            local b=bucket and s:get("buckets",bucket)
            if valid and r.wrongful and P.value(r.karma)<=0 then
                b=b or {key=bucket,account=r.account,target=r.target,life=r.life,match=r.match,
                    policy=r.policy,units=0,debits=0,credits=0,waived=0}
                assert(not b.decision,"early financial decision")
                local desired=P.loss(r.karma,10);local need=desired-outstanding(b)
                if need>0 then
                    adjustment=adjust(s,r.account,-need);b.debits=b.debits+math.max(0,-adjustment)
                elseif need<0 then
                    adjustment=adjust(s,r.account,-need);b.credits=b.credits-need
                end
                s:put("buckets",bucket,b)
            end
            -- A justified terminal action or positive bounty does not erase earlier wrongdoing.
            if valid and not r.source_bot and not r.target_bot and P.bounty(r.karma)>0 then
                bounty,claim=reward(s,receipt,r.match,r.account,r.target,P.bounty(r.karma),"bounty")
            end
            local result={adjustment=adjustment,bounty=bounty,claim=claim,outstanding=b and outstanding(b) or 0,
                category=r.category,certified=causal,account=r.account,target=r.target,life=r.life}
            local expiry=nil
            if not m.hidden or m.state=="REVEALED" then expiry=r.time+C.review_seconds end
            local terminal={receipt=receipt,result=result,input=r,expires=expiry}
            s:insert("terminals",key,terminal)
            return result
        end)
    end
    function L:seal_match(match,receipt)
        U.id(match)
        return self:tx(receipt,"seal_match",{match},function(s)
            local m=assert(s:get("matches",match));assert(m.state=="ACTIVE" or m.state=="SEALED")
            m.state="SEALED";s:put("matches",match,m);return m
        end)
    end
    function L:reveal(match,time,receipt)
        U.id(match);U.number(time,0,1e12)
        return self:tx(receipt,"reveal",{match,time},function(s)
            local m=assert(s:get("matches",match));assert(m.state=="SEALED" or m.state=="REVEALED")
            if m.state=="REVEALED" then return m end
            m.state="REVEALED";m.revealed=time;s:put("matches",match,m)
            for key,t in pairs(s:scan("terminals")) do if t.input.match==match and not t.expires then
                t.expires=time+C.review_seconds;s:put("terminals",key,t)
            end end
            return m
        end)
    end
    function L:public(match,account)
        local m=assert(self.store:get("matches",match))
        if m.hidden and m.state~="REVEALED" then
            local snap=self.store:get("snapshots",match.."|"..account);return snap and snap.value or nil
        end
        local a=self.store:get("accounts",account);return a and a.balance or nil
    end
    function L:forgive(receipt,r)
        r=U.copy(r);U.id(r.victim);U.id(r.match);U.id(r.life);U.id(r.account);U.id(r.policy);U.number(r.time,0,1e12)
        return self:tx(receipt,"forgive",r,function(s)
            local m=assert(s:get("matches",r.match));assert(not m.hidden or m.state=="REVEALED","review unavailable")
            local t=assert(s:get("terminals",r.match.."|"..r.life),"review unavailable")
            assert(t.input.target==r.victim and t.expires and r.time<=t.expires,"review unavailable")
            local key=r.match.."|"..r.account.."|"..r.life.."|"..r.policy
            local b=assert(s:get("buckets",key),"no refundable loss");assert(b.target==r.victim and not b.decision,"decision complete")
            local waived=outstanding(b);assert(waived>0,"no refundable loss")
            local paid,balance=adjust(s,r.account,waived);b.waived=b.waived+waived;b.decision="forgive"
            s:put("buckets",key,b)
            return {waived=waived,paid=paid,clipped=waived-paid,balance=balance}
        end)
    end
    function L:respect(receipt,r)
        r=U.copy(r);U.id(r.victim);U.id(r.account);U.id(r.match);U.id(r.life);U.number(r.time,0,1e12)
        return self:tx(receipt,"respect",r,function(s)
            local m=assert(s:get("matches",r.match));assert(not m.hidden or m.state=="REVEALED","review unavailable")
            local t=assert(s:get("terminals",r.match.."|"..r.life));assert(t.expires and r.time<=t.expires,"review expired")
            assert(t.input.target==r.victim and t.input.account==r.account,"invalid case ownership")
            assert(t.input.respect_eligible==true and t.result.certified,"respect unavailable")
            local paid,reason=0,"ACKNOWLEDGED"
            if not t.input.source_bot and not t.input.target_bot and P.bounty(t.input.karma)==0 then
                paid,reason=reward(s,receipt,r.match,r.account,r.victim,U.money(C.respect),"respect")
            end
            return {paid=paid,reason=reason}
        end)
    end
    function L:outbox(receipt,input)
        local r=U.copy(input);U.id(r.id);U.id(r.account);U.id(r.match)
        assert(r.kind=="dose" or r.kind=="sanction","invalid outbox kind")
        if r.kind=="dose" then U.number(r.amount,0,C.brain.life_cap,"dose")
        else U.integer(r.minutes,1,60,"sanction duration")end
        return self:tx(receipt,"outbox",r,function(s)
            local row=U.copy(r);row.state="PENDING";s:insert("outbox",r.id,row);return row
        end)
    end
    function L:delivery(receipt,id,expected,next_state,generation)
        U.id(id);U.id(generation)
        assert((expected=="PENDING" and next_state=="RESERVED") or (expected=="RESERVED" and
            (next_state=="DELIVERED" or next_state=="REVIEW")),"invalid delivery transition")
        return self:tx(receipt,"delivery",{id,expected,next_state,generation},function(s)
            local r=assert(s:get("outbox",id));assert(r.state==expected,"delivery state changed")
            assert(not r.generation or r.generation==generation,"wrong delivery generation")
            r.state=next_state;r.generation=generation;s:put("outbox",id,r);return r
        end)
    end
    return L
end
