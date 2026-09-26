-- Source-connected predictive runtime. Deliberately no account/gameplay writer.
-- The same pure adjudicator is exercised using real accepted-effect records.
return function(B,G)
    local U,C=B.U,B.C
    local R={};R.__index=R
    local function weak()return setmetatable({},{__mode="k"})end
    local function isplayer(p)return IsValid(p) and p:IsPlayer()end
    local function vec(v)return {v.x,v.y,v.z}end
    local function pack(...)return {n=select("#",...),...}end
    local function unpacked(t)return unpack(t,1,t.n)end
    local DATA="zc_justice_v3_shadow"
    function R.new(observer)
        local self=setmetatable({observer=observer,version="3.3.0-shadow.2",enabled=true,
            adjudicator=B.Adjudicator.new(),provenance=B.Provenance.new("source:"..observer.session),
            prepared=weak(),damage=weak(),wounds=weak(),by_life={},scope={},pending={},
            selected=weak(),groups={},hooks={},wrappers={},serial=0,epoch=0,effect_stack={},
            profiles={},telemetry={},summary={},summary_count=0,stats={committed=0,effects=0,
                scoped_harm=0,unscoped_harm=0,traces=0,directed=0,predictions=0,
                source_unknown=0,unknown_terminal=0,errors=0,public_writes=0,financial_writes=0},
            coverage={custom_hitscan="connected_callback_and_real_trace",native_hitscan="connected_callback",
                phys_projectiles="pending_explicit_segment_adapter",melee="accepted_hit_scoped_only",
                explosions="pending_launch_control_adapter",medical="private_wound_bindings_only",
                terminal="unknown_until_certified_branch",restraints="pending_commit_adapters",
                ledger="tested_library_not_live_writer"}},R)
        return self
    end
    function R:Next(kind)
        self.serial=self.serial+1;return "j:"..self.observer.session..":"..kind..":"..self.serial
    end
    -- Player command execution can temporarily change CurTime. Event ordering
    -- uses the authoritative server tick; source geometry keeps its own sample time.
    function R:Clock()
        local tick=engine.TickCount()
        local interval=engine.TickInterval and engine.TickInterval()or 0.02
        U.integer(tick,0,9007199254740991,"server tick")
        U.number(interval,0.000001,1,"server tick interval")
        return tick*interval
    end
    function R:Issue(code,detail)
        self.stats.errors=self.stats.errors+1
        self.last_error={code=code,detail=tostring(detail):sub(1,500),time=os.time()}
        -- Failure cannot fall through to a guessed new financial decision.
        self.enabled=false
        pcall(function()self:WriteStatus()end)
        if not self.warned then self.warned=true;ErrorNoHalt("[Justice integration] Capture paused; inspect private status. Existing scoring unchanged.\n")end
    end
    function R:Safe(method,...)
        if not self.enabled then return nil end
        local start=SysTime();local result=pack(pcall(method,self,...))
        local elapsed=SysTime()-start
        self.profile_serial=(self.profile_serial or 0)+1
        self.telemetry[(self.profile_serial%1024)+1]=elapsed
        self.maximum_ms=math.max(self.maximum_ms or 0,elapsed*1000)
        if not result[1]then self:Issue("adapter",result[2]);return nil end
        return unpack(result,2,result.n)
    end
    function R:Actor(p)
        local actor=self.observer:Actor(p)
        if actor then self.by_life[actor.life]=p end
        return actor
    end
    function R:Receiver(ent)
        return self.observer:ResolveReceiver(ent)
    end
    function R:View(p)
        -- Do not pretend the hidden carrier is an authenticated remote viewpoint.
        local view=p.GetViewEntity and p:GetViewEntity()
        if IsValid(view) and view~=p then return nil end
        if ZCityPillCompat and ZCityPillCompat.Morph and IsValid(ZCityPillCompat.Morph(p))then return nil end
        if p:GetNWEntity("kamikaze_"):IsValid() or p:GetNWEntity("active_mavic"):IsValid()then return nil end
        return p:EyePos()
    end
    function R:Visible(p,source,point)
        if not isplayer(p)or not p:Alive()or p:Team()>=1000 then return false end
        local eye=self:View(p);if not eye then return false end
        local target=point or source:WorldSpaceCenter()
        if eye:DistToSqr(target)>1024*1024 then return false end
        local trace=util.TraceLine({start=eye,endpos=target,mask=MASK_VISIBLE,
            filter={p,p.FakeRagdoll,source,source.FakeRagdoll}})
        return not trace.Hit
    end
    function R:Shapes(p)
        local ent=IsValid(p.FakeRagdoll)and p.FakeRagdoll or p
        if ZCityPillCompat and ZCityPillCompat.Morph then
            local morph=ZCityPillCompat.Morph(p)
            if IsValid(morph)then
                local puppet=morph.GetPuppet and morph:GetPuppet()
                ent=IsValid(puppet)and puppet or morph
            end
        end
        local shapes={};local set=ent.GetHitboxSet and ent:GetHitboxSet()or 0
        local count=ent.GetHitBoxCount and ent:GetHitBoxCount(set)or 0
        for i=0,math.min(count or 0,40)-1 do
            local bone=ent:GetHitBoxBone(i,set)
            local matrix=bone and ent:GetBoneMatrix(bone)
            if matrix then
                local lo,hi=ent:GetHitBoxBounds(i,set);local ang=matrix:GetAngles()
                shapes[#shapes+1]={origin=vec(matrix:GetTranslation()),mins=vec(lo),maxs=vec(hi),
                    axes={vec(ang:Forward()),vec(-ang:Right()),vec(ang:Up())}}
            end
        end
        -- Hull is not a hurtbox: missing hitbox data remains a coverage gap.
        return shapes
    end
    function R:Prepare(source,method,descriptor)
        source=self:Receiver(source)or source
        if not isplayer(source)then return nil end
        local mode=self.observer:Mode();self.observer:CheckRound(mode)
        local actor=self:Actor(source);if not actor then return nil end
        local targets,entities={},{}
        for _,p in ipairs(player.GetAll())do
            if p~=source and p:Alive()and p:Team()<1000 then
                local t=self:Actor(p)
                if t then
                    targets[t.life]={account=t.account,life=t.life,karma=t.karma,
                        relation=B.Modes.relation(mode,actor,t),context_complete=false,
                        traitor_pair=actor.traitor and t.traitor,phase_exempt=t.exempt,
                        observed_source=false,observation_complete=false,directed=false,witnesses={}}
                    entities[t.life]=p
                end
            end
        end
        local action={id=self:Next("action"),seq=self.serial,match=self.observer.round,
            life=actor.life,account=actor.account,policy=C.policy,batch=tostring(engine.TickCount()),
            time=self:Clock(),sampled_curtime=CurTime(),method=method,source_known=true,scored=mode.scored and zb.ROUND_STATE==1,
            committed=true,profile_known=method~="unknown",context_complete=false,
            phase_exempt=actor.exempt,targets=targets}
        local pending={action=action,source=source,source_actor=actor,entities=entities,
            descriptor=descriptor,confirmed=false,closed=false,effects={},traced={},scopes=0}
        -- Until full source coverage exists, missing context cannot convict a player.
        -- Confirmed defensive outcomes still exercise the real prior-state model.
        return pending
    end
    function R:Confirm(pending)
        if not pending or pending.confirmed then return pending end
        pending.action.seq=self.serial+1;self.serial=pending.action.seq
        pending.action.time=self:Clock();pending.action.sampled_curtime=CurTime();pending.action.batch=tostring(engine.TickCount())
        local result,gap=self.adjudicator:commit(pending.action)
        if not result then error(gap and gap.reason or "adjudicator capacity")end
        pending.confirmed=true;pending.decisions=result;self.stats.committed=self.stats.committed+1
        self.pending[pending.action.id]=pending
        return pending
    end
    function R:Trace(pending,trace,intended,origin,ricochet)
        if not pending or pending.closed or not trace or not trace.StartPos or not trace.HitPos then return end
        self:Confirm(pending);self.stats.traces=self.stats.traces+1
        if not intended or not origin then return end
        local maxdist=math.max((trace.HitPos-origin):Length(),1)
        local finish=origin+intended:GetNormalized()*maxdist
        local source=pending.source
        if not isplayer(source)then return end
        for life,p in pairs(pending.entities)do
            if isplayer(p)and self:Actor(p).life==life and not pending.traced[life]then
                -- Broad phase is cheap; exact copied hitboxes follow only nearby paths.
                local body=IsValid(p.FakeRagdoll)and p.FakeRagdoll or p
                local lo,hi=body:WorldSpaceAABB()
                local shape={origin={0,0,0},mins=vec(lo),maxs=vec(hi),axes={{1,0,0},{0,1,0},{0,0,1}}}
                if G.segment_box(vec(trace.StartPos),vec(trace.HitPos),shape,24)then
                    local directed,reason=G.directed({committed=true,timeline_valid=true,start=vec(origin),
                        intended_end=vec(finish),actual_start=vec(trace.StartPos),actual_end=vec(trace.HitPos),
                        shapes=self:Shapes(p),ricochet=ricochet==true})
                    if directed then
                        local observations={directed=true,observed_source=self:Visible(p,source),
                            observation_complete=true,witnesses={}}
                        for _,helper in ipairs(player.GetAll())do
                            if helper~=p and helper~=source and self:Visible(helper,source)then
                                local h=self:Actor(helper);local eye=self:View(helper)
                                if h and eye then observations.witnesses[h.life]={visible=true,participating=true,
                                    distance=eye:Distance(source:WorldSpaceCenter())}end
                            end
                        end
                        -- Complete only this physical observation, not missing history.
                        self.adjudicator:observe(pending.action.id,life,observations)
                        pending.traced[life]=true;self.stats.directed=self.stats.directed+1
                    else pending.trace_gap=reason end
                end
            end
        end
    end
    function R:BindDamage(pending,info,target,force_new)
        local p=self:Receiver(target)
        if not pending or pending.closed or not p then return nil end
        local actor=self:Actor(p)
        if not actor or not pending.action.targets[actor.life]then return nil end
        self:Confirm(pending)
        local record=self.damage[info]
        if not force_new and record and record.pending==pending and record.life==actor.life and not record.completed then return record end
        record={id=self:Next("effect"),pending=pending,life=actor.life,target=p,info=info,
            harm=0,scoped=false,completed=false,raw=info:GetDamage(),tick=engine.TickCount(),physical_target=target,
            brain=p.organism and p.organism.brain,org=p.organism,
            health=p.Health and p:Health(),maximum=p.GetMaxHealth and p:GetMaxHealth()}
        self.damage[info]=record;pending.effects[#pending.effects+1]=record
        self.selected[p]=record
        return record
    end
    function R:FindDamage(info,target)
        local p=target and self:Receiver(target)
        local actor=p and self:Actor(p)
        local active=self.effect_stack and self.effect_stack[#self.effect_stack]
        if active and active.info==info and (not actor or active.life==actor.life)then return active end
        local record=self.damage[info]
        if record and (not actor or record.life==actor.life)then return record end
        -- No last-hit/sole-pending fallback: another receiver can reuse this userdata.
        -- Explicit forwarding is bound by WithDamage while that native call is active.
    end
    function R:Contribution(info,harm)
        if not U.finite(harm)or harm<0 then return end
        local active=self.effect_stack and self.effect_stack[#self.effect_stack]
        local record=active and active.info==info and active or self.damage[info]
        if record and not record.completed then
            record.harm=record.harm+harm;record.scoped=true;self.stats.scoped_harm=self.stats.scoped_harm+1
        else self.stats.unscoped_harm=self.stats.unscoped_harm+1 end
    end
    function R:Harm(target,info,group,body,harm)
        local p=self:Receiver(target)or self:Receiver(body);if not p then return end
        local record=self:FindDamage(info,p)
        if not record then
            self.stats.source_unknown=self.stats.source_unknown+1
            self:Summary({reason="ACCEPTED_HARM_WITHOUT_COMMIT_ADAPTER",target=self:Actor(p).account,
                target_life=self:Actor(p).life,harm=U.finite(harm)and harm or 0,proposed_debit=0})
            return
        end
        if record.completed then return end
        if not record.scoped then
            self:Summary({reason="UNSCOPED_NATIVE_HARM",target=self:Actor(p).account,
                target_life=record.life,harm=0,proposed_debit=0});return
        end
        self:Accepted(record,record.harm)
    end
    function R:Accepted(record,harm)
        if record.completed then return end
        local pending=record.pending;local p=record.target
        if not IsValid(p)or self:Actor(p).life~=record.life or record.org~=p.organism then
            record.completed=true;self:Summary({reason="STALE_BODY_EFFECT",harm=0});return
        end
        self.adjudicator:effect(pending.action.id,{id=record.id,target_life=record.life,
            time=self:Clock(),harm=math.max(0,harm),accepted=harm>0,damage=math.max(0,record.raw),
            lethal=not p:Alive(),serious=false})
        record.completed=true;self.stats.effects=self.stats.effects+1
    end
    function R:PostDamage(target,info,took)
        local record=self:FindDamage(info,target)
        if not record or record.completed then return end
        if record.scoped then self:Accepted(record,record.harm)
        elseif took and record.org==nil and U.finite(record.health)and U.finite(record.maximum)
            and record.maximum>0 and record.target.Health then
            local health=record.target:Health()
            if U.finite(health)then
                local loss=math.max(0,record.health-math.max(0,health))
                self:Accepted(record,math.min(10,loss/record.maximum*10))
            end
        elseif took then
            -- Existing organism or creature ledgers require their own normalization.
            self:Summary({reason="HEALTH_ROUTE_NORMALIZATION_PENDING",target_life=record.life,harm=0})
        end
    end
    function R:Finish(pending)
        if not pending or pending.closed or pending.scopes>0 or pending.hold_open then return end
        for projectile in pairs(pending.holds or {})do if not projectile.Removed then return end end
        pending.closed=true
        if self.ClearNativeFrames then self:ClearNativeFrames(pending)end
        if not pending.confirmed then return end
        for _,r in ipairs(pending.effects)do if not r.completed and r.scoped then self:Accepted(r,r.harm)end end
        local decisions=self.adjudicator:finish(pending.action.id)
        for _,d in ipairs(decisions)do self:Summary(d);self.stats.predictions=self.stats.predictions+1 end
        self.adjudicator:archived(pending.action.id)
        self.pending[pending.action.id]=nil
    end
    function R:Summary(d)
        local key=table.concat({d.source or "unknown",d.target_life or "unknown",d.reason or "unknown"},"|")
        local s=self.summary[key]
        if not s then
            if self.summary_count>=512 then self:Flush()end
            s={kind="adjudication_prediction",round=self.observer.round,source=d.source,target=d.target,
                target_life=d.target_life,reason=d.reason,force=d.force,root=d.root,
                events=0,harm=0,proposed_debit=0,first=CurTime(),status=d.status or "UNRESOLVED",
                observation_only=true,context_complete=false}
            self.summary[key]=s;self.summary_count=self.summary_count+1
        end
        s.events=s.events+1;s.harm=s.harm+(d.harm or 0);s.last=CurTime()
        s.proposed_debit=s.proposed_debit+(d.proposed_debit or 0)
    end
    function R:Flush()
        for _,s in pairs(self.summary)do self.observer:Record(s)end
        self.summary={};self.summary_count=0
    end
    function R:Wounds(ent,info,before)
        local p=self:Receiver(ent);if not p or not p.organism then return end
        local r=self:FindDamage(info,p)
        for _,w in pairs(p.organism.wounds or {})do
            local previous=before[w]or 0;local added=math.max(0,(w[1]or 0)-previous)
            if added>0 then
                if self.MedicalWoundAddition then self:MedicalWoundAddition(p,w,previous,added,r)end
                if r then
                    local d=self.adjudicator.actions[r.pending.action.id].decisions[r.life]
                    self.condition_count=(self.condition_count or 0)+1
                    assert(self.condition_count<=C.capacity.conditions,"private condition capacity reached")
                    local id=self.provenance:condition({life=r.life,organism=self.observer:Life(p).generation,
                        action=r.pending.action.id,account=r.pending.action.account,kind="wound",
                        verdict=d and d.reason or "UNRESOLVED"},w)
                    local binding=self.wounds[w]or {};self.wounds[w]=binding
                    binding[#binding+1]={id=id,added=added}
                else
                    -- Preexisting and uncovered manual wound additions stay unknown.
                    self.wounds[w]=self.wounds[w]or {};self.wounds[w][#self.wounds[w]+1]={id="unknown",added=added}
                end
            end
        end
    end
    function R:Death(p,kind)
        local actor=self:Actor(p);if not actor then return end
        self.stats.unknown_terminal=self.stats.unknown_terminal+1
        self:Summary({reason="TERMINAL_CAUSE_ADAPTER_REQUIRED",target=actor.account,
            target_life=actor.life,harm=0})
        -- No largest-contributor guess, no suicide-request shortcut, no money.
    end
    function R:WriteStatus()
        local samples={};for _,n in pairs(self.telemetry)do samples[#samples+1]=n*1000 end;table.sort(samples)
        local status={version=self.version,enabled=self.enabled,enforcement=false,
            stats=self.stats,coverage=self.coverage,error=self.last_error,time=os.time(),
            public_writes=0,financial_writes=0,p95_callback_ms=samples[math.max(1,math.ceil(#samples*.95))]or 0,
            p99_callback_ms=samples[math.max(1,math.ceil(#samples*.99))]or 0,
            max_callback_ms=self.maximum_ms or 0,live_players=#player.GetAll(),maximum_players=game.MaxPlayers(),
            awaiting={full_source_coverage=true,real_multiplayer_validation=true,staff_review=true,single_writer_cutover=true}}
        file.CreateDir(DATA);file.Write(DATA.."/integration_status.json",util.TableToJSON(status,true))
    end
    function R:Tick()
        local list={};for _,p in pairs(self.pending)do if p.scopes==0 and p.action.time<self:Clock()then list[#list+1]=p end end
        table.sort(list,function(a,b)return a.action.seq<b.action.seq end)
        for _,p in ipairs(list)do self:Finish(p)end
        local now=self:Clock()
        if now>=(self.next_flush or 0)then self.next_flush=now+5;self:Flush()end
        if now>=(self.next_status or 0)then
            self.next_status=now+15
            for _,w in ipairs(self.wrappers)do
                if w.table[w.key]~=w.wrapper then self:Issue("ownership_changed",w.label);return end
            end
            self:WriteStatus()
        end
        if now>=(self.next_prune or 0)then self.next_prune=now+5;self.adjudicator:prune_resolved(now)end
    end
    function R:Scope(pending,fn,...)
        if not pending or not self.enabled then return fn(...)end
        pending.scopes=pending.scopes+1;self.scope[#self.scope+1]=pending
        local out=pack(pcall(fn,...))
        if self.scope[#self.scope]~=pending then
            self:Issue("source_scope","context mismatch; observer disabled")
        end
        self.scope[#self.scope]=nil;pending.scopes=pending.scopes-1
        self:Safe(self.Finish,pending)
        if not out[1]then error(out[2],0)end
        return unpack(out,2,out.n)
    end
    function R:Wrap(tbl,key,label,factory)
        local original=tbl and tbl[key]
        if type(original)~="function"then self.coverage[label]="function_unavailable";return false end
        local wrapper=factory(original)
        tbl[key]=wrapper;self.wrappers[#self.wrappers+1]={table=tbl,key=key,original=original,wrapper=wrapper,label=label}
        self.coverage[label]="connected_observer_only"
        return true
    end
    function R:Add(event,suffix,fn,priority)
        local name="ZCJusticeV3Integration_"..suffix
        local wrapper=function(...)self:Safe(fn,...);end
        hook.Add(event,name,wrapper,priority or 2)
        self.hooks[#self.hooks+1]={event=event,name=name,fn=wrapper}
    end
    function R:Stop()
        if not self.enabled and self.stopped then return end
        self.enabled=false;self.stopped=true
        for i=#self.wrappers,1,-1 do local w=self.wrappers[i]
            if w.table[w.key]==w.wrapper then w.table[w.key]=w.original end
        end
        for _,h in ipairs(self.hooks)do if (hook.GetTable()[h.event]or {})[h.name]==h.fn then hook.Remove(h.event,h.name)end end
        pcall(function()self:Flush();self.observer:Flush();self:WriteStatus()end)
    end
    function R:Install()
        local selfref=self;local ent=FindMetaTable("Entity")
        local function bullet_factory(route)
            return function(original)
                return function(entity,data,...)
                    if not selfref.enabled or type(data)~="table"then return original(entity,data,...)end
                    local parent=selfref.scope[#selfref.scope]
                    local source=data.Attacker
                    if not isplayer(source)then source=entity.GetOwner and entity:GetOwner()end
                    if not isplayer(source)then source=entity end
                    -- Only an explicitly opened discharge group may own multiple pellets.
                    if not parent or not parent.discharge_group or parent.source~=source then parent=nil end
                    local pending=parent or selfref:Safe(selfref.Prepare,source,"firearm",route)
                    if not pending then return original(entity,data,...)end
                    local old=data.Callback;local origin=data.Src;local intended=data.Dir
                    pending.raw_descriptor={Src=origin,Dir=intended,ricochet=(data.limit_ricochet or 0)>0}
                    local callback=function(attacker,trace,info,...)
                        selfref:Safe(selfref.Trace,pending,trace,intended,origin,(data.limit_ricochet or 0)>0)
                        selfref:Safe(selfref.BindDamage,pending,info,trace.Entity)
                        if old then return old(attacker,trace,info,...)end
                    end
                    data.Callback=callback;selfref.prepared[data]=pending
                    local args=pack(...)
                    local result=pack(pcall(function()
                        return selfref:Scope(pending,original,entity,data,unpacked(args))
                    end))
                    if data.Callback==callback then data.Callback=old end
                    selfref.prepared[data]=nil
                    if not result[1]then error(result[2],0)end
                    return unpack(result,2,result.n)
                end
            end
        end
        local weaponbase=weapons and weapons.GetStored and weapons.GetStored("homigrad_base")
        if weaponbase then self:Wrap(weaponbase,"FireBullet","discharge_group",function(original)
            return function(weapon,...)
                if not selfref.enabled then return original(weapon,...)end
                local pending=selfref:Safe(selfref.Prepare,weapon:GetOwner(),"firearm","weapon_discharge")
                if pending then pending.discharge_group=true end
                return selfref:Scope(pending,original,weapon,...)
            end
        end)end
        self:Wrap(ent,"FireLuaBullets","custom_hitscan",bullet_factory("custom_hitscan"))
        self:Wrap(ent,"FireBullets","native_hitscan",bullet_factory("native_hitscan"))
        self:Add("PostEntityFireBullets","Trace",function(s,entity,data)
            local p=s.scope[#s.scope]
            if p and type(data)=="table"and data.Trace then
                -- Misses do not invoke Callback. Use the actual trace supplied here.
                local raw=p.raw_descriptor
                if raw then s:Trace(p,data.Trace,raw.Dir,raw.Src,raw.ricochet)end
            end
        end,-2)
        self:Wrap(hg,"AddHarmToAttacker","scoped_harm",function(original)
            return function(info,harm,...)
                selfref:Safe(selfref.Contribution,info,harm)
                return original(info,harm,...)
            end
        end)
        self:Wrap(hg and hg.organism,"AddWound","private_wounds",function(original)
            return function(entity,trace,bone,info,...)
                local before=selfref:Safe(function(s)
                    local saved={}
                    if not IsValid(entity)then return saved end
                    for _,w in pairs(entity.organism and entity.organism.wounds or {})do saved[w]=w[1]end
                    return saved
                end)
                local out=pack(pcall(original,entity,trace,bone,info,...))
                if before and out[1]then selfref:Safe(selfref.Wounds,entity,info,before)end
                if not out[1]then error(out[2],0)end
                return unpack(out,2,out.n)
            end
        end)
        self:Add("HomigradDamage","Accepted",R.Harm,2)
        self:Add("PostEntityTakeDamage","HealthFinal",R.PostDamage,2)
        self:Add("PlayerDeath","Death",function(s,p)s:Death(p,"normal")end,2)
        self:Add("PlayerSilentDeath","SilentDeath",function(s,p)s:Death(p,"silent")end,2)
        self:Add("Think","Drain",R.Tick,2)
        self:Add("PlayerDisconnected","Disconnect",function(s,p)
            local actor=s:Actor(p)
            if actor then for id,root in pairs(s.adjudicator.roots)do
                if root.source==actor.life or root.victim==actor.life then
                    s.adjudicator:closure(id,math.max(s:Clock(),root.last),"life_end",true)
                end
            end end
        end,2)
        self:Add("ZB_EndRound","End",function(s)s:Flush();s:WriteStatus()end,2)
        self:Add("ShutDown","Save",function(s)s:Stop()end,2)
        if self.InstallEffects then self:InstallEffects()end
        if self.InstallPhysical then self:InstallPhysical()end
        if self.InstallControls then self:InstallControls()end
        if self.InstallTerminals then self:InstallTerminals()end
        if self.InstallMedical then self:InstallMedical()end
        self:WriteStatus()
    end
    return R
end
