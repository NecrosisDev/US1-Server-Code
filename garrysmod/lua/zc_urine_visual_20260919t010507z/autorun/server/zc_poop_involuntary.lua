-- Involuntary pooping from ZCity death/spinal-control loss.
if not SERVER then return end
local I=ZCityPoopInvoluntary or {}
ZCityPoopInvoluntary=I
I.Version="20260918.h1"
I.Interval=0.2
I.RetryInterval=0.2
I.RetryCount=10
I.states=I.states or setmetatable({},{__mode="k"})
I.stats=I.stats or {death=0,paralysis=0,spawn_fail=0,errors=0}
I.logged=I.logged or {}
local function accountID(p)
    return p:IsBot() and ("bot:"..p:UserID()) or p:SteamID64()
end
local function finite(n)
    return type(n)=="number" and n==n and math.abs(n)<math.huge
end
local function validPlayer(p)
    return IsValid(p) and p:IsPlayer()
end
function I.Error(tag,err)
    I.stats.errors=I.stats.errors+1
    if I.logged[tag]then return end
    I.logged[tag]=true
    file.CreateDir("zc_poop")
    file.Append("zc_poop/involuntary_errors.txt",
        os.date("!%Y-%m-%dT%H:%M:%SZ").." "..tag.." "..tostring(err):sub(1,1000).."\n")
end
function I.Body(p,C)
    if C and type(C.Body)=="function"then
        local ok,b=pcall(C.Body,p)
        if ok and IsValid(b)then return b end
    end
    if IsValid(p.FakeRagdoll)then return p.FakeRagdoll end
    if type(p.GetRagdollEntity)=="function"then
        local b=p:GetRagdollEntity()
        if IsValid(b)then return b end
    end
    if hg and type(hg.GetCurrentCharacter)=="function"then
        local ok,b=pcall(hg.GetCurrentCharacter,p)
        if ok and IsValid(b)then return b end
    end
    return IsValid(p) and p or nil
end
function I.Paralyzed(org)
    local H=hg and hg.organism
    if type(org)~="table" or not H then return false end
    local s1=finite(org.spine1) and org.spine1 or 0
    local s2=finite(org.spine2) and org.spine2 or 0
    local s3=finite(org.spine3) and org.spine3 or 0
    return s1>=(H.fake_spine1 or 1)
        or s2>=(H.fake_spine2 or 1)
        or s3>=(H.fake_spine3 or 0.5)
end
function I.Condition(p,reason)
    if not validPlayer(p)then return false end
    local org=p.organism
    if reason=="paralysis"then return I.Paralyzed(org) end
    if reason=="death"then
        return not p:Alive() or (type(org)=="table" and org.alive==false)
    end
    return false
end
function I.Spawn(p,reason)
    local C=ZCityPoop
    if not C or type(C.DropPosition)~="function" or type(C.owned)~="table"then
        return false,"poop_system"
    end
    if not validPlayer(p)then return false,"player" end
    local id=accountID(p)
    if type(id)~="string" or id=="" or id=="0"then return false,"identity" end
    local body=I.Body(p,C)
    if not IsValid(body)then return false,"body" end
    if not file.Exists(C.Model,"GAME") or not util.IsValidProp(C.Model)then
        return false,"assets"
    end
    local pos,ang=C.DropPosition(p,body)
    if not pos then return false,"ground" end
    local ent=ents.Create("prop_physics")
    if not IsValid(ent)then return false,"entity_limit" end
    C.owned[ent]=true
    ent.DoNotDuplicate=true
    ent.PhysgunDisabled=true
    ent.ZCityCosmeticPoop=true
    ent.ZCityInvoluntaryPoop=reason
    ent.ZCityPoopOwner=id
    local ok,err=pcall(function()
        ent:SetModel(C.Model)
        ent:SetModelScale(C.Scale or 1,0)
        ent:SetPos(pos)
        ent:SetAngles(ang)
        ent:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
        ent:Spawn()
        ent:Activate()
        ent:SetNoDraw(false)
        ent:SetNW2Bool("zc_poop",true)
        assert(IsValid(ent),"poop prop removed during spawn")
        ent:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
        local phys=ent:GetPhysicsObject()
        assert(IsValid(phys),"poop has no physics object")
        phys:AddGameFlag(FVPHYSICS_NO_IMPACT_DMG)
        phys:SetMass(1)
        phys:Wake()
    end)
    if not ok then
        if IsValid(ent)then ent:Remove()end
        C.owned[ent]=nil
        return false,err
    end
    local account=C.accounts[id] or {poops={},next=0}
    C.accounts[id]=account
    account.player=p
    local live={}
    for _,old in ipairs(account.poops or {})do
        if IsValid(old)then live[#live+1]=old end
    end
    while #live>=C.Limit do
        local old=table.remove(live,1)
        if IsValid(old)then old:Remove()end
    end
    live[#live+1]=ent
    account.poops=live
    -- Deliberately do not touch account.next: involuntary events do not consume manual cooldown.
    if file.Exists("sound/"..C.Sound,"GAME")then
        pcall(body.EmitSound,body,C.Sound,65,95,0.7,CHAN_AUTO)
    end
    timer.Simple(2,function()
        if type(C.Settle)=="function" then
            local ok,err=pcall(C.Settle,ent)
            if not ok then I.Error("settle",err) end
        end
    end)
    I.stats[reason]=(I.stats[reason] or 0)+1
    return true,ent
end
function I.State(p)
    local org=p.organism
    local s=I.states[p]
    if not s or s.org~=org then
        s={org=org,pending={},deathFired=false,paralysisFired=false,paralyzed=false}
        I.states[p]=s
    end
    return s
end
function I.Trigger(p,reason)
    if not validPlayer(p)then return end
    local s=I.State(p)
    local flag=reason=="death" and "deathFired" or "paralysisFired"
    s.failed=s.failed or {}
    if s[flag] or s.failed[reason] or s.pending[reason]then return end
    local token={}
    s.pending[reason]=token
    local tries=0
    local function attempt()
        if not validPlayer(p) or I.states[p]~=s or p.organism~=s.org
            or s.pending[reason]~=token then
            if s.pending[reason]==token then s.pending[reason]=nil end
            return
        end
        if not I.Condition(p,reason)then
            s.pending[reason]=nil
            return
        end
        tries=tries+1
        local ok,spawned,why=pcall(I.Spawn,p,reason)
        if not ok then
            s.pending[reason]=nil
            s.failed[reason]=true
            I.Error("spawn_"..reason,spawned)
            return
        end
        if spawned then
            s[flag]=true
            s.pending[reason]=nil
            return
        end
        if tries>=I.RetryCount then
            s.failed[reason]=true
            s.pending[reason]=nil
            I.stats.spawn_fail=I.stats.spawn_fail+1
            return
        end
        timer.Simple(I.RetryInterval,attempt)
    end
    attempt()
end
function I.Tick()
    for _,p in ipairs(player.GetAll())do
        if validPlayer(p)then
            local org=p.organism
            if type(org)=="table"then
                local s=I.State(p)
                local par=I.Paralyzed(org)
                if par and not s.paralyzed then
                    s.paralyzed=true
                    s.paralysisFired=false
                    I.Trigger(p,"paralysis")
                elseif not par and s.paralyzed then
                    s.paralyzed=false
                    s.paralysisFired=false
                    s.pending.paralysis=nil
                    if s.failed then s.failed.paralysis=nil end
                end
                if org.alive==false and not s.deathFired then
                    I.Trigger(p,"death")
                end
            end
        end
    end
end
I.Timer=function()
    local ok,err=pcall(I.Tick)
    if not ok then I.Error("tick",err)end
end
timer.Create("ZCityPoop_Involuntary",I.Interval,0,I.Timer)
hook.Add("PlayerDeath","ZCityPoop_InvoluntaryDeath",function(p)
    timer.Simple(0,function()
        if validPlayer(p)then I.Trigger(p,"death")end
    end)
end)
hook.Add("PlayerSpawn","ZCityPoop_InvoluntaryReset",function(p)
    I.states[p]=nil
end)
hook.Add("PlayerDisconnected","ZCityPoop_InvoluntaryReset",function(p)
    I.states[p]=nil
end)
function I.ResetAll()
    I.states=setmetatable({},{__mode="k"})
    -- Existing dead/paralyzed bodies are not new events after round cleanup.
    for _,p in ipairs(player.GetAll()) do
        if validPlayer(p) then
            local s=I.State(p)
            s.deathFired=I.Condition(p,"death")
            s.paralyzed=I.Paralyzed(p.organism)
            s.paralysisFired=s.paralyzed
        end
    end
end
hook.Add("ZB_EndRound","ZCityPoop_InvoluntaryResetAll",I.ResetAll)
hook.Add("PostCleanupMap","ZCityPoop_InvoluntaryResetAll",I.ResetAll)
