-- Physical projectiles: keep a private launch binding through deferred Think calls.
-- Does not edit bullet fields, trajectories, damage values, RNG, or network schemas.
return function(R,B)
    local function player(p)return IsValid(p)and p:IsPlayer()end
    local function weak()return setmetatable({},{__mode="k"})end
    function R:PhysicalPrepare(bullet)
        self.physical=self.physical or weak()
        if self.physical[bullet]then return self.physical[bullet]end
        local source=bullet.Shooter or bullet.Attacker
        if not player(source)then return nil end
        local parent=self.scope[#self.scope]
        local pending
        if parent and parent.source==source and (parent.discharge_group or parent.physical_group)then pending=parent end
        pending=pending or self:Prepare(source,"firearm","physical_projectile")
        if not pending then return nil end
        pending.physical_group=true;pending.holds=pending.holds or weak()
        pending.holds[bullet]=true;self.physical[bullet]=pending
        self.stats.physical_created=(self.stats.physical_created or 0)+1
        return pending
    end
    function R:PhysicalRelease(bullet)
        local pending=self.physical and self.physical[bullet]
        if not pending or not bullet.Removed then return end
        self.physical[bullet]=nil
        if pending.holds then pending.holds[bullet]=nil end
        self.stats.physical_retired=(self.stats.physical_retired or 0)+1
        self:Finish(pending)
    end
    function R:DispatchObserved(target,info,trace)
        local pending=self.scope[#self.scope]
        if not pending or pending.closed then return end
        local record=self:FindDamage(info,target)or self:BindDamage(pending,info,target)
        if record and pending.physical_group then
            record.physical_dispatch=true
            self.stats.physical_dispatch=(self.stats.physical_dispatch or 0)+1
            -- A real direct impact is recorded. It does not certify an entire
            -- flight path, unseen near miss, or deliberate ricochet target.
            record.actual_hit=trace and trace.Hit==true or false
        end
    end
    function R:InstallPhysical()
        local selfref=self
        local entity=FindMetaTable("Entity")
        self:Wrap(entity,"DispatchTraceAttack","accepted_trace_dispatch",function(original)
            return function(target,info,trace,...)
                selfref:Safe(selfref.DispatchObserved,target,info,trace)
                return selfref:WithDamage(selfref.scope[#selfref.scope],target,info,original,target,info,trace,...)
            end
        end)
        local plugin=hg and hg.PhysBullet
        if not plugin or not plugin.Class_Bullet then
            self.coverage.phys_projectiles="plugin_unavailable";return
        end
        local class=plugin.Class_Bullet
        self.physical=weak()
        self:Wrap(plugin,"CreateBullet","physical_launch",function(original)
            return function(bullet,...)
                if not selfref.enabled or type(bullet)~="table"then return original(bullet,...)end
                local pending=selfref:Safe(selfref.PhysicalPrepare,bullet)
                return selfref:Scope(pending,original,bullet,...)
            end
        end)
        self:Wrap(class,"Think","physical_steps",function(original)
            return function(bullet,...)
                local pending=selfref.physical[bullet]
                return selfref:Scope(pending,original,bullet,...)
            end
        end)
        self:Wrap(class,"Remove","physical_retire",function(original)
            return function(bullet,...)
                local result=B.U.pack(pcall(original,bullet,...))
                if result[1]then selfref:Safe(selfref.PhysicalRelease,bullet)end
                if not result[1]then error(result[2],0)end
                return unpack(result,2,result.n)
            end
        end)
        self.coverage.phys_projectiles="launch_and_accepted_dispatch_connected_flight_segments_pending"
    end
end
