-- Trusted weapon-method adapters. No HP/organ/karma writes and no client output.
return function(R,B)
    local U,C=B.U,B.C
    local function isplayer(p)return IsValid(p)and p:IsPlayer()end
    local function weak()return setmetatable({},{__mode="k"})end
    local function ret(t)if not t[1]then error(t[2],0)end;return unpack(t,2,t.n)end
    function R:ContactObserved(pending,target,trace)
        if not pending or pending.closed then return end
        local p=self:Receiver(target);local t=p and self:Actor(p)
        if not t or not pending.action.targets[t.life]then return end
        if trace and trace.Entity~=target then return end
        self:Confirm(pending)
        local visible=self:Visible(p,pending.source)
        local observations={directed=true,observed_source=visible,observation_complete=true,witnesses={}}
        for _,helper in ipairs(player.GetAll())do
            if helper~=p and helper~=pending.source and self:Visible(helper,pending.source)then
                local h=self:Actor(helper);local eye=self:View(helper)
                if h and eye then observations.witnesses[h.life]={visible=true,participating=true,
                    distance=eye:Distance(pending.source:WorldSpaceCenter())}end
            end
        end
        self.adjudicator:observe(pending.action.id,t.life,observations)
        pending.contacts=pending.contacts or {};pending.contacts[t.life]=observations
        self.stats.contact_observations=(self.stats.contact_observations or 0)+1
    end
    function R:ControlAccepted(pending,p,kind,origin)
        if not pending or not isplayer(p)then return end
        local t=self:Actor(p)
        if not t or not pending.action.targets[t.life]then return end
        self:ContactObserved(pending,p)
        if not pending.confirmed then return end
        pending.control_seen=pending.control_seen or {}
        if pending.control_seen[t.life]then return end
        local id=self:Next("control");pending.control_seen[t.life]=id
        self.adjudicator:effect(pending.action.id,{id=id,target_life=t.life,time=self:Clock(),
            accepted=true,harm=0,damage=0,control=kind,serious=true,lethal=false})
        self.stats.control_effects=(self.stats.control_effects or 0)+1
        self:Summary({reason="CONTROL_ACCEPTED_"..origin,source=pending.action.account,
            target=t.account,target_life=t.life,harm=0,control=kind,proposed_debit=0})
        return t.life
    end
    function R:HandsProfile(weapon,special)
        local owner=weapon:GetOwner();local org=owner and owner.organism
        local inv=owner and owner.GetNetVar and owner:GetNetVar("Inventory",{})or {}
        if special or not org or org.superfighter or (U.finite(org.berserk)and org.berserk>0)
            or (inv.Weapons and inv.Weapons.hg_brassknuckles)
            or (owner.MeleeDamageMul and owner.MeleeDamageMul>1)
            or (weapon.DamageMul and weapon.DamageMul>1)
            or owner.PlayerClassName=="furry"or owner.PlayerClassName=="headcrabzombie"then
            return "dangerous_melee"
        end
        return "ordinary_unarmed"
    end
    function R:Swing(weapon)
        if not IsValid(weapon)or not weapon.GetInAttack or not weapon:GetInAttack()then return nil end
        local source=weapon:GetOwner();if not isplayer(source)then return nil end
        local actor=self:Actor(source);if not actor then return nil end
        local stamp=weapon:GetAttackTime();local attack=weapon:GetAttackType()
        local old=self.swings[weapon]
        if old and not old.closed and old.stamp==stamp and old.attacktype==attack
            and old.action.life==actor.life and old.action.match==self.observer.round then return old end
        if old then old.hold_open=false;self:Finish(old)end
        local pending=self:Prepare(source,"dangerous_melee","melee_swing")
        if pending then
            pending.stamp=stamp;pending.attacktype=attack;pending.hold_open=true
            self.swings[weapon]=pending
        end
        return pending
    end
    function R:SwingEnd(weapon,pending)
        if not pending then return end
        if not IsValid(weapon)or not weapon:GetInAttack()or weapon:GetAttackTime()~=pending.stamp then
            pending.hold_open=false;self:Finish(pending)
            if self.swings[weapon]==pending then self.swings[weapon]=nil end
        end
    end
    function R:WireState(weapon)
        if not IsValid(weapon)or not weapon.GetStrangling or not weapon:GetStrangling()then return nil end
        local source,rag=weapon:GetOwner(),weapon.StrangleRag
        if not isplayer(source)or not source:Alive()or not IsValid(rag)
            or rag.Strangler~=source or rag.StrangleLocked~=true then return nil end
        local target=self:Receiver(rag)
        if not isplayer(target)or not target:Alive()or target==source then return nil end
        return source,target,rag
    end
    function R:StartWire(weapon,pending,was_active)
        if was_active or not pending then return end
        local source,target,rag=self:WireState(weapon)
        if not source or source~=pending.source then return end
        local life=self:ControlAccepted(pending,target,"danger","CHOKE")
        if not life then return end
        local session={action=pending.action.id,source=source,account=pending.action.account,source_life=pending.action.life,
            target=target,life=life,rag=rag,org=target.organism,match=pending.action.match,
            since=self:Clock(),last=self:Clock(),closed=false}
        self.wire[weapon]=session
        if self.MedicalWireStart then self:MedicalWireStart(session,pending)end
        self.stats.chokes_started=(self.stats.chokes_started or 0)+1
    end
    function R:EndWire(weapon,session,reason)
        if not session or session.closed then return end
        session.closed=true;session.reason=reason
        local id=session.action.."/"..session.life
        local root=self.adjudicator.roots[id]
        if root then self.adjudicator:release(id,math.max(self:Clock(),root.last))end
        if self.wire[weapon]==session then self.wire[weapon]=nil end
        self.stats.chokes_released=(self.stats.chokes_released or 0)+1
        self:Summary({reason="CHOKE_RELEASED_"..reason,source=session.account,
            target_life=session.life,harm=0,proposed_debit=0})
    end
    function R:WireStep(weapon)
        local session=self.wire[weapon];if not session then return end
        local source,target,rag=self:WireState(weapon)
        if not source or source~=session.source or target~=session.target or rag~=session.rag
            or target.organism~=session.org or self:Actor(source).life~=session.source_life
            or self:Actor(target).life~=session.life or self.observer.round~=session.match then
            self:EndWire(weapon,session,"STATE_END");return
        end
        local now=self:Clock();if now-session.last<0.25 then return end
        session.last=now
        local id=session.action.."/"..session.life;local root=self.adjudicator.roots[id]
        if root then self.adjudicator:heartbeat(id,math.max(now,root.last),true)end
        self.stats.control_heartbeats=(self.stats.control_heartbeats or 0)+1
    end
    function R:ControlTick()
        for weapon,pending in pairs(self.swings)do
            local source=pending.source
            if not IsValid(weapon)or not isplayer(source)or not source:Alive()
                or self:Actor(source).life~=pending.action.life or self.observer.round~=pending.action.match then
                pending.hold_open=false;self:Finish(pending);self.swings[weapon]=nil
            else self:SwingEnd(weapon,pending)end
        end
        if self:Clock()<(self.next_control_check or 0)then return end
        self.next_control_check=self:Clock()+0.25
        for weapon,session in pairs(self.wire)do
            -- A watchdog closes a lost control; only the native Think path refreshes it.
            if not IsValid(weapon)or self:Clock()-session.last>1 then self:EndWire(weapon,session,"HEARTBEAT_EXPIRED")end
        end
    end
    function R:InstallControls()
        local selfref=self;self.swings=weak();self.wire={}
        local get=weapons and weapons.GetStored
        if not get then return end
        local hands=get("weapon_hands_sh")
        self:Wrap(hands,"AttackFront","hands_committed_method",function(original)
            return function(weapon,special,...)
                local pending=selfref:Safe(function(s)
                    return s:Prepare(weapon:GetOwner(),s:HandsProfile(weapon,special),"hands")
                end)
                return selfref:Scope(pending,original,weapon,special,...)
            end
        end)
        self:Wrap(hands,"BlockingLogic","hands_trace_observation",function(original)
            return function(weapon,target,mul,attack,trace,...)
                local pending=selfref.scope[#selfref.scope]
                if pending and pending.descriptor=="hands"then selfref:Safe(selfref.ContactObserved,pending,target,trace)end
                return original(weapon,target,mul,attack,trace,...)
            end
        end)
        local melee=get("weapon_melee")
        self:Wrap(melee,"CustomThink","melee_action_scope",function(original)
            return function(weapon,...)
                local pending=selfref:Safe(selfref.Swing,weapon)
                local out=U.pack(pcall(selfref.Scope,selfref,pending,original,weapon,...))
                selfref:Safe(selfref.SwingEnd,weapon,pending)
                return ret(out)
            end
        end)
        self:Wrap(melee,"Attack","melee_trace_observation",function(original)
            return function(weapon,...)
                local out=U.pack(pcall(original,weapon,...))
                local pending=selfref.scope[#selfref.scope]
                if out[1]and pending and pending.descriptor=="melee_swing"and type(out[2])=="table"then
                    selfref:Safe(selfref.ContactObserved,pending,out[2].Entity,out[2])
                end
                return ret(out)
            end
        end)
        self:Wrap(get("weapon_handcuffs"),"Tie","handcuff_acceptance",function(original)
            return function(weapon,trace,...)
                local pending=selfref:Safe(selfref.Prepare,weapon:GetOwner(),"restrict","cuffs")
                local victim=selfref:Safe(selfref.Receiver,trace and trace.Entity)
                local org=victim and victim.organism;local before=org and org.handcuffed
                local args=U.pack(...)
                return selfref:Scope(pending,function()
                    local out=U.pack(pcall(original,weapon,trace,U.unpack(args)))
                    if pending and org and not before and IsValid(victim)and victim.organism==org and org.handcuffed==true then
                        selfref:Safe(selfref.ControlAccepted,pending,victim,"restrict","CUFFS")
                    end
                    return ret(out)
                end)
            end
        end)
        local wire=get("weapon_zc_fiberwire_standalone")
        for _,key in ipairs({"CustomAttack","PrimaryAttackAdd"})do
            self:Wrap(wire,key,"fiberwire_"..key,function(original)
                return function(weapon,...)
                    local was=selfref:Safe(function(s)return s:WireState(weapon)~=nil end)
                    local pending=not was and selfref:Safe(selfref.Prepare,weapon:GetOwner(),"choke","fiberwire")or nil
                    local args=U.pack(...)
                    return selfref:Scope(pending,function()
                        local out=U.pack(pcall(original,weapon,U.unpack(args)))
                        selfref:Safe(selfref.StartWire,weapon,pending,was)
                        return ret(out)
                    end)
                end
            end)
        end
        self:Wrap(wire,"CustomThink","fiberwire_maintenance",function(original)
            return function(weapon,...)
                local out=U.pack(pcall(original,weapon,...))
                if out[1]then selfref:Safe(selfref.WireStep,weapon)end
                return ret(out)
            end
        end)
        for _,key in ipairs({"PrimaryAttack","OnRemove","OnDrop","Holster"})do
            self:Wrap(wire,key,"fiberwire_release_"..key,function(original)
                return function(weapon,...)
                    local out=U.pack(pcall(original,weapon,...));selfref:Safe(selfref.WireStep,weapon);return ret(out)
                end
            end)
        end
        self:Add("Think","ControlLifetimes",R.ControlTick,2)
        self.coverage.melee="hands_and_melee_committed_scopes_observer_only"
        self.coverage.restraints="cuffs_fiberwire_acceptance_and_maintenance_observer_only"
    end
end
