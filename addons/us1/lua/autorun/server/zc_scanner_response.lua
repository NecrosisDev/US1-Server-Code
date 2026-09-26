-- City Scanner destruction response. Server only; no changes to karma or existing damage hooks.
if not SERVER then return end
ZCityScannerResponse=ZCityScannerResponse or {}
local S=ZCityScannerResponse
S.Version="20260915.2"
S.GraphReader=include("zc_scanner_response/graph.lua")
S.pending=S.pending or {};S.responders=S.responders or {};S.serial=S.serial or 0
S.seen=S.seen or setmetatable({},{__mode="k"})
S.wrapped=S.wrapped or setmetatable({},{__mode="k"})
S.stats=S.stats or {queued=0,spawned=0,skipped=0}
include("zc_scanner_response/escalation.lua")
S.Settings={minDistance=512,maxDistance=3000,anchorDistance=1600,pairDistance=600,
    delay=1,timeout=15,maxPending=8,maxActive=12,lifetime=180,batch=6}
local enabled=CreateConVar("zc_scanner_response","1",FCVAR_ARCHIVE,"Two hidden Metropolice respond to City Scanner destruction on AI-node maps",0,1)
local cap=CreateConVar("zc_scanner_response_max_npcs","12",FCVAR_ARCHIVE,"Maximum living scanner-response NPCs across both response stages",2,32)
local mins,maxs=Vector(-18,-18,0),Vector(18,18,76)
local samples={Vector(0,0,6),Vector(0,0,40),Vector(0,0,72),Vector(17,0,40),Vector(-17,0,40),Vector(0,17,40),Vector(0,-17,40)}
function S.Round()return game.GetMap()..":"..tostring(zb and zb.ROUND_START)end
function S.Active()
    return enabled:GetBool() and not S.cleaning and (not zb or zb.ROUND_STATE==1)
        and not (GetConVar("ai_disabled") and GetConVar("ai_disabled"):GetBool())
end
function S.Graph()
    local count=ai.GetNodeCount and ai.GetNodeCount() or 0
    local key=game.GetMap()..":"..count
    if S.graphKey~=key or (not S.graph and CurTime()>=(S.graphRetry or 0)) then
        S.graphKey=key;S.graph,S.graphReason=S.GraphReader.Load();S.graphRetry=CurTime()+30
    end
    return S.graph
end
function S.Views()
    local views={}
    local function add(ent)
        if not IsValid(ent) then return end
        local pos=ent:EyePos()
        for _,v in ipairs(views)do if v:DistToSqr(pos)<16 then return end end
        views[#views+1]=pos
    end
    for _,p in ipairs(player.GetHumans())do
        add(p);add(p:GetViewEntity());add(p:GetObserverTarget())
        for _,key in ipairs({"spect","active_mavic","kamikaze_","zc_pill_morph"})do add(p:GetNWEntity(key))end
    end
    return views
end
local function cover(ent)
    -- People/NPCs and temporary ragdolls are not reliable cover for a spawn.
    return not (ent:IsPlayer() or ent:IsNPC() or ent:IsRagdoll())
end
function S.Hidden(pos,views)
    if #views==0 then return false end
    for _,eye in ipairs(views)do
        if eye:DistToSqr(pos)<S.Settings.minDistance^2 then return false end
        for _,offset in ipairs(samples)do
            local tr=util.TraceLine({start=eye,endpos=pos+offset,mask=MASK_VISIBLE_AND_NPCS,filter=cover})
            if not tr.Hit or tr.Fraction>0.995 or tr.StartSolid then return false end
        end
    end
    return true
end
function S.Ground(node)
    local tr=util.TraceHull({start=node.pos+Vector(0,0,48),endpos=node.pos-Vector(0,0,128),
        mins=mins,maxs=maxs,mask=MASK_NPCSOLID})
    if not tr.Hit or tr.HitSky or tr.StartSolid or tr.AllSolid or tr.HitNormal.z<0.7 then return end
    local pos=tr.HitPos+Vector(0,0,2)
    if not util.IsInWorld(pos+Vector(0,0,72)) then return end
    if bit.band(util.PointContents(pos+Vector(0,0,32)),CONTENTS_WATER+CONTENTS_SLIME)~=0 then return end
    local clear=util.TraceHull({start=pos,endpos=pos,mins=mins,maxs=maxs,mask=MASK_NPCSOLID})
    if clear.Hit or clear.StartSolid or clear.AllSolid then return end
    return pos
end
function S.Anchor(graph,origin)
    local best,distance=nil,S.Settings.anchorDistance^2
    for _,id in ipairs(graph.ground)do
        local node=graph.nodes[id];local d=node.pos:DistToSqr(origin)
        if d<distance then best=id;distance=d end
    end
    return best
end
function S.Candidates(graph,anchor,origin)
    local list={};local component=graph.nodes[anchor].component
    for _,id in ipairs(graph.ground)do
        local node=graph.nodes[id];local d=node.pos:DistToSqr(origin)
        if node.component==component and d>=S.Settings.minDistance^2 and d<=S.Settings.maxDistance^2 then
            list[#list+1]={id=id,score=math.abs(d-1200^2)}
        end
    end
    table.sort(list,function(a,b)return a.score<b.score end)
    return list
end
function S.Count()
    local count=0
    for npc in pairs(S.responders)do
        if not IsValid(npc) or npc:Health()<=0 then S.responders[npc]=nil else count=count+1 end
    end
    return count
end
function S.Notify(ent,kind)
    if not IsValid(ent) or S.seen[ent] then return false end
    if kind=="npc" then
        if ent:GetClass()~="npc_cscanner" then return false end
    elseif kind=="pill" then
        if not ent.GetPillForm or ent:GetPillForm()~="cityscanner" then return false end
    else return false end
    S.seen[ent]=true
    return S.Enqueue(ent:GetPos(),kind,1)
end
function S.Enqueue(origin,kind,stage,parent)
    if not S.Active() or not S.Rosters[stage] or #S.pending>=S.Settings.maxPending then return false end
    local graph=S.Graph();if not graph then return false end
    local anchor=S.Anchor(graph,origin);if not anchor then return false end
    local candidates=S.Candidates(graph,anchor,origin);if #candidates<1 then return false end
    S.serial=S.serial+1
    local job={id=S.serial,kind=kind,origin=Vector(origin),graph=graph,anchor=anchor,
        candidates=candidates,cursor=1,round=S.Round(),ready=CurTime()+S.Settings.delay,
        expires=CurTime()+S.Settings.timeout,stage=stage,parent=parent}
    S.pending[#S.pending+1]=job;S.stats.queued=S.stats.queued+1
    return true
end
function S.OnKilled(npc)
    if S.ResponseKilled(npc) then return end
    S.Notify(npc,"npc")
end
hook.Add("OnNPCKilled","ZCityScannerResponse_Death",S.OnKilled,-2)
function S.WrapForm(form)
    if not istable(form) then return end
    local old=S.wrapped[form]
    if old and form.die==old.wrapper then return end
    local before=form.die
    local wrapper=function(ply,ent,...)
        S.Notify(ent,"pill")
        if isfunction(before) then return before(ply,ent,...) end
    end
    S.wrapped[form]={wrapper=wrapper,previous=before};form.die=wrapper
end
function S.InstallPill()
    if not pk_pills or not isfunction(pk_pills.getPillTable) then return false end
    local form=pk_pills.getPillTable("cityscanner");if not form then return false end
    S.WrapForm(form)
    for _,ent in ipairs(ents.FindByClass("pill_ent_phys"))do
        if ent.GetPillForm and ent:GetPillForm()=="cityscanner" then S.WrapForm(ent.formTable) end
    end
    return true
end
function S.SpawnSquad(job,positions,views)
    local stage=job.stage or 1;local roster=S.Rosters[stage]
    if not roster or #positions~=#roster or S.Count()+#roster>cap:GetInt()
        or not S.Active() or job.round~=S.Round() or S.Graph()~=job.graph then return false end
    for i,pos in ipairs(positions)do
        if not S.Hidden(pos,views) then return false end
        for j=1,i-1 do
            local d=pos:DistToSqr(positions[j])
            if d<64^2 or d>S.Settings.pairDistance^2 then return false end
        end
    end
    local made={};local goal=job.graph.nodes[job.anchor].pos
    local ok,problem=pcall(function()
        for i,pos in ipairs(positions)do
            local spec=roster[i];local npc=ents.Create(spec.class);assert(IsValid(npc),"npc_creation_failed")
            made[#made+1]=npc;npc.ZCScannerResponse=true;npc.ZCScannerStage=stage;npc.ZCScannerRole=spec.role
            npc:SetNoDraw(true);npc:SetPos(pos);npc:SetAngles(Angle(0,(goal-pos):Angle().y,0))
            if spec.model then npc:SetModel(spec.model) end
            npc:SetKeyValue("additionalequipment",spec.weapon)
            npc:SetKeyValue("squadname","zc_scanner_response_"..job.id)
            npc:Spawn();npc:Activate();npc:SetNoDraw(true)
            if spec.skin then npc:SetSkin(spec.skin) end
            if npc:Health()<=0 then npc:SetHealth(spec.health);npc:SetMaxHealth(spec.health) end
            assert(npc:GetPos():DistToSqr(pos)<64 and npc:Health()>0,"invalid_spawn")
            assert(IsValid(npc:GetActiveWeapon()),"missing_weapon")
            assert(npc:NavSetGoalPos(goal),"unreachable_scene")
        end
    end)
    local function rollback()
        for _,npc in ipairs(made)do if IsValid(npc)then npc:Remove()end end
    end
    if not ok then S.lastFailure=tostring(problem);rollback();return false end
    local currentViews=S.Views()
    for _,pos in ipairs(positions)do if not S.Hidden(pos,currentViews)then rollback();return false end end
    -- Publish the whole squad only after all clearance, view and route checks pass.
    S.TrackPatrol(job,made)
    for _,npc in ipairs(made)do
        npc:SetNoDraw(false);npc:SetNPCState(NPC_STATE_ALERT)
        if stage==2 then npc:Fire("StartPatrolling","",0) end
        npc:SetLastPosition(goal);npc:SetSchedule(SCHED_FORCED_GO_RUN)
        S.responders[npc]=CurTime()+S.Settings.lifetime
    end
    S.stats.spawned=S.stats.spawned+#made
    S.lastSpawn={time=os.time(),map=game.GetMap(),round=job.round,kind=job.kind,stage=stage,
        origin=job.origin,positions=positions,id=job.id,parent=job.parent}
    file.CreateDir("zc_scanner_response")
    file.Append("zc_scanner_response/"..os.date("%Y%m%d")..".txt",util.TableToJSON(S.lastSpawn).."\n")
    return true
end
function S.SpawnPair(job,first,second,views)
    if (job.stage or 1)~=1 then return false end
    return S.SpawnSquad(job,{first,second},views)
end

function S.Positions(job,node,views)
    local roster=S.Rosters[job.stage or 1];if not roster then return end
    local positions={}
    local function add(n)
        local p=S.Ground(n);if not p then return false end
        local d=p:DistToSqr(job.origin)
        if d<S.Settings.minDistance^2 or d>S.Settings.maxDistance^2 or not S.Hidden(p,views)then return false end
        for _,q in ipairs(positions)do
            local apart=q:DistToSqr(p)
            if apart<64^2 or apart>S.Settings.pairDistance^2 then return false end
        end
        positions[#positions+1]=p;return #positions==#roster
    end
    add(node);if #positions==0 then return end
    for index,id in ipairs(node.links)do
        if index>8 then break end
        if add(job.graph.nodes[id]) then return positions end
    end
    for _,v in ipairs({Vector(96,0,0),Vector(-96,0,0),Vector(0,96,0),Vector(0,-96,0),
        Vector(96,96,0),Vector(-96,-96,0),Vector(96,-96,0),Vector(-96,96,0)})do
        if add({pos=positions[1]+v}) then return positions end
    end
end
function S.Try(job,views)
    for _=1,S.Settings.batch do
        local candidate=job.candidates[job.cursor]
        if not candidate then job.cursor=1;job.ready=CurTime()+1;return false end
        job.cursor=job.cursor+1
        local positions=S.Positions(job,job.graph.nodes[candidate.id],views)
        if positions then return S.SpawnSquad(job,positions,views) end
    end
    return false
end

function S.Service()
    local now=CurTime();local views
    if not S.Active() then S.pending={};return end
    for npc,expiry in pairs(S.responders)do
        if not IsValid(npc) or npc:Health()<=0 then S.responders[npc]=nil
        elseif expiry<=now then
            views=views or S.Views()
            if #views==0 or S.Hidden(npc:GetPos(),views) then npc:Remove();S.responders[npc]=nil end
        end
    end
    for i=#S.pending,1,-1 do
        local job=S.pending[i]
        if job.expires<now or job.round~=S.Round() then
            table.remove(S.pending,i);S.stats.skipped=S.stats.skipped+1
        end
    end
    if S.Count()+2>cap:GetInt() then return end
    for i,job in ipairs(S.pending)do
        if job.ready<=now and S.Count()+#(S.Rosters[job.stage or 1] or {})<=cap:GetInt() then
            views=views or S.Views()
            local done=#views>0 and S.Try(job,views)
            table.remove(S.pending,i)
            if not done then S.pending[#S.pending+1]=job end
            break -- One bounded search slice per timer tick, not per death.
        end
    end
end
function S.Reset()
    S.pending={}
    for _,group in pairs(S.patrols)do S.CancelPatrol(group) end
    S.patrols={};S.memberPatrol={}
    for npc in pairs(S.responders)do if IsValid(npc)then npc:Remove()end end
    S.responders={}
end
hook.Add("PreCleanupMap","ZCityScannerResponse_Reset",function()S.cleaning=true;S.Reset()end)
hook.Add("PostCleanupMap","ZCityScannerResponse_Reset",function()S.cleaning=false;S.graph=nil;S.graphRetry=0 end)
hook.Add("ZB_EndRound","ZCityScannerResponse_Reset",S.Reset)
hook.Add("ZB_PreRoundStart","ZCityScannerResponse_Reset",S.Reset)
hook.Add("InitPostEntity","ZCityScannerResponse_Install",function()S.InstallPill()end)
hook.Add("OnReloaded","ZCityScannerResponse_Install",function()S.InstallPill()end)
timer.Create("ZCityScannerResponse_Install",2,0,S.InstallPill)
timer.Create("ZCityScannerResponse_Service",0.25,0,S.Service)
concommand.Add("zc_scanner_response_status",function(p)
    if IsValid(p) and not p:IsAdmin() then return end
    local graph=S.Graph()
    print("[ScannerResponse]",S.Version,"enabled",enabled:GetBool(),"map",game.GetMap(),
        "nodes",graph and graph.count or 0,"ground",graph and #graph.ground or 0,
        "reason",S.graphReason or "ready","pending",#S.pending,"active",S.Count())
end, nil, "Admin: print City Scanner response status.")
S.InstallPill()

S.legacyAdopted=S.AdoptLegacyPair()
