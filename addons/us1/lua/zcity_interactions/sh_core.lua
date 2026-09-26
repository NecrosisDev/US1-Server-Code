-- Shared contract; native damage, inventory and physiology keep their owners.
ZCityInteractions=ZCityInteractions or {}
local I=ZCityInteractions
I.Version="20260920.interactions3"
if SERVER then AddCSLuaFile("zcity_interactions/sh_weapons.lua") AddCSLuaFile("zcity_interactions/sh_policy.lua") AddCSLuaFile("zcity_interactions/cl_context.lua") end
include("zcity_interactions/sh_weapons.lua")
include("zcity_interactions/sh_policy.lua")
if SERVER then AddCSLuaFile("zcity_interactions/sh_scale.lua") end
include("zcity_interactions/sh_scale.lua")
function I.Cuffed(p)
    if hg and hg.IsHandcuffed then return hg.IsHandcuffed(p) end
    return IsValid(p) and ((p.organism and p.organism.handcuffed) or p:GetNetVar("handcuffed",false)) or false
end
function I.HandsAvailable(p)
    local o=IsValid(p) and p.organism
    return o and not I.Cuffed(p) and not o.larmamputated and not o.rarmamputated
        and (o.larm or 0)<.99 and (o.rarm or 0)<.99
end
function I.RoundAllowsHostility()
    if zb and zb.ROUND_STATE~=nil and zb.ROUND_STATE~=1 then return false,"Wait for the round to start" end
    if GetGlobalFloat and GetGlobalFloat("RS_GraceUntil",0)>CurTime() then return false,"Round-start protection is active" end
    return true
end
if SERVER then AddCSLuaFile("zcity_interactions/cl_quick.lua") end
if CLIENT then include("zcity_interactions/cl_context.lua") include("zcity_interactions/cl_quick.lua") return I end
I.Reservations=I.Reservations or setmetatable({}, {__mode="k"})
I.Recovery=I.Recovery or setmetatable({}, {__mode="k"})
I.Collisions=I.Collisions or {}
I.CollisionOwners=I.CollisionOwners or {}
I.CollisionPairs=I.CollisionPairs or {}
function I.Session(p)
    local s=I.Reservations[p]
    if s and not s.done then return s end
    -- Bridges cover admission during migration and native-owner adapters.
    local g=ZCityHostage and ZCityHostage.Gameplay
    local h=g and g.ByPlayer and g.ByPlayer[p]
    if h and not h.done then return h end
    local f=ZCityStealth and ZCityStealth.ByActor and ZCityStealth.ByActor[p]
    if f and not f.done then return f end
end
function I.Available(p,own)
    local s=I.Session(p)
    if s and s~=own then return false,"Already in an interaction" end
    return true
end
function I.Reserve(s,actors,predecessor)
    for _,p in ipairs(actors) do
        if not IsValid(p) then return false end
        local owner=I.Session(p)
        if owner and owner~=s and owner~=predecessor then return false end
    end
    s.reserved=s.reserved or {}
    for _,p in ipairs(actors) do I.Reservations[p]=s s.reserved[p]=true end
    return true
end
function I.Release(s)
    for p in pairs(s.reserved or {}) do
        if I.Reservations[p]==s then I.Reservations[p]=nil end
    end
    s.reserved=nil
end
function I.Receiver(p)
    if not IsValid(p) then return end
    if p:IsPlayer() then return p end
    return hg and hg.RagdollOwner and hg.RagdollOwner(p) or p
end
function I.Protect(p,seconds)
    p=I.Receiver(p)
    if IsValid(p) then I.Recovery[p]=math.max(I.Recovery[p] or 0,CurTime()+(seconds or 2)) end
end
function I.HostileAllowed(a,v,session,intent)
    local ok,why=I.RoundAllowsHostility()
    if not ok then return false,why end
    ok,why=I.Available(a,session)
    if not ok then return false,why end
    local receiver=I.Receiver(v)
    if receiver and (I.Recovery[receiver] or 0)>CurTime() and not session then
        return false,"Give the released player space"
    end
    return I.PolicyAllowed(a,intent or (session and session.policyIntent) or "hold",v)
end
function I.CanVoluntaryRagdoll(p)
    local s=I.Session(p)
    if not s then return true end
    if s.system=="inventory" then return false end
    if (s.v==p or s.originalVictim==p) and s.phase~="attempt" then return false end
    -- The initiator can abandon control; voluntary collapse cannot erase harm.
    if s.cancel then s.cancel(s,"Interaction released") return true end
    return false
end
function I.CanLoot(p,target,own)
    if not IsValid(p) or not p:IsPlayer() or not p:Alive() or not IsValid(target) then return false end
    local o=p.organism
    if not o or o.otrub or I.Cuffed(p) or not I.Available(p,own) then return false end
    local left=not o.larmamputated and (o.larm or 0)<.99
    local right=not o.rarmamputated and (o.rarm or 0)<.99
    if not left and not right then return false end
    if IsValid(p.FakeRagdoll) and not I.Available(p.FakeRagdoll,own) then return false end
    local actual=IsValid(target.FakeRagdoll) and target.FakeRagdoll or target
    if not I.Available(target,own) or not I.Available(actual,own) then return false end
    local viewer=IsValid(p.FakeRagdoll) and p.FakeRagdoll or p
    if viewer:GetPos():DistToSqr(actual:GetPos())>125*125 then return false end
    local eye=hg and hg.eye and hg.eye(p) or p:EyePos()
    local tr=util.TraceLine({start=eye,endpos=actual:WorldSpaceCenter(),filter={p,viewer},mask=MASK_SOLID})
    if tr.Hit and tr.Entity~=actual and tr.Entity~=target then return false end
    local first,_,allowed=hook.Run("ZB_CanLootInventory",p,target)
    return first~=false and allowed~=false
end
local function bounds(p)
    if p:IsPlayer() then
        local lo,hi=p:GetHull() local scale=p:GetModelScale() local pos=p:GetPos()
        return pos+lo*scale,pos+hi*scale
    end
    return p:WorldSpaceAABB()
end
local function overlap(a,b)
    if not IsValid(a) or not IsValid(b) then return false end
    if (a:IsPlayer() and not a:Alive()) or (b:IsPlayer() and not b:Alive()) then return false end
    local lo,hi=bounds(a) local otherLo,otherHi=bounds(b)
    return lo.x<otherHi.x and hi.x>otherLo.x and lo.y<otherHi.y and hi.y>otherLo.y and lo.z<otherHi.z and hi.z>otherLo.z
end
local function pair(a,b,s,add)
    if add then
        I.CollisionPairs[a]=I.CollisionPairs[a] or {}
        I.CollisionPairs[a][b]=I.CollisionPairs[a][b] or {}
        I.CollisionPairs[a][b][s]=true
    else
        local list=I.CollisionPairs[a] local tokens=list and list[b]
        if tokens then tokens[s]=nil if not next(tokens) then list[b]=nil end end
        if list and not next(list) then I.CollisionPairs[a]=nil end
    end
end
function I.AcquireCollision(s,actors,a,b)
    if not IsValid(a) or not IsValid(b) or a==b then return end
    local state=I.Collisions[s] or {actors={},pairs={}}
    I.Collisions[s]=state state.ended=false
    local found=false
    for _,p in ipairs(state.pairs) do if p[1]==a and p[2]==b then found=true break end end
    if not found then state.pairs[#state.pairs+1]={a,b} end
    -- Establish the complete predicate before invalidating any entity rules.
    pair(a,b,s,true) pair(b,a,s,true)
    for _,p in ipairs(actors) do
        state.actors[p]=true
        local lease=I.CollisionOwners[p]
        if not lease then lease={original=p:GetCustomCollisionCheck(),sessions={}} I.CollisionOwners[p]=lease end
        lease.sessions[s]=true p:SetCustomCollisionCheck(true) p:CollisionRulesChanged()
    end
end
local function finishCollision(s)
    local state=I.Collisions[s]
    if not state then return end
    for _,p in ipairs(state.pairs) do pair(p[1],p[2],s,false) pair(p[2],p[1],s,false) end
    I.Collisions[s]=nil
    for p in pairs(state.actors) do
        local lease=I.CollisionOwners[p]
        if lease then
            lease.sessions[s]=nil
            if not next(lease.sessions) then
                if IsValid(p) then p:SetCustomCollisionCheck(lease.original) end
                I.CollisionOwners[p]=nil
            end
            if IsValid(p) then p:CollisionRulesChanged() end
        end
    end
end
function I.ReleaseCollision(s,force)
    local state=I.Collisions[s]
    if not state then return end
    state.ended=true
    if not force then
        for _,p in ipairs(state.pairs) do if overlap(p[1],p[2]) then return end end
    end
    finishCollision(s)
end
hook.Add("ShouldCollide","ZCityInteractions.Pair",function(a,b)
    if I.CollisionPairs[a] and I.CollisionPairs[a][b] then return false end
end)
hook.Add("Think","ZCityInteractions.Separation",function()
    for s,state in pairs(I.Collisions) do if state.ended then I.ReleaseCollision(s) end end
end)
for _,event in ipairs({"PlayerSpawn","PlayerDisconnected"}) do
    hook.Add(event,"ZCityInteractions.Life",function(p) if event=="PlayerSpawn" and OverrideSpawn then return end I.Recovery[p]=nil end)
end
for _,event in ipairs({"PreCleanupMap","ShutDown"}) do
    hook.Add(event,"ZCityInteractions.CollisionCleanup",function()
        local all={} for s in pairs(I.Collisions) do all[#all+1]=s end
        for _,s in ipairs(all) do finishCollision(s) end
    end)
end
include("zcity_interactions/sv_policy.lua")
include("zcity_interactions/sv_native.lua")
include("zcity_interactions/sv_observation.lua")
include("zcity_interactions/sv_roles.lua")
include("zcity_interactions/sv_context.lua")
include("zcity_interactions/sv_quick.lua")
return I
