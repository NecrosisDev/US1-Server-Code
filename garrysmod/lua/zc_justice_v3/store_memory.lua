-- Transactional test backend. Production uses the checked SQLite adapter.
return function(U)
    local S={};S.__index=S
    function S.new()return setmetatable({data={},busy=false,fail_after=nil,writes=0},S)end
    function S:get(space,key)local r=self.data[space] and self.data[space][key];return r and U.copy(r)end
    function S:put(space,key,value)
        assert(self.busy,"write outside transaction")
        self.writes=self.writes+1
        if self.fail_after and self.writes>=self.fail_after then error("injected persistence failure")end
        self.data[space]=self.data[space] or {};self.data[space][key]=U.copy(value)
    end
    function S:insert(space,key,value)assert(not self:get(space,key),"duplicate key");self:put(space,key,value)end
    function S:scan(space)return U.copy(self.data[space] or {})end
    function S:transaction(fn)
        if self.busy then return false,"transaction already owned" end
        local before=U.copy(self.data);self.busy=true;self.writes=0
        local result=U.pack(pcall(fn,self));self.busy=false
        if not result[1] then self.data=before;return false,tostring(result[2])end
        return true,(unpack or table.unpack)(result,2,result.n)
    end
    return S
end
