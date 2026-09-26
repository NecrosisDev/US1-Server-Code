-- Exact native mutation scopes: receiver-specific, nested, and private.
return function(R,B)
    local U=B.U
    function R:WithDamage(pending,target,info,fn,...)
        if not self.enabled or not pending or pending.closed then return fn(...)end
        local source=info and info.GetAttacker and info:GetAttacker()
        -- Only an already authenticated physical launch may outlive its player entity.
        if not pending.physical_group and source~=pending.source then return fn(...)end
        local record=self:Safe(function(s)
            local p=s:Receiver(target);local actor=p and s:Actor(p)
            if not actor or not pending.action.targets[actor.life]then return nil end
            local top=s.effect_stack[#s.effect_stack]
            if top and top.pending==pending and top.life==actor.life and top.info==info
                and top.physical_target==p and target==p.FakeRagdoll then
                s.stats.forwarded_aliases=(s.stats.forwarded_aliases or 0)+1
                return top
            end
            return s:BindDamage(pending,info,target,top~=nil)
        end)
        if not record then return fn(...)end
        record.active_depth=(record.active_depth or 0)+1
        self.effect_stack[#self.effect_stack+1]=record
        local out=U.pack(pcall(fn,...))
        if self.effect_stack[#self.effect_stack]~=record then self:Issue("effect_scope","mutation unwind mismatch")end
        self.effect_stack[#self.effect_stack]=nil;record.active_depth=record.active_depth-1
        local parent=self.effect_stack[#self.effect_stack]
        if parent and parent.info==info then self.damage[info]=parent end
        if record.active_depth==0 and not record.completed then
            self:Safe(function(s)
                if record.scoped then s:Accepted(record,record.harm)
                elseif out[1]then s:PostDamage(target,info,true)end
            end)
        end
        if not out[1]then error(out[2],0)end
        return unpack(out,2,out.n)
    end
    function R:BeginNativeDamage(target,info)
        local pending=self.scope[#self.scope]
        if not pending or pending.closed or not info or not info.GetAttacker then return end
        if not pending.physical_group and info:GetAttacker()~=pending.source then return end
        local p=self:Receiver(target);local actor=p and self:Actor(p)
        if not actor or not pending.action.targets[actor.life]then return end
        local active=self.effect_stack[#self.effect_stack]
        local r
        if active and active.pending==pending and active.life==actor.life then r=active
        else r=self:BindDamage(pending,info,target,true)end
        if not r then return end
        local stack=self.native_frames[target]or {};self.native_frames[target]=stack
        stack[#stack+1]={pending=pending,record=r,life=actor.life}
        self.damage[info]=r
    end
    function R:EndNativeDamage(target,info,took)
        local pending=self.scope[#self.scope]
        local stack=self.native_frames[target]
        local frame=stack and stack[#stack]
        if not pending or not frame or frame.pending~=pending then return end
        local p=self:Receiver(target);local actor=p and self:Actor(p)
        stack[#stack]=nil
        if not actor or actor.life~=frame.life then return end
        self.damage[info]=frame.record
        self:PostDamage(target,info,took)
    end
    function R:ClearNativeFrames(pending)
        for target,stack in pairs(self.native_frames or {})do
            local kept={}
            for _,frame in ipairs(stack)do if frame.pending~=pending then kept[#kept+1]=frame end end
            self.native_frames[target]=#kept>0 and kept or nil
        end
    end
    function R:InstallEffects()
        local selfref=self
        self.native_frames=setmetatable({},{__mode="k"})
        self:Add("EntityTakeDamage","EngineBegin",R.BeginNativeDamage,-3)
        self:Add("PostEntityTakeDamage","EngineEnd",R.EndNativeDamage,3)
        self:Wrap(FindMetaTable("Entity"),"TakeDamageInfo","direct_damage_scope",function(original)
            return function(target,info,...)
                return selfref:WithDamage(selfref.scope[#selfref.scope],target,info,original,target,info,...)
            end
        end)
    end
end
