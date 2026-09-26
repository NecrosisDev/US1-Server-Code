-- NON-ENFORCING capture runtime. Does not wrap or replace gameplay functions.
-- No net messages, chat, physics, RNG, balance writes, SQL writes or injury changes.
return function(B)
    local U,C=B.U,B.C
    local S={};S.__index=S
    local PREFIX="ZCJusticeV3Shadow_"
    local DATA="zc_justice_v3_shadow"
    local function is_player(p)return IsValid(p) and p:IsPlayer()end
    local function account(p)
        if not is_player(p)then return nil end
        if p:IsBot() then return "bot:"..p:UserID()end
        local id=p:SteamID64();if type(id)=="string" and id:match("^%d+$") then return id end
    end
    local function origin(fn)
        if type(fn)~="function"then return "missing"end
        local x=debug.getinfo(fn,"S");return (x.short_src or "unknown")..":"..(x.linedefined or 0)
    end
    function S.new()
        -- Namespace has no random draw and remains distinct across script reloads.
        local stamp=tostring(os.time())..":"..string.format("%.0f",SysTime()*1000000)
        return setmetatable({version=C.version,session=stamp,enabled=true,hooks={},sequence=0,
            queue={},head=1,tail=0,summary={},summary_count=0,ring={},ring_cursor=0,
            lives=setmetatable({},{__mode="k"}),life_serial=0,
            dedup=setmetatable({},{__mode="k"}),last_capture_tick=-1,
            stats={captured=0,processed=0,scored_events=0,protected_events=0,
                legacy_guilty_target=0,legacy_retaliation=0,unknown_source=0,
                control_transitions=0,unresolved_context=0,overflow=0,errors=0,
                rounds_observed=0,fully_qualified_rounds=0,staff_reviewed=0,
                cpu_total=0,cpu_max=0,cpu_n=0},profile={},
            round=nil,round_partial=true,log_pending={},log_bytes=0,
            next_flush=CurTime()+5,next_status=CurTime()+15,
            controls=setmetatable({},{__mode="k"}),coverage={
                native_harm="capture_only_shared_accumulator",native_bullets="pellet_trace_capture_only",
                custom_ballistics="source_adapter_pending",observed_threats="source_adapter_pending",
                direct_controls="transition_capture_only",medical_provenance="source_adapter_pending",
                terminal_causes="category_adapter_pending",pill_lifecycle="observation_only",
                source_phase="not_enforcing",account_ledger="tested_library_not_live_writer"}},S)
    end
    function S:Error(code,detail)
        self.stats.errors=self.stats.errors+1
        self.last_error={code=code,detail=tostring(detail):sub(1,400),time=os.time()}
        -- Stop only this observer. Never return a failure into game damage processing.
        self.enabled=false
        -- Best effort: paused observers no longer enter the normal status tick.
        pcall(function()self:WriteStatus()end)
        if not self.warned then self.warned=true;ErrorNoHalt("[JusticeV3 shadow] Observer paused; see DATA status. Existing karma is unchanged.\n")end
    end
    function S:NextId(kind)
        self.sequence=self.sequence+1;return "s:"..self.session..":"..kind..":"..self.sequence
    end
    function S:Mode()
        local mode=type(CurrentRound)=="function" and CurrentRound() or nil
        if type(mode)~="table" then return {name="unknown",scored=false,hidden=false,kind=nil}end
        local chain,seen={},{};local m=mode
        for _=1,12 do
            if type(m)~="table" or seen[m]then break end
            seen[m]=true;chain[#chain+1]=tostring(m.name or "unknown")
            m=zb and zb.modes and zb.modes[m.base]
        end
        local dev=GetConVar("zb_dev")
        return B.Modes.compile({name=tostring(mode.name or "unknown"),variant=zb and tostring(zb.CROUND or "unknown"),
            chain=chain,guilt_disabled=mode.GuiltDisabled==true,developer=dev and dev:GetBool() or false,
            has_subroles=type(mode.SubRoles)=="table",custom_rule_complete=false})
    end
    function S:RoundKey(mode)
        return game.GetMap()..":"..tostring(zb and zb.ROUND_START or "none")..":"..tostring(mode.name)
    end
    function S:CheckRound(mode)
        local key=self:RoundKey(mode)
        if self.round~=key then
            if self.round then self:EndRound("signature_change")end
            self.round=key;self.round_partial=true;self.mode=mode
            self.lives=setmetatable({},{__mode="k"});self.controls=setmetatable({},{__mode="k"})
            self:Record({kind="round_observed",round=key,mode=mode.name,variant=mode.variant,
                scored=mode.scored,hidden=mode.hidden,partial=true})
        end
        return key
    end
    function S:Life(p)
        if not is_player(p)then return nil end
        local life=self.lives[p]
        local org=p.organism
        local morph=ZCityPillCompat and ZCityPillCompat.states and ZCityPillCompat.states[p]
        morph=morph and morph.morph
        local body=IsValid(morph) and morph or IsValid(p.FakeRagdoll) and p.FakeRagdoll or p
        if not life then
            self.life_serial=self.life_serial+1
            life={id="l:"..self.session..":"..self.life_serial,account=account(p),organism=org,
                body=body,generation=1,partial=true,state="OBSERVED"}
            self.lives[p]=life
        elseif life.body~=body or life.organism~=org then
            life.generation=life.generation+1;life.body=body;life.organism=org
        end
        return life
    end
    function S:ResolveReceiver(ent,body)
        if is_player(ent)then return ent end
        if not IsValid(ent)and IsValid(body)then ent=body end
        if not IsValid(ent)then return nil end
        if hg and type(hg.RagdollOwner)=="function"then
            local p=hg.RagdollOwner(ent)
            if is_player(p)and (p.FakeRagdoll==ent or p.RagdollDeath==ent)then return p end
        end
        if ZCityPillCompat and type(ZCityPillCompat.Body)=="function"then
            local _,p=ZCityPillCompat.Body(ent);if is_player(p)then return p end
        end
    end
    function S:Actor(p)
        if not is_player(p)then return nil end
        local l=self:Life(p);if not l or not l.account then return nil end
        local excluded=ZC_POSTMORTEM_KARMA and ZC_POSTMORTEM_KARMA.players and ZC_POSTMORTEM_KARMA.players[p]~=nil
        return {account=l.account,life=l.id,generation=l.generation,traitor=p.isTraitor==true,
            team=p:Team(),karma=U.finite(p.Karma) and U.clamp(p.Karma,-60,120)or 100,
            exempt=excluded==true,admin=p:IsAdmin()or p:IsSuperAdmin(),bot=p:IsBot(),partial=l.partial}
    end
    function S:Enqueue(row)
        if self.tail-self.head+1>=C.capacity.queue then
            self.stats.overflow=self.stats.overflow+1
            self:Error("capture_capacity","bounded capture queue full")
            return
        end
        self.tail=self.tail+1;self.queue[self.tail]=row;self.stats.captured=self.stats.captured+1
    end
    function S:Harm(v,info,hitgroup,body,harm)
        if not U.finite(harm)or harm<0 or not info then return end
        local p=self:ResolveReceiver(v,body);if not p then return end
        local mode=self:Mode();local round=self:CheckRound(mode)
        local target=self:Actor(p);if not target or target.team>=1000 then return end
        local raw=info:GetDamage();if not U.finite(raw)or raw<=0 then return end
        local a=info:GetAttacker();local source=self:Actor(a)
        local tick=engine.TickCount()
        if self.last_capture_tick~=tick then self.last_capture_tick=tick;self.dedup=setmetatable({},{__mode="k"})end
        local seen=self.dedup[info]
        if not seen then seen={};self.dedup[info]=seen end
        local duplicate=seen[target.life]==true;seen[target.life]=true
        local inf=info:GetInflictor();local class=IsValid(inf)and inf:GetClass()or "unknown"
        local legacy="unavailable";local legacy_scale=nil
        local j=ZCityGuiltJustice
        local remembered=j and j.latest and j.latest[p]
        if remembered and remembered.tick==tick and remembered.attacker==a and remembered.policy then
            legacy=tostring(remembered.policy.reason or "unknown");legacy_scale=remembered.policy.scale
        end
        local relation=source and B.Modes.relation(mode,source,target)or "unsupported"
        local row={kind="harm",id=self:NextId("h"),time=CurTime(),tick=tick,round=round,
            mode=mode.name,variant=mode.variant,scored=mode.scored and zb and zb.ROUND_STATE==1 or false,
            hidden=mode.hidden,source=source and source.account,source_life=source and source.life,
            target=target.account,target_life=target.life,generation=target.generation,
            harm=harm,damage=raw,damage_type=info:GetDamageType(),inflictor=class,
            relation=relation,legacy_reason=legacy,legacy_scale=legacy_scale,possible_duplicate=duplicate,
            source_admin=source and source.admin or false,
            verdict="UNRESOLVED_CONTEXT",coverage="native_harm_without_complete_threat_history"}
        if not source then row.verdict="UNKNOWN_SOURCE"end
        if not row.scored then row.verdict="CONFIGURED_UNSCORED"end
        if source and source.account==target.account then row.verdict="SELF"end
        if relation=="enemy"then row.verdict="ORDINARY_ENEMY"end
        -- Estimates are explicitly hypothetical, never a proposed conviction.
        self:Enqueue(row)
    end
    function S:NativeBullet(ent,data)
        -- PostEntityFireBullets is per pellet, not per discharge. Record coverage only.
        self.native_pellets=(self.native_pellets or 0)+1
        if type(data)~="table" or type(data.Trace)~="table"then return end
        local trace=data.Trace
        local source=self:Actor(ent)
        self.last_native_trace={tick=engine.TickCount(),source=source and source.account,
            entity=IsValid(trace.Entity)and trace.Entity:GetClass()or "world",observed_only=true}
        -- No callback replacement, extra trace, second rewind or fabricated injury.
    end
    function S:Spawn(p)
        if not is_player(p)then return end
        local spawning=ZCityPillCompat and ZCityPillCompat.spawning and ZCityPillCompat.spawning[p]
        local morph=ZCityPillCompat and ZCityPillCompat.states and ZCityPillCompat.states[p]
        if OverrideSpawn or morph then
            local l=self:Life(p);if l then l.generation=l.generation+1 end
            return
        end
        self.lives[p]=nil;local l=self:Life(p)
        if l then l.state=spawning and "PROVISIONAL"or "SPAWN_OBSERVED";l.partial=true end
        -- Until explicit source adapters validate commit/rollback, this is observation only.
    end
    function S:Death(p,kind)
        if not is_player(p)then return end
        local l=self:Life(p);if not l or l.death_recorded then return end
        l.death_recorded=true
        local spawning=ZCityPillCompat and ZCityPillCompat.spawning and ZCityPillCompat.spawning[p]
        self:Enqueue({kind="terminal_observation",id=self:NextId("d"),time=CurTime(),
            round=self.round,target=l.account,target_life=l.id,callback=kind,
            verdict=spawning and "PROVISIONAL_ROLLBACK_POSSIBLE"or "UNRESOLVED_TERMINAL_CATEGORY",
            source="unknown",coverage="explicit_terminal_adapter_pending"})
    end
    function S:ControlScan()
        if not self.enabled then return end
        for _,p in ipairs(player.GetAll())do
            if is_player(p)and p:Alive()and p:Team()<1000 then
                local org=p.organism;local rag=p.FakeRagdoll
                local strangler=IsValid(rag)and rag.StrangleLocked==true and rag.Strangler or nil
                local source=is_player(strangler)and account(strangler)or nil
                local state=(source and "wire:"..source or "")..":"..
                    tostring(org and org.handcuffed==true)..":"..tostring(org and U.finite(org.tasered)and org.tasered>CurTime()or false)
                local old=self.controls[p]
                if state~=old then
                    self.controls[p]=state
                    local l=self:Life(p)
                    if l and (old~=nil or source or (org and org.handcuffed) or (org and U.finite(org.tasered) and org.tasered>CurTime()))then
                        self.stats.control_transitions=self.stats.control_transitions+1
                        self:Enqueue({kind="control_observation",id=self:NextId("c"),time=CurTime(),round=self.round,
                            target=l.account,target_life=l.id,source=source,state=state,
                            verdict="UNRESOLVED_CONTROL_CONTEXT",coverage="state_transition_not_committed_action"})
                    end
                end
            end
        end
    end
    function S:Record(record)
        record.version=self.version;record.session=self.session;record.observation_only=true
        local text=util.TableToJSON(record,false)
        if not text then error("shadow serialization failed")end
        if self.log_bytes+#text+1>C.capacity.log_bytes then error("shadow log buffer full")end
        self.log_pending[#self.log_pending+1]=text.."\n";self.log_bytes=self.log_bytes+#text+1
    end
    function S:Process(row)
        self.stats.processed=self.stats.processed+1
        if row.kind=="harm"then
            if row.scored then self.stats.scored_events=self.stats.scored_events+1 end
            if row.relation=="protected"then self.stats.protected_events=self.stats.protected_events+1 end
            if row.legacy_reason=="guilty_target"then self.stats.legacy_guilty_target=self.stats.legacy_guilty_target+1 end
            if row.legacy_reason=="native_retaliation"then self.stats.legacy_retaliation=self.stats.legacy_retaliation+1 end
            if row.verdict=="UNKNOWN_SOURCE"then self.stats.unknown_source=self.stats.unknown_source+1 end
            if row.verdict=="UNRESOLVED_CONTEXT"then self.stats.unresolved_context=self.stats.unresolved_context+1 end
            local key=table.concat({row.round or "?",row.source or "unknown",row.target_life,
                row.inflictor,row.legacy_reason,row.verdict,row.possible_duplicate and "duplicate"or "single"},"|")
            local group=self.summary[key]
            if not group then
                if self.summary_count>=512 then self:FlushSummaries()end
                group={kind="harm_summary",round=row.round,mode=row.mode,variant=row.variant,scored=row.scored,
                    source=row.source,target=row.target,target_life=row.target_life,inflictor=row.inflictor,
                    verdict=row.verdict,legacy_reason=row.legacy_reason,legacy_scale=row.legacy_scale,
                    possible_duplicate=row.possible_duplicate,source_admin=row.source_admin,
                    first_id=row.id,last_id=row.id,first_time=row.time,last_time=row.time,harm=0,events=0}
                self.summary[key]=group;self.summary_count=self.summary_count+1
            end
            group.last_id=row.id;group.last_time=row.time;group.events=group.events+1;group.harm=group.harm+row.harm
        else self:Record(row)end
        self.ring_cursor=(self.ring_cursor%C.capacity.ring)+1;self.ring[self.ring_cursor]=row
    end
    function S:FlushSummaries()
        for _,key in ipairs(U.keys(self.summary))do self:Record(self.summary[key])end
        self.summary={};self.summary_count=0
    end
    function S:Flush()
        self:FlushSummaries();if #self.log_pending==0 then return end
        file.CreateDir(DATA)
        local path=DATA.."/"..os.date("%Y%m%d")..".txt"
        local previous=file.Size(path,"DATA");if not previous or previous<0 then previous=0 end
        local text=table.concat(self.log_pending)
        file.Append(path,text)
        local actual=file.Size(path,"DATA")
        if actual~=previous+#text then error("shadow log append size check failed")end
        self.log_pending={};self.log_bytes=0
    end
    function S:Status()
        local times={};for _,v in ipairs(self.profile)do times[#times+1]=v end;table.sort(times)
        local function quantile(p)return #times>0 and times[math.max(1,math.ceil(#times*p))]*1000 or 0 end
        return {version=self.version,session=self.session,enabled=self.enabled,enforcement=false,
            financial_writes=0,public_messages=0,gameplay_hooks_replaced=0,
            round=self.round,stats=U.copy(self.stats),coverage=U.copy(self.coverage),
            queue=self.tail-self.head+1,pending_log_bytes=self.log_bytes,
            drain_sample_p95_ms=quantile(0.95),drain_sample_p99_ms=quantile(0.99),
            max_observer_callback_ms=self.stats.cpu_max*1000,error=self.last_error,
            max_players=game.MaxPlayers(),tick_interval=engine.TickInterval(),
            gates={qualified_rounds=0,required_rounds=C.gates.rounds,staff_reviewed=0,required_reviews=C.gates.reviewed,
                complete_source_coverage=false,automatic_cutover=false},time=os.time()}
    end
    function S:WriteStatus()
        file.CreateDir(DATA)
        file.Write(DATA.."/status.json",assert(util.TableToJSON(self:Status(),true)))
    end
    function S:EndRound(reason)
        if not self.round or self.ended_round==self.round then return end
        self.ended_round=self.round
        self.stats.rounds_observed=self.stats.rounds_observed+1
        self:Record({kind="round_boundary",round=self.round,reason=reason,full_coverage=false})
    end
    function S:Tick()
        local start=SysTime();local worked=0
        while self.head<=self.tail and worked<C.capacity.events_per_tick do
            local row=self.queue[self.head];self.queue[self.head]=nil;self.head=self.head+1
            self:Process(row);worked=worked+1
        end
        if self.head>self.tail then self.queue={};self.head=1;self.tail=0 end
        local elapsed=SysTime()-start
        self.stats.cpu_total=self.stats.cpu_total+elapsed;self.stats.cpu_n=self.stats.cpu_n+1
        self.stats.cpu_max=math.max(self.stats.cpu_max,elapsed)
        self.profile[(self.stats.cpu_n%512)+1]=elapsed
        if CurTime()>=self.next_flush then self.next_flush=CurTime()+5;self:Flush()end
        if CurTime()>=self.next_status then self.next_status=CurTime()+15;self:WriteStatus()end
    end
    function S:Add(event,suffix,fn)
        local name=PREFIX..suffix
        local wrapper=function(...)
            if not self.enabled then return end
            local start=SysTime();local ok,err=pcall(fn,...)
            local elapsed=SysTime()-start
            self.stats.cpu_total=self.stats.cpu_total+elapsed
            self.stats.cpu_max=math.max(self.stats.cpu_max,elapsed)
            if not ok then self:Error(event,err)end
            -- Always nil. In particular, do NOT return pcall/handler status.
        end
        hook.Add(event,name,wrapper,2)
        self.hooks[#self.hooks+1]={event=event,name=name,fn=wrapper}
    end
    function S:Stop()
        self.enabled=false
        for _,h in ipairs(self.hooks)do
            local current=(hook.GetTable()[h.event]or {})[h.name]
            if current==h.fn then hook.Remove(h.event,h.name)end
        end
        timer.Remove(PREFIX.."Controls")
        local ok,err=pcall(function()self:Flush();self:WriteStatus()end)
        if not ok then self.last_error={code="stop_flush",detail=tostring(err)}end
    end
    function S:Install()
        self:Add("HomigradDamage","Harm",function(...)self:Harm(...)end)
        self:Add("PostEntityFireBullets","NativePellet",function(...)self:NativeBullet(...)end)
        self:Add("PlayerSpawn","Spawn",function(p)self:Spawn(p)end)
        self:Add("PlayerDeath","Death",function(p)self:Death(p,"PlayerDeath")end)
        self:Add("PlayerSilentDeath","SilentDeath",function(p)self:Death(p,"PlayerSilentDeath")end)
        self:Add("ZB_StartRound","RoundStart",function()
            local mode=self:Mode();self:CheckRound(mode);self.round_partial=false
        end)
        self:Add("ZB_EndRound","RoundEnd",function()self:EndRound("ZB_EndRound")end)
        self:Add("PlayerDisconnected","Disconnected",function(p)
            self.controls[p]=nil;self.lives[p]=nil
        end)
        self:Add("Think","Drain",function()self:Tick()end)
        self:Add("ShutDown","Shutdown",function()self:Flush();self:WriteStatus()end)
        timer.Create(PREFIX.."Controls",0.5,0,function()
            if not self.enabled then return end
            local ok,err=pcall(function()self:ControlScan()end)
            if not ok then self:Error("controls",err)end
        end)
        concommand.Add("zcj3_shadow_status",function(p)
            if IsValid(p)then return end -- No role-sensitive metrics to playing staff.
            self:WriteStatus();print("[JusticeV3 shadow]",self.version,"enabled",self.enabled,
                "captured",self.stats.captured,"processed",self.stats.processed,"enforcement",false)
        end, nil, "Server console: print Justice v3 shadow capture status.")
        concommand.Add("zcj3_shadow_stop",function(p)
            if IsValid(p)then return end
            self:Stop();print("[JusticeV3 shadow] stopped; legacy gameplay unchanged")
        end, nil, "Server console: stop Justice v3 shadow capture.")
        local entity=FindMetaTable("Entity")
        self:Record({kind="observer_started",coverage=self.coverage,
            origins={native_guilt=origin((hook.GetTable().HomigradDamage or {}).GuiltReg),
                custom_bullets=origin(entity and entity.FireLuaBullets)},
            backend=mysql and mysql.module or "unknown",max_players=game.MaxPlayers(),tick_interval=engine.TickInterval()})
        self:WriteStatus()
    end
    return S
end
