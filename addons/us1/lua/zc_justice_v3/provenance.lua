-- Private sidecar. Never attaches justice metadata to a replicated game object.
return function(U,C)
    local R={};R.__index=R
    function R.new(namespace)
        return setmetatable({namespace=U.id(namespace),serial=0,conditions={},reservoirs={},items={},
            bindings=setmetatable({},{__mode="k"}),tokens={},contexts={},seen={}},R)
    end
    function R:id(kind)self.serial=self.serial+1;return self.namespace..":"..kind..":"..self.serial end
    function R:push(context)
        assert(#self.contexts<C.capacity.contexts,"context overflow")
        local c=U.copy(context);U.id(c.action);U.id(c.life)
        local token={};self.contexts[#self.contexts+1]={token=token,data=c};return token
    end
    function R:peek()
        local c=self.contexts[#self.contexts];return c and U.copy(c.data)
    end
    function R:pop(token)
        local top=self.contexts[#self.contexts];assert(top and top.token==token,"context unwind mismatch")
        self.contexts[#self.contexts]=nil
    end
    function R:scoped(context,fn,...)
        local token=self:push(context);local args=U.pack(...)
        local result=U.pack(pcall(fn,U.unpack(args)))
        self:pop(token)
        if not result[1] then error(result[2],0) end
        return (unpack or table.unpack)(result,2,result.n)
    end
    function R:condition(input,object)
        local c=U.copy(input)
        U.id(c.life);U.id(c.action);U.id(c.kind)
        assert(type(c.verdict)=="string","condition verdict missing")
        if c.account then U.id(c.account) end
        U.integer(c.organism,1,1e12,"organism generation")
        local id=self:id("condition");c.id=id;c.active=true;self.conditions[id]=c
        if object then self:bind(object,id) end
        return id
    end
    function R:bind(object,id)
        assert(type(object)=="table" or type(object)=="userdata","object required")
        assert(self.conditions[id],"unknown condition")
        local b=self.bindings[object] or {};self.bindings[object]=b;b[id]=true
    end
    function R:merge(destination,source)
        local b=self.bindings[source];if not b then return false end
        for id in pairs(b) do self:bind(destination,id) end
        if destination~=source then self.bindings[source]=nil end
        return true
    end
    function R:clone(destination,source)
        for id in pairs(self.bindings[source] or {}) do self:bind(destination,id) end
    end
    function R:close(id)
        local c=assert(self.conditions[id]);c.active=false
        -- Reservoir losses already caused by this condition deliberately remain.
    end
    function R:loss(receipt,life,channel,amount,condition)
        U.id(receipt);U.id(life);U.id(channel);U.integer(amount,0,1e12,"loss units")
        condition=condition or "unknown"
        if condition~="unknown" and condition~="environment" and condition~="preexisting" then
            local c=assert(self.conditions[condition],"missing condition");assert(c.life==life,"wrong life")
        end
        local sig=U.canonical({life,channel,amount,condition})
        if self.seen[receipt] then assert(self.seen[receipt]==sig,"conflicting reservoir replay");return false end
        local key=life.."|"..channel;local r=self.reservoirs[key] or {};self.reservoirs[key]=r
        r[condition]=(r[condition] or 0)+amount;self.seen[receipt]=sig;return true
    end
    function R:restore(receipt,life,channel,amount,target)
        U.id(receipt);U.id(life);U.id(channel);U.integer(amount,0,1e12,"restoration")
        local sig=U.canonical({life,channel,amount,target,"restore"})
        if self.seen[receipt] then assert(self.seen[receipt]==sig,"conflicting restoration replay");return false end
        local r=self.reservoirs[life.."|"..channel] or {};local sum=0
        for _,v in pairs(r) do sum=sum+v end
        local applied=math.min(amount,target and (r[target] or 0) or sum)
        if target then r[target]=(r[target] or 0)-applied
        elseif applied>0 then
            local allocation=U.allocate(applied,r)
            for id,value in pairs(allocation) do r[id]=r[id]-value end
        end
        self.seen[receipt]=sig;return true,applied
    end
    function R:outstanding(life,channel)
        local result=U.copy(self.reservoirs[life.."|"..channel] or {});local total=0
        for _,v in pairs(result) do total=total+v end
        return total,result
    end
    function R:terminal_support(life,channel,certified_condition)
        local _,weights=self:outstanding(life,channel)
        if certified_condition then
            local c=assert(self.conditions[certified_condition]);assert(c.life==life)
            return {status="CERTIFIED_BRANCH",condition=c.id,account=c.account,verdict=c.verdict,action=c.action}
        end
        local account,verdict=nil,nil;local count=0
        for id,value in pairs(weights) do if value>0 then
            local c=self.conditions[id]
            if not c or not c.account then return {status="UNRESOLVED_CAUSE"} end
            if account and (account~=c.account or verdict~=c.verdict) then return {status="MIXED_CAUSE"} end
            account,verdict=c.account,c.verdict;count=count+1
        end end
        -- Consistent attribution is useful but cannot itself certify the terminal branch.
        return {status=count>0 and "CONSISTENT_SUPPORT" or "NO_SUPPORT",account=account,verdict=verdict}
    end
    function R:contaminate(item,batch)
        U.id(item);local b=U.copy(batch);U.id(b.id);U.id(b.action)
        U.number(b.quantity,0,1e12,"quantity");if b.account then U.id(b.account) end
        local it=self.items[item] or {batches={},generation=1};self.items[item]=it
        if it.batches[b.id] then assert(U.equal(it.batches[b.id],b),"conflicting contamination");return false end
        it.batches[b.id]=b;return true
    end
    function R:transfer(from,to)
        U.id(from);U.id(to);assert(from~=to and not self.items[to],"invalid item replacement")
        local item=assert(self.items[from]);self.items[to]=item;self.items[from]=nil
        item.generation=item.generation+1
    end
    function R:deliver(item,life,organism,receipt)
        U.id(receipt);local it=assert(self.items[item]);local ids={}
        local sig=U.canonical({item,life,organism,"dose"})
        if self.seen[receipt] then assert(self.seen[receipt]==sig);return false end
        for _,id in ipairs(U.keys(it.batches)) do
            local b=it.batches[id]
            ids[#ids+1]=self:condition({life=life,organism=organism,action=b.action,kind="contamination",
                account=b.account,quantity=b.quantity,verdict=b.verdict or "UNRESOLVED"})
        end
        self.seen[receipt]=sig;it.batches={};return true,ids
    end
    return R
end
