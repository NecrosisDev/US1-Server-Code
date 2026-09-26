return function(U,C)
    local L={};L.__index=L
    function L.new(namespace)
        return setmetatable({namespace=U.id(namespace),serial=0,lives={},active={},match=nil},L)
    end
    function L:id(kind) self.serial=self.serial+1;return self.namespace..":"..kind..":"..self.serial end
    function L:start_match(id,hidden)
        U.id(id);assert(not self.match or self.match.status=="REVEALED","prior match not revealed")
        self.match={id=id,hidden=hidden==true,status="ACTIVE",snapshots={}}
        return U.copy(self.match)
    end
    function L:snapshot(account,karma)
        account=U.id(account);assert(self.match and self.match.status=="ACTIVE")
        U.integer(karma,C.minimum,C.maximum,"balance")
        local s=self.match.snapshots
        if s[account]==nil then s[account]=karma end
        return s[account]
    end
    function L:provisional(account)
        account=U.id(account);assert(self.match and self.match.status=="ACTIVE")
        local prior=self.active[account]
        assert(not prior or self.lives[prior].state=="DEAD_FINAL" or self.lives[prior].state=="ABORTED","active logical life exists")
        local id=self:id("life")
        local life={id=id,account=account,match=self.match.id,state="PROVISIONAL",body=1,organism=1,terminals={}}
        self.lives[id]=life;self.active[account]=id;return U.copy(life)
    end
    function L:activate(id)
        local l=assert(self.lives[id]);assert(l.state=="PROVISIONAL");l.state="ACTIVE";return U.copy(l)
    end
    function L:abort(id)
        local l=assert(self.lives[id]);assert(l.state=="PROVISIONAL");l.state="ABORTED"
        if self.active[l.account]==id then self.active[l.account]=nil end
        return U.copy(l)
    end
    function L:body(id,organism_changed)
        local l=assert(self.lives[id]);assert(l.state=="ACTIVE" or l.state=="DOWNED")
        l.body=l.body+1;if organism_changed then l.organism=l.organism+1 end;return U.copy(l)
    end
    function L:down(id,value)
        local l=assert(self.lives[id]);assert(l.state=="ACTIVE" or l.state=="DOWNED")
        l.state=value and "DOWNED" or "ACTIVE";return U.copy(l)
    end
    function L:token(id)
        local l=assert(self.lives[id]);return {life=id,match=l.match,body=l.body,organism=l.organism}
    end
    function L:valid(t)
        local l=t and self.lives[t.life]
        return l~=nil and (l.state=="ACTIVE" or l.state=="DOWNED") and l.match==t.match
            and l.body==t.body and l.organism==t.organism and self.match.id==t.match and self.match.status=="ACTIVE"
    end
    function L:dying(id)
        local l=assert(self.lives[id]);if l.state=="DEAD_FINAL" then return false end
        assert(l.state=="ACTIVE" or l.state=="DOWNED" or l.state=="DYING_PENDING_SEAL")
        l.state="DYING_PENDING_SEAL";return true
    end
    function L:seal(id,receipt)
        local l=assert(self.lives[id]);U.id(receipt)
        if l.state=="DEAD_FINAL" then return false,l.receipt end
        assert(l.state=="DYING_PENDING_SEAL");l.state="DEAD_FINAL";l.receipt=receipt
        return true,receipt
    end
    function L:seal_match()
        assert(self.match and self.match.status=="ACTIVE");self.match.status="SEALED"
    end
    function L:reveal_match()
        assert(self.match and self.match.status=="SEALED");self.match.status="REVEALED"
    end
    return L
end
